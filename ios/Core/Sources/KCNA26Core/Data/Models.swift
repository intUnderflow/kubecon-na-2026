import Foundation

/*
 * Domain models for every JSON data file. Built by `Repository` from the DTOs in Dto.swift.
 * All are plain immutable value types, safe to use from any thread and in unit tests.
 *
 * Coordinates: x is metres east, y metres north of the West Temple & 200 South
 * intersection (wayfinding.json "origin"). Levels are the venue's floor numbers
 * (Level 1 = street level at 200 South).
 *
 * Kotlin -> Swift: `Instant` -> `Date`; `LocalDate` -> `LocalDate` (Time/); Kotlin `Map`
 * (file order) -> `OrderedMap`; `Duration` -> seconds (`TimeInterval`).
 */

/// A point in local metres (x east, y north). Shared by rooms, nodes, venue shapes and routes.
struct PointXY: Sendable, Hashable {
    let x: Double
    let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

// MARK: - schedule.json

/// One of the five conference days (schedule.json "days").
struct Day: Sendable, Hashable {
    /// "sun", "mon", "tue", "wed", "thu". Sessions refer to days by this key.
    let key: String
    /// Calendar date in America/Denver.
    let date: LocalDate
    /// "Sunday, Nov 8"
    let label: String
    /// "Sun 8"
    let short: String
    /// One-line description shown under the day heading.
    let subtitle: String
    /// 0..4, position in `Repository.days`.
    let index: Int

    /// "Sun", "Mon", ... (the web's `dow`): `short` before the first space.
    var dow: String { short.substringBefore(" ") }

    /// 8, 9, ... (the web's `num`).
    var num: Int { date.dayOfMonth }
}

/// A session category (schedule.json "categories"); colours are "#RRGGBB".
struct Category: Sendable, Hashable {
    /// "key", "talk", "mnt", "hands", "show", "com", "soc", "colo", "log".
    let key: String
    /// "Keynote", "Talk", ...; "Break" for log. The web shows no label for log rows.
    let label: String
    let colorLight: String
    let colorDark: String

    /// 0xFFRRGGBB (see ``parseHexColor(_:)``). Throws on a malformed colour (Kotlin throws too).
    var lightArgb: UInt32 { get throws { try parseHexColor(colorLight) } }
    var darkArgb: UInt32 { get throws { try parseHexColor(colorDark) } }

    /// The colour for a theme (Kotlin `Category.color(dark)`, minus the Compose `Color`).
    func argb(dark: Bool) throws -> UInt32 { try dark ? darkArgb : lightArgb }
}

/// Back-to-back sessions in one room, shown as one expandable card titled `title`.
struct SessionGroup: Sendable, Hashable {
    let key: String
    let title: String

    init(_ key: String, _ title: String) {
        self.key = key
        self.title = title
    }

