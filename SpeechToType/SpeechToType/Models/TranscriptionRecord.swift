//
//  TranscriptionRecord.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import Foundation

enum RecordType: String, Codable {
    case transcription
    case rewrite
}

struct TranscriptionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    let duration: TimeInterval
    let model: String
    let recordType: RecordType
    let originalText: String?  // For rewrites, stores the original text

    init(id: UUID = UUID(), text: String, date: Date = Date(), duration: TimeInterval, model: String, recordType: RecordType = .transcription, originalText: String? = nil) {
        self.id = id
        self.text = text
        self.date = date
        self.duration = duration
        self.model = model
        self.recordType = recordType
        self.originalText = originalText
    }
}
