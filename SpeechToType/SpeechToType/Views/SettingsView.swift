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
    @State private var isRecordingShortcut = false
    @State private var isRecordingRewriteShortcut = false

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
                Text("transcriptionModelSection")
            }

            // Text Rewriting Section
            Section {
                Toggle("textRewriteEnabled", isOn: $settings.textRewriteEnabled)

                if settings.textRewriteEnabled {
                    Picker("gptModel", selection: $settings.selectedGPTModel) {
                        ForEach(GPTModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }

                    Text("gptModelDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("textRewriteSection")
            }

            // Shortcuts Section
            Section {
                // Recording shortcut
                HStack {
                    Text("recordingShortcut")
                    Spacer()
                    ShortcutRecorderButton(
                        shortcut: $settings.recordingShortcut,
                        isRecording: $isRecordingShortcut,
                        otherRecording: $isRecordingRewriteShortcut
                    )
                }

                // Rewrite shortcut (only if enabled)
                if settings.textRewriteEnabled {
                    HStack {
                        Text("rewriteShortcut")
                        Spacer()
                        ShortcutRecorderButton(
                            shortcut: $settings.rewriteShortcut,
                            isRecording: $isRecordingRewriteShortcut,
                            otherRecording: $isRecordingShortcut
                        )
                    }
                }

                Text("shortcutsDescription")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Legacy toggle for backward compatibility
                Toggle("useControlKeyAsHotkey", isOn: $settings.useControlKey)
                    .onChange(of: settings.useControlKey) { _, newValue in
                        if newValue {
                            settings.recordingShortcut = ShortcutConfig(keyCode: kVK_Control, modifiers: 0)
                        }
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
                Text("shortcutsSection")
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

                if let updater = updater {
                    Toggle("autoCheckUpdates", isOn: $automaticallyChecksForUpdates)
                        .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                            updater.automaticallyChecksForUpdates = newValue
                        }

                    Toggle("autoDownloadUpdates", isOn: $automaticallyDownloadsUpdates)
                        .disabled(!automaticallyChecksForUpdates)
                        .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                            updater.automaticallyDownloadsUpdates = newValue
                        }

                    Button("checkForUpdates") {
                        updater.checkForUpdates()
                    }
                }

                Link("OpenAI API Documentation", destination: URL(string: "https://platform.openai.com/docs/api-reference/audio")!)
            } header: {
                Text("about")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 700)
        .onAppear {
            accessibilityEnabled = HotkeyManager.checkAccessibilityPermission()
        }
    }
}

// MARK: - Shortcut Recorder Button

struct ShortcutRecorderButton: View {
    @Binding var shortcut: ShortcutConfig
    @Binding var isRecording: Bool
    @Binding var otherRecording: Bool

    var body: some View {
        Button(action: {
            if !otherRecording {
                isRecording.toggle()
            }
        }) {
            HStack {
                if isRecording {
                    Text("pressKeys")
                        .foregroundColor(.red)
                } else {
                    Text(shortcut.displayString)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.red.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.red : Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onKeyPress { keyPress in
            if isRecording {
                recordShortcut(keyPress)
                return .handled
            }
            return .ignored
        }
    }

    private func recordShortcut(_ keyPress: KeyPress) {
        var modifiers = 0
        if keyPress.modifiers.contains(.command) {
            modifiers |= Int(CGEventFlags.maskCommand.rawValue)
        }
        if keyPress.modifiers.contains(.control) {
            modifiers |= Int(CGEventFlags.maskControl.rawValue)
        }
        if keyPress.modifiers.contains(.option) {
            modifiers |= Int(CGEventFlags.maskAlternate.rawValue)
        }
        if keyPress.modifiers.contains(.shift) {
            modifiers |= Int(CGEventFlags.maskShift.rawValue)
        }

        // Map the key character to a key code
        let keyCode = characterToKeyCode(keyPress.key.character)

        shortcut = ShortcutConfig(keyCode: keyCode, modifiers: modifiers)
        isRecording = false
    }

    private func characterToKeyCode(_ character: Character) -> Int {
        let charMap: [Character: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            " ": kVK_Space
        ]
        return charMap[character.lowercased().first ?? "a"] ?? kVK_ANSI_A
    }
}

#Preview {
    SettingsView()
}
