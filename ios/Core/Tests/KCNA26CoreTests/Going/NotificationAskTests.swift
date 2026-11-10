import XCTest
@testable import KCNA26Core

/// Port of going/NotificationAskTest.kt: when the contextual notification-permission ask fires
/// (first star, a name picked, reminders turned on, or reminders already planned at start) and
/// what the notifications-off hint says. The tests after "iOS" cover the UNAuthorizationStatus
/// mapping that replaces Android's POST_NOTIFICATIONS plumbing (no Kotlin counterpart).
@MainActor
final class NotificationAskTests: XCTestCase {

    /// Kotlin runs the flow on an UnconfinedTestDispatcher (each value reaches the collector at
    /// once); here `flush()` delivers the last change before the watch is cancelled.
    private func countTriggers(_ block: (SettingsStore, GoingStore) -> Void) -> Int {
        var n = 0
        let settings = SettingsStore(InMemoryStore())
        let going = GoingStore(InMemoryStore())
        let job = NotificationAsk.triggers(settings, going) { n += 1 }
        block(settings, going)
        job.flush()
        job.cancel()
        return n
    }

    func testNothingHappensUntilTheUserDoesSomething() {
        XCTAssertEqual(0, countTriggers { _, _ in })
    }

    func testStarringASessionTriggers() {
        XCTAssertEqual(1, countTriggers { _, g in g.toggle("1251049") })
        // Unstarring the last one doesn't.
        XCTAssertEqual(1, countTriggers { _, g in g.toggle("1251049"); g.toggle("1251049") })
    }

    func testPickingANameTriggersButNoneDoesNot() {
        XCTAssertEqual(1, countTriggers { s, _ in s.setSpeakingAs("Graham Helton") })
        XCTAssertEqual(0, countTriggers { s, _ in s.setSpeakingAs(nil) })
    }

    func testTurningTheGoingRemindersOnTriggersButOffDoesNot() {
        XCTAssertEqual(0, countTriggers { _, g in g.setRemindMinutes(0) })
        XCTAssertEqual(1, countTriggers { _, g in g.setRemindMinutes(0); g.setRemindMinutes(15) })
    }

    // MARK: - at start

    private let repo = TestData.repo
    private func at(_ iso: String) -> Date { TestData.instant(iso) }
    private func toCome(_ me: String?, _ now: String, _ going: Set<String> = [], minutes: Int = 10) -> Bool {
        NotificationAsk.remindersToCome(repo.sessions, repo.rooms, me, at(now), going, minutes)
    }

    func testAtStartTheAskIsDueOnlyWhenRemindersArePlanned() {
        // The default speaker (Lucy Sweet) has talks to come: the ask is due at start, as before.
        XCTAssertTrue(toCome(SettingsStore.DEFAULT_SPEAKER, "2026-11-08T08:00"))
        // None and nothing starred (the public default): nothing to deliver, so no ask at launch.
        XCTAssertFalse(toCome(nil, "2026-11-08T08:00"))
        // A star counts while its reminder is on and still to come.
        XCTAssertTrue(toCome(nil, "2026-11-08T08:00", ["1251049"]))
        XCTAssertFalse(toCome(nil, "2026-11-08T08:00", ["1251049"], minutes: 0))
        XCTAssertFalse(toCome(nil, "2026-11-11T14:15", ["1251049"])) // its 2:10 reminder is past
        // After Lucy's last talk (Wed 5:00 PM) there is nothing left for her.
        XCTAssertFalse(toCome("Lucy Sweet", "2026-11-11T17:30"))
    }

    // MARK: - the hint

    private func block(
        permission: Bool = true,
        appOn: Bool = true,
        channelOn: Bool = true,
        needsRuntimeAsk: Bool = true,
        asked: Bool = true,
        asking: Bool = false
    ) -> NotificationAsk.Block {
        NotificationAsk.blockOf(
            permission: permission, appOn: appOn, channelOn: channelOn,
            needsRuntimeAsk: needsRuntimeAsk, asked: asked, asking: asking
        )
    }

    func testTheHintStatesFollowThePermissionAndTheChannels() {
        XCTAssertEqual(NotificationAsk.Block.nothing, block())
        // Refused: the app is off.
        XCTAssertEqual(NotificationAsk.Block.app, block(permission: false))
        // Not asked yet on Android 13+: nothing to say until the contextual ask.
        XCTAssertEqual(NotificationAsk.Block.nothing, block(permission: false, asked: false))
        // While the system dialog is up: nothing either (no "off" hint behind the dialog).
        XCTAssertEqual(NotificationAsk.Block.nothing, block(permission: false, asking: true))
        // Notifications switched off for the app (any Android version).
        XCTAssertEqual(NotificationAsk.Block.app, block(appOn: false, needsRuntimeAsk: false, asked: false))
        // Only the channel is off: a deliberate choice, told apart from the app being off.
        XCTAssertEqual(NotificationAsk.Block.channel, block(channelOn: false))
        XCTAssertEqual(NotificationAsk.Block.app, block(appOn: false, channelOn: false))
    }

