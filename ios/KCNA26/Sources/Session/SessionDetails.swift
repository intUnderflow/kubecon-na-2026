import SwiftUI

// STUB (shell): replaced by the session agent. Keep this signature.

/// Kotlin ui/session/SessionSheet.kt `SessionDetails`: the session details content, the
/// right-hand pane on wide windows (the shell gives it the pane's size and its `surface`
/// background, keyed by `sessionId`). Scrolls on its own; the Directions button stays pinned at
/// the bottom.
///
/// - Parameters:
///   - sessionId: the session to show (the shell only passes ids the data has).
///   - onDirections: open Directions for this session.
///   - contentPadding: extra padding inside the scroll (Kotlin: the window insets; on iOS the
///     safe area already reaches the scroll view, so the shell passes none).
///   - onClose: non-nil (the pane): show a close button that clears the selection.
struct SessionDetails: View {
    let sessionId: String
    let onDirections: (String) -> Void
    let contentPadding: EdgeInsets
    let onClose: (() -> Void)?

    @Environment(AppGraph.self) private var graph

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
        let title: String = graph.repository.session(sessionId)?.title ?? sessionId
        VStack(spacing: 16) {
            Text(verbatim: title)
            Button {
                onDirections(sessionId)
            } label: {
                Text(verbatim: "Directions")
            }
            if let onClose {
                Button {
                    onClose()
                } label: {
                    Text(verbatim: "Close")
                }
            }
        }
        .padding()
        .padding(contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
