import XCTest
@testable import KCNA26Core

/// Kotlin -> Swift: kotlinx-coroutines-test's `runTest` + `StandardTestDispatcher` become plain
/// `async` tests (real concurrency; the assertions do not depend on scheduling), the mutable
/// `nowMs` clock is a `Locked` box read by the `elapsedMillis` closure, and the temp directory
/// is made per test like JUnit's per-test instance field.
final class DetailsRepositoryTests: XCTestCase {

    private var dir: URL!
    private let nowMs = Locked<Int64>(1_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kcna26-details-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        try super.tearDownWithError()
    }

    /// Scripted fetcher: answers from `script` (last answer repeats) and counts calls per id.
    private final class FakeFetcher: DetailsFetcher {
        private struct State {
            var answers: [FetchResult]
            var calls: [String] = []
        }

        private let state: Locked<State>

        init(_ script: FetchResult...) {
            state = Locked(State(answers: script))
        }

        var calls: [String] { state.value.calls }

        func fetch(_ sessionId: String) async throws -> FetchResult {
            state.withLock { s in
                s.calls.append(sessionId)
                return s.answers.count > 1 ? s.answers.removeFirst() : s.answers[0]
            }
        }
    }

    private struct Boom: Error, CustomStringConvertible {
        let message: String
        var description: String { "IllegalStateException: \(message)" }
    }

    private func repo(_ fetcher: any DetailsFetcher) -> DetailsRepository {
        let clock = nowMs
        return DetailsRepository(
            TestData.repo,
            cacheDir: dir,
            fetcher: fetcher,
            elapsedMillis: { clock.value }
        )
    }

    private func advance(_ ms: Int64) { nowMs.withLock { $0 += ms } }

    private func file(_ name: String) -> URL { dir.appendingPathComponent(name, isDirectory: false) }

    private func isFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    /// Kotlin `result as DetailsResult.Found` (fails the test otherwise).
    private func found(_ r: DetailsResult, file: StaticString = #filePath, line: UInt = #line) throws -> DetailInfo {
        try XCTUnwrap(r.info, "expected Found, got \(r)", file: file, line: line)
    }

    // A KubeCon session that details.json lacks.
    private let missing = "1302802"
    private var sampleMd: String { SessionizeSamples.byId["1289660"]! }

    func testBundledDetailsNeedNoFetch() async throws {
        let f = FakeFetcher(.failed("must not be called"))
        let r = repo(f)
        let res = try found(await r.load("1289660"))
        XCTAssertEqual(DetailInfo.Source.bundled, res.source)
        XCTAssertTrue(try XCTUnwrap(res.description).isNotBlank)
        XCTAssertEqual(
            ["Lucy Sweet", "Ryan Hallisey", "Filip K\u{159}epinsk\u{FD}"],
            res.speakers.map(\.name)
        )
        XCTAssertEqual("Member of Technical Staff at Anthropic", res.speakers[0].tagline)
        XCTAssertTrue(f.calls.isEmpty)
        // Now in memory: peek is synchronous.
        XCTAssertEqual(res, r.peek("1289660"))
        let got = await r.get("1289660")
        XCTAssertEqual(res, got)
    }

    func testPeekNeedsNoIoAndKnowsBundledOnceWarmed() {
        let r = repo(FakeFetcher(.notFound))
        XCTAssertNil(r.peekResult("1202489"))
        r.warmBundled()
        let info = r.peek("1202489")
        XCTAssertNotNil(info)
        XCTAssertEqual(DetailInfo.Source.bundled, info?.source)
        XCTAssertEqual([SpeakerTagline("Maciej Wal", "Cybersecurity Platform Architect, The Cybersecurity Center at MSU Denver")], info?.speakers)
    }

