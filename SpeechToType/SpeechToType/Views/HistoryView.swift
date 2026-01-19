//
//  HistoryView.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyManager = TranscriptionHistoryManager.shared
    @State private var searchText = ""
    @State private var showingDeleteAllAlert = false
    @State private var selectedRecord: TranscriptionRecord?
    
    var filteredRecords: [TranscriptionRecord] {
        if searchText.isEmpty {
            return historyManager.records
        }
        return historyManager.records.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
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
            Text(record.text)
                .font(.body)
                .lineLimit(3)
            
            HStack {
                Label(formatDate(record.date), systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Label(formatDuration(record.duration), systemImage: "waveform")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
