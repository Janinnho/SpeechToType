//
//  AboutSettingsView.swift
//  SpeechToType
//
//  Settings pane: version, automatic updates (Sparkle), and links.
//

import SwiftUI
import Sparkle

struct AboutSettingsView: View {
    private let updater: SPUUpdater?
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updater: SPUUpdater? = nil) {
        self.updater = updater
        self._automaticallyChecksForUpdates = State(initialValue: updater?.automaticallyChecksForUpdates ?? true)
        self._automaticallyDownloadsUpdates = State(initialValue: updater?.automaticallyDownloadsUpdates ?? false)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                        .foregroundColor(.secondary)
                }

                if let updater = updater {
                    Toggle("autoCheckUpdates", isOn: $automaticallyChecksForUpdates)
                        .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                            updater.automaticallyChecksForUpdates = newValue
                        }

                    Toggle("autoDownloadUpdates", isOn: $automaticallyDownloadsUpdates)
                        .disabled(!automaticallyChecksForUpdates)
                        .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                            updater.automaticallyDownloadsUpdates = newValue
                        }

                    Button("checkForUpdates") {
                        updater.checkForUpdates()
                    }
                }

                Link("OpenAI API Documentation", destination: URL(string: "https://platform.openai.com/docs/api-reference/audio")!)
            } header: {
                Text("about")
            }
        }
        .formStyle(.grouped)
    }
}
