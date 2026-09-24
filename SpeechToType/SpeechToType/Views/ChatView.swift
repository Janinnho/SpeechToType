//
//  ChatView.swift
//  SpeechToType
//
//  The "Chat" tab: list of conversations on the left, the selected conversation (or a
//  new chat) on the right.
//

import SwiftUI

struct ChatView: View {
    @ObservedObject private var manager = ChatManager.shared

    var body: some View {
        HStack(spacing: 0) {
            ChatListView()
                .frame(width: 240)

            Divider()

            // A fresh view per conversation: scroll position and draft belong to it
            ChatConversationView(conversationID: manager.selectedConversationID)
                .id(manager.selectedConversationID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Conversation list

private struct ChatListSection: Identifiable {
    let title: String
    let conversations: [ChatConversation]
    var id: String { title }
}

struct ChatListView: View {
    @ObservedObject private var manager = ChatManager.shared
    @State private var searchText = ""
    @State private var renameTarget: ChatConversation?
    @State private var renameText = ""
    @State private var deleteTarget: ChatConversation?

    private var filteredConversations: [ChatConversation] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return manager.conversations }
        return manager.conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query)
                || conversation.messages.contains { $0.content.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Grouped like ChatGPT: today, yesterday, last 7 days, last 30 days, older
    private var sections: [ChatListSection] {
        let calendar = Calendar.current
        let now = Date()
        let titles = [
            String(localized: "chatSectionToday"),
            String(localized: "chatSectionYesterday"),
            String(localized: "chatSectionLast7Days"),
            String(localized: "chatSectionLast30Days"),
            String(localized: "chatSectionOlder")
        ]
        var buckets: [[ChatConversation]] = Array(repeating: [], count: titles.count)
        for conversation in filteredConversations {
            let date = conversation.updatedAt
            let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            let bucket: Int
            if calendar.isDateInToday(date) {
                bucket = 0
            } else if calendar.isDateInYesterday(date) {
                bucket = 1
            } else if days < 7 {
                bucket = 2
            } else if days < 30 {
                bucket = 3
            } else {
                bucket = 4
            }
            buckets[bucket].append(conversation)
        }
        return zip(titles, buckets)
            .filter { !$0.1.isEmpty }
            .map { ChatListSection(title: $0.0, conversations: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("chat")
                    .font(.headline)
                Spacer()
                Button {
                    manager.selectedConversationID = nil
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("chatNew")
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(String(localized: "search"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            if filteredConversations.isEmpty {
                Text(searchText.isEmpty ? "chatNoConversations" : "noResults")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $manager.selectedConversationID) {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.conversations) { conversation in
                                row(conversation)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .alert("chatRenameTitle", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField(String(localized: "chatRenamePlaceholder"), text: $renameText)
            Button("ok") {
                if let renameTarget {
                    manager.rename(renameTarget.id, to: renameText)
                }
            }
            Button("cancel", role: .cancel) {}
        }
        .alert("chatDeleteTitle", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), presenting: deleteTarget) { target in
            Button("delete", role: .destructive) {
                manager.delete(target.id)
            }
            Button("cancel", role: .cancel) {}
        } message: { target in
            Text(String(format: String(localized: "chatDeleteMessage %@"), target.title))
        }
    }

    private func row(_ conversation: ChatConversation) -> some View {
        HStack(spacing: 6) {
            Text(conversation.title)
                .lineLimit(1)
            Spacer(minLength: 0)
            if manager.isGenerating(conversation.id) {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .tag(conversation.id)
        .contextMenu {
            Button {
                renameText = conversation.title
                renameTarget = conversation
            } label: {
                Label("chatRename", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                deleteTarget = conversation
            } label: {
                Label("delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Conversation

/// Measurements used to tell scrolling apart from content that grows while streaming
private struct ScrollMetrics: Equatable {
    var offset: CGFloat
    var visibleHeight: CGFloat
    var contentHeight: CGFloat

    var isNearBottom: Bool {
        offset + visibleHeight >= contentHeight - 60
    }
}

struct ChatConversationView: View {
    /// nil = a new chat that starts with the first message
    let conversationID: UUID?

    @ObservedObject private var manager = ChatManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var draft = ChatDraft()
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var isNearBottom = true

    private var conversation: ChatConversation? {
        conversationID.flatMap { manager.conversation(with: $0) }
    }

    private var isGenerating: Bool {
        conversationID.map { manager.isGenerating($0) } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(conversation?.title ?? String(localized: "chatNew"))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 44)

            Divider()

            if let conversation, !conversation.messages.isEmpty {
                messageList(conversation)
            } else {
                emptyState
            }

            ChatComposerView(
                draft: $draft,
                model: conversation?.model ?? settings.chatModel,
                isGenerating: isGenerating,
                onSelectModel: { manager.setModel($0, for: conversationID) },
                onSend: send,
                onStop: {
                    if let conversationID {
                        manager.stop(conversationID)
                    }
                }
            )
            .frame(maxWidth: 760)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .onAppear {
            draft = manager.draft(for: conversationID)
        }
        .onDisappear {
            manager.storeDraft(draft, for: conversationID)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("chatEmptyTitle")
                .font(.title2)
                .fontWeight(.semibold)
            Text("chatEmptySubtitle")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageList(_ conversation: ChatConversation) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(conversation.messages) { message in
                    ChatMessageView(
                        message: message,
                        isLast: message.id == conversation.messages.last?.id && !isGenerating,
                        onRegenerate: { manager.regenerate(conversation.id) }
                    )
                }

                if isGenerating {
                    StreamingMessageView(
                        conversationID: conversation.id,
                        buffer: manager.streamBuffer,
                        onTextChange: followBottom
                    )
                } else if conversation.messages.last?.role == .user {
                    // The reply is missing (stopped before the first word, or the app quit)
                    Button {
                        manager.regenerate(conversation.id)
                    } label: {
                        Label("chatGenerateReply", systemImage: "arrow.clockwise")
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offset: geometry.contentOffset.y,
                visibleHeight: geometry.containerSize.height,
                contentHeight: geometry.contentSize.height
            )
        } action: { old, new in
            // Content growing underneath (a streaming reply) is not the user scrolling away
            guard new.offset != old.offset || new.visibleHeight != old.visibleHeight else { return }
            isNearBottom = new.isNearBottom
        }
        .onChange(of: conversation.messages.count) {
            followBottom()
        }
        .overlay(alignment: .bottom) {
            if !isNearBottom {
                Button {
                    withAnimation {
                        scrollPosition.scrollTo(edge: .bottom)
                    }
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.body.weight(.semibold))
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor)))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
                .help("chatScrollToBottom")
            }
        }
    }

    /// Keeps the newest text in view, unless the user scrolled up to read.
    private func followBottom() {
        guard isNearBottom else { return }
        scrollPosition.scrollTo(edge: .bottom)
    }

    private func send() {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = draft.attachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        draft = ChatDraft()
        isNearBottom = true

        if let conversationID {
            manager.send(text: text, attachments: attachments, to: conversationID)
        } else {
            manager.startConversation(text: text, attachments: attachments)
        }
    }
}
