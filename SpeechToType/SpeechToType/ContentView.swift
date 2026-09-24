//
//  ContentView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI

enum ContentTab: String, CaseIterable {
    case status = "status"
    case chat = "chat"
    case rewrite = "rewrite"
    case dictionary = "dictionary"
    case history = "history"
    case templates = "templates"

    var icon: String {
        switch self {
        case .status:
            return "waveform"
        case .chat:
            return "bubble.left.and.bubble.right"
        case .rewrite:
            return "wand.and.stars"
        case .dictionary:
            return "character.book.closed"
        case .history:
            return "clock"
        case .templates:
            return "note.text"
        }
    }

    var localizedName: LocalizedStringKey {
        return LocalizedStringKey(self.rawValue)
    }
}

struct ContentView: View {
    @State private var selectedTab: ContentTab = .status
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(isOnboardingComplete: $showOnboarding)
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
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 220)
            .safeAreaInset(edge: .bottom) {
                // Small settings affordance pinned to the bottom-left of the sidebar.
                // Opens the standard Settings window (same one as the menu bar item).
                SettingsLink {
                    Label("settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        } detail: {
            switch selectedTab {
            case .status:
                StartPageView {
                    selectedTab = .chat
                }
            case .chat:
                ChatView()
            case .templates:
                TemplatesView()
            case .rewrite:
                ScrollView {
                    RewriteView()
                }
            case .dictionary:
                ScrollView {
                    DictionaryView()
                }
            case .history:
                ScrollView {
                    HistoryView()
                }
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

/// The status page plus a message field: sending starts a new chat and opens it.
struct StartPageView: View {
    /// Called once a chat was started, to switch to the chat tab
    let onChatStarted: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var draft = ChatDraft()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                StatusView()
            }

            ChatComposerView(
                draft: $draft,
                model: settings.chatModel,
                placeholder: "startChatPlaceholder",
                onSelectModel: { ChatManager.shared.setModel($0, for: nil) },
                onSend: send
            )
            .frame(maxWidth: 680)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func send() {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draft.attachments.isEmpty else { return }
        ChatManager.shared.startConversation(text: text, attachments: draft.attachments)
        draft = ChatDraft()
        onChatStarted()
    }
}

#Preview {
    ContentView()
}
