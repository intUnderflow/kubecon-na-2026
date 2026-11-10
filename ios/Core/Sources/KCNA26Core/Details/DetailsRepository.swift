import Foundation

/// Session descriptions and speaker taglines (port of schedule_app.js loadDetails / parseMd /
/// fetchOne). Sources, in order:
///
/// 1. in memory (everything resolved so far this process, including "nothing there"),
/// 2. the bundled details.json (`Repository.details`, 558 of 579 KubeCon sessions, plus every
///    co-located session from colocated.json),
/// 3. Maintainer Summit sessions ("m…" ids): `Session.description` / `Session.slidesUrl` from
///    schedule.json (maintainer_summit_details.json by id as a fallback),
/// 4. a disk cache under `cacheDir` (one `<id>.json` per session, details.json's entry shape),
/// 5. a live Sessionize fetch, KubeCon ids only, parsed by ``SessionizeMarkdown`` and written to (4).
///    Co-located sessions (`Session.isColocated`) have plain numeric ids too, but they belong to
///    another Sessionize event: they are never fetched or disk-cached (the bundle is complete).
///
/// Offline-safe: nothing here throws. A failed fetch is reported as ``DetailsResult/unavailable``
/// and is not retried for `failBackoffMillis` (re-opening the sheet after that tries once more).
/// Concurrent requests for one id share a single fetch, and a fetch keeps running (and caches)
/// even if the screen that asked for it goes away (an unstructured task, like Kotlin's own
/// scope). Disk and network work runs off the caller's actor (`Task.detached`).
///
/// Thread-safe (`Sendable`): ``peek(_:)`` / ``peekResult(_:)`` are synchronous and do no I/O
/// (call them from the main actor); ``load(_:)`` / ``get(_:)`` are `async`.
///
/// The app constructs it as
/// `DetailsRepository(repository, cacheDir: <Application Support>/details)` (one per
/// Repository, like Kotlin's `RepositoryScoped`), and calls ``warmBundled()`` off the main
/// thread after loading the Repository.
final class DetailsRepository: Sendable {
    private let repo: Repository
    private let cacheDir: URL
    private let fetcher: any DetailsFetcher
    /// Monotonic milliseconds, for the retry backoff only (not app "now", which may be faked).
    private let elapsedMillis: @Sendable () -> Int64
    private let failBackoffMillis: Int64

    private let memory = Locked<[String: DetailsResult]>([:])
    private let failedAt = Locked<[String: Int64]>([:])
    private let inFlight = Locked<[String: InFlight]>([:])
    private let nextToken = Locked<Int>(0)

    /// details.json, once something has touched it off the main thread (see ``warmBundled()``).
    private let bundled = Locked<OrderedMap<String, SessionDetail>?>(nil)

    private struct InFlight {
        let token: Int
        let task: Task<DetailsResult, Never>
    }

    init(
        _ repo: Repository,
        cacheDir: URL,
        fetcher: any DetailsFetcher = SessionizeFetcher(),
        elapsedMillis: @escaping @Sendable () -> Int64 = DetailsRepository.monotonicMillis,
        failBackoffMillis: Int64 = DetailsRepository.FAIL_BACKOFF_MS
    ) {
        self.repo = repo
        self.cacheDir = cacheDir
        self.fetcher = fetcher
        self.elapsedMillis = elapsedMillis
        self.failBackoffMillis = failBackoffMillis
    }

    /// Synchronous lookup without I/O or network. Nil if not available (yet).
    func peek(_ sessionId: String) -> DetailInfo? { peekResult(sessionId)?.info }

    /// Full lookup: ``load(_:)``, keeping only the details themselves. Nil if none.
    func get(_ sessionId: String) async -> DetailInfo? { await load(sessionId).info }

    /// What is known without any I/O: memory, Maintainer Summit data, and details.json if it has
    /// already been parsed. ``DetailsResult/unavailable`` while a recent failure is backing off.
    /// Nil means "unknown until ``load(_:)`` runs".
    func peekResult(_ sessionId: String) -> DetailsResult? {
        if let r = memory.withLock({ $0[sessionId] }) { return r }
        guard let s = repo.session(sessionId) else { return .nothing }
        if s.isMaintainerSummit { return keep(sessionId, summit(s)) }
        guard let b = bundled.value else { return nil }
        if let d = b[sessionId] { return keep(sessionId, found(s, d, .bundled)) }
        return isBackingOff(sessionId) ? .unavailable : nil
    }

    /// Resolves a session's details from every source, fetching live if needed. Never throws.
    func load(_ sessionId: String) async -> DetailsResult {
        if let r = peekResult(sessionId), r != .unavailable { return r }
        guard let s = repo.session(sessionId) else { return .nothing }
        let local = await Task.detached { self.local(s) }.value
        if let local { return local }
        if !isFetchable(s) { return keep(sessionId, .nothing) }
        return await fetchShared(sessionId).value
    }

