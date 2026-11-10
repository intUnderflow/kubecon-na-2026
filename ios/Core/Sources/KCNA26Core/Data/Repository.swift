import Foundation

/// A data file that is missing from a directory / the app bundle.
struct DataFileMissingError: Error, CustomStringConvertible {
    let name: String
    let location: String
    var description: String { "\(name) not found in \(location)" }
}

/// All bundled data, parsed once. Immutable and thread-safe (`Sendable`).
///
/// - In the app: loaded once off the main thread at launch (`try Repository.bundled()` inside
///   a `Task.detached`, or through DataSync), then shared.
/// - In unit tests: `TestData.repo`, which uses ``fromDirectory(_:)`` on
///   ios/KCNA26/Resources/Data.
///
/// The core files (schedule, rooms, wayfinding, venue, summit details and colocated.json) are
/// parsed eagerly by ``load(open:)``; the 575 KB details.json and the 220 KB
/// colocated_details.json are read lazily on first access to ``details`` (thread-safe, like
/// Kotlin's `by lazy(SYNCHRONIZED)`; a failure is not cached).
///
/// colocated.json (optional: the app works without it) merges in like this: its sessions follow
/// schedule.json's in ``sessions``; its events are ``coloEvents``; the schedule.json
/// placeholders they replace are ``supersededIds`` (kept, but not shown); its position-less
/// places are ``extraRooms`` (found by ``room(_:)``); its Anthropic speakers join
/// ``anthropicSpeakers``; colocated_details.json (optional too) joins ``details`` for its
/// sessions. All or nothing: a colocated.json that is missing, unreadable or does not convert
/// (a bad date) leaves the rest of the schedule exactly as without it.
///
/// Errors: a missing/unreadable/invalid core file makes ``load(open:)`` throw; the details
/// files throw from ``details`` (colocated_details.json problems are swallowed: no
/// descriptions for those sessions).
final class Repository: Sendable {
    let meta: ScheduleMeta
    /// schedule.json's 614 sessions in file order, then colocated.json's (223). Ids are unique.
    let sessions: [Session]
    /// The five days in order (sun, mon, tue, wed, thu).
    let days: [Day]
    /// Keyed by category key, in file order.
    let categories: OrderedMap<String, Category>
    /// schedule.json "anthropicSpeakers" (includes Lucy Sweet) plus colocated.json's.
    let anthropicSpeakers: Set<String>
    /// rooms.json, keyed by room code, in file order (40).
    let rooms: OrderedMap<String, Room>
    let wayfinding: Wayfinding
    let venue: Venue
    /// maintainer_summit_details.json, keyed by session id (file order).
    let summitDetails: OrderedMap<String, SummitDetail>
    /// colocated.json "events": the CNCF-hosted co-located events, alphabetical.
    let coloEvents: [ColoEvent]
    /// Places only colocated.json uses (FOY meeting-room foyers, LCH4 lunch hall). They have no
    /// position, so they stay out of ``rooms`` (the walking graph's room list); ``room(_:)`` finds them.
    let extraRooms: OrderedMap<String, Room>

    /// Session by id.
    let sessionsById: OrderedMap<String, Session>
    /// Co-located event by key.
    let coloEventsByKey: OrderedMap<String, ColoEvent>
    /// schedule.json's all-day placeholders ("ArgoCon", note "All-Access pass") that an event in
    /// ``coloEvents`` replaces. They stay in ``sessions`` (an old saved id still opens) but the
    /// schedule never lists them.
    let supersededIds: Set<String>
    /// Every distinct speaker name in the schedule, sorted case-insensitively (for the Settings picker).
    let allSpeakers: [String]

    private let detailsLazy: SynchronizedLazy<OrderedMap<String, SessionDetail>, any Error>

