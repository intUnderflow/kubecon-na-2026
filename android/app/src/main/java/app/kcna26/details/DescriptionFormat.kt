package app.kcna26.details

/**
 * Turns a session description (Sessionize markdown, or Maintainer Summit plain text) into
 * blocks the details screen can render legibly. A superset of the web's `paras()`:
 *
 * - paragraphs split on blank lines; single newlines stay line breaks (the web's `<br>`),
 * - list lines become bulleted / numbered items with a hanging indent. Sessionize escapes the
 *   markers (`\- item`, `\* item`, `1\. item`), plain `- `, `* `, `+ `, `• `, `– ` work too,
 * - `[text](https://…)` shows `text` as a link, as do `<https://…>` and bare URLs (trailing
 *   punctuation and unbalanced brackets stay outside the link),
 * - `**bold**` / `__bold__` are bold, `*italic*` / `_italic_` italic, `\*`-style escapes are literal.
 *
 * Pure Kotlin (no Compose types) so it is unit-tested on the JVM; the UI maps [Rich] to an
 * AnnotatedString.
 */
object DescriptionFormat {

    /** Text with styled ranges ([Span.start] inclusive, [Span.end] exclusive, in [text]). */
    data class Rich(val text: String, val spans: List<Span> = emptyList())

    sealed interface Span {
        val start: Int
        val end: Int

        data class Bold(override val start: Int, override val end: Int) : Span
        data class Italic(override val start: Int, override val end: Int) : Span
        data class Link(override val start: Int, override val end: Int, val url: String) : Span
    }

    sealed interface Block {
        /** One paragraph; `\n` inside [text] is a line break. */
        data class Paragraph(val text: Rich) : Block

        /** Consecutive list items. */
        data class ListBlock(val items: List<Item>) : Block

        /** A `#`-style heading line, shown as a bold paragraph. */
        data class Heading(val text: Rich) : Block
    }

    /** [marker] is "•" for bullets or the number as written ("1.", "2)"). */
    data class Item(val marker: String, val text: Rich, val ordered: Boolean)

    private val BLANK_LINES = Regex("\\n(?:[ \\t\\u00A0]*\\n)+")
    private val LIST_ITEM =
        Regex("^[ \\t]*(?:\\\\?([-*+])|([•·▪◦‣–])|(\\d{1,3})\\\\?([.)]))[ \\t\\u00A0]+(\\S.*)$")
    private val HEADING = Regex("^[ \\t]*#{1,6}[ \\t]+(\\S.*?)[ \\t#]*$")
    private const val ESCAPABLE = "\\`*_{}[]()#+-.!>~|<\"'"

    /** Blocks for [description]; empty for null/blank. */
    fun parse(description: String?): List<Block> {
        if (description.isNullOrBlank()) return emptyList()
        val text = description.replace("\r\n", "\n").replace('\r', '\n')
        val out = ArrayList<Block>()
        for (chunk in text.split(BLANK_LINES)) {
            if (chunk.isBlank()) continue
            parseChunk(chunk, out)
        }
        return out
    }

    private fun parseChunk(chunk: String, out: MutableList<Block>) {
        val para = ArrayList<String>()
        val items = ArrayList<Pair<String, StringBuilder>>()
        var ordered = false

        fun flushPara() {
            if (para.isNotEmpty()) {
                out += Block.Paragraph(inline(para.joinToString("\n")))
                para.clear()
            }
        }

        fun flushList() {
            if (items.isNotEmpty()) {
                out += Block.ListBlock(items.map { (m, t) -> Item(m, inline(t.toString().trim()), m != "•") })
                items.clear()
            }
        }

        for (raw in chunk.split('\n')) {
            val line = raw.trimEnd()
            if (line.isBlank()) continue
            val li = LIST_ITEM.find(line)
            val h = if (li == null) HEADING.find(line) else null
            when {
                li != null -> {
                    flushPara()
                    val number = li.groupValues[3]
                    val isOrdered = number.isNotEmpty()
                    if (items.isNotEmpty() && isOrdered != ordered) flushList()
                    ordered = isOrdered
                    val marker = if (isOrdered) number + li.groupValues[4] else "•"
                    items += marker to StringBuilder(li.groupValues[5])
                }
                h != null -> {
                    flushPara()
                    flushList()
                    out += Block.Heading(inline(h.groupValues[1]))
                }
                // An indented line right after an item continues it.
                items.isNotEmpty() && (raw.startsWith(" ") || raw.startsWith("\t")) ->
                    items.last().second.append(' ').append(line.trim())
                else -> {
                    flushList()
                    para += line.trim()
                }
            }
        }
        flushPara()
        flushList()
    }

    /** Inline markdown in [s]: escapes, links, bare URLs, bold and italic. */
    fun inline(s: String): Rich {
        val out = StringBuilder(s.length)
        val spans = ArrayList<Span>()
        inlineInto(s, 0, s.length, out, spans)
        spans.sortWith(compareBy<Span> { it.start }.thenByDescending { it.end })
        return Rich(out.toString(), spans)
    }

