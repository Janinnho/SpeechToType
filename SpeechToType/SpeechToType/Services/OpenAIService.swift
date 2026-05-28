//
//  OpenAIService.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import Foundation
import Speech

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
    private let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"

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
        }
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

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model.rawValue)\r\n".data(using: .utf8)!)

        // Add language field (German)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("de\r\n".data(using: .utf8)!)

        // Add dictionary prompt (custom vocabulary / instructions)
        let dictionaryPrompt = settings.dictionaryPromptText
        if !dictionaryPrompt.isEmpty {
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

    // MARK: - Google Gemini Transcription

    private func transcribeWithGemini(audioURL: URL, settings: AppSettings) async throws -> String {
        let apiKey = settings.geminiApiKey
        guard !apiKey.isEmpty else {
            throw OpenAIError.invalidAPIKey
        }

        let model = settings.selectedGeminiSpeechModel
        guard let url = URL(string: "\(geminiBaseURL)/\(model.rawValue):generateContent") else {
            throw OpenAIError.invalidResponse
        }

        let audioData = try Data(contentsOf: audioURL)
        let base64Audio = audioData.base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let baseInstruction = "Transcribe this audio verbatim in German. Return only the transcription without any commentary, formatting, or quotation marks."
        let dictionaryPrompt = settings.dictionaryPromptText
        let instruction = dictionaryPrompt.isEmpty
            ? baseInstruction
            : "Use the following custom vocabulary and spellings where applicable: \(dictionaryPrompt)\n\n\(baseInstruction)"

        let requestBody: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["inlineData": ["mimeType": "audio/mp4", "data": base64Audio]],
                    ["text": instruction]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.0
            ]
        ]

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

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                throw OpenAIError.noTranscription
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw OpenAIError.noTranscription
            }
            return trimmed
        } catch let error as OpenAIError {
            throw error
        } catch {
            throw OpenAIError.networkError(error)
        }
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
}

// MARK: - Response Models

struct TranscriptionResponse: Codable {
    let text: String
}

struct OpenAIErrorResponse: Codable {
    let error: OpenAIErrorDetail
}

struct OpenAIErrorDetail: Codable {
    let message: String
    let type: String?
    let code: String?
}
