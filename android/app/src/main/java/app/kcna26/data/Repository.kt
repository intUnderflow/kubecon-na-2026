package app.kcna26.data

import android.content.res.AssetManager
import app.kcna26.time.ZONE
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.time.LocalDate
import java.time.OffsetDateTime

/**
 * All bundled data, parsed once. Immutable and thread-safe.
 *
 * - In the app: `LocalAppGraph.current.repository` (or `context.appGraph.repository`).
 *   The App warms it up on a background thread at process start and the shell
 *   only composes screens once it is loaded, so reading it in composition is free.
 * - In unit tests: `TestData.repo` (app/src/test), which uses [fromDirectory] on
 *   `src/main/assets`.
 *
 * The core files (schedule, rooms, wayfinding, venue, summit details and
 * colocated.json) are parsed eagerly by [load], which the splash waits for; the
 * 575 KB details.json and the 220 KB colocated_details.json are read lazily on
 * first access to [details] (DetailsRepository.warmBundled, off the main thread).
 *
 * colocated.json (optional: the app works without it) merges in like this:
 * its sessions follow schedule.json's in [sessions]; its events are [coloEvents];
 * the schedule.json placeholders they replace are [supersededIds] (kept, but not
 * shown); its position-less places are [extraRooms] (found by [room]); its
 * Anthropic speakers join [anthropicSpeakers]; colocated_details.json (optional
 * too) joins [details] for its sessions.
 */
