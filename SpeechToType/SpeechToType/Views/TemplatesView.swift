//
//  TemplatesView.swift
//  SpeechToType
//
//  "Vorlagen": a simple list of text snippets (with an optional title) to write down and
//  copy out again.
//

import SwiftUI

struct TemplatesView: View {
    @ObservedObject private var store = TemplateStore.shared
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @FocusState private var focusedField: EditorField?

    private enum EditorField {
        case title
        case text
    }

    private var filteredTemplates: [TextTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.templates }
        return store.templates.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                HStack {
                    Text("templates")
                        .font(.title2.weight(.bold))
                    Spacer()
                    Button(action: addTemplate) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("templatesAdd")
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

                PanelSearchField(text: $searchText)
                    .padding(.horizontal, 12)
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
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(width: 260)
            .frame(maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))

            Group {
                if let selectedID, let template = store.template(with: selectedID) {
                    editor(for: template)
                        .id(template.id)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField(
                        "templatesTitlePlaceholder",
                        text: Binding(
                            get: { store.template(with: template.id)?.title ?? "" },
                            set: { store.update(template.id, title: $0) }
                        ),
                        prompt: Text("templatesTitlePlaceholder")
                    )
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.bold))
                    .focused($focusedField, equals: .title)
                    .onSubmit { focusedField = .text }
                    Text(template.updatedAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        CopyButton(text: template.text, title: "copy")
                            .buttonStyle(.glassProminent)
                            .disabled(template.text.isEmpty)
                        Button(role: .destructive) {
                            delete(template.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.glass)
                        .help("delete")
                    }
                }
            }
            .padding(.horizontal, 10)

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { store.template(with: template.id)?.text ?? "" },
                    set: { store.update(template.id, text: $0) }
                ))
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .text)

                if template.text.isEmpty {
                    Text("templatesPlaceholder")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
        .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            EmptyStateView(icon: "note.text", title: "templatesNoSelection", message: "templatesEmptyMessage")
                .fixedSize()
            Button(action: addTemplate) {
                Label("templatesAdd", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addTemplate() {
        searchText = ""
        selectedID = store.add().id
        DispatchQueue.main.async {
            focusedField = .title
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
        guard let id, let template = store.template(with: id), template.isBlank else { return }
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
        let title = template.displayTitle
        VStack(alignment: .leading, spacing: 2) {
            Text(title.isEmpty ? String(localized: "templatesUntitled") : title)
                .lineLimit(1)
                .foregroundStyle(title.isEmpty ? .secondary : .primary)
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
