//
//  AppSettings.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import Foundation
import SwiftUI
import Carbon.HIToolbox
import Combine

struct HTTPHeader: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String = ""
    var value: String = ""
}

enum SpeechModelProvider: String, CaseIterable, Codable {
    case openAI = "openai"
    case local = "local"
    case appleSpeech = "appleSpeech"
    case gemini = "gemini"
    case azureFoundry = "azureFoundry"

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI API"
        case .local: return String(localized: "localProvider")
        case .appleSpeech: return "Apple Speech"
        case .gemini: return "Google Gemini"
        case .azureFoundry: return "Azure Foundry MAI"
        }
    }
}

enum TextProcessingProvider: String, CaseIterable, Codable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case ollama = "ollama"
    case appleIntelligence = "appleIntelligence"
    case gemini = "gemini"

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI API"
        case .anthropic: return "Anthropic API"
        case .ollama: return "Ollama"
        case .appleIntelligence: return "Apple Intelligence"
        case .gemini: return "Google Gemini"
        }
    }
}

enum GeminiModel: String, CaseIterable, Codable {
    case gemini36Flash = "gemini-3.6-flash"
    case gemini31Pro = "gemini-3.1-pro"

    var displayName: String {
        switch self {
        case .gemini36Flash: return "Gemini 3.6 Flash"
        case .gemini31Pro: return "Gemini 3.1 Pro"
        }
    }
}

enum AnthropicModel: String, CaseIterable, Codable {
    case claudeOpus5 = "claude-opus-5"
    case claudeSonnet5 = "claude-sonnet-5"
    case claudeHaiku45 = "claude-haiku-4-5"

    var displayName: String {
        switch self {
        case .claudeOpus5: return "Claude Opus 5"
        case .claudeSonnet5: return "Claude Sonnet 5"
        case .claudeHaiku45: return "Claude Haiku 4.5"
        }
    }
}

enum TranscriptionModel: String, CaseIterable, Codable {
    case gptTranscribe = "gpt-transcribe"
    case gptLiveTranscribe = "gpt-live-transcribe"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oTranscribeDiarize = "gpt-4o-transcribe-diarize"

    var displayName: String {
        switch self {
        case .gptTranscribe:
            return "GPT Transcribe"
        case .gptLiveTranscribe:
            return "GPT Live Transcribe"
        case .gpt4oMiniTranscribe:
            return "GPT-4o Mini Transcribe"
        case .gpt4oTranscribe:
            return "GPT-4o Transcribe"
        case .gpt4oTranscribeDiarize:
            return "GPT-4o Transcribe (Diarize)"
        }
    }

    /// New model generation: uses `languages[]` + `keywords[]` instead of the singular
    /// `language` plus a combined dictionary prompt.
    var usesLanguagesAndKeywords: Bool {
        self == .gptTranscribe || self == .gptLiveTranscribe
    }

    /// Realtime-only — there is no `/v1/audio/transcriptions` endpoint for this model.
    var isRealtimeOnly: Bool { self == .gptLiveTranscribe }

    /// The model that can actually be used on the batch endpoint.
    var batchFallback: TranscriptionModel { isRealtimeOnly ? .gptTranscribe : self }
}

/// Recognition language for the new OpenAI speech models. `automatic` omits the field
/// entirely so the model detects the language itself.
enum SpeechLanguageOption: String, CaseIterable, Codable {
    case automatic = "auto"
    case german = "de"
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case dutch = "nl"
    case portuguese = "pt"
    case polish = "pl"

    /// ISO-639-1 code for the API, or nil when the field must be omitted.
    var apiCode: String? { self == .automatic ? nil : rawValue }

    var displayName: String {
        switch self {
        case .automatic: return String(localized: "speechLanguageAutomatic")
        case .german: return "Deutsch (de)"
        case .english: return "English (en)"
        case .french: return "Français (fr)"
        case .spanish: return "Español (es)"
        case .italian: return "Italiano (it)"
        case .dutch: return "Nederlands (nl)"
        case .portuguese: return "Português (pt)"
        case .polish: return "Polski (pl)"
        }
    }
}

