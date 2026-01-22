//
//  TextRewritePopupWindow.swift
//  SpeechToType
//
//  Created on 22.01.26.
//

import SwiftUI
import AppKit
import Combine

class TextRewriteWindowController: NSObject, ObservableObject {
    static let shared = TextRewriteWindowController()

    private var popupWindow: NSWindow?
    @Published var selectedText: String = ""
    @Published var isVisible = false

    private override init() {
        super.init()
    }

    func show(with selectedText: String) {
        self.selectedText = selectedText

        // Close existing window if any
        popupWindow?.close()

        let contentView = TextRewritePopupView(controller: self)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = String(localized: "rewriteTitle")
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible

        popupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }

    func hide() {
        popupWindow?.close()
        popupWindow = nil
        isVisible = false
    }

    func insertResult(_ text: String) {
        hide()
        // Insert the rewritten text
        TextInputService.shared.insertText(text)
    }
}

struct TextRewritePopupView: View {
    @ObservedObject var controller: TextRewriteWindowController
    @ObservedObject var settings = AppSettings.shared
    @State private var selectedMode: RewriteMode = .grammar
    @State private var customPrompt: String = ""
    @State private var isProcessing = false
    @State private var resultText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            // Mode selection
            VStack(alignment: .leading, spacing: 8) {
                Text("rewriteSelectMode")
                    .font(.headline)

                Picker("", selection: $selectedMode) {
                    ForEach(RewriteMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Custom prompt field (only shown when custom mode is selected)
            if selectedMode == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    Text("rewriteCustomPromptLabel")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField(String(localized: "rewriteCustomPromptPlaceholder"), text: $customPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...5)
                }
            }

            // Selected text preview
            VStack(alignment: .leading, spacing: 4) {
                Text("rewriteSelectedText")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ScrollView {
                    Text(controller.selectedText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 60)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            }

            // Result preview (if available)
            if !resultText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("rewriteResult")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ScrollView {
                        Text(resultText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 60)
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            Spacer()

            // Action buttons
            HStack {
                Button("cancel") {
                    controller.hide()
                }
                .keyboardShortcut(.escape)

                Spacer()

                if !resultText.isEmpty {
                    Button("rewriteInsert") {
                        controller.insertResult(resultText)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                } else {
                    Button("rewriteProcess") {
                        processText()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing || (selectedMode == .custom && customPrompt.isEmpty))
                    .keyboardShortcut(.return)
                }
            }
        }
        .padding()
        .frame(width: 400, height: 350)
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("rewriteProcessing")
                            .foregroundColor(.white)
                            .padding(.top, 8)
                    }
                }
                .cornerRadius(12)
            }
        }
    }

    private func processText() {
        isProcessing = true
        errorMessage = nil
        resultText = ""

        Task {
            do {
                let result = try await TextRewriteService.shared.rewriteText(
                    controller.selectedText,
                    mode: selectedMode,
                    customPrompt: selectedMode == .custom ? customPrompt : nil
                )

                await MainActor.run {
                    resultText = result
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

#Preview {
    TextRewritePopupView(controller: TextRewriteWindowController.shared)
}
