import Foundation
import Observation

/// Default re-evaluation period for ``NowTicker``: every 15 s, aligned to :00/:15/:30/:45.
let NOW_PERIOD_MS: Int64 = 15_000

/// "Now" from the app clock, re-evaluated every ``periodMillis`` aligned to the wall clock (so
/// minute labels flip within a second of the minute), immediately on ``resume()`` (returning to
/// the foreground), and immediately when the debug fake time (``FakeableClock/offsetMillis``)
/// changes. The port of Kotlin's `rememberNow()` / `rememberNowState()` (Now.kt).
///
/// The app owns one (or one per screen) and drives it from `scenePhase`:
///
/// ```swift
/// @State private var ticker = NowTicker(clock: graph.clock)
/// ...
/// .onChange(of: scenePhase) { _, phase in phase == .active ? ticker.resume() : ticker.pause() }
/// Text(TimeFormat.clockLabel(ticker.now))     // re-renders each period
/// ```
///
/// Reading ``now`` re-renders the reader each period; read it as low in the view tree as
/// practical.
@MainActor
@Observable
final class NowTicker {
    /// The latest "now" (Kotlin's State<Instant>).
    private(set) var now: Date

    let clock: AppClock
    let periodMillis: Int64

    /// True while the periodic refresh runs (between ``resume()`` and ``pause()``).
    private(set) var isRunning = false

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// `running: true` starts ticking at once (the screen is visible).
    init(clock: AppClock, periodMillis: Int64 = NOW_PERIOD_MS, running: Bool = true) {
        precondition(periodMillis > 0, "periodMillis must be positive")
        self.clock = clock
        self.periodMillis = periodMillis
        now = clock.now()
        observeFakeOffset()
        if running { resume() }
    }

    /// Kotlin's loop delay: the time to the next period boundary of the clock's own timeline,
    /// plus 20 ms so the boundary has surely passed: `period - floorMod(now, period) + 20`.
    nonisolated static func nextDelayMillis(nowEpochMillis: Int64, periodMillis: Int64) -> Int64 {
        periodMillis - floorMod(nowEpochMillis, periodMillis) + 20
    }

    /// Re-reads the clock now.
    func refresh() {
        now = clock.now()
    }

    /// Starts (or restarts) the periodic refresh, refreshing at once (foreground / STARTED).
    func resume() {
        loop?.cancel()
        isRunning = true
        generation += 1
        let gen = generation
        refresh()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.tick(generation: gen) else { return }
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }
        }
    }

    /// Stops the periodic refresh (background). ``now`` keeps its last value.
    func pause() {
        loop?.cancel()
        loop = nil
        isRunning = false
        generation += 1
    }

    /// One loop step: refresh and return the delay to the next one; nil when this loop is stale.
    private func tick(generation gen: Int) -> Int64? {
        guard gen == generation, isRunning else { return nil }
        let t = clock.now()
        now = t
        return NowTicker.nextDelayMillis(nowEpochMillis: t.epochMillis, periodMillis: periodMillis)
    }

    /// Refreshes at once (and restarts the aligned loop) whenever a FakeableClock's offset changes.
    private func observeFakeOffset() {
        guard let fake = clock as? FakeableClock else { return }
        withObservationTracking {
            _ = fake.offsetMillis
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.fakeOffsetChanged() }
        }
    }

    private func fakeOffsetChanged() {
        observeFakeOffset() // tracking fires once per registration
        if isRunning { resume() } else { refresh() }
    }
}
