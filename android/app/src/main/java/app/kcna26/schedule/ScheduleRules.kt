package app.kcna26.schedule

import app.kcna26.data.Session
import app.kcna26.data.SessionGroup
import app.kcna26.time.TimeFormat
import java.time.Duration

/**
 * Port of the web version's `catOf` and `seriesOf` (schedule_app.js).
 *
 * schedule.json already carries the web's precomputed `category` and `group`,
 * and the app uses those. The one exception: the web's break regex
 * `/^(☕|🍲|Break|Lunch|Coffee)/` also matches talk titles that start with
 * "Breaking…", so three real talks (with speakers) arrive as category "log"
 * (quiet break rows that can't be opened or searched). [ScheduleIndex] re-runs
 * these rules with the word-bounded regex for exactly those rows; for every
 * other session the result equals the JSON (ScheduleRulesTest checks both).
 */
object ScheduleRules {
    /** The web's LOG_RE, verbatim (matches "Breaking…" too). */
    private val LOG_RE_WEB = Regex("^(☕|🍲|Break|Lunch|Coffee)")

    /** LOG_RE with "Break" as a whole word, so "Breaking up Is Hard…" stays a talk. */
    private val LOG_RE_FIXED = Regex("^(☕|🍲|Break(?!\\p{L})|Lunch|Coffee)")

    private val SOC_RE =
        Regex("KubeCrawl|ClashLoopBackOff|Trivia|Fun Run|Puppy Yoga|Pet-a-Pup|Documentary|Reception|Group Photo", RegexOption.IGNORE_CASE)
    private val CTF_RE = Regex("Capture The Flag", RegexOption.IGNORE_CASE)
    private val DEMOS_RE = Regex("In-Booth Demos")

    private val MNT_ROOMS = setOf("250AC", "250DF", "251AC", "251DF", "254")
    private val HANDS_ROOMS = setOf("255A", "255D", "RA")
    private val SHOW_ROOMS = setOf("PP", "CC", "DT", "NN", "SSZ")
    private val COM_ROOMS = setOf("J", "CR", "UM")

    /** Web `catOf`. [webExact] = true uses the web's regex unchanged (for tests). */
    fun catOf(s: Session, webExact: Boolean = false): String {
        val t = s.title
        val r = s.room
        val logRe = if (webExact) LOG_RE_WEB else LOG_RE_FIXED
        if (logRe.containsMatchIn(t)) return "log"
        if (s.isMaintainerSummit) {
            return when {
                s.note == "Keynote" -> "key"
                s.note == "Unconference" -> "com"
                s.note == "Project Meeting" -> "mnt"
                s.note == "Workshop" -> "hands"
                SOC_RE.containsMatchIn(t) -> "soc"
                else -> "talk"
            }
        }
        return when {
            r == "OFF" || s.note == "All-Access pass" -> "colo"
            SOC_RE.containsMatchIn(t) -> "soc"
            r == "DE" -> "key"
            CTF_RE.containsMatchIn(t) -> "hands"
            r in MNT_ROOMS -> "mnt"
            r in HANDS_ROOMS -> "hands"
            r in SHOW_ROOMS || DEMOS_RE.containsMatchIn(t) -> "show"
            r in COM_ROOMS -> "com"
            else -> "talk"
        }
    }

    /** Web `seriesOf` for a session whose category is [cat]. */
    fun seriesOf(s: Session, cat: String): SessionGroup? {
        if (cat == "log") return null
        val r = s.room
        val d = s.day
        val st = TimeFormat.minuteOfDay(s.start)
        val len = Duration.between(s.start, s.effectiveEnd).toMinutes()
        if (r == "DE") return SessionGroup("$d-key", if (d == "tue") "Opening keynotes" else "Morning keynotes")
        if (d == "mon" && r == "RBD") return SessionGroup("mon-plt", "Project Lightning Talks")
        if (d == "wed" && r == "RCD" && len <= 10) return SessionGroup("wed-lt", "Lightning talks")
        if (r == "CC") {
            when (d) {
                "tue" -> return when {
                    st < 770 -> SessionGroup("tue-cnu", "Cloud Native University")
                    st < 890 -> SessionGroup("tue-envoy", "EnvoyCon")
                    else -> SessionGroup("tue-kyv", "KyvernoCon")
                }
                "wed" -> return when {
                    st < 755 -> SessionGroup("wed-kv", "KubeVirt Summit")
                    st < 880 -> SessionGroup("wed-kf", "Kubeflow Summit")
                    else -> SessionGroup("wed-istio", "Istio Day")
                }
                "thu" -> return SessionGroup("thu-llmd", "llm-d sessions")
            }
        }
        if (d == "wed" && r == "SHOW" && cat == "talk") return SessionGroup("wed-posters", "Poster sessions")
        return null
    }

    /**
     * True for a JSON "log" row that is really a talk: it has speakers. Break rows
     * (coffee, lunch, networking) never list speakers.
     */
    fun isMisfiledBreak(s: Session): Boolean = s.category == "log" && s.speakers.isNotEmpty()
}
