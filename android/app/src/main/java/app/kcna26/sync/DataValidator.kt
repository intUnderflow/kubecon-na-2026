package app.kcna26.sync

import app.kcna26.data.Repository

/**
 * Cross-file sanity checks for a whole data set, run before a downloaded set replaces the
 * current one (and again when a downloaded set is loaded at start). Parsing with the app's own
 * DTOs already happened in [Repository.load]; this catches sets that parse but don't fit
 * together, such as a session in a room that rooms.json doesn't have, or that would break a
 * screen: duplicate keys in a lazy list (Compose throws), an empty building outline (the map
 * takes its min/max), no entrances (Directions falls back to the first one).
 */
object DataValidator {

    /**
     * Everything wrong with [repo] (empty = usable). With [includeDetails] it also parses
     * details.json (575 KB) and colocated_details.json, which a check before a swap wants and
     * app start doesn't. [files]: the set's file names (its manifest). The co-located files are
     * optional to [Repository.load], which quietly drops one that doesn't convert; a set that
     * ships them must actually deliver their events and descriptions.
     */
    fun problems(repo: Repository, includeDetails: Boolean = true, files: Collection<String> = emptyList()): List<String> {
        val out = mutableListOf<String>()
        fun check(ok: Boolean, what: () -> String) {
            if (!ok && out.size < MAX_REPORTED) out += what()
        }

        check(repo.sessions.isNotEmpty()) { "no sessions" }
        check(repo.days.isNotEmpty()) { "no days" }
        check(repo.rooms.isNotEmpty()) { "no rooms" }
        check(repo.sessionsById.size == repo.sessions.size) { "duplicate session ids" }
        val dayKeys = repo.days.mapTo(HashSet()) { it.key }
        check(dayKeys.size == repo.days.size) { "duplicate day keys" } // list keys "q-<day>", "slot-<day>-…"
        for (s in repo.sessions) {
            check(s.day in dayKeys) { "session ${s.id}: unknown day '${s.day}'" }
            // repo.room: co-located talks and breaks may be in colocated.json's own places (foyers, lunch hall).
            check(repo.room(s.room) != null) { "session ${s.id}: unknown room '${s.room}'" }
            check(s.category in repo.categories) { "session ${s.id}: unknown category '${s.category}'" }
            for (k in listOfNotNull(s.coloEvent) + s.coloEvents) {
                check(repo.coloEvent(k) != null) { "session ${s.id}: unknown co-located event '$k'" }
            }
        }

        // Co-located events (colocated.json): one card each, keyed "colo-<key>" in the list.
        if (Repository.COLOCATED in files) check(repo.coloEvents.isNotEmpty()) { "colocated.json: no usable events" }
        for (e in repo.coloEvents) {
            check(repo.room(e.mainRoom) != null) { "co-located event ${e.key}: unknown room '${e.mainRoom}'" }
            check(e.end.isAfter(e.start)) { "co-located event ${e.key}: ends before it starts" }
            check(repo.sessions.any { s -> s.coloEvent == e.key || e.key in s.coloEvents }) { "co-located event ${e.key}: no talks" }
        }

        val way = repo.wayfinding
        check(way.nodes.isNotEmpty()) { "no wayfinding nodes" }
        for (r in repo.rooms.values) {
            r.attachNode?.let { n -> check(n in way.nodes) { "room ${r.code}: unknown node '$n'" } }
        }
        for (e in way.edges) check(e.a in way.nodes && e.b in way.nodes) { "edge ${e.a}–${e.b}: unknown node" }
        for (e in way.entrances.values) check(e.node in way.nodes) { "entrance ${e.key}: unknown node '${e.node}'" }
        for (n in way.routing.lowerConcourseMerge.nodes) check(n in way.nodes) { "lowerConcourseMerge: unknown node '$n'" }
        for (n in way.nodes.values) check(n.building in repo.venue.buildings) { "node ${n.key}: unknown building '${n.building}'" }
        check(way.entrances.isNotEmpty()) { "no entrances" }
        for (b in repo.venue.buildings.values) check(b.outline.size >= 3) { "building ${b.code}: outline has ${b.outline.size} points" }

        if (includeDetails) {
            val details = repo.details
            check(details.isNotEmpty()) { "details.json is empty" }
            if (Repository.COLOCATED_DETAILS in files && repo.coloEvents.isNotEmpty()) {
                check(repo.sessions.any { it.isColocated && it.id in details }) { "colocated_details.json: no descriptions" }
            }
        }
        return out
    }

    private const val MAX_REPORTED = 20
}
