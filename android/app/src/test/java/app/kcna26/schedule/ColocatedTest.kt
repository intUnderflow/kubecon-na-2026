package app.kcna26.schedule

import app.kcna26.TestData
import app.kcna26.data.Repository
import app.kcna26.reminders.ReminderPlanner
import app.kcna26.time.FixedClock
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.Instant

/** The Monday "Co-located events" cards: lines, agendas, hiding, de-duplication, search, mine/Anthropic. */
class ColocatedTest {
    private val repo = TestData.repo
    private val idx = ScheduleIndex.of(repo)
    private val lucy = "Lucy Sweet"

    private fun at(iso: String): Instant = FixedClock.parse(iso).now()
    private fun cards(iso: String, me: String? = lucy) = idx.dayView("mon", at(iso), me)!!.colo
    private fun card(key: String, iso: String, me: String? = lucy) = cards(iso, me).single { it.key == key }
    private fun lines(key: String, iso: String) = card(key, iso).lines.map { ColoText.text(it, idx::roomName) }

    private fun DayView.blockSessions() = slots.flatMap { sl ->
        sl.blocks.flatMap { b ->
            when (b) {
                is SessionBlock -> listOf(b.session)
                is GroupBlock -> b.kids
            }
        }
    }

    // ------------------------------------------------------------ cards

    @Test
    fun oneCardPerEventAlphabeticalWithHoursAndMainRoom() {
        val all = cards("2026-11-09T08:00:00-07:00")
        assertEquals(
            listOf(
                "Agentics Day: MCP + Agents", "ArgoCon", "BackstageCon", "CiliumCon", "Cloud Native AI + Inference Day",
                "FluxCon", "Kubernetes on Edge Day", "Observability Day", "Open Source SecurityCon", "OpenTofu Day",
                "Platform Engineering Day",
            ),
            all.map { it.event.name },
        )
        val argo = all.single { it.key == "colo-argocon" }
        assertEquals("9:00 AM–5:45 PM", argo.hours)
        assertEquals("Room 151", idx.roomName(argo.event.mainRoom))
        assertEquals("Salt Palace L1", idx.building(argo.event.mainRoom))
        assertEquals("Half day · 9:00 AM–12:30 PM", all.single { it.key == "colo-ciliumcon" }.hours)
        assertEquals("Half day · 1:20–5:30 PM", all.single { it.key == "colo-kubernetes-on-edge-day" }.hours)
        assertEquals(listOf("Half day", "9:00 AM–12:30 PM"), ColoText.hoursParts(repo.coloEvent("colo-ciliumcon")!!))
        assertEquals(listOf("9:00 AM–5:45 PM"), ColoText.hoursParts(argo.event))
        // Other days have no co-located section.
        for (d in listOf("sun", "tue", "wed", "thu")) assertTrue(d, idx.dayView(d, at("2026-11-08T08:00:00-07:00"), lucy)!!.colo.isEmpty())
    }

    @Test
    fun beforeTheEventItSaysWhenItStartsAndTheFirstRealTalk() {
        // The opening remarks (9:00) are skipped: the first talk is the 9:10 project update, and the
        // line says so rather than pairing 9:00 with a talk that starts at 9:10.
        val first = "Starts 9:00 AM · First talk 9:10 · ArgoCon Project Update"
        assertEquals(listOf(first), lines("colo-argocon", "2026-11-09T08:00:00-07:00"))
        // The day before, too.
        assertEquals(listOf(first), lines("colo-argocon", "2026-11-08T20:00:00-07:00"))
        // An afternoon half day during the morning.
        val edge = card("colo-kubernetes-on-edge-day", "2026-11-09T11:00:00-07:00")
        val st = edge.lines.single() as ColoLine.Starts
        assertEquals(at("2026-11-09T13:20:00-07:00"), st.at)
        assertFalse(ColoText.isRemarks(st.session!!))
        assertTrue(ColoText.label(st, idx::roomName).startsWith("Starts 1:20 PM · First talk "))
        assertFalse(edge.live)
        // Every event opens with remarks, so every card names its first real talk with that talk's time.
        for (c in cards("2026-11-09T08:00:00-07:00")) {
            val line = c.lines.single() as ColoLine.Starts
            val talk = line.session!!
            val label = ColoText.label(line, idx::roomName)
            if (talk.start.isAfter(line.at)) {
                assertTrue(c.key, label.endsWith("· First talk " + app.kcna26.time.TimeFormat.hm(talk.start)))
            } else {
                assertEquals(c.key, "Starts " + app.kcna26.time.TimeFormat.hma(line.at), label)
            }
        }
    }

