//
//  GeminiRealtimeService.swift
//  SpeechToType
//
//  Real-time / streaming transcription via the Gemini Live API with
//  `gemini-3.5-transcribe-live`. That model exists only on the Live API — there is no unary
//  `interactions` call for it — so selecting it in the model picker is what switches the app
//  to the live path (see `AppDelegate.realtimeTranscriber(for:)`).
//
//  Microphone audio is captured with AVAudioEngine, converted to PCM16 mono 16 kHz and sent
//  base64-encoded over a WebSocket. The server answers with `interimInputTranscription`
//  (speculative, replaces the interim) and `inputTranscription` (finalized per speech
//  segment, appends).
//
//  VAD strategy is the "hybrid" one from Google's guide: server-side automatic VAD stays on
//  (it pads the start of speech, which keeps the first word intact for push-to-talk), and
//  `stop()` sends `audioStreamEnd` so the last turn is finalized immediately instead of
//  waiting out the server's silence timer.
//
//  One instance per dictation: every session owns a socket and its own drain state.
//

import Foundation
import AVFoundation

final class GeminiRealtimeService: RealtimeTranscriber {

    // MARK: - Tunables

    /// The Live API expects raw 16-bit PCM at this rate.
    private static let sampleRate: Double = 16_000

    /// Upper bound for how long `stop()` blocks waiting for the trailing final transcript.
    /// If it expires nothing is lost — `LiveTypingSession.fullText()` falls back to the last
    /// interim, only the final formatting pass is missing.
    private static let finalTimeout: TimeInterval = 2.5

    /// ~5 s of 16 kHz PCM16 held while the setup handshake is still in flight.
    private static let maxPendingChunks = 60

    private static let endpoint =
        "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    // MARK: - Callbacks

    private var onPartial: ((String) -> Void)?
    private var onFinal: ((String) -> Void)?
    private var onErrorHandler: ((Error) -> Void)?

    // MARK: - Networking

    private var apiKey = ""
    private var setupPayload: [String: Any] = [:]
    private var urlSession: URLSession?

    // MARK: - Audio

    private let audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    // MARK: - Shared state (everything below is guarded by `lock`)

    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var socketReady = false             // `setupComplete` received
    private var pendingAudio: [String] = []     // base64 chunks queued pre-handshake
    private var didCaptureAudio = false
    private var isStopping = false
    private var callbacksDisabled = false
    private var finalSemaphore: DispatchSemaphore?
    private var didSignalFinal = false

    // MARK: - RealtimeTranscriber

    func start(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onPartial = onPartial
        self.onFinal = onFinal
        self.onErrorHandler = onError

        let settings = AppSettings.shared
        let key = settings.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            emitError(OpenAIError.invalidAPIKey)
            return
        }
        apiKey = key
        // Snapshot the settings once so a change mid-dictation can't half-apply.
        setupPayload = Self.setupMessage(from: settings)

        connect()

