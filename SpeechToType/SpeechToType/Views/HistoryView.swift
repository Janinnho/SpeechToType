//
//  HistoryView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI

enum HistoryFilter: String, CaseIterable {
    case all
    case transcriptions
    case rewrites

    var displayName: LocalizedStringKey {
        switch self {
        case .all:
            return "filterAll"
        case .transcriptions:
            return "filterTranscriptions"
        case .rewrites:
            return "filterRewrites"
        }
    }
}

struct HistoryView: View {
    @ObservedObject var historyManager = TranscriptionHistoryManager.shared
    @State private var searchText = ""
    @State private var showingDeleteAllAlert = false
    @State private var selectedRecord: TranscriptionRecord?
    @State private var selectedFilter: HistoryFilter = .all

    var filteredRecords: [TranscriptionRecord] {
        var records = historyManager.records

        // Filter by type
        switch selectedFilter {
        case .all:
            break
        case .transcriptions:
            records = records.filter { $0.recordType == .transcription }
        case .rewrites:
            records = records.filter { $0.recordType == .rewrite }
        }

        // Filter by search text
        if !searchText.isEmpty {
            records = records.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }

        return records
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("transcriptionHistory")
                    .font(.headline)
                
                Spacer()
                
                if !historyManager.records.isEmpty {
                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        Label("deleteAll", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
            }
            .padding()
            
            // Filter picker
            Picker("", selection: $selectedFilter) {
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(String(localized: "search"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            Divider()
            
            // Content
            if filteredRecords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "waveform" : "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "noTranscriptions" : "noResults")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "holdToDictate" : "tryDifferentSearch")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(filteredRecords) { record in
                        HistoryRowView(record: record, isSelected: selectedRecord?.id == record.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedRecord = record
                            }
                            .contextMenu {
                                Button {
                                    copyToClipboard(record.text)
                                } label: {
                                    Label("copy", systemImage: "doc.on.doc")
                                }
                                
                                Button {
                                    TextInputService.shared.insertText(record.text)
                                } label: {
                                    Label("insert", systemImage: "text.cursor")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    historyManager.deleteRecord(record)
                                } label: {
                                    Label("delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { offsets in
                        historyManager.deleteRecords(at: offsets)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 350, minHeight: 400)
        .alert("deleteAllConfirmation", isPresented: $showingDeleteAllAlert) {
            Button("cancel", role: .cancel) {}
            Button("delete", role: .destructive) {
                historyManager.deleteAllRecords()
            }
        } message: {
            Text("deleteAllWarning")
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct HistoryRowView: View {
    let record: TranscriptionRecord
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Record type indicator
            HStack {
                Image(systemName: record.recordType == .transcription ? "waveform" : "pencil")
                    .foregroundColor(record.recordType == .transcription ? .blue : .orange)
                    .font(.caption)
                Text(record.recordType == .transcription ? "transcription" : "rewrite")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Show original text for rewrites
            if record.recordType == .rewrite, let original = record.originalText {
                Text(original)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .strikethrough()

                Image(systemName: "arrow.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(record.text)
                .font(.body)
                .lineLimit(3)

            HStack {
                Label(formatDate(record.date), systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if record.recordType == .transcription && record.duration > 0 {
                    Label(formatDuration(record.duration), systemImage: "waveform")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(record.model)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}

#Preview {
    HistoryView()
}
