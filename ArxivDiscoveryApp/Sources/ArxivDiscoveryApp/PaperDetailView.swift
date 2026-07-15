import ArxivDiscoveryCore
import SwiftUI

struct PaperDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppViewModel
    let paper: Paper
    @State private var note = ""
    @State private var creatingCollection = false
    @State private var collectionName = ""

    private var progress: PaperProgress { model.progress(for: paper) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                primaryDecision
                actions
                Divider()
                abstractSection
                if let translation = paper.abstractKO, !translation.isEmpty {
                    Divider()
                    translationSection(translation)
                }
                Divider()
                noteSection
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
        }
        .background(AppTheme.canvas(for: colorScheme))
        .navigationTitle(paper.shortID)
        .onAppear { note = progress.note }
        .alert("New collection", isPresented: $creatingCollection) {
            TextField("Collection name", text: $collectionName)
            Button("Cancel", role: .cancel) { collectionName = "" }
            Button("Create") {
                if model.createCollection(named: collectionName, adding: paper) { collectionName = "" }
            }
        } message: {
            Text("This paper will be added to the new collection.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(paper.title)
                .font(.title2.weight(.bold))
                .textSelection(.enabled)
            Text(paper.authors.joined(separator: ", "))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Label(paper.publishedAt.formatted(date: .long, time: .omitted), systemImage: "calendar")
                Text(paper.shortID).textSelection(.enabled)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(paper.subjects, id: \.self) { subject in
                    Text(subject)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.sky.opacity(0.12))
                        .overlay { RoundedRectangle(cornerRadius: 4).stroke(AppTheme.sky.opacity(0.45), lineWidth: 1) }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    private var primaryDecision: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { decisionButtons }
            VStack(alignment: .leading, spacing: 8) { decisionButtons }
        }
    }

    @ViewBuilder
    private var decisionButtons: some View {
        Button {
            model.toggleSaved(paper)
        } label: {
            Label(progress.disposition == .saved ? "Saved" : "Save for later", systemImage: progress.disposition == .saved ? "bookmark.fill" : "bookmark")
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.sky)
        .foregroundStyle(Color.black.opacity(0.82))

        Button {
            if progress.disposition == .reviewed { model.moveToInbox(paper) }
            else { model.markReviewed(paper) }
        } label: {
            Label(progress.disposition == .reviewed ? "Reviewed" : "Not for me", systemImage: progress.disposition == .reviewed ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .tint(progress.disposition == .reviewed ? AppTheme.teal : .secondary)

        Menu {
            if model.library.collections.isEmpty {
                Text("No collections yet")
            } else {
                ForEach(model.library.collections) { collection in
                    Button {
                        model.setCollection(
                            collection.id,
                            contains: paper,
                            enabled: !progress.collectionIDs.contains(collection.id)
                        )
                    } label: {
                        Label(collection.name, systemImage: progress.collectionIDs.contains(collection.id) ? "checkmark" : "rectangle.stack")
                    }
                }
                Divider()
            }
            Button("New collection…") { creatingCollection = true }
        } label: {
            Label("Collections", systemImage: "rectangle.stack.badge.plus")
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { actionButtons }
            VStack(alignment: .leading, spacing: 8) { actionButtons }
        }
        .controlSize(.regular)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button { model.openPaper(paper) } label: {
            Label("Open on arXiv", systemImage: "arrow.up.right.square")
        }

        Button { model.translate(paper) } label: {
            if model.translatingPaperID == paper.shortID {
                Label("Translating…", systemImage: "character.book.closed")
            } else {
                Label(paper.abstractKO == nil ? "Translate to Korean" : "Translate again", systemImage: "character.book.closed")
            }
        }
        .disabled(model.translatingPaperID != nil || ShowcaseMode.isEnabled)

        Button { model.openPDF(paper) } label: {
            if model.downloadingPaperID == paper.shortID {
                Label("Downloading…", systemImage: "arrow.down.circle")
            } else {
                Label(model.hasLocalPDF(paper) ? "Open PDF" : "Download PDF", systemImage: model.hasLocalPDF(paper) ? "doc.richtext" : "arrow.down.circle")
            }
        }
        .disabled(model.downloadingPaperID != nil || ShowcaseMode.isEnabled)
    }

    private var abstractSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Abstract").font(.headline)
            Text(paper.abstract)
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)
        }
    }

    private func translationSection(_ translation: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Korean translation").font(.headline)
            Text(translation)
                .font(.body)
                .lineSpacing(6)
                .textSelection(.enabled)
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Note").font(.headline)
                Spacer()
                Button("Save note") { model.saveNote(note, for: paper) }
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines) == progress.note)
            }
            TextEditor(text: $note)
                .font(.body)
                .frame(minHeight: 110)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(AppTheme.panel(for: colorScheme))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border(for: colorScheme)) }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Paper note")
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, max(0, x - spacing))
        }
        return (CGSize(width: min(usedWidth, width), height: y + rowHeight), points)
    }
}
