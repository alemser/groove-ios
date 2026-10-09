import SwiftUI
import Observation

/// The remote's arrangement (GET/PUT/DELETE /rig/remote/layout) — shared
/// with the web remote, so arranging it here rearranges it there too.
/// `layout` stays nil against an older groove-rig without the route; the
/// remote then falls back to its fixed cards.
@MainActor
@Observable
final class RemoteLayoutModel {
    var layout: RigRemoteLayout?
    var actionError: String?

    private var settings: AppSettings?

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
        }
    }

    func load() async {
        guard let settings else { return }
        // Supplementary to the remote itself — keep what we had on failure.
        layout = (try? await CatalogService(settings: settings).rigRemoteLayout()) ?? layout
    }

    /// Applies `change` locally right away, then saves; reverts on failure.
    func update(_ change: (inout RigRemoteLayout) -> Void) async {
        guard let settings, var next = layout else { return }
        let previous = layout
        change(&next)
        layout = next
        do {
            layout = try await CatalogService(settings: settings).rigSaveRemoteLayout(next)
            actionError = nil
        } catch {
            layout = previous
            actionError = error.localizedForDisplay
        }
    }

    func reset() async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).rigResetRemoteLayout()
            await load()
        } catch {
            actionError = error.localizedForDisplay
        }
    }
}

// MARK: - Span grid

private struct SpanKey: LayoutValueKey {
    static let defaultValue = 1
}

extension View {
    /// How many of the remote grid's columns this control spans.
    func gridSpan(_ span: Int) -> some View {
        layoutValue(key: SpanKey.self, value: span)
    }
}

/// Packs controls left to right into rows of `columns`, each spanning
/// `gridSpan` columns — the layout's 4-column grid, drawn natively.
struct SpanGrid: Layout {
    var columns = 4
    var spacing: CGFloat = 8

    private func rows(_ subviews: Subviews) -> [[(index: Int, span: Int)]] {
        var rows: [[(index: Int, span: Int)]] = [[]]
        var used = 0
        for (i, view) in subviews.enumerated() {
            let span = min(max(view[SpanKey.self], 1), columns)
            if used + span > columns {
                rows.append([])
                used = 0
            }
            rows[rows.count - 1].append((i, span))
            used += span
        }
        return rows.filter { !$0.isEmpty }
    }

    private func columnWidth(_ total: CGFloat) -> CGFloat {
        (total - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private func width(span: Int, total: CGFloat) -> CGFloat {
        columnWidth(total) * CGFloat(span) + spacing * CGFloat(span - 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 320
        var height: CGFloat = 0
        for (r, row) in rows(subviews).enumerated() {
            let h = row.map { subviews[$0.index].sizeThatFits(.init(width: width(span: $0.span, total: total), height: nil)).height }.max() ?? 0
            height += h + (r > 0 ? spacing : 0)
        }
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews) {
            let sizes = row.map { item -> CGFloat in
                let w = width(span: item.span, total: bounds.width)
                return subviews[item.index].sizeThatFits(.init(width: w, height: nil)).height
            }
            let rowHeight = sizes.max() ?? 0
            var x = bounds.minX
            for item in row {
                let w = width(span: item.span, total: bounds.width)
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: .init(width: w, height: rowHeight))
                x += w + spacing
            }
            y += rowHeight + spacing
        }
    }
}
