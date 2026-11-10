import XCTest
@testable import KCNA26Core

/// Port of nav/NavViewModelTest.kt, plus tests of the iOS saved form and `path`.
///
/// Kotlin `SavedStateHandle()` -> `InMemoryStore()`; a handle holding
/// `"nav.stack" to arrayListOf(...)` -> the stack's stored form, a JSON array string
/// (`NavModel.encodeKeys`); a handle holding something else under "nav.stack" (Kotlin: a bare
/// String) -> a string that isn't a JSON array, or another kind of value.
@MainActor
final class NavViewModelTests: XCTestCase {

    private func stackHandle(_ keys: [String], session: String? = nil) -> InMemoryStore {
        var initial: [String: KeyValueStoreValue] = [NavModel.KEY_STACK: .string(NavModel.encodeKeys(keys))]
        if let session { initial[NavModel.KEY_SESSION] = .string(session) }
        return InMemoryStore(initial)
    }

    func testStackAndSessionSurviveRecreation() {
        let handle = InMemoryStore()
        let nav = NavModel(handle)
        XCTAssertEqual([Screen.schedule], nav.stack)
        XCTAssertFalse(nav.pop())
        nav.openSession("1203350")
        nav.openDirections("1203350")
        nav.openDirections("1203350") // no duplicate
        XCTAssertEqual([Screen.schedule, Screen.directions("1203350")], nav.stack)

        // A recreated scene gets a new model over the same saved state.
        let again = NavModel(handle)
        XCTAssertEqual(nav.stack, again.stack)
        XCTAssertEqual("1203350", again.openSessionId)

        again.pop()
        XCTAssertEqual([Screen.schedule], again.stack)
        XCTAssertEqual("1203350", again.openSessionId)
        again.closeSession()
        XCTAssertNil(again.openSessionId)

        again.openSettings()
        again.openDirectionsFromNotification("m1290687")
        XCTAssertEqual([Screen.schedule, Screen.directions("m1290687")], again.stack)
        XCTAssertEqual("m1290687", again.openSessionId)
        XCTAssertEqual(Screen.directions("m1290687"), Screen.decode(Screen.directions("m1290687").key))
    }

    func testStaleUnconferenceRouteFromAnOlderInstallFallsBackToSchedule() {
        // The Unconference screen ("unconf") was removed. An older install's saved state with it open,
        // on top or under Directions, restores without it.
        XCTAssertNil(Screen.decode("unconf"))
        let onTop = stackHandle(["schedule", "unconf"], session: "m1318474")
        let nav = NavModel(onTop)
        XCTAssertEqual([Screen.schedule], nav.stack)
        XCTAssertEqual(Screen.schedule, nav.current)
        XCTAssertFalse(nav.pop())
        XCTAssertEqual("m1318474", nav.openSessionId)
        // The cleaned stack is what gets saved next time.
        XCTAssertEqual(["schedule"], NavModel.decodeKeys(onTop.string(forKey: "nav.stack")))
        XCTAssertEqual([Screen.schedule], NavModel(onTop).stack)

        let under = stackHandle(["schedule", "unconf", "directions:m1318474", "bogus"])
        let nav2 = NavModel(under)
        XCTAssertEqual([Screen.schedule, Screen.directions("m1318474")], nav2.stack)
        XCTAssertTrue(nav2.pop())
        XCTAssertEqual([Screen.schedule], nav2.stack)

        // Anything unexpected under the key counts as no saved stack.
        XCTAssertEqual([Screen.schedule], NavModel(InMemoryStore(["nav.stack": .string("unconf")])).stack)
        // iOS: other kinds of value, and non-string array elements.
        XCTAssertEqual([Screen.schedule], NavModel(InMemoryStore(["nav.stack": .stringSet(["settings"])])).stack)
        XCTAssertEqual([Screen.schedule], NavModel(InMemoryStore(["nav.stack": .string("{\"a\":\"settings\"}")])).stack)
        XCTAssertEqual(
            [Screen.schedule, Screen.settings],
            NavModel(InMemoryStore(["nav.stack": .string("[1,\"settings\",null]")])).stack
        )
    }

    // MARK: - iOS

    func testKeysAndDecodeRoundTrip() {
        XCTAssertEqual("schedule", Screen.schedule.key)
        XCTAssertEqual("settings", Screen.settings.key)
        XCTAssertEqual("directions:1203350", Screen.directions("1203350").key)
        for s in [Screen.schedule, .settings, .directions("1203350"), .directions("m1290687"), .directions("")] {
            XCTAssertEqual(s, Screen.decode(s.key))
        }
        XCTAssertEqual("1203350", Screen.directions("1203350").sessionId)
        XCTAssertNil(Screen.settings.sessionId)
        XCTAssertNil(Screen.decode("Schedule"))
        XCTAssertNil(Screen.decode(""))
    }

    func testSavedFormRestoresTheSameState() {
        let nav = NavModel(restoring: NavModel.Saved())
        XCTAssertEqual([Screen.schedule], nav.stack)
        XCTAssertNil(nav.openSessionId)
        XCTAssertEqual(NavModel.Saved(stack: "[\"schedule\"]", session: nil), nav.saved)

        nav.openSession("1249844")
        nav.openDirections("1249844")
        let saved = nav.saved
        XCTAssertEqual("[\"schedule\",\"directions:1249844\"]", saved.stack)
        XCTAssertEqual("1249844", saved.session)

        let again = NavModel(restoring: saved)
        XCTAssertEqual([Screen.schedule, Screen.directions("1249844")], again.stack)
        XCTAssertEqual("1249844", again.openSessionId)
        XCTAssertEqual(saved, again.saved)

        // An older install's stack restores cleaned.
        let stale = NavModel(restoring: NavModel.Saved(stack: "[\"schedule\",\"unconf\",\"settings\"]", session: nil))
        XCTAssertEqual([Screen.schedule, Screen.settings], stale.stack)
        XCTAssertEqual("[\"schedule\",\"settings\"]", stale.saved.stack)
    }

    func testPathFollowsAndSetsTheStack() {
        let handle = InMemoryStore()
        let nav = NavModel(handle)
        XCTAssertEqual([], nav.path)
        nav.openSettings()
        nav.openDirections("1203350")
        XCTAssertEqual([Screen.settings, Screen.directions("1203350")], nav.path)
        // The system back gesture pops one.
        nav.path = [.settings]
        XCTAssertEqual([Screen.schedule, Screen.settings], nav.stack)
        XCTAssertEqual(["schedule", "settings"], NavModel.decodeKeys(handle.string(forKey: NavModel.KEY_STACK)))
        // A Schedule entry in the path is dropped (it is always the bottom).
        nav.path = [.schedule, .directions("m1290687")]
        XCTAssertEqual([Screen.schedule, Screen.directions("m1290687")], nav.stack)
        nav.path = []
        XCTAssertEqual([Screen.schedule], nav.stack)
        XCTAssertFalse(nav.pop())
    }

    func testPushOnlySkipsTheSameTopScreen() {
        let nav = NavModel(InMemoryStore())
        nav.openDirections("1")
        nav.openDirections("2")
        nav.openDirections("1")
        XCTAssertEqual([Screen.schedule, .directions("1"), .directions("2"), .directions("1")], nav.stack)
        nav.push(.schedule) // never stacked twice
        XCTAssertEqual([Screen.schedule, .directions("1"), .directions("2"), .directions("1")], nav.stack)
        XCTAssertEqual(Screen.directions("1"), nav.current)
    }
}
