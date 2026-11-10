import Foundation
import XCTest
@testable import KCNA26Core

/// kotlinx-coroutines-test's virtual time for ``DirectionsViewModel``'s delays:
/// `advanceTimeBy(ms)` runs the actions due strictly before `currentTime + ms`, in time order
/// (then launch order), and `runCurrent()` those due now.
@MainActor
final class VirtualDirectionsScheduler: DirectionsScheduler {
    private(set) var currentTime: Int64 = 0
    private var queue: [(due: Int64, seq: Int, job: DirectionsJob, action: @MainActor @Sendable () -> Void)] = []
    private var seq = 0

    func launch(after delayMs: Int64, _ action: @escaping @MainActor @Sendable () -> Void) -> DirectionsJob {
        let job = DirectionsJob()
        seq += 1
        queue.append((currentTime + max(0, delayMs), seq, job, action))
        return job
    }

    func advanceTimeBy(_ ms: Int64) {
        let target = currentTime + ms
        runWhile { $0 < target }
        currentTime = target
    }

    func runCurrent() {
        let now = currentTime
        runWhile { $0 <= now }
    }

    private func runWhile(_ due: (Int64) -> Bool) {
        while true {
            queue.removeAll { !$0.job.isActive }
            guard let next = queue.min(by: { ($0.due, $0.seq) < ($1.due, $1.seq) }), due(next.due) else { return }
            queue.removeAll { $0.seq == next.seq }
            currentTime = max(currentTime, next.due)
            next.job.markCompleted()
            next.action()
        }
    }
}

@MainActor
final class DirectionsViewModelTests: XCTestCase {
    private let repo = TestData.repo
    // XCTest makes a fresh instance per test (like JUnit), so these start clean each time
    // (Kotlin's @Before also installs the test dispatcher: here ``scheduler``).
    private var logs: [String] = []
    private lazy var settings = SettingsStore(InMemoryStore())
    private var nowMs: Int64 = 0
    private lazy var scheduler = VirtualDirectionsScheduler()

    /// "The Future of Kubernetes Eviction and Node Lifecycle" (Wed, 251 A–C).
    private lazy var evictionTalk: String = repo.sessions.first { $0.title.hasPrefix("The Future of Kubernetes Eviction") }!.id
    private let vector = TestData.vectors.compass.first!

    private func vm(_ sessionId: String? = nil, repo data: Repository? = nil) -> DirectionsViewModel {
        let repo: Repository = data ?? self.repo
        return DirectionsViewModel(
            repo: repo,
            router: Router(repo),
            settings: settings,
            clock: TestData.clockAt("2026-11-11T16:30:00-07:00"),
            sessionId: sessionId ?? evictionTalk,
            declinationOf: { _, _, _, _ in 10.0 },
            log: { [unowned self] in self.logs.append($0) },
            elapsedMs: { [unowned self] in self.nowMs },
            scheduler: scheduler
        )
    }

    /// Kotlin `runCurrent()` / `advanceTimeBy(ms)` on the test dispatcher.
    private func runCurrent() { scheduler.runCurrent() }
    private func advanceTimeBy(_ ms: Int64) { scheduler.advanceTimeBy(ms) }

    func testResolvesTheRoom() {
        let vm = vm()
        XCTAssertEqual("251AC", vm.room?.code)
        XCTAssertNotNil(vm.target)
        XCTAssertEqual(10.0, vm.declination, accuracy: 1e-9)
    }

    func testOffSite_hasNoTargetOrPlan() throws {
        let off = try XCTUnwrap(repo.sessions.first { $0.room == "OFF" }).id
        let vm = vm(off)
        XCTAssertNil(vm.target)
        XCTAssertNil(vm.plan)
    }

    func testUnknownSession_isSafe() {
        let vm = vm("nope")
        XCTAssertNil(vm.session)
        XCTAssertNil(vm.target)
        XCTAssertNil(vm.plan)
    }

    func testMyLocation_fallsBackUntilAFixThenGoesLive() throws {
        let vm = vm()
        let before = try XCTUnwrap(vm.plan)
        XCTAssertEqual("LIVE", before.from)
        XCTAssertTrue(before.showFallbackNote)

        vm.onLocation(vector.lat, vector.lng, 12.0, nil)
        runCurrent()
        let fix = try XCTUnwrap(vm.fix)
        let local = Geo.toLocal(vector.lat, vector.lng, repo.wayfinding.origin)
        XCTAssertEqual(local.x, fix.x, accuracy: 1e-9)
        XCTAssertEqual(local.y, fix.y, accuracy: 1e-9)
        XCTAssertEqual(12.0, fix.accuracyM, accuracy: 1e-9)
        let after = try XCTUnwrap(vm.plan)
        XCTAssertTrue(try XCTUnwrap(after.route).live)
        XCTAssertFalse(after.showFallbackNote)
    }

