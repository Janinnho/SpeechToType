//
//  ContentView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI

enum ContentTab: String, CaseIterable {
    case status = "status"
    case rewrite = "rewrite"
    case dictionary = "dictionary"
    case history = "history"

    var icon: String {
        switch self {
        case .status:
            return "waveform"
        case .rewrite:
            return "wand.and.stars"
        case .dictionary:
            return "character.book.closed"
        case .history:
            return "clock"
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
            ScrollView {
                switch selectedTab {
                case .status:
                    StatusView()
                case .rewrite:
                    RewriteView()
                case .dictionary:
                    DictionaryView()
                case .history:
                    HistoryView()
                }
            }
        }
        .frame(minWidth: 650, minHeight: 450)
    }
}

#Preview {
    ContentView()
}
