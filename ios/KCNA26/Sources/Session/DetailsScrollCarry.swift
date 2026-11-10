import SwiftUI

// Kotlin ui/session/DetailsScrollCarry.kt: `rememberDetailsScrollState(sessionId)`, the details'
// scroll state seeded from the window's carried position. The carrier itself (Kotlin's
// activity-scoped `DetailsScrollCarry` ViewModel) is Core's `DetailsScrollCarry`
// (UILogic/Session/DetailsScrollCarryLogic.swift); the shell provides one per window as
// `\.detailsScrollCarry`.

/// The details' vertical scroll view (Kotlin `Modifier.verticalScroll(rememberDetailsScrollState(id))`).
///
/// Its position follows the session across a re-creation of the details, the way Kotlin's
/// saveable scroll state plus the carry do:
/// - the window's width class changes (rotation, Split View or Stage Manager resizes) and the
///   details move between the compact sheet and the wide pane (Kotlin: fold / unfold);
/// - the compact sheet is taken down while Directions is pushed and comes back on Back (Kotlin's
///   `rememberSaveable` keeps the position there).
///
/// While the details are on screen their position is written to the carry (``DetailsScrollCarry/put(_:_:)``);
/// a new details view for the same session takes it once (``DetailsScrollCarry/take(_:)``) and
/// scrolls there. When the details go away because the session was closed (×, swipe down,
/// another session picked: `nav.openSessionId` is no longer this one), the carry is emptied, so a
/// fresh open starts at the top like the web's `panel.scrollTop=0`. Not kept across a relaunch
/// (Kotlin's saveable state also survives process death).
///
/// Also reports whether the content can scroll further (Kotlin `scroll.canScrollForward`, the
/// Directions bar's hairline).
struct DetailsScrollView<Content: View>: View {
    let sessionId: String
    @Binding var canScrollForward: Bool
    private let content: Content

    @Environment(\.detailsScrollCarry) private var carry
    @Environment(NavModel.self) private var nav: NavModel?
    @State private var tracker = DetailsScrollTracker()
    /// Where the restore marker sits (points from the content's top): the carried position.
    @State private var restoreY: CGFloat = 0

    init(sessionId: String, canScrollForward: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.sessionId = sessionId
        _canScrollForward = canScrollForward
        self.content = content()
    }

    /// The scroll view's coordinate space (the content's frame in it gives the offset).
    private static var space: NamedCoordinateSpace { NamedCoordinateSpace.named("kcna26.details.scroll") }

    /// The id of the restore marker.
    private static var markerId: String { "kcna26.details.restore" }

    var body: some View {
        GeometryReader { outer in
            let viewport: CGFloat = outer.size.height
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    content
                        .background {
                            GeometryReader { inner in
                                let frame: CGRect = inner.frame(in: DetailsScrollView.space)
                                let metrics = DetailsScrollMetrics(top: frame.minY, bottom: frame.maxY, viewport: viewport)
                                Color.clear
                                    .onChange(of: metrics, initial: true) { _, m in
                                        update(m, proxy)
                                    }
                            }
                            .accessibilityHidden(true)
                        }
                        .overlay(alignment: .topLeading) {
                            DetailsRestoreMarker(y: restoreY, id: DetailsScrollView.markerId)
                        }
                }
                .coordinateSpace(DetailsScrollView.space)
            }
        }
        .onDisappear {
            // Closed (or replaced by another session): carry nothing. Still open: hidden by
            // Directions or moved by a width-class change, so keep the position for the next one.
            if nav?.openSessionId != sessionId {
                _ = carry?.take(sessionId)
            }
        }
    }

    private func update(_ m: DetailsScrollMetrics, _ proxy: ScrollViewProxy) {
        let more: Bool = m.bottom > m.viewport + 0.5
        if more != canScrollForward {
            canScrollForward = more
        }
        if !tracker.started {
            // First layout, before any scrolling: the resting top, and the carried position.
            tracker.started = true
            tracker.restTop = m.top
            let carried: Double = carry?.take(sessionId) ?? 0
            if carried > 0 {
                restoreY = CGFloat(carried)
                let id: String = DetailsScrollView.markerId
                // After the marker has moved there.
                DispatchQueue.main.async {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
            return
        }
        let offset: CGFloat = max(0, tracker.restTop - m.top)
        carry?.put(sessionId, Double(offset))
    }
}

/// The content's top and bottom in the scroll view's space, and the viewport height.
private struct DetailsScrollMetrics: Equatable {
    let top: CGFloat
    let bottom: CGFloat
    let viewport: CGFloat
}

/// Per-view bookkeeping written on every scroll step: a plain class, so writing it doesn't
/// re-render anything.
@MainActor
private final class DetailsScrollTracker {
    var started = false
    var restTop: CGFloat = 0
}

/// An invisible 1 pt target `y` points below the content's top: scrolling it to the top
/// restores a carried position (iOS 17 has no offset-based scroll API). An overlay, so it never
/// makes the content taller.
private struct DetailsRestoreMarker: View {
    let y: CGFloat
    let id: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .id(id)
            .padding(.top, y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
