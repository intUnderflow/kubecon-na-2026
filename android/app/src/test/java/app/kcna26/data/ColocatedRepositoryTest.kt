package app.kcna26.data

import app.kcna26.TestData
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.FileNotFoundException
import java.time.OffsetDateTime

/** colocated.json merged into the Repository (sessions, events, rooms, Anthropic speakers, details). */
class ColocatedRepositoryTest {
    private val repo = TestData.repo
    private val colo = repo.sessions.filter { it.isColocated }

    private fun instant(iso: String) = OffsetDateTime.parse(iso).toInstant()

    /** A file under the repository's data/ folder (tests run with android/app/ as the working directory). */
    private fun dataFile(name: String): File? =
        listOf(File("../../data/$name"), File("../data/$name")).firstOrNull { it.isFile }

    /**
     * The real assets, with colocated.json replaced by [colocated] and colocated_details.json by
     * [details] (null: the file is missing).
     */
    private fun loadWith(
        colocated: String?,
        details: String? = TestData.text(Repository.COLOCATED_DETAILS),
    ) = Repository.load { name ->
        when (name) {
            Repository.COLOCATED -> colocated?.byteInputStream() ?: throw FileNotFoundException(name)
            Repository.COLOCATED_DETAILS -> details?.byteInputStream() ?: throw FileNotFoundException(name)
            else -> File(TestData.assetsDir, name).inputStream()
        }
    }

    private fun coloJson(): JsonObject = Repository.json.parseToJsonElement(TestData.text(Repository.COLOCATED)).jsonObject

    private fun JsonObject.with(key: String, value: kotlinx.serialization.json.JsonElement) = JsonObject(this + (key to value))

    @Test
    fun mergeCounts() {
        assertEquals(TestData.scheduleCount + 223, repo.sessions.size)
        assertEquals(223, colo.size)
        assertEquals(212, colo.count { it.category == "colo" }) // talks
        assertEquals(10, colo.count { it.category == "log" }) // breaks
        assertEquals(1, colo.count { it.category == "soc" }) // the Evening Reception
        assertTrue(colo.all { it.day == "mon" && it.event == Session.EVENT_COLOCATED })
        // Events, the placeholders they replace, rooms.
        assertEquals(11, repo.coloEvents.size)
        assertEquals(repo.coloEvents.map { it.name }.sortedWith(String.CASE_INSENSITIVE_ORDER), repo.coloEvents.map { it.name })
        assertEquals(212, repo.coloEvents.sumOf { it.talkCount })
        assertEquals(11, repo.supersededIds.size)
        assertEquals(40, TestData.venueRooms.size) // rooms.json only: the walking graph's rooms are unchanged
        assertEquals(setOf("FOY", "LCH4"), repo.extraRooms.keys)
        assertTrue(repo.extraRooms.values.none { it.hasPosition })
        // Details: every co-located session is bundled.
        assertEquals(TestData.detailsCount + 223, repo.details.size)
        assertTrue(colo.all { it.id in repo.details })
    }

    @Test
    fun idsAreUniqueAcrossTheMergedList() {
        assertEquals(repo.sessions.size, repo.sessions.map { it.id }.toSet().size)
        assertEquals(repo.sessions.size, repo.sessionsById.size)
        // A co-located id that collides with schedule.json is dropped, keeping schedule.json's session.
        val root = coloJson()
        val sessions = root.getValue("sessions").jsonArray
        val first = sessions[0].jsonObject
        val clash = JsonObject(first + ("id" to JsonPrimitive("1289955"))) // a Project Lightning Talk
        val loaded = loadWith(root.with("sessions", JsonArray(listOf(clash) + sessions.drop(1))).toString())
        assertEquals(TestData.scheduleCount + 223 - 1, loaded.sessions.size)
        assertEquals(loaded.sessions.size, loaded.sessionsById.size)
        assertEquals("kubecon", loaded.session("1289955")!!.event)
    }

