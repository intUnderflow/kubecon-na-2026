import Foundation

/// Carries the details scroll position across a layout swap (Kotlin ui/session/DetailsScrollCarry.kt,
/// the pure ViewModel part; the file is not called DetailsScrollCarry.swift because the app's
/// port of `rememberDetailsScrollState` may use that name, and file names must be unique in the
/// one module).
///
/// Android: folding swaps the wide pane for the compact sheet (and back), so the details sit at
/// a different place after the activity is recreated and start from the top; this
/// activity-scoped holder survives the recreation and hands the position to the new instance
/// once. iOS: the same happens when the window's width class changes (rotation, Split View /
/// Stage Manager resize) and the details move between the sheet and the list–detail pane. Own
/// one per scene (e.g. `@State` at the root); `put` when the details view goes away because of
/// that swap (not when the user closes it), `take` when the new one appears. Closing the sheet
/// or pane carries nothing, so a fresh open starts at the top like the web's `panel.scrollTop=0`.
@MainActor
final class DetailsScrollCarry {
    private var sessionId: String?
    private var position: Double = 0

    init() {}

    /// Remembers `position` (Kotlin: `ScrollState.value` in px; iOS: the scroll offset in points) for `sessionId`.
    func put(_ sessionId: String, _ position: Double) {
        self.sessionId = sessionId
        self.position = position
    }

    /// The carried position for `sessionId` (once), else 0.
    func take(_ sessionId: String) -> Double {
        let p = self.sessionId.map { kotlinEquals($0, sessionId) } == true ? position : 0
        self.sessionId = nil
        position = 0
        return p
    }
}
