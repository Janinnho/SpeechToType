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
    @State private var apiKey = ""
    @State private var showingAPIKey = false
    @ObservedObject private var settings = AppSettings.shared

    private var canProceed: Bool {
        microphoneGranted && accessibilityGranted && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

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

                // Step 3: API Key Input
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.title2)
                            .foregroundColor(apiKey.isEmpty ? .orange : .green)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("openApiKey")
                                .font(.headline)
                            Text("openApiKeyDescription")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !apiKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                        }
                    }

                    HStack {
                        if showingAPIKey {
                            TextField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showingAPIKey.toggle() }) {
                            Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(!apiKey.isEmpty ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
                )
            }
            .padding(.horizontal)

            Spacer()

            // Continue Button
            VStack(spacing: 12) {
                if !canProceed {
                    Text(missingRequirementsMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }

                Button(action: completeOnboarding) {
                    Text("done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .frame(width: 500, height: 600)
        .onAppear {
            checkPermissions()
            apiKey = settings.apiKey
        }
    }

    private var missingRequirementsMessage: LocalizedStringKey {
        if !microphoneGranted || !accessibilityGranted {
            return "grantAllPermissions"
        } else if apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            return "enterApiKey"
        }
        return ""
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
        // Save API key
        settings.apiKey = apiKey.trimmingCharacters(in: .whitespaces)

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