    /// Parses details.json now. Blocking: call off the main thread (e.g. at app start).
    func warmBundled() {
        _ = bundledMap()
    }

    // MARK: - sources

    private func bundledMap() -> OrderedMap<String, SessionDetail> {
        if let b = bundled.value { return b }
        let m: OrderedMap<String, SessionDetail>
        do {
            m = try repo.details
        } catch {
            detailsLog("details.json unreadable: \(error)")
            m = [:]
        }
        bundled.value = m
        return m
    }

    /// Bundled, then disk. Blocking: runs in a detached task.
    private func local(_ s: Session) -> DetailsResult? {
        if let d = bundledMap()[s.id] { return keep(s.id, found(s, d, .bundled)) }
        if let d = readDisk(s.id) { return keep(s.id, found(s, d, .diskCache)) }
        return nil
    }

    private func fetchShared(_ id: String) -> Task<DetailsResult, Never> {
        inFlight.withLock { flights in
            if let f = flights[id] { return f.task }
            if isBackingOff(id) { return Task { .unavailable } }
            let token = nextToken.withLock { n -> Int in
                n += 1
                return n
            }
            // The task's clean-up takes this lock, so it cannot run before the entry is stored.
            let task = Task.detached { () -> DetailsResult in
                let r = await self.fetchNow(id)
                self.inFlight.withLock { fs in
                    if fs[id]?.token == token { fs[id] = nil }
                }
                return r
            }
            flights[id] = InFlight(token: token, task: task)
            return task
        }
    }

    private func fetchNow(_ id: String) async -> DetailsResult {
        guard let s = repo.session(id) else { return .nothing }
        if !isFetchable(s) { return keep(id, .nothing) }
        // Another caller may have cached it while this one was queued.
        if let r = memory.withLock({ $0[id] }) { return r }
        if let d = readDisk(id) { return keep(id, found(s, d, .diskCache)) }
        let r: FetchResult
        do {
            r = try await fetcher.fetch(id)
        } catch {
            r = .failed(String(describing: error))
        }
        switch r {
        case .ok(let body):
            failedAt.withLock { $0[id] = nil }
            let d = SessionizeMarkdown.parse(body)
            if !d.description.isEmpty || !d.speakers.isEmpty {
                writeDisk(id, d)
                return keep(id, found(s, d, .live))
            } else {
                // Like the web: remember "nothing there" in memory only.
                return keep(id, .nothing)
            }
        case .notFound:
            failedAt.withLock { $0[id] = nil }
            return keep(id, .nothing)
        case .failed(let reason):
            detailsLog("details \(id): \(reason)")
            let t = elapsedMillis()
            failedAt.withLock { $0[id] = t }
            return .unavailable
        }
    }

    private func isBackingOff(_ id: String) -> Bool {
        guard let t = failedAt.withLock({ $0[id] }) else { return false }
        return elapsedMillis() - t < failBackoffMillis
    }

    private func keep(_ id: String, _ r: DetailsResult) -> DetailsResult {
        if r != .unavailable { memory.withLock { $0[id] = r } }
        return r
    }

    // MARK: - disk cache

    private func cacheFile(_ id: String) -> URL { cacheDir.appendingPathComponent("\(id).json", isDirectory: false) }

    /// Live-fetchable from the main KubeCon Sessionize event (and so disk-cached).
    private func isFetchable(_ s: Session) -> Bool { !s.isColocated && DetailsRepository.isKubeConId(s.id) }

    private func isCacheable(_ id: String) -> Bool {
        DetailsRepository.isKubeConId(id) && repo.session(id)?.isColocated != true
    }

    private func readDisk(_ id: String) -> SessionDetail? {
        if !isCacheable(id) { return nil }
        let f = cacheFile(id)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: f.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        do {
            let text = String(decoding: try Data(contentsOf: f), as: UTF8.self)
            let e = try JSON.decode(CachedDetail.self, from: text)
            let d = SessionDetail(description: e.description, speakers: e.speakers.map { SpeakerTagline($0.name, $0.tagline) })
            return (!d.description.isEmpty || !d.speakers.isEmpty) ? d : nil
        } catch {
            detailsLog("dropping unreadable cache \(f.path): \(error)")
            try? FileManager.default.removeItem(at: f)
            return nil
        }
    }