    func testMaintainerSummitComesFromScheduleJsonWithoutFetching() async throws {
        let f = FakeFetcher(.failed("must not be called"))
        let r = repo(f)

        // Synchronous: no warm-up needed.
        let talk = try XCTUnwrap(r.peek("m1290687"))
        XCTAssertEqual(DetailInfo.Source.summit, talk.source)
        XCTAssertTrue(try XCTUnwrap(talk.description).isNotBlank)
        XCTAssertTrue(try XCTUnwrap(talk.slidesUrl).hasPrefix("https://sessionize.com/download/"))
        XCTAssertNil(talk.link)
        XCTAssertTrue(talk.speakers.isEmpty)

        // Unconference sessions (Sunday updates): their own description, and no "See and vote" link
        // (the unconference feature went once voting was over). The GitHub discussion is on the Session.
        let unconf = try XCTUnwrap(r.peek("m1318474"))
        XCTAssertTrue(try XCTUnwrap(unconf.description).hasPrefix("containerd has had over 100 times more vulnerability reports"))
        XCTAssertNil(unconf.link)
        XCTAssertNil(unconf.linkText)
        for id in ["m1318479", "m1318483"] {
            let info = try XCTUnwrap(r.peek(id), id)
            XCTAssertNil(info.link, id)
            XCTAssertFalse(try XCTUnwrap(info.description, id).contains("vote on GitHub"), id)
        }

        // A summit break: found, but nothing to describe.
        let coffee = try found(await r.load("m1318416"))
        XCTAssertNil(coffee.description)
        XCTAssertTrue(f.calls.isEmpty)
    }

    func testLiveFetchIsParsedCachedOnDiskAndServedOfflineLater() async throws {
        let f = FakeFetcher(.ok(sampleMd))
        let first = try found(await repo(f).load(missing))
        XCTAssertEqual(DetailInfo.Source.live, first.source)
        XCTAssertEqual(try XCTUnwrap(try TestData.repo.details["1289660"]).speakers, first.speakers)
        XCTAssertEqual([missing], f.calls)
        XCTAssertTrue(isFile(file("\(missing).json")))

        // A new process, offline: the disk cache answers.
        let offline = FakeFetcher(.failed("offline"))
        let second = try found(await repo(offline).load(missing))
        XCTAssertEqual(DetailInfo.Source.diskCache, second.source)
        XCTAssertEqual(first.description, second.description)
        XCTAssertEqual(first.speakers, second.speakers)
        XCTAssertTrue(offline.calls.isEmpty)
    }

    func testFailureIsQuietAndBacksOffInsteadOfStormingRetries() async throws {
        let f = FakeFetcher(.failed("offline"), .failed("offline"), .ok(sampleMd))
        let r = repo(f)
        var res = await r.load(missing)
        XCTAssertEqual(DetailsResult.unavailable, res)
        let got = await r.get(missing)
        XCTAssertNil(got)
        res = await r.load(missing)
        XCTAssertEqual(DetailsResult.unavailable, res)
        XCTAssertEqual(DetailsResult.unavailable, r.peekResult(missing))
        XCTAssertEqual(1, f.calls.count)

        advance(DetailsRepository.FAIL_BACKOFF_MS - 1)
        res = await r.load(missing)
        XCTAssertEqual(DetailsResult.unavailable, res)
        XCTAssertEqual(1, f.calls.count)

        advance(1)
        res = await r.load(missing)
        XCTAssertEqual(DetailsResult.unavailable, res)
        XCTAssertEqual(2, f.calls.count)

        advance(DetailsRepository.FAIL_BACKOFF_MS)
        let okResult = await r.load(missing)
        let ok = try found(okResult)
        XCTAssertEqual(DetailInfo.Source.live, ok.source)
        XCTAssertEqual(3, f.calls.count)
        XCTAssertEqual(okResult, r.peekResult(missing))
    }

    func testConcurrentRequestsShareOneFetch() async {
        let f = FakeFetcher(.ok(sampleMd))
        let r = repo(f)
        let id = missing
        let results = await withTaskGroup(of: DetailsResult.self) { group -> [DetailsResult] in
            for _ in 1...5 { group.addTask { await r.load(id) } }
            var out: [DetailsResult] = []
            for await x in group { out.append(x) }
            return out
        }
        XCTAssertEqual(5, results.count)
        XCTAssertTrue(results.allSatisfy { $0.info != nil })
        XCTAssertEqual(1, f.calls.count)
    }

