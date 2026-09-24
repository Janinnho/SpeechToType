//
//  TextRewritePopupWindow.swift
//  SpeechToType
//
//  Created on 22.01.26.
//

import SwiftUI
import AppKit
import Combine
import AVFoundation

class TextRewriteWindowController: NSObject, ObservableObject {
    static let shared = TextRewriteWindowController()

    private var popupWindow: NSWindow?
    @Published var selectedText: String = ""
    @Published var isVisible = false

    private override init() {
        super.init()
    }

    func show(with selectedText: String) {
        self.selectedText = selectedText

        // Close existing window if any
        popupWindow?.close()

        let contentView = TextRewritePopupView(controller: self)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = String(localized: "rewriteTitle")
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible

        popupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }

    func hide() {
        popupWindow?.close()
        popupWindow = nil
        isVisible = false
    }

    func insertResult(_ text: String) {
        hide()
        // Insert the rewritten text
        TextInputService.shared.insertText(text)
    }

    func showNoTextSelectedAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "rewriteErrorNoText")
        alert.informativeText = String(localized: "rewriteSelectTextFirst")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "ok"))
        alert.runModal()
    }
}

// MARK: - Voice Recorder for Dictation Mode
class DictationRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var durationTimer: Timer?
    private var levelTimer: Timer?
    private var recordingStartTime: Date?

    func startRecording() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "dictation_\(UUID().uuidString).m4a"
        recordingURL = tempDir.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()

        isRecording = true
        recordingStartTime = Date()
        recordingDuration = 0
        audioLevel = 0.0

        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateAudioLevel()
        }
    }

    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        let normalizedLevel = max(0, (level + 50) / 50)

        Task { @MainActor in
            self.audioLevel = normalizedLevel
        }
    }

    func stopRecording() -> URL? {
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        guard let recorder = audioRecorder, recorder.isRecording else {
            return nil
        }

        recorder.stop()
        isRecording = false
        audioLevel = 0.0

        return recordingURL
    }

    func cancelRecording() {
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        recordingDuration = 0
        audioLevel = 0.0

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    func cleanupRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

struct TextRewritePopupView: View {
    @ObservedObject var controller: TextRewriteWindowController
    @ObservedObject var settings = AppSettings.shared
    @StateObject private var dictationRecorder = DictationRecorder()
    @State private var selectedMode: RewriteMode = .dictate
    @State private var customPrompt: String = ""
    @State private var dictatedPrompt: String = ""
    @State private var selectedTranslationLanguage: String = AppSettings.shared.defaultTranslationLanguage
    @State private var isProcessing = false
    @State private var isTranscribingDictation = false
    @State private var resultText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mode and its options
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $selectedMode) {
                    ForEach(RewriteMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: selectedMode) { _, newMode in
                    // Reset dictated prompt when switching modes
                    if newMode != .dictate {
                        dictatedPrompt = ""
                        dictationRecorder.cancelRecording()
                    }
                }

                modeOptions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 14, cornerRadius: 20)

            // Selected text preview
            textCard(title: "rewriteSelectedText", icon: "text.quote", text: controller.selectedText, height: 70)

            // Result preview (if available)
            if !resultText.isEmpty {
                textCard(title: "rewriteResult", icon: "sparkles", text: resultText, height: 90, tint: Color.green.opacity(0.12))
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Spacer(minLength: 0)

            // Action buttons
            HStack(spacing: 10) {
                Button("cancel") {
                    dictationRecorder.cancelRecording()
                    controller.hide()
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.escape)

                Spacer()

                if !resultText.isEmpty {
                    Button("rewriteCopy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(resultText, forType: .string)
                        controller.hide()
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut("c", modifiers: .command)

                    Button {
                        controller.insertResult(resultText)
                    } label: {
                        Label("rewriteInsert", systemImage: "text.cursor")
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return)
                } else {
                    Button(action: processText) {
                        HStack(spacing: 6) {
                            if isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                                Text("rewriteProcessing")
                            } else {
                                Image(systemName: "sparkles")
                                Text("rewriteProcess")
                            }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isProcessing || isTranscribingDictation || !canProcess)
                    .keyboardShortcut(.return)
                }
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 18)
        .padding(.top, 36)
        .padding(.bottom, 18)
        .frame(width: 560, height: 520)
        .background(AppBackground())
    }

    // MARK: - Sections

    @ViewBuilder
    private var modeOptions: some View {
        switch selectedMode {
        case .dictate:
            VStack(alignment: .leading, spacing: 6) {
                Text("rewriteDictateInstructions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                dictationControl
            }
        case .translate:
            HStack {
                Text("rewriteTranslateTo")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedTranslationLanguage) {
                    ForEach(AppSettings.translationLanguages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        case .custom:
            TextField(String(localized: "rewriteCustomPromptPlaceholder"), text: $customPrompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(10)
                .insetField(cornerRadius: 12)
        case .grammar, .elaborate:
            EmptyView()
        }
    }

    @ViewBuilder
    private var dictationControl: some View {
        HStack(spacing: 10) {
            if dictationRecorder.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Text(formatDuration(dictationRecorder.recordingDuration))
                        .font(.caption.monospacedDigit())
                    // Audio level indicator
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color.red.opacity(0.5))
                            .frame(width: geometry.size.width * CGFloat(dictationRecorder.audioLevel))
                    }
                    .frame(height: 5)
                    .background(Color.primary.opacity(0.1), in: Capsule())
                }
                .padding(8)
                .insetField(cornerRadius: 10)

                Button(action: stopDictationRecording) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.red)
            } else if isTranscribingDictation {
                ProgressView()
                    .controlSize(.small)
                Text("transcribing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !dictatedPrompt.isEmpty {
                // Show transcribed prompt
                Text(dictatedPrompt)
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetField(cornerRadius: 10)

                Button {
                    dictatedPrompt = ""
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)

                Button(action: startDictationRecording) {
                    Image(systemName: "mic.fill")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            } else {
                Button(action: startDictationRecording) {
                    Label("rewriteStartDictation", systemImage: "mic.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
            }
        }
    }

    private func textCard(title: LocalizedStringKey, icon: String, text: String, height: CGFloat, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
        }
        .glassCard(padding: 14, cornerRadius: 20, tint: tint)
    }

    private var canProcess: Bool {
        switch selectedMode {
        case .dictate:
            return !dictatedPrompt.isEmpty
        case .custom:
            return !customPrompt.isEmpty
        case .grammar, .elaborate, .translate:
            return true
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d.%d", seconds, tenths)
    }

    private func startDictationRecording() {
        do {
            try dictationRecorder.startRecording()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopDictationRecording() {
        guard let audioURL = dictationRecorder.stopRecording() else { return }

        isTranscribingDictation = true

        Task {
            do {
                let transcribedText = try await OpenAIService.shared.transcribe(
                    audioURL: audioURL,
                    model: AppSettings.shared.selectedModel
                )

                await MainActor.run {
                    dictatedPrompt = transcribedText
                    isTranscribingDictation = false
                }

                dictationRecorder.cleanupRecording(at: audioURL)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isTranscribingDictation = false
                }
                dictationRecorder.cleanupRecording(at: audioURL)
            }
        }
    }

    private func processText() {
        isProcessing = true
        errorMessage = nil
        resultText = ""

        Task {
            do {
                let prompt: String?
                switch selectedMode {
                case .dictate:
                    prompt = dictatedPrompt
                case .custom:
                    prompt = customPrompt
                default:
                    prompt = nil
                }

                let result = try await TextRewriteService.shared.rewriteText(
                    controller.selectedText,
                    mode: selectedMode,
                    customPrompt: prompt,
                    targetLanguage: selectedMode == .translate ? selectedTranslationLanguage : nil
                )

                await MainActor.run {
                    resultText = result
                    isProcessing = false

                    // Save to history if enabled
                    if AppSettings.shared.saveRewritesToHistory {
                        let record = TranscriptionRecord(
                            text: result,
                            duration: 0,
                            model: AppSettings.shared.rewriteModelSelection.displayName,
                            recordType: .rewrite,
                            originalText: controller.selectedText
                        )
                        TranscriptionHistoryManager.shared.addRecord(record)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

#Preview {
    TextRewritePopupView(controller: TextRewriteWindowController.shared)
}
