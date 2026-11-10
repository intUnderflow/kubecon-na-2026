import SwiftUI

/// How a ``FlowRow`` aligns items of different heights within a line (Kotlin
/// `itemVerticalAlignment`).
enum FlowRowAlignment: Sendable, Equatable {
    case top
    case center
    case bottom
}

/// Compose `FlowRow(horizontalArrangement = spacedBy(h), verticalArrangement = spacedBy(v),
/// itemVerticalAlignment = ...)`: items left to right, wrapping to a new line when the next one
/// does not fit. Each item is measured with the full row width (a long text wraps inside it);
/// the row is as wide as its longest line. Used by the card meta rows, the details' meta, pills
/// and link rows. SwiftUI 17 has no flow layout, so this is a `Layout`.
struct FlowRow: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat
    var itemAlignment: FlowRowAlignment

    init(horizontalSpacing: CGFloat = 0, verticalSpacing: CGFloat = 0, itemAlignment: FlowRowAlignment = .top) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.itemAlignment = itemAlignment
    }

    /// One line of items: their indices and sizes, the line's width and height.
    private struct Line {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let lines = makeLines(maxWidth: proposal.width, subviews: subviews)
        var width: CGFloat = 0
        var height: CGFloat = 0
        for (i, line) in lines.enumerated() {
            width = max(width, line.width)
            height += line.height
            if i > 0 { height += verticalSpacing }
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let limit: CGFloat? = proposal.width ?? bounds.width
        let lines = makeLines(maxWidth: limit, subviews: subviews)
        var y: CGFloat = bounds.minY
        for line in lines {
            var x: CGFloat = bounds.minX
            for item in line.items {
                let dy: CGFloat
                switch itemAlignment {
                case .top: dy = 0
                case .center: dy = (line.height - item.size.height) / 2
                case .bottom: dy = line.height - item.size.height
                }
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + dy),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + horizontalSpacing
            }
            y += line.height + verticalSpacing
        }
    }

    /// Greedy line breaking: an item goes on the current line if it fits, else starts a new one.
    private func makeLines(maxWidth: CGFloat?, subviews: Subviews) -> [Line] {
        let limit: CGFloat = (maxWidth ?? .infinity).isFinite ? (maxWidth ?? .infinity) : .infinity
        let itemProposal = ProposedViewSize(width: limit.isFinite ? limit : nil, height: nil)
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let size: CGSize = subviews[index].sizeThatFits(itemProposal)
            let needed: CGFloat = current.items.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            // 0.5 pt of slack: text widths are fractional and must not wrap on rounding alone.
            if !current.items.isEmpty && needed > limit + 0.5 {
                lines.append(current)
                current = Line()
                current.width = size.width
            } else {
                current.width = needed
            }
            current.items.append((index: index, size: size))
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty {
            lines.append(current)
        }
        return lines
    }
}

#Preview("FlowRow") {
    ThemePreview {
        FlowRowSpecimen()
    }
}

private struct FlowRowSpecimen: View {
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        FlowRow(horizontalSpacing: 10, verticalSpacing: 4, itemAlignment: .center) {
            CapsText("Maintainer track", style: type.meta.bold, color: colors.category("mnt"), lineLimit: 2)
            CapsText("10:15–10:45 AM", style: type.meta, color: colors.muted, lineLimit: 1)
            CapsText("30 min", style: type.meta, color: colors.muted, lineLimit: 1)
            Pill("Anthropic", tone: .anthropic)
            Pill("Live · 12 min left", tone: .you)
        }
        .frame(width: 260, alignment: .leading)
        .background(colors.surface)
    }
}
