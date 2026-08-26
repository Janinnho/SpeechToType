//
//  OpenAIService.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import Foundation
import Speech
import AVFoundation

enum OpenAIError: Error, LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    case noTranscription
    case speechRecognitionUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Ungültiger API-Key. Bitte überprüfe deine Einstellungen."
        case .networkError(let error):
            return "Netzwerkfehler: \(error.localizedDescription)"
        case .invalidResponse:
            return "Ungültige Antwort vom Server."
        case .apiError(let message):
            return "API-Fehler: \(message)"
        case .noTranscription:
            return "Keine Transkription erhalten."
        case .speechRecognitionUnavailable:
            return String(localized: "appleSpeechUnavailable")
        }
    }
}

class OpenAIService {
    static let shared = OpenAIService()

    private let openAIBaseURL = "https://api.openai.com/v1/audio/transcriptions"
    /// Gemini 3.5 Transcribe runs on the Interactions API, not on `models/…:generateContent`.
    private let geminiInteractionsURL = "https://generativelanguage.googleapis.com/v1beta/interactions"

    /// Inline audio travels base64-encoded and the whole request must stay below the
    /// Interactions API's 20 MB cap.
    private static let geminiInlineAudioLimit = 18 * 1024 * 1024

    private init() {}

    func transcribe(audioURL: URL, model: TranscriptionModel) async throws -> String {
        let settings = AppSettings.shared

        switch settings.speechModelProvider {
        case .openAI:
            return try await transcribeWithOpenAI(audioURL: audioURL, model: model, settings: settings)
        case .local:
            return try await transcribeWithWhisperServer(audioURL: audioURL, settings: settings)
        case .appleSpeech:
            return try await transcribeWithAppleSpeech(audioURL: audioURL)
        case .gemini:
            return try await transcribeWithGemini(audioURL: audioURL, settings: settings)
        case .azureFoundry:
            return try await transcribeWithAzureFoundry(audioURL: audioURL, settings: settings)
        }
    }