    private fun inlineInto(s: String, from: Int, to: Int, out: StringBuilder, spans: MutableList<Span>) {
        var i = from
        while (i < to) {
            val c = s[i]
            when {
                c == '\\' && i + 1 < to && s[i + 1] in ESCAPABLE -> {
                    out.append(s[i + 1])
                    i += 2
                }
                c == '[' -> {
                    val end = mdLink(s, i, to, out, spans)
                    if (end > 0) {
                        i = end
                    } else {
                        out.append(c)
                        i++
                    }
                }
                c == '<' -> {
                    val close = s.indexOf('>', i + 1)
                    val url = if (close in (i + 1) until to) s.substring(i + 1, close) else null
                    if (url != null && isUrl(url) && url.none { it.isWhitespace() }) {
                        val start = out.length
                        out.append(url)
                        spans += Span.Link(start, out.length, url)
                        i = close + 1
                    } else {
                        out.append(c)
                        i++
                    }
                }
                (c == '*' || c == '_') && i + 1 < to && s[i + 1] == c -> {
                    val end = emphasis(s, i, to, 2, out, spans)
                    if (end > 0) {
                        i = end
                    } else {
                        out.append(c).append(c)
                        i += 2
                    }
                }
                c == '*' || c == '_' -> {
                    val end = emphasis(s, i, to, 1, out, spans)
                    if (end > 0) {
                        i = end
                    } else {
                        out.append(c)
                        i++
                    }
                }
                (c == 'h' || c == 'H') && startsUrl(s, i) && (i == from || !s[i - 1].isLetterOrDigit()) -> {
                    val end = bareUrlEnd(s, i, to)
                    val url = s.substring(i, end)
                    val start = out.length
                    out.append(url)
                    spans += Span.Link(start, out.length, url)
                    i = end
                }
                else -> {
                    out.append(c)
                    i++
                }
            }
        }
    }

    /** `[text](url)` at [i]; returns the index after it, or -1 if it isn't a link. */
    private fun mdLink(s: String, i: Int, to: Int, out: StringBuilder, spans: MutableList<Span>): Int {
        var j = i + 1
        while (j < to && s[j] != ']' && s[j] != '\n') {
            if (s[j] == '\\') j++
            j++
        }
        if (j >= to || s[j] != ']' || j == i + 1 || j + 1 >= to || s[j + 1] != '(') return -1
        val close = s.indexOf(')', j + 2)
        if (close < 0 || close >= to) return -1
        val url = s.substring(j + 2, close).trim().substringBefore(' ')
        if (!isUrl(url) && !url.startsWith("mailto:")) return -1
        val start = out.length
        inlineInto(s, i + 1, j, out, spans)
        spans += Span.Link(start, out.length, url)
        return close + 1
    }

    /**
     * `**x**` / `__x__` ([n] = 2) or `*x*` / `_x_` ([n] = 1) at [i]. Opening delimiters must be
     * followed by non-space and closers preceded by non-space; `_` must also sit on word
     * boundaries (so snake_case stays literal). Returns the index after the closer, or -1.
     */
    private fun emphasis(s: String, i: Int, to: Int, n: Int, out: StringBuilder, spans: MutableList<Span>): Int {
        val d = s[i]
        val open = i + n
        if (open >= to || s[open].isWhitespace() || s[open] == d) return -1
        if (d == '_' && i > 0 && s[i - 1].isLetterOrDigit()) return -1
        var j = open + 1
        while (j + n <= to) {
            if (s[j] == '\\') {
                j += 2
                continue
            }
            val isCloser = (0 until n).all { s[j + it] == d } && !s[j - 1].isWhitespace() &&
                (n == 2 || j + 1 >= to || s[j + 1] != d)
            if (isCloser && (d != '_' || j + n >= to || !s[j + n].isLetterOrDigit())) {
                val start = out.length
                inlineInto(s, open, j, out, spans)
                spans += if (n == 2) Span.Bold(start, out.length) else Span.Italic(start, out.length)
                return j + n
            }
            if (s[j] == '\n' && j + 1 < to && s[j + 1] == '\n') return -1
            j++
        }
        return -1
    }

    private fun startsUrl(s: String, i: Int): Boolean =
        s.startsWith("https://", i, ignoreCase = true) || s.startsWith("http://", i, ignoreCase = true)

    private fun isUrl(u: String): Boolean =
        (u.startsWith("https://", ignoreCase = true) && u.length > 8) ||
            (u.startsWith("http://", ignoreCase = true) && u.length > 7)

    /** End of a bare URL starting at [i]: up to whitespace, minus trailing punctuation / unbalanced closers. */
    private fun bareUrlEnd(s: String, i: Int, to: Int): Int {
        var e = i
        while (e < to && !s[e].isWhitespace() && s[e] !in "<>\"") e++
        while (e > i) {
            val last = s[e - 1]
            val drop = when (last) {
                '.', ',', ';', ':', '!', '?', '\'', '*', '_', '’', '”' -> true
                ')' -> s.substring(i, e).count { it == ')' } > s.substring(i, e).count { it == '(' }
                ']' -> s.substring(i, e).count { it == ']' } > s.substring(i, e).count { it == '[' }
                else -> false
            }
            if (!drop) break
            e--
        }
        return e
    }
}