    init(key: String, title: String) {
        self.key = key
        self.title = title
    }
}

/// One session: schedule.json "sessions" (614, file order), then colocated.json's (223: the
/// CNCF-hosted co-located events' talks and breaks, and their Evening Reception).
///
/// Read schedule.json "fieldNotes": `end` is nil when the agenda gives no end (treat as 90
/// minutes for "finished" logic, see ``effectiveEnd``); `endIsEstimate` means show durations
/// with "~"; category "log" rows are quiet break rows.
struct Session: Sendable, Hashable {
    /// Sessionize id. Maintainer Summit ids start with "m".
    let id: String
    /// "kubecon", "maintainer-summit" or "colocated" (``EVENT_COLOCATED``).
    let event: String
    /// Day key, see ``Day/key``.
    let day: String
    let start: Date
    /// Nil when the agenda gives no end time (one session).
    let end: Date?
    let endIsEstimate: Bool
    /// Room code, a key of `Repository.rooms` (e.g. "251AC", "OFF").
    let room: String
    let title: String
    /// Speaker names in agenda order; may be empty.
    let speakers: [String]
    /// "Sold out", "All-Access pass", "Main Track", "Keynote", ...; nil if none.
    let note: String?
    /// Category key, see ``Category/key``.
    let category: String
    let group: SessionGroup?
    /// Precomputed for "Lucy Sweet". Do NOT use: call ``isMine(_:_:)`` with the current setting.
    let precomputedIsMine: Bool
    /// Precomputed. Do NOT use: call `hasAnthropic`.
    let precomputedHasAnthropic: Bool
    /// Official agenda page for this session.
    let officialUrl: String
    /// Only Maintainer Summit sessions carry one (KubeCon descriptions are in details.json).
    let description: String?
    /// Only on two Maintainer Summit sessions.
    let slidesUrl: String?
    /// Unconference sessions: the GitHub discussion with the topic's proposal and replies; nil if none.
    let discussionUrl: String?
    /// Co-located only: the ``ColoEvent/key`` of the one event this talk (or single-event break) belongs to.
    let coloEvent: String?
    /// Co-located only: every event whose agenda lists this session (talk: its event; break: each event it serves).
    let coloEvents: [String]
    /// Co-located talks: "Breakout", "Panel", "Lightning talk" or "Keynote"; nil if none.
    let format: String?
    /// Co-located talks: "Any level", "Beginner", "Intermediate" or "Advanced"; nil if none.
    let level: String?
    /// Co-located talks: a sponsored (keynote) slot.
    let sponsored: Bool
    /// Co-located talks: the topic within its event ("Progressive Delivery"); nil if none.
    let topic: String?

    init(
        id: String,
        event: String,
        day: String,
        start: Date,
        end: Date?,
        endIsEstimate: Bool,
        room: String,
        title: String,
        speakers: [String],
        note: String?,
        category: String,
        group: SessionGroup?,
        precomputedIsMine: Bool,
        precomputedHasAnthropic: Bool,
        officialUrl: String,
        description: String?,
        slidesUrl: String?,
        discussionUrl: String? = nil,
        coloEvent: String? = nil,
        coloEvents: [String] = [],
        format: String? = nil,
        level: String? = nil,
        sponsored: Bool = false,
        topic: String? = nil
    ) {
        self.id = id
        self.event = event
        self.day = day
        self.start = start
        self.end = end
        self.endIsEstimate = endIsEstimate
        self.room = room
        self.title = title
        self.speakers = speakers
        self.note = note
        self.category = category
        self.group = group
        self.precomputedIsMine = precomputedIsMine
        self.precomputedHasAnthropic = precomputedHasAnthropic
        self.officialUrl = officialUrl
        self.description = description
        self.slidesUrl = slidesUrl
        self.discussionUrl = discussionUrl
        self.coloEvent = coloEvent
        self.coloEvents = coloEvents
        self.format = format
        self.level = level
        self.sponsored = sponsored
        self.topic = topic
    }

    var isMaintainerSummit: Bool { event == "maintainer-summit" }

    /// From colocated.json (CNCF-hosted co-located events, Monday). Their details are bundled: never fetched live.
    var isColocated: Bool { event == Session.EVENT_COLOCATED }

    /// `end`, or start + 90 min when the agenda has none. Use for "finished" and "live" logic.
    var effectiveEnd: Date { end ?? start.addingTimeInterval(Session.OPEN_ENDED) }

    /// Start in America/Denver (Kotlin `startLocal`, a ZonedDateTime).
    var startLocal: LocalDateTime { start.localDateTime }
    var endLocal: LocalDateTime? { end?.localDateTime }

    /// How long an open-ended session (`end` == nil) counts as lasting: 90 minutes, in seconds
    /// (Kotlin `Duration.ofMinutes(90)`).
    static let OPEN_ENDED: TimeInterval = 90 * 60

