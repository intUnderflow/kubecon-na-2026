import Foundation
@testable import KCNA26Core

/// Shared test fixtures (owner: foundation; Kotlin TestData.kt). Paths are found from this
/// file's location, so tests work from any working directory.
///
/// ```swift
/// let repo = TestData.repo                                   // parsed once per test process
/// let clock = TestData.clockAt("2026-11-11T09:00:00-07:00")  // FixedClock
/// let t = TestData.instant("2026-11-09T09:10:00-07:00")      // Date
/// let routes = TestData.vectors.routes                       // test_vectors.json, typed
/// ```
enum TestData {
    /// The repository root (…/kubecon-na-2026).
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // KCNA26CoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Core
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repo root

    /// The app's bundled data: ios/KCNA26/Resources/Data (Kotlin `TestData.assetsDir`).
    static let dataDir: URL = repoRoot.appendingPathComponent("ios/KCNA26/Resources/Data", isDirectory: true)

    /// Kotlin's name for ``dataDir`` (`File(TestData.assetsDir, name)` -> `TestData.assetsDir.appendingPathComponent(name)`).
    static var assetsDir: URL { dataDir }

    /// The published data folder (<repo>/data), which also holds test_vectors.json.
    static let publishedDataDir: URL = repoRoot.appendingPathComponent("data", isDirectory: true)

    /// The Android app's assets (parity checks).
    static let androidAssetsDir: URL = repoRoot.appendingPathComponent("android/app/src/main/assets", isDirectory: true)

    /// The Android unit tests' package folder (…/src/test/java/app/kcna26), e.g. for the router
    /// golden files under route/golden/.
    static let androidTestDir: URL = repoRoot.appendingPathComponent("android/app/src/test/java/app/kcna26", isDirectory: true)

    /// The real Repository, loaded from ``dataDir`` (once per test process).
    static let repo: Repository = {
        do {
            return try Repository.fromDirectory(dataDir)
        } catch {
            fatalError("TestData.repo: can't load \(dataDir.path): \(error)")
        }
    }()

    /// test_vectors.json (from ``publishedDataDir``: the iOS bundle does not ship it), typed.
    static let vectors: TestVectors = {
        do {
            return try JSON.decode(TestVectors.self, from: data(Repository.TEST_VECTORS))
        } catch {
            fatalError("TestData.vectors: \(error)")
        }
    }()

    /// The URL of a data file: ``dataDir``, or ``publishedDataDir`` for files the app doesn't
    /// bundle (test_vectors.json).
    static func url(_ name: String) -> URL {
        let bundled = dataDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return publishedDataDir.appendingPathComponent(name)
    }

    /// Raw bytes of a data file, e.g. `TestData.data("wayfinding.json")`.
    static func data(_ name: String) -> Data {
        do {
            return try Data(contentsOf: url(name))
        } catch {
            fatalError("TestData.data(\(name)): \(error)")
        }
    }

    /// Raw text of a data file (Kotlin `TestData.text`), e.g. `TestData.text("wayfinding.json")`.
    static func text(_ name: String) -> String {
        String(decoding: data(name), as: UTF8.self)
    }

    /// Parsed JSON of a data file.
    static func json(_ name: String) -> JSONValue {
        do {
            return try JSON.parse(data(name))
        } catch {
            fatalError("TestData.json(\(name)): \(error)")
        }
    }

    /// How many sessions schedule.json holds, read from the file itself so the tests keep passing
    /// when a data update adds or removes sessions (Kotlin `TestData.scheduleCount`).
    static let scheduleCount: Int = {
        guard let sessions = json(Repository.SCHEDULE)["sessions"]?.arrayValue else {
            fatalError("TestData.scheduleCount: schedule.json has no sessions array")
        }
        return sessions.count
    }()

    /// How many entries details.json holds (Kotlin `TestData.detailsCount`).
    static let detailsCount: Int = {
        guard let details = json(Repository.DETAILS).objectValue else {
            fatalError("TestData.detailsCount: details.json is not an object")
        }
        return details.count
    }()

