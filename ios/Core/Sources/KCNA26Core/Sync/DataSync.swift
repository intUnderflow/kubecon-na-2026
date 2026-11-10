import Foundation
import Observation

/// The data set the app is using: the bundled resources, or a set downloaded from GitHub.
/// (A class, like Kotlin's: compared by identity.)
final class ActiveData: Sendable {
    /// Kotlin `ActiveData.Source.BUNDLED` / `GITHUB` (raw values are the Kotlin names).
    enum Source: String, Sendable, Hashable {
        case bundled = "BUNDLED"
        case github = "GITHUB"
    }

    let repository: Repository
    let manifest: DataManifest
    let source: Source
    /// The downloaded set's folder; nil for the bundled resources.
    let dir: URL?

    init(repository: Repository, manifest: DataManifest, source: Source, dir: URL? = nil) {
        self.repository = repository
        self.manifest = manifest
        self.source = source
        self.dir = dir
    }

    var version: Int { manifest.version }
    var updatedAt: Date? { manifest.updatedInstant }
}

/// Result of one ``DataSync/check()``.
enum SyncOutcome: Sendable, Hashable, CustomStringConvertible {
    /// A newer set (this version) was verified and swapped in.
    case updated(Int)

    /// 304: the manifest hasn't changed since the last check.
    case notModified

    /// The published set (this remote version) is not newer than the one in use.
    case notNewer(Int)

    /// Offline, HTTP error, hash mismatch (CDN still serving an old file), partial download: retried next time.
    case failed(String)

    /// The published set is broken (bad JSON, missing room, …): skipped until the manifest changes.
    case rejected(String)

    /// The reason of a ``failed(_:)`` or ``rejected(_:)`` outcome.
    var reason: String? {
        switch self {
        case .failed(let r), .rejected(let r): return r
        case .updated, .notModified, .notNewer: return nil
        }
    }

    /// Kotlin's `toString()`: "Updated(version=2)", "NotModified", "Failed(reason=…)", …
    var description: String {
        switch self {
        case .updated(let v): return "Updated(version=\(v))"
        case .notModified: return "NotModified"
        case .notNewer(let v): return "NotNewer(remoteVersion=\(v))"
        case .failed(let r): return "Failed(reason=\(r))"
        case .rejected(let r): return "Rejected(reason=\(r))"
        }
    }
}

/// For the Settings row.
struct SyncStatus: Sendable, Hashable {
    let checking: Bool
    let last: SyncOutcome?
    /// Wall clock (not the app clock, which may be faked).
    let lastCheckedAt: Date?

    init(checking: Bool = false, last: SyncOutcome? = nil, lastCheckedAt: Date? = nil) {
        self.checking = checking
        self.last = last
        self.lastCheckedAt = lastCheckedAt
    }

    /// Kotlin `copy(checking = …)`.
    func copy(checking: Bool) -> SyncStatus {
        SyncStatus(checking: checking, last: last, lastCheckedAt: lastCheckedAt)
    }
}

