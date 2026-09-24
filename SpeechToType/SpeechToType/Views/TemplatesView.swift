//
//  TemplatesView.swift
//  SpeechToType
//
//  "Vorlagen": a simple list of text snippets to write down and copy out again.
//

import SwiftUI

struct TemplatesView: View {
    @ObservedObject private var store = TemplateStore.shared
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @FocusState private var editorFocused: Bool

    private var filteredTemplates: [TextTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.templates }
        return store.templates.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("templates")
                        .font(.headline)
                    Spacer()
                    Button(action: addTemplate) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("templatesAdd")
                }
                .padding(.horizontal, 14)
                .frame(height: 44)

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
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

                if filteredTemplates.isEmpty {
                    Text(searchText.isEmpty ? "templatesEmpty" : "noResults")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedID) {
                        ForEach(filteredTemplates) { template in
                            TemplateRow(template: template)
                                .tag(template.id)
                                .contextMenu {
                                    Button {
                                        copyToClipboard(template.text)
                                    } label: {
                                        Label("copy", systemImage: "doc.on.doc")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        delete(template.id)
                                    } label: {
                                        Label("delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(width: 240)

            Divider()

            if let selectedID, let template = store.template(with: selectedID) {
                editor(for: template)
                    .id(template.id)
            } else {
                emptyState
            }
        }
        .onAppear {
            if selectedID == nil {
                selectedID = store.templates.first?.id
            }
        }
        .onChange(of: selectedID) { oldValue, _ in
            removeIfBlank(oldValue)
        }
        .onDisappear {
            removeIfBlank(selectedID)
        }
    }

    private func editor(for template: TextTemplate) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(template.updatedAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                CopyButton(text: template.text, title: "copy")
                    .disabled(template.text.isEmpty)
                Button(role: .destructive) {
                    delete(template.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("delete")
            }
            .padding(.horizontal, 16)
            .frame(height: 44)

            Divider()

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { store.template(with: template.id)?.text ?? "" },
                    set: { store.update(template.id, text: $0) }
                ))
                .font(.body)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)

                if template.text.isEmpty {
                    Text("templatesPlaceholder")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("templatesNoSelection")
                .foregroundColor(.secondary)
            Button("templatesAdd", action: addTemplate)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addTemplate() {
        searchText = ""
        selectedID = store.add().id
        DispatchQueue.main.async {
            editorFocused = true
        }
    }

    private func delete(_ id: UUID) {
        if selectedID == id {
            selectedID = nil
        }
        store.delete(id)
    }

    /// Templates that were created but never written into don't stay around
    private func removeIfBlank(_ id: UUID?) {
        guard let id, let template = store.template(with: id),
              template.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.delete(id)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct TemplateRow: View {
    let template: TextTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(template.title.isEmpty ? String(localized: "templatesUntitled") : template.title)
                .lineLimit(1)
                .foregroundStyle(template.title.isEmpty ? .secondary : .primary)
            if !template.preview.isEmpty {
                Text(template.preview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