    /// `event` of colocated.json sessions.
    static let EVENT_COLOCATED = "colocated"
}

/// A CNCF-hosted co-located event (colocated.json "events"), shown on its day as one card
/// with its agenda: the sessions whose ``Session/coloEvents`` contain `key`. Alphabetical.
struct ColoEvent: Sendable, Hashable {
    /// "colo-argocon": also the group key of its talks.
    let key: String
    /// "ArgoCon", "Cloud Native AI + Inference Day", …
    let name: String
    /// Day key ("mon") of `start`.
    let day: String
    /// The room with the most talks (a rooms.json code).
    let mainRoom: String
    /// Every room with talks, `mainRoom` first.
    let rooms: [String]
    /// First talk's start.
    let start: Date
    /// Last talk's end: the card disappears then (agenda breaks may run later).
    let end: Date
    let halfDay: Bool
    let talkCount: Int
    /// schedule.json's all-day placeholder session for this event (hidden: the card replaces it).
    let supersedes: String?
    /// That placeholder's official listing.
    let infoUrl: String?
    /// The event's own LF page.
    let pageUrl: String?
    /// "All-Access pass" (the placeholder's note).
    let passNote: String?
}

/// schedule.json top-level fields other than the lists.
struct ScheduleMeta: Sendable, Hashable {
    let about: String
    /// "America/Denver"
    let timeZone: String
    /// The default "I'm speaking as" name ("Lucy Sweet").
    let me: String
    /// schedule.json "fieldNotes", verbatim (file order).
    let fieldNotes: OrderedMap<String, String>
}

// MARK: - rooms.json

/// A room (rooms.json "rooms"), keyed by its code. 40 rooms, in file order (which is also the
/// web version's room sort order). colocated.json adds two position-less places (FOY, LCH4:
/// `Repository.extraRooms`).
///
/// OFF ("Off-site") only has `name`; every other field is nil for it, and ``hasPosition`` is
/// false. HL (Hyatt lobby) has a position but a nil `buildingLabel`. REG and COAT exist here
/// but no session uses them.
struct Room: Sendable, Hashable {
    let code: String
    /// "251 A–C", "Grand Ballroom GI", "Off-site", ...
    let name: String
    /// "Salt Palace L2", "Hyatt L4", "Showcase floor"; nil for HL and OFF.
    let buildingLabel: String?
    /// "Salt Palace Convention Center" / "Hyatt Regency Salt Lake City".
    let venue: String?
    /// "SP" (Salt Palace) or "HY" (Hyatt).
    let venueCode: String?
    let level: Int?
    let lat: Double?
    let lng: Double?
    let x: Double?
    let y: Double?
    /// A sentence describing where the room is.
    let whereText: String?
    /// Wayfinding node the room opens off (`Wayfinding.nodes` key).
    let attachNode: String?
    /// Last walking step to reach the room.
    let finalStep: String?

    var hasPosition: Bool { x != nil && y != nil && lat != nil && lng != nil && level != nil }

    /// Local metres, or nil for OFF.
    var pos: PointXY? {
        guard let x, let y else { return nil }
        return PointXY(x, y)
    }
}

// MARK: - wayfinding.json

/// Flat-earth conversion constants: x = (lng - lon0) * metersPerDegLon; y = (lat - lat0) * metersPerDegLat.
struct Origin: Sendable, Hashable {
    let lat0: Double
    let lon0: Double
    let metersPerDegLat: Double
    let metersPerDegLon: Double
}

/// Walking-graph node. `building` is "SP" or "HY".
struct WayNode: Sendable, Hashable {
    let key: String
    let name: String
    let x: Double
    let y: Double
    let level: Int
    let building: String

