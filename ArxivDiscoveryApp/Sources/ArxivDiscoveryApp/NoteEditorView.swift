import ArxivDiscoveryCore
import SwiftUI

@MainActor
final class NoteDraftStore: ObservableObject {
    @Published var values = NoteDrafts()
    @Published var errors: [String: String] = [:]
}

struct NoteEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var drafts: NoteDraftStore
    let paperID: String
    let saved: String
    let editable: Bool
    let canSave: Bool
    let onSave: (String) -> Void

    private var text: String { drafts.values.text(for: paperID, saved: saved) }
    private var changed: Bool { text != saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Note").font(.headline)
                Text(changed ? "Unsaved" : (saved.isEmpty ? "" : "Saved")).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if changed {
                    Button("Revert") { drafts.values.discard(paperID) }
                        .help("Discard this unsaved draft; keep the saved note")
                }
                Button("Save note") { onSave(text) }.disabled(!editable || !canSave || !changed)
            }
            TextEditor(text: Binding(
                get: { text },
                set: { drafts.values.update($0, for: paperID, saved: saved) }
            ))
            .disabled(!editable)
            .font(.body)
            .frame(minHeight: 120)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(AppTheme.panel(for: colorScheme))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border(for: colorScheme)) }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Paper note")
            if let error = drafts.errors[paperID] {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
