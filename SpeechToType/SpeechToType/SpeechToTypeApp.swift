//
//  SpeechToTypeApp.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI
import Sparkle
import Combine

// This view model class publishes when new updates can be checked by the user
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    
    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

// This is the view for the "Check for Updates" menu item
struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater
    
    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }
    
    var body: some View {
        Button("Nach Updates suchen...") {
            updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

@main
struct SpeechToTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterController: SPUStandardUpdaterController
    
    init() {
        // Initialize Sparkle updater
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 700, height: 500)
        
        MenuBarExtra("SpeechToType", systemImage: "waveform") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView(updater: updaterController.updater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize TextInputService early to track app switching
        _ = TextInputService.shared

        // Request necessary permissions on launch
        Task {
            _ = await AudioRecorder.shared.requestPermission()
        }

        // Start hotkey listening
        HotkeyManager.shared.startListening()

        // Setup recording handlers
        setupRecordingHandlers()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stopListening()
    }
    
    private func setupRecordingHandlers() {
        let hotkeyManager = HotkeyManager.shared
        let audioRecorder = AudioRecorder.shared
        let settings = AppSettings.shared
        let historyManager = TranscriptionHistoryManager.shared
        
        hotkeyManager.onRecordingStarted = {
            do {
                try audioRecorder.startRecording()
            } catch {
                print("Recording error: \(error)")
                hotkeyManager.statusMessage = "Fehler bei der Aufnahme"
            }
        }
        
        hotkeyManager.onRecordingStopped = {
            guard let (audioURL, duration) = audioRecorder.stopRecording() else {
                hotkeyManager.statusMessage = "Keine Aufnahme verfügbar"
                return
            }

            guard duration >= 0.5 else {
                hotkeyManager.statusMessage = "Aufnahme zu kurz"
                audioRecorder.cleanupRecording(at: audioURL)
                return
            }

            hotkeyManager.statusMessage = "Transkribiere..."

            // Show processing overlay
            Task { @MainActor in
                RecordingOverlayWindowController.shared.showProcessing()
            }

            Task {
                do {
                    let text = try await OpenAIService.shared.transcribe(
                        audioURL: audioURL,
                        model: settings.selectedModel
                    )

                    await MainActor.run {
                        RecordingOverlayWindowController.shared.hide()
                        TextInputService.shared.insertText(text)

                        let record = TranscriptionRecord(
                            text: text,
                            duration: duration,
                            model: settings.selectedModel.displayName
                        )
                        historyManager.addRecord(record)

                        hotkeyManager.statusMessage = "Erfolgreich!"
                        hotkeyManager.lastError = nil

                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if !hotkeyManager.isRecording {
                                hotkeyManager.statusMessage = String(localized: "ready")
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        RecordingOverlayWindowController.shared.hide()
                        hotkeyManager.statusMessage = String(localized: "error")
                        hotkeyManager.lastError = error.localizedDescription
                    }
                }

                audioRecorder.cleanupRecording(at: audioURL)
            }
        }
    }
}

// MARK: - Menu Bar View
struct MenuBarView: View {
    @ObservedObject var hotkeyManager = HotkeyManager.shared
    @ObservedObject var audioRecorder = AudioRecorder.shared
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        VStack(spacing: 12) {
            // Status indicator
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                
                Text(hotkeyManager.statusMessage)
                    .font(.headline)
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Recording duration
            if hotkeyManager.isRecording {
                Text(formatDuration(audioRecorder.recordingDuration))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(.red)
            }
            
            Divider()
            
            // Quick actions
            VStack(spacing: 8) {
                if hotkeyManager.isRecording {
                    Button(action: {
                        hotkeyManager.stopCurrentRecording()
                    }) {
                        Label("stopRecording", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: {
                        hotkeyManager.startContinuousRecording()
                    }) {
                        Label("startContinuousRecording", systemImage: "mic.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if settings.textRewriteEnabled {
                    Button(action: {
                        triggerRewriteFromMenu()
                    }) {
                        Label("rewriteSelectedText", systemImage: "pencil.circle.fill")
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        rewriteFromClipboard()
                    }) {
                        Label("rewriteClipboardText", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                }

                Text(String(format: String(localized: "holdShortcutToDictate %@"), settings.directDictationShortcut.displayString))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(String(format: String(localized: "doubleTapShortcutForContinuous %@"), settings.continuousRecordingShortcut.displayString))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            Divider()

            // Microphone selection
            MicrophoneSelectionView()
                .padding(.horizontal)

            Divider()

            // API Status
            HStack {
                Image(systemName: settings.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(settings.isConfigured ? .green : .yellow)
                Text(settings.isConfigured ? "apiConfigured" : "apiKeyMissing")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal)

            Divider()

            // Menu items
            Button("openMainWindow") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            
            Button("settings") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 8)
        .frame(width: 250)
    }
    
    private var statusColor: Color {
        if hotkeyManager.isRecording {
            return .red
        } else if hotkeyManager.isListening {
            return .green
        } else {
            return .gray
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    private func triggerRewriteFromMenu() {
        // First try to get the text via Accessibility API with retries (from the previously active app)
        if let selectedText = TextInputService.shared.getSelectedTextWithRetry(maxAttempts: 2, delayBetweenAttempts: 0.05),
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TextRewriteWindowController.shared.show(with: selectedText)
            return
        }

        // If Accessibility API didn't work, try activating the previous app and copying
        guard let previousApp = TextInputService.shared.getPreviousApp() else {
            TextRewriteWindowController.shared.showNoTextSelectedAlert()
            return
        }

        // Activate the previous app briefly to copy the text
        previousApp.activate(options: [])

        // Wait for the app to become active, then try with retry mechanism
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Now try to get the text with multiple attempts
            if let selectedText = TextInputService.shared.getSelectedTextWithRetry(maxAttempts: 3, delayBetweenAttempts: 0.1),
               !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TextRewriteWindowController.shared.show(with: selectedText)
            } else {
                TextRewriteWindowController.shared.showNoTextSelectedAlert()
            }
        }
    }

    private func rewriteFromClipboard() {
        if let clipboardText = NSPasteboard.general.string(forType: .string),
           !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TextRewriteWindowController.shared.show(with: clipboardText)
        } else {
            let alert = NSAlert()
            alert.messageText = String(localized: "clipboardEmpty")
            alert.informativeText = String(localized: "clipboardEmptyDescription")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "ok"))
            alert.runModal()
        }
    }
}

// MARK: - Microphone Selection View
struct MicrophoneSelectionView: View {
    @ObservedObject var audioRecorder = AudioRecorder.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.secondary)
                Text("microphone")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            Menu {
                ForEach(audioRecorder.availableInputDevices) { device in
                    Button(action: {
                        audioRecorder.selectInputDevice(device.id)
                    }) {
                        HStack {
                            Text(device.name)
                            if device.isDefault {
                                Text("(Standard)")
                                    .foregroundColor(.secondary)
                            }
                            if audioRecorder.selectedDeviceId == device.id ||
                               (audioRecorder.selectedDeviceId == nil && device.isDefault) {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(audioRecorder.selectedDevice?.name ?? String(localized: "defaultMicrophone"))
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .onAppear {
                audioRecorder.refreshInputDevices()
            }
        }
    }
}
