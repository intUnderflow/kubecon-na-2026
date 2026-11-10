import CoreLocation
import Observation
import SwiftUI
import UIKit

/// Location and compass for one Directions screen, over Core Location (Kotlin's
/// `LocationTracker` (fused location) + `CompassSensor` (rotation vector) +
/// `rememberLocationPermission`). It feeds Core's ``DirectionsViewModel`` exactly as
/// ``LocationTracker`` and ``CompassSensor`` describe; the screen only lays out.
///
/// ```swift
/// @State private var location = DirectionsLocationService()
/// ...
/// LiveDirections(vm: vm, ...)
///     .tracksDirectionsLocation(location, for: vm)   // start/stop with visibility + scenePhase, screen kept on
/// let status = location.locStatus(vm)               // LocStatus for DirectionsLogic.readout
/// Button(DirectionsText.ALLOW_LOCATION) { location.requestAccess() }
/// ```
///
/// - Runs only while the screen is visible in an active scene (``start(_:)`` / ``stop()``; both
///   idempotent, like Kotlin's `started` flags). Location needs When-In-Use authorization (asked
///   once per screen, the first time it opens while `.notDetermined`; Info.plist
///   `NSLocationWhenInUseUsageDescription`); the compass doesn't.
/// - Location: best accuracy, no distance filter, `.fitness`, never paused. Each update ->
///   ``DirectionsViewModel/onLocation(_:)`` with `locations.last`, then
///   `setDeviceLocationOff(false)`; `CLError.denied` -> ``DirectionsViewModel/onLocationFailure()``
///   and stop; other errors are transient (the "No GPS fix yet" timer covers them).
/// - Compass: every `CLHeading` is recorded into the observed declination
///   (``installDeclinationSource()``, done at launch), then
///   ``DirectionsViewModel/onHeading(trueHeading:magneticHeading:headingAccuracy:timeMs:)``.
///   `headingOrientation` follows the interface orientation of the active window (at start, on
///   every change of its geometry, and on ``refreshOrientation()``). The system calibration
///   screen is suppressed: the app shows its own figure-8 hint (``DirectionsViewModel/calibrate``).
/// - Device-wide Location Services (`locationServicesEnabled()`, read off the main thread) ->
///   ``DirectionsViewModel/setDeviceLocationOff(_:)``, at every start and authorization change.
@MainActor
@Observable
final class DirectionsLocationService {
    /// Core Location's own declination (`trueHeading − magneticHeading` of the latest heading
    /// with both), the process's ``Geo/declinationSource``.
    nonisolated static let declination = ObservedDeclination()

    /// Installs ``declination`` as ``Geo/declinationSource`` (once, at launch: ``KCNA26App``).
    nonisolated static func installDeclinationSource() {
        Geo.declinationSource = declination
    }

    /// Core Location's authorization for this app, as Core sees it (observable).
    private(set) var authorization: LocationTracker.Authorization

    /// Created on the first ``start(_:)``: the screen's `@State` may build and drop several
    /// services, so `init` stays cheap.
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private let delegate = DirectionsLocationDelegate()
    @ObservationIgnored private weak var viewModel: DirectionsViewModel?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var locationStarted = false
    @ObservationIgnored private var headingStarted = false
    @ObservationIgnored private var asked = false
    @ObservationIgnored private var orientationObservation: NSKeyValueObservation?
    @ObservationIgnored private var servicesCheck: Task<Void, Never>?

    /// `.notDetermined` until the first ``start(_:)`` reads it.
    init() {
        authorization = .notDetermined
    }

    /// The screen's manager (one per service, made on the main thread so its delegate calls
    /// arrive there).
    private func ensureManager() -> CLLocationManager {
        if let m = manager { return m }
        let m = CLLocationManager()
        m.desiredAccuracy = kCLLocationAccuracyBest
        m.distanceFilter = kCLDistanceFilterNone
        m.activityType = .fitness
        m.pausesLocationUpdatesAutomatically = false
        m.headingFilter = kCLHeadingFilterNone
        delegate.service = self
        m.delegate = delegate
        manager = m
        return m
    }

    // MARK: - Lifecycle

