//
//  ContentView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI

enum ContentTab: String, CaseIterable {
    case status = "status"
    case history = "history"
    case settings = "settings"
    
    var icon: String {
        switch self {
        case .status:
            return "waveform"
        case .history:
            return "clock"
        case .settings:
            return "gear"
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
        } detail: {
            ScrollView {
                switch selectedTab {
                case .status:
                    StatusView()
                case .history:
                    HistoryView()
                case .settings:
                    SettingsView()
                }
            }
        }
        .frame(minWidth: 650, minHeight: 450)
    }
}

#Preview {
    ContentView()
}
