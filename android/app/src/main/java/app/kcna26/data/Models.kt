package app.kcna26.data

import app.kcna26.time.ZONE
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZonedDateTime

/*
 * Domain models for every JSON file in assets/. Built by [Repository] from the
 * DTOs in Dto.kt. All are plain immutable data classes, safe to use from any
 * thread and in plain JVM unit tests.
 *
 * Coordinates: x is metres east, y metres north of the West Temple & 200 South
 * intersection (wayfinding.json "origin"). Levels are the venue's floor numbers
 * (Level 1 = street level at 200 South).
 */

/** A point in local metres (x east, y north). Shared by rooms, nodes, venue shapes and routes. */
data class PointXY(val x: Double, val y: Double)

// ---------------------------------------------------------------- schedule.json

/** One of the five conference days (schedule.json "days"). */
data class Day(
    /** "sun", "mon", "tue", "wed", "thu". Sessions refer to days by this key. */
    val key: String,
    /** Calendar date in America/Denver. */
    val date: LocalDate,
    /** "Sunday, Nov 8" */
    val label: String,
    /** "Sun 8" */
    val short: String,
    /** One-line description shown under the day heading. */
    val subtitle: String,
    /** 0..4, position in [Repository.days]. */
    val index: Int,
) {
    /** "Sun", "Mon", ... (the web's `dow`). */
    val dow: String get() = short.substringBefore(' ')

    /** 8, 9, ... (the web's `num`). */
    val num: Int get() = date.dayOfMonth
}

/** A session category (schedule.json "categories"); colours are "#RRGGBB". */
data class Category(
    /** "key", "talk", "mnt", "hands", "show", "com", "soc", "colo", "log". */
    val key: String,
    /** "Keynote", "Talk", ...; "Break" for log. The web shows no label for log rows. */
    val label: String,
    val colorLight: String,
    val colorDark: String,
) {
    /** 0xFFRRGGBB, ready for `androidx.compose.ui.graphics.Color(Int)`. */
    val lightArgb: Int get() = parseHexColor(colorLight)
    val darkArgb: Int get() = parseHexColor(colorDark)
}

/** Back-to-back sessions in one room, shown as one expandable card titled [title]. */
data class SessionGroup(val key: String, val title: String)

/**
 * One session: schedule.json "sessions" (614, file order), then colocated.json's (223: the
 * CNCF-hosted co-located events' talks and breaks, and their Evening Reception).
 *
 * Read schedule.json "fieldNotes": [end] is null when the agenda gives no end
 * (treat as 90 minutes for "finished" logic, see [effectiveEnd]); [endIsEstimate]
 * means show durations with "~"; category "log" rows are quiet break rows.
 */
data class Session(
    /** Sessionize id. Maintainer Summit ids start with "m". */
    val id: String,
    /** "kubecon", "maintainer-summit" or "colocated" ([EVENT_COLOCATED]). */
    val event: String,
    /** Day key, see [Day.key]. */
    val day: String,
    val start: Instant,
    /** Null when the agenda gives no end time (one session). */
    val end: Instant?,
    val endIsEstimate: Boolean,
    /** Room code, a key of [Repository.rooms] (e.g. "251AC", "OFF"). */
    val room: String,
    val title: String,
    /** Speaker names in agenda order; may be empty. */
    val speakers: List<String>,
    /** "Sold out", "All-Access pass", "Main Track", "Keynote", ...; null if none. */
    val note: String?,
    /** Category key, see [Category.key]. */
    val category: String,
    val group: SessionGroup?,
    /** Precomputed for "Lucy Sweet". Do NOT use: call [isMine] with the current setting. */
    val precomputedIsMine: Boolean,
    /** Precomputed. Do NOT use: call [hasAnthropic]. */
    val precomputedHasAnthropic: Boolean,
    /** Official agenda page for this session. */
    val officialUrl: String,
    /** Only Maintainer Summit sessions carry one (KubeCon descriptions are in details.json). */
    val description: String?,
    /** Only on two Maintainer Summit sessions. */
    val slidesUrl: String?,
    /** Unconference sessions: the GitHub discussion with the topic's proposal and replies; null if none. */
    val discussionUrl: String? = null,
    /** Co-located only: the [ColoEvent.key] of the one event this talk (or single-event break) belongs to. */
    val coloEvent: String? = null,
    /** Co-located only: every event whose agenda lists this session (talk: its event; break: each event it serves). */
    val coloEvents: List<String> = emptyList(),
    /** Co-located talks: "Breakout", "Panel", "Lightning talk" or "Keynote"; null if none. */
    val format: String? = null,
    /** Co-located talks: "Any level", "Beginner", "Intermediate" or "Advanced"; null if none. */
    val level: String? = null,
    /** Co-located talks: a sponsored (keynote) slot. */
    val sponsored: Boolean = false,
    /** Co-located talks: the topic within its event ("Progressive Delivery"); null if none. */
    val topic: String? = null,
) {
    val isMaintainerSummit: Boolean get() = event == "maintainer-summit"

    /** From colocated.json (CNCF-hosted co-located events, Monday). Their details are bundled: never fetched live. */
    val isColocated: Boolean get() = event == EVENT_COLOCATED

    /** [end], or start + 90 min when the agenda has none. Use for "finished" and "live" logic. */
    val effectiveEnd: Instant get() = end ?: start.plus(OPEN_ENDED)

    /** Start in America/Denver. */
    val startLocal: ZonedDateTime get() = start.atZone(ZONE)
    val endLocal: ZonedDateTime? get() = end?.atZone(ZONE)

    companion object {
        /** How long an open-ended session ([end] == null) counts as lasting. */
        val OPEN_ENDED: Duration = Duration.ofMinutes(90)

        /** [event] of colocated.json sessions. */
        const val EVENT_COLOCATED = "colocated"
    }
}

