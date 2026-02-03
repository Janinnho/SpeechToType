//
//  OpenAIService.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import Foundation

enum OpenAIError: Error, LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    case noTranscription
    
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
        }
    }
}

class OpenAIService {
    static let shared = OpenAIService()

    private let openAIBaseURL = "https://api.openai.com/v1/audio/transcriptions"

    private init() {}

    func transcribe(audioURL: URL, model: TranscriptionModel) async throws -> String {
        let settings = AppSettings.shared

        if settings.useLocalWhisperServer {
            return try await transcribeWithWhisperServer(audioURL: audioURL, settings: settings)
        } else {
            return try await transcribeWithOpenAI(audioURL: audioURL, model: model, settings: settings)
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
