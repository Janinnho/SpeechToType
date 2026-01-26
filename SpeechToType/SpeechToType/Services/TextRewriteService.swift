//
//  TextRewriteService.swift
//  SpeechToType
//
//  Created on 22.01.26.
//

import Foundation

enum RewriteMode: String, CaseIterable, Codable {
    case dictate = "dictate"
    case grammar = "grammar"
    case elaborate = "elaborate"
    case translate = "translate"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .dictate:
            return String(localized: "rewriteDictate")
        case .grammar:
            return String(localized: "rewriteGrammar")
        case .elaborate:
            return String(localized: "rewriteElaborate")
        case .translate:
            return String(localized: "rewriteTranslate")
        case .custom:
            return String(localized: "rewriteCustom")
        }
    }

    var systemPrompt: String {
        switch self {
        case .dictate:
            return "" // Will be set dynamically from voice input
        case .grammar:
            return "You are a helpful assistant that corrects grammar and spelling errors. Return only the corrected text without any explanations or additional text. Preserve the original language of the input."
        case .elaborate:
            return "You are a helpful assistant that elaborates and improves text while maintaining the original meaning and tone. Make the text more professional and well-structured. Return only the improved text without any explanations or additional text. Preserve the original language of the input."
        case .translate:
            return "" // Will be set dynamically based on target language
        case .custom:
            return ""
        }
    }

    /// Whether this mode requires additional input (voice recording or text)
    var requiresInput: Bool {
        switch self {
        case .dictate, .custom:
            return true
        case .grammar, .elaborate, .translate:
            return false
        }
    }
}

enum GPTModel: String, CaseIterable, Codable {
    case gpt4o = "gpt-4o"
    case gpt5 = "gpt-5"
    case gpt52 = "gpt-5.2"

    var displayName: String {
        switch self {
        case .gpt4o:
            return "GPT-4o"
        case .gpt5:
            return "GPT-5"
        case .gpt52:
            return "GPT-5.2"
        }
    }

    /// Whether this model uses max_completion_tokens instead of max_tokens
    var usesMaxCompletionTokens: Bool {
        switch self {
        case .gpt4o:
            return false
        case .gpt5, .gpt52:
            return true
        }
    }

    /// Whether this model supports custom temperature values
    var supportsCustomTemperature: Bool {
        switch self {
        case .gpt4o:
            return true
        case .gpt5, .gpt52:
            return false // Only supports default temperature (1.0)
        }
    }
}

enum TextRewriteError: Error, LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    case noTextSelected
    case noResponse

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return String(localized: "rewriteErrorApiKey")
        case .networkError(let error):
            return String(localized: "rewriteErrorNetwork") + ": \(error.localizedDescription)"
        case .invalidResponse:
            return String(localized: "rewriteErrorInvalidResponse")
        case .apiError(let message):
            return String(localized: "rewriteErrorApi") + ": \(message)"
        case .noTextSelected:
            return String(localized: "rewriteErrorNoText")
        case .noResponse:
            return String(localized: "rewriteErrorNoResponse")
        }
    }
}

class TextRewriteService {
    static let shared = TextRewriteService()

    private let baseURL = "https://api.openai.com/v1/chat/completions"

    private init() {}

    func rewriteText(_ text: String, mode: RewriteMode, customPrompt: String? = nil, targetLanguage: String? = nil) async throws -> String {
        let apiKey = AppSettings.shared.apiKey

        guard !apiKey.isEmpty else {
            throw TextRewriteError.invalidAPIKey
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextRewriteError.noTextSelected
        }

        let model = AppSettings.shared.selectedGPTModel

        // Determine system prompt based on mode
        let systemPrompt: String
        switch mode {
        case .dictate:
            // For dictate mode, the customPrompt contains the voice-transcribed instruction
            systemPrompt = customPrompt ?? "Process the following text as instructed."
        case .translate:
            let language = targetLanguage ?? AppSettings.shared.defaultTranslationLanguage
            systemPrompt = "You are a translator. Translate the following text to \(language). Return only the translated text without any explanations or additional text."
        case .custom:
            systemPrompt = customPrompt ?? ""
        default:
            systemPrompt = mode.systemPrompt
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]

        // Only add temperature for models that support it
        if model.supportsCustomTemperature {
            requestBody["temperature"] = 0.7
        }

        // GPT-5 and GPT-5.2 use max_completion_tokens instead of max_tokens
        if model.usesMaxCompletionTokens {
            requestBody["max_completion_tokens"] = 2048
        } else {
            requestBody["max_tokens"] = 2048
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TextRewriteError.invalidResponse
            }

            if httpResponse.statusCode == 401 {
                throw TextRewriteError.invalidAPIKey
            }

            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                    throw TextRewriteError.apiError(errorJson.error.message)
                }
                throw TextRewriteError.apiError("HTTP \(httpResponse.statusCode)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw TextRewriteError.noResponse
            }

            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TextRewriteError {
            throw error
        } catch {
            throw TextRewriteError.networkError(error)
        }
    }
}
