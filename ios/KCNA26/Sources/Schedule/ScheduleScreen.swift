import SwiftUI

// STUB (shell): replaced by the schedule agent. Keep this signature.

/// Kotlin ui/schedule/ScheduleScreen.kt `ScheduleScreen`: the schedule list (the root of the
/// navigation stack; the shell hides the navigation bar, the screen draws its own header).
///
/// - Parameters:
///   - selectedSessionId: the session whose details are open (sheet or pane), highlighted in
///     the list; nil when none.
///   - onOpenSession: open a session's details (``NavModel/openSession(_:)``).
///   - onOpenDirections: open Directions for a session (``NavModel/openDirections(_:)``).
///   - onOpenSettings: open Settings (``NavModel/openSettings()``).
///   - twoPane: wide window, the list sits next to the details pane (Kotlin `twoPane`).
struct ScheduleScreen: View {
    let selectedSessionId: String?
    let onOpenSession: (String) -> Void
    let onOpenDirections: (String) -> Void
    let onOpenSettings: () -> Void
    let twoPane: Bool

    @Environment(AppGraph.self) private var graph

    init(
        selectedSessionId: String?,
        onOpenSession: @escaping (String) -> Void,
        onOpenDirections: @escaping (String) -> Void,
        onOpenSettings: @escaping () -> Void,
        twoPane: Bool
    ) {
        self.selectedSessionId = selectedSessionId
        self.onOpenSession = onOpenSession
        self.onOpenDirections = onOpenDirections
        self.onOpenSettings = onOpenSettings
        self.twoPane = twoPane
    }

    var body: some View {
        let first: Session? = graph.repository.sessions.first
        VStack(spacing: 16) {
            Text(verbatim: "Schedule")
            Button {
                onOpenSettings()
            } label: {
                Text(verbatim: "Settings")
            }
            if let first {
                Button {
                    onOpenSession(first.id)
                } label: {
                    Text(verbatim: first.title)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
