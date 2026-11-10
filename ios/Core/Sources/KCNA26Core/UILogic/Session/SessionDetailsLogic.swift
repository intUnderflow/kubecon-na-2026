import Foundation

/// The pure parts of Kotlin ui/session/SessionSheet.kt and ui/session/SessionDetailsParts.kt
/// (web `sheetHTML`): what the details pane / sheet shows and in which state, so the SwiftUI
/// `SessionDetails`, `SessionSheet`, `DetailsBody`, `MetaRow`, `WhereRow`, `ColoInfo`, `Pills`,
/// `SpeakerItem`, `About`, `Links` and `DirectionsBar` only lay out. The strings are
/// ``SessionText``'s.
///
/// Order of the body (web sheetHTML): ``meta(_:_:)``, the title (a heading), the where row
/// (``SessionText/roomName(_:_:)``, ``SessionText/buildingLabel(_:)``,
/// ``SessionText/whereNote(_:)`` in note amber), the co-located extras (``coloInfo(_:_:)``),
/// ``pills(_:mine:anthropic:now:)``, the clash note (``GoingUiLogic/clashNote(_:_:_:_:_:)``), the
/// speakers (``SessionText/speakerRows(_:_:_:_:)`` under ``SessionText/speakersHeading(_:)``),
/// ``gettingThere(_:)``, ``about(_:showLoading:)`` and ``links(_:_:_:)``; then the pinned
/// Directions bar (``directionsBar(_:_:)``).
enum SessionDetailsLogic {
    /// Shown for an id the schedule no longer has (a live update removed it).
    static let NOT_IN_SCHEDULE = "This session is no longer in the schedule."

    /// "Loading…" only appears if loading the details takes longer than this (ms).
    static let LOADING_DELAY_MS: Int64 = 250

    /// The × button's label.
    static let CLOSE = "Close"

    /// Whether to `await details.load(id)` after ``DetailsRepository/peekResult(_:)``: unknown
    /// (nil) or `.unavailable` (retry: the network may be back). The sheet starts from the peek,
    /// so known details show at once.
    static func needsLoad(_ result: DetailsResult?) -> Bool {
        guard let result else { return true }
        return result == .unavailable
    }

    /// Horizontal padding of the details: 24 pt in the wide pane (`widthClass.isWide && !inSheet`), else 18.
    static func horizontalPadding(wide: Bool) -> Double { wide ? 24 : 18 }

    /// Space the meta row keeps free for the × button (pane or sheet with a close button).
    static func metaTrailingReserve(closeButton: Bool) -> Double { closeButton ? 44 : 0 }

    // MARK: - MetaRow

    /// Category · "Wed 5:00–5:30 PM" · duration · tag (web `.meta`). A co-located session's event
    /// name ("ArgoCon") is the eyebrow in place of the category.
    struct Meta: Sendable, Hashable {
        /// Eyebrow (bold); "" = none.
        let label: String
        /// The category whose colour the eyebrow uses ("colo" for an event name).
        let labelCategory: String
        let dayAndTime: String
        let duration: String?
        /// The outlined summit tag.
        let tag: String?
    }

    static func meta(_ repo: Repository, _ s: Session) -> Meta {
        let event = SessionText.coloEyebrow(repo, s)
        return Meta(
            label: event ?? SessionText.categoryLabel(repo, s),
            labelCategory: event != nil ? "colo" : s.category,
            dayAndTime: SessionText.dayAndTime(repo.dayOf(s), s),
            duration: SessionText.duration(s),
            tag: SessionText.tag(s)
        )
    }

    // MARK: - ColoInfo

    /// Co-located extras under the where row: which events a shared break serves, the talk's
    /// format, level and "Sponsored" tags (outlined; "Sponsored" in note amber), and its topic.
    /// Nil for any other session.
    struct ColoInfo: Sendable, Hashable {
        let serves: String?
        let tags: [String]
        let topic: String?
    }

    static func coloInfo(_ repo: Repository, _ s: Session) -> ColoInfo? {
        if !s.isColocated { return nil }
        return ColoInfo(serves: SessionText.servesLine(repo, s), tags: SessionText.coloTags(s), topic: s.topic)
    }

    /// A co-located tag's text colour.
    static func coloTagColor(_ tag: String) -> PaletteRole { tag == SessionText.SPONSORED ? .note : .muted }

    // MARK: - Pills

    /// "You’re speaking" (pink), "Anthropic" (clay), "Live · N min left" (pink). Only this reads the ticking clock.
    struct Pill: Sendable, Hashable {
        let text: String
        let background: PaletteRole
        let content: PaletteRole
    }

