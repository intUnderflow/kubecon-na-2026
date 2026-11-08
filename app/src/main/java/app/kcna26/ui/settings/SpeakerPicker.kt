package app.kcna26.ui.settings

import androidx.compose.runtime.Immutable
import app.kcna26.data.Repository
import app.kcna26.schedule.TextMatch

/** One choice in the "I’m speaking as" picker. */
@Immutable
data class SpeakerOption(
    val name: String,
    /** "3 sessions · Wed", "1 session · Sun, Tue". */
    val summary: String,
    /** [name] normalised for case/diacritic-insensitive search. */
    val folded: String,
)

/** Pure helpers behind the Settings speaker picker (unit-tested). */
object SpeakerPicker {
    /** Every speaker in the schedule (repository.allSpeakers order) with how many sessions they have and on which days. */
    fun options(repo: Repository): List<SpeakerOption> {
        val bySpeaker = HashMap<String, MutableList<String>>()
        for (s in repo.sessions) for (n in s.speakers) bySpeaker.getOrPut(n) { mutableListOf() }.add(s.day)
        val dayOrder = repo.days.map { it.key }
        val dow = repo.days.associate { it.key to it.dow }
        return repo.allSpeakers.map { name ->
            val days = bySpeaker[name].orEmpty()
            val n = days.size
            val dayList = dayOrder.filter { it in days }.mapNotNull { dow[it] }.joinToString(", ")
            SpeakerOption(
                name = name,
                summary = "$n ${if (n == 1) "session" else "sessions"}" + if (dayList.isNotEmpty()) " · $dayList" else "",
                folded = TextMatch.normalize(name),
            )
        }
    }

    fun terms(query: String): List<String> = TextMatch.terms(query)

    /**
     * Options matching every term. With no terms, everything except [pinned]
     * (the default speaker, which the screen lists on its own above the rest).
     */
    fun filter(options: List<SpeakerOption>, terms: List<String>, pinned: String?): List<SpeakerOption> =
        if (terms.isEmpty()) {
            options.filter { it.name != pinned }
        } else {
            options.filter { TextMatch.matchesAll(it.folded, terms) }
        }
}
