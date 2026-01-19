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
    
    private let saveKey = "transcriptionHistory"
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadRecords()
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
    
    func addRecord(_ record: TranscriptionRecord) {
        records.insert(record, at: 0)
        saveRecords()
        cleanupOldRecords()
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
