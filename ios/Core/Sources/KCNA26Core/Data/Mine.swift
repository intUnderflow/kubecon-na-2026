import Foundation

/*
 * "Mine" and "Anthropic" are always worked out at runtime from the speakers list and the
 * current "I'm speaking as" setting (SettingsStore.speakingAs). Never use
 * Session.precomputedIsMine / precomputedHasAnthropic.
 */

/// True when `me` (the "I'm speaking as" name; nil = None) is one of the session's speakers.
func isMine(_ s: Session, _ me: String?) -> Bool {
    guard let me else { return false }
    return s.speakers.contains(me)
}

/// True when someone in `anthropicSpeakers` other than `me` is speaking and the session is not
/// mine (the web's `x.ant`). With me = nil, Lucy Sweet's own sessions count as Anthropic sessions.
func hasAnthropic<C: Collection>(_ s: Session, _ me: String?, _ anthropicSpeakers: C) -> Bool where C.Element == String {
    !isMine(s, me) && s.speakers.contains { $0 != me && anthropicSpeakers.contains($0) }
}

/// How a speaker name is shown in lists: "You" for `me`, otherwise the name.
func speakerLabel(_ name: String, _ me: String?) -> String {
    if let me, name == me { return "You" }
    return name
}

extension Repository {
    /// Convenience: ``isMine(_:_:)`` over the repository's sessions, sorted by start (stable).
    func mySessions(_ me: String?) -> [Session] {
        guard me != nil else { return [] }
        return sessions.filter { isMine($0, me) }.stableSorted(on: { $0.start })
    }

    /// Convenience: ``hasAnthropic(_:_:_:)`` using this repository's anthropicSpeakers.
    func hasAnthropic(_ s: Session, _ me: String?) -> Bool {
        freeHasAnthropic(s, me, anthropicSpeakers)
    }
}

/// The free ``hasAnthropic(_:_:_:)`` under another name, so the `Repository` method of the
/// same name can call it.
@inline(__always)
private func freeHasAnthropic(_ s: Session, _ me: String?, _ speakers: Set<String>) -> Bool {
    hasAnthropic(s, me, speakers)
}
