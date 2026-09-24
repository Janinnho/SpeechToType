//
//  ChatService.swift
//  SpeechToType
//
//  Streams chat replies from the text providers (OpenAI, Anthropic, Gemini, Ollama,
//  Apple Intelligence). Requests are built from a settings snapshot and run off the
//  main thread; the stream yields the accumulated reply text after every chunk.
//

import Foundation
import FoundationModels

/// Everything a request needs from `AppSettings`, captured on the main actor so the
/// network work can run elsewhere.
nonisolated struct ChatProviderConfig: Sendable {
    var openAIKey: String
    var anthropicKey: String
    var geminiKey: String
    var ollamaServerURL: String
    var ollamaHeaders: [(name: String, value: String)]

    @MainActor init(settings: AppSettings) {
        openAIKey = settings.textOpenAIApiKey
        anthropicKey = settings.anthropicApiKey
        geminiKey = settings.geminiApiKey
        var server = settings.ollamaServerURL.trimmingCharacters(in: .whitespaces)
        while server.hasSuffix("/") { server.removeLast() }
        ollamaServerURL = server
        ollamaHeaders = settings.ollamaCustomHeaders.compactMap { header -> (name: String, value: String)? in
            let name = header.name.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : (name: name, value: header.value)
        }
    }
}

nonisolated struct ChatRequest: Sendable {
    var messages: [ChatMessage]
    var model: ChatModelSelection
    /// Custom instructions, sent as the system prompt ("" = none)
    var instructions: String
    var config: ChatProviderConfig
    /// Small side task (e.g. a title): ask reasoning models to think as little as possible
    var quick = false
}

nonisolated enum ChatServiceError: LocalizedError {
    case invalidAPIKey
    case notConfigured(String)
    case apiError(String)
    case network(String)
    case invalidResponse
    case noResponse
    case imagesNotSupported
    case contextTooLong

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return String(localized: "rewriteErrorApiKey")
        case .notConfigured(let provider):
            return String(format: String(localized: "chatErrorNotConfigured %@"), provider)
        case .apiError(let message):
            return String(localized: "rewriteErrorApi") + ": " + message
        case .network(let message):
            return String(localized: "rewriteErrorNetwork") + ": " + message
        case .invalidResponse:
            return String(localized: "rewriteErrorInvalidResponse")
        case .noResponse:
            return String(localized: "rewriteErrorNoResponse")
        case .imagesNotSupported:
            return String(localized: "chatErrorImagesNotSupported")
        case .contextTooLong:
            return String(localized: "chatErrorContextTooLong")
        }
    }
}

