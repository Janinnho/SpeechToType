//
//  AppleRealtimeService.swift
//  SpeechToType
//
//  Real-time / streaming transcription using Apple's on-device speech recognition.
//  Uses the modern SpeechAnalyzer + SpeechTranscriber API (macOS 26), which delivers
//  results phrase-by-phrase: each phrase is reported as volatile (interim) text and then
//  once more as a finalized result. Earlier finalized phrases are never revoked, so pauses
//  no longer overwrite previously dictated text. No third-party framework required.
//

import Foundation
import Speech
import AVFoundation

/// Common interface for live (streaming) transcription engines.
/// Callbacks may be invoked on background threads.
protocol RealtimeTranscriber: AnyObject {
    func start(onPartial: @escaping (String) -> Void,
               onFinal: @escaping (String) -> Void,
               onError: @escaping (Error) -> Void)
    func stop()
}

final class AppleRealtimeService: RealtimeTranscriber {
    static let shared = AppleRealtimeService()
    private init() {}

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var isStopping = false

    func start(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        isStopping = false
        recognizerTask = Task {
            do {
                try await self.beginSession(onPartial: onPartial, onFinal: onFinal, onError: onError)
            } catch {
                if !self.isStopping { onError(error) }
            }
        }
    }

    private func beginSession(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        // Speech recognition authorization.
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else {
            throw OpenAIError.apiError(String(localized: "appleSpeechNotAuthorized"))
        }

        // Resolve a supported locale (fall back to the current one).
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale.current

        // Configure the transcriber for immediate transcription of live audio: volatile
        // (interim) results plus finalized phrases.
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        self.transcriber = transcriber

        // Download/install the on-device assets for this locale if needed.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw OpenAIError.speechRecognitionUnavailable
        }
        self.analyzerFormat = analyzerFormat

        // Build the audio input stream and capture microphone audio into it, converting from
        // the hardware format to the analyzer's required format.
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = continuation

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
        self.converter = converter

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let input = self.convert(buffer) else { return }
            continuation.yield(input)
        }

        audioEngine.prepare()
        try audioEngine.start()

        try await analyzer.start(inputSequence: stream)

        // Consume results: finalized phrases accumulate, volatile phrases are previews.
        for try await result in transcriber.results {
            let text = String(result.text.characters)
            if result.isFinal {
                onFinal(text)
            } else {
                onPartial(text)
            }
        }
    }

    /// Converts a hardware-format audio buffer to the analyzer's format and wraps it as an
    /// `AnalyzerInput`. Returns nil if conversion produced no audio.
    private func convert(_ buffer: AVAudioPCMBuffer) -> AnalyzerInput? {
        guard let converter, let analyzerFormat else { return nil }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else {
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

        guard status != .error, output.frameLength > 0 else { return nil }
        return AnalyzerInput(buffer: output)
    }

    func stop() {
        isStopping = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()
        inputContinuation = nil

        // Finalize any remaining audio so the trailing phrase is emitted, then end the session.
        // The results loop drains and exits on its own; we don't cancel it abruptly.
        let analyzer = self.analyzer
        Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }

        self.analyzer = nil
        self.transcriber = nil
        self.converter = nil
        self.analyzerFormat = nil
        self.recognizerTask = nil
    }
}
