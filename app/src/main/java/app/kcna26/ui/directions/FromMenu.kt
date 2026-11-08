package app.kcna26.ui.directions

import app.kcna26.data.PointXY
import app.kcna26.geo.Geo

/** What a From option is; the nearest-first menu shows it as a small icon. */
enum class FromKind { LIVE, ENTRANCE, ROOM }

/**
 * One row of the open From menu.
 * @property distanceM straight-line horizontal metres from the point the menu was sorted from,
 *   or null when the menu has no fix (grouped layout) or the option has no position.
 */
data class FromMenuItem(val option: FromOption, val distanceM: Double? = null) {
    val key: String get() = option.key

    /** "40 m", "1.2 km"; null without a distance. */
    val distance: String? get() = distanceM?.let(FromMenu::distanceLabel)

    /** "L2"; null when the level isn't known. */
    val level: String? get() = FromMenu.levelLabel(option.level)
}

/** A titled group of the open From menu. */
data class FromMenuSection(val title: String, val items: List<FromMenuItem>)

/**
 * What the open From menu lists after "My location (GPS)" ([live], always first).
 *
 * - With a fix ([byDistance]): one section, the entrances and rooms together, nearest first by
 *   straight-line horizontal distance from the fix. Distances compare as they are shown
 *   ([shownMetres]: "40 m", "1.2 km"), so options showing the same distance are ordered by level
 *   (lowest first), then name; an entrance comes before a room at the same spot (the Hyatt lobby
 *   is both), then key.
 * - Without a fix: the grouped layout, "Entrances" in file order then "Rooms" by name, with no
 *   distances.
 *
 * Rooms without a usable position (OFF) are left out of both layouts; the engine's
 * [app.kcna26.route.Router.startRooms] already excludes them. Build it once when the menu opens
 * and keep it while the menu is open, so new fixes never move items under the user's finger.
 */
data class FromMenu(val live: FromOption, val sections: List<FromMenuSection>, val byDistance: Boolean) {

    /** Every row after [live], in menu order. */
    val items: List<FromMenuItem> get() = sections.flatMap { it.items }

    companion object {
        /** The menu for [options] sorted from [at] (local metres); null or non-finite means no fix. */
        fun of(options: FromOptions, at: PointXY?): FromMenu {
            val rooms = options.rooms.filter { it.pos.isUsable() }
            if (at == null || !at.isUsable()) {
                return FromMenu(
                    live = options.live,
                    sections = listOf(
                        FromMenuSection(DirectionsText.ENTRANCES, options.entrances.map { FromMenuItem(it) }),
                        FromMenuSection(DirectionsText.ROOMS, rooms.map { FromMenuItem(it) }),
                    ),
                    byDistance = false,
                )
            }
            val nearest = (options.entrances + rooms)
                .map { FromMenuItem(it, it.pos?.takeIf { p -> p.isUsable() }?.let { p -> Geo.distance(at, p) }) }
                .sortedWith(NEAREST_FIRST)
            return FromMenu(options.live, listOf(FromMenuSection(DirectionsText.NEAREST, nearest)), byDistance = true)
        }

        /**
         * Nearest first: shown distance, then level (lowest first), then name (case-insensitive),
         * then entrances before rooms, then key. Options without a distance or a level go last.
         */
        val NEAREST_FIRST: Comparator<FromMenuItem> =
            compareBy<FromMenuItem>({ it.distanceM?.let(::shownMetres) ?: Long.MAX_VALUE }, { it.option.level ?: Int.MAX_VALUE })
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.option.label }
                .thenBy { it.option.kind }
                .thenBy { it.option.key }

        /**
         * A distance as the menu shows it, in metres: the readout's [Geo.r10] (nearest 10 m, at
         * least 10) below 1 km, else to the nearest 100 m (one decimal of a km).
         */
        fun shownMetres(m: Double): Long {
            val r = Geo.r10(m).toLong()
            return if (r < 1000) r else Geo.jsRound(m / 100.0) * 100
        }

        /** "10 m", "40 m", "990 m", then "1.0 km", "1.2 km", "12.3 km" (always a dot, any locale). */
        fun distanceLabel(m: Double): String {
            val s = shownMetres(m)
            return if (s < 1000) "$s m" else "${s / 1000}.${s % 1000 / 100} km"
        }

        /** "L2"; null for an unknown level. */
        fun levelLabel(level: Int?): String? = level?.let { "L$it" }

        private fun PointXY?.isUsable(): Boolean = this != null && x.isFinite() && y.isFinite()
    }
}
