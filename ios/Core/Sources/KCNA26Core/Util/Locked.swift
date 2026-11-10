import Foundation

/// A value guarded by an `NSLock`: a thread-safe box for state shared across threads
/// (Kotlin `@Volatile` fields, `synchronized(lock) { ... }` blocks, `AtomicReference`).
///
/// ```swift
/// let opened = Locked<[String]>([])
/// opened.withLock { $0.append(name) }
/// opened.value            // a snapshot
/// ```
///
/// (`Synchronization.Mutex` needs iOS 18; the app targets iOS 17.)
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    /// Runs `body` with exclusive access to the value. Do not call back into this box from `body`.
    func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&_value)
    }

    /// The current value (read or replaced under the lock).
    var value: Value {
        get { withLock { $0 } }
        set { withLock { $0 = newValue } }
    }
}

/// Kotlin `by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { ... }`: the initializer runs at most
/// once, on first access, while other threads asking at the same time wait for it.
///
/// Like Kotlin, a THROWING initializer leaves the lazy uninitialized, so the next access tries
/// again (the error is not cached).
///
/// ``isInitialized`` never waits: like Kotlin's `Lazy.isInitialized()` (a volatile read) it
/// answers false at once while another thread is still running the initializer, so the main
/// thread can ask "is the repository / are the details ready?" without blocking on the parse.
///
/// ```swift
/// private let detailsLazy = SynchronizedLazy { try parseDetails() }     // Failure = any Error
/// var details: Details { get throws { try detailsLazy.get() } }
///
/// private let big = SynchronizedLazy { buildIndex() }                   // Failure = Never
/// big.value
/// ```
final class SynchronizedLazy<Value, Failure: Error>: @unchecked Sendable {
    /// Serializes initializer runs (held for the whole run). Guards `initializer`.
    private let initLock = NSLock()
    /// Guards `stored`; only ever held for a read or a write, never while initializing.
    private let stateLock = NSLock()
    private var stored: Value?
    private var initializer: (() throws(Failure) -> Value)?

    init(_ initializer: @escaping @Sendable () throws(Failure) -> Value) {
        self.initializer = initializer
    }

    private var storedValue: Value? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stored
    }

    /// The value, computing it on first call. Rethrows the initializer's error (and retries on
    /// the next call).
    func get() throws(Failure) -> Value {
        if let v = storedValue { return v }
        initLock.lock()
        defer { initLock.unlock() }
        if let v = storedValue { return v } // another thread finished while we waited
        let v = try initializer!()
        stateLock.lock()
        stored = v
        stateLock.unlock()
        initializer = nil // release whatever it captured
        return v
    }

    /// True once the value has been computed (Kotlin `Lazy.isInitialized()`). Never blocks:
    /// false while another thread is still inside the initializer.
    var isInitialized: Bool { storedValue != nil }
}

extension SynchronizedLazy where Failure == Never {
    /// The value, computing it on first access.
    var value: Value { self.get() }
}
