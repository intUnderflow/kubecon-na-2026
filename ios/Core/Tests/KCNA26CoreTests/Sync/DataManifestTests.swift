import XCTest
@testable import KCNA26Core

/// iOS-only tests (no Kotlin counterpart) pinning DataManifest's rules, which Kotlin's
/// DataSyncTest only exercises through a few published sets: the same version, name, hash
/// and size rules, the same messages, kotlinx's decoding and encoding.
final class DataManifestTests: XCTestCase {
    private let sha = String(repeating: "a", count: 64)

    func testIsSafeNameAllowsOnlyPlainLowercaseJsonNames() {
        for ok in ["schedule.json", "a.json", "0_a-b.json", "colocated_details.json", "maintainer_summit_details.json"] {
            XCTAssertTrue(DataManifest.isSafeName(ok), ok)
        }
        let bad = [
            "", ".json", "../evil.json", "..\\evil.json", "sub/x.json", "/x.json", "x.json/", "x.json\n", "\nx.json",
            "X.json", "x.JSON", "a.b.json", "-x.json", "_x.json", "x .json", "caf\u{E9}.json", "x.json.bak", "x.json\u{0}",
            "manifest.json", "test_vectors.json",
        ]
        for name in bad {
            XCTAssertFalse(DataManifest.isSafeName(name), name.debugDescription)
        }
    }

    func testProblemsChecksVersionRequiredFilesNamesHashesAndSizes() {
        let e = ManifestEntry(sha256: sha, bytes: 10)
        let m = DataManifest(version: 0, files: [
            "schedule.json": e,
            "../evil.json": e,
            "sub/x.json": e,
            "Rooms.json": e,
            "manifest.json": e,
            "test_vectors.json": e,
            "x.json": ManifestEntry(sha256: sha.uppercased(), bytes: 10),
            "y.json": ManifestEntry(sha256: String(sha.dropLast()), bytes: 10),
            "z.json": ManifestEntry(sha256: sha, bytes: 0),
            "n.json": ManifestEntry(sha256: sha, bytes: -1),
            "big.json": ManifestEntry(sha256: sha, bytes: DataManifest.MAX_FILE_BYTES + 1),
            "max.json": ManifestEntry(sha256: sha, bytes: DataManifest.MAX_FILE_BYTES),
        ])
        XCTAssertEqual([
            "version 0",
            "missing rooms.json",
            "bad file name '../evil.json'",
            "bad file name 'sub/x.json'",
            "bad file name 'Rooms.json'",
            "bad file name 'manifest.json'",
            "bad file name 'test_vectors.json'",
            "x.json: bad sha256",
            "y.json: bad sha256",
            "z.json: bad size 0",
            "n.json: bad size -1",
            "big.json: bad size 8388609",
        ], m.problems(["schedule.json", "rooms.json"]))
        XCTAssertEqual(["version -3"], DataManifest(version: -3).problems())
        XCTAssertEqual([String](), DataManifest(version: 1, files: ["a.json": e]).problems(["a.json"]))
    }

    func testTheTotalSizeIsCappedAndHugeSizesDoNotOverflow() {
        let seven = ManifestEntry(sha256: sha, bytes: 7 * 1024 * 1024)
        let five = DataManifest(version: 2, files: ["a.json": seven, "b.json": seven, "c.json": seven, "d.json": seven, "e.json": seven])
        XCTAssertEqual(["total size 36700160"], five.problems())

        // Kotlin's Long sum wraps around; each entry is already reported, and nothing traps.
        let huge = ManifestEntry(sha256: sha, bytes: Int64.max)
        XCTAssertEqual(
            ["a.json: bad size 9223372036854775807", "b.json: bad size 9223372036854775807"],
            DataManifest(version: 2, files: ["a.json": huge, "b.json": huge]).problems()
        )
    }