/// Live schedule data. The app ships its data in the bundle (Resources/Data) and checks
/// `baseUrl` + `manifest.json` (raw.githubusercontent.com: the `KCNA26DataBaseURL` Info.plist
/// key, see ``baseUrl(from:)``) for a newer published set:
///
/// - When: on app start and when the app comes back to the foreground at least
///   ``FOREGROUND_INTERVAL_MS`` after the last check (the app calls ``onForeground()`` on
///   scenePhase `.active`, which is also its first foreground at launch), plus Settings →
///   "Check now" (``checkInBackground()``). No polling. The manifest request sends
///   If-None-Match, so an unchanged manifest is a 304.
/// - What: every file whose sha256 differs from the copy in use is downloaded and checked against
///   the manifest's sha256 and size. Unchanged files are copied from the current set. The whole
///   set is then parsed with the app's own DTOs (``Repository/load(open:)``) and checked by
///   ``DataValidator``.
/// - Only then is it committed: written to a staging folder, renamed to `root/v<version>`, and
///   made current by atomically replacing the `root/current` pointer (temp file + POSIX
///   rename). ``active`` then changes to the new set and `onSwapped` runs (the app republishes
///   the Repository and reschedules reminders).
/// - Any failure leaves the current data untouched, is logged (debug builds), and never throws.
///
/// At start, ``loadActive()`` uses the downloaded set only if it is intact, valid and newer than
/// the bundled resources' own manifest; otherwise the bundled resources (never a mix of the two).
///
/// Crash guard: a downloaded set is on probation for ``PROBATION_MS`` after it is swapped in. If
/// the app crashes ``MAX_CRASHES`` times with it during that time, the `current` pointer is
/// deleted, so the app uses the bundled resources from then on, and that version is not
/// downloaded again by this app version (a newer published version is). Android counts each
/// crash in an uncaught-exception handler; iOS can't run code when Swift traps, so here the
/// guard keeps a launch marker instead:
///
/// - The marker is the file `root/.running` ("<version> <epoch millis> <app version>"), written
///   atomically whenever this process is in the foreground with a downloaded set on probation in
///   use: when ``loadActive()`` picks one, when a check swaps one in, and on every
///   ``onForeground()`` (which also re-dates it). Writing it also sets a one-shot timer for the
///   moment probation ends, which deletes it if the app is still in the foreground then (it can
///   stay there for hours: Directions keeps the screen on), so a marker exists only while the
///   set is on probation, and a crash after probation is never counted, as on Android.
/// - It is deleted by ``onBackground()``, which the app calls whenever it leaves the foreground
///   (scenePhase `.inactive` or `.background`, and `willTerminateNotification`): the last moment
///   iOS reliably runs app code before it may suspend or kill the app, so a clean exit, a
///   swipe-away from the app switcher or a later kill in the background never leave a marker
///   behind. (A file, not prefs: the write reaches the file system at once and survives a crash
///   right after; UserDefaults may persist later.)
/// - A marker still there at the next launch means the previous process died in the
///   foreground: a crash (or a watchdog / out-of-memory kill, or the phone switching off, which
///   is why one crash is not enough). ``installCrashGuard()`` counts it with Android's rules
///   (``onCrash(version:at:appVersion:)``), taking the marker's time as the crash time (the
///   timer above keeps it within probation) and the marker's app version as the version that
///   crashed (the relaunch may already be an app update: the rollback is remembered for the
///   version that crashed, as Android's in-process count does). It runs once per process,
///   before anything else touches the marker (``loadActive()``, ``onForeground()`` and
///   ``onBackground()`` call it first), so the launch that follows the ``MAX_CRASHES``th crash
///   already starts from the bundled resources, as Android's next start does.
/// - The marker is never written while the app is in the background (after ``onBackground()``,
///   until the next ``onForeground()``); a process starts out as in the foreground.
///
/// Rejections (broken sets, crash rollbacks) are remembered per app version (`CFBundleVersion`,
/// Android's version code), so an app update that can read a set the old version rejected
/// downloads it again.
///
/// Threads: ``loadActive()`` blocks (call it off the main thread, e.g. in `Task.detached`);
/// ``check()`` is `async` and runs off the main actor, one at a time. ``active`` and ``status``
/// are thread-safe and `Observable` (Kotlin's StateFlows): SwiftUI views and
/// `withObservationTracking` see changes, which happen on whatever thread the work runs on;
/// `onSwapped` is called on that background thread too.
final class DataSync: Observable, @unchecked Sendable {
    private let root: URL
    private let bundled: @Sendable (String) throws -> Data
    private let fetcher: any DataFetcher
    private let prefs: any KeyValueStore
    private let baseUrl: String
    private let onSwapped: @Sendable (ActiveData) -> Void
    private let nowMillis: @Sendable () -> Int64
    private let appVersion: Int
    private let log: @Sendable (String) -> Void
    private let schedule: @Sendable (Int64, @escaping @Sendable () -> Void) -> Void

    private struct State {
        var active: ActiveData?
        var status = SyncStatus()
        var lastCheckMillis: Int64?
        /// The files the bundled manifest lists: a downloaded set must have all of them.
        var requiredFiles: [String] = []
    }

    private struct CrashGuardState {
        /// ``installCrashGuard()``'s result, once it has run.
        var result: Bool?
        var foreground = true
        /// When the pending probation-end timer fires (wall-clock millis), if one is pending.
        var probationTimerAt: Int64?
    }

    private let state = Locked(State())
    /// Guards the launch marker file (and the foreground flag) so a marker is never written
    /// after ``onBackground()`` has deleted it.
    private let crashGuard = Locked(CrashGuardState())
    private let loadLock = NSLock()
    private let mutex = CheckMutex()
    private let registrar = ObservationRegistrar()

