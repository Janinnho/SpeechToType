//
//  SettingsView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI
import Carbon.HIToolbox
import Sparkle

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var showingAPIKey = false
    @State private var accessibilityEnabled = HotkeyManager.checkAccessibilityPermission()
    
    private let updater: SPUUpdater?
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool
    
    init(updater: SPUUpdater? = nil) {
        self.updater = updater
        self._automaticallyChecksForUpdates = State(initialValue: updater?.automaticallyChecksForUpdates ?? true)
        self._automaticallyDownloadsUpdates = State(initialValue: updater?.automaticallyDownloadsUpdates ?? false)
    }
    
    var body: some View {
        Form {
            Section {
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
            } header: {
                Text("API-Konfiguration")
            }
            
            Section {
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
            } header: {
                Text("model")
            }
            
            Section {
                Toggle("useControlKeyAsHotkey", isOn: $settings.useControlKey)
                
                if !settings.useControlKey {
                    HStack {
                        Text("customKey")
                        Spacer()
                        Text(keyCodeToString(settings.hotkeyKeyCode))
                            .foregroundColor(.secondary)
                    }
                    Text("customKeyHint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("accessibilityAccess")
                    Spacer()
                    if accessibilityEnabled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("granted")
                            .foregroundColor(.green)
                    } else {
                        Button("activate") {
                            HotkeyManager.requestAccessibilityPermission()
                            // Check again after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                accessibilityEnabled = HotkeyManager.checkAccessibilityPermission()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                Text("accessibilityDescription")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("hotkey")
            }
            
            Section {
                Picker("autoDelete", selection: $settings.autoDeleteOption) {
                    ForEach(AutoDeleteOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                
                Text("autoDeleteDescription")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("historySection")
            }
            
            Section {
                HStack {
                    Text("version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                        .foregroundColor(.secondary)
                }
                
                // Update Settings
                if let updater = updater {
                    Toggle("Automatisch nach Updates suchen", isOn: $automaticallyChecksForUpdates)
                        .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                            updater.automaticallyChecksForUpdates = newValue
                        }
                    
                    Toggle("Updates automatisch herunterladen", isOn: $automaticallyDownloadsUpdates)
                        .disabled(!automaticallyChecksForUpdates)
                        .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                            updater.automaticallyDownloadsUpdates = newValue
                        }
                    
                    Button("Nach Updates suchen...") {
                        updater.checkForUpdates()
                    }
                }
                
                Link("OpenAI API Documentation", destination: URL(string: "https://platform.openai.com/docs/api-reference/audio")!)
            } header: {
                Text("about")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 550)
        .onAppear {
            accessibilityEnabled = HotkeyManager.checkAccessibilityPermission()
        }
    }
    
    private func keyCodeToString(_ keyCode: Int) -> LocalizedStringKey {
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
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        if keyCode == kVK_Space {
            return "spacebar"
        }
        if let key = keyMap[keyCode] {
            return LocalizedStringKey(key)
        }
        return "key \(keyCode)"
    }
}

#Preview {
    SettingsView()
}
