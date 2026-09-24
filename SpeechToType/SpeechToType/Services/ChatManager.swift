//
//  ChatManager.swift
//  SpeechToType
//
//  Owns the chat conversations: persistence (one JSON file per conversation in
//  Application Support), sending, streaming replies and generated titles. Replies keep
//  streaming when the chat view is closed.
//

import Foundation
import AppKit
import Combine

/// Live text of replies that are still being generated. Kept apart from `ChatManager`
/// so that only the streaming message re-renders for every chunk.
final class ChatStreamBuffer: ObservableObject {
    @Published private(set) var texts: [UUID: String] = [:]

    func update(_ text: String, for conversationID: UUID) {
        texts[conversationID] = text
    }

    func remove(_ conversationID: UUID) {
        texts[conversationID] = nil
    }
}

final class ChatManager: ObservableObject {
    static let shared = ChatManager()

    /// All conversations, most recently active first
    @Published private(set) var conversations: [ChatConversation] = []
    /// Conversation shown in the chat view; nil = a new chat that has not started yet
    @Published var selectedConversationID: UUID?
    /// Conversations whose reply is being generated right now
    @Published private(set) var generatingIDs: Set<UUID> = []

    let streamBuffer = ChatStreamBuffer()

    private let persistence = ChatPersistence(directory: AppDataDirectory.subdirectory("Chats"))
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Unsent composer contents per conversation (nil = new chat)
    private var drafts: [UUID?: ChatDraft] = [:]
    /// Minimum interval between UI updates while a reply streams in
    private let publishInterval: TimeInterval = 0.05
    private var cancellables = Set<AnyCancellable>()

