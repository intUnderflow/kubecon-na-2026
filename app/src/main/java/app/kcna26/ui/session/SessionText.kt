package app.kcna26.ui.session

import app.kcna26.data.Day
import app.kcna26.data.Repository
import app.kcna26.data.Room
import app.kcna26.data.Session
import app.kcna26.data.SpeakerTagline
import app.kcna26.schedule.ScheduleLogic
import app.kcna26.time.TimeFormat
import java.time.Instant

/**
 * The details sheet's strings, ported from schedule_app.js `sheetHTML` / `wayHTML`. Pure (no
 * Compose, no Android) so it is unit-tested on the JVM.
 */
object SessionText {
    const val OFF_SITE = "Off-site event. The official listing has the address and registration details."
    const val NO_POSITION = "No map position for this room."
    const val LOADING = "Loading the description…"

    /** Quiet note when a description that should exist couldn't be fetched (the web shows nothing). */
    const val UNAVAILABLE = "Couldn’t load the description. The official listing has it."

    const val YOU_SPEAKING = "You’re speaking"
    const val ANTHROPIC = "Anthropic"
    const val YOU = "You"
    const val GETTING_THERE = "Getting there"
    const val ABOUT = "About"
    const val DIRECTIONS = "Directions"
    const val SLIDES = "Slides ↗"
    const val OFFICIAL = "Official listing ↗"

    /** A session's GitHub discussion ([Session.discussionUrl], unconference sessions), opened in the browser. */
    const val DISCUSSION = "Proposal and replies on GitHub ↗"

    /** Tag on a sponsored co-located talk. */
    const val SPONSORED = "Sponsored"

    /** Eyebrow of a break shared by several co-located events. */
    const val COLOCATED_EVENTS = "Co-located events"

    /** "Speaker" / "Speakers" (web: `spkList.length===1`). */
    fun speakersHeading(count: Int): String = if (count == 1) "Speaker" else "Speakers"

    /** The web's `CATS[x.cat]`: the category label, empty for break rows ("log"). */
    fun categoryLabel(repo: Repository, s: Session): String =
        if (s.category == "log") "" else repo.category(s.category)?.label.orEmpty()

    /**
     * The co-located event a session belongs to, as the details' eyebrow (in place of the
     * category label): "ArgoCon" for its talks and its own breaks, "Co-located events" for a break
     * several events share; null for everything else (including the Evening Reception).
     */
    fun coloEyebrow(repo: Repository, s: Session): String? {
        if (!s.isColocated) return null
        val one = (s.coloEvent ?: s.coloEvents.singleOrNull())?.let { repo.coloEvent(it) }
        if (one != null) return one.name
        return if (s.coloEvents.count { repo.coloEvent(it) != null } > 1) COLOCATED_EVENTS else null
    }

    /** A co-located talk's tags: format ("Lightning talk"), level ("Intermediate"), "Sponsored". */
    fun coloTags(s: Session): List<String> =
        if (!s.isColocated) emptyList() else listOfNotNull(s.format, s.level, SPONSORED.takeIf { s.sponsored })

    /** A shared co-located break: "For ArgoCon, BackstageCon, FluxCon and Observability Day". */
    fun servesLine(repo: Repository, s: Session): String? {
        if (!s.isColocated) return null
        val names = s.coloEvents.mapNotNull { repo.coloEvent(it)?.name }
        if (names.size < 2) return null
        return "For " + names.dropLast(1).joinToString(", ") + " and " + names.last()
    }

    /** The official listing: the session's own link, else (co-located) its event's page; null if neither. */
    fun officialUrl(repo: Repository, s: Session): String? =
        s.officialUrl.takeIf { it.isNotBlank() }
            ?: s.coloEvent?.let { repo.coloEvent(it) }?.let { it.pageUrl ?: it.infoUrl }

    /** "Wed 5:00–5:30 PM", "Sun from 5:30 PM" (web: `${d.dow} ${range(x)}`). */
    fun dayAndTime(day: Day?, s: Session): String =
        listOfNotNull(day?.dow, TimeFormat.range(s)).joinToString(" ")

    /** "45 min", "~1h 30m"; null when the session has no end (open-ended). */
    fun duration(s: Session): String? = TimeFormat.dur(s)

    /** Maintainer Summit tag in the meta row ("Unconference", "Project Meeting"; not "Keynote"). */
    fun tag(s: Session): String? = s.note?.takeIf { s.isMaintainerSummit && it.isNotBlank() && it != "Keynote" }

    /** KubeCon note in the where row ("Sold out", "All-Access pass"). */
    fun whereNote(s: Session): String? = s.note?.takeIf { !s.isMaintainerSummit && it.isNotBlank() }