    func testAskingIsTrackedUntilTheDialogAnswers() {
        XCTAssertFalse(NotificationAsk.asking)
        NotificationAsk.requestStarted()
        XCTAssertTrue(NotificationAsk.asking)
        NotificationAsk.requestFinished()
        XCTAssertFalse(NotificationAsk.asking)
    }

    func testTheCurrentValuesAtStartDoNotTrigger() {
        var n = 0
        let settings = SettingsStore(InMemoryStore())
        settings.setSpeakingAs("Lucy Sweet")
        let going = GoingStore(InMemoryStore())
        going.toggle("1251049")
        going.setRemindMinutes(5)
        let job = NotificationAsk.triggers(settings, going) { n += 1 }
        job.cancel()
        XCTAssertEqual(0, n)
    }

    // MARK: - iOS (UNAuthorizationStatus mapping; no Kotlin counterpart)

    func testEveryChangeCountsAndTheLastIsDeliveredOnTheNextMainActorTurn() async throws {
        var n = 0
        let settings = SettingsStore(InMemoryStore())
        let going = GoingStore(InMemoryStore())
        let job = NotificationAsk.triggers(settings, going) { n += 1 }
        // Two names in a row are two triggers (as two StateFlow values); the same name again is none.
        settings.setSpeakingAs("Graham Helton")
        settings.setSpeakingAs("Lucy Sweet")
        settings.setSpeakingAs("Lucy Sweet")
        going.setRemindMinutes(15)
        XCTAssertEqual(2, n) // the speakingAs changes; the last change waits for the next turn
        for _ in 0..<200 where n < 3 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(3, n)
        job.flush()
        XCTAssertEqual(3, n)
        job.cancel()
        going.toggle("1251049")
        job.flush()
        XCTAssertEqual(3, n)
    }

    func testTheTriggerRuleCountsEachValueThatTurnsOn() {
        let off = NotificationAsk.Watched(ids: [], speakingAs: nil, remindMinutes: 0)
        let on = NotificationAsk.Watched(ids: ["1251049"], speakingAs: "Lucy Sweet", remindMinutes: 10)
        XCTAssertEqual(0, NotificationAsk.triggerCount(off, off))
        XCTAssertEqual(3, NotificationAsk.triggerCount(off, on))
        XCTAssertEqual(0, NotificationAsk.triggerCount(on, on))
        XCTAssertEqual(0, NotificationAsk.triggerCount(on, off))
        // Another star, another name, another lead time: each still needs notifications.
        let more = NotificationAsk.Watched(ids: ["1251049", "1251218"], speakingAs: "Graham Helton", remindMinutes: 5)
        XCTAssertEqual(3, NotificationAsk.triggerCount(on, more))
    }

    func testTheIOSHintFollowsTheAuthorizationStatus() {
        typealias A = NotificationAsk.Authorization
        // Never asked: the ask is still to come, nothing to say yet; after an unanswered ask, "off".
        XCTAssertEqual(.nothing, NotificationAsk.blockOf(A.notDetermined, asked: false, asking: false))
        XCTAssertEqual(.app, NotificationAsk.blockOf(A.notDetermined, asked: true, asking: false))
        XCTAssertEqual(.nothing, NotificationAsk.blockOf(A.notDetermined, asked: true, asking: true))
        // Refused or turned off in Settings: the dialog won't show again, so say so (asked or not).
        XCTAssertEqual(.app, NotificationAsk.blockOf(A.denied, asked: true, asking: false))
        XCTAssertEqual(.app, NotificationAsk.blockOf(A.denied, asked: false, asking: false))
        XCTAssertEqual(.nothing, NotificationAsk.blockOf(A.denied, asked: true, asking: true))
        // Delivered: nothing to say. No channel switch on iOS.
        for a in [A.authorized, .provisional, .ephemeral] {
            XCTAssertTrue(a.allowsDelivery)
            XCTAssertEqual(.nothing, NotificationAsk.blockOf(a, asked: true, asking: false))
            XCTAssertEqual(.nothing, NotificationAsk.blockOf(a, asked: false, asking: false))
        }
        // "Turn on": the dialog while it can still show, else the app's notification settings.
        XCTAssertEqual(.requestAuthorization, NotificationAsk.turnOn(.notDetermined))
        XCTAssertEqual(.openSettings, NotificationAsk.turnOn(.denied))
        // blocked() reads the asked flag and the dialog state.
        let settings = SettingsStore(InMemoryStore())
        XCTAssertEqual(.nothing, NotificationAsk.blocked(.notDetermined, settings))
        settings.notificationPermissionAsked = true
        XCTAssertEqual(.app, NotificationAsk.blocked(.notDetermined, settings))
        XCTAssertEqual(.app, NotificationAsk.blocked(.denied, settings))
        XCTAssertEqual(.nothing, NotificationAsk.blocked(.authorized, settings))
    }

