import Foundation
import Observation

/// Full screens. Session details are not a screen: see ``NavModel/openSessionId``.
/// (Kotlin `sealed interface Screen`: `Screen.Schedule` -> ``schedule``, `Screen.Settings` ->
/// ``settings``, `Screen.Directions(sessionId)` -> ``directions(_:)``.)
enum Screen: Sendable, Hashable {
    case schedule
    case settings
    /// Directions to a session's room (Kotlin `Screen.Directions(sessionId)`).
    case directions(String)

    /// Stable string form, stored in the saved navigation state and used as the screen's
    /// state key (Kotlin: the SaveableStateHolder key; SwiftUI: an `.id` / scene storage key).
    var key: String {
        switch self {
        case .schedule: return "schedule"
        case .settings: return "settings"
        case .directions(let sessionId): return Screen.DIRECTIONS_PREFIX + sessionId
        }
    }

    /// The session of a ``directions(_:)`` screen (Kotlin `(screen as? Directions)?.sessionId`).
    var sessionId: String? {
        if case .directions(let id) = self { return id }
        return nil
    }

    private static let DIRECTIONS_PREFIX = "directions:"

    /// Nil for keys this version doesn't know, e.g. "unconf" from an older install (the
    /// Unconference screen was removed): restored stacks drop them and fall back to the Schedule.
    static func decode(_ key: String) -> Screen? {
        if key == Screen.schedule.key { return .schedule }
        if key == Screen.settings.key { return .settings }
        if key.kotlinStartsWith(DIRECTIONS_PREFIX) { return .directions(key.removePrefix(DIRECTIONS_PREFIX)) }
        return nil
    }
}

/// Navigation state (Kotlin `NavViewModel`), one per window (scene), kept in a string
/// key-value handle (Kotlin's SavedStateHandle) so it survives scene restoration:
/// - ``stack``: back stack of full screens, Schedule at the bottom.
/// - ``openSessionId``: the session shown in the details sheet (compact) or pane (wide).
///   It stays set while Directions is on top, so back returns to the same details.
///
/// A restored stack keeps only the screens ``Screen/decode(_:)`` knows (stale keys such as an
/// older install's "unconf" are dropped) and is written back cleaned.
///
/// The handle holds two strings, under Kotlin's keys: ``KEY_STACK`` (the screen keys as a JSON
/// array, bottom first, e.g. `["schedule","directions:1203350"]`) and ``KEY_SESSION`` (the open
/// session id; absent when none). Anything else under ``KEY_STACK`` (not a JSON array, another
/// kind of value) counts as no saved stack; non-string array elements are skipped.
///
/// SwiftUI (per scene, like Android's activity-scoped view model):
///
/// ```swift
/// @SceneStorage(NavModel.KEY_STACK) private var savedStack: String?
/// @SceneStorage(NavModel.KEY_SESSION) private var savedSession: String?
/// @State private var nav: NavModel?
/// ...
/// .onAppear { if nav == nil { nav = NavModel(restoring: .init(stack: savedStack, session: savedSession)) } }
/// .onChange(of: nav?.saved) { _, s in savedStack = s?.stack; savedSession = s?.session }
/// NavigationStack(path: Binding(get: { nav.path }, set: { nav.path = $0 })) { … }
/// ```
@MainActor
@Observable
final class NavModel {
    /// Kotlin `KEY_STACK` (SavedStateHandle key).
    nonisolated static let KEY_STACK = "nav.stack"
    /// Kotlin `KEY_SESSION` (SavedStateHandle key).
    nonisolated static let KEY_SESSION = "nav.session"

    @ObservationIgnored private let handle: KeyValueStore

    /// Back stack, bottom first; always starts with ``Screen/schedule``.
    private(set) var stack: [Screen]

    /// Session shown in the details sheet/pane, or nil.
    private(set) var openSessionId: String?

