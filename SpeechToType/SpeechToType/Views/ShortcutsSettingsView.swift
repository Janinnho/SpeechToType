//
//  ShortcutsSettingsView.swift
//  SpeechToType
//
//  Settings pane: global shortcuts and accessibility permission.
//

import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var accessibilityEnabled = HotkeyManager.checkAccessibilityPermission()
    @State private var isRecordingDirectDictationShortcut = false
    @State private var isRecordingContinuousShortcut = false
    @State private var isRecordingRewriteShortcut = false

    var body: some View {
        Form {
            Section {
                // Direct Dictation shortcut (hold to record)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("directDictationShortcut")
                        Spacer()
                        ShortcutRecorderButton(
                            shortcut: $settings.directDictationShortcut,
                            isRecording: $isRecordingDirectDictationShortcut,
                            otherRecording: .constant(isRecordingContinuousShortcut || isRecordingRewriteShortcut),
                            triggerMode: .holdKey
                        )
                    }
                    Text("directDictationDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Continuous Recording shortcut (double-tap)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("continuousRecordingShortcut")
                        Spacer()
                        ShortcutRecorderButton(
                            shortcut: $settings.continuousRecordingShortcut,
                            isRecording: $isRecordingContinuousShortcut,
                            otherRecording: .constant(isRecordingDirectDictationShortcut || isRecordingRewriteShortcut),
                            triggerMode: .doubleTap
                        )
                    }
                    Text("continuousRecordingDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Rewrite shortcut (only if enabled)
                if settings.textRewriteEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("rewriteShortcut")
                            Spacer()
                            ShortcutRecorderButton(
                                shortcut: $settings.rewriteShortcut,
                                isRecording: $isRecordingRewriteShortcut,
                                otherRecording: .constant(isRecordingDirectDictationShortcut || isRecordingContinuousShortcut),
                                triggerMode: .keyCombo
                            )
                        }
                        Text("rewriteShortcutDescription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text("shortcutsDescription")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                Button("resetShortcuts") {
                    settings.resetShortcutsToDefaults()
                }
                .font(.caption)

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
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityEnabled = HotkeyManager.checkAccessibilityPermission()
        }
    }
}
