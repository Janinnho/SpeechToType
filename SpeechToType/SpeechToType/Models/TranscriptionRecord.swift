//
//  TranscriptionRecord.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import Foundation

struct TranscriptionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    let duration: TimeInterval
    let model: String
    
    init(id: UUID = UUID(), text: String, date: Date = Date(), duration: TimeInterval, model: String) {
        self.id = id
        self.text = text
        self.date = date
        self.duration = duration
        self.model = model
    }
}