    private init() {
        conversations = persistence.loadAll().sorted { $0.updatedAt > $1.updatedAt }

        // Chats on a model of an earlier generation continue with its successor
        for index in conversations.indices {
            let upgraded = conversations[index].model.upgraded
            guard upgraded != conversations[index].model else { continue }
            conversations[index].model = upgraded
            persistence.save(conversations[index])
        }

        // Attachments of drafts that were never sent
        let referenced = conversations.flatMap { $0.messages.flatMap { $0.attachments.map(\.storedName) } }
        ChatAttachmentStore.removeOrphans(keeping: Set(referenced))

        // Let queued writes finish before the app quits
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.persistence.flush() }
            .store(in: &cancellables)
    }

    func conversation(with id: UUID) -> ChatConversation? {
        conversations.first { $0.id == id }
    }

    func isGenerating(_ id: UUID) -> Bool {
        generatingIDs.contains(id)
    }

    // MARK: - Drafts

    func draft(for id: UUID?) -> ChatDraft {
        drafts[id] ?? ChatDraft()
    }

    func storeDraft(_ draft: ChatDraft, for id: UUID?) {
        drafts[id] = draft.isEmpty ? nil : draft
    }

    // MARK: - Conversations

    /// Starts a new conversation with the given message, selects it and requests the reply.
    func startConversation(text: String, attachments: [ChatAttachment]) {
        let now = Date()
        let conversation = ChatConversation(
            id: UUID(),
            title: ChatService.fallbackTitle(text: text, attachments: attachments),
            hasFinalTitle: false,
            model: AppSettings.shared.chatModel,
            messages: [ChatMessage(role: .user, content: text, attachments: attachments, date: now)],
            createdAt: now,
            updatedAt: now
        )
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        persistence.save(conversation)
        generateReply(for: conversation.id)
    }

    func send(text: String, attachments: [ChatAttachment], to id: UUID) {
        guard !isGenerating(id), let index = index(of: id) else { return }
        conversations[index].messages.append(ChatMessage(role: .user, content: text, attachments: attachments))
        touch(at: index)
        generateReply(for: id)
    }

    /// Replaces the last reply — or answers a trailing message that never got one.
    func regenerate(_ id: UUID) {
        guard !isGenerating(id), let index = index(of: id) else { return }
        if conversations[index].messages.last?.role == .assistant {
            conversations[index].messages.removeLast()
        }
        guard conversations[index].messages.last?.role == .user else { return }
        touch(at: index)
        generateReply(for: id)
    }

    func stop(_ id: UUID) {
        tasks[id]?.cancel()
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(of: id) else { return }
        conversations[index].title = trimmed
        conversations[index].hasFinalTitle = true
        persistence.save(conversations[index])
    }

    /// Switches the model of a conversation (nil = the new chat). New chats continue
    /// with the model picked last.
    func setModel(_ model: ChatModelSelection, for id: UUID?) {
        AppSettings.shared.chatModel = model
        guard let id, let index = index(of: id) else { return }
        conversations[index].model = model
        persistence.save(conversations[index])
    }

    func delete(_ id: UUID) {
        tasks[id]?.cancel()
        if let draft = drafts.removeValue(forKey: id) {
            ChatAttachmentStore.delete(draft.attachments)
        }
        guard let index = index(of: id) else { return }
        let conversation = conversations.remove(at: index)
        ChatAttachmentStore.delete(conversation.messages.flatMap(\.attachments))
        persistence.delete(id)
        if selectedConversationID == id {
            selectedConversationID = nil
        }
    }

    func deleteAll() {
        for id in conversations.map(\.id) {
            delete(id)
        }
    }

    // MARK: - Replies

    private func generateReply(for id: UUID) {
        guard let conversation = conversation(with: id) else { return }
        let settings = AppSettings.shared
        let request = ChatRequest(
            messages: conversation.messages,
            model: conversation.model,
            instructions: settings.chatCustomInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
            config: ChatProviderConfig(settings: settings)
        )
        let modelName = conversation.model.displayName

        generatingIDs.insert(id)
        streamBuffer.update("", for: id)

        tasks[id] = Task {
            var text = ""
            var errorMessage: String?
            var lastPublish = Date.distantPast
            do {
                for try await snapshot in ChatService.streamReply(request) {
                    text = snapshot
                    if Date().timeIntervalSince(lastPublish) >= publishInterval {
                        streamBuffer.update(text, for: id)
                        lastPublish = Date()
                    }
                }
            } catch {
                // A stopped reply is not an error
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            finishReply(for: id, text: text, errorMessage: errorMessage, modelName: modelName)
        }
    }

    private func finishReply(for id: UUID, text: String, errorMessage: String?, modelName: String) {
        tasks[id] = nil
        generatingIDs.remove(id)
        streamBuffer.remove(id)

        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing to keep when the reply was stopped before its first word
        guard let index = index(of: id), !content.isEmpty || errorMessage != nil else { return }
        conversations[index].messages.append(
            ChatMessage(role: .assistant, content: content, model: modelName, errorMessage: errorMessage)
        )
        touch(at: index)
        if errorMessage == nil {
            generateTitleIfNeeded(for: id)
        }
    }

    private func generateTitleIfNeeded(for id: UUID) {
        let settings = AppSettings.shared
        guard settings.chatAutoGenerateTitles,
              let conversation = conversation(with: id), !conversation.hasFinalTitle,
              let firstMessage = conversation.messages.first(where: { $0.role == .user }) else { return }
        let model = conversation.model
        let config = ChatProviderConfig(settings: settings)

        Task {
            guard let title = try? await ChatService.generateTitle(for: firstMessage, model: model, config: config),
                  !title.isEmpty,
                  let index = index(of: id), !conversations[index].hasFinalTitle else { return }
            conversations[index].title = title
            conversations[index].hasFinalTitle = true
            persistence.save(conversations[index])
        }
    }

    // MARK: - Helpers

    private func index(of id: UUID) -> Int? {
        conversations.firstIndex { $0.id == id }
    }

    /// Marks a conversation as active now, saves it and moves it to the top.
    private func touch(at index: Int) {
        conversations[index].updatedAt = Date()
        persistence.save(conversations[index])
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }
}

/// One JSON file per conversation, written on a background queue.
nonisolated final class ChatPersistence: @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "com.speechtotype.chat-persistence", qos: .utility)

    init(directory: URL) {
        self.directory = directory
    }

    func loadAll() -> [ChatConversation] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file in
                guard let data = try? Data(contentsOf: file) else { return nil }
                return try? decoder.decode(ChatConversation.self, from: data)
            }
    }

    func save(_ conversation: ChatConversation) {
        let url = fileURL(for: conversation.id)
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(conversation) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func delete(_ id: UUID) {
        let url = fileURL(for: id)
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Blocks until all queued writes are done
    func flush() {
        queue.sync {}
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
