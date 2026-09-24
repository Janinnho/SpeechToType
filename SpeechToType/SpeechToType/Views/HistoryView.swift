//
//  HistoryView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//
//  Past dictations and rewrites: a searchable list grouped by day on the left, the
//  selected entry with its full text, details and actions on the right.
//

import SwiftUI
import AppKit

enum HistoryFilter: String, CaseIterable {
    case all
    case transcriptions
    case rewrites

    var displayName: LocalizedStringKey {
        switch self {
        case .all:
            return "filterAll"
        case .transcriptions:
            return "filterDictations"
        case .rewrites:
            return "filterRewrites"
        }
    }
}

private struct HistoryDay: Identifiable {
    let day: Date
    let records: [TranscriptionRecord]

    var id: Date { day }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "chatSectionToday") }
        if calendar.isDateInYesterday(day) { return String(localized: "chatSectionYesterday") }
        if calendar.isDate(day, equalTo: Date(), toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return day.formatted(.dateTime.day().month(.wide).year())
    }
}

struct HistoryView: View {
    @ObservedObject private var historyManager = TranscriptionHistoryManager.shared
    @ObservedObject private var navigation = AppNavigation.shared
    @State private var searchText = ""
    @State private var selectedFilter: HistoryFilter = .all
    @State private var showingDeleteAllAlert = false

