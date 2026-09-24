//
//  ChatSettingsView.swift
//  SpeechToType
//
//  Settings pane: chat (custom instructions, generated titles, stored chats).
//

import SwiftUI

struct ChatSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject private var manager = ChatManager.shared
    @State private var showingDeleteAllAlert = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("chatCustomInstructions")
                        .font(.headline)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $settings.chatCustomInstructions)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .frame(minHeight: 140)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)

                        if settings.chatCustomInstructions.isEmpty {
                            Text("chatCustomInstructionsPlaceholder")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .allowsHitTesting(false)
                        }
                    }

                    Text("chatCustomInstructionsDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle("chatAutoGenerateTitles", isOn: $settings.chatAutoGenerateTitles)

                Text("chatAutoGenerateTitlesDescription")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("chatSettingsSection")
            }

            Section {
                HStack {
                    Text(String(format: String(localized: "chatConversationCount %lld"), manager.conversations.count))
                    Spacer()
                    Button("chatDeleteAll", role: .destructive) {
                        showingDeleteAllAlert = true
                    }
                    .disabled(manager.conversations.isEmpty)
                }

                Text("chatStorageDescription")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("chatStorageSection")
            }
        }
        .formStyle(.grouped)
        .alert("chatDeleteAllConfirmation", isPresented: $showingDeleteAllAlert) {
            Button("cancel", role: .cancel) {}
            Button("delete", role: .destructive) {
                manager.deleteAll()
            }
        } message: {
            Text("chatDeleteAllWarning")
        }
    }
}
