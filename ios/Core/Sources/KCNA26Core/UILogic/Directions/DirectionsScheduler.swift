import Foundation

/// A one-shot delayed action of ``DirectionsViewModel`` (Kotlin: the `Job` of a
/// `viewModelScope.launch { delay(ms); … }`). Active until it has run or was cancelled.
@MainActor
final class DirectionsJob {
    /// Kotlin `Job.isActive`.
    private(set) var isActive = true
    private var onCancel: (() -> Void)?

    init() {}

    /// Cancels the action if it has not run yet. Idempotent.
    func cancel() {
        guard isActive else { return }
        isActive = false
        let c = onCancel
        onCancel = nil
        c?()
    }

    /// For schedulers: what ``cancel()`` must also stop (e.g. the sleeping `Task`).
    func setOnCancel(_ action: @escaping () -> Void) {
        if isActive { onCancel = action } else { action() }
    }

    /// For schedulers: the action is about to run (the job is no longer active).
    func markCompleted() {
        isActive = false
        onCancel = nil
    }
}

/// Runs delayed actions on the main actor for ``DirectionsViewModel`` (Kotlin: coroutines in
/// `viewModelScope` with `delay`). The app uses ``TaskDirectionsScheduler``; tests use a
/// virtual-time scheduler (kotlinx-coroutines-test's `advanceTimeBy`).
@MainActor
protocol DirectionsScheduler: AnyObject {
    /// Runs `action` after `delayMs` milliseconds unless the returned job is cancelled first.
    func launch(after delayMs: Int64, _ action: @escaping @MainActor @Sendable () -> Void) -> DirectionsJob
}

/// ``DirectionsScheduler`` on Swift concurrency: a main-actor `Task` that sleeps, then runs the
/// action (cancelling the job cancels the task).
@MainActor
final class TaskDirectionsScheduler: DirectionsScheduler {
    init() {}

    func launch(after delayMs: Int64, _ action: @escaping @MainActor @Sendable () -> Void) -> DirectionsJob {
        let job = DirectionsJob()
        let nanos = UInt64(max(0, delayMs)) &* 1_000_000
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, job.isActive else { return }
            job.markCompleted()
            action()
        }
        job.setOnCancel { task.cancel() }
        return job
    }
}