    func testParseFollowsTheAppsLenientJsonRules() throws {
        XCTAssertEqual(DataManifest(), try DataManifest.parse(Data("{}".utf8)))
        XCTAssertEqual(DataManifest(), try DataManifest.parse(Data(#"{"version": null, "updatedAt": null, "files": null}"#.utf8)))
        let m = try DataManifest.parse(Data(#"""
            {"version": 3, "extra": [1, 2], "updatedAt": "2026-11-08T21:15:00Z",
             "files": {"a.json": {"sha256": "\#(sha)", "bytes": 5, "more": true}}}
            """#.utf8))
        XCTAssertEqual(DataManifest(version: 3, updatedAt: "2026-11-08T21:15:00Z", files: ["a.json": ManifestEntry(sha256: sha, bytes: 5)]), m)

        for bad in [
            #"{"version": 2.5}"#,
            #"{"version": 3000000000}"#, // Kotlin Int is 32-bit
            #"{"files": {"a.json": {"bytes": 5}}}"#, // sha256 is required
            #"{"files": {"a.json": {"sha256": "x"}}}"#, // bytes too
            #"{"files": []}"#,
            "[1]",
            "{",
            "",
        ] {
            XCTAssertThrowsError(try DataManifest.parse(Data(bad.utf8)), bad)
        }
    }

    func testEncodingLeavesDefaultsOutLikeKotlinx() throws {
        XCTAssertEqual("{}", JSON.encode(DataManifest()))
        let m = DataManifest(version: 7, updatedAt: "2026-11-08T21:15:00Z", files: ["schedule.json": ManifestEntry(sha256: sha, bytes: 364257)])
        let text = JSON.encode(m)
        XCTAssertEqual(#"{"version":7,"updatedAt":"2026-11-08T21:15:00Z","files":{"schedule.json":{"sha256":"\#(sha)","bytes":364257}}}"#, text)
        XCTAssertEqual(m, try DataManifest.parse(Data(text.utf8)))
    }

    func testEqualityIgnoresFileOrderLikeKotlinMaps() {
        let a = ManifestEntry(sha256: sha, bytes: 1)
        let b = ManifestEntry(sha256: sha, bytes: 2)
        XCTAssertEqual(DataManifest(version: 1, files: ["a.json": a, "b.json": b]), DataManifest(version: 1, files: ["b.json": b, "a.json": a]))
        XCTAssertNotEqual(DataManifest(version: 1, files: ["a.json": a]), DataManifest(version: 1, files: ["a.json": b]))
    }

    func testUpdatedInstantAndSha256() {
        XCTAssertEqual(TestData.instant("2026-11-08T21:15:00Z"), DataManifest(updatedAt: "2026-11-08T21:15:00Z").updatedInstant)
        XCTAssertNil(DataManifest().updatedInstant)
        XCTAssertNil(DataManifest(updatedAt: "2026-11-08").updatedInstant)
        XCTAssertEqual("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", DataManifest.sha256(Data("abc".utf8)))
    }

    func testPublishedDataSetValidatesAsAWhole() throws {
        // What installed apps download: data/manifest.json and the files it lists must pass the
        // same checks a downloaded set goes through before a swap.
        let dir = TestData.publishedDataDir
        let manifestFile = dir.appendingPathComponent(DataManifest.FILE)
        guard FileManager.default.fileExists(atPath: manifestFile.path) else { return }
        let m = try DataManifest.parse(Data(contentsOf: manifestFile))
        let bundled = try DataManifest.parse(Data(contentsOf: TestData.assetsDir.appendingPathComponent(DataManifest.FILE)))
        XCTAssertEqual([String](), m.problems(bundled.files.keys))
        for (name, e) in m.files {
            let b = try Data(contentsOf: dir.appendingPathComponent(name))
            XCTAssertEqual(e.bytes, Int64(b.count), name)
            XCTAssertEqual(e.sha256, DataManifest.sha256(b), name)
        }
        let repo = try Repository.fromDirectory(dir)
        XCTAssertEqual([String](), try DataValidator.problems(repo, files: m.files.keys))
    }
}
