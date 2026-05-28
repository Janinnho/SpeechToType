//
//  RewriteView.swift
//  SpeechToType
//
//  Created on 28.05.26.
//

import SwiftUI
import AppKit

struct RewriteView: View {
    @ObservedObject var settings = AppSettings.shared
    @StateObject private var dictationRecorder = DictationRecorder()
    @State private var inputText: String = ""
    @State private var selectedMode: RewriteMode = .grammar
    @State private var customPrompt: String = ""
    @State private var dictatedPrompt: String = ""
    @State private var selectedTranslationLanguage: String = AppSettings.shared.defaultTranslationLanguage
    @State private var isProcessing = false
    @State private var isTranscribingDictation = false
    @State private var resultText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)

                                Text(formatDuration(dictationRecorder.recordingDuration))
                                    .font(.caption)
                                    .monospacedDigit()

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

            // Editable input text
            VStack(alignment: .leading, spacing: 4) {
                Text("rewriteInputLabel")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $inputText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(minHeight: 120)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)

                    if inputText.isEmpty {
                        Text("rewriteInputPlaceholder")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Editable result
            if !resultText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("rewriteResult")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextEditor(text: $resultText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(minHeight: 120)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            // Action buttons
            HStack {
                Button("rewriteClear") {
                    dictationRecorder.cancelRecording()
                    inputText = ""
                    resultText = ""
                    customPrompt = ""
                    dictatedPrompt = ""
                    errorMessage = nil
                }
                .disabled(inputText.isEmpty && resultText.isEmpty)

                Spacer()

                if !resultText.isEmpty {
                    Button("rewriteCopy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(resultText, forType: .string)
                    }
                    .keyboardShortcut("c", modifiers: .command)
                }

                Button("rewriteProcess") {
                    processText()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || isTranscribingDictation || !canProcess)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
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
        guard !inputText.isEmpty else { return false }
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

        let textToProcess = inputText

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
                    textToProcess,
                    mode: selectedMode,
                    customPrompt: prompt,
                    targetLanguage: selectedMode == .translate ? selectedTranslationLanguage : nil
                )

                await MainActor.run {
                    resultText = result
                    isProcessing = false

                    if AppSettings.shared.saveRewritesToHistory {
                        let record = TranscriptionRecord(
                            text: result,
                            duration: 0,
                            model: AppSettings.shared.selectedGPTModel.displayName,
                            recordType: .rewrite,
                            originalText: textToProcess
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
    RewriteView()
}
