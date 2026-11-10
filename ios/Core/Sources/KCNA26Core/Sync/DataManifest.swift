import Foundation

/// data/manifest.json (written by scripts/make_manifest.py). The app bundles one in its
/// resources (Resources/Data/manifest.json), and the published copy on GitHub says which data
/// set is newest:
///
/// ```
/// {"version": 7, "updatedAt": "2026-11-08T21:15:00Z",
///  "files": {"schedule.json": {"sha256": "…", "bytes": 364257}, …}}
/// ```
///
/// Decoded with the app's lenient kotlinx rules (``JSON/decode(_:from:)``): every field has a
/// default, unknown keys are ignored. `==` ignores the order of ``files`` (Kotlin `Map` equality).
struct DataManifest: Sendable, Hashable, JSONDecodable, JSONEncodable {
    /// Goes up by one whenever any file changes. 0 means "unknown" (no manifest).
    let version: Int
    /// ISO-8601 instant, e.g. "2026-11-08T21:15:00Z".
    let updatedAt: String
    /// File name -> hash and size, in file order.
    let files: OrderedMap<String, ManifestEntry>

    init(version: Int = 0, updatedAt: String = "", files: OrderedMap<String, ManifestEntry> = [:]) {
        self.version = version
        self.updatedAt = updatedAt
        self.files = files
    }

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "DataManifest")
        version = try o.value("version", default: 0)
        updatedAt = try o.value("updatedAt", default: "")
        files = try o.value("files", default: [:])
    }

    /// kotlinx `encodeToString` (default `encodeDefaults = false`: fields equal to their
    /// default are left out).
    func toJSON() -> JSONValue {
        var o = JSONObjectBuilder()
        o.put("version", version, unlessEqualTo: 0)
        o.put("updatedAt", updatedAt, unlessEqualTo: "")
        if !files.isEmpty { o.put("files", files) }
        return o.value
    }

    /// ``updatedAt`` as an instant (`Instant.parse`), or nil if it isn't one.
    var updatedInstant: Date? { try? parseInstant(updatedAt) }

    /// Why this manifest can't describe a usable data set (empty = fine). `required`: file
    /// names it must list; DataSync passes the bundled manifest's, which make_manifest.py writes
    /// from the same data/ folder the app's resources come from (so there is no list to keep in
    /// step here).
    func problems(_ required: [String] = []) -> [String] {
        var out: [String] = []
        if version < 1 { out.append("version \(version)") }
        for name in required where !files.containsKey(name) { out.append("missing \(name)") }
        var total: Int64 = 0
        for (name, e) in files {
            if !DataManifest.isSafeName(name) { out.append("bad file name '\(name)'") }
            if !DataManifest.SHA256_HEX.matches(e.sha256) { out.append("\(name): bad sha256") }
            if !(1...DataManifest.MAX_FILE_BYTES).contains(e.bytes) { out.append("\(name): bad size \(e.bytes)") }
            total &+= e.bytes // Kotlin Long addition wraps (each oversized entry is already reported)
        }
        if total > DataManifest.MAX_TOTAL_BYTES { out.append("total size \(total)") }
        return out
    }

    static let FILE = "manifest.json"

    static let MAX_FILE_BYTES: Int64 = 8 * 1024 * 1024
    static let MAX_TOTAL_BYTES: Int64 = 32 * 1024 * 1024

    private static let SHA256_HEX = KRegex("^[0-9a-f]{64}$")
    private static let SAFE_NAME = KRegex("^[a-z0-9][a-z0-9_-]*\\.json$")

    /// A plain "name.json": no paths, never the manifest or the test vectors.
    static func isSafeName(_ name: String) -> Bool {
        SAFE_NAME.matches(name) && name != FILE && name != Repository.TEST_VECTORS
    }

    /// Parses manifest bytes (UTF-8 JSON); throws ``JSONParseError`` / ``JSONDecodingError``.
    static func parse(_ bytes: Data) throws -> DataManifest {
        try JSON.decode(DataManifest.self, from: bytes)
    }

    /// Lowercase hex SHA-256 of `bytes`.
    static func sha256(_ bytes: Data) -> String { SHA256.hex(bytes) }
}

/// One file of a ``DataManifest``.
struct ManifestEntry: Sendable, Hashable, JSONDecodable, JSONEncodable {
    let sha256: String
    let bytes: Int64

    init(sha256: String, bytes: Int64) {
        self.sha256 = sha256
        self.bytes = bytes
    }

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "ManifestEntry")
        sha256 = try o.required("sha256")
        bytes = try o.required("bytes")
    }

    func toJSON() -> JSONValue {
        var o = JSONObjectBuilder()
        o.put("sha256", sha256)
        o.put("bytes", bytes)
        return o.value
    }
}
