import Foundation

/// One choice in the "I’m speaking as" picker (Kotlin ui/settings/SpeakerPicker.kt).
struct SpeakerOption: Sendable, Hashable {
    let name: String
    /// "3 sessions · Wed", "1 session · Sun, Tue".
    let summary: String
    /// `name` normalised for case/diacritic-insensitive search (``TextMatch/normalize(_:)``).
    let folded: String
}

/// Pure helpers behind the Settings speaker picker and the first-run sheet (unit-tested).
enum SpeakerPicker {
    /// Every speaker in the schedule (``Repository/allSpeakers`` order) with how many sessions
    /// they have and on which days.
    ///
    /// Names are grouped with Swift `String` keys, like ``Repository/allSpeakers`` (built with
    /// `distinct()`), so the counts and the list agree; the data's names are NFC.
    static func options(_ repo: Repository) -> [SpeakerOption] {
        var bySpeaker: [String: [String]] = [:]
        for s in repo.sessions {
            for n in s.speakers { bySpeaker[n, default: []].append(s.day) }
        }
        let dayOrder = repo.days.map(\.key)
        let dow: [String: String] = Dictionary(repo.days.map { ($0.key, $0.dow) }, uniquingKeysWith: { _, last in last })
        return repo.allSpeakers.map { name in
            let days = bySpeaker[name] ?? []
            let n = days.count
            let dayList = dayOrder.filter { days.contains($0) }.compactMap { dow[$0] }.joined(separator: ", ")
            return SpeakerOption(
                name: name,
                summary: "\(n) \(n == 1 ? "session" : "sessions")" + (dayList.isEmpty ? "" : " · \(dayList)"),
                folded: TextMatch.normalize(name)
            )
        }
    }

    /// The search terms of `query` (``TextMatch/terms(_:)``).
    static func terms(_ query: String) -> [String] { TextMatch.terms(query) }

    /// Options matching every term. With no terms, everything except `pinned` (the default
    /// speaker, which the screen lists on its own above the rest).
    static func filter(_ options: [SpeakerOption], _ terms: [String], _ pinned: String?) -> [SpeakerOption] {
        if terms.isEmpty {
            return options.filter { o in !(pinned.map { kotlinEquals(o.name, $0) } ?? false) }
        }
        return options.filter { TextMatch.matchesAll($0.folded, terms) }
    }
}