    /// The screen is visible and its scene active (Kotlin `LifecycleStartEffect` / resume):
    /// reads the device switch, asks for When-In-Use authorization the first time, starts
    /// location (if authorized) and the compass (if the device has one).
    func start(_ vm: DirectionsViewModel) {
        if viewModel !== vm {
            stop()
            viewModel = vm
        }
        running = true
        let manager = ensureManager()
        refreshDeviceLocation()
        let status = DirectionsLocationService.coreAuthorization(manager.authorizationStatus)
        if authorization != status { authorization = status }
        #if DEBUG
        if ScreenshotMode.directionsStarted(vm) { return }  // -screenshotScene <name> (ScreenshotMode.swift)
        #endif
        if status == .notDetermined && !asked {
            asked = true
            manager.requestWhenInUseAuthorization()
        }
        startLocationIfAllowed()
        startHeading()
    }

    /// The screen went away or its scene left `.active` (Kotlin `onStopOrDispose`).
    func stop() {
        running = false
        stopLocation()
        stopHeading()
        servicesCheck?.cancel()
        servicesCheck = nil
    }

    /// The readout's status (Kotlin DirectionsScreen's `when`), with Core Location's quirks
    /// (``LocationTracker/locStatus(_:deviceLocationOff:noFix:)``).
    func locStatus(_ vm: DirectionsViewModel) -> LocStatus {
        LocationTracker.locStatus(authorization, deviceLocationOff: vm.deviceLocationOff, noFix: vm.noFix)
    }

    /// "Allow location" / "Turn on location": the system dialog while it can still show
    /// (`.notDetermined`), else the app's page in Settings (iOS can't open the Location Services
    /// switch itself).
    func requestAccess() {
        if authorization == .notDetermined {
            asked = true
            ensureManager().requestWhenInUseAuthorization()
        } else {
            SystemLinks.openAppSettings()
        }
    }

    /// Re-reads the interface orientation for the compass (Kotlin `compass.refreshDisplay()` on
    /// a configuration change). Called on start and when the window's geometry changes; call it
    /// also when the window size changes.
    func refreshOrientation() {
        guard let manager, let scene = DirectionsLocationService.activeWindowScene() else { return }
        let raw: Int = scene.effectiveGeometry.interfaceOrientation.rawValue
        let value: Int32 = CompassSensor.headingOrientation(interfaceOrientationRawValue: raw)
        let orientation: CLDeviceOrientation = CLDeviceOrientation(rawValue: value) ?? .portrait
        if manager.headingOrientation != orientation { manager.headingOrientation = orientation }
    }

    // MARK: - Location

    private func startLocationIfAllowed() {
        guard running, !locationStarted, LocationTracker.hasLocationPermission(authorization), let vm = viewModel else { return }
        locationStarted = true
        vm.trackingStarted()
        ensureManager().startUpdatingLocation()
    }

    private func stopLocation() {
        guard locationStarted else { return }
        locationStarted = false
        manager?.stopUpdatingLocation()
        viewModel?.trackingStopped()
    }

    /// `locationServicesEnabled()` can block: off the main thread, then back.
    private func refreshDeviceLocation() {
        servicesCheck?.cancel()
        servicesCheck = Task { [weak self] in
            let enabled: Bool = await Task.detached(priority: .userInitiated) {
                CLLocationManager.locationServicesEnabled()
            }.value
            guard !Task.isCancelled, let self else { return }
            self.viewModel?.setDeviceLocationOff(!enabled)
        }
    }

    // MARK: - Compass

    private func startHeading() {
        guard running, !headingStarted, CLLocationManager.headingAvailable() else { return }
        headingStarted = true
        refreshOrientation()
        observeOrientation()
        ensureManager().startUpdatingHeading()
    }

    private func stopHeading() {
        guard headingStarted else { return }
        headingStarted = false
        manager?.stopUpdatingHeading()
        orientationObservation?.invalidate()
        orientationObservation = nil
    }

    /// The window rotating (also by 180°, which leaves its size alone) changes its geometry.
    private func observeOrientation() {
        orientationObservation?.invalidate()
        orientationObservation = nil
        guard let scene = DirectionsLocationService.activeWindowScene() else { return }
        orientationObservation = scene.observe(\.effectiveGeometry, options: [.new]) { [weak self] _, _ in
            guard let service = self else { return }
            Task { @MainActor in service.refreshOrientation() }
        }
    }

    // MARK: - Delegate callbacks (main thread: the manager was created on it)

    fileprivate func didUpdateLocation(_ reading: LocationReading) {
        guard locationStarted, let vm = viewModel else { return }
        vm.onLocation(reading)
        vm.setDeviceLocationOff(false)
    }