    /// Appends a simple multipart/form-data text field.
    private func appendFormField(_ name: String, _ value: String, to body: inout Data, boundary: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    // MARK: - OpenAI API Transcription

    private func transcribeWithOpenAI(audioURL: URL, model: TranscriptionModel, settings: AppSettings) async throws -> String {
        let apiKey = settings.apiKey

        guard !apiKey.isEmpty else {
            throw OpenAIError.invalidAPIKey
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: openAIBaseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        var body = Data()

        // gpt-live-transcribe is realtime-only and has no /v1/audio/transcriptions endpoint.
        // Should it ever reach this path, transcribe with its batch sibling instead of
        // failing the request.
        let effectiveModel = model.batchFallback

        // Add model field
        appendFormField("model", effectiveModel.rawValue, to: &body, boundary: boundary)

        if effectiveModel.usesLanguagesAndKeywords {
            // New model generation: `languages` (plural) replaces the singular `language`
            // and is omitted entirely for automatic detection.
            if let language = settings.openAISpeechLanguage.apiCode {
                appendFormField("languages[]", language, to: &body, boundary: boundary)
            }

            // Dictionary words become literal custom vocabulary…
            for keyword in settings.openAIKeywords {
                appendFormField("keywords[]", keyword, to: &body, boundary: boundary)
            }

            // …and the free-text instructions stay in the prompt.
            let instructions = settings.dictionaryInstructionsText
            if !instructions.isEmpty {
                appendFormField("prompt", instructions, to: &body, boundary: boundary)
            }
        } else {
            // Legacy gpt-4o-* models: language field (German) and the combined dictionary prompt
            appendFormField("language", "de", to: &body, boundary: boundary)

            let dictionaryPrompt = settings.dictionaryPromptText
            if !dictionaryPrompt.isEmpty {
                appendFormField("prompt", dictionaryPrompt, to: &body, boundary: boundary)
            }
        }

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        return try await executeTranscriptionRequest(request)
    }

    // MARK: - Local Whisper Server Transcription

    private func transcribeWithWhisperServer(audioURL: URL, settings: AppSettings) async throws -> String {
        let serverURL = settings.whisperServerURL
        let modelName = settings.whisperServerModel

        guard !serverURL.isEmpty, let url = URL(string: serverURL) else {
            throw OpenAIError.apiError(String(localized: "whisperServerURLInvalid"))
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Add Bearer token if provided
        let bearerToken = settings.whisperServerBearerToken
        if !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.applyCustomHeaders(settings.whisperServerCustomHeaders)

        let audioData = try Data(contentsOf: audioURL)
        var body = Data()

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(modelName)\r\n".data(using: .utf8)!)

        // Add language field (German)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("de\r\n".data(using: .utf8)!)

        // Add dictionary prompt only if enabled for the local server.
        // In simple mode only the words (comma-separated) are sent, without instructions.
        let dictionaryPrompt = settings.dictionarySimpleModeLocalWhisper
            ? settings.dictionaryWordsText
            : settings.dictionaryPromptText
        if settings.applyDictionaryToLocalWhisper && !dictionaryPrompt.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(dictionaryPrompt)\r\n".data(using: .utf8)!)
        }

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        return try await executeTranscriptionRequest(request)
    }

    // MARK: - Google Gemini Transcription (Gemini 3.5 Transcribe)

    /// Unary transcription with `gemini-3.5-transcribe` over the Interactions API. Unlike the
    /// previous `generateContent` prompt hack this is a real ASR endpoint: language hints,
    /// custom vocabulary and the transcription mode are first-class config, so no instruction
    /// text is sent at all.
    private func transcribeWithGemini(audioURL: URL, settings: AppSettings) async throws -> String {
        let apiKey = settings.geminiApiKey
        guard !apiKey.isEmpty else {
            throw OpenAIError.invalidAPIKey
        }

        guard let url = URL(string: geminiInteractionsURL) else {
            throw OpenAIError.invalidResponse
        }

        // gemini-3.5-transcribe-live exists only on the Live API. Should it reach this path,
        // transcribe with its unary sibling instead of failing the request.
        let model = settings.selectedGeminiSpeechModel.batchFallback

        // The Interactions API accepts WAV/MP3/AIFF/AAC/OGG/FLAC — not the m4a container the
        // recorder writes — so the recording is converted first.
        let wavURL = try convertToWav(audioURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }
        let base64Audio = try Data(contentsOf: wavURL).base64EncodedString()
        guard base64Audio.count <= Self.geminiInlineAudioLimit else {
            throw OpenAIError.apiError(String(localized: "geminiAudioTooLong"))
        }

        // An empty `language_codes` list is the documented way to ask for automatic
        // detection (including mid-sentence language switches).
        var transcriptionConfig: [String: Any] = [
            "language_codes": settings.geminiSpeechLanguage.apiCode.map { [$0] } ?? [],
            "mode": ["type": settings.geminiTranscriptionMode.unaryValue]
        ]
        // Dictionary words bias recognition. The free-text instructions have no channel here
        // — the transcribe model takes no prompt.
        let vocabulary = settings.geminiCustomVocabulary
        if !vocabulary.isEmpty {
            transcriptionConfig["custom_vocabulary"] = vocabulary
        }

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "input": [[
                "type": "audio",
                "data": base64Audio,
                "mime_type": "audio/wav"
            ]],
            "generation_config": [
                "transcription_config": transcriptionConfig
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIError.invalidResponse
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw OpenAIError.invalidAPIKey
            }

            if httpResponse.statusCode != 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw OpenAIError.apiError(message)
                }
                throw OpenAIError.apiError("HTTP \(httpResponse.statusCode)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw OpenAIError.invalidResponse
            }

            let text = Self.geminiTranscript(from: json)
            if text.isEmpty {
                throw OpenAIError.noTranscription
            }
            return text
        } catch let error as OpenAIError {
            throw error
        } catch {
            throw OpenAIError.networkError(error)
        }
    }

