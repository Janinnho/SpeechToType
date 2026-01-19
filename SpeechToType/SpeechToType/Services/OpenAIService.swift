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
    
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    
    private init() {}
    
    func transcribe(audioURL: URL, model: TranscriptionModel) async throws -> String {
        let apiKey = AppSettings.shared.apiKey
        
        guard !apiKey.isEmpty else {
            throw OpenAIError.invalidAPIKey
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: baseURL)!)
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