class Repository private constructor(
    val meta: ScheduleMeta,
    /** schedule.json's 614 sessions in file order, then colocated.json's (223). Ids are unique. */
    val sessions: List<Session>,
    /** The five days in order (sun, mon, tue, wed, thu). */
    val days: List<Day>,
    /** Keyed by category key, in file order. */
    val categories: Map<String, Category>,
    /** schedule.json "anthropicSpeakers" (includes Lucy Sweet) plus colocated.json's. */
    val anthropicSpeakers: Set<String>,
    /** rooms.json, keyed by room code, in file order (40). */
    val rooms: Map<String, Room>,
    val wayfinding: Wayfinding,
    val venue: Venue,
    /** maintainer_summit_details.json, keyed by session id. */
    val summitDetails: Map<String, SummitDetail>,
    /** colocated.json "events": the CNCF-hosted co-located events, alphabetical. */
    val coloEvents: List<ColoEvent>,
    /**
     * Places only colocated.json uses (FOY meeting-room foyers, LCH4 lunch hall). They have no
     * position, so they stay out of [rooms] (the walking graph's room list); [room] finds them.
     */
    val extraRooms: Map<String, Room>,
    private val detailsLoader: () -> Map<String, SessionDetail>,
) {
    /** Session by id. */
    val sessionsById: Map<String, Session> = sessions.associateBy { it.id }

    /** Co-located event by key. */
    val coloEventsByKey: Map<String, ColoEvent> = coloEvents.associateBy { it.key }

    /**
     * schedule.json's all-day placeholders ("ArgoCon", note "All-Access pass") that an event in
     * [coloEvents] replaces. They stay in [sessions] (an old saved id still opens) but the
     * schedule never lists them.
     */
    val supersededIds: Set<String> = coloEvents.mapNotNullTo(LinkedHashSet()) { e -> e.supersedes?.takeIf { it in sessionsById } }

    /** Every distinct speaker name in the schedule, sorted case-insensitively (for the Settings picker). */
    val allSpeakers: List<String> =
        sessions.flatMap { it.speakers }.distinct().sortedWith(String.CASE_INSENSITIVE_ORDER)

    /**
     * details.json plus colocated_details.json (for colocated.json's sessions): session id →
     * description + speakers with taglines. Parsed on first access.
     */
    val details: Map<String, SessionDetail> by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { detailsLoader() }

    /** The default "I'm speaking as" name from schedule.json ("Lucy Sweet"). */
    val defaultMe: String get() = meta.me

    fun session(id: String): Session? = sessionsById[id]

    /** A rooms.json room, or one of the co-located [extraRooms]. */
    fun room(code: String): Room? = rooms[code] ?: extraRooms[code]
    fun day(key: String): Day? = days.firstOrNull { it.key == key }
    fun dayOf(session: Session): Day? = day(session.day)
    fun category(key: String): Category? = categories[key]
    fun roomOf(session: Session): Room? = room(session.room)
    fun coloEvent(key: String): ColoEvent? = coloEventsByKey[key]

    companion object {
        const val SCHEDULE = "schedule.json"
        const val ROOMS = "rooms.json"
        const val WAYFINDING = "wayfinding.json"
        const val VENUE = "venue.json"
        const val DETAILS = "details.json"
        const val SUMMIT_DETAILS = "maintainer_summit_details.json"
        const val TEST_VECTORS = "test_vectors.json"

        /** Optional: the CNCF-hosted co-located events (scripts/fetch_colocated.py). */
        const val COLOCATED = "colocated.json"

        /** Optional: [COLOCATED]'s descriptions and speaker taglines, a file of their own so start-up doesn't parse them. */
        const val COLOCATED_DETAILS = "colocated_details.json"

        /** Shared lenient JSON config (also fine for feature code that needs one). */
        val json: Json = Json {
            ignoreUnknownKeys = true
            explicitNulls = false
            coerceInputValues = true
            isLenient = true
        }

        /** Loads from the APK's assets (the app). Blocking: call off the main thread. */
        fun fromAssets(assets: AssetManager): Repository = load { name -> assets.open(name) }

        /** Loads from a directory holding the JSON files (unit tests: `File("src/main/assets")`). */
        fun fromDirectory(dir: File): Repository = load { name -> File(dir, name).inputStream() }

        /** Loads using [open] to open each file by name. Blocking. */
        fun load(open: (String) -> InputStream): Repository {
            fun text(name: String): String = open(name).use { it.readBytes().toString(Charsets.UTF_8) }
            fun <T> parse(name: String, s: DeserializationStrategy<T>): T = json.decodeFromString(s, text(name))

            val sch = parse(SCHEDULE, ScheduleFileDto.serializer())
            val rooms = parse(ROOMS, RoomsFileDto.serializer())
            val way = parse(WAYFINDING, WayfindingFileDto.serializer())
            val venue = parse(VENUE, VenueFileDto.serializer())
            val summit = json.parseToJsonElement(text(SUMMIT_DETAILS)) as JsonObject
            val colo = colocated(open)

            val days = sch.days.mapIndexed { i, d -> Day(d.key, LocalDate.parse(d.date), d.label, d.short, d.subtitle, i) }
            val roomMap = rooms.rooms.entries.associate { (k, r) -> k to r.toModel(k) }
            val base = sch.sessions.map { it.toModel() }
            val ids = base.mapTo(HashSet()) { it.id }
            val dayByDate = days.associateBy { it.date }
            // All or nothing: a co-located file that doesn't convert leaves the rest of the schedule as it is.
            val (coloSessions, coloEvents) = try {
                // A co-located id that collides with schedule.json is dropped (the script prefixes these, so none do).
                val xs = colo?.sessions.orEmpty().map { it.toModel() }.filter { ids.add(it.id) }
                val es = colo?.events.orEmpty().mapNotNull { e ->
                    val start = OffsetDateTime.parse(e.start).toInstant()
                    val day = dayByDate[start.atZone(ZONE).toLocalDate()] ?: return@mapNotNull null
                    ColoEvent(
                        key = e.key, name = e.name, day = day.key, mainRoom = e.mainRoom,
                        rooms = e.rooms.ifEmpty { listOf(e.mainRoom) }, start = start,
                        end = OffsetDateTime.parse(e.end).toInstant(), halfDay = e.halfDay, talkCount = e.talkCount,
                        supersedes = e.supersedes, infoUrl = e.infoUrl?.takeIf { it.isNotBlank() },
                        pageUrl = e.pageUrl?.takeIf { it.isNotBlank() }, passNote = e.passNote?.takeIf { it.isNotBlank() },
                    )
                }.distinctBy { it.key }
                xs to es
            } catch (e: java.time.DateTimeException) {
                emptyList<Session>() to emptyList<ColoEvent>()
            }
            val coloOk = coloSessions.isNotEmpty() || coloEvents.isNotEmpty()

            return Repository(
                meta = ScheduleMeta(sch.about, sch.timeZone, sch.me, sch.fieldNotes),
                sessions = base + coloSessions,
                days = days,
                categories = sch.categories.entries.associate { (k, c) -> k to Category(k, c.label, c.colorLight, c.colorDark) },
                anthropicSpeakers = LinkedHashSet(sch.anthropicSpeakers + if (coloOk) colo?.anthropicSpeakers.orEmpty() else emptyList()),
                rooms = roomMap,
                wayfinding = way.toModel(),
                venue = venue.toModel(),
                coloEvents = coloEvents,
                extraRooms = (if (coloOk) colo?.rooms.orEmpty() else emptyMap()).entries
                    .filter { (k, _) -> k !in roomMap }
                    .associate { (k, r) -> k to r.toModel(k) },
                summitDetails = summit.entries
                    .filter { (k, v) -> !k.startsWith("_") && v is JsonObject }
                    .associate { (k, v) ->
                        val d = json.decodeFromJsonElement<SummitDetailDto>(v)
                        k to SummitDetail(d.d, d.slides, d.link, d.linkText)
                    },
                detailsLoader = {
                    val raw = LinkedHashMap(json.decodeFromString<Map<String, DetailDto>>(text(DETAILS)))
                    if (coloSessions.isNotEmpty()) {
                        val coloIds = coloSessions.mapTo(HashSet()) { it.id }
                        colocatedDetails(open).forEach { (id, d) -> if (id in coloIds) raw.putIfAbsent(id, d) }
                    }
                    raw.mapValues { (_, d) -> SessionDetail(d.description, d.speakers.map { SpeakerTagline(it.name, it.tagline) }) }
                },
            )
        }

        /**
         * colocated.json, or null when it is missing or unreadable: the rest of the schedule
         * must still load. (Unit tests pin its contents.)
         */
        private fun colocated(open: (String) -> InputStream): ColocatedFileDto? = try {
            val t = open(COLOCATED).use { it.readBytes().toString(Charsets.UTF_8) }
            json.decodeFromString(ColocatedFileDto.serializer(), t)
        } catch (e: IOException) {
            null
        } catch (e: IllegalArgumentException) { // SerializationException
            null
        }

        /** colocated_details.json's "details", or empty when it is missing or unreadable (no descriptions then). */
        private fun colocatedDetails(open: (String) -> InputStream): Map<String, DetailDto> = try {
            val t = open(COLOCATED_DETAILS).use { it.readBytes().toString(Charsets.UTF_8) }
            json.decodeFromString(ColocatedDetailsDto.serializer(), t).details
        } catch (e: IOException) {
            emptyMap()
        } catch (e: IllegalArgumentException) {
            emptyMap()
        }

        private fun SessionDto.toModel() = Session(
            id = id,
            event = event,
            day = day,
            start = OffsetDateTime.parse(start).toInstant(),
            end = end?.let { OffsetDateTime.parse(it).toInstant() },
            endIsEstimate = endIsEstimate,
            room = room,
            title = title,
            speakers = speakers,
            note = note,
            category = category,
            group = group?.let { SessionGroup(it.key, it.title) },
            precomputedIsMine = isMine,
            precomputedHasAnthropic = hasAnthropicSpeaker,
            officialUrl = officialUrl,
            description = description,
            slidesUrl = slidesUrl?.takeIf { it.isNotBlank() },
            discussionUrl = discussionUrl?.takeIf { it.isNotBlank() },
            coloEvent = coloEvent?.takeIf { it.isNotBlank() },
            coloEvents = coloEvents.filter { it.isNotBlank() },
            format = format?.takeIf { it.isNotBlank() },
            level = level?.takeIf { it.isNotBlank() },
            sponsored = sponsored,
            topic = topic?.takeIf { it.isNotBlank() },
        )

        private fun RoomDto.toModel(code: String) = Room(
            code = code, name = name, buildingLabel = buildingLabel, venue = venue, venueCode = venueCode,
            level = level, lat = lat, lng = lng, x = x, y = y, whereText = whereText,
            attachNode = attachNode, finalStep = finalStep,
        )

        private fun WayfindingFileDto.toModel() = Wayfinding(
            origin = Origin(origin.lat0, origin.lon0, origin.metersPerDegLat, origin.metersPerDegLon),
            magneticDeclination = magneticDeclination,
            routing = RoutingRules(
                algorithm = routing.algorithm,
                roomAttach = routing.roomAttach,
                startText = routing.startText,
                lowerConcourseMerge = LowerConcourseMerge(
                    routing.lowerConcourseMerge.nodes,
                    routing.lowerConcourseMerge.rule,
                    routing.lowerConcourseMerge.where,
                ),
                distanceSuffix = routing.distanceSuffix,
                summary = routing.summary,
                stepKinds = routing.stepKinds,
            ),
            entrances = entrances.entries.associate { (k, e) -> k to Entrance(k, e.name, e.node) },
            nodes = nodes.entries.associate { (k, n) -> k to WayNode(k, n.name, n.x, n.y, n.level, n.building) },
            edges = edges.map { WayEdge(it.a, it.b, it.textAB, it.textBA) },
        )

        private fun List<Double>.pt() = PointXY(this[0], this[1])

        private fun VenueFileDto.toModel() = Venue(
            buildings = buildings.entries.associate { (k, b) -> k to Building(k, b.name, b.outline.map { it.pt() }) },
            streets = streets.map { Street(it.name, it.from.pt(), it.to.pt()) },
            zones = zones.map { Zone(it.name, it.x0, it.x1, it.y0, it.y1) },
        )
    }
}