    static func pills(_ s: Session, mine: Bool, anthropic: Bool, now: Date) -> [Pill] {
        var out: [Pill] = []
        if mine { out.append(Pill(text: SessionText.YOU_SPEAKING, background: .you, content: .onYou)) }
        if anthropic { out.append(Pill(text: SessionText.ANTHROPIC, background: .anthropic, content: .onAnthropic)) }
        if let live = SessionText.liveLabel(s, now) { out.append(Pill(text: live, background: .you, content: .onYou)) }
        return out
    }

    // MARK: - SpeakerItem

    /// Name colour: "You" pink, an Anthropic colleague clay (plus a small "Anthropic" badge), else ink.
    static func speakerColor(_ row: SessionText.SpeakerRow) -> PaletteRole {
        if row.isMe { return .you }
        if row.isAnthropic { return .anthropic }
        return .ink
    }

    // MARK: - Getting there

    /// The web's `.wf .loc`: an ink "LEVEL 2" badge and "SALT PALACE · 251 A–C"; read as one
    /// element ("Level 2 · Salt Palace · 251 A–C"). Nil without a position (no section).
    struct GettingThere: Sendable, Hashable {
        let level: String
        let place: String
        var accessibilityLabel: String { "\(level) · \(place)" }
    }

    static func gettingThere(_ room: Room?) -> GettingThere? {
        guard let level = SessionText.levelLabel(room), let place = SessionText.buildingAndRoom(room) else { return nil }
        return GettingThere(level: level, place: place)
    }

    // MARK: - About

    /// The About section (Kotlin `About`): the description as paragraphs and lists, or the
    /// loading / unavailable note, or nothing.
    enum About: Sendable, Hashable {
        /// No section.
        case hidden
        /// ``SessionText/ABOUT`` + ``SessionText/LOADING`` (muted, description style).
        case loading
        /// ``SessionText/ABOUT`` + ``SessionText/UNAVAILABLE`` (muted, small).
        case unavailable
        /// ``SessionText/ABOUT`` + the blocks (never empty).
        case description([DescriptionFormat.Block])
    }

    /// `showLoading`: set ``LOADING_DELAY_MS`` after opening while the result is still nil.
    static func about(_ result: DetailsResult?, showLoading: Bool) -> About {
        guard let result else { return showLoading ? .loading : .hidden }
        if result == .unavailable { return .unavailable }
        if let description = result.info?.description {
            let blocks = DescriptionFormat.parse(description)
            if !blocks.isEmpty { return .description(blocks) }
        }
        return .hidden
    }

    /// The marker column of a list block: 28 pt when any item is numbered, else 18 pt.
    static func markerWidth(_ items: [DescriptionFormat.Item]) -> Double { items.contains { $0.ordered } ? 28 : 18 }

    // MARK: - Links

    /// A link button (all open in the browser): primary = ink fill, else outlined.
    struct Link: Sendable, Hashable {
        let text: String
        let url: String
        let primary: Bool
    }

    /// Slides ↗, Proposal and replies on GitHub ↗ (sessions with a ``Session/discussionUrl``), an
    /// extra summit link if the data has one ("<text> ↗"), Official listing ↗ (the web's
    /// `.links`). `official`: ``SessionText/officialUrl(_:_:)``.
    static func links(_ s: Session, _ official: String?, _ info: DetailInfo?) -> [Link] {
        var out: [Link] = []
        if let slides = info?.slidesUrl ?? s.slidesUrl { out.append(Link(text: SessionText.SLIDES, url: slides, primary: true)) }
        if let discussion = s.discussionUrl { out.append(Link(text: SessionText.DISCUSSION, url: discussion, primary: true)) }
        if let link = info?.link {
            let text = info?.linkText ?? link
            out.append(Link(text: "\(text) ↗", url: link, primary: true))
        }
        if let official { out.append(Link(text: SessionText.OFFICIAL, url: official, primary: false)) }
        return out
    }

    // MARK: - DirectionsBar

    /// The pinned bar: the RSVP toggle (``GoingUiLogic/showsToggle(_:_:)``), the Directions
    /// button (enabled when `reason` is nil), the web's explanation above it otherwise, and the
    /// notifications-off hint above everything when it applies (``GoingUiLogic/reminderHint(_:_:_:_:_:)``).
    /// A hairline tops the bar while the content can scroll further.
    static func directionsBar(_ room: Room?, _ s: Session) -> (reason: String?, enabled: Bool) {
        let reason = SessionText.directionsUnavailable(room, s)
        return (reason, reason == nil)
    }
}