    /// - Parameters:
    ///   - root: the folder for downloaded sets (the app: Application Support/data; Android
    ///     filesDir/data). Created when needed.
    ///   - bundled: reads a bundled data file by name (``bundledOpener(_:)``); throws if it
    ///     doesn't exist.
    ///   - baseUrl: ends with '/'.
    ///   - nowMillis: wall-clock millis, for the foreground throttle, "last checked" and
    ///     probation (not the app's "now", which may be faked).
    ///   - appVersion: `CFBundleVersion` (``appVersion(from:)``): remembered rejections apply to
    ///     this app version only.
    ///   - log: debug messages (Android `Log.d`); prints in debug builds by default.
    ///   - schedule: runs an action after a delay in wall-clock millis, on any thread (the crash
    ///     guard's probation-end timer); ``dispatchAfter`` by default. Tests pass a fake clock's.
    init(
        root: URL,
        bundled: @escaping @Sendable (String) throws -> Data,
        fetcher: any DataFetcher,
        prefs: any KeyValueStore,
        baseUrl: String,
        onSwapped: @escaping @Sendable (ActiveData) -> Void = { _ in },
        nowMillis: @escaping @Sendable () -> Int64 = { Date().epochMillis },
        appVersion: Int = 0,
        log: @escaping @Sendable (String) -> Void = DataSync.debugLog,
        schedule: @escaping @Sendable (Int64, @escaping @Sendable () -> Void) -> Void = DataSync.dispatchAfter
    ) {
        self.root = root
        self.bundled = bundled
        self.fetcher = fetcher
        self.prefs = prefs
        self.baseUrl = baseUrl
        self.onSwapped = onSwapped
        self.nowMillis = nowMillis
        self.appVersion = appVersion
        self.log = log
        self.schedule = schedule
    }

    /// The data set in use; nil until ``loadActive()`` has run. Observable.
    var active: ActiveData? {
        registrar.access(self, keyPath: \.active)
        return state.value.active
    }

    /// Observable.
    var status: SyncStatus {
        registrar.access(self, keyPath: \.status)
        return state.value.status
    }

    var manifestUrl: String { baseUrl + DataManifest.FILE }

    private func setActive(_ a: ActiveData) {
        registrar.withMutation(of: self, keyPath: \.active) {
            state.withLock { $0.active = a }
        }
    }

    private func setStatus(_ s: SyncStatus) {
        registrar.withMutation(of: self, keyPath: \.status) {
            state.withLock { $0.status = s }
        }
    }

    // MARK: - Start

    /// The data set to use, loaded on first call (blocking: call off the main thread). Throws
    /// only if the bundled resources themselves can't be loaded. Runs ``installCrashGuard()``
    /// first.
    func loadActive() throws -> ActiveData {
        if let a = state.value.active { return a }
        installCrashGuard()
        loadLock.lock()
        defer { loadLock.unlock() }
        if let a = state.value.active { return a }
        let bundledManifest = readBundledManifest()
        state.withLock { $0.requiredFiles = bundledManifest.files.keys }
        let local = currentDir().flatMap { dir in loadLocal(dir, bundledVersion: bundledManifest.version) }
        let result: ActiveData
        if let local {
            result = local
        } else {
            result = ActiveData(repository: try Repository.load(open: bundled), manifest: bundledManifest, source: .bundled)
        }
        prune(keep: result.dir)
        setActive(result)
        armCrashMarker()
        return result
    }

    private func readBundledManifest() -> DataManifest {
        do {
            return try DataManifest.parse(bundled(DataManifest.FILE))
        } catch {
            debug("no bundled manifest", error)
            return DataManifest()
        }
    }

    /// The downloaded set in `dir` if it is newer than `bundledVersion`, intact and valid.
    private func loadLocal(_ dir: URL, bundledVersion: Int) -> ActiveData? {
        do {
            let m = try DataManifest.parse(Data(contentsOf: file(dir, DataManifest.FILE)))
            let required = state.value.requiredFiles
            if m.version <= bundledVersion {
                debug("downloaded v\(m.version) is not newer than bundled v\(bundledVersion)")
                return nil
            }
            if m.version == badVersion() {
                debug("downloaded v\(m.version) was rolled back after crashes")
                return nil
            }
            let manifestProblems = m.problems(required)
            if !manifestProblems.isEmpty {
                debug("downloaded manifest: \(DataSync.list(manifestProblems))")
                return nil
            }
            for (name, e) in m.files {
                let b = try Data(contentsOf: file(dir, name))
                guard Int64(b.count) == e.bytes && DataManifest.sha256(b) == e.sha256 else {
                    throw DataSyncError("\(name) changed on disk")
                }
            }
            // Verified in full (details.json too) before it was committed; the hashes above
            // prove it is unchanged, so details.json stays lazy here (cold start).
            let repo = try Repository.fromDirectory(dir)
            let problems = try DataValidator.problems(repo, includeDetails: false, files: m.files.keys)
            if problems.isEmpty { return ActiveData(repository: repo, manifest: m, source: .github, dir: dir) }
            debug("downloaded set invalid: \(DataSync.list(problems))")
            return nil
        } catch {
            debug("downloaded set unusable", error)
            return nil
        }
    }

