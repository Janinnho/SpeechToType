//
//  ContentView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI
import Combine

enum ContentTab: String, CaseIterable {
    case home = "home"
    case history = "history"
    case dictionary = "dictionary"
    case chat = "chat"
    case rewrite = "rewrite"
    case templates = "templates"

    var icon: String {
        switch self {
        case .home:
            return "house"
        case .history:
            return "clock"
        case .dictionary:
            return "character.book.closed"
        case .chat:
            return "bubble.left.and.bubble.right"
        case .rewrite:
            return "wand.and.stars"
        case .templates:
            return "note.text"
        }
    }

    var localizedName: LocalizedStringKey {
        return LocalizedStringKey(self.rawValue)
    }
}

/// Which page the main window shows, so other views (e.g. the dashboard) can jump to a
/// chat or a history entry.
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()

    @Published var selectedTab: ContentTab = .home
    /// History entry that is selected in the history page
    @Published var historySelection: UUID?
    /// Text dictated with the start page's record button, waiting to be added to the start
    /// page's message field (see `ButtonDictationTarget.messageField`)
    @Published var pendingComposerDictation: String?

    func openHistory(_ recordID: UUID?) {
        historySelection = recordID
        selectedTab = .history
    }

    /// Opens a conversation, or a new chat for nil
    func openChat(_ conversationID: UUID?) {
        ChatManager.shared.selectedConversationID = conversationID
        selectedTab = .chat
    }
}

struct ContentView: View {
    @ObservedObject private var navigation = AppNavigation.shared
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(isOnboardingComplete: $showOnboarding)
            } else {
                mainContent
            }
        }
        .containerBackground(for: .window) {
            AppBackground()
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            List(ContentTab.allCases, id: \.self, selection: $navigation.selectedTab) { tab in
                Label(tab.localizedName, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) {
                // Opens the standard Settings window (same one as the menu bar item)
                SettingsLink {
                    Label("settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } detail: {
            Group {
                switch navigation.selectedTab {
                case .home:
                    HomeView()
                case .history:
                    HistoryView()
                case .dictionary:
                    DictionaryView()
                case .chat:
                    ChatView()
                case .rewrite:
                    RewriteView()
                case .templates:
                    TemplatesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 560)
    }

}

#Preview {
    ContentView()
}
