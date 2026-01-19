//
//  ContentView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI
import AVFoundation

enum ContentTab: String, CaseIterable {
    case status = "status"
    case history = "history"
    case settings = "settings"
    
    var icon: String {
        switch self {
        case .status:
            return "waveform"
        case .history:
            return "clock"
        case .settings:
            return "gear"
        }
    }
    
    var localizedName: LocalizedStringKey {
        return LocalizedStringKey(self.rawValue)
    }
}

struct ContentView: View {
    @State private var selectedTab: ContentTab = .status
    @ObservedObject var hotkeyManager = HotkeyManager.shared
    @ObservedObject var audioRecorder = AudioRecorder.shared
    @ObservedObject var historyManager = TranscriptionHistoryManager.shared
    @ObservedObject var settings = AppSettings.shared
    
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    
    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(isOnboardingComplete: $showOnboarding)
                    .onChange(of: showOnboarding) { _, newValue in
                        if newValue == false {
                            // Onboarding abgeschlossen, starte die App
                            setupHotkeyHandlers()
                        }
                    }
            } else {
                mainContent
            }
        }
    }
    
    private var mainContent: some View {
        NavigationSplitView {
            List(ContentTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.localizedName, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150)
        } detail: {
            switch selectedTab {
            case .status:
                StatusView()
            case .history:
                HistoryView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            setupHotkeyHandlers()
        }
        .alert("error", isPresented: $showError) {
            Button("ok") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func setupHotkeyHandlers() {
        hotkeyManager.onRecordingStarted = {
            startRecording()
        }
        
        hotkeyManager.onRecordingStopped = {
            stopRecordingAndTranscribe()
        }
        
        hotkeyManager.startListening()
    }
    
    private func startRecording() {
        guard !isProcessing else { return }
        
        do {
            try audioRecorder.startRecording()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            hotkeyManager.statusMessage = "Fehler bei der Aufnahme"
        }
    }
    
    private func stopRecordingAndTranscribe() {
        guard let (audioURL, duration) = audioRecorder.stopRecording() else {
            hotkeyManager.statusMessage = "Keine Aufnahme verfügbar"
            return
        }
        
        // Don't process very short recordings (less than 0.5 seconds)
        guard duration >= 0.5 else {
            hotkeyManager.statusMessage = "Aufnahme zu kurz"
            audioRecorder.cleanupRecording(at: audioURL)
            return
        }
        
        isProcessing = true
        hotkeyManager.statusMessage = "Transkribiere..."
        
        Task {
            do {
                let text = try await OpenAIService.shared.transcribe(
                    audioURL: audioURL,
                    model: settings.selectedModel
                )
                
                await MainActor.run {
                    // Insert text at cursor
                    TextInputService.shared.insertText(text)
                    
                    // Save to history
                    let record = TranscriptionRecord(
                        text: text,
                        duration: duration,
                        model: settings.selectedModel.displayName
                    )
                    historyManager.addRecord(record)
                    
                    hotkeyManager.statusMessage = "Erfolgreich transkribiert!"
                    hotkeyManager.lastError = nil
                    isProcessing = false
                    
                    // Reset status after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if !hotkeyManager.isRecording && !isProcessing {
                            hotkeyManager.statusMessage = "Bereit"
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    hotkeyManager.statusMessage = "Fehler"
                    hotkeyManager.lastError = error.localizedDescription
                    isProcessing = false
                }
            }
            
            // Cleanup audio file
            audioRecorder.cleanupRecording(at: audioURL)
        }
    }
}

#Preview {
    ContentView()
}
