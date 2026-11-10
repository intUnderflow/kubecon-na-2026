import SwiftUI

/// The navigation shell (Kotlin nav/AppNav.kt): a `NavigationStack` over ``NavModel/path``,
/// rooted at the Schedule. Settings and Directions are pushed full screen (Kotlin shows the top
/// of the stack, cross-fading; iOS pushes, and the system back button / edge swipe pops,
/// which writes the shorter path back to the model). Session details are not a screen: the
/// Schedule layer shows ``NavModel/openSessionId`` in a sheet (compact) or in a pane next to the
/// list (wide); see ``AppNavLogic``.
///
/// The Schedule screen sits at the same place in the compact and the wide layout, so its view
/// state survives a width-class change (rotation, Split View) like Kotlin's.
struct AppNav: View {
    @Bindable var nav: NavModel

    init(nav: NavModel) {
        self.nav = nav
    }

    var body: some View {
        NavigationStack(path: $nav.path) {
            ScheduleLayer(nav: nav)
                .navigationDestination(for: Screen.self) { screen in
                    AppNavDestination(screen: screen, nav: nav)
                }
        }
    }
}

/// A pushed screen (Kotlin AppNav's `when (screen)`).
private struct AppNavDestination: View {
    let screen: Screen
    let nav: NavModel

    var body: some View {
        switch screen {
        case .schedule:
            // Never pushed: the path holds only the screens above the Schedule.
            EmptyView()
        case .settings:
            SettingsScreen(onBack: { _ = nav.pop() })
        case .directions(let sessionId):
            DirectionsScreen(sessionId: sessionId, onBack: { _ = nav.pop() })
        }
    }
}

/// The session a compact sheet shows (`.sheet(item:)` needs an `Identifiable`).
private struct SessionSheetItem: Identifiable, Hashable {
    let id: String
}

/// Kotlin `ScheduleLayer`: the Schedule screen, plus the session details as a sheet (compact)
/// or as a pane on the right (wide: list at ``AppNavLogic/listPaneWidth(_:)``, a hairline, the
/// details or the "Pick a session" hint on `surface`).
private struct ScheduleLayer: View {
    @Environment(AppGraph.self) private var graph
    @Environment(\.widthClass) private var widthClass
    @Environment(\.windowWidth) private var windowWidth
    @Environment(\.appColors) private var colors
    let nav: NavModel

    var body: some View {
        let repo: Repository = graph.repository
        let wide: Bool = widthClass.isWide
        let openId: String? = nav.openSessionId
        let session: String? = AppNavLogic.shownSession(openId, repo)
        let stale: Bool = AppNavLogic.dropsStaleSession(openId, repo)
        let placement: AppNavLogic.DetailsPlacement = AppNavLogic.detailsPlacement(wide: wide, shownSession: session)
        let onTop: Bool = nav.current == .schedule
        let back: AppNavLogic.BackAction = AppNavLogic.backAction(
            stackCount: nav.stack.count, top: nav.current, wide: wide, shownSession: session
        )
        let listWidth: CGFloat? = wide ? CGFloat(AppNavLogic.listPaneWidth(Double(windowWidth))) : nil
        let listMaxWidth: CGFloat? = wide ? nil : CGFloat.infinity

        HStack(spacing: 0) {
            ScheduleScreen(
                selectedSessionId: session,
                onOpenSession: { nav.openSession($0) },
                onOpenDirections: { nav.openDirections($0) },
                onOpenSettings: { nav.openSettings() },
                twoPane: wide
            )
            .frame(width: listWidth)
            .frame(maxWidth: listMaxWidth, maxHeight: .infinity)

            if wide {
                HairlineDivider(.vertical)
                    .ignoresSafeArea(.container, edges: .vertical)
                DetailsPane(placement: placement, nav: nav)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(colors.surface, ignoresSafeAreaEdges: .vertical)
            }
        }
        // The Schedule draws its own header (Kotlin has no app bar); pushed screens show the bar.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: sheetItem(placement: placement, onTop: onTop, wide: wide)) { item in
            SessionSheetHost(sessionId: item.id, nav: nav)
        }
        // Drop a stale id (e.g. restored from an older data set).
        .onChange(of: stale, initial: true) { _, isStale in
            if isStale { nav.closeSession() }
        }
        // Wide: Escape (hardware keyboard) clears the selected session, like Kotlin's back.
        // Compact: the sheet handles it; pushed screens: the system back.
        .background {
            if back == .closeSession {
                Button {
                    nav.closeSession()
                } label: {
                    Text(verbatim: "Close")
                }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    /// The compact sheet's item: the shown session while the Schedule is on top (a pushed
    /// Directions hides it; back brings it back, Kotlin keeps `openSessionId` for that) and the
    /// first-run sheet isn't up (one sheet at a time). Swiping it down closes the session.
    private func sheetItem(placement: AppNavLogic.DetailsPlacement, onTop: Bool, wide: Bool) -> Binding<SessionSheetItem?> {
        var item: SessionSheetItem? = nil
        if case .sheet(let id) = placement, onTop, !graph.showsFirstRunSheet {
            item = SessionSheetItem(id: id)
        }
        let shown: SessionSheetItem? = item
        let nav = nav
        return Binding<SessionSheetItem?>(
            get: { shown },
            set: { newValue in
                // Only a user dismissal (swipe down) reaches here; state-driven hiding (Directions
                // pushed, the window turning wide) doesn't call it, and must not close the session.
                if newValue == nil && !wide && nav.current == .schedule { nav.closeSession() }
            }
        )
    }
}

/// The compact sheet (Kotlin `SessionSheet`, a ModalBottomSheet that opens expanded): medium and
/// large detents, opening at large. A fresh host per presentation, so it opens large every time.
private struct SessionSheetHost: View {
    let sessionId: String
    let nav: NavModel
    @State private var detent: PresentationDetent = .large

    var body: some View {
        SessionSheet(
            sessionId: sessionId,
            onDismiss: { nav.closeSession() },
            onDirections: { nav.openDirections($0) }
        )
        .id(sessionId)
        .presentationDetents([.medium, .large], selection: $detent)
    }
}

/// The wide layout's right-hand pane: the details of the selected session (keyed by its id,
/// Kotlin `key(session)`, so a new selection starts fresh) or ``EmptyDetailsHint``.
private struct DetailsPane: View {
    let placement: AppNavLogic.DetailsPlacement
    let nav: NavModel

    var body: some View {
        switch placement {
        case .pane(let id):
            SessionDetails(
                sessionId: id,
                onDirections: { nav.openDirections($0) },
                onClose: { nav.closeSession() }
            )
            .id(id)
        case .emptyHint, .sheet, .nothing:
            EmptyDetailsHint()
        }
    }
}

/// Kotlin `EmptyDetailsHint`: "PICK A SESSION" and a line of text, centred in the pane.
private struct EmptyDetailsHint: View {
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        VStack(spacing: 0) {
            CapsText(AppNavLogic.EMPTY_DETAILS_TITLE, style: type.dayHeading, color: colors.ink)
            Text(verbatim: AppNavLogic.EMPTY_DETAILS_TEXT)
                .appTextStyle(type.body)
                .foregroundStyle(colors.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: CGFloat(AppNavLogic.EMPTY_DETAILS_TEXT_MAX_WIDTH))
                .padding(.top, CGFloat(AppNavLogic.EMPTY_DETAILS_TEXT_TOP))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CGFloat(AppNavLogic.EMPTY_DETAILS_PADDING))
    }
}

#Preview("Empty details") {
    ThemePreview {
        EmptyDetailsHint()
            .frame(height: 320)
    }
}
