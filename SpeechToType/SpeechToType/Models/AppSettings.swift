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

/// Stored shortcut configuration
struct ShortcutConfig: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int  // CGEventFlags raw value

    static let defaultRecording = ShortcutConfig(keyCode: kVK_Control, modifiers: 0)
    static let defaultRewrite = ShortcutConfig(keyCode: kVK_ANSI_R, modifiers: Int(CGEventFlags.maskCommand.rawValue))

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
            kVK_Return: "Return", kVK_Tab: "Tab", kVK_Escape: "Esc"
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

    /// Custom shortcut for recording
    @Published var recordingShortcut: ShortcutConfig {
        didSet {
            if let encoded = try? JSONEncoder().encode(recordingShortcut) {
                defaults.set(encoded, forKey: "recordingShortcut")
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

    var isConfigured: Bool {
        !apiKey.isEmpty
    }

    func resetShortcutsToDefaults() {
        recordingShortcut = ShortcutConfig.defaultRecording
        rewriteShortcut = ShortcutConfig.defaultRewrite
        useControlKey = true
    }

    private init() {
        self.apiKey = defaults.string(forKey: "apiKey") ?? ""
        self.selectedModel = TranscriptionModel(rawValue: defaults.string(forKey: "selectedModel") ?? "") ?? .gpt4oMiniTranscribe
        self.autoDeleteOption = AutoDeleteOption(rawValue: defaults.string(forKey: "autoDeleteOption") ?? "") ?? .never
        self.hotkeyKeyCode = defaults.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_ANSI_D
        self.hotkeyModifiers = defaults.object(forKey: "hotkeyModifiers") as? Int ?? 0
        self.useControlKey = defaults.object(forKey: "useControlKey") as? Bool ?? true
        self.launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false

        // New settings
        self.selectedGPTModel = GPTModel(rawValue: defaults.string(forKey: "selectedGPTModel") ?? "") ?? .gpt4o
        self.textRewriteEnabled = defaults.object(forKey: "textRewriteEnabled") as? Bool ?? true

        // Load shortcuts
        if let recordingData = defaults.data(forKey: "recordingShortcut"),
           let recordingConfig = try? JSONDecoder().decode(ShortcutConfig.self, from: recordingData) {
            self.recordingShortcut = recordingConfig
        } else {
            self.recordingShortcut = ShortcutConfig.defaultRecording
        }

        if let rewriteData = defaults.data(forKey: "rewriteShortcut"),
           let rewriteConfig = try? JSONDecoder().decode(ShortcutConfig.self, from: rewriteData) {
            self.rewriteShortcut = rewriteConfig
        } else {
            self.rewriteShortcut = ShortcutConfig.defaultRewrite
        }
    }
}