    private init(
        meta: ScheduleMeta,
        sessions: [Session],
        days: [Day],
        categories: OrderedMap<String, Category>,
        anthropicSpeakers: Set<String>,
        rooms: OrderedMap<String, Room>,
        wayfinding: Wayfinding,
        venue: Venue,
        summitDetails: OrderedMap<String, SummitDetail>,
        coloEvents: [ColoEvent],
        extraRooms: OrderedMap<String, Room>,
        detailsLoader: @escaping @Sendable () throws -> OrderedMap<String, SessionDetail>
    ) {
        self.meta = meta
        self.sessions = sessions
        self.days = days
        self.categories = categories
        self.anthropicSpeakers = anthropicSpeakers
        self.rooms = rooms
        self.wayfinding = wayfinding
        self.venue = venue
        self.summitDetails = summitDetails
        self.coloEvents = coloEvents
        self.extraRooms = extraRooms
        detailsLazy = SynchronizedLazy(detailsLoader)

        let byId = sessions.associateBy { $0.id }
        sessionsById = byId
        coloEventsByKey = coloEvents.associateBy { $0.key }
        supersededIds = Set(coloEvents.compactMap { e in e.supersedes.flatMap { byId.containsKey($0) ? $0 : nil } })
        allSpeakers = sessions.flatMap(\.speakers).distinct().stableSorted(with: .caseInsensitiveOrder)
    }

    /// details.json plus colocated_details.json (for colocated.json's sessions): session id ->
    /// description + speakers with taglines. Parsed on first access (blocking: call off the main
    /// thread first, e.g. at launch); throws if details.json is missing or invalid (and tries
    /// again on the next access).
    var details: OrderedMap<String, SessionDetail> {
        get throws { try detailsLazy.get() }
    }

    /// True once ``details`` has been parsed (so reading it is free).
    var isDetailsLoaded: Bool { detailsLazy.isInitialized }

    /// The default "I'm speaking as" name from schedule.json ("Lucy Sweet").
    var defaultMe: String { meta.me }

    func session(_ id: String) -> Session? { sessionsById[id] }

    /// A rooms.json room, or one of the co-located ``extraRooms``.
    func room(_ code: String) -> Room? { rooms[code] ?? extraRooms[code] }
    func day(_ key: String) -> Day? { days.first { $0.key == key } }
    func dayOf(_ session: Session) -> Day? { day(session.day) }
    func category(_ key: String) -> Category? { categories[key] }
    func roomOf(_ session: Session) -> Room? { room(session.room) }
    func coloEvent(_ key: String) -> ColoEvent? { coloEventsByKey[key] }

    // MARK: File names

    static let SCHEDULE = "schedule.json"
    static let ROOMS = "rooms.json"
    static let WAYFINDING = "wayfinding.json"
    static let VENUE = "venue.json"
    static let DETAILS = "details.json"
    static let SUMMIT_DETAILS = "maintainer_summit_details.json"
    static let TEST_VECTORS = "test_vectors.json"

    /// Optional: the CNCF-hosted co-located events (scripts/fetch_colocated.py).
    static let COLOCATED = "colocated.json"

    /// Optional: ``COLOCATED``'s descriptions and speaker taglines, a file of their own so start-up doesn't parse them.
    static let COLOCATED_DETAILS = "colocated_details.json"