    func testReRoutesOnlyWhenTheLiveStartChanges() throws {
        let vm = vm()
        vm.onLocation(vector.lat, vector.lng, 10.0, nil) // 200 South sidewalk: inside, starts at S200
        runCurrent()
        let first = try XCTUnwrap(vm.plan)
        XCTAssertEqual(vector.myLocationStart.node, first.startKey)
        vm.onLocation(vector.lat + 0.00001, vector.lng, 10.0, nil) // ~1 m on: same start, same steps
        runCurrent()
        // Kotlin assertSame: the plan was not recomputed. RoutePlan is a struct here; a recomputed
        // plan would differ (a live route's first point is the fix), so equality proves it.
        XCTAssertEqual(first, vm.plan)
        let far = TestData.vectors.compass[1] // Temple Square: outside, head to the West Temple entrance
        vm.onLocation(far.lat, far.lng, 10.0, nil)
        runCurrent()
        XCTAssertNotEqual(first, vm.plan)
        let farPlan = try XCTUnwrap(vm.plan)
        XCTAssertEqual("o\(far.myLocationStart.entrance ?? "")", farPlan.startKey)
        XCTAssertTrue(try XCTUnwrap(farPlan.route?.steps.first).text.hasPrefix("Head to the West Temple entrance"))
    }

    func testHeading_nullUntilTheCompassWakesThenTrue() throws {
        let vm = vm()
        vm.onLocation(vector.lat, vector.lng, 12.0, nil)
        runCurrent()
        // The map hides the heading cone until there is a heading, fix or not.
        XCTAssertNil(vm.heading)

        // Magnetic 340° + 10° declination = 350° true (GeomagneticField's value is injected here).
        vm.onAzimuth(340.0, 0, 0, 0)
        runCurrent()
        XCTAssertEqual(350.0, try XCTUnwrap(vm.heading), accuracy: 1e-9)
    }

    func testHeading_isSmoothedTheShortWay() throws {
        let vm = vm()
        vm.onAzimuth(340.0, 0, 0, 0) // 350 true
        vm.onAzimuth(0.0, 0, 0, 100) // 10 true: half way is 0, not 180
        XCTAssertEqual(0.0, try XCTUnwrap(vm.heading), accuracy: 1e-9)
    }

    func testCompassLog_atMostOncePerSecond() {
        let vm = vm()
        vm.onAzimuth(80.0, 7, 1, 0)
        vm.onAzimuth(81.0, 7, 1, 400)
        vm.onAzimuth(82.0, 7, 1, 999)
        vm.onAzimuth(83.0, 7, 1, 1000)
        XCTAssertEqual(2, logs.count)
        XCTAssertEqual("display=7 rotation=1 (90°) rawAzimuth=80.0 declination=10.0 trueHeading=90.0", logs.first)
    }

    func testFrom_isPersistedAndValidated() throws {
        let vm = vm()
        vm.setFrom("EWT")
        runCurrent()
        XCTAssertEqual("EWT", settings.directionsFrom)
        XCTAssertEqual("EWT", try XCTUnwrap(vm.plan).from)
        vm.setFrom("REG") // not offered by the picker
        vm.setFrom("bogus")
        XCTAssertEqual("EWT", settings.directionsFrom)
        vm.setFrom("LIVE")
        runCurrent()
        XCTAssertEqual("LIVE", try XCTUnwrap(vm.plan).from)
    }