    @Test
    fun duringATalkItSaysNowWithMinutesLeftThenNext() {
        val c = card("colo-argocon", "2026-11-09T09:20:00-07:00")
        assertTrue(c.live)
        assertEquals(
            listOf(
                "Now · 15 min left · ArgoCon Project Update",
                "Next 9:45 · Pets, Cattle, and Herds: Fleet-Scale Continuous Delivery the GitOps Way",
            ),
            c.lines.map { ColoText.text(it, idx::roomName) },
        )
        val now = c.lines[0] as ColoLine.Now
        assertEquals("1311951", now.session.id)
        assertEquals(15L, now.minutesLeft)
        assertNull(now.room) // main room
        // The welcome remarks are "Now" while they're on.
        assertEquals("Now · 5 min left · Welcome + Opening Remarks", lines("colo-argocon", "2026-11-09T09:00:00-07:00")[0])
    }

    @Test
    fun twoTracksGiveOneNowLineMainRoomFirstThenNext() {
        // A collapsed card stays compact: one "Now" line (the main room's talk) and "Next"; the
        // second room's talk is in the agenda.
        val c = card("colo-argocon", "2026-11-09T10:50:00-07:00")
        assertEquals(
            listOf(
                "Now · 15 min left · Beating the Final Boss: GitOps Promoter in Production",
                "Next 11:15 · Securing the Repo Server: A Practical Guide to Argo CD’s New Native mTLS",
            ),
            c.lines.map { ColoText.text(it, idx::roomName) },
        )
        assertTrue(c.agenda.any { it.room == "251AC" && it.live })
        // Only the second room has a talk on (Observability Day, 5:10 PM): the Now line names that room.
        val obs = card("colo-observability-day", "2026-11-09T17:10:00-07:00")
        val now = obs.lines.first() as ColoLine.Now
        assertEquals("1239971", now.session.id)
        assertEquals("250DF", now.room)
        // All day long, on every card: at most two lines, at most one of them "Now".
        var t = at("2026-11-08T20:00:00-07:00")
        while (t.isBefore(at("2026-11-09T18:00:00-07:00"))) {
            for (k in idx.dayView("mon", t, lucy)!!.colo) {
                assertTrue("${k.key} $t", k.lines.size <= 2)
                assertTrue("${k.key} $t", k.lines.count { it is ColoLine.Now } <= 1)
            }
            t = t.plusSeconds(5 * 60)
        }
    }

    @Test
    fun inAGapItSaysWhatsNextAndNamesTheBreakIfOneIsOn() {
        // 9:37: the project update ended at 9:35; nothing on until 9:45.
        assertEquals(
            listOf("Next 9:45 · Pets, Cattle, and Herds: Fleet-Scale Continuous Delivery the GitOps Way"),
            lines("colo-argocon", "2026-11-09T09:37:00-07:00"),
        )
        // ArgoCon's coffee break (10:15–10:40) and lunch (11:40–12:45). At equal starts the main room comes first.
        assertEquals(
            listOf("Coffee Break · Next 10:40 · Beating the Final Boss: GitOps Promoter in Production"),
            lines("colo-argocon", "2026-11-09T10:20:00-07:00"),
        )
        val lunch = card("colo-argocon", "2026-11-09T12:00:00-07:00")
        assertFalse(lunch.live)
        val next = lunch.lines.single() as ColoLine.Next
        assertEquals("Lunch", next.during)
        assertEquals("12:55", app.kcna26.time.TimeFormat.hm(next.session.start))
    }

