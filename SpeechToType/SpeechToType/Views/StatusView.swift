//
//  StatusView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI

struct StatusView: View {
    @ObservedObject var hotkeyManager = HotkeyManager.shared
    @ObservedObject var audioRecorder = AudioRecorder.shared
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Recording indicator
            ZStack {
                Circle()
                    .fill(recordingColor.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Circle()
                    .fill(recordingColor.opacity(0.4))
                    .frame(width: 70, height: 70)
                
                Circle()
                    .fill(recordingColor)
                    .frame(width: 40, height: 40)
                
                if hotkeyManager.isRecording {
                    Circle()
                        .stroke(recordingColor, lineWidth: 3)
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulseScale)
                        .opacity(2 - pulseScale)
                        .animation(
                            Animation.easeOut(duration: 1)
                                .repeatForever(autoreverses: false),
                            value: hotkeyManager.isRecording
                        )
                }
            }
            .animation(.easeInOut(duration: 0.3), value: hotkeyManager.isRecording)
            
            // Status text
            Text(hotkeyManager.statusMessage)
                .font(.headline)
                .foregroundColor(.primary)
            
            // Recording duration
            if hotkeyManager.isRecording {
                Text(formatDuration(audioRecorder.recordingDuration))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Hotkey hint
            VStack(spacing: 4) {
                Text("pressAndHold")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    KeyCapView(text: settings.useControlKey ? "⌃ Control" : "D")
                }
                
                Text("toDictate")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
            
            // Error message
            if let error = hotkeyManager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Configuration warning
            if !settings.isConfigured {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("apiKeyNotConfigured")
                        .font(.caption)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .frame(minWidth: 250)
    }
    
    private var recordingColor: Color {
        hotkeyManager.isRecording ? .red : (hotkeyManager.isListening ? .green : .gray)
    }
    
    private var pulseScale: CGFloat {
        hotkeyManager.isRecording ? 1.5 : 1.0
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

struct KeyCapView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(.body, design: .rounded))
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
    }
}

#Preview {
    StatusView()
}