    func testTheAskIsMadeOnceAndOnlyWhileTheSystemCanShowItsDialog() {
        XCTAssertTrue(NotificationAsk.shouldAsk(.notDetermined, asked: false))
        XCTAssertFalse(NotificationAsk.shouldAsk(.notDetermined, asked: true))
        for a in [NotificationAsk.Authorization.denied, .authorized, .provisional, .ephemeral] {
            XCTAssertFalse(NotificationAsk.shouldAsk(a, asked: false))
        }
        // At start: only with reminders planned, and the plan is only worked out when it matters.
        var planned = 0
        XCTAssertTrue(NotificationAsk.remindersWaiting(.notDetermined, asked: false) { planned += 1; return true })
        XCTAssertFalse(NotificationAsk.remindersWaiting(.notDetermined, asked: false) { planned += 1; return false })
        XCTAssertFalse(NotificationAsk.remindersWaiting(.notDetermined, asked: true) { planned += 1; return true })
        XCTAssertFalse(NotificationAsk.remindersWaiting(.authorized, asked: false) { planned += 1; return true })
        XCTAssertEqual(2, planned)
        // With the stores: the default speaker has talks to come before the conference.
        let settings = SettingsStore(InMemoryStore())
        let going = GoingStore(InMemoryStore())
        let before = at("2026-11-08T08:00")
        XCTAssertFalse(NotificationAsk.remindersWaiting(.notDetermined, settings, going, repo, before))
        settings.setSpeakingAs(SettingsStore.DEFAULT_SPEAKER)
        XCTAssertTrue(NotificationAsk.remindersWaiting(.notDetermined, settings, going, repo, before))
        XCTAssertFalse(NotificationAsk.remindersWaiting(.denied, settings, going, repo, before))
        settings.notificationPermissionAsked = true
        XCTAssertFalse(NotificationAsk.remindersWaiting(.notDetermined, settings, going, repo, before))
    }

    func testAskOnceMarksItAskedAndTracksTheDialog() async {
        let settings = SettingsStore(InMemoryStore())
        let permission = FakePermission(.notDetermined, grants: true)
        let granted = await NotificationAsk.askOnce(settings, permission)
        XCTAssertEqual(true, granted)
        XCTAssertTrue(settings.notificationPermissionAsked)
        XCTAssertFalse(NotificationAsk.asking)
        let first = await permission.log
        XCTAssertEqual(["status", "request asking=true"], first)
        // Asked once: never again, whatever the status.
        let again = await NotificationAsk.askOnce(settings, permission)
        XCTAssertNil(again)
        let second = await permission.log
        XCTAssertEqual(["status", "request asking=true", "status"], second)
        // Refused for good: nothing to ask.
        let denied = FakePermission(.denied, grants: false)
        let none = await NotificationAsk.askOnce(SettingsStore(InMemoryStore()), denied)
        XCTAssertNil(none)
        let deniedLog = await denied.log
        XCTAssertEqual(["status"], deniedLog)
        // The hint's "Turn on" while the dialog can still show: asks now, refused this time.
        let refused = FakePermission(.notDetermined, grants: false)
        let fresh = SettingsStore(InMemoryStore())
        let answer = await NotificationAsk.askNow(fresh, refused)
        XCTAssertFalse(answer)
        XCTAssertTrue(fresh.notificationPermissionAsked)
        XCTAssertFalse(NotificationAsk.asking)
    }
}

/// A scripted ``NotificationPermission``: a fixed status and answer, and a log of the calls.
private actor FakePermission: NotificationPermission {
    private let current: NotificationAsk.Authorization
    private let grants: Bool
    private(set) var log: [String] = []

    init(_ status: NotificationAsk.Authorization, grants: Bool) {
        current = status
        self.grants = grants
    }

    func status() -> NotificationAsk.Authorization {
        log.append("status")
        return current
    }

    func request() async -> Bool {
        let asking = await MainActor.run { NotificationAsk.asking }
        log.append("request asking=\(asking)")
        return grants
    }
}