    /// Reads the transcript out of an Interactions response. `output_text` is the documented
    /// convenience field; the per-step text content is the fallback for responses that carry
    /// the transcript only in `steps[].content[]` (e.g. alongside word annotations).
    private static func geminiTranscript(from json: [String: Any]) -> String {
        if let outputText = json["output_text"] as? String {
            let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        let steps = json["steps"] as? [[String: Any]] ?? []
        let texts = steps.flatMap { step -> [String] in
            let contents = step["content"] as? [[String: Any]] ?? []
            return contents.compactMap { content in
                guard content["type"] as? String == "text" else { return nil }
                return content["text"] as? String
            }
        }
        return texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Azure Foundry MAI (LLM Speech) Transcription

    private func transcribeWithAzureFoundry(audioURL: URL, settings: AppSettings) async throws -> String {
        let apiKey = settings.azureFoundryApiKey
        guard !apiKey.isEmpty else {
            throw OpenAIError.invalidAPIKey
        }

        // Build the request URL: <endpoint>/speechtotext/transcriptions:transcribe?api-version=...
        let trimmedEndpoint = settings.azureFoundryEndpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedEndpoint.hasSuffix("/") ? String(trimmedEndpoint.dropLast()) : trimmedEndpoint
        let apiVersion = settings.azureFoundryApiVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !apiVersion.isEmpty,
              let url = URL(string: "\(base)/speechtotext/transcriptions:transcribe?api-version=\(apiVersion)") else {
            throw OpenAIError.apiError(String(localized: "azureEndpointInvalid"))
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build the definition JSON.
        // - With an explicit model (e.g. mai-transcribe-1.5): MAI-Transcribe style,
        //   only `enabled` + `model` (no `task`; prompt-tuning is unsupported).
        // - With an empty model field: fall back to the default LLM Speech request
        //   (`enabled` + `task`), which is the request shape that worked before.
        var enhancedMode: [String: Any] = ["enabled": true]
        let modelName = settings.azureFoundryModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelName.isEmpty {
            enhancedMode["task"] = "transcribe"
        } else {
            enhancedMode["model"] = modelName
        }
        var definition: [String: Any] = [:]

        // Dictionary (custom vocabulary) — only when enabled and there are words.
        // MAI-Transcribe-1.5 supports `phraseList` (entity biasing); this is the
        // correct channel for custom vocabulary. The free-text instructions are not
        // sent because prompt-tuning is unsupported by MAI-Transcribe.
        if settings.applyDictionaryToAzure {
            let phrases = settings.dictionaryPhrases
            if !phrases.isEmpty {
                definition["phraseList"] = [
                    "phrases": phrases,
                    "biasing_weight": settings.azureBiasingWeightClamped
                ]
            }
        }

        definition["enhancedMode"] = enhancedMode

        let definitionData = try JSONSerialization.data(withJSONObject: definition)
        let definitionString = String(data: definitionData, encoding: .utf8) ?? "{}"

        // MAI-Transcribe only accepts WAV/MP3/FLAC, so convert the recorded m4a to WAV.
        let wavURL = try convertToWav(audioURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }
        let audioData = try Data(contentsOf: wavURL)
        var body = Data()

        // Add definition field (JSON string)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"definition\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(definitionString)\r\n".data(using: .utf8)!)

        // Add audio file (Azure expects the field name "audio")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        return try await executeAzureTranscriptionRequest(request)
    }

    /// Converts an audio file (e.g. m4a/AAC) to a 16-bit PCM WAV file in a temp location.
    /// MAI-Transcribe only accepts WAV/MP3/FLAC.
    private func convertToWav(_ sourceURL: URL) throws -> URL {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let processingFormat = sourceFile.processingFormat
        let frameCount = AVAudioFrameCount(sourceFile.length)

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount) else {
            throw OpenAIError.apiError(String(localized: "azureAudioConversionFailed"))
        }
        try sourceFile.read(into: buffer)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: processingFormat.sampleRate,
            AVNumberOfChannelsKey: processingFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
        try outputFile.write(from: buffer)
        return outputURL
    }

    // MARK: - Apple Speech (On-Device)

    private func transcribeWithAppleSpeech(audioURL: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw OpenAIError.speechRecognitionUnavailable
        }

        // Request authorization if needed
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard authStatus == .authorized else {
            throw OpenAIError.apiError(String(localized: "appleSpeechNotAuthorized"))
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: OpenAIError.apiError(error.localizedDescription))
                    return
                }

                guard let result = result, result.isFinal else {
                    return
                }

                let text = result.bestTranscription.formattedString
                if text.isEmpty {
                    continuation.resume(throwing: OpenAIError.noTranscription)
                } else {
                    continuation.resume(returning: text)
                }
            }
        }
    }

    // MARK: - Common Request Execution

    private func executeTranscriptionRequest(_ request: URLRequest) async throws -> String {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIError.invalidResponse
            }

            if httpResponse.statusCode == 401 {
                throw OpenAIError.invalidAPIKey
            }

            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                    throw OpenAIError.apiError(errorJson.error.message)
                }
                throw OpenAIError.apiError("HTTP \(httpResponse.statusCode)")
            }

            // Parse response
            if let transcriptionResponse = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) {
                return transcriptionResponse.text
            }

            // Try plain text response
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return text
            }

            throw OpenAIError.noTranscription
        } catch let error as OpenAIError {
            throw error
        } catch {
            throw OpenAIError.networkError(error)
        }
    }

    // MARK: - Azure Request Execution

    private func executeAzureTranscriptionRequest(_ request: URLRequest) async throws -> String {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIError.invalidResponse
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw OpenAIError.invalidAPIKey
            }

            if httpResponse.statusCode != 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw OpenAIError.apiError(message)
                }
                // Surface the raw body so unexpected error shapes are still diagnosable.
                if let body = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                    throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(body)")
                }
                throw OpenAIError.apiError("HTTP \(httpResponse.statusCode)")
            }

            guard let result = try? JSONDecoder().decode(AzureTranscriptionResponse.self, from: data) else {
                throw OpenAIError.noTranscription
            }

            let text = result.combinedPhrases
                .map { $0.text }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if text.isEmpty {
                throw OpenAIError.noTranscription
            }
            return text
        } catch let error as OpenAIError {
            throw error
        } catch {
            throw OpenAIError.networkError(error)
        }
    }
}

// MARK: - Response Models

struct TranscriptionResponse: Codable {
    let text: String
}

struct AzureTranscriptionResponse: Codable {
    struct CombinedPhrase: Codable {
        let text: String
    }
    let combinedPhrases: [CombinedPhrase]
}

struct OpenAIErrorResponse: Codable {
    let error: OpenAIErrorDetail
}

struct OpenAIErrorDetail: Codable {
    let message: String
    let type: String?
    let code: String?
}
