//
//  AppleRealtimeService.swift
//  SpeechToType
//
//  Real-time / streaming transcription using Apple's on-device speech recognition
//  (SFSpeechRecognizer + AVAudioEngine). No third-party framework required.
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
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            guard status == .authorized else {
                onError(OpenAIError.apiError(String(localized: "appleSpeechNotAuthorized")))
                return
            }
            do {
                try self.beginSession(onPartial: onPartial, onError: onError)
            } catch {
                onError(error)
            }
        }
    }

    private func beginSession(
        onPartial: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw OpenAIError.speechRecognitionUnavailable
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer on-device recognition (matches the "Apple Speech (on-device)" provider).
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Apple delivers cumulative hypotheses (the full text so far), so every result —
        // partial or final — is reported as the current text via onPartial. The caller
        // inserts the latest text once recording stops.
        self.task = recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                onPartial(result.bestTranscription.formattedString)
            }
            if let error = error {
                onError(error)
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        recognizer = nil
    }
}
