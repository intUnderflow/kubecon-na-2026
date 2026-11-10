import SwiftUI

// The card Modifier helpers of Kotlin ui/schedule/ScheduleParts.kt (`cardSurface`,
// `dashedOutline`), plus ColocatedCards.kt's `cardSegment` (a card cut in two across list rows,
// here the `edges` option of cardSurface) and the pink "mine" shadow.

/// Which edges of a card are closed (bordered, rounded). A co-located card with its agenda
/// open is drawn as two segments: the card (`.top`) and the agenda (`.bottom`).
struct CardEdges: OptionSet, Sendable {
    let rawValue: Int
    static let top = CardEdges(rawValue: 1)
    static let bottom = CardEdges(rawValue: 2)
    static let all: CardEdges = [.top, .bottom]
}

/// The card surface of the web's `.card` (Kotlin `Modifier.cardSurface`): `fill`, a 1 pt
/// `border`, a `stripe` down the left edge (`border-left: 4px`, `Dimens.categoryStripe`), an
/// optional live progress bar along the bottom (`.bar`, 3 pt; `progress` is Core's
/// `CardStatus.progress`, 0...1), and a 2 pt `ring` over the content when the card is selected
/// in the list–detail layout. Unlike Kotlin (where the caller clips), this also clips the
/// content to the card shape and makes the whole shape tappable.
/// Pad the content yourself (Kotlin: `start = Dimens.categoryStripe + 12, end = 12, top = 9,
/// bottom = 10`).
struct CardSurfaceModifier: ViewModifier {
    let fill: Color
    let border: Color
    let stripe: Color
    var progress: Float?
    var progressColor: Color
    var ring: Color?
    var radius: CGFloat
    var edges: CardEdges

    func body(content: Content) -> some View {
        let r = radius
        let outline = RoundedRectangle(cornerRadius: r, style: .circular)
        // Compose's RoundedCornerShape is circular (UnevenRoundedRectangle defaults to continuous).
        // An open edge: the rounded rect runs past it (the clip cuts it off), so that edge has no
        // line and square corners (Kotlin cardSegment: r + 2 x border width).
        let over: CGFloat = r + 2
        let topOver: CGFloat = edges.contains(.top) ? 0 : -over
        let bottomOver: CGFloat = edges.contains(.bottom) ? 0 : -over
        let clip = UnevenRoundedRectangle(
            topLeadingRadius: edges.contains(.top) ? r : 0,
            bottomLeadingRadius: edges.contains(.bottom) ? r : 0,
            bottomTrailingRadius: edges.contains(.bottom) ? r : 0,
            topTrailingRadius: edges.contains(.top) ? r : 0,
            style: .circular
        )
        let shownProgress: Float? = progress.flatMap { $0 > 0 ? min($0, 1) : nil }
        content
            .background {
                ZStack(alignment: .bottomLeading) {
                    ZStack {
                        outline.fill(fill)
                        outline.strokeBorder(border, lineWidth: 1)
                    }
                    .padding(.top, topOver)
                    .padding(.bottom, bottomOver)
                    Rectangle()
                        .fill(stripe)
                        .frame(width: CGFloat(Dimens.categoryStripe))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    if let shownProgress {
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(progressColor)
                                .frame(width: proxy.size.width * CGFloat(shownProgress), height: 3)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        }
                    }
                }
            }
            .overlay {
                if let ring {
                    outline
                        .strokeBorder(ring, lineWidth: 2)
                        .padding(.top, topOver)
                        .padding(.bottom, bottomOver)
                }
            }
            .clipShape(clip)
            .contentShape(clip)
    }
}

/// Web `.lrow` / `.empty`: a 1 pt dashed outline (dash 4, gap 3) behind the content.
struct DashedOutlineModifier: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .circular)
                .strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

extension View {
    /// Kotlin `Modifier.cardSurface(fill, border, stripe, progress, progressColor, ring, radius)`;
    /// `edges` is Kotlin `cardSegment(top =, bottom =)` (default: a whole card).
    func cardSurface(
        fill: Color,
        border: Color,
        stripe: Color,
        progress: Float? = nil,
        progressColor: Color = Color.clear,
        ring: Color? = nil,
        radius: CGFloat = CGFloat(Dimens.cardRadius),
        edges: CardEdges = .all
    ) -> some View {
        modifier(CardSurfaceModifier(
            fill: fill, border: border, stripe: stripe, progress: progress, progressColor: progressColor,
            ring: ring, radius: radius, edges: edges
        ))
    }