    var pos: PointXY { PointXY(x, y) }
}

/// Undirected corridor; `textAB` is the instruction walking a→b, `textBA` walking b→a.
struct WayEdge: Sendable, Hashable {
    let a: String
    let b: String
    let textAB: String
    let textBA: String
}

/// A building entrance usable as a "From" start. Keys: E200S, EWT, EHY, E200W (in that order).
struct Entrance: Sendable, Hashable {
    let key: String
    let name: String
    let node: String
}

/// wayfinding.json "routing.lowerConcourseMerge".
struct LowerConcourseMerge: Sendable, Hashable {
    /// S200, LCS, LCM, NF
    let nodes: [String]
    let rule: String
    /// node key -> "{where}" phrase
    let `where`: OrderedMap<String, String>
}

/// wayfinding.json "routing": the rules the router must follow, verbatim.
struct RoutingRules: Sendable, Hashable {
    let algorithm: String
    let roomAttach: String
    let startText: String
    let lowerConcourseMerge: LowerConcourseMerge
    let distanceSuffix: String
    let summary: String
    let stepKinds: String
}

struct Wayfinding: Sendable, Hashable {
    let origin: Origin
    /// Prose note about magnetic declination (iOS: `CLHeading.trueHeading` already includes it).
    let magneticDeclination: String
    let routing: RoutingRules
    /// Ordered as in the file: E200S, EWT, EHY, E200W.
    let entrances: OrderedMap<String, Entrance>
    /// Ordered as in the file.
    let nodes: OrderedMap<String, WayNode>
    /// In file order (the router's adjacency order depends on it).
    let edges: [WayEdge]
}

// MARK: - venue.json

/// Building outline polygon in local metres. `code` is "SP" or "HY".
struct Building: Sendable, Hashable {
    let code: String
    let name: String
    let outline: [PointXY]
}

struct Street: Sendable, Hashable {
    let name: String
    let from: PointXY
    let to: PointXY
}

/// Axis-aligned hall zone rectangle in local metres.
struct Zone: Sendable, Hashable {
    let name: String
    let x0: Double
    let x1: Double
    let y0: Double
    let y1: Double
}

/// Shapes for the small north-up map. The web draws a 512×510 viewBox with
/// svgX = x + 492, svgY = 492 − y.
struct Venue: Sendable, Hashable {
    let buildings: OrderedMap<String, Building>
    let streets: [Street]
    let zones: [Zone]
}

// MARK: - details.json, maintainer_summit_details.json

struct SpeakerTagline: Sendable, Hashable {
    let name: String
    let tagline: String

    init(_ name: String, _ tagline: String) {
        self.name = name
        self.tagline = tagline
    }

    init(name: String, tagline: String) {
        self.name = name
        self.tagline = tagline
    }
}

/// details.json entry: full KubeCon description and speakers with taglines (558 of 579 KubeCon sessions).
struct SessionDetail: Sendable, Hashable {
    let description: String
    let speakers: [SpeakerTagline]
}

/// maintainer_summit_details.json entry, keyed by session id (its content is already merged
/// into schedule.json descriptions/slides). `link`/`linkText` are an optional extra link for
/// the details (opened in the browser); no entry has one at present.
struct SummitDetail: Sendable, Hashable {
    let description: String
    let slides: String?
    let link: String?
    let linkText: String?
}

// MARK: - helpers

/// A malformed colour string.
struct HexColorError: Error, CustomStringConvertible, Equatable {
    let hex: String
    var description: String { "Bad colour \(hex)" }
}

/// Parses "#RRGGBB" (or "#AARRGGBB") to 0xAARRGGBB with full alpha by default.
///
/// Returns the colour as a `UInt32` (the same bit pattern as Kotlin's `Int` result, which is
/// negative for opaque colours: Kotlin `0xFFC2255B.toInt()` == `Int32(bitPattern: 0xFFC2255B)`).
/// Throws like Kotlin for anything that is not 6 or 8 hex digits after an optional "#"
/// (Kotlin's `toLong(16)` also accepts a leading sign; so does this).
func parseHexColor(_ hex: String) throws -> UInt32 {
    let h = hex.removePrefix("#")
    guard let v = Int64(h, radix: 16) else { throw HexColorError(hex: hex) }
    switch h.utf16.count {
    case 6: return UInt32(truncatingIfNeeded: 0xFF00_0000 | v)
    case 8: return UInt32(truncatingIfNeeded: v)
    default: throw HexColorError(hex: hex)
    }
}