nonisolated enum ChatService {
    private static let openAIURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let anthropicURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    /// Anthropic requires an explicit output budget. It covers thinking + text, and the
    /// current models always think first.
    private static let anthropicMaxTokens = 32_000
    /// Idle timeout per request — reasoning models can think a while before the first byte
    private static let requestTimeout: TimeInterval = 300
    /// Rough share of Apple Intelligence's small context window (≈4k tokens) used for
    /// history + prompt, in characters; older turns are dropped beyond that.
    private static let appleContextCharacters = 9_000

    /// Streams the reply to the last user message of `request`. Every element is the
    /// complete reply text received so far.
    static func streamReply(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await run(request) { text in continuation.yield(text) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Asks `model` for a short title for a chat that starts with `message`.
    static func generateTitle(for message: ChatMessage, model: ChatModelSelection, config: ChatProviderConfig) async throws -> String {
        var excerpt = String(message.content.prefix(2000))
        if excerpt.isEmpty {
            excerpt = message.attachments.map(\.fileName).joined(separator: ", ")
        }
        let prompt = """
        Write a short title (at most 6 words) for a chat conversation that starts with the message below. \
        Use the language of the message. Reply with the title only: no quotes, no prefix, no final punctuation.

        <message>
        \(excerpt)
        </message>
        """
        let request = ChatRequest(
            messages: [ChatMessage(role: .user, content: prompt)],
            model: model,
            instructions: "",
            config: config,
            quick: true
        )
        var reply = ""
        for try await text in streamReply(request) {
            reply = text
        }
        return cleanTitle(reply)
    }

    /// First line of a model-written title without quotes, "Title:" prefixes or a trailing period.
    static func cleanTitle(_ raw: String) -> String {
        var title = firstLine(of: raw)
        for prefix in ["title:", "titel:"] where title.lowercased().hasPrefix(prefix) {
            title = String(title.dropFirst(prefix.count))
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”„‚‘’*#`").union(.whitespaces))
        while let last = title.last, ".:".contains(last) {
            title.removeLast()
        }
        if title.count > 60 {
            title = String(title.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return title
    }

    /// Title used until (or instead of) a generated one: the first line of the message.
    static func fallbackTitle(text: String, attachments: [ChatAttachment]) -> String {
        let line = firstLine(of: text)
        if !line.isEmpty {
            return line.count > 50 ? String(line.prefix(50)) + "…" : line
        }
        return attachments.first?.fileName ?? String(localized: "chatNew")
    }

    /// First line that isn't blank, trimmed ("" if there is none)
    private static func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    private static func run(_ request: ChatRequest, emit: (String) -> Void) async throws {
        do {
            switch request.model.provider {
            case .openAI:
                try await streamOpenAI(request, emit: emit)
            case .anthropic:
                try await streamAnthropic(request, emit: emit)
            case .gemini:
                try await streamGemini(request, emit: emit)
            case .ollama:
                try await streamOllama(request, emit: emit)
            case .appleIntelligence:
                try await streamAppleIntelligence(request, emit: emit)
            }
        } catch let error as URLError where error.code != .cancelled {
            throw ChatServiceError.network(error.localizedDescription)
        }
    }

    // MARK: - OpenAI

    private static func streamOpenAI(_ request: ChatRequest, emit: (String) -> Void) async throws {
        let apiKey = request.config.openAIKey
        guard !apiKey.isEmpty else { throw ChatServiceError.notConfigured(TextProcessingProvider.openAI.displayName) }

        var messages: [[String: Any]] = []
        if !request.instructions.isEmpty {
            messages.append(["role": "system", "content": request.instructions])
        }
        for message in history(request) {
            switch message.role {
            case .assistant:
                messages.append(["role": "assistant", "content": message.content])
            case .user:
                messages.append(["role": "user", "content": openAIContent(for: message)])
            }
        }

        var body: [String: Any] = [
            "model": request.model.modelID,
            "stream": true,
            "messages": messages
        ]
        if request.quick, GPTModel(rawValue: request.model.modelID) != nil {
            body["reasoning_effort"] = "low"
        }

        var urlRequest = makeRequest(url: openAIURL)
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        var text = ""
        for try await line in try await openStream(urlRequest).lines {
            guard let json = sseJSON(line) else { continue }
            if let error = json["error"] as? [String: Any] {
                throw ChatServiceError.apiError(error["message"] as? String ?? "unknown")
            }
            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let chunk = delta["content"] as? String, !chunk.isEmpty else { continue }
            text += chunk
            emit(text)
        }
        guard !text.isEmpty else { throw ChatServiceError.noResponse }
    }

    /// Plain string without attachments, otherwise content parts (images and PDFs
    /// inline as base64, text files as text).
    private static func openAIContent(for message: ChatMessage) -> Any {
        guard !message.attachments.isEmpty else { return message.content }

        var parts: [[String: Any]] = message.attachments.map { attachment in
            switch attachment.kind {
            case .image:
                guard let data = ChatAttachmentStore.base64(of: attachment) else {
                    return ["type": "text", "text": missingNote(for: attachment)]
                }
                return ["type": "image_url", "image_url": ["url": "data:\(attachment.mimeType);base64,\(data)"]]
            case .pdf:
                guard let data = ChatAttachmentStore.base64(of: attachment) else {
                    return ["type": "text", "text": missingNote(for: attachment)]
                }
                return ["type": "file", "file": [
                    "filename": attachment.fileName,
                    "file_data": "data:application/pdf;base64,\(data)"
                ]]
            case .text:
                return ["type": "text", "text": inlineText(for: attachment)]
            }
        }
        if !message.content.isEmpty {
            parts.append(["type": "text", "text": message.content])
        }
        return parts
    }

    // MARK: - Anthropic

    private static func streamAnthropic(_ request: ChatRequest, emit: (String) -> Void) async throws {
        let apiKey = request.config.anthropicKey
        guard !apiKey.isEmpty else { throw ChatServiceError.notConfigured(TextProcessingProvider.anthropic.displayName) }

        let messages: [[String: Any]] = history(request).map { message in
            switch message.role {
            case .assistant:
                return ["role": "assistant", "content": message.content]
            case .user:
                return ["role": "user", "content": anthropicContent(for: message)]
            }
        }
        var body: [String: Any] = [
            "model": request.model.modelID,
            "max_tokens": anthropicMaxTokens,
            "stream": true,
            "messages": messages
        ]
        if !request.instructions.isEmpty {
            body["system"] = request.instructions
        }
        if request.quick, AnthropicModel(rawValue: request.model.modelID)?.supportsEffort == true {
            body["output_config"] = ["effort": "low"]
        }

        var urlRequest = makeRequest(url: anthropicURL)
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        var text = ""
        for try await line in try await openStream(urlRequest).lines {
            guard let json = sseJSON(line) else { continue }
            switch json["type"] as? String {
            case "content_block_delta":
                // Only text deltas — thinking blocks are not shown
                guard let delta = json["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let chunk = delta["text"] as? String else { continue }
                text += chunk
                emit(text)
            case "error":
                let error = json["error"] as? [String: Any]
                throw ChatServiceError.apiError(error?["message"] as? String ?? "unknown")
            default:
                continue
            }
        }
        guard !text.isEmpty else { throw ChatServiceError.noResponse }
    }

    private static func anthropicContent(for message: ChatMessage) -> Any {
        guard !message.attachments.isEmpty else { return message.content }

        var blocks: [[String: Any]] = message.attachments.map { attachment in
            switch attachment.kind {
            case .image:
                guard let data = ChatAttachmentStore.base64(of: attachment) else {
                    return ["type": "text", "text": missingNote(for: attachment)]
                }
                return ["type": "image", "source": ["type": "base64", "media_type": attachment.mimeType, "data": data]]
            case .pdf:
                guard let data = ChatAttachmentStore.base64(of: attachment) else {
                    return ["type": "text", "text": missingNote(for: attachment)]
                }
                return [
                    "type": "document",
                    "title": attachment.fileName,
                    "source": ["type": "base64", "media_type": "application/pdf", "data": data]
                ]
            case .text:
                return ["type": "text", "text": inlineText(for: attachment)]
            }
        }
        if !message.content.isEmpty {
            blocks.append(["type": "text", "text": message.content])
        }
        return blocks
    }

    // MARK: - Gemini

    private static func streamGemini(_ request: ChatRequest, emit: (String) -> Void) async throws {
        let apiKey = request.config.geminiKey
        guard !apiKey.isEmpty else { throw ChatServiceError.notConfigured(TextProcessingProvider.gemini.displayName) }
        guard let url = URL(string: "\(geminiBaseURL)/\(request.model.modelID):streamGenerateContent?alt=sse") else {
            throw ChatServiceError.invalidResponse
        }

        let contents: [[String: Any]] = history(request).map { message in
            ["role": message.role == .user ? "user" : "model", "parts": geminiParts(for: message)]
        }
        var body: [String: Any] = ["contents": contents]
        if !request.instructions.isEmpty {
            body["systemInstruction"] = ["parts": [["text": request.instructions]]]
        }

        var urlRequest = makeRequest(url: url)
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        var text = ""
        for try await line in try await openStream(urlRequest).lines {
            guard let json = sseJSON(line) else { continue }
            if let error = json["error"] as? [String: Any] {
                throw ChatServiceError.apiError(error["message"] as? String ?? "unknown")
            }
            if let feedback = json["promptFeedback"] as? [String: Any],
               let reason = feedback["blockReason"] as? String {
                throw ChatServiceError.apiError(reason)
            }
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            // Skip thought summaries, keep the answer text
            let chunk = parts
                .filter { ($0["thought"] as? Bool) != true }
                .compactMap { $0["text"] as? String }
                .joined()
            guard !chunk.isEmpty else { continue }
            text += chunk
            emit(text)
        }
        guard !text.isEmpty else { throw ChatServiceError.noResponse }
    }

    private static func geminiParts(for message: ChatMessage) -> [[String: Any]] {
        guard message.role == .user else { return [["text": message.content]] }

        var parts: [[String: Any]] = message.attachments.map { attachment in
            switch attachment.kind {
            case .image, .pdf:
                guard let data = ChatAttachmentStore.base64(of: attachment) else {
                    return ["text": missingNote(for: attachment)]
                }
                return ["inlineData": ["mimeType": attachment.mimeType, "data": data]]
            case .text:
                return ["text": inlineText(for: attachment)]
            }
        }
        if !message.content.isEmpty {
            parts.append(["text": message.content])
        }
        return parts
    }

    // MARK: - Ollama

    private static func streamOllama(_ request: ChatRequest, emit: (String) -> Void) async throws {
        let server = request.config.ollamaServerURL
        let model = request.model.modelID
        guard !server.isEmpty, !model.isEmpty else {
            throw ChatServiceError.apiError(String(localized: "ollamaConfigError"))
        }
        guard let url = URL(string: "\(server)/api/chat") else {
            throw ChatServiceError.apiError(String(localized: "ollamaURLInvalid"))
        }

        var messages: [[String: Any]] = []
        if !request.instructions.isEmpty {
            messages.append(["role": "system", "content": request.instructions])
        }
        for message in history(request) {
            // PDFs and text files go in as text; images use Ollama's `images` field
            var entry: [String: Any] = [
                "role": message.role.rawValue,
                "content": plainText(for: message, imagesAsNote: false)
            ]
            let images = message.attachments
                .filter { $0.kind == .image }
                .compactMap { ChatAttachmentStore.base64(of: $0) }
            if !images.isEmpty {
                entry["images"] = images
            }
            messages.append(entry)
        }

        var urlRequest = makeRequest(url: url)
        for header in request.config.ollamaHeaders {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": true,
            "messages": messages
        ])

        // Ollama streams newline-delimited JSON, not SSE
        var text = ""
        for try await line in try await openStream(urlRequest).lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let error = json["error"] as? String {
                throw ChatServiceError.apiError(error)
            }
            if let message = json["message"] as? [String: Any],
               let chunk = message["content"] as? String, !chunk.isEmpty {
                text += chunk
                emit(text)
            }
            if json["done"] as? Bool == true { break }
        }
        guard !text.isEmpty else { throw ChatServiceError.noResponse }
    }

    // MARK: - Apple Intelligence

    private static func streamAppleIntelligence(_ request: ChatRequest, emit: (String) -> Void) async throws {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw ChatServiceError.apiError(String(localized: "appleIntelligenceUnavailable"))
        }

        var messages = history(request)
        guard let last = messages.popLast(), last.role == .user else { throw ChatServiceError.noResponse }
        // The on-device model takes text only. Images from earlier turns become a note.
        guard !last.attachments.contains(where: { $0.kind == .image }) else {
            throw ChatServiceError.imagesNotSupported
        }
        let prompt = plainText(for: last, imagesAsNote: true)

        // Keep only as many recent turns as fit the small context window
        var budget = appleContextCharacters - prompt.count - request.instructions.count
        var entries: [Transcript.Entry] = []
        for message in messages.reversed() {
            let text = plainText(for: message, imagesAsNote: true)
            budget -= text.count
            guard budget >= 0 else { break }
            let segment = Transcript.Segment.text(Transcript.TextSegment(content: text))
            entries.insert(message.role == .user
                ? .prompt(Transcript.Prompt(segments: [segment]))
                : .response(Transcript.Response(assetIDs: [], segments: [segment])), at: 0)
        }
        if !request.instructions.isEmpty {
            let segment = Transcript.Segment.text(Transcript.TextSegment(content: request.instructions))
            entries.insert(.instructions(Transcript.Instructions(segments: [segment], toolDefinitions: [])), at: 0)
        }

        let session = LanguageModelSession(model: model, tools: [], transcript: Transcript(entries: entries))
        do {
            // Snapshots already carry the full text so far
            for try await snapshot in session.streamResponse(to: prompt) {
                emit(snapshot.content)
            }
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error { throw ChatServiceError.contextTooLong }
            throw error
        }
    }

    // MARK: - Common

    private static func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Starts the request and returns the body stream, or throws the provider's error.
    private static func openStream(_ request: URLRequest) async throws -> URLSession.AsyncBytes {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatServiceError.invalidResponse }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 { throw ChatServiceError.invalidAPIKey }
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 64 * 1024 { break }
            }
            throw ChatServiceError.apiError(errorMessage(in: body) ?? "HTTP \(http.statusCode)")
        }
        return bytes
    }

    /// Error message in any of the providers' error formats
    private static func errorMessage(in body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : String(text.prefix(300))
        }
        // Gemini's streaming endpoint wraps the error object in an array
        let object = (json as? [[String: Any]])?.first ?? (json as? [String: Any])
        if let error = object?["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        // Ollama: {"error": "…"}
        return object?["error"] as? String
    }

    /// JSON payload of an SSE `data:` line (nil for other lines and `[DONE]`)
    private static func sseJSON(_ line: String) -> [String: Any]? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", let data = payload.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Replies that failed before any text arrived are not sent back to the model
    private static func history(_ request: ChatRequest) -> [ChatMessage] {
        request.messages.filter { $0.role == .user || !$0.content.isEmpty }
    }

    /// A user message flattened to text, for providers without native file support.
    private static func plainText(for message: ChatMessage, imagesAsNote: Bool) -> String {
        guard message.role == .user else { return message.content }
        var parts: [String] = message.attachments.compactMap { attachment in
            switch attachment.kind {
            case .image:
                return imagesAsNote ? "[Image: \(attachment.fileName)]" : nil
            case .pdf, .text:
                return inlineText(for: attachment)
            }
        }
        if !message.content.isEmpty {
            parts.append(message.content)
        }
        return parts.joined(separator: "\n\n")
    }

    private static func inlineText(for attachment: ChatAttachment) -> String {
        var content = ChatAttachmentStore.text(of: attachment)
        if content.count > ChatAttachmentStore.maxInlineTextCharacters {
            content = String(content.prefix(ChatAttachmentStore.maxInlineTextCharacters)) + "\n[…]"
        }
        return "<file name=\"\(attachment.fileName)\">\n\(content)\n</file>"
    }

    private static func missingNote(for attachment: ChatAttachment) -> String {
        "[Attachment \"\(attachment.fileName)\" is no longer available]"
    }
}
