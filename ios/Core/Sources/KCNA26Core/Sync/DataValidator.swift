import Foundation

/// Cross-file sanity checks for a whole data set, run before a downloaded set replaces the
/// current one (and again when a downloaded set is loaded at start). Parsing with the app's own
/// DTOs already happened in ``Repository/load(open:)``; this catches sets that parse but don't
/// fit together, such as a session in a room that rooms.json doesn't have, or that would break a
/// screen: duplicate keys in a lazy list (SwiftUI `ForEach` ids, Compose throws on Android), an
/// empty building outline (the map takes its min/max), no entrances (Directions falls back to
/// the first one).
enum DataValidator {

    /// Everything wrong with `repo` (empty = usable). With `includeDetails` it also parses
    /// details.json (575 KB) and colocated_details.json, which a check before a swap wants and
    /// app start doesn't (and throws if details.json can't be read, as Kotlin's `repo.details`
    /// does). `files`: the set's file names (its manifest). The co-located files are optional to
    /// ``Repository/load(open:)``, which quietly drops one that doesn't convert; a set that ships
    /// them must actually deliver their events and descriptions.
    static func problems(_ repo: Repository, includeDetails: Bool = true, files: [String] = []) throws -> [String] {
        var out: [String] = []
        func check(_ ok: Bool, _ what: @autoclosure () -> String) {
            if !ok && out.count < MAX_REPORTED { out.append(what()) }
        }

        check(!repo.sessions.isEmpty, "no sessions")
        check(!repo.days.isEmpty, "no days")
        check(!repo.rooms.isEmpty, "no rooms")
        check(repo.sessionsById.count == repo.sessions.count, "duplicate session ids")
        let dayKeys = Set(repo.days.map(\.key))
        check(dayKeys.count == repo.days.count, "duplicate day keys") // list keys "q-<day>", "slot-<day>-…"
        for s in repo.sessions {
            check(dayKeys.contains(s.day), "session \(s.id): unknown day '\(s.day)'")
            // repo.room: co-located talks and breaks may be in colocated.json's own places (foyers, lunch hall).
            check(repo.room(s.room) != nil, "session \(s.id): unknown room '\(s.room)'")
            check(repo.categories.containsKey(s.category), "session \(s.id): unknown category '\(s.category)'")
            for k in [s.coloEvent].compactMap({ $0 }) + s.coloEvents {
                check(repo.coloEvent(k) != nil, "session \(s.id): unknown co-located event '\(k)'")
            }
        }

        // Co-located events (colocated.json): one card each, keyed "colo-<key>" in the list.
        if files.contains(Repository.COLOCATED) { check(!repo.coloEvents.isEmpty, "colocated.json: no usable events") }
        for e in repo.coloEvents {
            check(repo.room(e.mainRoom) != nil, "co-located event \(e.key): unknown room '\(e.mainRoom)'")
            check(e.end > e.start, "co-located event \(e.key): ends before it starts")
            check(
                repo.sessions.contains { s in s.coloEvent == e.key || s.coloEvents.contains(e.key) },
                "co-located event \(e.key): no talks"
            )
        }

        let way = repo.wayfinding
        check(!way.nodes.isEmpty, "no wayfinding nodes")
        for r in repo.rooms.values {
            if let n = r.attachNode { check(way.nodes.containsKey(n), "room \(r.code): unknown node '\(n)'") }
        }
        for e in way.edges {
            check(way.nodes.containsKey(e.a) && way.nodes.containsKey(e.b), "edge \(e.a)–\(e.b): unknown node")
        }
        for e in way.entrances.values {
            check(way.nodes.containsKey(e.node), "entrance \(e.key): unknown node '\(e.node)'")
        }
        for n in way.routing.lowerConcourseMerge.nodes {
            check(way.nodes.containsKey(n), "lowerConcourseMerge: unknown node '\(n)'")
        }
        for n in way.nodes.values {
            check(repo.venue.buildings.containsKey(n.building), "node \(n.key): unknown building '\(n.building)'")
        }
        check(!way.entrances.isEmpty, "no entrances")
        for b in repo.venue.buildings.values {
            check(b.outline.count >= 3, "building \(b.code): outline has \(b.outline.count) points")
        }

        if includeDetails {
            let details = try repo.details
            check(!details.isEmpty, "details.json is empty")
            if files.contains(Repository.COLOCATED_DETAILS) && !repo.coloEvents.isEmpty {
                check(
                    repo.sessions.contains { $0.isColocated && details.containsKey($0.id) },
                    "colocated_details.json: no descriptions"
                )
            }
        }
        return out
    }

    private static let MAX_REPORTED = 20
}
