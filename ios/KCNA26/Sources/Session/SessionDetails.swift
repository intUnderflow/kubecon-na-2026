import SwiftUI

/// Kotlin ui/session/SessionSheet.kt `SessionDetails`: the session details content, the
/// right-hand pane on wide windows (the shell gives it the pane's size and its `surface`
/// background, keyed by `sessionId`). Scrolls on its own; the Directions button stays pinned at
/// the bottom, within thumb reach. The content is ``SessionDetailsContent`` (shared with the
/// compact ``SessionSheet``): 24 pt side padding on wide windows, 20 pt above.
///
/// - Parameters:
///   - sessionId: the session to show (the shell only passes ids the data has; one that a live
///     update removed shows "This session is no longer in the schedule.").
///   - onDirections: open Directions for this session.
///   - contentPadding: extra padding inside the scroll (Kotlin: the window insets; on iOS the
///     safe area already reaches the scroll view, so the shell passes none).
///   - onClose: non-nil (the pane): show a close button that clears the selection.
struct SessionDetails: View {
    let sessionId: String
    let onDirections: (String) -> Void
    let contentPadding: EdgeInsets
    let onClose: (() -> Void)?

    init(
        sessionId: String,
        onDirections: @escaping (String) -> Void,
        contentPadding: EdgeInsets = EdgeInsets(),
        onClose: (() -> Void)? = nil
    ) {
        self.sessionId = sessionId
        self.onDirections = onDirections
        self.contentPadding = contentPadding
        self.onClose = onClose
    }

    var body: some View {
        SessionDetailsContent(
            sessionId: sessionId,
            onDirections: onDirections,
            contentPadding: contentPadding,
            onClose: onClose,
            inSheet: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