    func testEmptyAnswersAndNotFoundShowNothingAndAreNotRefetched() async {
        let f = FakeFetcher(.ok(SessionizeSamples.byId["1342434"]!.kotlinReplace("## Description", "## Notes")))
        let r = repo(f)
        // "Closing Remarks": Sessionize has no description and no speakers.
        var res = await r.load("1302802")
        XCTAssertEqual(DetailsResult.nothing, res)
        res = await r.load("1302802")
        XCTAssertEqual(DetailsResult.nothing, res)
        XCTAssertEqual(1, f.calls.count)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file("1302802.json").path))

        let nf = FakeFetcher(.notFound)
        let r2 = repo(nf)
        res = await r2.load("1370500")
        XCTAssertEqual(DetailsResult.nothing, res)
        res = await r2.load("1370500")
        XCTAssertEqual(DetailsResult.nothing, res)
        XCTAssertEqual(1, nf.calls.count)
    }

    func testCoLocatedDetailsAreBundledAndNeverFetchedOrCached() async throws {
        let f = FakeFetcher(.ok(sampleMd))
        let r = repo(f)
        // Jiazhou Gao's Cloud Native AI + Inference Day talk: description and taglines from colocated_details.json.
        let res = try found(await r.load("1245135"))
        XCTAssertEqual(DetailInfo.Source.bundled, res.source)
        XCTAssertTrue(try XCTUnwrap(res.description).hasPrefix("As LLM inference moves from demos to production"))
        XCTAssertEqual(SpeakerTagline("Jiazhou Gao", "Member of Technical Staff at Anthropic"), res.speakers[0])
        // Slides come from the session; a lunch carries its menu.
        let withSlides = try XCTUnwrap(TestData.repo.sessions.first { $0.isColocated && $0.slidesUrl != nil })
        let slides = try found(await r.load(withSlides.id))
        XCTAssertEqual(withSlides.slidesUrl, slides.slidesUrl)
        let lunch = try found(await r.load("1309415"))
        XCTAssertTrue(try XCTUnwrap(lunch.description).contains("Lunch Menu"))
        XCTAssertTrue(f.calls.isEmpty)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(contents.isEmpty, "\(contents)")
    }

    func testACoLocatedSessionWithoutBundledDetailsIsNoneNotFetched() async throws {
        // Their ids are plain digits but belong to another Sessionize event: never ask the main one.
        let details = Repository.COLOCATED_DETAILS
        let original = TestData.text(details)
        let text = original.kotlinReplace("\"1245135\": {", "\"x1245135\": {")
        XCTAssertTrue(text != original)
        let assets = TestData.assetsDir
        let base = try Repository.load { name in
            name == details ? Data(text.utf8) : try Data(contentsOf: assets.appendingPathComponent(name))
        }
        XCTAssertFalse(try base.details.containsKey("1245135"))
        let f = FakeFetcher(.ok(sampleMd))
        let clock = nowMs
        let r = DetailsRepository(base, cacheDir: dir, fetcher: f, elapsedMillis: { clock.value })
        var res = await r.load("1245135")
        XCTAssertEqual(DetailsResult.nothing, res)
        XCTAssertTrue(DetailsRepository.isKubeConId("1245135"))
        XCTAssertTrue(f.calls.isEmpty)
        // A stray cache file for it is ignored too.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{\"description\":\"stale\",\"speakers\":[]}".utf8).write(to: file("1245135.json"))
        res = await DetailsRepository(base, cacheDir: dir, fetcher: f, elapsedMillis: { clock.value }).load("1245135")
        XCTAssertEqual(DetailsResult.nothing, res)
    }

    func testUnknownSessionsAreNoneWithoutAnyFetch() async {
        let f = FakeFetcher(.ok(sampleMd))
        let r = repo(f)
        var res = await r.load("999")
        XCTAssertEqual(DetailsResult.nothing, res)
        res = await r.load("m999")
        XCTAssertEqual(DetailsResult.nothing, res)
        res = await r.load("../../etc/passwd")
        XCTAssertEqual(DetailsResult.nothing, res)
        XCTAssertTrue(f.calls.isEmpty)
    }

    func testCorruptCacheFileIsReplaced() async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: file("\(missing).json"))
        let f = FakeFetcher(.ok(sampleMd))
        let res = try found(await repo(f).load(missing))
        XCTAssertEqual(DetailInfo.Source.live, res.source)
        XCTAssertEqual(1, f.calls.count)
        let again = try found(await repo(FakeFetcher(.failed("offline"))).load(missing))
        XCTAssertEqual(DetailInfo.Source.diskCache, again.source)
    }

    func testAThrowingFetcherNeverCrashes() async {
        let r = repo(ClosureDetailsFetcher { _ in throw Boom(message: "boom") })
        let res = await r.load(missing)
        XCTAssertEqual(DetailsResult.unavailable, res)
    }

    func testOnlyPlainNumericIdsAreFetchable() {
        XCTAssertTrue(DetailsRepository.isKubeConId("1302802"))
        XCTAssertFalse(DetailsRepository.isKubeConId("m1318474"))
        XCTAssertFalse(DetailsRepository.isKubeConId(""))
        XCTAssertFalse(DetailsRepository.isKubeConId("12/../3"))
    }
}