    /// The app bundle's data folder (Resources/Data, copied as a folder reference named "Data").
    static func bundledDataDirectory(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "Data", withExtension: nil)
    }

    // MARK: Loading

    /// Loads the bundled data set (the app; Kotlin `fromAssets`). Blocking: call off the main thread.
    static func bundled(_ bundle: Bundle = .main) throws -> Repository {
        guard let dir = bundledDataDirectory(in: bundle) else {
            throw DataFileMissingError(name: "Data", location: bundle.bundlePath)
        }
        return try fromDirectory(dir)
    }

    /// Loads from a directory holding the JSON files (unit tests, a downloaded data set).
    static func fromDirectory(_ dir: URL) throws -> Repository {
        try load { name in try Data(contentsOf: dir.appendingPathComponent(name)) }
    }

    /// Loads using `open` to read each file by name (any error = file missing/unreadable).
    /// Blocking. `open` is kept for the lazy details files.
    static func load(open: @escaping @Sendable (String) throws -> Data) throws -> Repository {
        func parse<T: JSONDecodable>(_ name: String, _ type: T.Type) throws -> T {
            try JSON.decode(T.self, from: open(name))
        }

        let sch = try parse(SCHEDULE, ScheduleFileDto.self)
        let roomsDto = try parse(ROOMS, RoomsFileDto.self)
        let way = try parse(WAYFINDING, WayfindingFileDto.self)
        let venueDto = try parse(VENUE, VenueFileDto.self)
        let summitRoot = try JSON.parse(open(SUMMIT_DETAILS))
        guard case .object(let summit) = summitRoot else {
            throw JSONDecodingError.typeMismatch("an object (\(SUMMIT_DETAILS))", summitRoot)
        }
        let colo = colocated(open)

        let days = try sch.days.enumerated().map { i, d in
            Day(key: d.key, date: try LocalDate.parse(d.date), label: d.label, short: d.short, subtitle: d.subtitle, index: i)
        }
        let roomMap = roomsDto.rooms.mapValuesWithKey { k, r in r.toModel(k) }
        let base = try sch.sessions.map { try $0.toModel() }
        var ids = Set(base.map(\.id))
        let dayByDate = days.associateBy { $0.date }

        // All or nothing: a co-located file that doesn't convert leaves the rest of the schedule as it is.
        var coloSessions: [Session] = []
        var coloEvents: [ColoEvent] = []
        do {
            // A co-located id that collides with schedule.json is dropped (the script prefixes these, so none do).
            let xs = try (colo?.sessions ?? []).map { try $0.toModel() }.filter { ids.insert($0.id).inserted }
            let es = try (colo?.events ?? []).compactMap { e -> ColoEvent? in
                let start = try parseOffsetDateTime(e.start)
                guard let day = dayByDate[start.localDate] else { return nil }
                return ColoEvent(
                    key: e.key, name: e.name, day: day.key, mainRoom: e.mainRoom,
                    rooms: e.rooms.ifEmpty { [e.mainRoom] }, start: start,
                    end: try parseOffsetDateTime(e.end), halfDay: e.halfDay, talkCount: e.talkCount,
                    supersedes: e.supersedes, infoUrl: e.infoUrl?.takeIfNotBlank(),
                    pageUrl: e.pageUrl?.takeIfNotBlank(), passNote: e.passNote?.takeIfNotBlank()
                )
            }.distinctBy { $0.key }
            coloSessions = xs
            coloEvents = es
        } catch is DateTimeParseError {
            coloSessions = []
            coloEvents = []
        }
        let coloOk = !coloSessions.isEmpty || !coloEvents.isEmpty

        let summitDetails = try summit
            .filter { k, v in !k.hasPrefix("_") && v.objectValue != nil }
            .mapValuesWithKey { k, v -> SummitDetail in
                do {
                    let d = try SummitDetailDto(json: v)
                    return SummitDetail(description: d.d, slides: d.slides, link: d.link, linkText: d.linkText)
                } catch let e as JSONDecodingError {
                    throw e.prefixed(".\(k)")
                }
            }

        let extraRoomDtos: OrderedMap<String, RoomDto> = coloOk ? (colo?.rooms ?? [:]) : [:]
        let coloSessionsForDetails = coloSessions
        return Repository(
            meta: ScheduleMeta(about: sch.about, timeZone: sch.timeZone, me: sch.me, fieldNotes: sch.fieldNotes),
            sessions: base + coloSessions,
            days: days,
            categories: sch.categories.mapValuesWithKey { k, c in
                Category(key: k, label: c.label, colorLight: c.colorLight, colorDark: c.colorDark)
            },
            anthropicSpeakers: Set(sch.anthropicSpeakers + (coloOk ? (colo?.anthropicSpeakers ?? []) : [])),
            rooms: roomMap,
            wayfinding: way.toModel(),
            venue: try venueDto.toModel(),
            summitDetails: summitDetails,
            coloEvents: coloEvents,
            extraRooms: extraRoomDtos
                .filter { k, _ in !roomMap.containsKey(k) }
                .mapValuesWithKey { k, r in r.toModel(k) },
            detailsLoader: {
                var raw = try JSON.decode(OrderedMap<String, DetailDto>.self, from: open(DETAILS))
                if !coloSessionsForDetails.isEmpty {
                    let coloIds = Set(coloSessionsForDetails.map(\.id))
                    for (id, d) in colocatedDetails(open) where coloIds.contains(id) {
                        raw.putIfAbsent(id, d)
                    }
                }
                return raw.mapValues { d in
                    SessionDetail(description: d.description, speakers: d.speakers.map { SpeakerTagline($0.name, $0.tagline) })
                }
            }
        )
    }

    /// colocated.json, or nil when it is missing or unreadable (any read, parse or decode
    /// error): the rest of the schedule must still load. (Unit tests pin its contents.)
    private static func colocated(_ open: (String) throws -> Data) -> ColocatedFileDto? {
        do {
            return try JSON.decode(ColocatedFileDto.self, from: open(COLOCATED))
        } catch {
            return nil
        }
    }

    /// colocated_details.json's "details", or empty when it is missing or unreadable (no descriptions then).
    private static func colocatedDetails(_ open: (String) throws -> Data) -> OrderedMap<String, DetailDto> {
        do {
            return try JSON.decode(ColocatedDetailsDto.self, from: open(COLOCATED_DETAILS)).details
        } catch {
            return [:]
        }
    }
}

