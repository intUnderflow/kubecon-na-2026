import Foundation

/*
 * Wire-format mirrors of the data JSON files (Kotlin Dto.kt). Everything else uses the domain
 * models in Models.swift. Decoding follows the kotlinx config (JSONDecoding.swift): unknown
 * keys are ignored and missing (or null) fields fall back to the defaults below (rooms.json
 * OFF has only name/buildingLabel); a missing required field or a wrong type throws.
 */

struct ScheduleFileDto: JSONDecodable {
    let about: String
    let timeZone: String
    let me: String
    let anthropicSpeakers: [String]
    let days: [DayDto]
    let categories: OrderedMap<String, CategoryDto>
    let fieldNotes: OrderedMap<String, String>
    let sessions: [SessionDto]

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "ScheduleFileDto")
        about = try o.value("_about", default: "")
        timeZone = try o.value("timeZone", default: "America/Denver")
        me = try o.value("me", default: "Lucy Sweet")
        anthropicSpeakers = try o.value("anthropicSpeakers", default: [])
        days = try o.value("days", default: [])
        categories = try o.value("categories", default: [:])
        fieldNotes = try o.value("fieldNotes", default: [:])
        sessions = try o.value("sessions", default: [])
    }
}

struct DayDto: JSONDecodable {
    let key: String
    let date: String
    let label: String
    let short: String
    let subtitle: String

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "DayDto")
        key = try o.required("key")
        date = try o.required("date")
        label = try o.required("label")
        short = try o.required("short")
        subtitle = try o.value("subtitle", default: "")
    }
}

struct CategoryDto: JSONDecodable {
    let label: String
    let colorLight: String
    let colorDark: String

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "CategoryDto")
        label = try o.required("label")
        colorLight = try o.required("colorLight")
        colorDark = try o.required("colorDark")
    }
}

struct GroupDto: JSONDecodable {
    let key: String
    let title: String

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "GroupDto")
        key = try o.required("key")
        title = try o.required("title")
    }
}

struct SessionDto: JSONDecodable {
    let id: String
    let event: String
    let day: String
    let start: String
    let end: String?
    let endIsEstimate: Bool
    let room: String
    let title: String
    let speakers: [String]
    let note: String?
    let category: String
    let group: GroupDto?
    let isMine: Bool
    let hasAnthropicSpeaker: Bool
    let officialUrl: String
    let description: String?
    let slidesUrl: String?
    /// Optional (unconference sessions): the GitHub discussion with the proposal and replies.
    let discussionUrl: String?
    // colocated.json only (all optional): see its fieldNotes.
    let coloEvent: String?
    let coloEvents: [String]
    let format: String?
    let level: String?
    let sponsored: Bool
    let topic: String?

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "SessionDto")
        id = try o.required("id")
        event = try o.required("event")
        day = try o.required("day")
        start = try o.required("start")
        end = try o.optional("end")
        endIsEstimate = try o.value("endIsEstimate", default: false)
        room = try o.required("room")
        title = try o.required("title")
        speakers = try o.value("speakers", default: [])
        note = try o.optional("note")
        category = try o.required("category")
        group = try o.optional("group")
        isMine = try o.value("isMine", default: false)
        hasAnthropicSpeaker = try o.value("hasAnthropicSpeaker", default: false)
        officialUrl = try o.value("officialUrl", default: "")
        description = try o.optional("description")
        slidesUrl = try o.optional("slidesUrl")
        discussionUrl = try o.optional("discussionUrl")
        coloEvent = try o.optional("coloEvent")
        coloEvents = try o.value("coloEvents", default: [])
        format = try o.optional("format")
        level = try o.optional("level")
        sponsored = try o.value("sponsored", default: false)
        topic = try o.optional("topic")
    }
}

/// colocated.json (its descriptions are in colocated_details.json: ``ColocatedDetailsDto``).
/// Its sessions are shaped like schedule.json's; its rooms like rooms.json's.
struct ColocatedFileDto: JSONDecodable {
    let about: String
    let timeZone: String
    let anthropicSpeakers: [String]
    let fieldNotes: OrderedMap<String, String>
    let events: [ColoEventDto]
    let sessions: [SessionDto]
    let rooms: OrderedMap<String, RoomDto>

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "ColocatedFileDto")
        about = try o.value("_about", default: "")
        timeZone = try o.value("timeZone", default: "America/Denver")
        anthropicSpeakers = try o.value("anthropicSpeakers", default: [])
        fieldNotes = try o.value("fieldNotes", default: [:])
        events = try o.value("events", default: [])
        sessions = try o.value("sessions", default: [])
        rooms = try o.value("rooms", default: [:])
    }
}

/// colocated_details.json: "details", the same shape as details.json (read lazily).
struct ColocatedDetailsDto: JSONDecodable {
    let details: OrderedMap<String, DetailDto>

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "ColocatedDetailsDto")
        details = try o.value("details", default: [:])
    }
}

struct ColoEventDto: JSONDecodable {
    let key: String
    let name: String
    let mainRoom: String
    let rooms: [String]
    let start: String
    let end: String
    let halfDay: Bool
    let talkCount: Int
    let supersedes: String?
    let infoUrl: String?
    let pageUrl: String?
    let passNote: String?

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "ColoEventDto")
        key = try o.required("key")
        name = try o.required("name")
        mainRoom = try o.required("mainRoom")
        rooms = try o.value("rooms", default: [])
        start = try o.required("start")
        end = try o.required("end")
        halfDay = try o.value("halfDay", default: false)
        talkCount = try o.value("talkCount", default: 0)
        supersedes = try o.optional("supersedes")
        infoUrl = try o.optional("infoUrl")
        pageUrl = try o.optional("pageUrl")
        passNote = try o.optional("passNote")
    }
}