    // MARK: - Checks

    /// The app came to the foreground (scenePhase `.active`, also at launch): re-arms the crash
    /// guard's launch marker, then checks if none has run in this process, or the last was
    /// long enough ago (Kotlin: `watchForeground`'s first activity start). Returns the check's
    /// task, if one started.
    @discardableResult
    func onForeground() -> Task<SyncOutcome, Never>? {
        installCrashGuard()
        crashGuard.withLock { $0.foreground = true }
        armCrashMarker()
        return isDue() ? checkInBackground() : nil
    }

    /// The app left the foreground (scenePhase `.inactive` or `.background`, or
    /// `willTerminateNotification`): it ran healthily, so the launch marker goes (see the type's
    /// documentation). iOS only (Android needs no such hook).
    func onBackground() {
        installCrashGuard()
        crashGuard.withLock { g in
            g.foreground = false
            removeIfExists(markerFile)
        }
    }

    /// True if no check has started in this process, or the last one started ``FOREGROUND_INTERVAL_MS`` ago.
    func isDue() -> Bool { isDue(at: nowMillis()) }

    /// ``isDue()`` at `now` (wall-clock millis).
    func isDue(at now: Int64) -> Bool {
        guard let last = state.value.lastCheckMillis else { return true }
        return now &- last >= DataSync.FOREGROUND_INTERVAL_MS
    }

    /// "Check now": runs ``check()`` in the background unless one is already running. Returns
    /// its task (nil if one was running).
    @discardableResult
    func checkInBackground() -> Task<SyncOutcome, Never>? {
        if state.value.status.checking { return nil }
        state.withLock { $0.lastCheckMillis = nowMillis() }
        return Task.detached { [self] in await self.check() }
    }

    /// One check: manifest, downloads, verification, swap. Runs off the main actor
    /// (`@concurrent`: on the global executor whoever awaits it, like Kotlin's IO dispatcher),
    /// one at a time; never throws. Once started it runs to the end even if the calling task is
    /// cancelled (as Kotlin's blocking check body does).
    @concurrent
    func check() async -> SyncOutcome {
        await mutex.lock()
        defer { mutex.unlock() }
        state.withLock { $0.lastCheckMillis = nowMillis() }
        setStatus(state.value.status.copy(checking: true))
        let outcome: SyncOutcome
        do {
            outcome = try await runCheck()
        } catch {
            // A file write or the bundled data failing: drop it and keep the current data.
            outcome = .failed(DataSync.describe(error))
        }
        removeIfExists(stagingDir)
        debug("check: \(outcome)")
        setStatus(SyncStatus(checking: false, last: outcome, lastCheckedAt: Date(epochMillis: nowMillis())))
        return outcome
    }

