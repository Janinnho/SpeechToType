//
//  TextRewriteSettingsView.swift
//  SpeechToType
//
//  Settings pane: text rewriting (text processing) model configuration.
//

import SwiftUI
import FoundationModels

struct TextRewriteSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var showingTextProcessingAPIKey = false
    @State private var showingAnthropicAPIKey = false
    @State private var showingGeminiAPIKey = false
    @State private var ollamaModels: [String] = []
    @State private var isLoadingOllamaModels = false
    @State private var ollamaModelError: String?

    var body: some View {
        Form {
            Section {
                Toggle("textRewriteEnabled", isOn: $settings.textRewriteEnabled)

                if settings.textRewriteEnabled {
                    Toggle("dictionaryApplyRewrite", isOn: $settings.applyDictionaryToRewrite)

                    Picker("textProcessingProviderPicker", selection: $settings.textProcessingProvider) {
                        ForEach(TextProcessingProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    switch settings.textProcessingProvider {
                    case .openAI:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("textProcessingOpenAIApiKey")
                                .font(.headline)

                            HStack {
                                if showingTextProcessingAPIKey {
                                    TextField("sk-...", text: $settings.textProcessingOpenAIApiKey)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField("sk-...", text: $settings.textProcessingOpenAIApiKey)
                                        .textFieldStyle(.roundedBorder)
                                }

                                Button(action: { showingTextProcessingAPIKey.toggle() }) {
                                    Image(systemName: showingTextProcessingAPIKey ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.borderless)
                            }

                            Text("textProcessingOpenAIApiKeyDescription")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Picker("gptModel", selection: $settings.selectedGPTModel) {
                            ForEach(GPTModel.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }

                        Text("gptModelDescription")
                            .font(.caption)
                            .foregroundColor(.secondary)

                    case .anthropic:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("anthropicApiKey")
                                .font(.headline)

                            HStack {
                                if showingAnthropicAPIKey {
                                    TextField("sk-ant-...", text: $settings.anthropicApiKey)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField("sk-ant-...", text: $settings.anthropicApiKey)
                                        .textFieldStyle(.roundedBorder)
                                }

                                Button(action: { showingAnthropicAPIKey.toggle() }) {
                                    Image(systemName: showingAnthropicAPIKey ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.borderless)
                            }

                            Text("anthropicApiKeyDescription")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Picker("anthropicModel", selection: $settings.selectedAnthropicModel) {
                            ForEach(AnthropicModel.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }

                    case .ollama:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ollamaServerURL")
                                .font(.headline)

                            TextField("http://localhost:11434", text: $settings.ollamaServerURL)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: settings.ollamaServerURL) { _, _ in
                                    loadOllamaModels()
                                }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("ollamaModel")
                                    .font(.headline)
                                Spacer()
                                if isLoadingOllamaModels {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                                Button {
                                    loadOllamaModels()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                            }

                            if ollamaModels.isEmpty && !isLoadingOllamaModels {
                                if let error = ollamaModelError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                } else {
                                    Text("ollamaNoModels")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Picker("", selection: $settings.selectedOllamaModel) {
                                    if settings.selectedOllamaModel.isEmpty {
                                        Text("ollamaSelectModel").tag("")
                                    }
                                    ForEach(ollamaModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        Text("ollamaDescription")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        CustomHeadersEditor(headers: $settings.ollamaCustomHeaders)

                    case .appleIntelligence:
                        let model = SystemLanguageModel.default
                        switch model.availability {
                        case .available:
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("appleIntelligenceAvailable")
                                    .foregroundColor(.green)
                            }
                        case .unavailable(.deviceNotEligible):
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("appleIntelligenceNotEligible")
                                    .foregroundColor(.red)
                            }
                        case .unavailable(.appleIntelligenceNotEnabled):
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("appleIntelligenceNotEnabled")
                                    .foregroundColor(.orange)
                            }
                        case .unavailable(.modelNotReady):
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("appleIntelligenceNotReady")
                                    .foregroundColor(.secondary)
                            }
                        default:
                            HStack {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundColor(.secondary)
                                Text("appleIntelligenceUnavailable")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("appleIntelligenceDescription")
                            .font(.caption)
                            .foregroundColor(.secondary)

                    case .gemini:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("geminiApiKey")
                                .font(.headline)

                            HStack {
                                if showingGeminiAPIKey {
                                    TextField("AIza...", text: $settings.geminiApiKey)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField("AIza...", text: $settings.geminiApiKey)
                                        .textFieldStyle(.roundedBorder)
                                }

                                Button(action: { showingGeminiAPIKey.toggle() }) {
                                    Image(systemName: showingGeminiAPIKey ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.borderless)
                            }

                            Text("geminiApiKeyDescription")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("geminiSharedKeyHint")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Picker("geminiModel", selection: $settings.selectedGeminiTextModel) {
                            ForEach(GeminiModel.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                    }

                    Picker("defaultTranslationLanguage", selection: $settings.defaultTranslationLanguage) {
                        ForEach(AppSettings.translationLanguages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }

                    Text("defaultTranslationLanguageDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("textRewriteSection")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if settings.textProcessingProvider == .ollama {
                loadOllamaModels()
            }
        }
        .onChange(of: settings.textProcessingProvider) { _, newValue in
            if newValue == .ollama {
                loadOllamaModels()
            }
        }
    }

    private func loadOllamaModels() {
        isLoadingOllamaModels = true
        ollamaModelError = nil

        Task {
            do {
                let models = try await TextRewriteService.fetchOllamaModels(serverURL: settings.ollamaServerURL)
                await MainActor.run {
                    ollamaModels = models
                    isLoadingOllamaModels = false
                    // Auto-select first model if none selected
                    if settings.selectedOllamaModel.isEmpty, let first = models.first {
                        settings.selectedOllamaModel = first
                    }
                }
            } catch {
                await MainActor.run {
                    ollamaModels = []
                    ollamaModelError = String(localized: "ollamaConnectionError")
                    isLoadingOllamaModels = false
                }
            }
        }
    }
}
