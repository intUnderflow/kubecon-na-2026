package app.kcna26.schedule

import java.text.Normalizer
import java.util.Locale

/**
 * Case- and diacritic-insensitive matching for search ("krepinsky" finds
 * "Filip Křepinský", "255 a-c" finds "255 A–C", "o'leary" finds "O’Leary").
 * Pure JVM, no Android.
 */
object TextMatch {
    private val MARKS = Regex("\\p{Mn}+")
    private val SPACES = Regex("\\s+")

    /** Letters that NFD doesn't split into base + mark. */
    private val FOLD = mapOf(
        'ł' to "l", 'ø' to "o", 'æ' to "ae", 'œ' to "oe", 'ß' to "ss", 'đ' to "d", 'ð' to "d",
        'þ' to "th", 'ı' to "i", 'ħ' to "h", 'ŀ' to "l",
        '’' to "'", '‘' to "'", 'ʼ' to "'", '“' to "\"", '”' to "\"",
        '–' to "-", '—' to "-", '‑' to "-", '−' to "-",
    )

    /** Lower-cases, strips diacritics and folds look-alike punctuation. */
    fun normalize(s: String): String {
        if (s.isEmpty()) return s
        val lower = s.lowercase(Locale.ROOT)
        val stripped = MARKS.replace(Normalizer.normalize(lower, Normalizer.Form.NFD), "")
        if (stripped.none { it in FOLD }) return stripped
        val sb = StringBuilder(stripped.length + 4)
        for (c in stripped) {
            val f = FOLD[c]
            if (f != null) sb.append(f) else sb.append(c)
        }
        return sb.toString()
    }

    /** The web's `q.toLowerCase().split(/\s+/).filter(Boolean)`, normalised. */
    fun terms(query: String): List<String> =
        normalize(query.trim()).split(SPACES).filter { it.isNotEmpty() }

    /** True when every term occurs in [normalizedHaystack] (already passed through [normalize]). */
    fun matchesAll(normalizedHaystack: String, terms: List<String>): Boolean =
        terms.all { normalizedHaystack.contains(it) }
}
