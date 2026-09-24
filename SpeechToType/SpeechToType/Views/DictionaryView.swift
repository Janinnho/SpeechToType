//
//  DictionaryView.swift
//  SpeechToType
//
//  Created on 28.05.26.
//

import SwiftUI

struct DictionaryView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var newWord: String = ""
    @FocusState private var wordFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("dictionary", subtitle: "dictionarySubtitle")

                // Words
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("dictionaryWordsTitle", systemImage: "textformat.abc")
                            .font(.headline)
                        Spacer()
                        if !settings.dictionaryWords.isEmpty {
                            Text(settings.dictionaryWords.count.formatted())
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(String(localized: "dictionaryWordPlaceholder"), text: $newWord)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .insetField(cornerRadius: 10)
                            .focused($wordFieldFocused)
                            .onSubmit(addWord)

                        Button(action: addWord) {
                            Label("dictionaryAdd", systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if settings.dictionaryWords.isEmpty {
                        Text("dictionaryEmptyWords")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(settings.dictionaryWords, id: \.self) { word in
                                WordChip(word: word) {
                                    removeWord(word)
                                }
                            }
                        }
                    }
                }
                .glassCard(padding: 20, cornerRadius: 24)

                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Label("dictionaryInstructionsTitle", systemImage: "text.alignleft")
                        .font(.headline)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $settings.dictionaryInstructions)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 140)

                        if settings.dictionaryInstructions.isEmpty {
                            Text("dictionaryInstructionsPlaceholder")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(10)
                    .insetField(cornerRadius: 14)
                }
                .glassCard(padding: 20, cornerRadius: 24)

                Label("dictionaryDescription", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.dictionaryWords.contains(trimmed) else {
            newWord = ""
            return
        }
        withAnimation(.snappy) {
            settings.dictionaryWords.append(trimmed)
        }
        newWord = ""
        wordFieldFocused = true
    }

    private func removeWord(_ word: String) {
        withAnimation(.snappy) {
            settings.dictionaryWords.removeAll { $0 == word }
        }
    }
}

/// One dictionary word as a removable capsule
private struct WordChip: View {
    let word: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.callout.weight(.medium))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.18), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.3)))
    }
}

#Preview {
    DictionaryView()
}
