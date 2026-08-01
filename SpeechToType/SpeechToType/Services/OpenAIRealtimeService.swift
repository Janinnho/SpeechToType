//
//  OpenAIRealtimeService.swift
//  SpeechToType
//
//  Real-time / streaming transcription via OpenAI's Realtime API with `gpt-live-transcribe`.
//  That model is realtime-only — it has no /v1/audio/transcriptions endpoint — so selecting it
//  in the model picker is what switches the app to the live path (see
//  `AppDelegate.realtimeTranscriber(for:)`).
//
//  Microphone audio is captured with AVAudioEngine, converted to PCM16 mono 24 kHz and sent
//  base64-encoded over a WebSocket. The server streams incremental transcript deltas plus a
//  finalized transcript per turn.
//
//  One instance per dictation: every session owns a socket, a delta map and a semaphore, so a
//  fresh instance avoids any stale-state bugs between dictations.
//

import Foundation
import AVFoundation

final class OpenAIRealtimeService: RealtimeTranscriber {

    // MARK: - Tunables

    /// The realtime API expects PCM at this rate.
    private static let sampleRate: Double = 24_000

    /// Upper bound for how long `stop()` blocks waiting for the `completed` event. Without
    /// turn detection this is the only finalized transcript of the whole dictation, so the
    /// window is generous. If it expires nothing is lost — `LiveTypingSession.fullText()`
    /// falls back to the accumulated deltas, only the final formatting pass is missing.
    private static let finalTimeout: TimeInterval = 2.5

    /// ~5 s of 24 kHz PCM16 held while the socket is still connecting.
    private static let maxPendingChunks = 60

    /// The transcription guide shows `?intent=transcription`, the GA realtime guide shows
    /// `?model=`. Try them in order — the first one that completes a handshake wins.
    private static let urlCandidates = [
        "wss://api.openai.com/v1/realtime?intent=transcription",
        "wss://api.openai.com/v1/realtime?model=gpt-live-transcribe"
    ]

    // MARK: - Callbacks

    private var onPartial: ((String) -> Void)?
    private var onFinal: ((String) -> Void)?
    private var onErrorHandler: ((Error) -> Void)?

    // MARK: - Networking

    private var apiKey = ""
    private var sessionPayload: [String: Any] = [:]
    private var urlSession: URLSession?

    // MARK: - Audio

