package app.kcna26.ui.session

import app.kcna26.TestData
import app.kcna26.data.SpeakerTagline
import app.kcna26.ui.session.SessionText.SpeakerRow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class SessionTextTest {
    private val repo = TestData.repo
    private fun s(id: String) = repo.session(id)!!
    private fun at(iso: String): Instant = TestData.clockAt(iso).now()

    private val eviction = "1289660" // Wed 5:00–5:30 PM, 251 A–C (the spec's example)

    @Test
    fun metaRowMatchesTheWeb() {
        val x = s(eviction)
        assertEquals("Maintainer", SessionText.categoryLabel(repo, x))
        assertEquals("Wed 5:00–5:30 PM", SessionText.dayAndTime(repo.dayOf(x), x))
        assertEquals("30 min", SessionText.duration(x))
        assertNull(SessionText.tag(x))

        // Estimated end: "~"; Maintainer Summit note as a tag.
        val summit = s("m1290687")
        assertEquals("~45 min", SessionText.duration(summit))
        assertEquals("Main Track", SessionText.tag(summit))
        assertNull(SessionText.whereNote(summit))
        assertNull(SessionText.tag(s("m1318410"))) // "Keynote" is not shown as a tag

        // Open-ended reception: "from 5:30 PM", no duration.
        val reception = s("m1318417")
        assertEquals("Sun from 5:30 PM", SessionText.dayAndTime(repo.dayOf(reception), reception))
        assertNull(SessionText.duration(reception))

        // Breaks have no category label.
        assertEquals("", SessionText.categoryLabel(repo, s("1289742")))
    }

    @Test
    fun liveCountdownLikeTheWebSheet() {
        val x = s(eviction)
        assertNull(SessionText.liveLabel(x, at("2026-11-11T16:59:59-07:00")))
        assertEquals("Live · 30 min left", SessionText.liveLabel(x, at("2026-11-11T17:00:00-07:00")))
        assertEquals("Live · 12 min left", SessionText.liveLabel(x, at("2026-11-11T17:18:40-07:00")))
        assertEquals("Live · 1 min left", SessionText.liveLabel(x, at("2026-11-11T17:29:59-07:00")))
        assertNull(SessionText.liveLabel(x, at("2026-11-11T17:30:00-07:00")))
        // Open-ended sessions count as 90 minutes.
        assertEquals("Live · 30 min left", SessionText.liveLabel(s("m1318417"), at("2026-11-08T18:30:00-07:00")))
    }

    @Test
    fun whereAndFloorLines() {
        val r = repo.room("251AC")
        assertEquals("251 A–C", SessionText.roomName(r, s(eviction)))
        assertEquals("Salt Palace L2", SessionText.buildingLabel(r))
        assertEquals("Level 2", SessionText.levelLabel(r))
        assertEquals("Salt Palace · 251 A–C", SessionText.buildingAndRoom(r))
        assertEquals("Level 2 · Salt Palace · 251 A–C", SessionText.locationLine(r))
        assertNull(SessionText.directionsUnavailable(r, s(eviction)))

        assertEquals("Level 3 · Hyatt Regency · Park City", SessionText.locationLine(repo.room("PC")))
        // Hyatt lobby: a position but no building label.
        assertEquals("Level 1 · Hyatt Regency · Hyatt lobby", SessionText.locationLine(repo.room("HL")))
        assertNull(SessionText.buildingLabel(repo.room("HL")))
        assertEquals("Level 1 · Salt Palace · Project Pavilion, Hall 5", SessionText.locationLine(repo.room("PP")))
    }

    @Test
    fun offSiteDisablesDirectionsWithTheWebWording() {
        val hackathon = s("1344383")
        val off = repo.room("OFF")
        assertEquals("Off-site", SessionText.roomName(off, hackathon))
        assertNull(SessionText.buildingLabel(off))
        assertNull(SessionText.levelLabel(off))
        assertNull(SessionText.locationLine(off))
        assertEquals("Sold out", SessionText.whereNote(hackathon))
        assertEquals(
            "Off-site event. The official listing has the address and registration details.",
            SessionText.directionsUnavailable(off, hackathon),
        )
        // Unknown room code (no Room at all): no position.
        assertEquals("No map position for this room.", SessionText.directionsUnavailable(null, s(eviction)))
        assertEquals("XYZ", SessionText.roomName(null, s(eviction).copy(room = "XYZ")))
    }

    @Test
    fun speakersShowYouAndAnthropicFromTheCurrentSetting() {
        val x = s(eviction)
        val detail = repo.details.getValue(eviction).speakers
        val ant = repo.anthropicSpeakers

        val asLucy = SessionText.speakerRows(detail, x.speakers, "Lucy Sweet", ant)
        assertEquals(
            listOf(
                SpeakerRow("You", "Member of Technical Staff at Anthropic", isMe = true, isAnthropic = false),
                SpeakerRow("Ryan Hallisey", "Nvidia, Software Engineer", isMe = false, isAnthropic = false),
                SpeakerRow("Filip Křepinský", "Principal Software Engineer, Red Hat", isMe = false, isAnthropic = false),
            ),
            asLucy,
        )
        assertEquals("Speakers", SessionText.speakersHeading(asLucy.size))

        // None: Lucy is an Anthropic colleague like anyone else.
        val asNone = SessionText.speakerRows(detail, x.speakers, null, ant)
        assertEquals(SpeakerRow("Lucy Sweet", "Member of Technical Staff at Anthropic", isMe = false, isAnthropic = true), asNone[0])

        // Someone else: "You" moves with the setting.
        val asRyan = SessionText.speakerRows(detail, x.speakers, "Ryan Hallisey", ant)
        assertEquals(listOf("Lucy Sweet", "You", "Filip Křepinský"), asRyan.map { it.label })
        assertEquals(listOf(true, false, false), asRyan.map { it.isAnthropic })

        // A colleague on someone else's talk.
        val colleague = repo.sessions.first { ses -> ses.speakers.any { it in ant && it != "Lucy Sweet" } }
        val rows = SessionText.speakerRows(repo.details[colleague.id]?.speakers.orEmpty(), colleague.speakers, "Lucy Sweet", ant)
        assertEquals(true, rows.any { it.isAnthropic })
    }

    @Test
    fun speakersFallBackToScheduleNamesWhileLoading() {
        val x = s("m1290687")
        assertEquals(
            listOf(SpeakerRow("Rohit Agrawal", "", false, false), SpeakerRow("Kateryna Nezdolii", "", false, false)),
            SessionText.speakerRows(emptyList(), x.speakers, "Lucy Sweet", repo.anthropicSpeakers),
        )
        assertEquals("Speaker", SessionText.speakersHeading(1))
        assertEquals(emptyList<SpeakerRow>(), SessionText.speakerRows(emptyList(), emptyList(), "Lucy Sweet", emptySet()))
    }

    @Test
    fun sessionizeNameQuirksStillMatchTheSchedule() {
        assertEquals("Flynn", SessionText.cleanName("Flynn -"))
        assertEquals("Suhani", SessionText.cleanName("Suhani ‎"))
        assertEquals("Ann Lee", SessionText.cleanName(" Ann Lee – "))
        assertEquals("Smit Jain", SessionText.matchScheduleName("Smit Jain (he/him)", listOf("Smit Jain")))
        assertEquals("Piotr Prokop", SessionText.matchScheduleName("Piotr Prokop PL", listOf("Piotr Prokop", "Sreeja Varnam")))
        assertNull(SessionText.matchScheduleName("Ann", listOf("Ann Lee")))

        val suhani = SessionText.speakerRows(listOf(SpeakerTagline("Suhani ‎", "Contributor @Kyverno")), listOf("Suhani"), "Suhani", emptySet())
        assertEquals(listOf(SpeakerRow("You", "Contributor @Kyverno", true, false)), suhani)
        val smit = SessionText.speakerRows(listOf(SpeakerTagline("Smit Jain (he/him)", "")), listOf("Smit Jain"), "Smit Jain", emptySet())
        assertEquals("You", smit.single().label)
        // Display keeps the Sessionize spelling otherwise.
        assertEquals("Smit Jain (he/him)", SessionText.speakerRows(listOf(SpeakerTagline("Smit Jain (he/him)", "")), listOf("Smit Jain"), null, emptySet()).single().label)
    }

    @Test
    fun coLocatedSessions() {
        val talk = s("1311945") // ArgoCon sponsored keynote
        assertEquals("ArgoCon", SessionText.coloEyebrow(repo, talk))
        assertEquals(listOf("Keynote", "Any level", "Sponsored").filter { it in SessionText.coloTags(talk) }, SessionText.coloTags(talk))
        assertTrue(SessionText.SPONSORED in SessionText.coloTags(talk))
        assertEquals("Keynote", SessionText.coloTags(talk).first())
        assertEquals("Event", SessionText.categoryLabel(repo, talk)) // replaced by the eyebrow in the meta row
        assertNull(SessionText.whereNote(talk))
        assertNull(SessionText.tag(talk))
        assertEquals(talk.officialUrl, SessionText.officialUrl(repo, talk))
        assertTrue(talk.officialUrl.endsWith("?id=1311945"))
        // A break several events share, and one event's own break.
        val lunch = s("1309415")
        assertEquals(SessionText.COLOCATED_EVENTS, SessionText.coloEyebrow(repo, lunch))
        assertEquals("For Agentics Day: MCP + Agents, ArgoCon, BackstageCon and Open Source SecurityCon", SessionText.servesLine(repo, lunch))
        assertEquals(emptyList<String>(), SessionText.coloTags(lunch))
        val ciliumLunch = s("1309414")
        assertEquals("CiliumCon", SessionText.coloEyebrow(repo, ciliumLunch))
        assertNull(SessionText.servesLine(repo, ciliumLunch))
        // Their places have no position: say where they are instead of the bare sentence.
        assertEquals(
            "Lower Concourse foyer and Hall 4, reached via the Lower Mezzanine. No map position for this room.",
            SessionText.directionsUnavailable(repo.roomOf(lunch), lunch),
        )
        assertNull(SessionText.levelLabel(repo.roomOf(lunch)))
        // Talks are in real rooms: Directions work, "Getting there" shows.
        assertNull(SessionText.directionsUnavailable(repo.roomOf(talk), talk))
        assertEquals("Level 1 · Salt Palace · Room 151", SessionText.locationLine(repo.roomOf(talk)))
        // The reception and everything from schedule.json have no eyebrow or tags.
        assertNull(SessionText.coloEyebrow(repo, s("1309453")))
        assertNull(SessionText.coloEyebrow(repo, s("1289660")))
        assertEquals(emptyList<String>(), SessionText.coloTags(s("1289660")))
        // No official link of its own: the event's page.
        val bare = talk.copy(officialUrl = "")
        assertEquals(repo.coloEvent("colo-argocon")!!.pageUrl, SessionText.officialUrl(repo, bare))
        assertNull(SessionText.officialUrl(repo, s("1289660").copy(officialUrl = "")))
    }
}
