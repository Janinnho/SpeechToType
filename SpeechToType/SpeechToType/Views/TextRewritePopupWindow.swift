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
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 450),
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
        VStack(spacing: 12) {
            // Mode selection
            VStack(alignment: .leading, spacing: 8) {
                Text("rewriteSelectMode")
                    .font(.headline)

                Picker("", selection: $selectedMode) {
                    ForEach(RewriteMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedMode) { _, newMode in
                    // Reset dictated prompt when switching modes
                    if newMode != .dictate {
                        dictatedPrompt = ""
                        dictationRecorder.cancelRecording()
                    }
                }
            }

            // Dictation input (for dictate mode)
            if selectedMode == .dictate {
                VStack(alignment: .leading, spacing: 4) {
                    Text("rewriteDictateInstructions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        if dictationRecorder.isRecording {
                            // Recording indicator
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)

                                Text(formatDuration(dictationRecorder.recordingDuration))
                                    .font(.caption)
                                    .monospacedDigit()

                                // Audio level indicator
                                GeometryReader { geometry in
                                    Rectangle()
                                        .fill(Color.red.opacity(0.3))
                                        .frame(width: geometry.size.width * CGFloat(dictationRecorder.audioLevel))
                                }
                                .frame(height: 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(2)
                            }
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)

                            Button(action: stopDictationRecording) {
                                Image(systemName: "stop.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                        } else if isTranscribingDictation {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("transcribing")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                        } else if !dictatedPrompt.isEmpty {
                            // Show transcribed prompt
                            Text(dictatedPrompt)
                                .font(.body)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(8)

                            Button(action: { dictatedPrompt = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)

                            Button(action: startDictationRecording) {
                                Image(systemName: "mic.fill")
                            }
                            .buttonStyle(.bordered)
                        } else {
                            // Start recording button
                            Button(action: startDictationRecording) {
                                HStack {
                                    Image(systemName: "mic.fill")
                                    Text("rewriteStartDictation")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                }
            }

            // Translation language picker (for translate mode)
            if selectedMode == .translate {
                HStack {
                    Text("rewriteTranslateTo")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedTranslationLanguage) {
                        ForEach(AppSettings.translationLanguages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 150)
                }
            }

            // Custom prompt field (only shown when custom mode is selected)
            if selectedMode == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    Text("rewriteCustomPromptLabel")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField(String(localized: "rewriteCustomPromptPlaceholder"), text: $customPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...5)
                }
            }

            // Selected text preview
            VStack(alignment: .leading, spacing: 4) {
                Text("rewriteSelectedText")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ScrollView {
                    Text(controller.selectedText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 60)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            }

            // Result preview (if available)
            if !resultText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("rewriteResult")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ScrollView {
                        Text(resultText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 60)
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            Spacer()

            // Action buttons
            HStack {
                Button("cancel") {
                    dictationRecorder.cancelRecording()
                    controller.hide()
                }
                .keyboardShortcut(.escape)

                Spacer()

                if !resultText.isEmpty {
                    Button("rewriteCopy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(resultText, forType: .string)
                        controller.hide()
                    }
                    .keyboardShortcut("c", modifiers: .command)

                    Button("rewriteInsert") {
                        controller.insertResult(resultText)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                } else {
                    Button("rewriteProcess") {
                        processText()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing || isTranscribingDictation || !canProcess)
                    .keyboardShortcut(.return)
                }
            }
        }
        .padding()
        .frame(width: 450, height: 450)
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("rewriteProcessing")
                            .foregroundColor(.white)
                            .padding(.top, 8)
                    }
                }
                .cornerRadius(12)
            }
        }
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
                            model: AppSettings.shared.selectedGPTModel.displayName,
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
