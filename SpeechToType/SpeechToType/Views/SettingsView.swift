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

                Button("resetShortcuts") {
                    settings.resetShortcutsToDefaults()
                }
                .font(.caption)

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

                Toggle("saveRewritesToHistory", isOn: $settings.saveRewritesToHistory)

                Text("saveRewritesToHistoryDescription")
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
    @State private var eventMonitor: Any?

    var body: some View {
        Button(action: {
            if !otherRecording {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
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
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true

        // Use local event monitor to capture key presses
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // Handle modifier-only shortcuts (like Control key alone)
                let keyCode = Int(event.keyCode)

                // Check if this is a modifier key being pressed
                if keyCode == kVK_Control || keyCode == kVK_RightControl {
                    self.shortcut = ShortcutConfig(keyCode: kVK_Control, modifiers: 0)
                    self.stopRecording()
                    return nil
                } else if keyCode == kVK_Command || keyCode == kVK_RightCommand {
                    // Ignore command alone as it's used by system
                    return event
                } else if keyCode == kVK_Option || keyCode == kVK_RightOption {
                    self.shortcut = ShortcutConfig(keyCode: kVK_Option, modifiers: 0)
                    self.stopRecording()
                    return nil
                } else if keyCode == kVK_Shift || keyCode == kVK_RightShift {
                    self.shortcut = ShortcutConfig(keyCode: kVK_Shift, modifiers: 0)
                    self.stopRecording()
                    return nil
                }

                return event
            }

            // Handle regular key press
            let keyCode = Int(event.keyCode)
            var modifiers = 0

            let flags = event.modifierFlags
            if flags.contains(.command) {
                modifiers |= Int(CGEventFlags.maskCommand.rawValue)
            }
            if flags.contains(.control) {
                modifiers |= Int(CGEventFlags.maskControl.rawValue)
            }
            if flags.contains(.option) {
                modifiers |= Int(CGEventFlags.maskAlternate.rawValue)
            }
            if flags.contains(.shift) {
                modifiers |= Int(CGEventFlags.maskShift.rawValue)
            }

            // Escape cancels recording
            if keyCode == kVK_Escape {
                self.stopRecording()
                return nil
            }

            self.shortcut = ShortcutConfig(keyCode: keyCode, modifiers: modifiers)
            self.stopRecording()
            return nil  // Consume the event
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
    }
}

#Preview {
    SettingsView()
}