// MARK: - DTO -> model

private extension SessionDto {
    func toModel() throws(DateTimeParseError) -> Session {
        Session(
            id: id,
            event: event,
            day: day,
            start: try parseOffsetDateTime(start),
            end: try end.map { s throws(DateTimeParseError) in try parseOffsetDateTime(s) },
            endIsEstimate: endIsEstimate,
            room: room,
            title: title,
            speakers: speakers,
            note: note,
            category: category,
            group: group.map { SessionGroup($0.key, $0.title) },
            precomputedIsMine: isMine,
            precomputedHasAnthropic: hasAnthropicSpeaker,
            officialUrl: officialUrl,
            description: description,
            slidesUrl: slidesUrl?.takeIfNotBlank(),
            discussionUrl: discussionUrl?.takeIfNotBlank(),
            coloEvent: coloEvent?.takeIfNotBlank(),
            coloEvents: coloEvents.filter(\.isNotBlank),
            format: format?.takeIfNotBlank(),
            level: level?.takeIfNotBlank(),
            sponsored: sponsored,
            topic: topic?.takeIfNotBlank()
        )
    }
}

private extension RoomDto {
    func toModel(_ code: String) -> Room {
        Room(
            code: code, name: name, buildingLabel: buildingLabel, venue: venue, venueCode: venueCode,
            level: level, lat: lat, lng: lng, x: x, y: y, whereText: whereText,
            attachNode: attachNode, finalStep: finalStep
        )
    }
}

private extension WayfindingFileDto {
    func toModel() -> Wayfinding {
        Wayfinding(
            origin: Origin(lat0: origin.lat0, lon0: origin.lon0, metersPerDegLat: origin.metersPerDegLat, metersPerDegLon: origin.metersPerDegLon),
            magneticDeclination: magneticDeclination,
            routing: RoutingRules(
                algorithm: routing.algorithm,
                roomAttach: routing.roomAttach,
                startText: routing.startText,
                lowerConcourseMerge: LowerConcourseMerge(
                    nodes: routing.lowerConcourseMerge.nodes,
                    rule: routing.lowerConcourseMerge.rule,
                    where: routing.lowerConcourseMerge.where
                ),
                distanceSuffix: routing.distanceSuffix,
                summary: routing.summary,
                stepKinds: routing.stepKinds
            ),
            entrances: entrances.mapValuesWithKey { k, e in Entrance(key: k, name: e.name, node: e.node) },
            nodes: nodes.mapValuesWithKey { k, n in WayNode(key: k, name: n.name, x: n.x, y: n.y, level: n.level, building: n.building) },
            edges: edges.map { WayEdge(a: $0.a, b: $0.b, textAB: $0.textAB, textBA: $0.textBA) }
        )
    }
}

/// `List<Double>.pt()`: Kotlin throws IndexOutOfBoundsException for a short list; this throws too.
private func pt(_ xs: [Double]) throws -> PointXY {
    guard xs.count >= 2 else { throw JSONDecodingError("Expected a point [x, y], found \(xs.count) number(s)") }
    return PointXY(xs[0], xs[1])
}

private extension VenueFileDto {
    func toModel() throws -> Venue {
        Venue(
            buildings: try buildings.mapValuesWithKey { k, b in Building(code: k, name: b.name, outline: try b.outline.map(pt)) },
            streets: try streets.map { Street(name: $0.name, from: try pt($0.from), to: try pt($0.to)) },
            zones: zones.map { Zone(name: $0.name, x0: $0.x0, x1: $0.x1, y0: $0.y0, y1: $0.y1) }
        )
    }
}
