import SwiftUI

// Kotlin ui/session/SessionSheet.kt (OWNER: details; port of schedule_app.js sheetHTML): the
// compact sheet (`SessionSheet`) and the content it shares with the wide pane
// (`SessionDetailsContent`). The web's inline wayfinding is the Directions screen, opened with
// the pinned Directions button. `SessionDetails` (the pane's entry point) is in
// SessionDetails.swift.

/// Kotlin ui/session/SessionSheet.kt `SessionSheet`: the compact layout's details, as the
/// content of the shell's `.sheet` (the shell presents it while the session is open and the
/// Schedule is on top, with `.presentationDetents([.medium, .large])` opening at large, keyed by
/// `sessionId`). This view sets the rest of the presentation itself: Kotlin `containerColor =
/// surface` -> `.presentationBackground(colors.surface)`, the corner radius
/// (`.presentationCornerRadius(Dimens.sheetRadius)`), and the drag indicator: Kotlin draws its
/// own grab bar beside the ×; here the system indicator draws it (visible; VoiceOver can resize
/// the sheet with it) over the bar's room at the top of the content (``GrabBar``).
///
/// - Parameters:
///   - sessionId: the session to show.
///   - onDismiss: close the details (the × button; a swipe down is handled by the shell).
///   - onDirections: open Directions for this session (the shell hides the sheet while
///     Directions is on top and shows it again on back).
struct SessionSheet: View {
    let sessionId: String
    let onDismiss: () -> Void
    let onDirections: (String) -> Void

    @Environment(\.appColors) private var colors

    init(sessionId: String, onDismiss: @escaping () -> Void, onDirections: @escaping (String) -> Void) {
        self.sessionId = sessionId
        self.onDismiss = onDismiss
        self.onDirections = onDirections
    }

    var body: some View {
        SessionDetailsContent(
            sessionId: sessionId,
            onDirections: onDirections,
            contentPadding: EdgeInsets(),
            onClose: onDismiss,
            inSheet: true
        )
        .id(sessionId)
        .presentationBackground(colors.surface)
        .presentationCornerRadius(CGFloat(Dimens.sheetRadius))
        .presentationDragIndicator(.visible)
    }
}

/// Shared by the pane and the sheet (Kotlin `SessionDetailsContent`): the scrolling details
/// (``DetailsBody``, at most `Dimens.maxTextWidth` wide), the × button over their top-right
/// corner when `onClose` is given, and the pinned ``DirectionsBar`` under them.
///
/// Details come from `graph.details` (``DetailsRepository``): at once when already known
/// (bundled, summit, cached this process: `peekResult`), else loaded off the main thread
/// (disk cache, then a live Sessionize fetch), and again after `.unavailable` (the network may
/// be back). A new data set (live update) brings its own details. "Loading…" only appears if
/// that takes longer than ``SessionDetailsLogic/LOADING_DELAY_MS``.
struct SessionDetailsContent: View {
    let sessionId: String
    let onDirections: (String) -> Void
    let contentPadding: EdgeInsets
    let onClose: (() -> Void)?
    /// In the compact sheet (Kotlin `inSheet`): no wide padding, the grab bar's room on top.
    let inSheet: Bool

    @Environment(AppGraph.self) private var graph
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type
    @Environment(\.widthClass) private var widthClass

    /// The latest lookup, for the details set it came from (Kotlin `produceState`).
    @State private var loaded: LoadedDetails?
    @State private var showLoading = false
    @State private var canScrollForward = false

    init(
        sessionId: String,
        onDirections: @escaping (String) -> Void,
        contentPadding: EdgeInsets,
        onClose: (() -> Void)?,
        inSheet: Bool
    ) {
        self.sessionId = sessionId
        self.onDirections = onDirections
        self.contentPadding = contentPadding
        self.onClose = onClose
        self.inSheet = inSheet
    }

    var body: some View {
        let repo: Repository = graph.repository
        if let session = repo.session(sessionId) {
            details(session, repo)
        } else {
            Text(verbatim: SessionDetailsLogic.NOT_IN_SCHEDULE)
                .appTextStyle(type.body)
                .foregroundStyle(colors.muted)
                .padding(contentPadding)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func details(_ session: Session, _ repo: Repository) -> some View {
        let source: DetailsRepository = graph.details
        let key = LoadedDetails.Key(details: source, sessionId: sessionId)
        // Until the lookup below has run for this details set: what is known without I/O.
        let result: DetailsResult? = loaded?.key == key ? loaded?.result : source.peekResult(sessionId)
        let waiting: Bool = result == nil
        let me: String? = graph.settings.speakingAs
        let room: Room? = repo.roomOf(session)
        let wide: Bool = widthClass.isWide && !inSheet
        let hPad = CGFloat(SessionDetailsLogic.horizontalPadding(wide: wide))
        let top: CGFloat = contentPadding.top
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                DetailsScrollView(sessionId: sessionId, canScrollForward: $canScrollForward) {
                    VStack(alignment: .leading, spacing: 0) {
                        if inSheet {
                            GrabBar()
                        }
                        DetailsBody(
                            session: session,
                            repo: repo,
                            room: room,
                            result: result,
                            showLoading: showLoading,
                            me: me,
                            reserveCloseSpace: onClose != nil
                        )
                    }
                    .widthIn(max: CGFloat(Dimens.maxTextWidth))
                    .padding(.leading, hPad)
                    .padding(.trailing, hPad)
                    .padding(.top, top + (inSheet ? 0 : 20))
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let onClose {
                    CloseButton(onClick: onClose)
                        .padding(.top, top + (inSheet ? 8 : 4))
                        .padding(.trailing, hPad - 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            DirectionsBar(
                session: session,
                room: room,
                onDirections: onDirections,
                showDivider: canScrollForward,
                horizontalPadding: hPad,
                bottomPadding: contentPadding.bottom
            )
        }
        .task(id: key) {
            await load(source, key)
        }
        .task(id: waiting) {
            // Kotlin: LaunchedEffect while the result is null; showLoading stays set once set.
            guard waiting else { return }
            try? await Task.sleep(nanoseconds: UInt64(SessionDetailsLogic.LOADING_DELAY_MS) * 1_000_000)
            if !Task.isCancelled {
                showLoading = true
            }
        }
    }

    /// Kotlin `produceState(initial, details, sessionId)`: start from the peek, then load unless
    /// it is known (``SessionDetailsLogic/needsLoad(_:)``: unknown, or unavailable = retry).
    private func load(_ source: DetailsRepository, _ key: LoadedDetails.Key) async {
        let initial: DetailsResult? = source.peekResult(key.sessionId)
        loaded = LoadedDetails(key: key, result: initial)
        guard SessionDetailsLogic.needsLoad(initial) else { return }
        let result: DetailsResult = await source.load(key.sessionId)
        if Task.isCancelled { return }
        loaded = LoadedDetails(key: key, result: result)
    }
}

/// A details lookup and the details set (``DetailsRepository``, one per data set) it came from.
private struct LoadedDetails: Equatable {
    /// The details set (held, and compared by identity) and the session.
    struct Key: Equatable {
        let details: DetailsRepository
        let sessionId: String

        static func == (a: Key, b: Key) -> Bool {
            a.details === b.details && a.sessionId == b.sessionId
        }
    }

    let key: Key
    let result: DetailsResult?
}