    func testCalibrationHint_afterAMomentOfPoorAccuracy() {
        let vm = vm()
        vm.onSensorAccuracy(CompassSensor.TYPE_MAGNETIC_FIELD, Calibration.UNRELIABLE)
        XCTAssertFalse(vm.calibrate)
        advanceTimeBy(DirectionsViewModel.CALIBRATE_AFTER_MS + 1)
        XCTAssertTrue(vm.calibrate)
        vm.onSensorAccuracy(CompassSensor.TYPE_MAGNETIC_FIELD, 3)
        XCTAssertFalse(vm.calibrate)

        // A brief blip doesn't flash the hint.
        vm.onSensorAccuracy(CompassSensor.TYPE_ROTATION_VECTOR, Calibration.LOW)
        advanceTimeBy(500)
        vm.onSensorAccuracy(CompassSensor.TYPE_ROTATION_VECTOR, 3)
        advanceTimeBy(DirectionsViewModel.CALIBRATE_AFTER_MS)
        XCTAssertFalse(vm.calibrate)
    }

    func testNoFix_after30SecondsOfTracking() {
        let vm = vm()
        vm.trackingStarted()
        advanceTimeBy(DirectionsViewModel.NO_FIX_AFTER_MS - 1)
        XCTAssertFalse(vm.noFix)
        advanceTimeBy(2)
        XCTAssertTrue(vm.noFix)
        vm.onLocation(vector.lat, vector.lng, 30.0, 1300.0)
        XCTAssertFalse(vm.noFix)
    }

    func testStaleFix_isDroppedWhenTrackingRestarts() throws {
        let vm = vm()
        nowMs = 1_000
        vm.onLocation(vector.lat, vector.lng, 10.0, nil)
        vm.trackingStopped()
        nowMs = 3_000 // a fold/unfold later: keep it
        vm.trackingStarted()
        XCTAssertNotNil(vm.fix)
        vm.trackingStopped()
        nowMs = 1_000 + DirectionsViewModel.STALE_FIX_MS + 1 // back after a while: drop it
        vm.trackingStarted()
        XCTAssertNil(vm.fix)
        XCTAssertTrue(try XCTUnwrap(vm.plan).showFallbackNote)
    }

    func testNoFix_timerStopsWithTracking() {
        let vm = vm()
        vm.trackingStarted()
        vm.trackingStopped()
        advanceTimeBy(DirectionsViewModel.NO_FIX_AFTER_MS + 1)
        XCTAssertFalse(vm.noFix)
        vm.onLocationFailure()
        XCTAssertTrue(vm.noFix)
    }

    func testBadInputIsIgnored() throws {
        let vm = vm()
        vm.onLocation(Double.nan, 0.0, 5.0, nil)
        XCTAssertNil(vm.fix)
        vm.onAzimuth(Double.nan, 0, 0, 0)
        XCTAssertNil(vm.heading)
        vm.onLocation(vector.lat, vector.lng, Double.nan, nil)
        XCTAssertEqual(0.0, try XCTUnwrap(vm.fix).accuracyM, accuracy: 1e-9)
    }

    // ---------------------------------------------------------------- iOS additions

    /// Core Location headings: `trueHeading` is used as is (declination already applied), a
    /// missing true heading (−1) falls back to magnetic + declination, an invalid reading is
    /// ignored and poor accuracy shows the figure-8 hint after a moment.
    func testIOS_coreLocationHeadings() throws {
        let vm = vm()
        vm.onHeading(trueHeading: 350.0, magneticHeading: 340.0, headingAccuracy: 10.0, timeMs: 0)
        XCTAssertEqual(350.0, try XCTUnwrap(vm.heading), accuracy: 1e-9) // not 360: no second declination
        vm.onHeading(trueHeading: -1.0, magneticHeading: 0.0, headingAccuracy: 10.0, timeMs: 100)
        XCTAssertEqual(0.0, try XCTUnwrap(vm.heading), accuracy: 1e-9) // 0 + 10 = 10 true; half way from 350 is 0
        vm.onHeading(trueHeading: 90.0, magneticHeading: 80.0, headingAccuracy: -1.0, timeMs: 200)
        XCTAssertEqual(0.0, try XCTUnwrap(vm.heading), accuracy: 1e-9) // invalid: unchanged
        advanceTimeBy(DirectionsViewModel.CALIBRATE_AFTER_MS + 1)
        XCTAssertTrue(vm.calibrate) // ... and it asked for calibration
        vm.onHeading(trueHeading: 10.0, magneticHeading: 0.0, headingAccuracy: 5.0, timeMs: 300)
        XCTAssertFalse(vm.calibrate)
        XCTAssertEqual(1, logs.count)
        XCTAssertEqual("trueHeading=350.0 magneticHeading=340.0 accuracy=10.0 declination=10.0 usedHeading=350.0", logs.first)
    }

