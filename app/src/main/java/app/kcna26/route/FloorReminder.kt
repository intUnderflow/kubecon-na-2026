package app.kcna26.route

import androidx.compose.runtime.Immutable
import app.kcna26.data.Room

/**
 * The floor reminder, derived from a room and its route
 * (owner: engine). GPS can't tell floors apart, so Directions shows the room's floor in
 * large type plus what to do to get there:
 *
 * - [headline]: "Level 2 · Salt Palace · 251 A–C"
 * - [instruction]: "Room is on Level 2: take the North Foyer escalator up"
 *
 * [action] comes from the route's up/down step that arrives on the room's level: its first
 * sentence, with the first letter lower-cased and a trailing " to Level N" (or " on
 * Level N") dropped, because the level is already said. When the last level change is the
 * end of several hops in the same direction, the hops are joined with ", then " (for
 * Capitol Reef from 200 South: "take the Hyatt escalators or an elevator up, then take a
 * Hyatt elevator up one level"). With no level change on the way (a Level 1 room, or
 * starting on the right level) [action] is null and [instruction] is just "Room is on
 * Level N". Pieces that aren't known are null, never made up.
 *
 * @property level the room's floor, null for OFF.
 * @property building "Salt Palace" or "Hyatt Regency" (the web's `.loc .bd`), null if unknown.
 * @property roomName the room's name, e.g. "251 A–C".
 * @property action what to do to reach [level], or null when the route doesn't change level.
 * @property direction [StepKind.UP] or [StepKind.DOWN] for [action], null without one.
 * @property hops how many up/down steps [action] covers (0 without one).
 */
@Immutable
data class FloorReminder(
    val level: Int?,
    val building: String?,
    val roomName: String,
    val action: String?,
    val direction: StepKind? = null,
    val hops: Int = 0,
) {
    /** "Level 2 · Salt Palace · 251 A–C"; missing pieces are left out ("Off-site" for OFF). */
    val headline: String
        get() = listOfNotNull(level?.let { "Level $it" }, building, roomName).joinToString(" · ")

    /** "Level 2", or null for OFF. */
    val levelLabel: String? get() = level?.let { "Level $it" }

    /** "Salt Palace · 251 A–C" (the web's `.loc .bd` line). */
    val buildingAndRoom: String get() = listOfNotNull(building, roomName).joinToString(" · ")

    /** "Room is on Level 2: take the North Foyer escalator up", "Room is on Level 1", or null for OFF. */
    val instruction: String?
        get() = level?.let { if (action != null) "Room is on Level $it: $action" else "Room is on Level $it" }

    companion object {
        /** The reminder for [room], reached by [route] (null: no route, so no action). */
        fun of(room: Room, route: Route?): FloorReminder {
            val level = room.level
            val base = FloorReminder(level, buildingName(room.venueCode), room.name, null)
            if (route == null || level == null) return base
            val steps = route.steps
            val arrival = steps.indexOfLast { it.kind.changesLevel && (it.level == null || it.level == level) }
            if (arrival < 0) return base
            val kind = steps[arrival].kind
            // Walk back over earlier hops in the same direction (walks in between are fine).
            var first = arrival
            for (i in arrival - 1 downTo 0) {
                val k = steps[i].kind
                if (k == kind) first = i else if (k.changesLevel || k == StepKind.START) break
            }
            val parts = (first..arrival).filter { steps[it].kind == kind }.mapNotNull { actionOf(steps[it].text) }
            if (parts.isEmpty()) return base
            return base.copy(action = parts.joinToString(", then "), direction = kind, hops = parts.size)
        }

        /**
         * The action part of one up/down step: "Take the North Foyer escalator up to Level 2.
         * You arrive on the Upper Concourse." → "take the North Foyer escalator up".
         * Null for blank text.
         */
        fun actionOf(stepText: String): String? {
            val sentence = stepText.trim().let { t ->
                val end = t.indexOf(". ")
                (if (end >= 0) t.substring(0, end) else t).removeSuffix(".").trim()
            }
            if (sentence.isEmpty()) return null
            val lowered = sentence.replaceFirstChar { it.lowercaseChar() }
            return LEVEL_TAIL.replace(lowered, "").trim().ifEmpty { null }
        }

        /** "SP" → "Salt Palace", "HY" → "Hyatt Regency" (web wayHTML), else null. */
        fun buildingName(venueCode: String?): String? = when (venueCode) {
            "SP" -> "Salt Palace"
            "HY" -> "Hyatt Regency"
            else -> null
        }

        /** " to Level 2" / " on Level 1" at the end of the sentence or before a comma. */
        private val LEVEL_TAIL = Regex(""" (?:to|on) Level \d+(?=,|$)""")
    }
}