    fileprivate func didUpdateHeading(trueHeading: Double, magneticHeading: Double, headingAccuracy: Double, timeMs: Int64) {
        DirectionsLocationService.declination.record(
            trueHeading: trueHeading, magneticHeading: magneticHeading, headingAccuracy: headingAccuracy
        )
        guard headingStarted, let vm = viewModel else { return }
        vm.onHeading(trueHeading: trueHeading, magneticHeading: magneticHeading, headingAccuracy: headingAccuracy, timeMs: timeMs)
    }

    fileprivate func didFail(denied: Bool) {
        guard denied, running else { return }
        viewModel?.onLocationFailure()
        stopLocation()
    }

    fileprivate func authorizationChanged(_ status: LocationTracker.Authorization) {
        if authorization != status { authorization = status }
        guard running else { return }
        refreshDeviceLocation()
        if LocationTracker.hasLocationPermission(status) {
            startLocationIfAllowed()
        } else {
            stopLocation()
        }
    }

    // MARK: - Helpers

    /// `CLAuthorizationStatus` as Core sees it (an unknown future status counts as authorized:
    /// Core Location then reports `.denied` itself if it isn't).
    nonisolated static func coreAuthorization(_ status: CLAuthorizationStatus) -> LocationTracker.Authorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted, .denied: return .denied
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        @unknown default: return .authorized
        }
    }

    /// The foreground-active window scene (the one showing Directions), else any window scene.
    private static func activeWindowScene() -> UIWindowScene? {
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

/// The `CLLocationManagerDelegate`. Core Location calls it on the run loop of the thread that
/// created the manager, i.e. the main thread (``DirectionsLocationService`` is main-actor
/// isolated), so it hands each update over synchronously. Only `Sendable` values cross.
private final class DirectionsLocationDelegate: NSObject, CLLocationManagerDelegate {
    weak var service: DirectionsLocationService?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let reading = LocationReading(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            horizontalAccuracy: loc.horizontalAccuracy,
            altitude: loc.altitude,
            verticalAccuracy: loc.verticalAccuracy,
            ageSeconds: -loc.timestamp.timeIntervalSinceNow
        )
        let service = self.service
        MainActor.assumeIsolated { service?.didUpdateLocation(reading) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueHeading: Double = newHeading.trueHeading
        let magneticHeading: Double = newHeading.magneticHeading
        let accuracy: Double = newHeading.headingAccuracy
        let timeMs: Int64 = newHeading.timestamp.epochMillis
        let service = self.service
        MainActor.assumeIsolated {
            service?.didUpdateHeading(trueHeading: trueHeading, magneticHeading: magneticHeading, headingAccuracy: accuracy, timeMs: timeMs)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied: Bool = (error as? CLError)?.code == .denied
        let service = self.service
        MainActor.assumeIsolated { service?.didFail(denied: denied) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = DirectionsLocationService.coreAuthorization(manager.authorizationStatus)
        let service = self.service
        MainActor.assumeIsolated { service?.authorizationChanged(status) }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }
}

// MARK: - SwiftUI wiring

extension View {
    /// Runs `service` for `viewModel` while this view is on screen and its window's scene is
    /// active (Kotlin: `LifecycleStartEffect` for the tracker and the compass,
    /// `LifecycleResumeEffect` for the device switch), keeps the screen on meanwhile (Kotlin
    /// `KeepScreenOn`), and follows rotations for the compass. Put it on the live Directions
    /// content (not on the "no position" variant).
    func tracksDirectionsLocation(_ service: DirectionsLocationService, for viewModel: DirectionsViewModel) -> some View {
        modifier(DirectionsLocationModifier(service: service, viewModel: viewModel))
    }
}

private struct DirectionsLocationModifier: ViewModifier {
    let service: DirectionsLocationService
    let viewModel: DirectionsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.windowWidth) private var windowWidth
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                visible = true
                update()
            }
            .onDisappear {
                visible = false
                update()
            }
            .onChange(of: scenePhase) { _, _ in update() }
            .onChange(of: ObjectIdentifier(viewModel)) { _, _ in update() }
            .onChange(of: windowWidth) { _, _ in service.refreshOrientation() }
    }

    private func update() {
        let on: Bool = visible && scenePhase == .active
        if on {
            service.start(viewModel)
        } else {
            service.stop()
        }
        UIApplication.shared.isIdleTimerDisabled = on
    }
}
