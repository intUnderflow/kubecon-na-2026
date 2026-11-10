import SwiftUI

/// The root of every window (Kotlin MainActivity's `Root`): ``AppGraph/rootState`` decides.
///
/// - `.loading`: nothing on the page background (the launch screen's `LaunchBackground` is the
///   same colour, so the hand-over is invisible; Kotlin keeps the splash until the data is
///   parsed).
/// - `.ready`: the navigation shell (``AppNav``) with this window's ``NavModel`` and, on a fresh
///   install, the first-run speaker sheet over it (``FirstRunSpeakerSheet``).
/// - `.failed(text)`: the Core error text ("Couldn’t load the schedule data: …"), 24 points in
///   from the safe area.
///
/// Install it with `.environment(graph)`, `.kcnaTheme()` and `.readsWindowWidth()` (``KCNA26App``).
struct RootView: View {
    @Environment(AppGraph.self) private var graph
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init() {}

    var body: some View {
        switch graph.rootState {
        case .loading:
            colors.bg
                .ignoresSafeArea()
                .accessibilityHidden(true)
        case .ready:
            SceneRoot()
        case .failed(let text):
            // Kotlin: Text(...) in the Material default style (bodyLarge), ink, padding 24 inside safeDrawing.
            Text(verbatim: text)
                .appTextStyle(type.material.bodyLarge)
                .foregroundStyle(colors.ink)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The ready window: its ``NavModel`` (restored from and mirrored into `@SceneStorage`, so a
/// window comes back where it was, Kotlin's SavedStateHandle) and ``DetailsScrollCarry``.
private struct SceneRoot: View {
    @SceneStorage(NavModel.KEY_STACK) private var savedStack: String?
    @SceneStorage(NavModel.KEY_SESSION) private var savedSession: String?
    @State private var nav: NavModel?
    @State private var scrollCarry = DetailsScrollCarry()

    var body: some View {
        if let nav {
            SceneContent(nav: nav, savedStack: $savedStack, savedSession: $savedSession)
                .environment(nav)
                .environment(\.detailsScrollCarry, scrollCarry)
        } else {
            // One pass: @SceneStorage is only readable from here on.
            Color.clear
                .accessibilityHidden(true)
                .onAppear {
                    if nav == nil {
                        nav = NavModel(restoring: NavModel.Saved(stack: savedStack, session: savedSession))
                    }
                }
        }
    }
}

private struct SceneContent: View {
    @Environment(AppGraph.self) private var graph
    let nav: NavModel
    @Binding var savedStack: String?
    @Binding var savedSession: String?

    var body: some View {
        // Read here, in body, so Observation tracks them; the bindings below only hand them on.
        let showsFirstRun: Bool = graph.showsFirstRunSheet
        let settings: SettingsStore = graph.settings
        let firstRun = Binding<Bool>(
            get: { showsFirstRun },
            set: { shown in
                // Swiped away (Kotlin onDismissRequest): only until the next cold start. Picking a
                // name or Skip calls settings.finishFirstRun, which closes the sheet by itself.
                // SwiftUI calls a binding's setter on the main thread; `assumeIsolated` keeps this
                // compiling whether or not the SDK declares Binding's closures `@Sendable`.
                MainActor.assumeIsolated {
                    if !shown && settings.firstRunPending { settings.dismissFirstRunForNow() }
                }
            }
        )
        AppNav(nav: nav)
            .sheet(isPresented: firstRun) {
                // Kotlin: skipPartiallyExpanded, 90 % of the height.
                FirstRunSpeakerSheet()
                    .presentationDetents([.large])
            }
            .onAppear {
                _ = graph.routePendingDirections(to: nav)
            }
            .onChange(of: graph.pendingDirectionsSessionId) { _, _ in
                _ = graph.routePendingDirections(to: nav)
            }
            .onChange(of: nav.saved, initial: true) { _, saved in
                savedStack = saved.stack
                savedSession = saved.session
            }
    }
}