    @Test
    fun sessionsKeepTheirCoLocatedFields() {
        val talk = repo.session("1311951")!! // ArgoCon Project Update, 9:10 in Room 151
        assertEquals("colo-argocon", talk.coloEvent)
        assertEquals(listOf("colo-argocon"), talk.coloEvents)
        assertEquals(SessionGroup("colo-argocon", "ArgoCon"), talk.group)
        assertEquals("151", talk.room)
        assertEquals(instant("2026-11-09T09:10:00-07:00"), talk.start)
        assertEquals("Breakout", talk.format)
        assertTrue(talk.isColocated)
        assertFalse(talk.isMaintainerSummit)
        assertNull(talk.note)
        assertTrue(talk.officialUrl.endsWith("cncf-hosted-co-located-schedule/?id=1311951"))
        val keynote = repo.session("1311945")!!
        assertEquals("Keynote", keynote.format)
        assertTrue(keynote.sponsored)
        assertTrue(colo.count { it.slidesUrl != null } > 0)
        assertTrue(colo.count { it.topic != null } > 0)
        // A shared break serves several events; one event's own break names it.
        val lunch = repo.session("1309415")!!
        assertEquals("log", lunch.category)
        assertNull(lunch.coloEvent)
        assertEquals(4, lunch.coloEvents.size)
        assertEquals("colo-ciliumcon", repo.session("1309414")!!.coloEvent)
        // The reception is an ordinary session.
        val reception = repo.session("1309453")!!
        assertEquals("soc", reception.category)
        assertTrue(reception.coloEvents.isEmpty())
        assertEquals("UM", reception.room)
        // schedule.json sessions have none of it.
        assertTrue(repo.sessions.filter { !it.isColocated }.all { it.coloEvent == null && it.coloEvents.isEmpty() && it.format == null })
    }

    @Test
    fun eventsAndThePlaceholdersTheyReplace() {
        val argo = repo.coloEvent("colo-argocon")!!
        assertEquals("ArgoCon", argo.name)
        assertEquals("mon", argo.day)
        assertEquals("151", argo.mainRoom)
        assertEquals(listOf("151", "251AC"), argo.rooms)
        assertEquals(instant("2026-11-09T09:00:00-07:00"), argo.start)
        assertEquals(instant("2026-11-09T17:45:00-07:00"), argo.end) // the agenda, not the placeholder's 5:30
        assertFalse(argo.halfDay)
        assertEquals("All-Access pass", argo.passNote)
        assertEquals("1289755", argo.supersedes)
        val placeholder = repo.session("1289755")!!
        assertEquals("All-Access pass", placeholder.note)
        assertEquals(placeholder.officialUrl, argo.infoUrl)
        assertTrue(argo.pageUrl!!.endsWith("/co-located-events/argocon/"))
        assertTrue(repo.coloEvent("colo-ciliumcon")!!.halfDay)
        for (e in repo.coloEvents) {
            // Every placeholder still exists (an old saved id still opens) and sits in the event's main room.
            val p = repo.session(e.supersedes!!)!!
            assertEquals(e.name, "All-Access pass", p.note)
            assertEquals(e.name, e.mainRoom, p.room)
            // The card's hours are its talks' (first start to last end).
            val talks = colo.filter { it.coloEvent == e.key && it.category == "colo" }
            assertEquals(e.name, e.talkCount, talks.size)
            assertEquals(e.name, talks.minOf { it.start }, e.start)
            assertEquals(e.name, talks.maxOf { it.effectiveEnd }, e.end)
            assertTrue(e.name, talks.all { it.group == SessionGroup(e.key, e.name) })
        }
    }

    @Test
    fun everyRoomResolvesAndNewPlacesHaveNoPosition() {
        assertTrue(repo.sessions.all { repo.room(it.room) != null && repo.roomOf(it) != null })
        val foy = repo.room("FOY")!!
        assertEquals("Meeting room foyers", foy.name)
        assertFalse(foy.hasPosition)
        assertNotNull(foy.whereText)
        assertEquals(1, repo.room("LCH4")!!.level)
        // Co-located talks are all in rooms.json rooms with a position (Directions work).
        assertTrue(colo.filter { it.category == "colo" }.all { it.room in repo.rooms && repo.room(it.room)!!.hasPosition })
    }

    @Test
    fun anthropicSpeakersAndMineAtRuntime() {
        assertTrue("Jiazhou Gao" in repo.anthropicSpeakers)
        assertTrue("Lucy Sweet" in repo.anthropicSpeakers)
        val gao = repo.session("1245135")!!
        assertTrue(repo.hasAnthropic(gao, "Lucy Sweet"))
        assertTrue(isMine(gao, "Jiazhou Gao"))
        assertFalse(repo.hasAnthropic(gao, "Jiazhou Gao"))
        // The precomputed flags agree with the runtime rule for the default setting.
        for (s in colo) {
            assertEquals(s.id, s.precomputedIsMine, isMine(s, "Lucy Sweet"))
            assertEquals(s.id, s.precomputedHasAnthropic, repo.hasAnthropic(s, "Lucy Sweet"))
        }
        // The details carry the tagline.
        assertEquals("Member of Technical Staff at Anthropic", repo.details.getValue("1245135").speakers[0].tagline)
        // Co-located speakers are pickable.
        assertTrue("Katie Lamkin-Fulsher" in repo.allSpeakers)
        assertEquals(3, repo.mySessions("Katie Lamkin-Fulsher").size)
    }

