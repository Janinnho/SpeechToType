//
//  TemplateStore.swift
//  SpeechToType
//
//  "Vorlagen": free-form text snippets with an optional title, to keep and copy. Stored as
//  one JSON file in Application Support.
//

import Foundation
import AppKit
import Combine

nonisolated struct TextTemplate: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// Given by the user; may be empty, then the text's first line stands in
    var title: String
    var text: String
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID, title: String, text: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, text, createdAt, updatedAt
    }

    /// Templates saved before titles existed have no `title` key
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// The title, or else the text's first non-empty line like a note's title (empty for a
    /// blank template)
    var displayTitle: String {
        let title = trimmedTitle
        return title.isEmpty ? String((lines.first ?? "").prefix(80)) : title
    }

    /// The text flattened to one line, without the line that stands in for a missing title
    var preview: String {
        (trimmedTitle.isEmpty ? lines.dropFirst() : lines[...]).joined(separator: " ")
    }

    /// Neither a title nor any text
    var isBlank: Bool {
        trimmedTitle.isEmpty && lines.isEmpty
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Non-empty lines of the text
    private var lines: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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
    func add(title: String = "", text: String = "") -> TextTemplate {
        let now = Date()
        let template = TextTemplate(id: UUID(), title: title, text: text, createdAt: now, updatedAt: now)
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

    func update(_ id: UUID, title: String) {
        // One line: pasted line breaks become spaces
        let title = title.components(separatedBy: .newlines).joined(separator: " ")
        guard let index = templates.firstIndex(where: { $0.id == id }),
              templates[index].title != title else { return }
        templates[index].title = title
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
