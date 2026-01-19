//
//  OnboardingView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    @State private var currentStep = 0
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                
                Text("onboardingTitle")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("onboardingSubtitle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            Divider()
            
            // Steps
            VStack(alignment: .leading, spacing: 20) {
                // Step 1: Microphone
                PermissionRow(
                    icon: "mic.fill",
                    iconColor: .red,
                    title: String(localized: "microphoneAccess"),
                    description: String(localized: "microphoneDescription"),
                    isGranted: microphoneGranted,
                    buttonTitle: String(localized: "grantAccess"),
                    action: requestMicrophoneAccess
                )
                
                // Step 2: Accessibility
                PermissionRow(
                    icon: "hand.raised.fill",
                    iconColor: .blue,
                    title: String(localized: "accessibilityAccess"),
                    description: String(localized: "accessibilityOnboardingDescription"),
                    isGranted: accessibilityGranted,
                    buttonTitle: String(localized: "openInSettings"),
                    action: requestAccessibilityAccess
                )
                
                // Step 3: API Key hint
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("openApiKey")
                            .font(.headline)
                        Text("onboardingApiKeyHint")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Continue Button
            VStack(spacing: 12) {
                if !microphoneGranted || !accessibilityGranted {
                    Text("grantAllPermissions")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Button(action: completeOnboarding) {
                    Text("done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!microphoneGranted || !accessibilityGranted)
                .controlSize(.large)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .frame(width: 500, height: 550)
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        // Check microphone
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        
        // Check accessibility
        accessibilityGranted = AXIsProcessTrusted()
    }
    
    private func requestMicrophoneAccess() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                microphoneGranted = granted
            }
        }
    }
    
    private func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // Check periodically if permission was granted
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if AXIsProcessTrusted() {
                accessibilityGranted = true
                timer.invalidate()
            }
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isOnboardingComplete = true
    }
}

struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let buttonTitle: String
    let action: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isGranted ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }
}

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
}