    @Test
    fun assetsMatchTheDataFolder() {
        for (name in listOf(Repository.COLOCATED, Repository.COLOCATED_DETAILS)) {
            val data = dataFile(name) ?: error("data/$name not found")
            assertEquals(name, data.readText(), TestData.text(name))
        }
    }

    @Test
    fun theDetailsAreAFileOfTheirOwnReadOnlyWhenNeeded() {
        // colocated.json, which the splash waits for, carries no descriptions: they're in
        // colocated_details.json, read lazily with details.json.
        val main = coloJson()
        assertFalse("details" in main)
        val details = Repository.json.parseToJsonElement(TestData.text(Repository.COLOCATED_DETAILS)).jsonObject
            .getValue("details").jsonObject
        assertEquals(main.getValue("sessions").jsonArray.map { it.jsonObject.getValue("id").jsonPrimitive.content }, details.keys.toList())
        // Loading opens colocated_details.json only when the details are first used.
        val opened = ArrayList<String>()
        val r = Repository.load { name -> opened += name; File(TestData.assetsDir, name).inputStream() }
        assertFalse(Repository.COLOCATED_DETAILS in opened)
        assertFalse(Repository.DETAILS in opened)
        assertEquals(TestData.scheduleCount + 223, r.sessions.size)
        assertEquals(TestData.detailsCount + 223, r.details.size)
        assertTrue(Repository.COLOCATED_DETAILS in opened)
        assertEquals(1, opened.count { it == Repository.COLOCATED })
        // Without it (or unreadable), the co-located sessions still load; they just have no descriptions.
        for (text in listOf(null, "{ not json")) {
            val bare = loadWith(TestData.text(Repository.COLOCATED), text)
            assertEquals(TestData.scheduleCount + 223, bare.sessions.size)
            assertEquals(11, bare.coloEvents.size)
            assertEquals(TestData.detailsCount, bare.details.size)
            assertNull(bare.details["1245135"])
        }
    }

    @Test
    fun theScheduleStillLoadsWithoutColocatedJson() {
        val badDate = TestData.text(Repository.COLOCATED).replaceFirst("\"start\": \"2026-11-09T09:00:00-07:00\"", "\"start\": \"9 AM Monday\"")
        assertTrue(badDate != TestData.text(Repository.COLOCATED))
        for (text in listOf(null, "{ not json", badDate)) {
            val r = loadWith(text)
            assertEquals(TestData.scheduleCount, r.sessions.size)
            assertTrue(r.coloEvents.isEmpty())
            assertTrue(r.supersededIds.isEmpty())
            assertTrue(r.extraRooms.isEmpty())
            assertEquals(TestData.detailsCount, r.details.size)
            assertFalse("Jiazhou Gao" in r.anthropicSpeakers)
            // Monday is as it was before the co-located cards: the All-Access events are back in the
            // "Co-located + off-site" section at the top of the day, not labelled sponsor-hosted.
            val mon = app.kcna26.schedule.ScheduleIndex(r).dayView("mon", instant("2026-11-09T08:00:00-07:00"), "Lucy Sweet")!!
            assertTrue(mon.colo.isEmpty())
            assertEquals("Co-located + off-site", mon.longsTitle)
            assertTrue(mon.longsFirst)
            assertEquals(11, mon.longs.count { it.session.note == "All-Access pass" })
        }
    }

    @Test
    fun anEventWithoutItsPlaceholderSupersedesNothing() {
        val root = coloJson()
        val events = root.getValue("events").jsonArray.map { e ->
            val o = e.jsonObject
            if (o.getValue("key").jsonPrimitive.content == "colo-argocon") JsonObject(o + ("supersedes" to JsonPrimitive("nope"))) else o
        }
        val r = loadWith(root.with("events", JsonArray(events)).toString())
        assertEquals(10, r.supersededIds.size)
        assertFalse("1289755" in r.supersededIds)
    }
}
