package app.kcna26.route

import app.kcna26.TestData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.util.zip.CRC32

/**
 * Every route the web version can produce, compared with what the web's own `route` and
 * `lvStartNode` return (golden/web_routes.txt and golden/web_live.txt, written by
 * golden/gen_web_golden.js from reference/schedule.html; see that script for the format).
 *
 * - 43 starts (4 entrances, 39 rooms) × 39 rooms = 1677 routes: step kinds, a CRC of the
 *   step texts, polyline length (±0.01 m), point count and levelsChanged.
 * - One deliberate difference: REG and COAT are missing from the web's `R` name table, so
 *   starting from them the web says "Start at REG, then …" where the app uses the room
 *   name. Neither is in the From picker (no session uses them).
 * - 756 live positions on a 30 m grid around the venue: start node, start key, start text
 *   and the live route to a rotating destination.
 * - Another deliberate difference: the app has no Google Maps button, so the outside start
 *   ("Head to the {entrance}, about N m {direction} of you.") drops the web's last sentence,
 *   "The Google Maps button above walks you there." gen_web_golden.js strips it from the web
 *   code before computing the CRCs.
 */
class WebParityTest {
    private val repo = TestData.repo
    private val router = Router(repo)

    private fun golden(name: String): List<List<String>> {
        val f = listOf(File("src/test/java/app/kcna26/route/golden/$name"), File("app/src/test/java/app/kcna26/route/golden/$name"))
            .first { it.isFile }
        return f.readLines().filter { it.isNotBlank() }.map { it.split('|') }
    }

    private fun crc(texts: List<String>): String {
        val c = CRC32()
        c.update(texts.joinToString("\n").toByteArray(Charsets.UTF_8))
        return "%08x".format(c.value)
    }

    private fun kinds(r: Route): String = r.steps.joinToString("") { it.kind.wire.take(1) }

    /** Compares a route with golden columns [m, dl, kinds, crc, points]; returns a mismatch description or null. */
    private fun mismatch(r: Route?, g: List<String>, webTexts: (List<String>) -> List<String> = { it }): String? {
        if (r == null) return "no route"
        val (m, dl, k, c, n) = g
        return when {
            abs(r.totalM - m.toDouble()) > 0.01 -> "totalM ${r.totalM} vs $m"
            r.levelsChanged != dl.toInt() -> "levelsChanged ${r.levelsChanged} vs $dl"
            kinds(r) != k -> "kinds ${kinds(r)} vs $k"
            crc(webTexts(r.steps.map { it.text })) != c -> "texts differ:\n" + r.steps.joinToString("\n") { "  ${it.kind.wire}: ${it.text}" }
            r.points.size != n.toInt() -> "points ${r.points.size} vs $n"
            else -> null
        }
    }

    private fun abs(d: Double) = kotlin.math.abs(d)

    private companion object {
        /** Rooms the web has no display name for (not in its `R` table). */
        val WEB_UNNAMED = setOf("REG", "COAT")
    }

    @Test
    fun everyEntranceAndRoomRouteMatchesTheWeb() {
        val lines = golden("web_routes.txt")
        assertEquals(43 * 39, lines.size)
        val errors = ArrayList<String>()
        for (g in lines) {
            val (from, to) = g
            val start = if (repo.wayfinding.entrances.containsKey(from)) RouteFrom.Entrance(from) else RouteFrom.Room(from)
            val r = router.route(start, to)
            val webTexts: (List<String>) -> List<String> = if (from in WEB_UNNAMED && from != to) {
                val name = repo.room(from)!!.name
                { texts -> listOf(texts[0].replaceFirst("Start at $name,", "Start at $from,")) + texts.drop(1) }
            } else {
                { it }
            }
            if (from in WEB_UNNAMED && from != to) assertTrue(r!!.steps[0].text.startsWith("Start at ${repo.room(from)!!.name}, then step out to the "))
            mismatch(r, g.drop(2), webTexts)?.let { errors += "$from → $to: $it" }
        }
        if (errors.isNotEmpty()) fail("${errors.size} routes differ from the web, first: ${errors.take(3).joinToString("\n")}")
    }

    @Test
    fun liveStartsAndRoutesMatchTheWeb() {
        val lines = golden("web_live.txt")
        assertTrue(lines.size > 700)
        val errors = ArrayList<String>()
        for (g in lines) {
            val x = g[0].toDouble()
            val y = g[1].toDouble()
            val st = router.myLocationStart(x, y)
            val where = "($x, $y)"
            if (st.node != g[2]) errors += "$where start node ${st.node} vs ${g[2]}"
            if (st.key != g[3]) errors += "$where start key ${st.key} vs ${g[3]}"
            if (crc(listOf(st.text)) != g[4]) errors += "$where start text: ${st.text}"
            val r = router.route(RouteFrom.MyLocation(x, y, 10.0), g[5])
            mismatch(r, g.drop(6))?.let { errors += "$where → ${g[5]}: $it" }
            if (r != null && (!r.live || r.start != st)) errors += "$where → ${g[5]}: live ${r.live} start ${r.start}"
        }
        if (errors.isNotEmpty()) fail("${errors.size} live mismatches, first: ${errors.take(3).joinToString("\n")}")
    }
}