struct RoomsFileDto: JSONDecodable {
    let rooms: OrderedMap<String, RoomDto>

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "RoomsFileDto")
        rooms = try o.value("rooms", default: [:])
    }
}

struct RoomDto: JSONDecodable {
    let name: String
    let buildingLabel: String?
    let venue: String?
    let venueCode: String?
    let level: Int?
    let lat: Double?
    let lng: Double?
    let x: Double?
    let y: Double?
    let whereText: String?
    let attachNode: String?
    let finalStep: String?

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "RoomDto")
        name = try o.required("name")
        buildingLabel = try o.optional("buildingLabel")
        venue = try o.optional("venue")
        venueCode = try o.optional("venueCode")
        level = try o.optional("level")
        lat = try o.optional("lat")
        lng = try o.optional("lng")
        x = try o.optional("x")
        y = try o.optional("y")
        whereText = try o.optional("whereText")
        attachNode = try o.optional("attachNode")
        finalStep = try o.optional("finalStep")
    }
}

struct WayfindingFileDto: JSONDecodable {
    let origin: OriginDto
    let magneticDeclination: String
    let routing: RoutingDto
    let entrances: OrderedMap<String, EntranceDto>
    let nodes: OrderedMap<String, NodeDto>
    let edges: [EdgeDto]

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "WayfindingFileDto")
        origin = try o.required("origin")
        magneticDeclination = try o.value("magneticDeclination", default: "")
        routing = try o.required("routing")
        entrances = try o.required("entrances")
        nodes = try o.required("nodes")
        edges = try o.required("edges")
    }
}

struct OriginDto: JSONDecodable {
    let lat0: Double
    let lon0: Double
    let metersPerDegLat: Double
    let metersPerDegLon: Double

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "OriginDto")
        lat0 = try o.required("lat0")
        lon0 = try o.required("lon0")
        metersPerDegLat = try o.required("metersPerDegLat")
        metersPerDegLon = try o.required("metersPerDegLon")
    }
}

struct RoutingDto: JSONDecodable {
    let algorithm: String
    let roomAttach: String
    let startText: String
    let lowerConcourseMerge: MergeDto
    let distanceSuffix: String
    let summary: String
    let stepKinds: String

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "RoutingDto")
        algorithm = try o.value("algorithm", default: "")
        roomAttach = try o.value("roomAttach", default: "")
        startText = try o.value("startText", default: "")
        lowerConcourseMerge = try o.required("lowerConcourseMerge")
        distanceSuffix = try o.value("distanceSuffix", default: "")
        summary = try o.value("summary", default: "")
        stepKinds = try o.value("stepKinds", default: "")
    }
}

struct MergeDto: JSONDecodable {
    let nodes: [String]
    let rule: String
    let `where`: OrderedMap<String, String>

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "MergeDto")
        nodes = try o.required("nodes")
        rule = try o.value("rule", default: "")
        `where` = try o.required("where")
    }
}

struct EntranceDto: JSONDecodable {
    let name: String
    let node: String

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "EntranceDto")
        name = try o.required("name")
        node = try o.required("node")
    }
}

struct NodeDto: JSONDecodable {
    let name: String
    let x: Double
    let y: Double
    let level: Int
    let building: String

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "NodeDto")
        name = try o.required("name")
        x = try o.required("x")
        y = try o.required("y")
        level = try o.required("level")
        building = try o.required("building")
    }
}

struct EdgeDto: JSONDecodable {
    let a: String
    let b: String
    let textAB: String
    let textBA: String

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "EdgeDto")
        a = try o.required("a")
        b = try o.required("b")
        textAB = try o.required("textAB")
        textBA = try o.required("textBA")
    }
}

struct VenueFileDto: JSONDecodable {
    let buildings: OrderedMap<String, BuildingDto>
    let streets: [StreetDto]
    let zones: [ZoneDto]

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "VenueFileDto")
        buildings = try o.value("buildings", default: [:])
        streets = try o.value("streets", default: [])
        zones = try o.value("zones", default: [])
    }
}

struct BuildingDto: JSONDecodable {
    let name: String
    let outline: [[Double]]

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "BuildingDto")
        name = try o.required("name")
        outline = try o.required("outline")
    }
}

struct StreetDto: JSONDecodable {
    let name: String
    let from: [Double]
    let to: [Double]

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "StreetDto")
        name = try o.required("name")
        from = try o.required("from")
        to = try o.required("to")
    }
}

struct ZoneDto: JSONDecodable {
    let name: String
    let x0: Double
    let x1: Double
    let y0: Double
    let y1: Double

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "ZoneDto")
        name = try o.required("name")
        x0 = try o.required("x0")
        x1 = try o.required("x1")
        y0 = try o.required("y0")
        y1 = try o.required("y1")
    }
}

struct DetailDto: JSONDecodable {
    let description: String
    let speakers: [SpeakerDto]

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "DetailDto")
        description = try o.value("description", default: "")
        speakers = try o.value("speakers", default: [])
    }
}

struct SpeakerDto: JSONDecodable {
    let name: String
    let tagline: String

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "SpeakerDto")
        name = try o.required("name")
        tagline = try o.value("tagline", default: "")
    }
}

struct SummitDetailDto: JSONDecodable {
    let d: String
    let slides: String?
    let link: String?
    let linkText: String?

    init(json: JSONValue) throws {
        let o = try JSONFields(json, "SummitDetailDto")
        d = try o.value("d", default: "")
        slides = try o.optional("slides")
        link = try o.optional("link")
        linkText = try o.optional("linkText")
    }
}
