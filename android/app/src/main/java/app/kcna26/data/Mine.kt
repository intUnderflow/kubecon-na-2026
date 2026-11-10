package app.kcna26.data

/*
 * "Mine" and "Anthropic" are always worked out at runtime from the speakers list
 * and the current "I'm speaking as" setting (SettingsStore.speakingAs). Never use
 * Session.precomputedIsMine / precomputedHasAnthropic.
 */

/** True when [me] (the "I'm speaking as" name; null = None) is one of the session's speakers. */
fun isMine(s: Session, me: String?): Boolean = me != null && me in s.speakers

/**
 * True when someone in [anthropicSpeakers] other than [me] is speaking and the
 * session is not mine (the web's `x.ant`). With me = null, Lucy Sweet's own
 * sessions count as Anthropic sessions.
 */
fun hasAnthropic(s: Session, me: String?, anthropicSpeakers: Collection<String>): Boolean =
    !isMine(s, me) && s.speakers.any { it != me && it in anthropicSpeakers }

/** How a speaker name is shown in lists: "You" for [me], otherwise the name. */
fun speakerLabel(name: String, me: String?): String = if (me != null && name == me) "You" else name

/** Convenience: [isMine] over the repository's sessions, sorted by start. */
fun Repository.mySessions(me: String?): List<Session> =
    if (me == null) emptyList() else sessions.filter { isMine(it, me) }.sortedBy { it.start }

/** Convenience: [hasAnthropic] using this repository's anthropicSpeakers. */
fun Repository.hasAnthropic(s: Session, me: String?): Boolean = hasAnthropic(s, me, anthropicSpeakers)
