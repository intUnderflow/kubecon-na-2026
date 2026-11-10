import Foundation

/// The navigation rules of Kotlin nav/AppNav.kt (the shell's layout lives in the app's AppNav
/// view): which screen shows, how the Schedule hosts session details (sheet on compact, a
/// list–detail pane on wide windows), what back does, and the empty-pane hint's texts.
///
/// Every screen keeps its own view state under ``Screen/key`` (Kotlin: a SaveableStateProvider
/// per key), so going to another screen and back, or the window changing width class, keeps it.
/// The ScheduleScreen sits at the same place in the compact and wide layouts for the same reason.
enum AppNavLogic {
    /// The screen transition: fade in over 140 ms, fade out over 110 ms.
    static let FADE_IN_MS = 140
    static let FADE_OUT_MS = 110

    /// The details pane's hint while no session is picked (Kotlin `EmptyDetailsHint`; the title
    /// is drawn in caps, `CapsText`).
    static let EMPTY_DETAILS_TITLE = "Pick a session"
    static let EMPTY_DETAILS_TEXT = "Its details, speakers and directions show up here."
    /// Hint geometry (points): 32 padding, 8 between title and text, text at most 360 wide, centred.
    static let EMPTY_DETAILS_PADDING = 32.0
    static let EMPTY_DETAILS_TEXT_TOP = 8.0
    static let EMPTY_DETAILS_TEXT_MAX_WIDTH = 360.0

    /// Width of the schedule list pane in list–detail mode: 47% of the window, within 360…480
    /// points (Kotlin `listPaneWidth`, Dp × Float).
    static func listPaneWidth(_ windowWidth: Double) -> Double {
        let w = Float(windowWidth) * Float(0.47)
        return Double(min(max(w, 360), 480))
    }

    /// The session the Schedule shows details for: ``NavModel/openSessionId`` if the data still
    /// has it (Kotlin `openSession?.takeIf { repo.session(it) != null }`).
    static func shownSession(_ openSessionId: String?, _ repo: Repository) -> String? {
        guard let id = openSessionId, repo.session(id) != nil else { return nil }
        return id
    }

    /// True when ``NavModel/openSessionId`` is stale (e.g. restored from an older data set) and
    /// must be dropped with ``NavModel/closeSession()``.
    static func dropsStaleSession(_ openSessionId: String?, _ repo: Repository) -> Bool {
        openSessionId != nil && shownSession(openSessionId, repo) == nil
    }

    /// Where the Schedule screen puts the details of `shownSession`.
    enum DetailsPlacement: Sendable, Hashable {
        /// Compact: no session open.
        case nothing
        /// Compact: the details sheet over the schedule.
        case sheet(String)
        /// Wide: the details pane next to the list.
        case pane(String)
        /// Wide: the pane shows ``EMPTY_DETAILS_TITLE`` / ``EMPTY_DETAILS_TEXT``.
        case emptyHint
    }

    static func detailsPlacement(wide: Bool, shownSession: String?) -> DetailsPlacement {
        switch (wide, shownSession) {
        case (true, let id?): return .pane(id)
        case (true, nil): return .emptyHint
        case (false, let id?): return .sheet(id)
        case (false, nil): return .nothing
        }
    }

    /// What a back gesture / Escape does (Kotlin's two BackHandlers; the Schedule layer's one is
    /// composed innermost, so it wins while enabled).
    enum BackAction: Sendable, Hashable {
        /// ``NavModel/pop()``.
        case pop
        /// ``NavModel/closeSession()`` (wide only; compact: the sheet handles back itself).
        case closeSession
        /// Nothing to do here (the system handles it).
        case nothing
    }

    static func backAction(stackCount: Int, top: Screen, wide: Bool, shownSession: String?) -> BackAction {
        if top == .schedule && wide && shownSession != nil { return .closeSession }
        if stackCount > 1 { return .pop }
        return .nothing
    }
}
