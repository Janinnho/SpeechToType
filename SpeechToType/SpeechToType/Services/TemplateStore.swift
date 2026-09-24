//
//  TemplateStore.swift
//  SpeechToType
//
//  "Vorlagen": free-form text snippets to keep and copy. Stored as one JSON file in
//  Application Support.
//

import Foundation
import AppKit
import Combine

nonisolated struct TextTemplate: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var text: String
    let createdAt: Date
    var updatedAt: Date

    /// First non-empty line, like a note's title (empty for a blank template)
    var title: String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return String(line.prefix(80))
    }

    /// The text after the title line, flattened to one line
    var preview: String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.dropFirst().joined(separator: " ")
    }
}

final class TemplateStore: ObservableObject {
    static let shared = TemplateStore()

    /// Newest first
    @Published private(set) var templates: [TextTemplate] = []

    private let fileURL = AppDataDirectory.subdirectory("Templates").appendingPathComponent("templates.json")
    private let queue = DispatchQueue(label: "com.speechtotype.templates", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([TextTemplate].self, from: data) {
            templates = decoded
        }

        // Don't lose the last edits when the app quits within the save delay
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.pendingSave?.perform()
                self?.pendingSave?.cancel()
            }
            .store(in: &cancellables)
    }

    func template(with id: UUID) -> TextTemplate? {
        templates.first { $0.id == id }
    }

    @discardableResult
    func add(text: String = "") -> TextTemplate {
        let now = Date()
        let template = TextTemplate(id: UUID(), text: text, createdAt: now, updatedAt: now)
        templates.insert(template, at: 0)
        scheduleSave()
        return template
    }

    func update(_ id: UUID, text: String) {
        guard let index = templates.firstIndex(where: { $0.id == id }),
              templates[index].text != text else { return }
        templates[index].text = text
        templates[index].updatedAt = Date()
        scheduleSave()
    }

    func delete(_ id: UUID) {
        templates.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Writes shortly after the last change, so typing doesn't rewrite the file per keystroke.
    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = templates
        let url = fileURL
        let work = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        pendingSave = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