/// `delay` for gpt-live-transcribe: latency vs. accuracy trade-off.
enum OpenAIRealtimeDelay: String, CaseIterable, Codable {
    case minimal
    case low
    case medium
    case high
    case xhigh

    var displayName: String {
        switch self {
        case .minimal: return String(localized: "realtimeDelayMinimal")
        case .low: return String(localized: "realtimeDelayLow")
        case .medium: return String(localized: "realtimeDelayMedium")
        case .high: return String(localized: "realtimeDelayHigh")
        case .xhigh: return String(localized: "realtimeDelayXHigh")
        }
    }
}

enum AutoDeleteOption: String, CaseIterable, Codable {
    case never = "never"
    case oneDay = "1day"
    case oneWeek = "1week"
    case oneMonth = "1month"
    case threeMonths = "3months"

    var displayName: LocalizedStringKey {
        switch self {
        case .never:
            return "never"
        case .oneDay:
            return "after1Day"
        case .oneWeek:
            return "after1Week"
        case .oneMonth:
            return "after1Month"
        case .threeMonths:
            return "after3Months"
        }
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .never:
            return nil
        case .oneDay:
            return 86400
        case .oneWeek:
            return 604800
        case .oneMonth:
            return 2592000
        case .threeMonths:
            return 7776000
        }
    }
}

/// Shortcut trigger mode
enum ShortcutTriggerMode: String, Codable {
    case holdKey           // Hold single key to activate (for direct dictation)
    case doubleTap         // Double-tap key/combination to toggle (for continuous recording)
    case keyCombo          // Press key combination once (for rewrite)
}

