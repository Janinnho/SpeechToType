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
        VStack(alignment: .leading, spacing: 16) {
            // Words section
            VStack(alignment: .leading, spacing: 8) {
                Text("dictionaryWordsTitle")
                    .font(.headline)

                HStack {
                    TextField(String(localized: "dictionaryWordPlaceholder"), text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .focused($wordFieldFocused)
                        .onSubmit(addWord)

                    Button("dictionaryAdd", action: addWord)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if settings.dictionaryWords.isEmpty {
                    Text("dictionaryEmptyWords")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(settings.dictionaryWords, id: \.self) { word in
                            HStack {
                                Text(word)
                                Spacer()
                                Button(action: { removeWord(word) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            Divider()
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                }
            }

            // Instructions section
            VStack(alignment: .leading, spacing: 8) {
                Text("dictionaryInstructionsTitle")
                    .font(.headline)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $settings.dictionaryInstructions)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(minHeight: 120)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)

                    if settings.dictionaryInstructions.isEmpty {
                        Text("dictionaryInstructionsPlaceholder")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
            }

            Text("dictionaryDescription")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.dictionaryWords.contains(trimmed) else {
            newWord = ""
            return
        }
        settings.dictionaryWords.append(trimmed)
        newWord = ""
        wordFieldFocused = true
    }

    private func removeWord(_ word: String) {
        settings.dictionaryWords.removeAll { $0 == word }
    }
}

#Preview {
    DictionaryView()
}
