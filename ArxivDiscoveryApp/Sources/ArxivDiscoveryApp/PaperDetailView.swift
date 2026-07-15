import ArxivDiscoveryCore
import SwiftUI

struct PaperDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppViewModel
    let paper: Paper

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                actions
                Divider()
                abstractSection
                if let translation = paper.abstractKO, !translation.isEmpty {
                    Divider()
                    translationSection(translation)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
        }
        .background(AppTheme.canvas(for: colorScheme))
        .navigationTitle(paper.shortID)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(paper.title)
                        .font(.title2.weight(.bold))
                        .textSelection(.enabled)
                    Text(paper.authors.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Button {
                    model.toggleFavorite(paper)
                } label: {
                    Image(systemName: model.favorites.contains(paper.shortID) ? "bookmark.fill" : "bookmark")
                        .font(.title3)
                }
                .buttonStyle(.plain)
        .foregroundStyle(model.favorites.contains(paper.shortID) ? (colorScheme == .light ? AppTheme.skyInk : AppTheme.sky) : .secondary)
                .accessibilityLabel(model.favorites.contains(paper.shortID) ? "Remove from Saved" : "Save Paper")
            }

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
                        .overlay { Rectangle().stroke(AppTheme.sky.opacity(0.45), lineWidth: 1) }
                }
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                actionButtons
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 8) {
                actionButtons
            }
        }
        .controlSize(.regular)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            model.openPaper(paper)
        } label: {
            Label("Open on arXiv", systemImage: "arrow.up.right.square")
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.sky)
        .foregroundStyle(Color.black.opacity(0.82))

        Button {
            model.translate(paper)
        } label: {
            if model.translatingPaperID == paper.shortID {
                Label("Translating…", systemImage: "character.book.closed")
            } else {
                Label(paper.abstractKO == nil ? "Translate to Korean" : "Translate again", systemImage: "character.book.closed")
            }
        }
        .disabled(model.translatingPaperID != nil || ShowcaseMode.isEnabled)
        .tint(colorScheme == .light ? AppTheme.skyInk : AppTheme.sky)

        Button {
            model.openPDF(paper)
        } label: {
            if model.downloadingPaperID == paper.shortID {
                Label("Downloading…", systemImage: "arrow.down.circle")
            } else {
                Label(model.hasLocalPDF(paper) ? "Open PDF" : "Download PDF", systemImage: model.hasLocalPDF(paper) ? "doc.richtext" : "arrow.down.circle")
            }
        }
        .disabled(model.downloadingPaperID != nil || ShowcaseMode.isEnabled)
        .tint(colorScheme == .light ? AppTheme.skyInk : AppTheme.sky)
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
            HStack {
                Text("Korean translation").font(.headline)
                Text(model.settings.geminiModel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(translation)
                .font(.body)
                .lineSpacing(6)
                .textSelection(.enabled)
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
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