    /** "Live · 12 min left" while the session is on (the sheet always counts down, like the web). */
    fun liveLabel(s: Session, now: Instant): String? =
        if (ScheduleLogic.isLive(s, now)) "Live · ${TimeFormat.minutesBetween(now, s.effectiveEnd)} min left" else null

    /** Room name for the where row (the web's `rname`). */
    fun roomName(room: Room?, s: Session): String = room?.name ?: s.room

    /** The where row's muted building label ("Salt Palace L2"); null for HL and OFF. */
    fun buildingLabel(room: Room?): String? = room?.buildingLabel?.takeIf { it.isNotBlank() }

    /** "Level 2" (the web's `.wf .lv`); null without a position. */
    fun levelLabel(room: Room?): String? = room?.takeIf { it.hasPosition }?.level?.let { "Level $it" }

    /** "Salt Palace · 251 A–C" / "Hyatt Regency · Park City" (the web's `.wf .bd`). */
    fun buildingAndRoom(room: Room?): String? {
        if (room == null || !room.hasPosition) return null
        val building = if (room.venueCode == "HY") "Hyatt Regency" else "Salt Palace"
        return "$building · ${room.name}"
    }

    /** "Level 2 · Salt Palace · 251 A–C"; null for OFF or a room without a position. */
    fun locationLine(room: Room?): String? {
        val lv = levelLabel(room) ?: return null
        return "$lv · ${buildingAndRoom(room)}"
    }

    /**
     * Why Directions is unavailable (the web's wayHTML fallback), or null if it is available. A
     * place without a position that says where it is (the co-located foyers and lunch hall) leads
     * with that sentence.
     */
    fun directionsUnavailable(room: Room?, s: Session): String? {
        if (room != null && room.hasPosition) return null
        if (s.room == "OFF") return OFF_SITE
        val where = room?.whereText?.trim()
        return if (where.isNullOrEmpty()) NO_POSITION else "$where $NO_POSITION"
    }

    /** One row of the speakers list. */
    data class SpeakerRow(
        /** "You" for me, otherwise the name (cleaned of stray marks). */
        val label: String,
        val tagline: String,
        val isMe: Boolean,
        /** An Anthropic colleague (never me). */
        val isAnthropic: Boolean,
    )

    /**
     * Speakers with taglines (the web's `spkList`): the details list when it has any, otherwise
     * the schedule names. "You" follows the current "I'm speaking as" [me]; Anthropic is anyone
     * in [anthropicSpeakers] other than me (so with me = None, Lucy Sweet shows as Anthropic).
     * Sessionize names can differ slightly from the agenda's ("Suhani‎", "Smit Jain (he/him)"),
     * so each is matched back to its schedule name before comparing.
     */
    fun speakerRows(
        detailSpeakers: List<SpeakerTagline>,
        scheduleSpeakers: List<String>,
        me: String?,
        anthropicSpeakers: Set<String>,
    ): List<SpeakerRow> {
        val list = detailSpeakers.ifEmpty { scheduleSpeakers.map { SpeakerTagline(it, "") } }
        return list.mapNotNull { sp ->
            val name = cleanName(sp.name)
            if (name.isEmpty()) return@mapNotNull null
            val canonical = matchScheduleName(name, scheduleSpeakers) ?: name
            val isMe = me != null && canonical == me
            SpeakerRow(
                label = if (isMe) YOU else name,
                tagline = sp.tagline.trim(),
                isMe = isMe,
                isAnthropic = !isMe && canonical in anthropicSpeakers,
            )
        }
    }

    private val TRAILING_DASH = Regex("[\\s]*[-–—]+\\s*$")

    /** Drops invisible format characters (LRM, ZWSP, BOM…) and a dangling trailing dash. */
    fun cleanName(name: String): String {
        val visible = buildString(name.length) {
            for (c in name) if (Character.getType(c) != Character.FORMAT.toInt()) append(c)
        }
        return visible.trim().replace(TRAILING_DASH, "").trim()
    }

    /** The schedule's spelling of [name]: exact, case-insensitive, or a prefix ("Smit Jain (he/him)"). */
    fun matchScheduleName(name: String, scheduleSpeakers: List<String>): String? =
        scheduleSpeakers.firstOrNull { it == name }
            ?: scheduleSpeakers.firstOrNull { it.equals(name, ignoreCase = true) }
            ?: scheduleSpeakers.filter { it.isNotBlank() }
                .firstOrNull { name.startsWith("$it ", ignoreCase = true) || name.startsWith("$it(", ignoreCase = true) }
}
