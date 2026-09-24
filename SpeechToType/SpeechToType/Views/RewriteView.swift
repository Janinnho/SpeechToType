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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("rewrite", subtitle: "rewriteSubtitle")

                // Mode and its options
                VStack(alignment: .leading, spacing: 14) {
                    Label("rewriteSelectMode", systemImage: "slider.horizontal.3")
                        .font(.headline)

                    Picker("", selection: $selectedMode) {
                        ForEach(RewriteMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: selectedMode) { _, newMode in
                        if newMode != .dictate {
                            dictatedPrompt = ""
                            dictationRecorder.cancelRecording()
                        }
                    }

                    modeOptions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(padding: 20, cornerRadius: 24)

                // Text to process
                VStack(alignment: .leading, spacing: 10) {
                    Label("rewriteInputLabel", systemImage: "text.alignleft")
                        .font(.headline)
                    editor(text: $inputText, placeholder: "rewriteInputPlaceholder")
                }
                .glassCard(padding: 20, cornerRadius: 24)

                if !resultText.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("rewriteResult", systemImage: "sparkles")
                            .font(.headline)
                        editor(text: $resultText, placeholder: nil)
                    }
                    .glassCard(padding: 20, cornerRadius: 24, tint: Color.green.opacity(0.12))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                actions
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: resultText.isEmpty)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var modeOptions: some View {
        switch selectedMode {
        case .dictate:
            VStack(alignment: .leading, spacing: 8) {
                Text("rewriteDictateInstructions")
                    .font(.callout)
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
            VStack(alignment: .leading, spacing: 8) {
                Text("rewriteCustomPromptLabel")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField(String(localized: "rewriteCustomPromptPlaceholder"), text: $customPrompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...5)
                    .padding(10)
                    .insetField(cornerRadius: 12)
            }
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
                        .font(.callout.monospacedDigit())
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color.red.opacity(0.5))
                            .frame(width: geometry.size.width * CGFloat(dictationRecorder.audioLevel))
                    }
                    .frame(height: 5)
                    .background(Color.primary.opacity(0.1), in: Capsule())
                }
                .padding(10)
                .insetField(cornerRadius: 12)

                Button(action: stopDictationRecording) {
                    Label("chatStopDictation", systemImage: "stop.fill")
                }
                .buttonStyle(.glass)
                .tint(.red)
            } else if isTranscribingDictation {
                ProgressView()
                    .controlSize(.small)
                Text("transcribing")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !dictatedPrompt.isEmpty {
                Text(dictatedPrompt)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetField(cornerRadius: 12)

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

    private func editor(text: Binding<String>, placeholder: LocalizedStringKey?) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 130)

            if let placeholder, text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(10)
        .insetField(cornerRadius: 14)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                dictationRecorder.cancelRecording()
                inputText = ""
                resultText = ""
                customPrompt = ""
                dictatedPrompt = ""
                errorMessage = nil
            } label: {
                Label("rewriteClear", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.glass)
            .disabled(inputText.isEmpty && resultText.isEmpty)

            Spacer()

            if !resultText.isEmpty {
                CopyButton(text: resultText, title: "rewriteCopy")
                    .buttonStyle(.glass)
            }

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
                .padding(.horizontal, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isProcessing || isTranscribingDictation || !canProcess)
            .keyboardShortcut(.return)
        }
    }

    // MARK: - Logic

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
                            model: AppSettings.shared.rewriteModelSelection.displayName,
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