    private func runCheck() async throws -> SyncOutcome {
        let active = try loadActive()
        let etag = prefs.string(forKey: DataSync.KEY_ETAG)
        let etagVersion = prefs.int(forKey: DataSync.KEY_ETAG_VERSION) ?? 0
        // A rejection by an older app version doesn't count: this one may accept the set.
        let etagRejected = (prefs.bool(forKey: DataSync.KEY_ETAG_REJECTED) ?? false)
            && (prefs.int(forKey: DataSync.KEY_REJECTED_BY) ?? -1) == appVersion
        // Only trust a 304 if we already hold that manifest's data (or know it is broken).
        let ifNoneMatch = etag.flatMap { e in etagRejected || active.version >= etagVersion ? e : nil }

        let body: Data
        let bodyEtag: String?
        switch await fetcher.get(manifestUrl, ifNoneMatch: ifNoneMatch, maxBytes: DataSync.MAX_MANIFEST_BYTES) {
        case .notModified: return .notModified
        case .failed(let reason): return .failed("manifest: " + reason)
        case .ok(let b, let e):
            body = b
            bodyEtag = e
        }
        if Int64(body.count) > DataSync.MAX_MANIFEST_BYTES { return .failed("manifest too large") }
        let remote: DataManifest
        do {
            remote = try DataManifest.parse(body)
        } catch {
            remember(bodyEtag, 0, rejected: true)
            return .rejected("manifest: " + DataSync.message(error))
        }
        let manifestProblems = remote.problems(state.value.requiredFiles)
        if !manifestProblems.isEmpty {
            remember(bodyEtag, remote.version, rejected: true)
            return .rejected("manifest: " + DataSync.list(manifestProblems))
        }
        if remote.version <= active.version {
            remember(bodyEtag, remote.version, rejected: false)
            return .notNewer(remote.version)
        }
        if remote.version == badVersion() {
            remember(bodyEtag, remote.version, rejected: true)
            return .rejected("v\(remote.version) was rolled back after crashes")
        }

        // Stage the complete set: reuse identical files, download the rest.
        let fm = FileManager.default
        let staging = stagingDir
        removeIfExists(staging)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            return .failed("can't create \(staging.path)")
        }
        for (name, entry) in remote.files {
            let bytes: Data
            if let b = try reusable(active, name, entry) {
                bytes = b // its size and sha256 were just checked
            } else {
                switch await fetcher.get(baseUrl + name, ifNoneMatch: nil, maxBytes: entry.bytes) {
                case .ok(let b, _): bytes = b
                case .notModified: return .failed("\(name): unexpected 304")
                case .failed(let reason): return .failed("\(name): " + reason)
                }
                if Int64(bytes.count) != entry.bytes { return .failed("\(name): \(bytes.count) bytes, expected \(entry.bytes)") }
                if DataManifest.sha256(bytes) != entry.sha256 { return .failed("\(name): sha256 mismatch") }
            }
            try bytes.write(to: file(staging, name))
        }
        try body.write(to: file(staging, DataManifest.FILE))

        // Parse and cross-check the whole set before anything changes.
        let repo: Repository
        do {
            repo = try Repository.fromDirectory(staging)
            _ = try repo.details // details.json too, before the folder moves
        } catch {
            remember(bodyEtag, remote.version, rejected: true)
            return .rejected("parse: " + DataSync.message(error))
        }
        let problems = try DataValidator.problems(repo, files: remote.files.keys)
        if !problems.isEmpty {
            remember(bodyEtag, remote.version, rejected: true)
            return .rejected("invalid: " + DataSync.list(problems))
        }

        // Commit: folder rename, then the pointer flip (the atomic step).
        let dir = root.appendingPathComponent("v\(remote.version)", isDirectory: true)
        if fm.fileExists(atPath: dir.path) {
            do {
                try fm.removeItem(at: dir)
            } catch {
                return .failed("can't clear \(dir.path)")
            }
        }
        if rename(staging.path, dir.path) != 0 { return .failed("can't rename \(staging.path)") }
        let tmp = file(root, DataSync.POINTER + ".tmp")
        try Data(dir.lastPathComponent.utf8).write(to: tmp)
        if rename(tmp.path, pointerFile.path) != 0 {
            removeIfExists(dir)
            return .failed("can't update \(DataSync.POINTER)")
        }