    /// Kotlin `Modifier.dashedOutline(color, radius)`.
    func dashedOutline(_ color: Color, radius: CGFloat) -> some View {
        modifier(DashedOutlineModifier(color: color, radius: radius))
    }

    /// The pink glow under my own cards and the "You’re speaking" banner (Kotlin
    /// `Modifier.shadow(10.dp, shape, ambientColor = you, spotColor = you)`). Apply after
    /// `cardSurface` (outside the clip). Composited first, so the card casts one shadow (without
    /// it SwiftUI shadows every text and chip inside the card separately).
    func mineShadow(_ color: Color) -> some View {
        compositingGroup()
            .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 4)
    }

    /// The selectable tile look the Kotlin screens share: ink fill and border when `selected`,
    /// else `surface` with a `line` border (the day tabs, the Going chip, the reminder options).
    /// Content colour is the caller's (Kotlin: `bg` on, `ink` off). Clips to the shape.
    func tileSurface(selected: Bool, radius: CGFloat = CGFloat(Dimens.cardRadius)) -> some View {
        modifier(TileSurfaceModifier(selected: selected, radius: radius))
    }
}

/// See `View.tileSurface(selected:radius:)`.
struct TileSurfaceModifier: ViewModifier {
    let selected: Bool
    let radius: CGFloat
    @Environment(\.appColors) private var colors

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        content
            .background { shape.fill(selected ? colors.ink : colors.surface) }
            .overlay { shape.strokeBorder(selected ? colors.ink : colors.line, lineWidth: 1) }
            .clipShape(shape)
            .contentShape(shape)
    }
}

#Preview("Card surface") {
    ThemePreview {
        CardSurfaceSpecimen()
    }
}

private struct CardSurfaceSpecimen: View {
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        card("Plain", fill: colors.surface, border: colors.line, stripe: colors.category("talk"))
        card("Live, 40% through", fill: colors.surface, border: colors.liveBorder, stripe: colors.category("mnt"),
             progress: 0.4, progressColor: colors.you)
        card("Anthropic", fill: colors.anthropicCardBg, border: colors.anthropicCardBorder, stripe: colors.anthropic)
        card("Going, selected", fill: colors.goingCardBg, border: colors.goingCardBorder,
             stripe: colors.category("hands"), ring: colors.ink)
        card("Mine", fill: colors.you, border: colors.you, stripe: colors.you, text: colors.onYou)
            .mineShadow(colors.you)
        VStack(spacing: 0) {
            card("Co-located card (top segment)", fill: colors.surface, border: colors.line,
                 stripe: colors.category("colo"), edges: .top)
            card("Its agenda (bottom segment)", fill: colors.surface, border: colors.line,
                 stripe: colors.category("colo"), edges: .bottom)
        }
        HStack(spacing: 6) {
            ForEach(["Off", "5 min", "10 min"], id: \.self) { label in
                let on = label == "10 min"
                CapsText(label, style: type.button, color: on ? colors.bg : colors.ink, lineLimit: 1)
                    .frame(maxWidth: .infinity, minHeight: CGFloat(Dimens.touchTarget))
                    .tileSurface(selected: on)
            }
        }
        Text(verbatim: "Coffee Break · Hall B")
            .appTextStyle(type.small)
            .foregroundStyle(colors.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashedOutline(colors.line, radius: CGFloat(Dimens.cardRadius))
    }

    private func card(
        _ title: String,
        fill: Color,
        border: Color,
        stripe: Color,
        progress: Float? = nil,
        progressColor: Color = Color.clear,
        ring: Color? = nil,
        edges: CardEdges = .all,
        text: Color? = nil
    ) -> some View {
        Text(verbatim: title)
            .appTextStyle(type.cardTitle)
            .foregroundStyle(text ?? colors.ink)
            .padding(.leading, CGFloat(Dimens.categoryStripe) + 12)
            .padding(.trailing, 12)
            .padding(.top, 9)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(fill: fill, border: border, stripe: stripe, progress: progress,
                         progressColor: progressColor, ring: ring, edges: edges)
    }
}