/// Stored shortcut configuration
struct ShortcutConfig: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int  // CGEventFlags raw value
    var triggerMode: ShortcutTriggerMode

    // Default: Right Option key for direct dictation (hold to record)
    static let defaultDirectDictation = ShortcutConfig(
        keyCode: kVK_RightOption,
        modifiers: 0,
        triggerMode: .holdKey
    )

    // Default: Double-tap Right Option for continuous recording
    static let defaultContinuousRecording = ShortcutConfig(
        keyCode: kVK_RightOption,
        modifiers: 0,
        triggerMode: .doubleTap
    )

    // Default: Right Option + Space for text rewrite
    static let defaultRewrite = ShortcutConfig(
        keyCode: kVK_Space,
        modifiers: Int(CGEventFlags.maskAlternate.rawValue),
        triggerMode: .keyCombo
    )

    // Legacy defaults for migration
    static let legacyRecording = ShortcutConfig(keyCode: kVK_Control, modifiers: 0, triggerMode: .holdKey)
    static let legacyRewrite = ShortcutConfig(keyCode: kVK_ANSI_R, modifiers: Int(CGEventFlags.maskCommand.rawValue), triggerMode: .keyCombo)

    /// Check if this is a modifier-only shortcut (like Right Option alone)
    var isModifierOnly: Bool {
        return keyCode == kVK_RightOption || keyCode == kVK_Option ||
               keyCode == kVK_RightControl || keyCode == kVK_Control ||
               keyCode == kVK_RightShift || keyCode == kVK_Shift ||
               keyCode == kVK_RightCommand || keyCode == kVK_Command
    }

    var displayString: String {
        var parts: [String] = []

        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }

        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: Int) -> String {
        let keyMap: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_Space: "Space", kVK_Control: "Control",
            kVK_Return: "Return", kVK_Tab: "Tab", kVK_Escape: "Esc",
            kVK_Option: "⌥", kVK_RightOption: "⌥ Right",
            kVK_RightControl: "⌃ Right", kVK_RightShift: "⇧ Right",
            kVK_Command: "⌘", kVK_RightCommand: "⌘ Right",
            kVK_Shift: "⇧"
        ]
        return keyMap[keyCode] ?? "Key \(keyCode)"
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var apiKey: String {
        didSet { defaults.set(apiKey, forKey: "apiKey") }
    }

    @Published var selectedModel: TranscriptionModel {
        didSet { defaults.set(selectedModel.rawValue, forKey: "selectedModel") }
    }

    @Published var autoDeleteOption: AutoDeleteOption {
        didSet { defaults.set(autoDeleteOption.rawValue, forKey: "autoDeleteOption") }
    }

    @Published var hotkeyKeyCode: Int {
        didSet { defaults.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") }
    }

    @Published var hotkeyModifiers: Int {
        didSet { defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }

    @Published var useControlKey: Bool {
        didSet { defaults.set(useControlKey, forKey: "useControlKey") }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    // New settings for v1.1

    /// GPT model for text rewriting
    @Published var selectedGPTModel: GPTModel {
        didSet { defaults.set(selectedGPTModel.rawValue, forKey: "selectedGPTModel") }
    }

    /// Enable/disable text rewriting feature
    @Published var textRewriteEnabled: Bool {
        didSet { defaults.set(textRewriteEnabled, forKey: "textRewriteEnabled") }
    }

    /// Custom shortcut for direct dictation (hold to record)
    @Published var directDictationShortcut: ShortcutConfig {
        didSet {
            if let encoded = try? JSONEncoder().encode(directDictationShortcut) {
                defaults.set(encoded, forKey: "directDictationShortcut")
            }
        }
    }

    /// Custom shortcut for continuous recording (double-tap to toggle)
    @Published var continuousRecordingShortcut: ShortcutConfig {
        didSet {
            if let encoded = try? JSONEncoder().encode(continuousRecordingShortcut) {
                defaults.set(encoded, forKey: "continuousRecordingShortcut")
            }
        }
    }

    /// Custom shortcut for text rewriting
    @Published var rewriteShortcut: ShortcutConfig {
        didSet {
            if let encoded = try? JSONEncoder().encode(rewriteShortcut) {
                defaults.set(encoded, forKey: "rewriteShortcut")
            }
        }
    }

    // Legacy property for backward compatibility
    var recordingShortcut: ShortcutConfig {
        get { directDictationShortcut }
        set { directDictationShortcut = newValue }
    }

    /// Save rewritten texts to history
    @Published var saveRewritesToHistory: Bool {
        didSet { defaults.set(saveRewritesToHistory, forKey: "saveRewritesToHistory") }
    }

    /// When true, text is inserted via the clipboard (copy + Cmd+V). When false, text is
    /// typed directly without ever touching the clipboard.
    @Published var copyToClipboardOnInsert: Bool {
        didSet { defaults.set(copyToClipboardOnInsert, forKey: "copyToClipboardOnInsert") }
    }

    /// Default language for translation
    @Published var defaultTranslationLanguage: String {
        didSet { defaults.set(defaultTranslationLanguage, forKey: "defaultTranslationLanguage") }
    }

    /// Available translation languages
    static let translationLanguages = [
        "English",
        "German",
        "French",
        "Spanish",
        "Italian",
        "Portuguese",
        "Dutch",
        "Polish",
        "Russian",
        "Chinese",
        "Japanese",
        "Korean"
    ]

    // MARK: - Whisper Server Settings

    /// Whether to use a local Whisper server instead of OpenAI API
    @Published var useLocalWhisperServer: Bool {
        didSet { defaults.set(useLocalWhisperServer, forKey: "useLocalWhisperServer") }
    }

    /// URL of the local Whisper server
    @Published var whisperServerURL: String {
        didSet { defaults.set(whisperServerURL, forKey: "whisperServerURL") }
    }

    /// Custom model name for the local Whisper server
    @Published var whisperServerModel: String {
        didSet { defaults.set(whisperServerModel, forKey: "whisperServerModel") }
    }

    /// Optional Bearer token for Whisper server authentication
    @Published var whisperServerBearerToken: String {
        didSet { defaults.set(whisperServerBearerToken, forKey: "whisperServerBearerToken") }
    }

    /// Custom HTTP headers for the Whisper server (e.g. behind Cloudflare Access)
    @Published var whisperServerCustomHeaders: [HTTPHeader] {
        didSet {
            if let encoded = try? JSONEncoder().encode(whisperServerCustomHeaders) {
                defaults.set(encoded, forKey: "whisperServerCustomHeaders")
            }
        }
    }

    // MARK: - Provider Settings

    /// Speech model provider (OpenAI API or Local)
    @Published var speechModelProvider: SpeechModelProvider {
        didSet {
            defaults.set(speechModelProvider.rawValue, forKey: "speechModelProvider")
            // Sync with useLocalWhisperServer for backward compatibility
            useLocalWhisperServer = (speechModelProvider == .local)
        }
    }

    /// Text processing provider (OpenAI API or Anthropic API)
    @Published var textProcessingProvider: TextProcessingProvider {
        didSet { defaults.set(textProcessingProvider.rawValue, forKey: "textProcessingProvider") }
    }

    // MARK: - Anthropic Settings

    /// Separate OpenAI API key for text processing (optional, falls back to main API key)
    @Published var textProcessingOpenAIApiKey: String {
        didSet { defaults.set(textProcessingOpenAIApiKey, forKey: "textProcessingOpenAIApiKey") }
    }

    /// Anthropic API key
    @Published var anthropicApiKey: String {
        didSet { defaults.set(anthropicApiKey, forKey: "anthropicApiKey") }
    }

    /// Selected Anthropic model for text processing
    @Published var selectedAnthropicModel: AnthropicModel {
        didSet { defaults.set(selectedAnthropicModel.rawValue, forKey: "selectedAnthropicModel") }
    }

    // MARK: - Ollama Settings

    /// Ollama server URL
    @Published var ollamaServerURL: String {
        didSet { defaults.set(ollamaServerURL, forKey: "ollamaServerURL") }
    }

    /// Selected Ollama model name
    @Published var selectedOllamaModel: String {
        didSet { defaults.set(selectedOllamaModel, forKey: "selectedOllamaModel") }
    }

    /// Custom HTTP headers for the Ollama server (e.g. behind Cloudflare Access)
    @Published var ollamaCustomHeaders: [HTTPHeader] {
        didSet {
            if let encoded = try? JSONEncoder().encode(ollamaCustomHeaders) {
                defaults.set(encoded, forKey: "ollamaCustomHeaders")
            }
        }
    }

    // MARK: - Gemini Settings

    /// Google Gemini API key (shared between speech transcription and text rewriting)
    @Published var geminiApiKey: String {
        didSet { defaults.set(geminiApiKey, forKey: "geminiApiKey") }
    }

    /// Selected Gemini model for speech transcription
    @Published var selectedGeminiSpeechModel: GeminiModel {
        didSet { defaults.set(selectedGeminiSpeechModel.rawValue, forKey: "selectedGeminiSpeechModel") }
    }

    /// Selected Gemini model for text rewriting
    @Published var selectedGeminiTextModel: GeminiModel {
        didSet { defaults.set(selectedGeminiTextModel.rawValue, forKey: "selectedGeminiTextModel") }
    }

    // MARK: - Azure Foundry MAI Settings

    /// Azure resource endpoint (e.g. https://<resource>.cognitiveservices.azure.com/)
    @Published var azureFoundryEndpoint: String {
        didSet { defaults.set(azureFoundryEndpoint, forKey: "azureFoundryEndpoint") }
    }

    /// Azure Speech resource subscription key
    @Published var azureFoundryApiKey: String {
        didSet { defaults.set(azureFoundryApiKey, forKey: "azureFoundryApiKey") }
    }

    /// Azure fast-transcription API version
    @Published var azureFoundryApiVersion: String {
        didSet { defaults.set(azureFoundryApiVersion, forKey: "azureFoundryApiVersion") }
    }

    /// Azure Foundry model name (free-text, e.g. MAI-Transcribe-1.5)
    @Published var azureFoundryModel: String {
        didSet { defaults.set(azureFoundryModel, forKey: "azureFoundryModel") }
    }

    /// Whether to pass the dictionary to Azure Foundry MAI (default off)
    @Published var applyDictionaryToAzure: Bool {
        didSet { defaults.set(applyDictionaryToAzure, forKey: "applyDictionaryToAzure") }
    }

    /// Biasing weight for the Azure phraseList (valid range 1.0...20.0)
    @Published var azureBiasingWeight: Double {
        didSet { defaults.set(azureBiasingWeight, forKey: "azureBiasingWeight") }
    }

    /// Enable real-time/streaming transcription via the Azure Speech SDK (standard models,
    /// not MAI-Transcribe). Only relevant when the speech provider is Azure Foundry.
    @Published var azureRealtimeEnabled: Bool {
        didSet { defaults.set(azureRealtimeEnabled, forKey: "azureRealtimeEnabled") }
    }

    /// Recognition language (BCP-47 locale, e.g. "de-DE") for real-time transcription
    @Published var azureRealtimeLanguage: String {
        didSet { defaults.set(azureRealtimeLanguage, forKey: "azureRealtimeLanguage") }
    }

    /// Enable real-time/live transcription with Apple Speech (on-device). Only relevant
    /// when the speech provider is Apple Speech.
    @Published var appleRealtimeEnabled: Bool {
        didSet { defaults.set(appleRealtimeEnabled, forKey: "appleRealtimeEnabled") }
    }

    /// Recognition language for gpt-transcribe / gpt-live-transcribe. The legacy gpt-4o-*
    /// models keep their hardcoded `language=de`.
    @Published var openAISpeechLanguage: SpeechLanguageOption {
        didSet { defaults.set(openAISpeechLanguage.rawValue, forKey: "openAISpeechLanguage") }
    }

    /// `delay` for gpt-live-transcribe (realtime latency profile)
    @Published var openAIRealtimeDelay: OpenAIRealtimeDelay {
        didSet { defaults.set(openAIRealtimeDelay.rawValue, forKey: "openAIRealtimeDelay") }
    }

    /// Common locales offered in the real-time language picker
    static let azureRealtimeLocales: [(code: String, name: String)] = [
        ("de-DE", "Deutsch (de-DE)"),
        ("en-US", "English (en-US)"),
        ("en-GB", "English UK (en-GB)"),
        ("fr-FR", "Français (fr-FR)"),
        ("es-ES", "Español (es-ES)"),
        ("it-IT", "Italiano (it-IT)"),
        ("nl-NL", "Nederlands (nl-NL)"),
        ("pt-PT", "Português (pt-PT)"),
        ("pl-PL", "Polski (pl-PL)")
    ]

    // MARK: - Dictionary (Custom Vocabulary) Settings

    /// Custom words/spellings the system should recognize
    @Published var dictionaryWords: [String] {
        didSet {
            if let encoded = try? JSONEncoder().encode(dictionaryWords) {
                defaults.set(encoded, forKey: "dictionaryWords")
            }
        }
    }

    /// General free-text instructions added to the prompt
    @Published var dictionaryInstructions: String {
        didSet { defaults.set(dictionaryInstructions, forKey: "dictionaryInstructions") }
    }

    /// Whether to pass the dictionary to the local Whisper server (default off)
    @Published var applyDictionaryToLocalWhisper: Bool {
        didSet { defaults.set(applyDictionaryToLocalWhisper, forKey: "applyDictionaryToLocalWhisper") }
    }

    /// For the local Whisper server: send only the words (comma-separated), not the instructions
    @Published var dictionarySimpleModeLocalWhisper: Bool {
        didSet { defaults.set(dictionarySimpleModeLocalWhisper, forKey: "dictionarySimpleModeLocalWhisper") }
    }

    /// Whether to inject the dictionary into the text-rewrite system prompt (default off)
    @Published var applyDictionaryToRewrite: Bool {
        didSet { defaults.set(applyDictionaryToRewrite, forKey: "applyDictionaryToRewrite") }
    }

    /// Only the words (comma-separated); empty if no words are set
    var dictionaryWordsText: String {
        dictionaryWords
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: ", ")
    }

    /// The dictionary words trimmed, blanks removed (for Azure phraseList)
    var dictionaryPhrases: [String] {
        dictionaryWords
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Azure biasing weight clamped to the valid 1.0...20.0 range
    var azureBiasingWeightClamped: Double {
        min(max(azureBiasingWeight, 1.0), 20.0)
    }

    /// The dictionary words as OpenAI `keywords`. Per the API docs each keyword must be a
    /// single line without `<`, `>`, CR or LF.
    var openAIKeywords: [String] {
        var seen = Set<String>()
        return dictionaryWords.compactMap { raw -> String? in
            let cleaned = raw
                .components(separatedBy: .newlines)
                .joined(separator: " ")
                .replacingOccurrences(of: "<", with: "")
                .replacingOccurrences(of: ">", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { return nil }
            return cleaned
        }
    }

    /// Only the free-text instructions — for the new OpenAI models the words travel
    /// separately as `keywords`.
    var dictionaryInstructionsText: String {
        dictionaryInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Combined dictionary prompt text (words + instructions); empty if nothing is set
    var dictionaryPromptText: String {
        var parts: [String] = []
        let words = dictionaryWordsText
        if !words.isEmpty { parts.append(words) }
        let instr = dictionaryInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instr.isEmpty { parts.append(instr) }
        return parts.joined(separator: "\n")
    }

    var isConfigured: Bool {
        let speechConfigured: Bool
        switch speechModelProvider {
        case .openAI:
            speechConfigured = !apiKey.isEmpty
        case .local:
            speechConfigured = !whisperServerURL.isEmpty
        case .appleSpeech:
            speechConfigured = true
        case .gemini:
            speechConfigured = !geminiApiKey.isEmpty
        case .azureFoundry:
            speechConfigured = !azureFoundryEndpoint.isEmpty && !azureFoundryApiKey.isEmpty
        }

        // Text processing is optional, but if enabled, check the provider
        if textRewriteEnabled {
            switch textProcessingProvider {
            case .openAI:
                return speechConfigured && !apiKey.isEmpty
            case .anthropic:
                return speechConfigured && !anthropicApiKey.isEmpty
            case .ollama:
                return speechConfigured && !ollamaServerURL.isEmpty
            case .appleIntelligence:
                return speechConfigured
            case .gemini:
                return speechConfigured && !geminiApiKey.isEmpty
            }
        }

        return speechConfigured
    }

    func resetShortcutsToDefaults() {
        directDictationShortcut = ShortcutConfig.defaultDirectDictation
        continuousRecordingShortcut = ShortcutConfig.defaultContinuousRecording
        rewriteShortcut = ShortcutConfig.defaultRewrite
        useControlKey = false  // No longer using legacy Control key mode
    }

    private init() {
        self.apiKey = defaults.string(forKey: "apiKey") ?? ""
        self.autoDeleteOption = AutoDeleteOption(rawValue: defaults.string(forKey: "autoDeleteOption") ?? "") ?? .never
        self.hotkeyKeyCode = defaults.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_ANSI_D
        self.hotkeyModifiers = defaults.object(forKey: "hotkeyModifiers") as? Int ?? 0
        self.launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false

        // v1.6 migration: one-time upgrade of default models
        let hasApplied16Migration = defaults.bool(forKey: "hasApplied16Migration")

        // Transcription model: new default is gptTranscribe. An already stored choice is
        // never overwritten — only fresh installs get the new default.
        if !hasApplied16Migration {
            // First install or upgrade: set to new default
            self.selectedModel = .gptTranscribe
            defaults.set(TranscriptionModel.gptTranscribe.rawValue, forKey: "selectedModel")
        } else {
            self.selectedModel = TranscriptionModel(rawValue: defaults.string(forKey: "selectedModel") ?? "") ?? .gptTranscribe
        }

        // GPT model: new default is gpt56Terra (balanced tier). A stored value from a
        // model that is no longer offered no longer parses and falls back to the default.
        if !hasApplied16Migration {
            self.selectedGPTModel = .gpt56Terra
            defaults.set(GPTModel.gpt56Terra.rawValue, forKey: "selectedGPTModel")
        } else {
            self.selectedGPTModel = GPTModel(rawValue: defaults.string(forKey: "selectedGPTModel") ?? "") ?? .gpt56Terra
        }

        // Mark v1.6 migration as applied
        if !hasApplied16Migration {
            defaults.set(true, forKey: "hasApplied16Migration")
        }

        self.textRewriteEnabled = defaults.object(forKey: "textRewriteEnabled") as? Bool ?? true
        self.saveRewritesToHistory = defaults.object(forKey: "saveRewritesToHistory") as? Bool ?? true
        self.copyToClipboardOnInsert = defaults.object(forKey: "copyToClipboardOnInsert") as? Bool ?? true
        self.defaultTranslationLanguage = defaults.string(forKey: "defaultTranslationLanguage") ?? "English"

        // Whisper server settings
        let isLocalWhisper = defaults.object(forKey: "useLocalWhisperServer") as? Bool ?? false
        self.useLocalWhisperServer = isLocalWhisper
        self.whisperServerURL = defaults.string(forKey: "whisperServerURL") ?? ""
        self.whisperServerModel = defaults.string(forKey: "whisperServerModel") ?? "whisper-1"
        self.whisperServerBearerToken = defaults.string(forKey: "whisperServerBearerToken") ?? ""
        if let headerData = defaults.data(forKey: "whisperServerCustomHeaders"),
           let headers = try? JSONDecoder().decode([HTTPHeader].self, from: headerData) {
            self.whisperServerCustomHeaders = headers
        } else {
            self.whisperServerCustomHeaders = []
        }

        // Provider settings - derive from existing useLocalWhisperServer if no explicit setting
        if let providerRaw = defaults.string(forKey: "speechModelProvider"),
           let provider = SpeechModelProvider(rawValue: providerRaw) {
            self.speechModelProvider = provider
        } else {
            self.speechModelProvider = isLocalWhisper ? .local : .openAI
        }

        self.textProcessingProvider = TextProcessingProvider(rawValue: defaults.string(forKey: "textProcessingProvider") ?? "") ?? .openAI

        // Text processing & Anthropic settings
        self.textProcessingOpenAIApiKey = defaults.string(forKey: "textProcessingOpenAIApiKey") ?? ""
        self.anthropicApiKey = defaults.string(forKey: "anthropicApiKey") ?? ""
        self.selectedAnthropicModel = AnthropicModel(rawValue: defaults.string(forKey: "selectedAnthropicModel") ?? "") ?? .claudeSonnet5

        // Ollama settings
        self.ollamaServerURL = defaults.string(forKey: "ollamaServerURL") ?? "http://localhost:11434"
        self.selectedOllamaModel = defaults.string(forKey: "selectedOllamaModel") ?? ""
        if let headerData = defaults.data(forKey: "ollamaCustomHeaders"),
           let headers = try? JSONDecoder().decode([HTTPHeader].self, from: headerData) {
            self.ollamaCustomHeaders = headers
        } else {
            self.ollamaCustomHeaders = []
        }

        // Gemini settings
        self.geminiApiKey = defaults.string(forKey: "geminiApiKey") ?? ""
        self.selectedGeminiSpeechModel = GeminiModel(rawValue: defaults.string(forKey: "selectedGeminiSpeechModel") ?? "") ?? .gemini36Flash
        self.selectedGeminiTextModel = GeminiModel(rawValue: defaults.string(forKey: "selectedGeminiTextModel") ?? "") ?? .gemini36Flash

        // Azure Foundry MAI settings
        self.azureFoundryEndpoint = defaults.string(forKey: "azureFoundryEndpoint") ?? ""
        self.azureFoundryApiKey = defaults.string(forKey: "azureFoundryApiKey") ?? ""
        self.azureFoundryApiVersion = defaults.string(forKey: "azureFoundryApiVersion") ?? "2025-10-15"
        // Azure expects the lowercase model id (e.g. mai-transcribe-1.5). Migrate the
        // previously shipped wrong-cased default if it was persisted.
        let storedAzureModel = defaults.string(forKey: "azureFoundryModel")
        if storedAzureModel == nil || storedAzureModel == "MAI-Transcribe-1.5" {
            self.azureFoundryModel = "mai-transcribe-1.5"
            defaults.set("mai-transcribe-1.5", forKey: "azureFoundryModel")
        } else {
            self.azureFoundryModel = storedAzureModel!
        }
        self.applyDictionaryToAzure = defaults.object(forKey: "applyDictionaryToAzure") as? Bool ?? false
        self.azureBiasingWeight = defaults.object(forKey: "azureBiasingWeight") as? Double ?? 5.0
        self.azureRealtimeEnabled = defaults.object(forKey: "azureRealtimeEnabled") as? Bool ?? false
        self.azureRealtimeLanguage = defaults.string(forKey: "azureRealtimeLanguage") ?? "de-DE"
        self.appleRealtimeEnabled = defaults.object(forKey: "appleRealtimeEnabled") as? Bool ?? true

        // OpenAI (gpt-transcribe / gpt-live-transcribe) settings
        self.openAISpeechLanguage = SpeechLanguageOption(rawValue: defaults.string(forKey: "openAISpeechLanguage") ?? "") ?? .german
        self.openAIRealtimeDelay = OpenAIRealtimeDelay(rawValue: defaults.string(forKey: "openAIRealtimeDelay") ?? "") ?? .low

        // Dictionary settings
        if let dictData = defaults.data(forKey: "dictionaryWords"),
           let words = try? JSONDecoder().decode([String].self, from: dictData) {
            self.dictionaryWords = words
        } else {
            self.dictionaryWords = []
        }
        self.dictionaryInstructions = defaults.string(forKey: "dictionaryInstructions") ?? ""
        self.applyDictionaryToLocalWhisper = defaults.object(forKey: "applyDictionaryToLocalWhisper") as? Bool ?? false
        self.dictionarySimpleModeLocalWhisper = defaults.object(forKey: "dictionarySimpleModeLocalWhisper") as? Bool ?? false
        self.applyDictionaryToRewrite = defaults.object(forKey: "applyDictionaryToRewrite") as? Bool ?? false

        // Check if this is an upgrade from a version before 1.5 (shortcut overhaul)
        let hasNewShortcutSettings = defaults.data(forKey: "directDictationShortcut") != nil
        let isUpgradeFrom14OrEarlier = !hasNewShortcutSettings && defaults.object(forKey: "useControlKey") != nil

        // Load shortcuts with migration from old format
        if let directData = defaults.data(forKey: "directDictationShortcut"),
           let directConfig = try? JSONDecoder().decode(ShortcutConfig.self, from: directData) {
            self.directDictationShortcut = directConfig
            self.useControlKey = defaults.object(forKey: "useControlKey") as? Bool ?? false
        } else {
            // New installation or upgrade from 1.4 or earlier - use new defaults
            self.directDictationShortcut = ShortcutConfig.defaultDirectDictation
            self.useControlKey = false
            // Persist immediately so we don't migrate again
            if let encoded = try? JSONEncoder().encode(ShortcutConfig.defaultDirectDictation) {
                defaults.set(encoded, forKey: "directDictationShortcut")
            }
            defaults.set(false, forKey: "useControlKey")
        }

        if let continuousData = defaults.data(forKey: "continuousRecordingShortcut"),
           let continuousConfig = try? JSONDecoder().decode(ShortcutConfig.self, from: continuousData) {
            self.continuousRecordingShortcut = continuousConfig
        } else {
            self.continuousRecordingShortcut = ShortcutConfig.defaultContinuousRecording
            if let encoded = try? JSONEncoder().encode(ShortcutConfig.defaultContinuousRecording) {
                defaults.set(encoded, forKey: "continuousRecordingShortcut")
            }
        }

        if let rewriteData = defaults.data(forKey: "rewriteShortcut"),
           let rewriteConfig = try? JSONDecoder().decode(ShortcutConfig.self, from: rewriteData) {
            // Check if this is the old Cmd+R default - if so, migrate to new default
            if isUpgradeFrom14OrEarlier &&
               rewriteConfig.keyCode == kVK_ANSI_R &&
               rewriteConfig.modifiers == Int(CGEventFlags.maskCommand.rawValue) {
                self.rewriteShortcut = ShortcutConfig.defaultRewrite
                if let encoded = try? JSONEncoder().encode(ShortcutConfig.defaultRewrite) {
                    defaults.set(encoded, forKey: "rewriteShortcut")
                }
            } else {
                self.rewriteShortcut = rewriteConfig
            }
        } else {
            self.rewriteShortcut = ShortcutConfig.defaultRewrite
            if let encoded = try? JSONEncoder().encode(ShortcutConfig.defaultRewrite) {
                defaults.set(encoded, forKey: "rewriteShortcut")
            }
        }
    }
}

extension URLRequest {
    mutating func applyCustomHeaders(_ headers: [HTTPHeader]) {
        for header in headers {
            let name = header.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            setValue(header.value, forHTTPHeaderField: name)
        }
    }
}
