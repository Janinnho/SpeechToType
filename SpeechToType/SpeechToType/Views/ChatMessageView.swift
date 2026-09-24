//
//  ChatMessageView.swift
//  SpeechToType
//
//  One message of a conversation: the user's messages as bubbles on the right,
//  replies as full-width Markdown with copy / regenerate actions.
//

import SwiftUI
import AppKit

struct ChatMessageView: View {
    let message: ChatMessage
    /// The conversation's last message gets the regenerate action and always shows its actions
    let isLast: Bool
    var onRegenerate: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        Group {
            switch message.role {
            case .user:
                userMessage
            case .assistant:
                assistantMessage
            }
        }
        .onHover { isHovering = $0 }
    }

    private var userMessage: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 6) {
                if !message.attachments.isEmpty {
                    MessageAttachmentsView(attachments: message.attachments)
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.tint(Color.accentColor.opacity(0.35)), in: .rect(cornerRadius: 20))
                    CopyButton(text: message.content)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .opacity(isHovering ? 1 : 0)
                }
            }
        }
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.content.isEmpty || message.errorMessage != nil {
                VStack(alignment: .leading, spacing: 10) {
                    if !message.content.isEmpty {
                        MarkdownView(text: message.content)
                    }
                    if let error = message.errorMessage {
                        ChatErrorView(message: error, onRetry: isLast ? onRegenerate : nil)
                    }
                }
                .glassCard(padding: 16, cornerRadius: 20)
            }

            HStack(spacing: 12) {
                if !message.content.isEmpty {
                    CopyButton(text: message.content)
                }
                if isLast {
                    Button(action: onRegenerate) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("chatRegenerate")
                }
                if let model = message.model {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(isHovering || isLast ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The reply that is being generated right now. Observes the stream buffer on its
/// own so the rest of the conversation doesn't re-render for every chunk.
struct StreamingMessageView: View {
    let conversationID: UUID
    @ObservedObject var buffer: ChatStreamBuffer
    /// Called whenever new text arrived (used to keep the view scrolled to the bottom)
    var onTextChange: () -> Void = {}

    private var text: String {
        buffer.texts[conversationID] ?? ""
    }

    var body: some View {
        Group {
            if text.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("chatThinking")
                        .foregroundStyle(.secondary)
                }
                .glassCard(padding: 14, cornerRadius: 18)
            } else {
                MarkdownView(text: text)
                    .glassCard(padding: 16, cornerRadius: 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: text) {
            onTextChange()
        }
    }
}

struct ChatErrorView: View {
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onRetry {
                Button("chatRetry", action: onRetry)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Attachments

/// Attachments of a sent message: image previews and file chips. Click opens the file.
private struct MessageAttachmentsView: View {
    let attachments: [ChatAttachment]

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(attachments.filter { $0.kind == .image }) { attachment in
                AttachmentThumbnail(attachment: attachment)
                    .frame(maxWidth: 240, maxHeight: 240)
                    .onTapGesture { NSWorkspace.shared.open(ChatAttachmentStore.url(for: attachment)) }
                    .help(attachment.fileName)
            }
            ForEach(attachments.filter { $0.kind != .image }) { attachment in
                AttachmentChip(attachment: attachment)
            }
        }
    }
}

/// Compact file chip, used in messages and in the composer (with a remove button).
struct AttachmentChip: View {
    let attachment: ChatAttachment
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            if attachment.kind == .image {
                AttachmentThumbnail(attachment: attachment, fill: true)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 32)
            }
            Text(attachment.fileName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160, alignment: .leading)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(ChatAttachmentStore.url(for: attachment)) }
        .help(attachment.fileName)
    }
}

struct AttachmentThumbnail: View {
    let attachment: ChatAttachment
    /// Fill (and crop) the frame instead of fitting the whole image
    var fill = false

    private static let cache = NSCache<NSString, NSImage>()
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Color.primary.opacity(0.06)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: fill ? 6 : 10, style: .continuous))
        .task(id: attachment.id) {
            let key = attachment.storedName as NSString
            if let cached = Self.cache.object(forKey: key) {
                image = cached
            } else if let loaded = NSImage(contentsOf: ChatAttachmentStore.url(for: attachment)) {
                Self.cache.setObject(loaded, forKey: key)
                image = loaded
            }
        }
    }
}