        let next = ActiveData(repository: repo, manifest: remote, source: .github, dir: dir)
        let since = nowMillis()
        prefs.edit { e in
            e.set(remote.version, forKey: DataSync.KEY_PROBATION_VERSION)
            e.set(since, forKey: DataSync.KEY_PROBATION_SINCE)
            e.set(0, forKey: DataSync.KEY_CRASHES)
        }
        setActive(next)
        armCrashMarker()
        remember(bodyEtag, remote.version, rejected: false)
        onSwapped(next)
        return .updated(remote.version)
    }

    /// `name`'s bytes from the set in use (or the bundled resources) if identical to `entry`; else nil.
    private func reusable(_ active: ActiveData, _ name: String, _ entry: ManifestEntry) throws -> Data? {
        func matches(_ b: Data) -> Bool { Int64(b.count) == entry.bytes && DataManifest.sha256(b) == entry.sha256 }
        if let d = active.dir {
            let f = file(d, name)
            if isFile(f) {
                let b = try Data(contentsOf: f)
                if matches(b) { return b }
            }
        }
        let b = try? bundled(name) // nil: not bundled
        return b.flatMap { matches($0) ? $0 : nil }
    }

    private func remember(_ etag: String?, _ version: Int, rejected: Bool) {
        let appVersion = appVersion
        prefs.edit { e in
            if let etag {
                e.set(etag, forKey: DataSync.KEY_ETAG)
            } else {
                e.removeValue(forKey: DataSync.KEY_ETAG)
            }
            e.set(version, forKey: DataSync.KEY_ETAG_VERSION)
            e.set(rejected, forKey: DataSync.KEY_ETAG_REJECTED)
            e.set(appVersion, forKey: DataSync.KEY_REJECTED_BY)
        }
    }

    /// The downloaded version this app version rolled back after crashes, or 0.
    private func badVersion() -> Int {
        (prefs.int(forKey: DataSync.KEY_BAD_VERSION_APP) ?? -1) == appVersion ? (prefs.int(forKey: DataSync.KEY_BAD_VERSION) ?? 0) : 0
    }

    // MARK: - Crash guard

    /// The crash guard's launch step (Android installs its uncaught-exception handler here): if
    /// the previous process left its launch marker (it died in the foreground with a downloaded
    /// set on probation), counts that crash with ``onCrash(version:at:appVersion:)``. Runs once per
    /// DataSync (a process); later calls return the first result. ``loadActive()``,
    /// ``onForeground()`` and ``onBackground()`` run it first, so calling it at launch is
    /// optional. Returns true if it rolled the set back.
    @discardableResult
    func installCrashGuard() -> Bool {
        crashGuard.withLock { g in
            if let r = g.result { return r }
            let r = countPreviousCrash()
            g.result = r
            return r
        }
    }

    private func countPreviousCrash() -> Bool {
        let url = markerFile
        guard let data = try? Data(contentsOf: url) else { return false }
        removeIfExists(url)
        // "<version> <millis> <app version>"; without the app version (the form earlier builds
        // wrote) the crash is this app version's.
        let parts = String(decoding: data, as: UTF8.self).kotlinTrim().components(separatedBy: " ")
        guard parts.count == 2 || parts.count == 3, let version = Int(parts[0]), let at = Int64(parts[1]) else {
            debug("bad launch marker")
            return false
        }
        var crashedAppVersion: Int?
        if parts.count == 3 {
            guard let v = Int(parts[2]) else {
                debug("bad launch marker")
                return false
            }
            crashedAppVersion = v
        }
        debug("the last run with v\(version) ended in the foreground: a crash")
        return onCrash(version: version, at: at, appVersion: crashedAppVersion)
    }

    /// Android's `onCrash` policy for a crash of the process that used downloaded set `version`
    /// (its launch marker says so; the marker exists only for downloaded sets) at `at` (wall-clock
    /// millis): if the set was on probation then, count it; at ``MAX_CRASHES`` drop the set
    /// (delete the pointer), so this and every later start use the bundled resources, and
    /// remember the rollback for `appVersion`, the app version that crashed (nil: this one).
    /// Returns true if it rolled back.
    @discardableResult
    func onCrash(version: Int, at: Int64, appVersion crashedAppVersion: Int? = nil) -> Bool {
        if (prefs.int(forKey: DataSync.KEY_PROBATION_VERSION) ?? 0) != version { return false }
        if at &- (prefs.int64(forKey: DataSync.KEY_PROBATION_SINCE) ?? 0) > DataSync.PROBATION_MS { return false }
        let crashes = (prefs.int(forKey: DataSync.KEY_CRASHES) ?? 0) &+ 1
        if crashes < DataSync.MAX_CRASHES {
            prefs.set(crashes, forKey: DataSync.KEY_CRASHES)
            return false
        }
        removeIfExists(pointerFile)
        let appVersion = crashedAppVersion ?? appVersion
        prefs.edit { e in
            e.set(version, forKey: DataSync.KEY_BAD_VERSION)
            e.set(appVersion, forKey: DataSync.KEY_BAD_VERSION_APP)
            e.removeValue(forKey: DataSync.KEY_PROBATION_VERSION)
            e.set(0, forKey: DataSync.KEY_CRASHES)
        }
        debug("rolled back v\(version) after \(crashes) crashes")
        return true
    }

    /// Writes the launch marker if this process is in the foreground with a downloaded set on
    /// probation in use (dated now, with this app version); otherwise makes sure there is none.
    /// While it is on probation, also makes sure a timer runs this again just after probation
    /// ends, which then deletes the marker.
    private func armCrashMarker() {
        installCrashGuard()
        let appVersion = appVersion
        let timer: (at: Int64, delay: Int64)? = crashGuard.withLock { g in
            let now = nowMillis()
            let url = markerFile
            guard g.foreground, let a = state.value.active, a.source == .github, let since = probationSince(a.version),
                now &- since <= DataSync.PROBATION_MS else {
                removeIfExists(url)
                return nil
            }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try Data("\(a.version) \(now) \(appVersion)".utf8).write(to: url, options: .atomic)
            } catch {
                debug("can't write the launch marker", error)
            }
            let at = since &+ DataSync.PROBATION_MS &+ 1
            if g.probationTimerAt == at { return nil } // already pending
            g.probationTimerAt = at
            // At least 1 ms; at most a probation (a clock set back: it fires early and re-arms).
            let delay: Int64 = min(max(at &- now, 1), DataSync.PROBATION_MS + 1)
            return (at, delay)
        }
        // Scheduled outside the lock: the action takes it.
        if let timer {
            schedule(timer.delay) { [weak self] in self?.probationTimerFired(timer.at) }
        }
    }

    /// The probation-end timer for `at`: re-arms, which deletes the marker once probation is over
    /// (or, if the clock moved and it fired early, re-dates it and sets a new timer).
    private func probationTimerFired(_ at: Int64) {
        crashGuard.withLock { g in
            if g.probationTimerAt == at { g.probationTimerAt = nil }
        }
        armCrashMarker()
    }

    /// When the set `version` went on probation (wall-clock millis), if it is the one on
    /// probation (or was: probation is over ``PROBATION_MS`` after that).
    private func probationSince(_ version: Int) -> Int64? {
        guard (prefs.int(forKey: DataSync.KEY_PROBATION_VERSION) ?? 0) == version else { return nil }
        return prefs.int64(forKey: DataSync.KEY_PROBATION_SINCE) ?? 0
    }

    // MARK: - Files

    private var pointerFile: URL { file(root, DataSync.POINTER) }
    private var stagingDir: URL { root.appendingPathComponent(DataSync.STAGING, isDirectory: true) }
    private var markerFile: URL { file(root, DataSync.LAUNCH_MARKER) }

    private func file(_ dir: URL, _ name: String) -> URL { dir.appendingPathComponent(name, isDirectory: false) }

    private func isFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func removeIfExists(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
    }

    private func currentDir() -> URL? {
        let p = pointerFile
        guard isFile(p) else { return nil }
        do {
            let name = String(decoding: try Data(contentsOf: p), as: UTF8.self).kotlinTrim()
            guard DataSync.VERSION_DIR.matches(name) else { return nil }
            let dir = root.appendingPathComponent(name, isDirectory: true)
            return isDirectory(dir) ? dir : nil
        } catch {
            debug("no current pointer", error)
            return nil
        }
    }

    /// Deletes every downloaded set except `keep` (and the pointer if nothing is kept).
    private func prune(keep: URL?) {
        guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for f in children {
            let name = f.lastPathComponent
            let keepIt = keep.map { k in name == k.lastPathComponent || name == DataSync.POINTER } ?? false
            if !keepIt { try? FileManager.default.removeItem(at: f) }
        }
    }

    private func debug(_ msg: String, _ error: (any Error)? = nil) {
        log("data sync: " + msg + (error.map { " (\(DataSync.describe($0)))" } ?? ""))
    }

    // MARK: - Constants

    static let TAG = "kcna26"
    static let PREFS = "kcna26.sync"

    /// Foreground checks at most this often (app start always checks).
    static let FOREGROUND_INTERVAL_MS: Int64 = 15 * 60 * 1000

    static let MAX_MANIFEST_BYTES: Int64 = 256 * 1024

    /// How long a newly downloaded set is on probation for the crash guard.
    static let PROBATION_MS: Int64 = 24 * 60 * 60 * 1000

    /// Crashes with a set on probation before it is rolled back (one could be unrelated).
    static let MAX_CRASHES = 2

    static let POINTER = "current"
    static let STAGING = ".staging"
    /// iOS: the crash guard's launch marker in `root` (see the type's documentation).
    static let LAUNCH_MARKER = ".running"

    /// Where the published data lives unless the Info.plist says otherwise (Android's
    /// `DATA_BASE_URL` default).
    static let DEFAULT_BASE_URL = "https://raw.githubusercontent.com/intUnderflow/kubecon-na-2026/main/data/"

    /// The Info.plist key holding the data base URL (the `KCNA26_DATA_BASE_URL` build setting).
    static let INFO_BASE_URL_KEY = "KCNA26DataBaseURL"

    private static let VERSION_DIR = KRegex("^v[0-9]+$")
    private static let KEY_ETAG = "manifestEtag"
    private static let KEY_ETAG_VERSION = "manifestEtagVersion"
    private static let KEY_ETAG_REJECTED = "manifestEtagRejected"
    private static let KEY_REJECTED_BY = "rejectedByAppVersion"
    private static let KEY_PROBATION_VERSION = "probationVersion"
    private static let KEY_PROBATION_SINCE = "probationSince"
    private static let KEY_CRASHES = "probationCrashes"
    private static let KEY_BAD_VERSION = "rolledBackVersion"
    private static let KEY_BAD_VERSION_APP = "rolledBackByAppVersion"

    // MARK: - App wiring (Android: BuildConfig, AssetManager)

    /// Reads a bundled data file by name from the app bundle's "Data" folder (Android `assets::open`).
    static func bundledOpener(_ bundle: Bundle = .main) -> @Sendable (String) throws -> Data {
        let dir = Repository.bundledDataDirectory(in: bundle)
        let location = bundle.bundlePath
        return { name in
            guard let dir else { throw DataFileMissingError(name: "Data", location: location) }
            return try Data(contentsOf: dir.appendingPathComponent(name, isDirectory: false))
        }
    }

    /// The data base URL from the Info.plist (``INFO_BASE_URL_KEY``), else ``DEFAULT_BASE_URL``.
    static func baseUrl(from bundle: Bundle = .main) -> String {
        let s = (bundle.object(forInfoDictionaryKey: INFO_BASE_URL_KEY) as? String)?.kotlinTrim() ?? ""
        return s.isEmpty || s.hasPrefix("$(") ? DEFAULT_BASE_URL : s
    }

    /// `CFBundleVersion` as an integer (Android `BuildConfig.VERSION_CODE`), or 0.
    static func appVersion(from bundle: Bundle = .main) -> Int {
        (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { Int($0.kotlinTrim()) } ?? 0
    }

    /// Runs `action` on a global queue after `delayMillis` of wall-clock time (a suspended app
    /// runs it when it resumes, if the time has passed by then): the default `schedule`.
    static let dispatchAfter: @Sendable (Int64, @escaping @Sendable () -> Void) -> Void = { delayMillis, action in
        let ms = Int(min(max(delayMillis, 0), Int64(Int32.max)))
        DispatchQueue.global(qos: .utility).asyncAfter(wallDeadline: .now() + .milliseconds(ms)) { action() }
    }

    /// Prints in debug builds (Android `Log.d(TAG, …)`); silent in release builds.
    static let debugLog: @Sendable (String) -> Void = { message in
        #if DEBUG
        print("\(TAG): \(message)")
        #endif
    }

    // MARK: - Messages

    /// Kotlin `e.message` for a Swift error.
    static func message(_ error: any Error) -> String {
        if let e = error as? CocoaError { return e.localizedDescription }
        return String(describing: error)
    }

    /// Kotlin `e.javaClass.simpleName + ": " + e.message`.
    static func describe(_ error: any Error) -> String {
        "\(type(of: error)): \(message(error))"
    }

    /// Kotlin `List.toString()`: "[a, b]".
    static func list(_ xs: [String]) -> String { "[" + xs.joined(separator: ", ") + "]" }
}

/// Kotlin `require(…)` / `IllegalArgumentException` inside DataSync.
struct DataSyncError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// Kotlin's coroutine `Mutex` for ``DataSync/check()``: one check at a time, in arrival order;
/// waiting suspends the task (never blocks a thread).
private final class CheckMutex: @unchecked Sendable {
    private let state = NSLock()
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            state.lock()
            if locked {
                waiters.append(c)
                state.unlock()
            } else {
                locked = true
                state.unlock()
                c.resume()
            }
        }
    }

    /// Hands the lock to the next waiter, or releases it.
    func unlock() {
        state.lock()
        if waiters.isEmpty {
            locked = false
            state.unlock()
        } else {
            let next = waiters.removeFirst()
            state.unlock()
            next.resume()
        }
    }
}
