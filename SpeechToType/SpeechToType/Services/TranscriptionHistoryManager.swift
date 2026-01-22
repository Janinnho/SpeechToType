//
//  TranscriptionHistoryManager.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import Foundation
import Combine
import SwiftUI

class TranscriptionHistoryManager: ObservableObject {
    static let shared = TranscriptionHistoryManager()

    @Published var records: [TranscriptionRecord] = []

    // Statistics (persisted separately)
    @Published var totalWordsTranscribed: Int = 0
    @Published var totalTokensUsed: Int = 0
    @Published var totalRecordingDuration: TimeInterval = 0

    private let saveKey = "transcriptionHistory"
    private let statsKey = "transcriptionStats"
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadRecords()
        loadStats()
        setupAutoDelete()
    }

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([TranscriptionRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func loadStats() {
        let defaults = UserDefaults.standard
        totalWordsTranscribed = defaults.integer(forKey: "\(statsKey)_words")
        totalTokensUsed = defaults.integer(forKey: "\(statsKey)_tokens")
        totalRecordingDuration = defaults.double(forKey: "\(statsKey)_duration")
    }

    private func saveStats() {
        let defaults = UserDefaults.standard
        defaults.set(totalWordsTranscribed, forKey: "\(statsKey)_words")
        defaults.set(totalTokensUsed, forKey: "\(statsKey)_tokens")
        defaults.set(totalRecordingDuration, forKey: "\(statsKey)_duration")
    }

    func addRecord(_ record: TranscriptionRecord) {
        records.insert(record, at: 0)
        saveRecords()

        // Update statistics
        let wordCount = record.text.split(separator: " ").count
        totalWordsTranscribed += wordCount

        // Estimate tokens (roughly 0.75 words per token for English, 0.5 for German)
        let estimatedTokens = Int(Double(wordCount) * 1.3) + Int(record.duration * 16) // Audio tokens
        totalTokensUsed += estimatedTokens

        totalRecordingDuration += record.duration
        saveStats()

        cleanupOldRecords()
    }

    /// Estimated minutes saved based on typing speed (average 40 WPM vs speaking 150 WPM)
    var estimatedMinutesSaved: Double {
        // Average typing speed: 40 words per minute
        // Speaking is ~3.75x faster than typing
        let typingTimeMinutes = Double(totalWordsTranscribed) / 40.0
        let speakingTimeMinutes = totalRecordingDuration / 60.0
        return max(0, typingTimeMinutes - speakingTimeMinutes)
    }
    
    func deleteRecord(_ record: TranscriptionRecord) {
        records.removeAll { $0.id == record.id }
        saveRecords()
    }
    
    func deleteRecords(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        saveRecords()
    }
    
    func deleteAllRecords() {
        records.removeAll()
        saveRecords()
    }
    
    func cleanupOldRecords() {
        let option = AppSettings.shared.autoDeleteOption
        guard let maxAge = option.timeInterval else { return }
        
        let cutoffDate = Date().addingTimeInterval(-maxAge)
        records.removeAll { $0.date < cutoffDate }
        saveRecords()
    }
    
    private func setupAutoDelete() {
        // Check for old records periodically
        Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.cleanupOldRecords()
            }
            .store(in: &cancellables)
    }
}