    private func writeDisk(_ id: String, _ d: SessionDetail) {
        if !isCacheable(id) { return }
        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let tmp = cacheDir.appendingPathComponent("\(id).json.tmp", isDirectory: false)
            let cached = CachedDetail(description: d.description, speakers: d.speakers.map { CachedSpeaker(name: $0.name, tagline: $0.tagline) })
            try Data(JSON.serialize(cached.toJSON()).utf8).write(to: tmp)
            // rename(2) replaces an existing file, like Java's File.renameTo on Linux/Android.
            if rename(tmp.path, cacheFile(id).path) != 0 {
                try? FileManager.default.removeItem(at: cacheFile(id))
                try FileManager.default.moveItem(at: tmp, to: cacheFile(id))
            }
        } catch {
            detailsLog("can't cache details \(id): \(error)")
        }
    }

    // MARK: - mapping

    private func found(_ s: Session, _ d: SessionDetail, _ source: DetailInfo.Source) -> DetailsResult {
        .found(
            DetailInfo(
                description: d.description.takeIfNotBlank(),
                speakers: d.speakers,
                slidesUrl: s.slidesUrl,
                link: nil,
                linkText: nil,
                source: source
            )
        )
    }

    /// The web's `MSD[x.id]`. (Its `MSD.UNCONF` fallback for "Unconference…" sessions, the "See and
    /// vote on the topics" link, went with the unconference feature: voting is over.)
    private func summit(_ s: Session) -> DetailsResult {
        let md = repo.summitDetails[s.id]
        return .found(
            DetailInfo(
                description: (s.description ?? md?.description)?.takeIfNotBlank(),
                speakers: [],
                slidesUrl: s.slidesUrl ?? md?.slides,
                link: md?.link,
                linkText: md?.linkText,
                source: .summit
            )
        )
    }

    /// The disk cache entry (kotlinx `CachedDetail`): defaults are omitted when written
    /// (`encodeDefaults = false`) and tolerated when missing.
    private struct CachedDetail: JSONDecodable, JSONEncodable {
        let description: String
        let speakers: [CachedSpeaker]

        init(description: String = "", speakers: [CachedSpeaker] = []) {
            self.description = description
            self.speakers = speakers
        }

        init(json: JSONValue) throws {
            let o = try JSONFields(json, "CachedDetail")
            description = try o.value("description", default: "")
            speakers = try o.value("speakers", default: [])
        }

        func toJSON() -> JSONValue {
            var o = JSONObjectBuilder()
            o.put("description", description, unlessEqualTo: "")
            o.put("speakers", speakers.map { $0.toJSON() }, unlessEqualTo: [])
            return o.value
        }
    }

    private struct CachedSpeaker: JSONDecodable, JSONEncodable {
        let name: String
        let tagline: String

        init(name: String, tagline: String = "") {
            self.name = name
            self.tagline = tagline
        }

        init(json: JSONValue) throws {
            let o = try JSONFields(json, "CachedSpeaker")
            name = try o.required("name")
            tagline = try o.value("tagline", default: "")
        }

        func toJSON() -> JSONValue {
            var o = JSONObjectBuilder()
            o.put("name", name)
            o.put("tagline", tagline, unlessEqualTo: "")
            return o.value
        }
    }

    /// How long a failed fetch for one session is not retried.
    static let FAIL_BACKOFF_MS: Int64 = 30_000

    /// KubeCon (Sessionize) ids are plain ASCII digits (Kotlin `\d{1,12}` on the JVM).
    private static let KUBECON_ID = KRegex("[0-9]{1,12}")

    /// KubeCon (Sessionize) ids are plain digits; Maintainer Summit ids start with "m".
    static func isKubeConId(_ id: String) -> Bool { KUBECON_ID.matches(id) }

    /// Kotlin `System.nanoTime() / 1_000_000`: monotonic milliseconds.
    @Sendable static func monotonicMillis() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }
}

/// Outcome of ``DetailsRepository/load(_:)`` (Kotlin `sealed interface DetailsResult`).
enum DetailsResult: Sendable, Hashable {
    /// Details to show (the description may still be nil, e.g. a Maintainer Summit break).
    case found(DetailInfo)

    /// Nothing anywhere: the sheet shows no About section (the web's `desc=''`). Kotlin
    /// `DetailsResult.None` (renamed: `.none` would clash with `Optional.none` in a `DetailsResult?`).
    case nothing

    /// Not bundled or cached and the live fetch failed (offline?). Show a quiet note; retry later.
    case unavailable

    /// The details of ``found(_:)``, else nil (Kotlin `(r as? DetailsResult.Found)?.info`).
    var info: DetailInfo? {
        if case .found(let i) = self { return i }
        return nil
    }
}

/// Everything the details sheet shows beyond the schedule fields.
///
/// - `description`: markdown-ish text with blank-line paragraphs (see ``DescriptionFormat``); nil if none.
/// - `speakers`: names with taglines, in order; empty means use `Session.speakers`.
/// - `link` / `linkText`: an optional extra link from maintainer_summit_details.json (opened in the browser).
struct DetailInfo: Sendable, Hashable {
    let description: String?
    let speakers: [SpeakerTagline]
    let slidesUrl: String?
    let link: String?
    let linkText: String?
    let source: Source

    enum Source: String, Sendable, Hashable {
        case bundled = "BUNDLED"
        case summit = "SUMMIT"
        case diskCache = "DISK_CACHE"
        case live = "LIVE"
    }
}

/// Android `Log.w` / `Log.i`: a debug-build console line only.
private func detailsLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("kcna26: \(message())")
    #endif
}