/**
 * A CNCF-hosted co-located event (colocated.json "events"), shown on its day as one card
 * with its agenda: the sessions whose [Session.coloEvents] contain [key]. Alphabetical.
 */
data class ColoEvent(
    /** "colo-argocon": also the group key of its talks. */
    val key: String,
    /** "ArgoCon", "Cloud Native AI + Inference Day", … */
    val name: String,
    /** Day key ("mon") of [start]. */
    val day: String,
    /** The room with the most talks (a rooms.json code). */
    val mainRoom: String,
    /** Every room with talks, [mainRoom] first. */
    val rooms: List<String>,
    /** First talk's start. */
    val start: Instant,
    /** Last talk's end: the card disappears then (agenda breaks may run later). */
    val end: Instant,
    val halfDay: Boolean,
    val talkCount: Int,
    /** schedule.json's all-day placeholder session for this event (hidden: the card replaces it). */
    val supersedes: String?,
    /** That placeholder's official listing. */
    val infoUrl: String?,
    /** The event's own LF page. */
    val pageUrl: String?,
    /** "All-Access pass" (the placeholder's note). */
    val passNote: String?,
)

/** schedule.json top-level fields other than the lists. */
data class ScheduleMeta(
    val about: String,
    /** "America/Denver" */
    val timeZone: String,
    /** The default "I'm speaking as" name ("Lucy Sweet"). */
    val me: String,
    /** schedule.json "fieldNotes", verbatim. */
    val fieldNotes: Map<String, String>,
)

// ---------------------------------------------------------------- rooms.json

/**
 * A room (rooms.json "rooms"), keyed by its code. 40 rooms, in file order (which
 * is also the web version's room sort order). colocated.json adds two position-less
 * places (FOY, LCH4: [Repository.extraRooms]).
 *
 * OFF ("Off-site") only has [name]; every other field is null for it, and
 * [hasPosition] is false. HL (Hyatt lobby) has a position but a null
 * [buildingLabel]. REG and COAT exist here but no session uses them.
 */
data class Room(
    val code: String,
    /** "251 A–C", "Grand Ballroom GI", "Off-site", ... */
    val name: String,
    /** "Salt Palace L2", "Hyatt L4", "Showcase floor"; null for HL and OFF. */
    val buildingLabel: String?,
    /** "Salt Palace Convention Center" / "Hyatt Regency Salt Lake City". */
    val venue: String?,
    /** "SP" (Salt Palace) or "HY" (Hyatt). */
    val venueCode: String?,
    val level: Int?,
    val lat: Double?,
    val lng: Double?,
    val x: Double?,
    val y: Double?,
    /** A sentence describing where the room is. */
    val whereText: String?,
    /** Wayfinding node the room opens off ([Wayfinding.nodes] key). */
    val attachNode: String?,
    /** Last walking step to reach the room. */
    val finalStep: String?,
) {
    val hasPosition: Boolean get() = x != null && y != null && lat != null && lng != null && level != null

    /** Local metres, or null for OFF. */
    val pos: PointXY? get() = if (x != null && y != null) PointXY(x, y) else null
}

