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

enum TranscriptionModel: String, CaseIterable, Codable {
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oTranscribeDiarize = "gpt-4o-transcribe-diarize"

    var displayName: String {
        switch self {
        case .gpt4oMiniTranscribe:
            return "GPT-4o Mini Transcribe"
        case .gpt4oTranscribe:
            return "GPT-4o Transcribe"
        case .gpt4oTranscribeDiarize:
            return "GPT-4o Transcribe (Diarize)"
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

    var isConfigured: Bool {
        if useLocalWhisperServer {
            return !whisperServerURL.isEmpty
        }
        return !apiKey.isEmpty
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

        // Transcription model: new default is gpt4oTranscribe
        if !hasApplied16Migration {
            // First install or upgrade: set to new default
            self.selectedModel = .gpt4oTranscribe
            defaults.set(TranscriptionModel.gpt4oTranscribe.rawValue, forKey: "selectedModel")
        } else {
            self.selectedModel = TranscriptionModel(rawValue: defaults.string(forKey: "selectedModel") ?? "") ?? .gpt4oTranscribe
        }

        // GPT model: new default is gpt52
        if !hasApplied16Migration {
            self.selectedGPTModel = .gpt52
            defaults.set(GPTModel.gpt52.rawValue, forKey: "selectedGPTModel")
        } else {
            self.selectedGPTModel = GPTModel(rawValue: defaults.string(forKey: "selectedGPTModel") ?? "") ?? .gpt52
        }

        // Mark v1.6 migration as applied
        if !hasApplied16Migration {
            defaults.set(true, forKey: "hasApplied16Migration")
        }

        self.textRewriteEnabled = defaults.object(forKey: "textRewriteEnabled") as? Bool ?? true
        self.saveRewritesToHistory = defaults.object(forKey: "saveRewritesToHistory") as? Bool ?? true
        self.defaultTranslationLanguage = defaults.string(forKey: "defaultTranslationLanguage") ?? "English"

        // Whisper server settings
        self.useLocalWhisperServer = defaults.object(forKey: "useLocalWhisperServer") as? Bool ?? false
        self.whisperServerURL = defaults.string(forKey: "whisperServerURL") ?? ""
        self.whisperServerModel = defaults.string(forKey: "whisperServerModel") ?? "whisper-1"
        self.whisperServerBearerToken = defaults.string(forKey: "whisperServerBearerToken") ?? ""

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