        do {
            try startAudio()
        } catch {
            emitError(error)
        }
    }

    func stop() {
        lock.lock()
        if isStopping {
            lock.unlock()
            return
        }
        isStopping = true
        let socketAlive = task != nil && !callbacksDisabled
        let needsStreamEnd = didCaptureAudio && socketAlive
        let semaphore = DispatchSemaphore(value: 0)
        finalSemaphore = semaphore
        // `didSignalFinal` is pre-set by emitError(), so the error path never blocks here.
        let mustWait = !didSignalFinal && needsStreamEnd
        if !mustWait { didSignalFinal = true }
        lock.unlock()

        stopAudio()

        if needsStreamEnd {
            // Finalize the open turn now instead of waiting out the server's silence timer.
            send(["realtimeInput": ["audioStreamEnd": true]])
        }

        if mustWait {
            _ = semaphore.wait(timeout: .now() + Self.finalTimeout)
        }

        lock.lock()
        callbacksDisabled = true    // no late overlay churn after we return
        let socket = task
        task = nil
        let session = urlSession
        urlSession = nil
        lock.unlock()

        socket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        converter = nil
        targetFormat = nil
    }

    // MARK: - Session configuration

    private static func setupMessage(from settings: AppSettings) -> [String: Any] {
        var transcription: [String: Any] = [
            // An empty list is the documented way to ask for automatic language detection.
            "languageCodes": settings.geminiSpeechLanguage.apiCode.map { [$0] } ?? [],
            "mode": settings.geminiTranscriptionMode.liveValue
        ]
        // Dictionary words bias recognition. The free-text instructions have no channel here
        // — the transcribe model takes no prompt.
        let vocabulary = settings.geminiCustomVocabulary
        if !vocabulary.isEmpty {
            transcription["customVocabulary"] = vocabulary
        }

        return [
            "setup": [
                "model": "models/\(GeminiSpeechModel.transcribeLive.rawValue)",
                "generationConfig": ["responseModalities": ["TEXT"]],
                "inputAudioTranscription": transcription
            ]
        ]
    }

    // MARK: - WebSocket

    private func connect() {
        // The Live API authenticates the WebSocket handshake through the `key` query
        // parameter; there is no header form for the upgrade request.
        guard let escapedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "\(Self.endpoint)?key=\(escapedKey)") else {
            emitError(RealtimeError.startFailed("Live endpoint unavailable"))
            return
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        let socket = session.webSocketTask(with: url)

        lock.lock()
        socketReady = false
        urlSession = session
        task = socket
        lock.unlock()

        socket.resume()
        // WebSocket frames are delivered in order, so `setup` always reaches the server
        // first; audio is still queued until `setupComplete` confirms the config was taken.
        send(setupPayload)
        receiveNext()
    }

    private func receiveNext() {
        guard let socket = currentTask() else { return }
        socket.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.handleSocketFailure(error)
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handle(raw: text)
                case .data(let data):
                    // The Live API answers with JSON in binary frames.
                    self.handle(raw: String(data: data, encoding: .utf8) ?? "")
                @unknown default:
                    break
                }
                self.receiveNext()
            }
        }
    }

    /// Parses one server message. The stream is heterogeneous and gains fields over time, so
    /// unknown messages are ignored by construction rather than failing a decode.
    private func handle(raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if json["setupComplete"] != nil {
            markSocketReady()
            return
        }

        if let error = json["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "Live transcription error"
            lock.lock()
            let stopping = isStopping
            lock.unlock()
            // After `audioStreamEnd` an error just means there is no tail left to wait for.
            if stopping {
                signalFinal()
            } else {
                emitError(RealtimeError.startFailed(message))
            }
            return
        }

        if json["goAway"] != nil {
            // The server is about to close (session limit). Never leave stop() blocking.
            signalFinal()
            return
        }

        guard let content = json["serverContent"] as? [String: Any] else { return }

        lock.lock()
        let muted = callbacksDisabled
        lock.unlock()

        if let interim = (content["interimInputTranscription"] as? [String: Any])?["text"] as? String,
           !interim.isEmpty, !muted {
            // The interim REPLACES the running preview — Gemini sends the whole hypothesis
            // for the current segment, not a delta.
            onPartial?(interim)
        }

        if let final = (content["inputTranscription"] as? [String: Any])?["text"] as? String,
           !final.isEmpty {
            if !muted { onFinal?(final) }
            // The authoritative text for this segment has landed; if we are already
            // shutting down, that is the tail stop() was waiting for.
            signalFinal()
        }

        if content["turnComplete"] as? Bool == true || content["generationComplete"] as? Bool == true {
            signalFinal()
        }
    }

    private func send(_ payload: [String: Any]) {
        guard let socket = currentTask(),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] error in
            if let error { self?.handleSocketFailure(error) }
        }
    }

    private func currentTask() -> URLSessionWebSocketTask? {
        lock.lock()
        defer { lock.unlock() }
        return task
    }

    private func handleSocketFailure(_ error: Error) {
        lock.lock()
        let ignore = isStopping || callbacksDisabled
        lock.unlock()
        // While stopping, a dropped socket only means the tail will never arrive.
        if ignore {
            signalFinal()
            return
        }
        emitError(RealtimeError.startFailed(error.localizedDescription))
    }

    /// Reports the first error only, and pre-arms the drain so a `stop()` issued from the
    /// error callback — which `AppDelegate` does synchronously on this very thread — cannot
    /// deadlock waiting for a message the receive loop can no longer deliver.
    private func emitError(_ error: Error) {
        lock.lock()
        if callbacksDisabled {
            lock.unlock()
            return
        }
        callbacksDisabled = true
        didSignalFinal = true
        let handler = onErrorHandler
        lock.unlock()
        handler?(error)
    }

    /// Unblocks `stop()` once the trailing segment has been delivered.
    private func signalFinal() {
        lock.lock()
        let ready = isStopping && !didSignalFinal
        if ready { didSignalFinal = true }
        let semaphore = finalSemaphore
        lock.unlock()
        if ready { semaphore?.signal() }
    }

    // MARK: - Audio capture

    private func startAudio() throws {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: Self.sampleRate,
                                         channels: 1,
                                         interleaved: true) else {
            throw RealtimeError.startFailed("PCM16 16 kHz format unavailable")
        }
        targetFormat = target

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw RealtimeError.startFailed("No audio input device available")
        }
        converter = AVAudioConverter(from: inputFormat, to: target)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock()
            let stopping = self.isStopping
            self.lock.unlock()
            guard !stopping, let pcm = self.convert(buffer) else { return }
            self.lock.lock()
            self.didCaptureAudio = true
            self.lock.unlock()
            self.sendAudio(pcm.base64EncodedString())
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func stopAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    /// Converts a hardware-format buffer to PCM16 mono 16 kHz and returns the raw sample
    /// bytes. Returns nil if conversion produced no audio.
    private func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter, let targetFormat else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, statusPointer in
            if consumed {
                statusPointer.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPointer.pointee = .haveData
            return buffer
        }

        guard status != .error, output.frameLength > 0,
              let channel = output.int16ChannelData else { return nil }
        return Data(bytes: channel[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }

    /// Queues audio until `setupComplete` lands, so the user's first word survives the
    /// connect + handshake latency.
    private func sendAudio(_ base64: String) {
        lock.lock()
        if !socketReady {
            if pendingAudio.count < Self.maxPendingChunks { pendingAudio.append(base64) }
            lock.unlock()
            return
        }
        lock.unlock()
        sendAudioChunk(base64)
    }

    private func sendAudioChunk(_ base64: String) {
        send([
            "realtimeInput": [
                "audio": [
                    "data": base64,
                    "mimeType": "audio/pcm;rate=\(Int(Self.sampleRate))"
                ]
            ]
        ])
    }

    private func markSocketReady() {
        lock.lock()
        guard !socketReady else {
            lock.unlock()
            return
        }
        socketReady = true
        let queued = pendingAudio
        pendingAudio.removeAll()
        lock.unlock()

        for chunk in queued {
            sendAudioChunk(chunk)
        }
    }
}