// ---------------------------------------------------------------- wayfinding.json

/** Flat-earth conversion constants: x = (lng - lon0) * metersPerDegLon; y = (lat - lat0) * metersPerDegLat. */
data class Origin(
    val lat0: Double,
    val lon0: Double,
    val metersPerDegLat: Double,
    val metersPerDegLon: Double,
)

/** Walking-graph node. [building] is "SP" or "HY". */
data class WayNode(
    val key: String,
    val name: String,
    val x: Double,
    val y: Double,
    val level: Int,
    val building: String,
) {
    val pos: PointXY get() = PointXY(x, y)
}

/** Undirected corridor; [textAB] is the instruction walking a→b, [textBA] walking b→a. */
data class WayEdge(val a: String, val b: String, val textAB: String, val textBA: String)

/** A building entrance usable as a "From" start. Keys: E200S, EWT, EHY, E200W (in that order). */
data class Entrance(val key: String, val name: String, val node: String)

/** wayfinding.json "routing.lowerConcourseMerge". */
data class LowerConcourseMerge(
    /** S200, LCS, LCM, NF */
    val nodes: List<String>,
    val rule: String,
    /** node key -> "{where}" phrase */
    val where: Map<String, String>,
)

/** wayfinding.json "routing": the rules the router must follow, verbatim. */
data class RoutingRules(
    val algorithm: String,
    val roomAttach: String,
    val startText: String,
    val lowerConcourseMerge: LowerConcourseMerge,
    val distanceSuffix: String,
    val summary: String,
    val stepKinds: String,
)

data class Wayfinding(
    val origin: Origin,
    /** Prose note: add android.hardware.GeomagneticField declination (~+10°) to magnetic heading. */
    val magneticDeclination: String,
    val routing: RoutingRules,
    /** Ordered as in the file: E200S, EWT, EHY, E200W. */
    val entrances: Map<String, Entrance>,
    /** Ordered as in the file. */
    val nodes: Map<String, WayNode>,
    /** In file order (the router's adjacency order depends on it). */
    val edges: List<WayEdge>,
)

// ---------------------------------------------------------------- venue.json

/** Building outline polygon in local metres. [code] is "SP" or "HY". */
data class Building(val code: String, val name: String, val outline: List<PointXY>)

data class Street(val name: String, val from: PointXY, val to: PointXY)

/** Axis-aligned hall zone rectangle in local metres. */
data class Zone(val name: String, val x0: Double, val x1: Double, val y0: Double, val y1: Double)

/**
 * Shapes for the small north-up map. The web draws a 512×510 viewBox with
 * svgX = x + 492, svgY = 492 − y.
 */
data class Venue(
    val buildings: Map<String, Building>,
    val streets: List<Street>,
    val zones: List<Zone>,
)

// ---------------------------------------------------------------- details.json, maintainer_summit_details.json

data class SpeakerTagline(val name: String, val tagline: String)

/** details.json entry: full KubeCon description and speakers with taglines (558 of 579 KubeCon sessions). */
data class SessionDetail(val description: String, val speakers: List<SpeakerTagline>)

/**
 * maintainer_summit_details.json entry, keyed by session id (its content is already
 * merged into schedule.json descriptions/slides). [link]/[linkText] are an optional
 * extra link for the details (opened in the browser); no entry has one at present.
 */
data class SummitDetail(
    val description: String,
    val slides: String?,
    val link: String?,
    val linkText: String?,
)

// ---------------------------------------------------------------- helpers

/** Parses "#RRGGBB" (or "#AARRGGBB") to an ARGB int with full alpha by default. */
fun parseHexColor(hex: String): Int {
    val h = hex.removePrefix("#")
    val v = h.toLong(16)
    return when (h.length) {
        6 -> (0xFF000000 or v).toInt()
        8 -> v.toInt()
        else -> throw IllegalArgumentException("Bad colour $hex")
    }
}