    private var filteredRecords: [TranscriptionRecord] {
        var records = historyManager.records
        switch selectedFilter {
        case .all:
            break
        case .transcriptions:
            records = records.filter { $0.recordType == .transcription }
        case .rewrites:
            records = records.filter { $0.recordType == .rewrite }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            records = records.filter {
                $0.text.localizedCaseInsensitiveContains(query) || ($0.originalText?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return records
    }

    private var days: [HistoryDay] {
        let grouped = Dictionary(grouping: filteredRecords) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            HistoryDay(day: day, records: grouped[day, default: []].sorted { $0.date > $1.date })
        }
    }

    private var selectedRecord: TranscriptionRecord? {
        guard let id = navigation.historySelection else { return nil }
        return historyManager.records.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 14) {
            listPanel
                .frame(width: 330)

            Group {
                if let record = selectedRecord {
                    HistoryDetailView(record: record) {
                        delete(record)
                    }
                    .id(record.id)
                } else {
                    EmptyStateView(
                        icon: "clock",
                        title: "historyNoSelection",
                        message: historyManager.records.isEmpty ? "historyEmptyMessage" : nil
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .onAppear {
            if selectedRecord == nil {
                navigation.historySelection = filteredRecords.first?.id
            }
        }
        .alert("deleteAllConfirmation", isPresented: $showingDeleteAllAlert) {
            Button("cancel", role: .cancel) {}
            Button("delete", role: .destructive) {
                historyManager.deleteAllRecords()
                navigation.historySelection = nil
            }
        } message: {
            Text("deleteAllWarning")
        }
    }

    // MARK: - List

    private var listPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("history")
                    .font(.title2.weight(.bold))
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        Label("deleteAll", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(historyManager.records.isEmpty)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)

            PanelSearchField(text: $searchText)

            HistoryFilterBar(selection: $selectedFilter)

            if filteredRecords.isEmpty {
                EmptyStateView(
                    icon: searchText.isEmpty ? "waveform" : "magnifyingglass",
                    title: searchText.isEmpty ? "noTranscriptions" : "noResults",
                    message: searchText.isEmpty ? "historyEmptyMessage" : "tryDifferentSearch"
                )
            } else {
                List(selection: $navigation.historySelection) {
                    ForEach(days) { day in
                        Section(day.title) {
                            ForEach(day.records) { record in
                                HistoryRow(record: record)
                                    .tag(record.id)
                                    .contextMenu {
                                        Button {
                                            copyToClipboard(record.text)
                                        } label: {
                                            Label("copy", systemImage: "doc.on.doc")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            delete(record)
                                        } label: {
                                            Label("delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onDeleteCommand {
                    if let selectedRecord {
                        delete(selectedRecord)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        // Nothing may spill out of the panel (e.g. under the sidebar)
        .clipShape(.rect(cornerRadius: 24))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: - Actions

    /// Deletes a record and moves the selection to its neighbor in the list
    private func delete(_ record: TranscriptionRecord) {
        if navigation.historySelection == record.id {
            let records = filteredRecords
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                let neighbor = records.indices.contains(index + 1) ? records[index + 1] : (index > 0 ? records[index - 1] : nil)
                navigation.historySelection = neighbor?.id
            }
        }
        historyManager.deleteRecord(record)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Filter

/// Filter tabs that always fit the panel. A segmented Picker sizes all segments for its
/// longest title and can end up wider than the panel.
private struct HistoryFilterBar: View {
    @Binding var selection: HistoryFilter
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selection = filter
                    }
                } label: {
                    Text(filter.displayName)
                        .font(.callout.weight(selection == filter ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if selection == filter {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.3))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

// MARK: - Row

struct HistoryRow: View {
    let record: TranscriptionRecord

    private var isTranscription: Bool {
        record.recordType == .transcription
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isTranscription ? "waveform" : "wand.and.stars")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isTranscription ? Color.blue : Color.orange)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.text)
                    .font(.callout)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(record.date, format: .dateTime.hour().minute())
                    if isTranscription && record.duration > 0 {
                        Text("·")
                        Text(formatDuration(record.duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Detail

struct HistoryDetailView: View {
    let record: TranscriptionRecord
    let onDelete: () -> Void

    private var isTranscription: Bool {
        record.recordType == .transcription
    }

    /// App that was active before SpeechToType — "Insert" pastes the text there
    private var targetApp: NSRunningApplication? {
        TextInputService.shared.getPreviousApp()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                FlowLayout(spacing: 8) {
                    if !record.model.isEmpty {
                        InfoChip(icon: "cpu", text: record.model)
                    }
                    if isTranscription && record.duration > 0 {
                        InfoChip(icon: "timer", text: formatDuration(record.duration))
                    }
                    InfoChip(icon: "text.word.spacing", text: String(format: String(localized: "historyWordCount %lld"), wordCount))
                    InfoChip(icon: "character.cursor.ibeam", text: String(format: String(localized: "historyCharacterCount %lld"), record.text.count))
                }

                if record.recordType == .rewrite, let original = record.originalText {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("historyOriginal")
                        Text(original)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .glassCard(padding: 16, cornerRadius: 18)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if record.recordType == .rewrite {
                        SectionTitle("historyResult")
                    }
                    Text(record.text)
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .glassCard(padding: 20, cornerRadius: 22)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            IconBadge(
                systemName: isTranscription ? "waveform" : "wand.and.stars",
                color: isTranscription ? .blue : .orange,
                size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(isTranscription ? "transcription" : "rewrite")
                    .font(.title2.weight(.bold))
                Text(record.date.formatted(date: .complete, time: .shortened))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    CopyButton(text: record.text, title: "copy")
                        .buttonStyle(.glass)

                    Button(action: insertIntoTargetApp) {
                        Label {
                            if let name = targetApp?.localizedName {
                                Text(String(format: String(localized: "historyInsertInto %@"), name))
                            } else {
                                Text("insert")
                            }
                        } icon: {
                            Image(systemName: "text.cursor")
                        }
                    }
                    .buttonStyle(.glassProminent)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.glass)
                    .help("delete")
                }
            }
        }
    }

    private var wordCount: Int {
        record.text.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// Switches back to the app that was active before and pastes the text there
    private func insertIntoTargetApp() {
        let text = record.text
        guard let app = targetApp else {
            TextInputService.shared.insertText(text)
            return
        }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            TextInputService.shared.insertText(text)
        }
    }
}

private func formatDuration(_ duration: TimeInterval) -> String {
    let seconds = Int(duration)
    return seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
}