    private let audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    // MARK: - Shared state (everything below is guarded by `lock`)

    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var candidateIndex = 0
    private var socketReady = false             // a server event has been received
    private var pendingAudio: [String] = []     // base64 chunks queued pre-handshake
    private var didCaptureAudio = false
    private var isStopping = false
    private var callbacksDisabled = false
    private var partialByItem: [String: String] = [:]   // item_id → accumulated deltas
    private var openItems = Set<String>()               // item_ids awaiting `completed`
    private var activeItem: String?
    private var awaitingCommitAck = false
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
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            emitError(OpenAIError.invalidAPIKey)
            return
        }
        apiKey = key
        // Snapshot the settings once so a change mid-dictation can't half-apply.
        sessionPayload = Self.sessionUpdatePayload(from: settings)

        connect(candidate: 0)

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
        let needsCommit = didCaptureAudio && socketAlive
        if needsCommit { awaitingCommitAck = true }
        let semaphore = DispatchSemaphore(value: 0)
        finalSemaphore = semaphore
        // `didSignalFinal` is pre-set by emitError(), so the error path never blocks here.
        let mustWait = !didSignalFinal && (needsCommit || !openItems.isEmpty)
        if !mustWait { didSignalFinal = true }
        lock.unlock()

        stopAudio()

        if needsCommit {
            // Force the open VAD turn closed so the trailing words are transcribed.
            send(["type": "input_audio_buffer.commit"])
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

    private static func sessionUpdatePayload(from settings: AppSettings) -> [String: Any] {
        var transcription: [String: Any] = [
            "model": TranscriptionModel.gptLiveTranscribe.rawValue,
            "delay": settings.openAIRealtimeDelay.rawValue
        ]

        // Dictionary: the free-text instructions are the prompt, the words are keywords.
        let instructions = settings.dictionaryInstructionsText
        if !instructions.isEmpty { transcription["prompt"] = instructions }
        let keywords = settings.openAIKeywords
        if !keywords.isEmpty { transcription["keywords"] = keywords }
        if let language = settings.openAISpeechLanguage.apiCode {
            transcription["languages"] = [language]
        }

        return [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": Int(sampleRate)],
                        "transcription": transcription,
                        // Must be null: gpt-live-transcribe rejects any turn detection config
                        // ("Turn detection is not supported for this transcription model").
                        // The model streams deltas from the appended audio on its own; the
                        // single turn is closed by the explicit commit in `stop()`.
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ]
    }

    // MARK: - WebSocket

    private func connect(candidate: Int) {
        guard candidate < Self.urlCandidates.count,
              let url = URL(string: Self.urlCandidates[candidate]) else {
            emitError(RealtimeError.startFailed("Realtime endpoint unavailable"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // No `OpenAI-Beta: realtime=v1` — the GA API expects it to be absent.

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        let socket = session.webSocketTask(with: request)

        lock.lock()
        candidateIndex = candidate
        socketReady = false
        urlSession = session
        task = socket
        lock.unlock()

        socket.resume()
        // WebSocket frames are delivered in order, so the config always reaches the server
        // ahead of the first audio chunk; no need to wait for `session.created`.
        send(sessionPayload)
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
                    self.handle(raw: String(data: data, encoding: .utf8) ?? "")
                @unknown default:
                    break
                }
                self.receiveNext()
            }
        }
    }

    /// Parses one server event. The realtime stream is heterogeneous and gains fields over
    /// time, so unknown events are ignored by construction rather than failing a decode.
    private func handle(raw: String) {
        markSocketReady()   // the first event proves the handshake succeeded

        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {

        case "conversation.item.input_audio_transcription.delta":
            guard let item = json["item_id"] as? String,
                  let delta = json["delta"] as? String, !delta.isEmpty else { return }
            lock.lock()
            let accumulated = (partialByItem[item] ?? "") + delta
            partialByItem[item] = accumulated
            activeItem = item
            openItems.insert(item)
            let muted = callbacksDisabled
            lock.unlock()
            // `delta` is an incremental fragment, but LiveTypingSession.updatePartial REPLACES
            // the interim text — so always hand it the whole running phrase.
            if !muted { onPartial?(accumulated) }

        case "conversation.item.input_audio_transcription.completed":
            guard let item = json["item_id"] as? String else { return }
            let transcript = (json["transcript"] as? String) ?? ""
            lock.lock()
            partialByItem.removeValue(forKey: item)
            openItems.remove(item)
            if activeItem == item { activeItem = nil }
            // commitFinal() clears lastPartial; if a different item is still streaming,
            // re-publish its text so the overlay preview doesn't lose it.
            let stillStreaming = activeItem.flatMap { partialByItem[$0] }
            let muted = callbacksDisabled
            lock.unlock()
            if !muted {
                if !transcript.isEmpty { onFinal?(transcript) }
                if let stillStreaming, !stillStreaming.isEmpty { onPartial?(stillStreaming) }
            }
            signalFinalIfDrained()

        case "conversation.item.input_audio_transcription.failed":
            guard let item = json["item_id"] as? String else { return }
            lock.lock()
            partialByItem.removeValue(forKey: item)
            openItems.remove(item)
            if activeItem == item { activeItem = nil }
            lock.unlock()
            // Never block stop() on a turn that will never complete.
            signalFinalIfDrained()

        case "input_audio_buffer.committed":
            lock.lock()
            awaitingCommitAck = false
            if let item = json["item_id"] as? String { openItems.insert(item) }
            lock.unlock()
            // No signal: a turn was just opened, we now wait for its `completed`.

        case "error":
            let message = ((json["error"] as? [String: Any])?["message"] as? String)
                ?? "Realtime error"
            lock.lock()
            let stopping = isStopping
            awaitingCommitAck = false
            lock.unlock()
            if stopping {
                // A commit on an empty or too-short buffer errors out — that just means the
                // VAD already closed the last turn and there is no tail left to wait for.
                signalFinalIfDrained()
            } else {
                emitError(RealtimeError.startFailed(message))
            }

        default:
            #if DEBUG
            print("[OpenAIRealtime] unhandled event: \(type)")
            #endif
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
        if isStopping || callbacksDisabled {
            lock.unlock()
            return
        }
        // Only fall back while the handshake is still unconfirmed, and only once — the index
        // is advanced under the lock so a simultaneous send+receive failure can't double-fire.
        let next = candidateIndex + 1
        let canFallback = !socketReady && next < Self.urlCandidates.count
        if canFallback {
            candidateIndex = next
            let dead = task
            task = nil
            lock.unlock()
            dead?.cancel(with: .abnormalClosure, reason: nil)
            connect(candidate: next)    // pendingAudio survives → nothing is lost
            return
        }
        lock.unlock()
        emitError(RealtimeError.startFailed(error.localizedDescription))
    }

    /// Reports the first error only, and pre-arms the drain so a `stop()` issued from the
    /// error callback — which `AppDelegate` does synchronously on this very thread — cannot
    /// deadlock waiting for an event the receive loop can no longer deliver.
    private func emitError(_ error: Error) {
        lock.lock()
        if callbacksDisabled {
            lock.unlock()
            return
        }
        callbacksDisabled = true
        didSignalFinal = true
        openItems.removeAll()
        awaitingCommitAck = false
        let handler = onErrorHandler
        lock.unlock()
        handler?(error)
    }

    /// Unblocks `stop()` once the trailing turn has been delivered.
    private func signalFinalIfDrained() {
        lock.lock()
        let ready = isStopping && !awaitingCommitAck && openItems.isEmpty && !didSignalFinal
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
            throw RealtimeError.startFailed("PCM16 24 kHz format unavailable")
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

    /// Converts a hardware-format buffer to PCM16 mono 24 kHz and returns the raw sample
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

    /// Queues audio until the handshake is confirmed, so the user's first word survives both
    /// the normal connect latency and a fallback to the second URL candidate.
    private func sendAudio(_ base64: String) {
        lock.lock()
        if !socketReady {
            if pendingAudio.count < Self.maxPendingChunks { pendingAudio.append(base64) }
            lock.unlock()
            return
        }
        lock.unlock()
        send(["type": "input_audio_buffer.append", "audio": base64])
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
            send(["type": "input_audio_buffer.append", "audio": chunk])
        }
    }
}
