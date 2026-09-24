//
//  ChatModelPicker.swift
//  SpeechToType
//
//  Menu to pick the chat model, listing every text provider that is set up in the
//  settings (API key present, Ollama reachable, Apple Intelligence available).
//

import SwiftUI
import Combine
import FoundationModels

enum ChatModelCatalog {
    static func isConfigured(_ provider: TextProcessingProvider, settings: AppSettings) -> Bool {
        switch provider {
        case .openAI:
            return !settings.textOpenAIApiKey.isEmpty
        case .anthropic:
            return !settings.anthropicApiKey.isEmpty
        case .gemini:
            return !settings.geminiApiKey.isEmpty
        case .ollama:
            return !settings.ollamaServerURL.trimmingCharacters(in: .whitespaces).isEmpty
        case .appleIntelligence:
            return SystemLanguageModel.default.availability == .available
        }
    }

    static func models(for provider: TextProcessingProvider, ollamaModels: [String]) -> [ChatModelSelection] {
        switch provider {
        case .openAI:
            return GPTModel.allCases.map { ChatModelSelection(provider: .openAI, modelID: $0.rawValue) }
        case .anthropic:
            return AnthropicModel.allCases.map { ChatModelSelection(provider: .anthropic, modelID: $0.rawValue) }
        case .gemini:
            return GeminiModel.allCases.map { ChatModelSelection(provider: .gemini, modelID: $0.rawValue) }
        case .ollama:
            return ollamaModels.map { ChatModelSelection(provider: .ollama, modelID: $0) }
        case .appleIntelligence:
            return [ChatModelSelection(provider: .appleIntelligence, modelID: "")]
        }
    }
}

/// Models offered by the Ollama server, fetched at most every 30 seconds.
final class OllamaModelList: ObservableObject {
    static let shared = OllamaModelList()

    @Published private(set) var models: [String] = []
    private var lastServer = ""
    private var lastRefresh = Date.distantPast

    func refreshIfNeeded(serverURL: String) {
        let server = serverURL.trimmingCharacters(in: .whitespaces)
        guard !server.isEmpty else {
            models = []
            return
        }
        guard server != lastServer || Date().timeIntervalSince(lastRefresh) > 30 else { return }
        lastServer = server
        lastRefresh = Date()
        Task {
            models = (try? await TextRewriteService.fetchOllamaModels(serverURL: server)) ?? []
        }
    }
}

struct ChatModelPicker: View {
    let selection: ChatModelSelection
    let onSelect: (ChatModelSelection) -> Void

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var ollama = OllamaModelList.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu {
            ForEach(TextProcessingProvider.allCases, id: \.self) { provider in
                let options = options(for: provider)
                if !options.isEmpty {
                    Section(provider.displayName) {
                        ForEach(options, id: \.self) { option in
                            Toggle(option.displayName, isOn: Binding(
                                get: { option == selection },
                                set: { if $0 { onSelect(option) } }
                            ))
                        }
                    }
                }
            }
            Divider()
            Button("chatManageProviders") {
                openSettings()
            }
        } label: {
            Text(selection.displayName)
        }
        .menuStyle(.button)
        .fixedSize()
        .help("chatModel")
        .onAppear {
            ollama.refreshIfNeeded(serverURL: settings.ollamaServerURL)
        }
    }

    /// Models of a provider that is set up. The current model stays listed even if it
    /// is no longer offered (e.g. Ollama offline).
    private func options(for provider: TextProcessingProvider) -> [ChatModelSelection] {
        guard ChatModelCatalog.isConfigured(provider, settings: settings) else { return [] }
        var options = ChatModelCatalog.models(for: provider, ollamaModels: ollama.models)
        if selection.provider == provider, !options.contains(selection) {
            options.insert(selection, at: 0)
        }
        return options
    }
}
