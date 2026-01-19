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
    
    var isConfigured: Bool {
        !apiKey.isEmpty
    }
    
    private init() {
        self.apiKey = defaults.string(forKey: "apiKey") ?? ""
        self.selectedModel = TranscriptionModel(rawValue: defaults.string(forKey: "selectedModel") ?? "") ?? .gpt4oMiniTranscribe
        self.autoDeleteOption = AutoDeleteOption(rawValue: defaults.string(forKey: "autoDeleteOption") ?? "") ?? .never
        self.hotkeyKeyCode = defaults.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_ANSI_D
        self.hotkeyModifiers = defaults.object(forKey: "hotkeyModifiers") as? Int ?? 0
        self.useControlKey = defaults.object(forKey: "useControlKey") as? Bool ?? true
        self.launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
    }
}
