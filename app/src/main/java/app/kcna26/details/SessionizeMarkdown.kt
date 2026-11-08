package app.kcna26.details

import app.kcna26.data.SessionDetail
import app.kcna26.data.SpeakerTagline
import java.util.Locale

/**
 * Parser for Sessionize's per-session markdown
 * (`https://sessionize.com/api/v2/uo948i5p/view/markdown/session/<id>`).
 *
 * A line-for-line port of `parse()` in scripts/fetch_details.py (the web's `parseMd`), so a
 * live fetch gives exactly what details.json would have held:
 *
 * - split on `## ` / `### ` headings (lowercased); keep "description" and "speakers" (or "speaker"),
 * - a speaker is a `- ` / `* ` bullet: `[Name](url) — tagline` (em, en dash or hyphen), or
 *   `**Name** — tagline` / `Name – tagline` (em or en dash only).
 *
 * Python's `\s` and `str.strip()` are Unicode-aware, so [WS] and [pyStrip] spell out the same
 * character set; `.` becomes `[^\n]` and `$` becomes `\z` (lines never contain `\n`).
 */
object SessionizeMarkdown {
    /** Python 3 `\s` for str patterns: ASCII whitespace plus every char where `str.isspace()`. */
    private const val WS = "[\\t\\n\\u000B\\f\\r \\u001C-\\u001F\\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000]"

    private val HEADING = Regex("^#{2,3}$WS+([^\\n]+?)$WS*\\z")
    private val BULLET = Regex("^$WS*[-*]$WS+")
    private val LINKED = Regex("^\\[([^\\]]+)\\]\\([^)]*\\)$WS*(?:[—–-]$WS*([^\\n]*))?\\z")
    private val PLAIN = Regex("^\\**([^—–*]+?)\\**$WS*(?:[—–]$WS*([^\\n]*))?\\z")

    /** `md` → description (blank-line paragraphs, as written) and speakers with taglines. */
    fun parse(md: String): SessionDetail {
        val sections = HashMap<String, MutableList<String>>()
        var cur: MutableList<String>? = null
        for (line in md.replace("\r\n", "\n").split("\n")) {
            val h = HEADING.find(line)
            if (h != null) {
                cur = ArrayList()
                sections[h.groupValues[1].lowercase(Locale.ROOT)] = cur
            } else {
                cur?.add(line)
            }
        }
        val speakers = ArrayList<SpeakerTagline>()
        for (raw in sections["speakers"] ?: sections["speaker"] ?: emptyList()) {
            if (BULLET.find(raw) == null) continue
            val line = pyStrip(BULLET.replaceFirst(raw, ""))
            val m = LINKED.find(line) ?: PLAIN.find(line)
            speakers += if (m != null) {
                SpeakerTagline(pyStrip(m.groupValues[1]), pyStrip(m.groupValues[2]))
            } else {
                SpeakerTagline(line, "")
            }
        }
        val description = pyStrip((sections["description"] ?: emptyList()).joinToString("\n"))
        return SessionDetail(description, speakers)
    }

    /** Python's `str.strip()` (same whitespace set as [WS]). */
    internal fun pyStrip(s: String): String {
        var a = 0
        var b = s.length
        while (a < b && isPySpace(s[a])) a++
        while (b > a && isPySpace(s[b - 1])) b--
        return s.substring(a, b)
    }

    private fun isPySpace(c: Char): Boolean = when (c) {
        '\t', '\n', '\u000B', '\u000C', '\r', ' ', '\u0085', ' ', ' ',
        ' ', ' ', ' ', ' ', '　',
        -> true
        in '\u001C'..'\u001F', in ' '..' ' -> true
        else -> false
    }
}
