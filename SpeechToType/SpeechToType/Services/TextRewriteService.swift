//
//  TextRewriteService.swift
//  SpeechToType
//
//  Created on 22.01.26.
//

import Foundation
import FoundationModels

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
    case gpt54 = "gpt-5.4"
    case gpt54mini = "gpt-5.4-mini"
    case gpt54nano = "gpt-5.4-nano"
    case gpt55 = "gpt-5.5"

    var displayName: String {
        switch self {
        case .gpt4o:
            return "GPT-4o"
        case .gpt54:
            return "GPT-5.4"
        case .gpt54mini:
            return "GPT-5.4 Mini"
        case .gpt54nano:
            return "GPT-5.4 Nano"
        case .gpt55:
            return "GPT-5.5"
        }
    }

    /// Whether this model uses max_completion_tokens instead of max_tokens
    var usesMaxCompletionTokens: Bool {
        switch self {
        case .gpt4o:
            return false
        case .gpt54, .gpt54mini, .gpt54nano, .gpt55:
            return true
        }
    }

    /// Whether this model supports custom temperature values
    var supportsCustomTemperature: Bool {
        switch self {
        case .gpt4o:
            return true
        case .gpt54, .gpt54mini, .gpt54nano, .gpt55:
            return false
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

    private let openAIBaseURL = "https://api.openai.com/v1/chat/completions"
    private let anthropicBaseURL = "https://api.anthropic.com/v1/messages"
    private let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    private init() {}

    func rewriteText(_ text: String, mode: RewriteMode, customPrompt: String? = nil, targetLanguage: String? = nil) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextRewriteError.noTextSelected
        }

        let settings = AppSettings.shared

        // Determine system prompt based on mode
        var systemPrompt: String
        switch mode {
        case .dictate:
            systemPrompt = customPrompt ?? "Process the following text as instructed."
        case .translate:
            let language = targetLanguage ?? settings.defaultTranslationLanguage
            systemPrompt = "You are a translator. Translate the following text to \(language). Return only the translated text without any explanations or additional text."
        case .custom:
            systemPrompt = customPrompt ?? ""
        default:
            systemPrompt = mode.systemPrompt
        }

        // Inject dictionary (custom vocabulary / instructions) if enabled
        if settings.applyDictionaryToRewrite {
            let dictionaryPrompt = settings.dictionaryPromptText
            if !dictionaryPrompt.isEmpty {
                systemPrompt = "Custom vocabulary and instructions to respect: \(dictionaryPrompt)\n\n" + systemPrompt
            }
        }

        switch settings.textProcessingProvider {
        case .openAI:
            return try await rewriteWithOpenAI(text: text, systemPrompt: systemPrompt, settings: settings)
        case .anthropic:
            return try await rewriteWithAnthropic(text: text, systemPrompt: systemPrompt, settings: settings)
        case .ollama:
            return try await rewriteWithOllama(text: text, systemPrompt: systemPrompt, settings: settings)
        case .appleIntelligence:
            return try await rewriteWithAppleIntelligence(text: text, systemPrompt: systemPrompt)
        case .gemini:
            return try await rewriteWithGemini(text: text, systemPrompt: systemPrompt, settings: settings)
        }
    }

    // MARK: - OpenAI

    private func rewriteWithOpenAI(text: String, systemPrompt: String, settings: AppSettings) async throws -> String {
        // Use dedicated text processing API key if set, otherwise fall back to main API key
        let apiKey = settings.textProcessingOpenAIApiKey.isEmpty ? settings.apiKey : settings.textProcessingOpenAIApiKey
        guard !apiKey.isEmpty else {
            throw TextRewriteError.invalidAPIKey
        }

        let model = settings.selectedGPTModel

        var request = URLRequest(url: URL(string: openAIBaseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]

        if model.supportsCustomTemperature {
            requestBody["temperature"] = 0.7
        }

        if model.usesMaxCompletionTokens {
            requestBody["max_completion_tokens"] = 2048
        } else {
            requestBody["max_tokens"] = 2048
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await executeRequest(request, data: nil)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TextRewriteError.noResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic

    private func rewriteWithAnthropic(text: String, systemPrompt: String, settings: AppSettings) async throws -> String {
        let apiKey = settings.anthropicApiKey
        guard !apiKey.isEmpty else {
            throw TextRewriteError.invalidAPIKey
        }

        let model = settings.selectedAnthropicModel

        var request = URLRequest(url: URL(string: anthropicBaseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": text]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await executeRequest(request, data: nil)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let responseText = firstBlock["text"] as? String else {
            throw TextRewriteError.noResponse
        }

        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Gemini

    private func rewriteWithGemini(text: String, systemPrompt: String, settings: AppSettings) async throws -> String {
        let apiKey = settings.geminiApiKey
        guard !apiKey.isEmpty else {
            throw TextRewriteError.invalidAPIKey
        }

        let model = settings.selectedGeminiTextModel
        guard let url = URL(string: "\(geminiBaseURL)/\(model.rawValue):generateContent") else {
            throw TextRewriteError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [[
                "role": "user",
                "parts": [["text": text]]
            ]],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await executeRequest(request, data: nil)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let responseText = parts.first?["text"] as? String else {
            throw TextRewriteError.noResponse
        }

        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Ollama

    private func rewriteWithOllama(text: String, systemPrompt: String, settings: AppSettings) async throws -> String {
        let serverURL = settings.ollamaServerURL
        let modelName = settings.selectedOllamaModel

        guard !serverURL.isEmpty, !modelName.isEmpty else {
            throw TextRewriteError.apiError(String(localized: "ollamaConfigError"))
        }

        guard let url = URL(string: "\(serverURL)/api/chat") else {
            throw TextRewriteError.apiError(String(localized: "ollamaURLInvalid"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.applyCustomHeaders(settings.ollamaCustomHeaders)

        let requestBody: [String: Any] = [
            "model": modelName,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await executeRequest(request, data: nil)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TextRewriteError.noResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fetches available models from an Ollama server
    static func fetchOllamaModels(serverURL: String) async throws -> [String] {
        guard !serverURL.isEmpty, let url = URL(string: "\(serverURL)/api/tags") else {
            return []
        }

        var request = URLRequest(url: url)
        request.applyCustomHeaders(AppSettings.shared.ollamaCustomHeaders)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { $0["name"] as? String }.sorted()
    }

    // MARK: - Apple Intelligence

    private func rewriteWithAppleIntelligence(text: String, systemPrompt: String) async throws -> String {
        let model = SystemLanguageModel.default

        guard model.availability == .available else {
            throw TextRewriteError.apiError(String(localized: "appleIntelligenceUnavailable"))
        }

        let instructions = """
        You are a text editing assistant. You receive text from the user and edit it according to the task described below. \
        Return ONLY the edited text. Do NOT include any explanations, code, markdown, or extra commentary. \
        Do NOT generate code. Output plain text only.

        Task: \(systemPrompt)
        """

        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Edit the following text according to the task:\n\n\(text)"
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Common

    private func executeRequest(_ request: URLRequest, data: Data?) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TextRewriteError.invalidResponse
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw TextRewriteError.invalidAPIKey
            }

            if httpResponse.statusCode != 200 {
                // Try OpenAI error format
                if let errorJson = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                    throw TextRewriteError.apiError(errorJson.error.message)
                }
                // Try Anthropic error format
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw TextRewriteError.apiError(message)
                }
                throw TextRewriteError.apiError("HTTP \(httpResponse.statusCode)")
            }

            return (data, response)
        } catch let error as TextRewriteError {
            throw error
        } catch {
            throw TextRewriteError.networkError(error)
        }
    }
}
