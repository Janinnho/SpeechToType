//
//  MarkdownView.swift
//  SpeechToType
//
//  Lightweight Markdown rendering for chat replies: headings, lists, quotes, code
//  blocks (with copy button), tables and rules. Inline formatting (bold, italic, code,
//  links) comes from AttributedString. Also copes with incomplete Markdown while a
//  reply is still streaming in (e.g. an unterminated code fence).
//

import SwiftUI
import AppKit

nonisolated struct MarkdownListItem: Equatable {
    /// "•", "☐"/"☑" for task lists, or "1." for numbered items
    let marker: String
    let indent: Int
    let text: String

    var isOrdered: Bool { marker.hasSuffix(".") }
}

nonisolated enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(language: String?, code: String)
    case list([MarkdownListItem])
    case quote(String)
    case table(header: [String], rows: [[String]])
    case rule
}

nonisolated enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block — an unterminated fence runs to the end
            if let fence = codeFence(trimmed) {
                flushParagraph()
                let language = trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !isClosingFence(lines[index], fence: fence) {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                blocks.append(.code(language: language.isEmpty ? nil : language, code: code.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let heading = heading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quote.append(quoteLine.dropFirst().trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }

            if listItem(line) != nil {
                flushParagraph()
                var items: [MarkdownListItem] = []
                while index < lines.count, let item = listItem(lines[index]) {
                    var text = item.text
                    index += 1
                    // Indented continuation lines belong to the item
                    while index < lines.count {
                        let next = lines[index]
                        let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                        guard !nextTrimmed.isEmpty, next.hasPrefix("  ") || next.hasPrefix("\t"),
                              listItem(next) == nil, codeFence(nextTrimmed) == nil else { break }
                        text += "\n" + nextTrimmed
                        index += 1
                    }
                    items.append(MarkdownListItem(marker: item.marker, indent: item.indent, text: text))
                    // A single blank line keeps the list going — unless a list of the other kind starts
                    if index + 1 < lines.count,
                       lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                       let next = listItem(lines[index + 1]),
                       next.indent > 0 || next.isOrdered == items[0].isOrdered {
                        index += 1
                    }
                }
                blocks.append(.list(items))
                continue
            }

            if index + 1 < lines.count, trimmed.contains("|"), isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let rowLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard rowLine.contains("|") else { break }
                    rows.append(tableCells(rowLine))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    /// The fence ("```" or "~~~", three or more) if the line opens a code block
    private static func codeFence(_ trimmed: String) -> String? {
        for marker in ["`", "~"] {
            let run = trimmed.prefix { String($0) == marker }
            if run.count >= 3 {
                return String(run)
            }
        }
        return nil
    }

    private static func isClosingFence(_ line: String, fence: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(fence), let marker = fence.first else { return false }
        return trimmed.allSatisfy { $0 == marker }
    }

    private static func heading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // Optional closing sequence: "## Title ##"
        if let range = text.range(of: #"\s+#+$"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return .heading(level: hashes.count, text: text)
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String) -> MarkdownListItem? {
        let expanded = line.replacingOccurrences(of: "\t", with: "    ")
        let spaces = expanded.prefix { $0 == " " }.count
        let rest = expanded.dropFirst(spaces)
        let indent = min(spaces / 2, 4)

        if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
            var text = String(rest.dropFirst(2))
            var marker = "•"
            if text.hasPrefix("[ ] ") {
                marker = "☐"
                text.removeFirst(4)
            } else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                marker = "☑"
                text.removeFirst(4)
            }
            return MarkdownListItem(marker: marker, indent: indent, text: text)
        }

        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard (1...3).contains(digits.count) else { return nil }
        let afterDigits = rest.dropFirst(digits.count)
        guard let delimiter = afterDigits.first, ".)".contains(delimiter),
              afterDigits.dropFirst().first == " " else { return nil }
        return MarkdownListItem(marker: "\(digits).", indent: indent, text: String(afterDigits.dropFirst(2)))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|"), trimmed.contains("-") else { return false }
        return tableCells(trimmed).allSatisfy { cell in
            !cell.isEmpty && cell.contains("-") && cell.allSatisfy { "-:".contains($0) }
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        return content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// Inline Markdown (bold, italic, `code`, links) as an AttributedString.
enum MarkdownInline {
    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        let codeRanges = result.runs
            .filter { $0.inlinePresentationIntent?.contains(.code) == true }
            .map(\.range)
        for range in codeRanges {
            result[range].font = .system(.body, design: .monospaced)
            result[range].backgroundColor = Color.primary.opacity(0.08)
        }
        return result
    }
}

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(MarkdownInline.attributed(text))
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let text):
            Text(MarkdownInline.attributed(text))
                .font(headingFont(level))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 6 : 2)

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.marker)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(MarkdownInline.attributed(item.text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.indent) * 18)
                }
            }

        case .quote(let text):
            Text(MarkdownInline.attributed(text))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 3)
                }

        case .table(let header, let rows):
            MarkdownTableView(header: header, rows: rows)

        case .rule:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        case 3: return .headline
        default: return .subheadline.bold()
        }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton(text: code)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06))

            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .fixedSize()
                    .padding(10)
            }
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
    }
}

private struct MarkdownTableView: View {
    let header: [String]
    let rows: [[String]]

    private var columnCount: Int {
        max(header.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        cellText(header, column)
                            .fontWeight(.semibold)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { column in
                            cellText(row, column)
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
    }

    private func cellText(_ row: [String], _ column: Int) -> some View {
        Text(MarkdownInline.attributed(column < row.count ? row[column] : ""))
            .frame(maxWidth: 320, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Copies `text` to the clipboard and briefly shows a checkmark.
struct CopyButton: View {
    let text: String
    var title: LocalizedStringKey?

    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            if let title {
                Label(copied ? "copied" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
            } else {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
        }
        .help("copy")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