    /// Kotlin `NavViewModel(handle)`: restores from `handle` and writes every change back to it.
    /// `InMemoryStore()` is a fresh, empty state (Kotlin `SavedStateHandle()`).
    init(_ handle: KeyValueStore) {
        self.handle = handle
        let restored = NavModel.decode(NavModel.restoredKeys(handle))
        stack = restored
        openSessionId = handle.string(forKey: NavModel.KEY_SESSION)
        handle.set(NavModel.encodeKeys(restored.map(\.key)), forKey: NavModel.KEY_STACK)
    }

    /// A model over a fresh in-memory handle seeded with `saved` (SwiftUI `@SceneStorage`).
    convenience init(restoring saved: Saved = Saved()) {
        let h = InMemoryStore()
        if let stack = saved.stack { h.set(stack, forKey: NavModel.KEY_STACK) }
        if let session = saved.session { h.set(session, forKey: NavModel.KEY_SESSION) }
        self.init(h)
    }

    /// The top screen.
    var current: Screen { stack[stack.count - 1] }

    func push(_ screen: Screen) {
        let s = stack
        if s.last == screen { return }
        setStack(s + [screen])
    }

    /// Pops the top screen; false if already at the Schedule.
    @discardableResult
    func pop() -> Bool {
        let s = stack
        if s.count <= 1 { return false }
        setStack(Array(s.dropLast()))
        return true
    }

    func openSession(_ sessionId: String) {
        handle.set(sessionId, forKey: NavModel.KEY_SESSION)
        openSessionId = sessionId
    }

    func closeSession() {
        handle.removeValue(forKey: NavModel.KEY_SESSION)
        openSessionId = nil
    }

    func openSettings() { push(.settings) }

    func openDirections(_ sessionId: String) { push(.directions(sessionId)) }

    /// From a reminder notification: Schedule (with that session's details underneath) → Directions.
    func openDirectionsFromNotification(_ sessionId: String) {
        openSession(sessionId)
        setStack([.schedule, .directions(sessionId)])
    }

    /// iOS: the screens above the Schedule, for `NavigationStack(path:)`. Setting it (the
    /// system back button or edge swipe pops) replaces the stack, cleaned like any other change.
    var path: [Screen] {
        get { Array(stack.dropFirst()) }
        set { setStack([.schedule] + newValue) }
    }

    private func setStack(_ screens: [Screen]) {
        let fixed = NavModel.decode(screens.map(\.key))
        stack = fixed
        handle.set(NavModel.encodeKeys(fixed.map(\.key)), forKey: NavModel.KEY_STACK)
    }

    private static func decode(_ raw: [String]) -> [Screen] {
        [.schedule] + raw.compactMap(Screen.decode).filter { $0 != .schedule }
    }

    /// The saved stack's keys; anything unexpected in the handle counts as no saved stack.
    private static func restoredKeys(_ handle: KeyValueStore) -> [String] {
        decodeKeys(handle.string(forKey: KEY_STACK)) ?? []
    }

    // MARK: - Saved form (strings)

    /// The navigation state as two strings, for SwiftUI `@SceneStorage` (or any string store).
    struct Saved: Sendable, Hashable {
        /// ``KEY_STACK``: the stack's screen keys as a JSON array (nil = nothing saved).
        var stack: String?
        /// ``KEY_SESSION``: ``NavModel/openSessionId``.
        var session: String?

        init(stack: String? = nil, session: String? = nil) {
            self.stack = stack
            self.session = session
        }
    }

    /// The current state in its saved form (observable: it changes with ``stack`` and
    /// ``openSessionId``).
    var saved: Saved { Saved(stack: NavModel.encodeKeys(stack.map(\.key)), session: openSessionId) }

    /// Screen keys -> the stored ``KEY_STACK`` string (a JSON array of strings).
    nonisolated static func encodeKeys(_ keys: [String]) -> String {
        JSON.serialize(.array(keys.map { JSONValue.string($0) }))
    }

    /// The stored ``KEY_STACK`` string -> screen keys (Kotlin `as? List<*>` +
    /// `filterIsInstance<String>()`): nil unless it is a JSON array; non-strings are skipped.
    nonisolated static func decodeKeys(_ stored: String?) -> [String]? {
        guard let stored, let value = try? JSON.parse(stored), let items = value.arrayValue else { return nil }
        return items.compactMap(\.stringValue)
    }
}
