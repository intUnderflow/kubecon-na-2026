import SwiftUI

// STUB (shell): replaced by the settings agent. Keep this signature.

/// Kotlin ui/settings/FirstRunSheet.kt `FirstRunSpeakerSheet`: "Speaking at KubeCon? Pick your
/// name", the content of the shell's first-run `.sheet` (``RootView``). The shell presents it
/// while ``AppGraph/showsFirstRunSheet`` (data loaded, `settings.firstRunPending`) with
/// `.presentationDetents([.large])`, and turns a swipe-down into
/// `settings.dismissFirstRunForNow()` (Kotlin `onDismissRequest`). This view sets its own
/// background (`.presentationBackground(colors.bg)`), and finishes with
/// `graph.settings.finishFirstRun(name)` (a name, or nil for Skip): the sheet then closes by
/// itself. Don't call `dismiss()` for that: it counts as a swipe-down.
struct FirstRunSpeakerSheet: View {
    @Environment(AppGraph.self) private var graph

    init() {}

    var body: some View {
        VStack(spacing: 16) {
            Text(verbatim: FirstRunSheetLogic.TITLE)
            Button {
                graph.settings.finishFirstRun(nil)
            } label: {
                Text(verbatim: FirstRunSheetLogic.SKIP)
            }
        }
        .padding()
    }
}
