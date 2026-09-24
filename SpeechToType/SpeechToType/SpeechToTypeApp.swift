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
        .defaultSize(width: 1040, height: 700)
        
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
    // Real-time (streaming) transcription state
    private var liveSession: LiveTypingSession?
    private var activeTranscriber: RealtimeTranscriber?
    private var realtimeModelLabel = "Realtime"
    private var isRealtimeActive = false
    private var realtimeStart: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize TextInputService early to track app switching
        _ = TextInputService.shared

        // Load chats now: its startup cleanup of unreferenced attachment files must run
        // before any composer can hold a draft attachment
        _ = ChatManager.shared

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
        
        hotkeyManager.onRecordingStarted = { [weak self] in
            // Real-time streaming path (live preview, insert on release) instead of record→REST.
            if let transcriber = self?.realtimeTranscriber(for: settings) {
                self?.startRealtime(transcriber)
                return
            }

            do {
                try audioRecorder.startRecording()
            } catch {
                print("Recording error: \(error)")
                hotkeyManager.statusMessage = "Fehler bei der Aufnahme"
            }
        }

        hotkeyManager.onRecordingStopped = { [weak self] in
            if self?.isRealtimeActive == true {
                self?.stopRealtime()
                return
            }

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
            let source = hotkeyManager.recordingSource

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
                        self?.deliver(text, from: source)

                        let record = TranscriptionRecord(
                            text: text,
                            duration: duration,
                            model: settings.speechModelDisplayName
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

    // MARK: - Real-time transcription

    /// Returns the live transcriber to use for the current provider, or nil for the
    /// normal record→REST path. Also sets the history label for the active engine.
    private func realtimeTranscriber(for settings: AppSettings) -> RealtimeTranscriber? {
        // gpt-live-transcribe is realtime-only, so selecting it is the live switch.
        // Deliberately not gated on a non-empty API key: this way a missing key surfaces a
        // visible error instead of silently falling back to a pointless recording.
        if settings.speechModelProvider == .openAI, settings.selectedModel == .gptLiveTranscribe {
            realtimeModelLabel = "GPT Live Transcribe (\(settings.openAISpeechLanguage.displayName))"
            return OpenAIRealtimeService()
        }
        // Same for gemini-3.5-transcribe-live: Live API only, so picking it is the switch.
        if settings.speechModelProvider == .gemini, settings.selectedGeminiSpeechModel.isRealtimeOnly {
            realtimeModelLabel = "Gemini 3.5 Transcribe Live (\(settings.geminiSpeechLanguage.displayName))"
            return GeminiRealtimeService()
        }
        if settings.speechModelProvider == .azureFoundry,
           settings.azureRealtimeEnabled,
           AzureRealtimeService.isAvailable {
            realtimeModelLabel = "Azure Realtime (\(settings.azureRealtimeLanguage))"
            return AzureRealtimeService.shared
        }
        if settings.speechModelProvider == .appleSpeech, settings.appleRealtimeEnabled {
            realtimeModelLabel = "Apple Speech (Realtime)"
            return AppleRealtimeService.shared
        }
        return nil
    }

    private func startRealtime(_ transcriber: RealtimeTranscriber) {
        let hotkeyManager = HotkeyManager.shared
        let session = LiveTypingSession()
        liveSession = session
        activeTranscriber = transcriber
        isRealtimeActive = true
        realtimeStart = Date()

        Task { @MainActor in
            RecordingOverlayWindowController.shared.showLive()
        }
        hotkeyManager.statusMessage = String(localized: "liveTranscription")

        transcriber.start(
            onPartial: { text in
                session.updatePartial(text)
            },
            onFinal: { text in
                session.commitFinal(text)
            },
            onError: { [weak self] error in
                DispatchQueue.main.async {
                    RecordingOverlayWindowController.shared.hide()
                    hotkeyManager.statusMessage = String(localized: "error")
                    hotkeyManager.lastError = error.localizedDescription
                }
                self?.isRealtimeActive = false
                self?.liveSession = nil
                self?.activeTranscriber?.stop()
                self?.activeTranscriber = nil
            }
        )
    }

    private func stopRealtime() {
        guard isRealtimeActive else { return }
        isRealtimeActive = false

        let session = liveSession
        liveSession = nil
        let transcriber = activeTranscriber
        activeTranscriber = nil
        let duration = Date().timeIntervalSince(realtimeStart ?? Date())
        realtimeStart = nil

        let hotkeyManager = HotkeyManager.shared
        let label = realtimeModelLabel
        let source = hotkeyManager.recordingSource

        // Stop recognition, then insert the complete text once.
        // Done off the main thread to avoid blocking UI.
        DispatchQueue.global(qos: .userInitiated).async {
            transcriber?.stop()
            let fullText = session?.fullText() ?? ""

            DispatchQueue.main.async {
                RecordingOverlayWindowController.shared.hide()

                if !fullText.isEmpty {
                    self.deliver(fullText, from: source)

                    let record = TranscriptionRecord(
                        text: fullText,
                        duration: duration,
                        model: label
                    )
                    TranscriptionHistoryManager.shared.addRecord(record)
                }

                hotkeyManager.statusMessage = "Erfolgreich!"
                hotkeyManager.lastError = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !hotkeyManager.isRecording {
                        hotkeyManager.statusMessage = String(localized: "ready")
                    }
                }
            }
        }
    }

    // MARK: - Delivery

    /// Puts dictated text where it belongs: the shortcut inserts it into the focused app, the
    /// start page's record button follows `AppSettings.buttonDictationTarget`.
    private func deliver(_ text: String, from source: RecordingSource) {
        guard source == .button else {
            TextInputService.shared.insertText(text)
            return
        }

        switch AppSettings.shared.buttonDictationTarget {
        case .previousApp:
            if let app = TextInputService.shared.getPreviousApp() {
                app.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    TextInputService.shared.insertText(text)
                }
                return
            }
            // No other app used yet: keep the text in the message field
            fallthrough
        case .messageField:
            let pending = AppNavigation.shared.pendingComposerDictation ?? ""
            AppNavigation.shared.pendingComposerDictation = pending.isEmpty ? text : pending + " " + text
        case .clipboard:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

// MARK: - Menu Bar View
struct MenuBarView: View {
    @ObservedObject var hotkeyManager = HotkeyManager.shared
    @ObservedObject var audioRecorder = AudioRecorder.shared
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject private var overlay = RecordingOverlayWindowController.shared

    private var phase: DictationOrb.Phase {
        if hotkeyManager.isRecording { return .recording }
        if overlay.isVisible && overlay.mode == .processing { return .processing }
        return hotkeyManager.isListening ? .idle : .inactive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Status
            HStack(spacing: 12) {
                DictationOrb(phase: phase, level: audioRecorder.audioLevel, size: 28)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SpeechToType")
                        .font(.headline)
                    Text(hotkeyManager.compactStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if let start = hotkeyManager.recordingStartedAt {
                    TimelineView(.periodic(from: start, by: 0.1)) { context in
                        Text(formatDuration(context.date.timeIntervalSince(start)))
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
            }

            // Actions
            VStack(spacing: 8) {
                if hotkeyManager.isRecording {
                    Button {
                        hotkeyManager.stopCurrentRecording()
                    } label: {
                        Label("stopRecording", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .controlSize(.large)
                } else {
                    Button {
                        hotkeyManager.startContinuousRecording()
                    } label: {
                        Label("startContinuousRecording", systemImage: "mic.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }

                if settings.textRewriteEnabled {
                    Button {
                        triggerRewriteFromMenu()
                    } label: {
                        Label("rewriteSelectedText", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)

                    Button {
                        rewriteFromClipboard()
                    } label: {
                        Label("rewriteClipboardText", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }

            // Shortcut hints
            VStack(alignment: .leading, spacing: 6) {
                shortcutHint(settings.directDictationShortcut.displayString, label: "homeHoldToDictate")
                shortcutHint(settings.continuousRecordingShortcut.displayString + " ×2", label: "homeDoubleTapContinuous")
            }

            Divider()

            MicrophoneSelectionView()

            Label {
                Text(settings.isConfigured ? "apiConfigured" : "apiKeyMissing")
            } icon: {
                Image(systemName: settings.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(settings.isConfigured ? .green : .yellow)
            }
            .font(.caption)

            Divider()

            // Window, settings, quit
            HStack(spacing: 8) {
                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                } label: {
                    Label("openMainWindow", systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .keyboardShortcut(",", modifiers: .command)
                .help("settings")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .keyboardShortcut("q", modifiers: .command)
                .help("quit")
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private func shortcutHint(_ keys: String, label: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            KeyCap(text: keys)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .insetField(cornerRadius: 8)
            }
            .buttonStyle(.plain)
            .onAppear {
                audioRecorder.refreshInputDevices()
            }
        }
    }
}
