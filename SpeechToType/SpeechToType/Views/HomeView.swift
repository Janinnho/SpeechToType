//
//  HomeView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//
//  Start page: greeting, dictation status with the record button and the shortcuts,
//  statistics, the latest dictations and chats, and a message field that starts a new chat.
//

import SwiftUI
import AppKit

struct HomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var historyManager = TranscriptionHistoryManager.shared
    @ObservedObject private var chatManager = ChatManager.shared
    @ObservedObject private var navigation = AppNavigation.shared
    @State private var draft = ChatDraft()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                greeting

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        DictationStatusCard()
                        statistics
                            .frame(width: 350)
                    }
                    VStack(spacing: 16) {
                        DictationStatusCard()
                        statistics
                    }
                }

                recentSection
            }
            .frame(maxWidth: 1000, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .safeAreaInset(edge: .bottom) {
            ChatComposerView(
                draft: $draft,
                model: settings.chatModel,
                placeholder: "startChatPlaceholder",
                onSelectModel: { ChatManager.shared.setModel($0, for: nil) },
                onSend: startChat
            )
            .frame(maxWidth: 720)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        // Text from the record button (target "message field"); also picks up text that
        // arrived while another page was open
        .onChange(of: navigation.pendingComposerDictation, initial: true) { _, text in
            guard let text, !text.isEmpty else { return }
            navigation.pendingComposerDictation = nil
            appendDictation(text)
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingText)
                .font(.system(size: 34, weight: .bold))
            Text("homeSubtitle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case 5..<11: greeting = String(localized: "greetingMorning")
        case 11..<18: greeting = String(localized: "greetingDay")
        default: greeting = String(localized: "greetingEvening")
        }
        let firstName = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return firstName.isEmpty ? greeting : "\(greeting), \(firstName)"
    }

    // MARK: - Statistics

    private var statistics: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(
                    icon: "text.word.spacing",
                    value: historyManager.totalWordsTranscribed.formatted(),
                    label: "wordsTranscribed",
                    tint: .blue
                )
                StatTile(
                    icon: "waveform",
                    value: formatDuration(historyManager.totalRecordingDuration),
                    label: "transcribedTime",
                    tint: .purple
                )
            }
            GridRow {
                StatTile(
                    icon: "number",
                    value: formatTokens(historyManager.totalTokensUsed),
                    label: "tokensUsed",
                    tint: .teal
                )
                StatTile(
                    icon: "clock.arrow.circlepath",
                    value: Int(historyManager.estimatedMinutesSaved).formatted(),
                    label: "minutesSaved",
                    tint: .orange
                )
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private func formatTokens(_ tokens: Int) -> String {
        tokens >= 1000 ? String(format: "%.1fk", Double(tokens) / 1000.0) : "\(tokens)"
    }

    // MARK: - Recent activity

    private enum RecentItem: Identifiable {
        case record(TranscriptionRecord)
        case chat(ChatConversation)

        var id: UUID {
            switch self {
            case .record(let record): return record.id
            case .chat(let conversation): return conversation.id
            }
        }

        var date: Date {
            switch self {
            case .record(let record): return record.date
            case .chat(let conversation): return conversation.updatedAt
            }
        }
    }

    private var recentItems: [RecentItem] {
        let records = historyManager.records.prefix(6).map { RecentItem.record($0) }
        let chats = chatManager.conversations.prefix(6).map { RecentItem.chat($0) }
        return Array((records + chats).sorted { $0.date > $1.date }.prefix(6))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("homeRecent")

            let items = recentItems
            if items.isEmpty {
                HStack(spacing: 14) {
                    IconBadge(systemName: "sparkles", color: .indigo, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("homeNoActivityTitle")
                            .font(.headline)
                        Text(String(format: String(localized: "homeNoActivityMessage %@"), settings.directDictationShortcut.displayString))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .glassCard(padding: 16, cornerRadius: 20)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(items) { item in
                        recentCard(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentCard(_ item: RecentItem) -> some View {
        switch item {
        case .record(let record):
            RecentActivityCard(
                icon: record.recordType == .transcription ? "waveform" : "wand.and.stars",
                color: record.recordType == .transcription ? .blue : .orange,
                kind: record.recordType == .transcription ? "transcription" : "rewrite",
                title: record.text,
                date: record.date
            ) {
                AppNavigation.shared.openHistory(record.id)
            }
        case .chat(let conversation):
            RecentActivityCard(
                icon: "bubble.left.and.bubble.right.fill",
                color: .green,
                kind: "chat",
                title: conversation.title,
                date: conversation.updatedAt
            ) {
                AppNavigation.shared.openChat(conversation.id)
            }
        }
    }

    // MARK: - Chat

    private func startChat() {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draft.attachments.isEmpty else { return }
        ChatManager.shared.startConversation(text: text, attachments: draft.attachments)
        draft = ChatDraft()
        AppNavigation.shared.selectedTab = .chat
    }

    private func appendDictation(_ text: String) {
        if draft.text.isEmpty || draft.text.last?.isWhitespace == true {
            draft.text += text
        } else {
            draft.text += " " + text
        }
    }
}

// MARK: - Dictation status

/// Big card with the record button, the current status, the active speech model and the
/// keyboard shortcuts.
struct DictationStatusCard: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var audioRecorder = AudioRecorder.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var overlay = RecordingOverlayWindowController.shared

    private var phase: DictationOrb.Phase {
        if hotkeyManager.isRecording { return .recording }
        if overlay.isVisible && overlay.mode == .processing { return .processing }
        return hotkeyManager.isListening ? .idle : .inactive
    }

    /// The model that is used for the next dictation
    private var speechModelName: String {
        switch settings.speechModelProvider {
        case .openAI: return settings.selectedModel.displayName
        case .gemini: return settings.selectedGeminiSpeechModel.displayName
        default: return settings.speechModelDisplayName
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            DictationRecordButton(phase: phase, level: audioRecorder.audioLevel)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hotkeyManager.compactStatusMessage)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        InfoChip(icon: "waveform", text: speechModelName)
                        if let start = hotkeyManager.recordingStartedAt {
                            TimelineView(.periodic(from: start, by: 1)) { context in
                                InfoChip(icon: "record.circle", text: formatDuration(context.date.timeIntervalSince(start)))
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow(settings.directDictationShortcut.displayString, label: "homeHoldToDictate")
                    shortcutRow(settings.continuousRecordingShortcut.displayString + " ×2", label: "homeDoubleTapContinuous")
                    if settings.textRewriteEnabled {
                        shortcutRow(settings.rewriteShortcut.displayString, label: "homeRewriteShortcut")
                    }
                }

                if let error = hotkeyManager.lastError {
                    notice(icon: "exclamationmark.triangle.fill", color: .orange, text: error)
                } else if !settings.isConfigured {
                    notice(icon: "exclamationmark.triangle.fill", color: .yellow, text: String(localized: "apiKeyNotConfigured"))
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 20, cornerRadius: 26)
    }

    private func shortcutRow(_ keys: String, label: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            KeyCap(text: keys)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func notice(icon: String, color: Color, text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}

// MARK: - Record button

/// The orb on the start page doubles as a record button: a click records until the next
/// click, holding it records until it is let go — like the dictation shortcut. Where the
/// text goes is set in the settings (`AppSettings.buttonDictationTarget`).
struct DictationRecordButton: View {
    let phase: DictationOrb.Phase
    let level: Float

    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @State private var isPressed = false
    @State private var isHovering = false
    /// Start of the current press, if it started a recording (a press on a running one stops it)
    @State private var pressStart: Date?
    /// The current press has lasted long enough to count as holding
    @State private var isHolding = false
    @State private var holdTask: Task<Void, Never>?

    /// Shorter presses are clicks, longer ones record only while the button is held
    private static let holdThreshold: TimeInterval = 0.35

    var body: some View {
        VStack(spacing: 2) {
            DictationOrb(phase: phase, level: level, size: 64)
                .frame(width: 110, height: 110)
                .contentShape(Circle().inset(by: 12))
                .scaleEffect(isPressed ? 0.93 : (isHovering ? 1.04 : 1))
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isPressed)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .onHover { isHovering = $0 }
                .pointerStyle(.link)
                .gesture(pressGesture)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hotkeyManager.isRecording ? Text("orbStopRecording") : Text("orbStartRecording"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggleRecording() }
        .help("orbHelp")
    }

    private var caption: LocalizedStringKey {
        guard hotkeyManager.isRecording else { return "orbCaptionIdle" }
        return isHolding ? "orbCaptionRelease" : "orbCaptionStop"
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressed else { return }
                isPressed = true
                pressBegan()
            }
            .onEnded { _ in
                isPressed = false
                pressEnded()
            }
    }

    private func pressBegan() {
        guard !hotkeyManager.isRecording else {
            pressStart = nil
            hotkeyManager.stopCurrentRecording()
            return
        }
        pressStart = Date()
        hotkeyManager.startButtonRecording()
        holdTask = Task {
            try? await Task.sleep(for: .seconds(Self.holdThreshold))
            if !Task.isCancelled { isHolding = true }
        }
    }

    private func pressEnded() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        guard let start = pressStart else { return }
        pressStart = nil
        if Date().timeIntervalSince(start) < Self.holdThreshold {
            hotkeyManager.continueButtonRecording()
        } else {
            hotkeyManager.stopCurrentRecording()
        }
    }

    /// Accessibility action: starts a recording that runs until the next activation
    private func toggleRecording() {
        if hotkeyManager.isRecording {
            hotkeyManager.stopCurrentRecording()
        } else {
            hotkeyManager.startButtonRecording()
            hotkeyManager.continueButtonRecording()
        }
    }
}

// MARK: - Recent activity card

/// A dictation, rewrite or chat on the start page; opens it on click.
struct RecentActivityCard: View {
    let icon: String
    let color: Color
    let kind: LocalizedStringKey
    let title: String
    let date: Date
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    IconBadge(systemName: icon, color: color, size: 22)
                    Text(kind)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(title)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .scaleEffect(isHovering ? 1.015 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

extension HotkeyManager {
    /// Status for places that list the shortcuts anyway: "ready — hold the key to record"
    /// shortens to "ready"
    var compactStatusMessage: String {
        statusMessage == String(localized: "readyHoldToRecord") ? String(localized: "ready") : statusMessage
    }
}