    /// `CLLocation` readings: invalid or stale ones are dropped; an invalid altitude is unknown.
    func testIOS_coreLocationReadings() throws {
        let vm = vm()
        func reading(acc: Double, vAcc: Double = 4.0, age: Double = 0.2) -> LocationReading {
            LocationReading(latitude: vector.lat, longitude: vector.lng, horizontalAccuracy: acc, altitude: 1310.0, verticalAccuracy: vAcc, ageSeconds: age)
        }
        vm.onLocation(reading(acc: -1.0))
        XCTAssertNil(vm.fix)
        vm.onLocation(reading(acc: 8.0, age: 600.0)) // Core Location's cached fix from 10 minutes ago
        XCTAssertNil(vm.fix)
        vm.onLocation(reading(acc: 8.0, vAcc: -1.0))
        XCTAssertEqual(8.0, try XCTUnwrap(vm.fix).accuracyM)
        XCTAssertNil(try XCTUnwrap(vm.fix).altitudeM)
        vm.onLocation(reading(acc: 9.0))
        XCTAssertEqual(1310.0, try XCTUnwrap(vm.fix).altitudeM)
    }

    /// Observation: the plan follows a From change made elsewhere (another screen's view model).
    func testIOS_planFollowsTheSharedFromSetting() throws {
        let vm = vm()
        XCTAssertEqual("LIVE", try XCTUnwrap(vm.plan).from)
        settings.setDirectionsFrom("EHY")
        XCTAssertEqual("EHY", try XCTUnwrap(vm.plan).from)
        XCTAssertEqual("EHY", vm.directionsFrom)
    }

    /// Why the app keys the view model by the data set too (Kotlin DirectionsScreen:
    /// `viewModel(key = "dir-$sessionId-${System.identityHashCode(repo)}")`): it routes with the
    /// Repository and Router it was built with, so after a live data update moves the talk
    /// (251 A–C -> 255 EF) only a view model built on the swapped-in pair shows the new room.
    func testIOS_aLiveDataSwapNeedsANewViewModel() throws {
        let doc = try XCTUnwrap(TestData.json(Repository.SCHEDULE).objectValue)
        let talk: String = evictionTalk
        let sessions: [JSONValue] = (doc["sessions"]?.arrayValue ?? []).map { s in
            guard let o = s.objectValue, o["id"]?.stringValue == talk else { return s }
            return JSONValue.object(o.with("room", .string("255EF")))
        }
        let schedule = JSON.serializedData(.object(doc.with("sessions", .array(sessions))))
        let dir = TestData.dataDir
        let swapped = try Repository.load { name in
            name == Repository.SCHEDULE ? schedule : try Data(contentsOf: dir.appendingPathComponent(name))
        }
        let before = vm()
        let after = vm(repo: swapped)

        // The old view model still shows the old room: it must be replaced, not kept.
        XCTAssertEqual("251AC", before.room?.code)
        XCTAssertEqual(repo.rooms["251AC"]?.pos, before.target)

        let room = try XCTUnwrap(after.room)
        XCTAssertEqual("255EF", room.code)
        XCTAssertEqual(swapped.rooms["255EF"]?.pos, after.target)
        XCTAssertNotEqual(before.target, after.target)
        XCTAssertEqual(talk, after.session?.id)
        let reminder = FloorReminder.of(room, try XCTUnwrap(after.plan).route)
        XCTAssertEqual("255 EF", reminder.roomName)
        XCTAssertEqual(2, reminder.level)
        XCTAssertNotEqual(before.plan, after.plan)
        // The steps and the map's route line end at the new room.
        XCTAssertEqual(after.target, try XCTUnwrap(after.plan?.route?.points.last))
        XCTAssertEqual(before.target, try XCTUnwrap(before.plan?.route?.points.last))
    }

    /// The production scheduler really runs (and cancels) its delays.
    func testIOS_taskSchedulerRunsAndCancels() async throws {
        let s = TaskDirectionsScheduler()
        let box = RunBox()
        let cancelled = s.launch(after: 10) { box.count += 100 }
        let kept = s.launch(after: 10) { box.count += 1 }
        cancelled.cancel()
        XCTAssertFalse(cancelled.isActive)
        XCTAssertTrue(kept.isActive)
        for _ in 0..<400 where box.count == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(1, box.count)
        XCTAssertFalse(kept.isActive)
    }
}

@MainActor
private final class RunBox {
    var count = 0
}
