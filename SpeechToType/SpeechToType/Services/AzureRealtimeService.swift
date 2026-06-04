//
//  AzureRealtimeService.swift
//  SpeechToType
//
//  Real-time / streaming transcription via the Microsoft Cognitive Services Speech SDK.
//  Uses Azure's standard streaming speech models (NOT mai-transcribe, which is batch only).
//
//  The whole SDK-dependent code is wrapped in `#if canImport(MicrosoftCognitiveServicesSpeech)`
//  so the project still compiles when the binary xcframework has not been added yet.
//

import Foundation

#if canImport(MicrosoftCognitiveServicesSpeech)
import MicrosoftCognitiveServicesSpeech
#endif

enum RealtimeError: Error, LocalizedError {
    case sdkUnavailable
    case notConfigured
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return String(localized: "azureRealtimeSDKUnavailable")
        case .notConfigured:
            return String(localized: "azureRealtimeNotConfigured")
        case .startFailed(let message):
            return "API-Fehler: \(message)"
        }
    }
}

final class AzureRealtimeService: RealtimeTranscriber {
    static let shared = AzureRealtimeService()
    private init() {}

    /// Whether the Speech SDK is compiled into the build.
    static var isAvailable: Bool {
        #if canImport(MicrosoftCognitiveServicesSpeech)
        return true
        #else
        return false
        #endif
    }

    #if canImport(MicrosoftCognitiveServicesSpeech)
    private var recognizer: SPXSpeechRecognizer?
    private var phraseListGrammar: SPXPhraseListGrammar?
    #endif

    /// Starts continuous recognition. `onPartial` receives the growing interim hypothesis,
    /// `onFinal` each finalized segment. Callbacks may be invoked on background threads.
    func start(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        #if canImport(MicrosoftCognitiveServicesSpeech)
        let settings = AppSettings.shared
        let endpoint = settings.azureFoundryEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = settings.azureFoundryApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !endpoint.isEmpty, !key.isEmpty else {
            onError(RealtimeError.notConfigured)
            return
        }

        do {
            let speechConfig = try SPXSpeechConfiguration(endpoint: endpoint, subscription: key)
            speechConfig.speechRecognitionLanguage = settings.azureRealtimeLanguage

            let audioConfig = SPXAudioConfiguration()
            let reco = try SPXSpeechRecognizer(speechConfiguration: speechConfig, audioConfiguration: audioConfig)

            // Custom vocabulary via phrase list (entity biasing).
            if settings.applyDictionaryToAzure {
                let phrases = settings.dictionaryPhrases
                if !phrases.isEmpty {
                    let grammar = SPXPhraseListGrammar(recognizer: reco)
                    for phrase in phrases {
                        grammar?.addPhrase(phrase)
                    }
                    self.phraseListGrammar = grammar
                }
            }

            reco.addRecognizingEventHandler { _, evt in
                let text = evt.result.text ?? ""
                if !text.isEmpty { onPartial(text) }
            }

            reco.addRecognizedEventHandler { _, evt in
                guard evt.result.reason == SPXResultReason.recognizedSpeech else { return }
                let text = evt.result.text ?? ""
                if !text.isEmpty { onFinal(text) }
            }

            reco.addCanceledEventHandler { _, evt in
                let details = evt.errorDetails ?? "Recognition canceled"
                onError(RealtimeError.startFailed(details))
            }

            self.recognizer = reco
            try reco.startContinuousRecognition()
        } catch {
            self.recognizer = nil
            self.phraseListGrammar = nil
            onError(RealtimeError.startFailed(error.localizedDescription))
        }
        #else
        onError(RealtimeError.sdkUnavailable)
        #endif
    }

    /// Stops continuous recognition and releases the recognizer.
    func stop() {
        #if canImport(MicrosoftCognitiveServicesSpeech)
        try? recognizer?.stopContinuousRecognition()
        recognizer = nil
        phraseListGrammar = nil
        #endif
    }
}
