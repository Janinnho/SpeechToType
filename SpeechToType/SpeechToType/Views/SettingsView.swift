//
//  SettingsView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI
import Carbon.HIToolbox
import Sparkle

/// The categories shown in the Settings window sidebar.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case speech
    case text
    case shortcuts
    case general
    case about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .speech:    return "settingsTabSpeech"
        case .text:      return "settingsTabText"
        case .shortcuts: return "settingsTabShortcuts"
        case .general:   return "settingsTabGeneral"
        case .about:     return "settingsTabAbout"
        }
    }

    var icon: String {
        switch self {
        case .speech:    return "waveform"
        case .text:      return "text.bubble"
        case .shortcuts: return "keyboard"
        case .general:   return "gearshape"
        case .about:     return "info.circle"
        }
    }
}

struct SettingsView: View {
    private let updater: SPUUpdater?
    @State private var selection: SettingsCategory = .speech

    init(updater: SPUUpdater? = nil) {
        self.updater = updater
    }

    var body: some View {
        // A custom two-column layout instead of NavigationSplitView: SettingsView is also
        // embedded inside ContentView's NavigationSplitView detail pane, and nesting two
        // split views makes the inner sidebar render behind the app's navigation.
        HStack(spacing: 0) {
            List(SettingsCategory.allCases, selection: $selection) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            Divider()

            // Hide each pane's own grouped-form background and paint a single uniform
            // backdrop across the whole detail area, with the form content left-aligned
            // at a comfortable reading width. This avoids the big centred gap and any
            // seam between the form and the surrounding whitespace.
            detail
                .scrollContentBackground(.hidden)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .speech:    SpeechSettingsView()
        case .text:      TextRewriteSettingsView()
        case .shortcuts: ShortcutsSettingsView()
        case .general:   GeneralSettingsView()
        case .about:     AboutSettingsView(updater: updater)
        }
    }
}

// MARK: - Custom HTTP Headers Editor

struct CustomHeadersEditor: View {
    @Binding var headers: [HTTPHeader]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("customHeadersTitle")
                .font(.caption)
                .fontWeight(.semibold)

            ForEach($headers) { $header in
                HStack {
                    TextField(String(localized: "customHeaderNamePlaceholder"), text: $header.name)
                        .textFieldStyle(.roundedBorder)
                    TextField(String(localized: "customHeaderValuePlaceholder"), text: $header.value)
                        .textFieldStyle(.roundedBorder)
                    Button(action: { headers.removeAll { $0.id == header.id } }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button(action: { headers.append(HTTPHeader()) }) {
                HStack {
                    Image(systemName: "plus")
                    Text("customHeadersAdd")
                }
            }
            .buttonStyle(.bordered)

            Text("customHeadersDescription")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Shortcut Recorder Button

struct ShortcutRecorderButton: View {
    @Binding var shortcut: ShortcutConfig
    @Binding var isRecording: Bool
    @Binding var otherRecording: Bool
    var triggerMode: ShortcutTriggerMode = .holdKey
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
                    HStack(spacing: 4) {
                        Text(shortcut.displayString)
                            .foregroundColor(.primary)
                        if triggerMode == .doubleTap {
                            Text("(2x)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
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
                // Handle modifier-only shortcuts (like Right Option key alone)
                let keyCode = Int(event.keyCode)

                // Check if this is a modifier key being pressed
                if keyCode == kVK_RightOption {
                    self.shortcut = ShortcutConfig(keyCode: kVK_RightOption, modifiers: 0, triggerMode: self.triggerMode)
                    self.stopRecording()
                    return nil
                } else if keyCode == kVK_Option {
                    self.shortcut = ShortcutConfig(keyCode: kVK_Option, modifiers: 0, triggerMode: self.triggerMode)
                    self.stopRecording()
                    return nil
                } else if keyCode == kVK_Control || keyCode == kVK_RightControl {
                    self.shortcut = ShortcutConfig(keyCode: keyCode, modifiers: 0, triggerMode: self.triggerMode)
                    self.stopRecording()
                    return nil
                } else if keyCode == kVK_Command || keyCode == kVK_RightCommand {
                    // Allow command as single key for some shortcuts
                    if self.triggerMode != .keyCombo {
                        self.shortcut = ShortcutConfig(keyCode: keyCode, modifiers: 0, triggerMode: self.triggerMode)
                        self.stopRecording()
                        return nil
                    }
                    return event
                } else if keyCode == kVK_Shift || keyCode == kVK_RightShift {
                    self.shortcut = ShortcutConfig(keyCode: keyCode, modifiers: 0, triggerMode: self.triggerMode)
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

            self.shortcut = ShortcutConfig(keyCode: keyCode, modifiers: modifiers, triggerMode: self.triggerMode)
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
