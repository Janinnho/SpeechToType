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
            
            Task {
                do {
                    let text = try await OpenAIService.shared.transcribe(
                        audioURL: audioURL,
                        model: settings.selectedModel
                    )
                    
                    await MainActor.run {
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
            VStack(spacing: 4) {
                Text("holdControlToDictate")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
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
}