    @Test
    fun cardsDisappearWhenTheirEventEnds() {
        // CiliumCon (half day) ends at 12:30 with its closing remarks; its lunch starts then.
        val cilium = card("colo-ciliumcon", "2026-11-09T12:29:00-07:00")
        assertEquals("Now · 1 min left · Closing Remarks", ColoText.text(cilium.lines.single(), idx::roomName))
        assertEquals(listOf("Closing Remarks", "🍲 Lunch"), cilium.agenda.map { it.session.title })
        assertTrue(cards("2026-11-09T12:30:00-07:00").none { it.key == "colo-ciliumcon" })
        // ArgoCon is the last to end (5:45 PM); then the section is empty and the day goes on with the blocks.
        assertEquals(listOf("colo-argocon"), cards("2026-11-09T17:30:00-07:00").map { it.key })
        assertEquals(1, cards("2026-11-09T17:44:00-07:00").size)
        assertTrue(cards("2026-11-09T17:45:00-07:00").isEmpty())
        val evening = idx.dayView("mon", at("2026-11-09T17:45:00-07:00"), lucy)!!
        assertFalse(evening.isEmpty) // the reception and the documentary are still to come
        assertTrue(idx.dayView("mon", at("2026-11-09T23:00:00-07:00"), lucy)!!.isEmpty)
    }

    @Test
    fun aBreakThatOutlivesItsEventJoinsTheTimeBlocks() {
        // CiliumCon ends at 12:30 as its lunch (12:30–1:30, LCH4) starts; FluxCon's lunch starts at its 12:55 end.
        // While the event is on, its break is only in its card; once the card has gone it's a quiet block row.
        val before = idx.dayView("mon", at("2026-11-09T12:29:00-07:00"), lucy)!!
        assertTrue(before.colo.single { it.key == "colo-ciliumcon" }.holds("1309414"))
        assertTrue(before.blockSessions().none { it.isColocated && idx.isBreak(it) })
        val at1230 = idx.dayView("mon", at("2026-11-09T12:30:00-07:00"), lucy)!!
        assertTrue(at1230.colo.none { it.key == "colo-ciliumcon" })
        assertEquals(listOf("1309414"), at1230.blockSessions().filter { it.isColocated && idx.isBreak(it) }.map { it.id })
        val row = at1230.slots.flatMap { it.blocks }.filterIsInstance<SessionBlock>().single { it.session.id == "1309414" }
        assertEquals("log", row.category)
        val at1255 = idx.dayView("mon", at("2026-11-09T12:55:00-07:00"), lucy)!!
        assertTrue(at1255.colo.none { it.key == "colo-fluxcon" })
        assertEquals(listOf("1309414", "1309427"), at1255.blockSessions().filter { it.isColocated && idx.isBreak(it) }.map { it.id })
        // The shared lunch that's on (12:25–1:30) serves events that are still on: it stays in their cards.
        assertTrue(at1255.blockSessions().none { it.id == "1309413" })
        val shared = repo.session("1309413")!!.coloEvents
        assertEquals(3, at1255.colo.count { it.key in shared && it.holds("1309413") })
        // Finished breaks go, as usual.
        assertTrue(idx.dayView("mon", at("2026-11-09T13:30:00-07:00"), lucy)!!.blockSessions().none { it.isColocated && idx.isBreak(it) })
        // No co-located talk ever falls into the blocks: an unfinished talk's event is always on.
        var t = at("2026-11-09T08:00:00-07:00")
        while (t.isBefore(at("2026-11-09T18:00:00-07:00"))) {
            val blocks = idx.dayView("mon", t, lucy)!!.blockSessions()
            assertTrue("$t", blocks.none { it.isColocated && idx.category(it) == "colo" })
            t = t.plusSeconds(5 * 60)
        }
    }

    @Test
    fun agendaHidesFinishedTalksKeepsBreaksQuietAndNamesOtherRooms() {
        val c = card("colo-argocon", "2026-11-09T10:50:00-07:00")
        val now = at("2026-11-09T10:50:00-07:00")
        assertTrue(c.agenda.none { ScheduleLogic.isFinished(it.session, now) })
        assertEquals(c.agenda.map { it.session.start }.sorted(), c.agenda.map { it.session.start })
        assertEquals("1269659", c.agenda[0].session.id) // 151 before 251 A–C at 10:40
        assertNull(c.agenda[0].room)
        assertEquals("251AC", c.agenda[1].room)
        assertTrue(c.agenda[0].live && c.agenda[1].live)
        val breaks = c.agenda.filter { it.isBreak }
        assertEquals(listOf("🍲 Lunch", "☕ Coffee Break"), breaks.map { it.session.title })
        assertEquals(listOf("LCH4", "FOY"), breaks.map { it.room }) // breaks always say where
        // Every agenda row is a real session the details can open; ArgoCon's talks are all there at 8 AM.
        val morning = card("colo-argocon", "2026-11-09T08:00:00-07:00")
        assertEquals(29, morning.agenda.count { !it.isBreak })
        assertTrue(morning.agenda.all { repo.session(it.session.id) != null })
    }

