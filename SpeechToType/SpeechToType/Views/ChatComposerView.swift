//
//  ChatComposerView.swift
//  SpeechToType
//
//  Message input used by the chat and the start page: multi-line text (Return sends,
//  Shift-Return adds a line break), attachments via button, paste or drag & drop,
//  dictation with the configured speech model, and the model picker.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ChatComposerView: View {
    @Binding var draft: ChatDraft
    let model: ChatModelSelection
    var isGenerating = false
    var placeholder: LocalizedStringKey = "chatInputPlaceholder"
    let onSelectModel: (ChatModelSelection) -> Void
    let onSend: () -> Void
    var onStop: () -> Void = {}

    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var dictationRecorder = DictationRecorder()
    @State private var isTranscribing = false
    @State private var showingFileImporter = false
    @State private var pendingImports = 0
    @State private var isDropTargeted = false
    @State private var errorMessage: String?

    private var canSend: Bool {
        !draft.isEmpty && !isGenerating && pendingImports == 0 && !dictationRecorder.isRecording && !isTranscribing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                if !draft.attachments.isEmpty || pendingImports > 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(draft.attachments) { attachment in
                                AttachmentChip(attachment: attachment) { remove(attachment) }
                            }
                            if pendingImports > 0 {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                }

                ZStack(alignment: .topLeading) {
                    ChatInputTextView(
                        text: $draft.text,
                        onSubmit: send,
                        onPasteFiles: importFiles,
                        onPasteImage: importImageData
                    )
                    if draft.text.isEmpty {
                        Text(placeholder)
                            .font(.system(size: ChatInputTextView.fontSize))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                }

                HStack(spacing: 14) {
                    Button { showingFileImporter = true } label: {
                        Image(systemName: "paperclip")
                    }
                    .help("chatAttachFiles")
                    .disabled(draft.attachments.count >= ChatAttachmentStore.maxAttachmentsPerMessage)

                    dictationButton

                    ChatModelPicker(selection: model, onSelect: onSelectModel)

                    Spacer()

                    if isGenerating {
                        Button(action: onStop) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .help("chatStop")
                    } else {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .disabled(!canSend)
                        .help("chatSend")
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 6)
            } else if !ChatModelCatalog.isConfigured(model.provider, settings: settings) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(String(format: String(localized: "chatProviderNotConfigured %@"), model.provider.displayName))
                    SettingsLink {
                        Text("chatOpenSettings")
                    }
                    .buttonStyle(.link)
                }
                .font(.caption)
                .padding(.horizontal, 6)
            }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                importFiles(urls)
            }
        }
        .onDisappear {
            dictationRecorder.cancelRecording()
        }
    }

    // MARK: - Sending

    private func send() {
        guard canSend else { return }
        errorMessage = nil
        onSend()
    }

    // MARK: - Dictation

    @ViewBuilder
    private var dictationButton: some View {
        if isTranscribing {
            ProgressView()
                .controlSize(.small)
                .help("transcribing")
        } else if dictationRecorder.isRecording {
            Button(action: stopDictation) {
                HStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                        .foregroundColor(.red)
                    Text(formatDuration(dictationRecorder.recordingDuration))
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            .help("chatStopDictation")
        } else {
            Button(action: startDictation) {
                Image(systemName: "mic")
            }
            .help("chatDictate")
        }
    }

    private func startDictation() {
        errorMessage = nil
        do {
            try dictationRecorder.startRecording()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopDictation() {
        let duration = dictationRecorder.recordingDuration
        guard let audioURL = dictationRecorder.stopRecording() else { return }
        guard duration >= 0.5 else {
            dictationRecorder.cleanupRecording(at: audioURL)
            return
        }

        isTranscribing = true
        Task {
            do {
                let text = try await OpenAIService.shared.transcribe(
                    audioURL: audioURL,
                    model: AppSettings.shared.selectedModel
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    let needsSpace = !draft.text.isEmpty && !draft.text.hasSuffix(" ") && !draft.text.hasSuffix("\n")
                    draft.text += (needsSpace ? " " : "") + text
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isTranscribing = false
            dictationRecorder.cleanupRecording(at: audioURL)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }

    // MARK: - Attachments

    private func importFiles(_ urls: [URL]) {
        errorMessage = nil
        let room = ChatAttachmentStore.maxAttachmentsPerMessage - draft.attachments.count - pendingImports
        if urls.count > room {
            errorMessage = String(format: String(localized: "chatAttachmentLimit %lld"), ChatAttachmentStore.maxAttachmentsPerMessage)
        }
        for url in urls.prefix(max(room, 0)) {
            runImport { try ChatAttachmentStore.importFile(at: url) }
        }
    }

    private func importImageData(_ data: Data) {
        errorMessage = nil
        guard draft.attachments.count + pendingImports < ChatAttachmentStore.maxAttachmentsPerMessage else {
            errorMessage = String(format: String(localized: "chatAttachmentLimit %lld"), ChatAttachmentStore.maxAttachmentsPerMessage)
            return
        }
        runImport { try ChatAttachmentStore.importImageData(data) }
    }

    /// Imports off the main thread (images get re-encoded) and adds the result to the draft.
    private func runImport(_ work: @escaping @Sendable () throws -> ChatAttachment) {
        pendingImports += 1
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try work() }
            }.value
            pendingImports -= 1
            switch result {
            case .success(let attachment):
                draft.attachments.append(attachment)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ attachment: ChatAttachment) {
        draft.attachments.removeAll { $0.id == attachment.id }
        ChatAttachmentStore.delete([attachment])
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    importFiles([url])
                }
            }
        }
        return true
    }
}

// MARK: - Text input

/// NSTextView-based input: Return sends, Shift/Option-Return inserts a line break, and
/// pasted or dropped files and images become attachments. Grows with its content up to
/// a maximum height, then scrolls. Takes the keyboard focus when it appears.
struct ChatInputTextView: NSViewRepresentable {
    static let fontSize: CGFloat = 14
    private static let maxHeight: CGFloat = 200

    @Binding var text: String
    var onSubmit: () -> Void
    var onPasteFiles: ([URL]) -> Void
    var onPasteImage: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ComposerTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: Self.fontSize)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.focusWhenInWindow = true

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? ComposerTextView else { return }
        textView.onPasteFiles = onPasteFiles
        textView.onPasteImage = onPasteImage
        // External changes (cleared after sending, dictated text appended)
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        // Measure one extra character so an empty text or a trailing line break keeps its line
        let measured = text.isEmpty || text.hasSuffix("\n") ? text + " " : text
        let bounds = (measured as NSString).boundingRect(
            with: NSSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: Self.fontSize)]
        )
        return CGSize(width: width, height: min(ceil(bounds.height), Self.maxHeight))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInputTextView

        init(parent: ChatInputTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onSubmit()
            }
            return true
        }
    }
}

final class ComposerTextView: NSTextView {
    var onPasteFiles: (([URL]) -> Void)?
    var onPasteImage: ((Data) -> Void)?
    /// Become first responder as soon as the view is in a window
    var focusWhenInWindow = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusWhenInWindow, let window else { return }
        focusWhenInWindow = false
        DispatchQueue.main.async {
            window.makeFirstResponder(self)
        }
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let urls = Self.fileURLs(on: pasteboard)
        if !urls.isEmpty {
            onPasteFiles?(urls)
            return
        }
        // Screenshots and copied images — but not rich text that also carries an image rendition
        if pasteboard.string(forType: .string) == nil,
           let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            onPasteImage?(data)
            return
        }
        super.paste(sender)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.fileURL]
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURLs(on: sender.draggingPasteboard).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURLs(on: sender.draggingPasteboard).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(on: sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onPasteFiles?(urls)
        return true
    }

    private static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}