    /// A clock frozen at an ISO time ("2026-11-11T09:00:00-07:00", Denver local
    /// "2026-11-11T09:00", or "…Z"). Traps on a malformed time (a test bug).
    static func clockAt(_ iso: String) -> FixedClock {
        FixedClock(instant(iso))
    }

    /// `OffsetDateTime.parse(iso).toInstant()` (or any form ``parseFakeNow(_:)`` takes).
    /// Traps on a malformed time (a test bug).
    static func instant(_ iso: String) -> Date {
        do {
            return try parseFakeNow(iso)
        } catch {
            fatalError("TestData.instant: \(error)")
        }
    }

    /// Lines of a text file, e.g. a golden file under ``androidTestDir``.
    static func lines(_ url: URL) -> [String] {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { fatalError("TestData.lines: can't read \(url.path)") }
        return s.components(separatedBy: "\n")
    }

    /// CRC-32 (java.util.zip.CRC32) of `bytes`, as Kotlin's `"%08x".format(crc.value)`.
    static func crc32Hex(_ bytes: [UInt8]) -> String {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            c ^= UInt32(b)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
        }
        let v = c ^ 0xFFFF_FFFF
        return String(v, radix: 16).padStart(8, "0")
    }

    /// CRC-32 of a string's UTF-8 bytes.
    static func crc32Hex(_ s: String) -> String { crc32Hex(Array(s.utf8)) }
}

/// test_vectors.json. Distances ±3 m, bearings ±2°.
struct TestVectors: JSONDecodable {
    let about: String
    let compass: [CompassVector]
    let arrowRotation: [ArrowVector]
    let trueHeading: String
    let routes: [RouteVector]

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "TestVectors")
        about = try o.value("_about", default: "")
        compass = try o.value("compass", default: [])
        arrowRotation = try o.value("arrowRotation", default: [])
        trueHeading = try o.value("trueHeading", default: "")
        routes = try o.value("routes", default: [])
    }
}

struct CompassVector: JSONDecodable {
    let `where`: String
    let lat: Double
    let lng: Double
    let room: String
    let roomLevel: Int
    let expectDistanceM: Double
    let expectBearingTrueDeg: Double
    let myLocationStart: StartVector

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "CompassVector")
        `where` = try o.required("where")
        lat = try o.required("lat")
        lng = try o.required("lng")
        room = try o.required("room")
        roomLevel = try o.required("roomLevel")
        expectDistanceM = try o.required("expectDistanceM")
        expectBearingTrueDeg = try o.required("expectBearingTrueDeg")
        myLocationStart = try o.required("myLocationStart")
    }
}

/// mode "inside" (node) or "outside" (entrance, node, distanceM, bearingDeg).
struct StartVector: JSONDecodable {
    let mode: String
    let node: String
    let entrance: String?
    let distanceM: Double?
    let bearingDeg: Double?

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "StartVector")
        mode = try o.required("mode")
        node = try o.required("node")
        entrance = try o.optional("entrance")
        distanceM = try o.optional("distanceM")
        bearingDeg = try o.optional("bearingDeg")
    }
}

struct ArrowVector: JSONDecodable {
    let trueHeadingDeg: Double
    let bearingDeg: Double
    let arrowDeg: Double
    let note: String?

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "ArrowVector")
        trueHeadingDeg = try o.required("trueHeadingDeg")
        bearingDeg = try o.required("bearingDeg")
        arrowDeg = try o.required("arrowDeg")
        note = try o.optional("note")
    }
}

/// from: entrance key or room code; to: room code.
struct RouteVector: JSONDecodable {
    let from: String
    let to: String
    let steps: [StepVector]
    let totalM: Double
    let levelsChanged: Int

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "RouteVector")
        from = try o.required("from")
        to = try o.required("to")
        steps = try o.required("steps")
        totalM = try o.required("totalM")
        levelsChanged = try o.required("levelsChanged")
    }
}

/// kind: "start", "walk", "up", "down", "end" (StepKind.wire).
struct StepVector: JSONDecodable {
    let kind: String
    let text: String

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "StepVector")
        kind = try o.required("kind")
        text = try o.required("text")
    }
}
