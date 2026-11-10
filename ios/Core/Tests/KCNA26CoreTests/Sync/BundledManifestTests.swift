import XCTest
@testable import KCNA26Core

/// Port of sync/BundledManifestTest.kt: the app's Resources/Data/manifest.json must describe
/// the bundled files (run scripts/make_manifest.py after editing data).
final class BundledManifestTests: XCTestCase {
    private let manifest: DataManifest = {
        do {
            return try DataManifest.parse(Data(contentsOf: TestData.assetsDir.appendingPathComponent(DataManifest.FILE)))
        } catch {
            fatalError("bundled manifest: \(error)")
        }
    }()

    func testBundledManifestMatchesTheBundledFiles() throws {
        XCTAssertEqual([String](), manifest.problems())
        for (name, e) in manifest.files {
            let b = try Data(contentsOf: TestData.assetsDir.appendingPathComponent(name))
            XCTAssertEqual(e.bytes, Int64(b.count), "\(name) size (run scripts/make_manifest.py)")
            XCTAssertEqual(e.sha256, DataManifest.sha256(b), "\(name) sha256 (run scripts/make_manifest.py)")
        }
        XCTAssertTrue(manifest.updatedInstant != nil)
    }

    func testManifestCoversEveryFileTheAppLoads() {
        let loaded: Set<String> = [
            Repository.SCHEDULE, Repository.ROOMS, Repository.WAYFINDING, Repository.VENUE, Repository.DETAILS,
            Repository.SUMMIT_DETAILS, Repository.COLOCATED, Repository.COLOCATED_DETAILS,
        ]
        XCTAssertEqual(loaded, Set(manifest.files.keys))
        XCTAssertFalse(manifest.files.containsKey(Repository.TEST_VECTORS))
    }

    func testPublishedManifestIsTheBundledOne() throws {
        let published = TestData.publishedDataDir.appendingPathComponent(DataManifest.FILE)
        guard FileManager.default.fileExists(atPath: published.path) else { return }
        XCTAssertEqual(manifest, try DataManifest.parse(Data(contentsOf: published)))
    }
}
