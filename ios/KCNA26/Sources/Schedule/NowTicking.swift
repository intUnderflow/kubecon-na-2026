import SwiftUI

// Kotlin time/Now.kt `rememberNowState(graph.clock)` for SwiftUI: Core's `NowTicker` (15 s,
// aligned to the clock, refreshed at once when the debug fake time changes), run while the view
// is on screen and its scene is in the foreground (Kotlin `repeatOnLifecycle(STARTED)`: visible,
// `.active` or `.inactive`), paused in the background and when the view goes away.

/// Drives a ``NowTicker`` held in the caller's `@State` (created on first appearance with
/// `clock`): resumes it (refreshing at once) when the view appears or its scene comes back from
/// the background, pauses it when the view disappears or the scene goes to the background.
///
///     @State private var ticker: NowTicker?
///     ...
///     content.ticksNow($ticker, clock: graph.clock)
///     let now: Date = NowTicking.now(ticker, clock: graph.clock)
struct NowTickingModifier: ViewModifier {
    @Binding var ticker: NowTicker?
    let clock: any AppClock

    @Environment(\.scenePhase) private var scenePhase
    /// Between onAppear and onDisappear. A view that stays alive off screen (the Schedule under
    /// a pushed Settings or Directions screen) must not start ticking again when the app comes
    /// back to the foreground (Kotlin: that back-stack entry is no longer STARTED).
    @State private var onScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                onScreen = true
                start(scenePhase)
            }
            .onDisappear {
                onScreen = false
                ticker?.pause()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    ticker?.pause()
                } else if onScreen {
                    start(phase)
                }
            }
    }

    private func start(_ phase: ScenePhase) {
        let t: NowTicker = ticker ?? NowTicker(clock: clock, running: false)
        if ticker == nil {
            ticker = t
        }
        if phase != .background && !t.isRunning {
            t.resume()
        }
    }
}

enum NowTicking {
    /// The ticker's "now" while it runs; else (not created yet, or paused) the clock read afresh,
    /// so a view never shows a stale minute.
    @MainActor
    static func now(_ ticker: NowTicker?, clock: any AppClock) -> Date {
        if let t = ticker, t.isRunning {
            return t.now
        }
        return clock.now()
    }
}

extension View {
    /// Runs `ticker` (created on first appearance) while this view is on screen in a foreground
    /// scene; see ``NowTickingModifier``.
    func ticksNow(_ ticker: Binding<NowTicker?>, clock: any AppClock) -> some View {
        modifier(NowTickingModifier(ticker: ticker, clock: clock))
    }
}

/// A view that re-renders `content` with "now" every 15 s (Kotlin `rememberNow()` read inside a
/// small composable), from the graph's clock. For small views (the details' clash note and
/// reminder hint); a screen that derives a lot from the time keeps its own ticker
/// (``View/ticksNow(_:clock:)``) and works per minute (`ScheduleLogic.minuteOf`).
///
///     NowReader { now in
///         if let kind = GoingUiLogic.reminderHint(s, me, ids, minutes, now) { ... }
///     }
///
/// The ticker runs while the content is on screen (an empty content never starts it; "now" is
/// then read from the clock at each render).
struct NowReader<Content: View>: View {
    @Environment(AppGraph.self) private var graph
    @State private var ticker: NowTicker?
    private let content: (Date) -> Content

    init(@ViewBuilder content: @escaping (Date) -> Content) {
        self.content = content
    }

    var body: some View {
        let clock: any AppClock = graph.clock
        let now: Date = NowTicking.now(ticker, clock: clock)
        content(now)
            .ticksNow($ticker, clock: clock)
    }
}
