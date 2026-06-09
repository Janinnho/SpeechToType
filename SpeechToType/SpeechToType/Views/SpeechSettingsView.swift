//
//  SpeechSettingsView.swift
//  SpeechToType
//
//  Settings pane: speech (transcription) model configuration.
//

import SwiftUI

struct SpeechSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var showingAPIKey = false
    @State private var showingGeminiAPIKey = false
    @State private var showingAzureAPIKey = false

    var body: some View {
        Form {
            Section {
                Picker("speechModelProviderPicker", selection: $settings.speechModelProvider) {
                    ForEach(SpeechModelProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                switch settings.speechModelProvider {
                case .openAI:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("openApiKey")
                            .font(.headline)

                        HStack {
                            if showingAPIKey {
                                TextField("sk-...", text: $settings.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("sk-...", text: $settings.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: { showingAPIKey.toggle() }) {
                                Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }

                        Text("openApiKeyDescription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("transcriptionModel", selection: $settings.selectedModel) {
                        ForEach(TranscriptionModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("modelInfo")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("modelInfoMini")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("modelInfoStandard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("modelInfoDiarize")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .local:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("whisperServerURL")
                            .font(.caption)
                            .fontWeight(.semibold)
                        TextField("http://yourserver/v1/audio/transcriptions", text: $settings.whisperServerURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("whisperServerModel")
                            .font(.caption)
                            .fontWeight(.semibold)
                        TextField("whisper-1", text: $settings.whisperServerModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("whisperServerBearerToken")
                            .font(.caption)
                            .fontWeight(.semibold)
                        SecureField("whisperServerBearerTokenPlaceholder", text: $settings.whisperServerBearerToken)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text("whisperServerDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("dictionaryApplyLocalWhisper", isOn: $settings.applyDictionaryToLocalWhisper)

                    Toggle("dictionarySimpleModeLocalWhisper", isOn: $settings.dictionarySimpleModeLocalWhisper)
                        .disabled(!settings.applyDictionaryToLocalWhisper)
                    Text("dictionarySimpleModeDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    CustomHeadersEditor(headers: $settings.whisperServerCustomHeaders)

                case .appleSpeech:
                    Text("appleSpeechDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("appleRealtimeEnabled", isOn: $settings.appleRealtimeEnabled)

                    Text("appleRealtimeDescription")
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
                    }

                    Picker("geminiModel", selection: $settings.selectedGeminiSpeechModel) {
                        ForEach(GeminiModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }

                case .azureFoundry:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("azureEndpoint")
                            .font(.caption)
                            .fontWeight(.semibold)
                        TextField("https://<resource>.cognitiveservices.azure.com/", text: $settings.azureFoundryEndpoint)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("azureApiKey")
                            .font(.headline)

                        HStack {
                            if showingAzureAPIKey {
                                TextField("azureApiKeyPlaceholder", text: $settings.azureFoundryApiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("azureApiKeyPlaceholder", text: $settings.azureFoundryApiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: { showingAzureAPIKey.toggle() }) {
                                Image(systemName: showingAzureAPIKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }

                        Text("azureApiKeyDescription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("azureModel")
                            .font(.caption)
                            .fontWeight(.semibold)
                        TextField("mai-transcribe-1.5", text: $settings.azureFoundryModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("azureApiVersion")
                            .font(.caption)
                            .fontWeight(.semibold)
                        TextField("2025-10-15", text: $settings.azureFoundryApiVersion)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text("azureDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("dictionaryApplyAzure", isOn: $settings.applyDictionaryToAzure)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("azureBiasingWeight")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(String(format: "%.1f", settings.azureBiasingWeight))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.azureBiasingWeight, in: 1.0...20.0, step: 0.5)
                        Text("azureBiasingWeightDescription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .disabled(!settings.applyDictionaryToAzure)

                    Divider()

                    Toggle("azureRealtimeEnabled", isOn: $settings.azureRealtimeEnabled)

                    Picker("azureRealtimeLanguage", selection: $settings.azureRealtimeLanguage) {
                        ForEach(AppSettings.azureRealtimeLocales, id: \.code) { locale in
                            Text(locale.name).tag(locale.code)
                        }
                    }
                    .disabled(!settings.azureRealtimeEnabled)

                    Text("azureRealtimeDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("speechModelConfigSection")
            }
        }
        .formStyle(.grouped)
    }
}