    // ------------------------------------------------------------ time blocks and hiding

    @Test
    fun placeholdersAreNeverShown() {
        val placeholders = repo.supersededIds
        assertEquals(11, placeholders.size)
        for (iso in listOf("2026-11-08T12:00:00-07:00", "2026-11-09T08:00:00-07:00", "2026-11-09T13:00:00-07:00")) {
            val mon = idx.dayView("mon", at(iso), lucy)!!
            val shown = (mon.blockSessions() + mon.longs.map { it.session }).map { it.id }
            assertTrue(iso, shown.none { it in placeholders })
        }
        assertTrue(idx.search("argocon", at("2026-11-09T08:00:00-07:00"), lucy).days.flatMap { it.sessions }.none { it.session.id in placeholders })
        assertTrue(idx.search("all-access", at("2026-11-09T08:00:00-07:00"), lucy).days.flatMap { it.sessions }.none { it.session.id in placeholders })
        assertTrue(placeholders.all { idx.isHidden(repo.session(it)!!) })
        // Still loadable by id (an old saved selection opens rather than vanishing).
        assertNotNull(repo.session("1289755"))
    }

    @Test
    fun coLocatedTalksAndBreaksStayOutOfTheTimeBlocks() {
        val mon = idx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy)!!
        val inBlocks = mon.blockSessions()
        // Only the Evening Reception (an ordinary social session) comes from colocated.json.
        assertEquals(listOf("1309453"), inBlocks.filter { it.isColocated }.map { it.id })
        assertEquals("soc", idx.category(repo.session("1309453")!!))
        // No group card for an event: they're the cards above.
        assertTrue(mon.slots.flatMap { it.blocks }.filterIsInstance<GroupBlock>().none { it.group.key.startsWith("colo-") })
        assertTrue(idx.groups.keys.none { it.startsWith("colo-") })
        // Status line still counts the co-located talks on now.
        val ten = idx.dayView("mon", at("2026-11-09T10:50:00-07:00"), lucy)!!
        assertTrue(ten.status!!.onNow > 10)
    }

    @Test
    fun breaksAreDeDuplicated() {
        // Real data: Monday's own break rows (the Project Lightning Talks') show once each and the
        // co-located breaks only inside their events' cards: in every card of an event they serve.
        val mon = idx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy)!!
        val blockBreaks = mon.blockSessions().filter { idx.isBreak(it) }
        assertEquals(listOf("1352094", "1339249", "1368701"), blockBreaks.map { it.id })
        val coloBreaks = repo.sessions.filter { it.isColocated && idx.isBreak(it) }
        assertEquals(10, coloBreaks.size)
        for (b in coloBreaks) {
            for (key in b.coloEvents) {
                assertEquals("${b.id} in $key", 1, mon.colo.single { it.key == key }.agenda.count { it.session.id == b.id })
            }
            val others = mon.colo.filter { it.key !in b.coloEvents }
            assertTrue(b.id, others.none { c -> c.agenda.any { it.session.id == b.id } })
        }

        // A co-located break that is the same break as a day's own row (same start, end and title,
        // emoji aside) shows once, as that quiet row; one that isn't joins the blocks.
        val root = Repository.json.parseToJsonElement(TestData.text(Repository.COLOCATED)).jsonObject
        val template = root.getValue("sessions").jsonArray.first { it.jsonObject["id"] == JsonPrimitive("1309409") }.jsonObject
        fun brk(id: String, start: String, end: String, title: String) = JsonObject(
            template + mapOf(
                "id" to JsonPrimitive(id), "start" to JsonPrimitive(start), "end" to JsonPrimitive(end),
                "title" to JsonPrimitive(title), "coloEvent" to kotlinx.serialization.json.JsonNull,
                "coloEvents" to JsonArray(emptyList()),
            ),
        )
        val same = brk("9000001", "2026-11-09T10:48:00-07:00", "2026-11-09T11:03:00-07:00", "Coffee Break")
        val other = brk("9000002", "2026-11-09T16:00:00-07:00", "2026-11-09T16:15:00-07:00", "☕ Coffee Break")
        val sessions = JsonArray(root.getValue("sessions").jsonArray + same + other)
        val text = JsonObject(root + ("sessions" to sessions)).toString()
        val synthetic = Repository.load { name ->
            if (name == Repository.COLOCATED) text.byteInputStream() else File(TestData.assetsDir, name).inputStream()
        }
        val sIdx = ScheduleIndex(synthetic)
        val day = sIdx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy)!!
        val rows = day.blockSessions().filter { sIdx.isBreak(it) }.map { it.id }
        assertEquals(listOf("1352094", "1339249", "1368701", "9000002"), rows) // 10:48 once; 4:00 PM joins
        assertNotNull(synthetic.session("9000001")) // loaded, just not shown twice
    }

    // ------------------------------------------------------------ search

    @Test
    fun searchFindsEveryTalkOfAnEventByItsName() {
        fun hits(q: String, iso: String = "2026-11-09T08:00:00-07:00") =
            idx.search(q, at(iso), lucy).days.flatMap { it.sessions }.map { it.session }
        val argo = hits("argocon")
        val argoTalks = repo.sessions.filter { it.coloEvent == "colo-argocon" && it.category == "colo" }
        assertEquals(29, argoTalks.size)
        assertTrue(argoTalks.all { it in argo })
        assertTrue(argo.none { idx.isBreak(it) })
        assertTrue(argoTalks.all { idx.coloEventOf(it)?.name == "ArgoCon" }) // the result rows' eyebrow
        // Case, accents and several terms: "ARGOCON 251" = ArgoCon's second-track talks.
        val track2 = hits("ARGOCON 251")
        assertTrue(track2.isNotEmpty())
        assertTrue(track2.all { it.coloEvent == "colo-argocon" && it.room == "251AC" })
        assertEquals(argoTalks.count { it.room == "251AC" }, track2.size)
        // Every event, by name; finished talks drop out as the day goes.
        for (e in repo.coloEvents) {
            val n = hits(e.name).count { it.coloEvent == e.key }
            assertEquals(e.name, e.talkCount, n)
        }
        assertTrue(hits("argocon", "2026-11-09T12:00:00-07:00").size < argo.size)
        assertTrue(hits("argocon", "2026-11-09T18:00:00-07:00").none { it.coloEvent == "colo-argocon" })
        // Topic, format and speakers work as usual.
        val lightning = hits("lightning argocon")
        assertEquals(argoTalks.count { it.format == "Lightning talk" }, lightning.count { it.format == "Lightning talk" })
        assertTrue(hits("lamkin").any { it.id == "1312032" })
        val withTopic = repo.sessions.first { it.isColocated && it.topic != null }
        assertTrue(hits(withTopic.topic!!).any { it.id == withTopic.id })
    }

    // ------------------------------------------------------------ mine and Anthropic

    @Test
    fun anthropicColleagueInsideACard() {
        // Jiazhou Gao (Anthropic) on Cloud Native AI + Inference Day, 2:05 PM in 254.
        val ai = card("colo-cloud-native-ai-inference-day", "2026-11-09T08:00:00-07:00")
        assertTrue(ai.anthropic)
        assertFalse(ai.mine)
        val row = ai.agenda.single { it.session.id == "1245135" }
        assertTrue(row.anthropic)
        assertFalse(row.mine)
        assertTrue(ai.agenda.filter { it.session.id != "1245135" }.none { it.anthropic })
        // Once the talk is over the card no longer carries the mark.
        assertFalse(card("colo-cloud-native-ai-inference-day", "2026-11-09T14:30:00-07:00").anthropic)
        // Only that card has it; "anthropic" search finds the talk.
        assertEquals(listOf("colo-cloud-native-ai-inference-day"), cards("2026-11-09T08:00:00-07:00").filter { it.anthropic }.map { it.key })
        assertTrue(idx.search("anthropic", at("2026-11-09T08:00:00-07:00"), lucy).days.flatMap { it.sessions }.any { it.session.id == "1245135" && it.anthropic })
    }

    @Test
    fun myCoLocatedTalksAreMineEverywhere() {
        val katie = "Katie Lamkin-Fulsher" // ArgoCon: opening remarks 9:00, a keynote 9:55, closing remarks 5:40
        val argo = card("colo-argocon", "2026-11-09T08:00:00-07:00", katie)
        assertTrue(argo.mine)
        assertEquals(listOf("1312032", "1311947", "1312052"), argo.agenda.filter { it.mine }.map { it.session.id })
        assertTrue(argo.agenda.filter { it.mine }.none { it.anthropic })
        assertEquals(listOf("colo-argocon"), cards("2026-11-09T08:00:00-07:00", katie).filter { it.mine }.map { it.key })
        // Still mine at noon (the closing remarks are to come); the YOU badge on Monday's tab and the banner follow.
        assertTrue(card("colo-argocon", "2026-11-09T12:00:00-07:00", katie).mine)
        assertTrue(idx.dayTabs(at("2026-11-09T08:00:00-07:00"), katie).single { it.key == "mon" }.hasMine)
        val b = idx.banner("mon", at("2026-11-09T08:00:00-07:00"), katie)!!
        assertEquals("1312032", b.next.id)
        assertEquals("Room 151 · Salt Palace L1", b.nextWhere)
        assertEquals(listOf("1311947", "1312052"), b.later.map { it.session.id })
        assertEquals(listOf("9:55 AM", "5:40 PM"), b.later.map { it.time })
        // Reminders cover any session that's mine.
        val plan = ReminderPlanner.plan(repo.sessions, repo.rooms, katie, at("2026-11-09T08:00:00-07:00"))
        assertEquals(setOf("1312032", "1311947", "1312052"), plan.map { it.sessionId }.toSet())
        assertEquals(6, plan.size) // 30 and 10 min before each
        assertEquals("Your talk in 10 min · Room 151, Level 1", plan.first { it.minutesBefore == 10 }.text)
        // The default speaker (Lucy) has nothing on Monday.
        assertTrue(cards("2026-11-09T08:00:00-07:00").none { it.mine })
        assertNull(idx.banner("mon", at("2026-11-09T08:00:00-07:00"), lucy))
        // As Jiazhou Gao: the talk is mine, not an Anthropic colleague's.
        val gao = card("colo-cloud-native-ai-inference-day", "2026-11-09T08:00:00-07:00", "Jiazhou Gao")
        assertTrue(gao.mine)
        assertFalse(gao.anthropic)
    }

    @Test
    fun lineTextsAndLabels() {
        val s = repo.session("1311951")!!
        val roomName: (String) -> String = idx::roomName
        assertEquals("Now · 3 min left · 251 A–C", ColoText.label(ColoLine.Now(s, 3, "251AC"), roomName))
        assertEquals("Lunch · Next 9:10", ColoText.label(ColoLine.Next(s, null, "Lunch"), roomName))
        assertEquals("Next 9:10 · 251 A–C · ArgoCon Project Update", ColoText.text(ColoLine.Next(s, "251AC", null), roomName))
        // A first talk that starts with the event needs no "First talk" time.
        assertEquals("Starts 9:10 AM", ColoText.label(ColoLine.Starts(at("2026-11-09T09:10:00-07:00"), s), roomName))
        assertEquals("Starts 9:00 AM · First talk 9:10", ColoText.label(ColoLine.Starts(at("2026-11-09T09:00:00-07:00"), s), roomName))
        // An agenda break row: its time column has the start, so the text gives the end and the place.
        assertEquals(
            "Coffee Break · until 10:40 · Meeting room foyers",
            ColoText.breakParts(repo.session("1309409")!!, "FOY", roomName).joinToString(" · "),
        )
        assertEquals(listOf("Lunch", "until 1:30"), ColoText.breakParts(repo.session("1309414")!!, null, roomName))
        assertTrue(ColoText.isRemarks(repo.session("1312032")!!))
        assertTrue(ColoText.isRemarks(repo.session("1312052")!!))
        assertFalse(ColoText.isRemarks(s))
        assertEquals("Co-located events", ColoText.SECTION)
    }
}
