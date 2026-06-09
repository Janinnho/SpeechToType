//
//  GeneralSettingsView.swift
//  SpeechToType
//
//  Settings pane: general settings (history and insertion behavior).
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("autoDelete", selection: $settings.autoDeleteOption) {
                    ForEach(AutoDeleteOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }

                Text("autoDeleteDescription")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("saveRewritesToHistory", isOn: $settings.saveRewritesToHistory)

                Text("saveRewritesToHistoryDescription")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("historySection")
            }

            Section {
                Toggle("copyToClipboardOnInsert", isOn: $settings.copyToClipboardOnInsert)

                Text("copyToClipboardOnInsertDescription")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("insertionSection")
            }
        }
        .formStyle(.grouped)
    }
}
