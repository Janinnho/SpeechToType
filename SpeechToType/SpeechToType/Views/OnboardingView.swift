//
//  OnboardingView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI
import AVFoundation
import FoundationModels

struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    @State private var showingAPIKey = false
    @State private var showingTextProcessingAPIKey = false
    @State private var showingAnthropicAPIKey = false
    @State private var ollamaModels: [String] = []
    @State private var isLoadingOllamaModels = false
    @ObservedObject private var settings = AppSettings.shared

    private var canProceed: Bool {
        microphoneGranted && accessibilityGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)

                Text("onboardingTitle")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("onboardingSubtitle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // MARK: - Permissions
                    Text("onboardingPermissions")
                        .font(.headline)
                        .padding(.top, 8)

                    PermissionRow(
                        icon: "mic.fill",
                        iconColor: .red,
                        title: String(localized: "microphoneAccess"),
                        description: String(localized: "microphoneDescription"),
                        isGranted: microphoneGranted,
                        buttonTitle: String(localized: "grantAccess"),
                        action: requestMicrophoneAccess
                    )

                    PermissionRow(
                        icon: "hand.raised.fill",
                        iconColor: .blue,
                        title: String(localized: "accessibilityAccess"),
                        description: String(localized: "accessibilityOnboardingDescription"),
                        isGranted: accessibilityGranted,
                        buttonTitle: String(localized: "openInSettings"),
                        action: requestAccessibilityAccess
                    )

                    Divider()
                        .padding(.vertical, 4)

                    // MARK: - Speech Model Provider
                    Text("speechModelConfigSection")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        Picker("speechModelProviderPicker", selection: $settings.speechModelProvider) {
                            ForEach(SpeechModelProvider.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }

                        switch settings.speechModelProvider {
                        case .openAI:
                            apiKeyField(
                                title: "openApiKey",
                                placeholder: "sk-...",
                                text: $settings.apiKey,
                                showing: $showingAPIKey,
                                description: "openApiKeyDescription"
                            )

                        case .local:
                            VStack(alignment: .leading, spacing: 4) {
                                Text("whisperServerURL")
                                    .font(.caption).fontWeight(.semibold)
                                TextField("http://yourserver/v1/audio/transcriptions", text: $settings.whisperServerURL)
                                    .textFieldStyle(.roundedBorder)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("whisperServerModel")
                                    .font(.caption).fontWeight(.semibold)
                                TextField("whisper-1", text: $settings.whisperServerModel)
                                    .textFieldStyle(.roundedBorder)
                            }

                        case .appleSpeech:
                            Text("appleSpeechDescription")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)

                    Divider()
                        .padding(.vertical, 4)

                    // MARK: - Text Processing Provider
                    Text("textRewriteSection")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("textRewriteEnabled", isOn: $settings.textRewriteEnabled)

                        if settings.textRewriteEnabled {
                            Picker("textProcessingProviderPicker", selection: $settings.textProcessingProvider) {
                                ForEach(TextProcessingProvider.allCases, id: \.self) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }

                            switch settings.textProcessingProvider {
                            case .openAI:
                                apiKeyField(
                                    title: "textProcessingOpenAIApiKey",
                                    placeholder: "sk-...",
                                    text: $settings.textProcessingOpenAIApiKey,
                                    showing: $showingTextProcessingAPIKey,
                                    description: "textProcessingOpenAIApiKeyDescription"
                                )

                            case .anthropic:
                                apiKeyField(
                                    title: "anthropicApiKey",
                                    placeholder: "sk-ant-...",
                                    text: $settings.anthropicApiKey,
                                    showing: $showingAnthropicAPIKey,
                                    description: "anthropicApiKeyDescription"
                                )

                            case .ollama:
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ollamaServerURL")
                                        .font(.caption).fontWeight(.semibold)
                                    TextField("http://localhost:11434", text: $settings.ollamaServerURL)
                                        .textFieldStyle(.roundedBorder)
                                }
                                Text("ollamaDescription")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                            case .appleIntelligence:
                                let model = SystemLanguageModel.default
                                HStack {
                                    if case .available = model.availability {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("appleIntelligenceAvailable")
                                            .foregroundColor(.green)
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("appleIntelligenceUnavailable")
                                            .foregroundColor(.orange)
                                    }
                                }
                                .font(.caption)

                                Text("appleIntelligenceDescription")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Continue Button
            VStack(spacing: 8) {
                if !canProceed {
                    Text("grantAllPermissions")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Button(action: completeOnboarding) {
                    Text("done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canProceed)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 680)
        .onAppear {
            checkPermissions()
        }
    }

    // MARK: - Reusable API Key Field

    @ViewBuilder
    private func apiKeyField(
        title: LocalizedStringKey,
        placeholder: String,
        text: Binding<String>,
        showing: Binding<Bool>,
        description: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption).fontWeight(.semibold)
            HStack {
                if showing.wrappedValue {
                    TextField(placeholder, text: text)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField(placeholder, text: text)
                        .textFieldStyle(.roundedBorder)
                }
                Button(action: { showing.wrappedValue.toggle() }) {
                    Image(systemName: showing.wrappedValue ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func checkPermissions() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
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
