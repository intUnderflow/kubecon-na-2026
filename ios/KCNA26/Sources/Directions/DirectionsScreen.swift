import SwiftUI
import os

/// Kotlin ui/directions/DirectionsScreen.kt `DirectionsScreen`: directions to a session's room
/// (a live map, no compass arrow and no Google Maps button; web: wayHTML, lvPaint, mapSVG).
/// Pushed on the navigation stack for a session (also from a tapped reminder).
///
/// - Header: the system navigation bar (back) with "DIRECTIONS · WED 10:15–10:45 AM", then the
///   session title; then the room's level, building and name in large type ("LEVEL 2 · SALT
///   PALACE · 251 A–C").
/// - A big live north-up ``VenueMap``: route, me (dot, accuracy circle, heading cone),
///   destination.
/// - Under it: the live distance and accuracy, the floor instruction, "You’re about here",
///   weak-GPS and permission / no-fix states, the figure-8 hint (``LiveReadout``).
/// - Then the From picker, the route summary and the turn-by-turn steps. With a fix, the From
///   menu lists the entrances and rooms nearest first, frozen from the moment it opens.
/// - Location and the compass (for the heading cone only) run only while this screen is visible
///   in an active scene, and the screen is kept on meanwhile (``DirectionsLocationService``, via
///   `.tracksDirectionsLocation`). Location permission is requested here.
/// - Compact: one scrolling column, the map about half the window high. Wide: the map fills the
///   left column; header, readout, From picker and steps scroll on the right. Either way the From
///   picker sits above the steps, as the route texts say ("pick a room or entrance above").
/// - State survives a compact/wide switch: the view model, the From picker (open state and its
///   frozen sort point) and the map camera live in this view, above the branch; the camera is
///   also kept in the scene's storage (state restoration); the From choice is in settings.
///
/// - Parameters:
///   - sessionId: the session to route to (may be unknown to the data: "Unknown session").
///   - onBack: leave Directions (``NavModel/pop()``). The system back button and the edge swipe
///     pop the stack themselves, so the screen has no back control of its own.
struct DirectionsScreen: View {
    let sessionId: String
    let onBack: () -> Void

    @Environment(AppGraph.self) private var graph
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type
    @Environment(\.widthClass) private var widthClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var models = DirectionsScreenModels()
    @State private var location = DirectionsLocationService()
    /// The From picker is open (Kotlin `fromOpen`, hoisted above the compact/wide branch).
    @State private var fromOpen = false
    /// Where the open From menu is sorted from: the fix as it opened (nil: none, so grouped).
    /// Kept while it's open so new fixes don't move items; taken again on every opening.
    @State private var fromAt: PointXY?
    /// The map camera for state restoration (``DirectionsScreenUI/storedCamera(_:_:)``).
    @SceneStorage("kcna26.directions.camera") private var savedCamera: String = ""

    init(sessionId: String, onBack: @escaping () -> Void) {
        self.sessionId = sessionId
        self.onBack = onBack
    }

    var body: some View {
        let repo: Repository = graph.repository
        // Keyed by the data set too: after a live data update (room change) it routes with the new data.
        let vm: DirectionsViewModel = models.viewModel(
            repo: repo, router: graph.router, settings: graph.settings, clock: graph.clock, sessionId: sessionId
        )
        let camera: MapCameraState = models.camera(restoring: DirectionsScreenUI.restoredCamera(sessionId, savedCamera))
        let label: String = DirectionsScreenUI.topBarLabel(repo, vm.session)
        let wide: Bool = widthClass.isWide
        GeometryReader { geo in
            // Kotlin `LocalWindowInfo.current.containerDpSize.height`: the whole window.
            let windowHeight: Double = Double(geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            VStack(alignment: .leading, spacing: 0) {
                DirectionsTitle(title: DirectionsScreenUI.title(vm.session))
                if let live = DirectionsScreenUI.live(vm.session, vm.room, vm.target) {
                    LiveDirections(
                        vm: vm,
                        live: live,
                        venue: repo.venue,
                        wide: wide,
                        windowHeight: windowHeight,
                        location: location,
                        camera: camera,
                        fromOpen: $fromOpen,
                        fromAt: $fromAt
                    )
                    .tracksDirectionsLocation(location, for: vm)
                } else {
                    DirectionsUnavailable(session: vm.session)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background(colors.bg)
        .navigationTitle(Text(verbatim: label))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                CapsText(label, style: type.sectionLabel, color: colors.muted, lineLimit: 1)
            }
        }
        .toolbarBackground(colors.bg, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in
            // Kotlin's rememberSaveable: what a recreated screen comes back to.
            if phase != .active {
                savedCamera = DirectionsScreenUI.storedCamera(sessionId, MapCameraState.Saver.save(camera))
            }
        }
        .onDisappear {
            // Left for good (popped): the map's framing ends, and a later visit starts afresh.
            camera.stopFraming()
            savedCamera = ""
        }
    }
}

/// The screen's long-lived objects, made once per screen (Kotlin: the activity-scoped
/// `viewModel(key = "dir-<id>-<repo>")` and `rememberMapCameraState()`). The view model is
/// rebuilt when the data set changes (a live update).
@MainActor
@Observable
final class DirectionsScreenModels {
    @ObservationIgnored private var cached: (repo: ObjectIdentifier, vm: DirectionsViewModel)?
    @ObservationIgnored private var cachedCamera: MapCameraState?

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.kcna26",
        category: CompassSensor.TAG
    )

    init() {}

    func viewModel(
        repo: Repository,
        router: Router,
        settings: SettingsStore,
        clock: any AppClock,
        sessionId: String
    ) -> DirectionsViewModel {
        let id = ObjectIdentifier(repo)
        if let c = cached, c.repo == id, c.vm.sessionId == sessionId { return c.vm }
        let vm = DirectionsViewModel(
            repo: repo,
            router: router,
            settings: settings,
            clock: clock,
            sessionId: sessionId,
            log: { DirectionsScreenModels.log($0) }
        )
        cached = (id, vm)
        return vm
    }

    /// The map camera: restored from `saved` (``MapCameraState/Saver``) the first time, else a
    /// following one.
    func camera(restoring saved: String?) -> MapCameraState {
        if let c = cachedCamera { return c }
        let c: MapCameraState = saved.flatMap { MapCameraState.Saver.restore($0) } ?? MapCameraState()
        cachedCamera = c
        return c
    }

    /// The compass debug log (Kotlin `Log.d(CompassSensor.TAG, …)`).
    nonisolated private static func log(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}

/// Kotlin `TopBar`'s title (the label is in the navigation bar, the back arrow is the system's):
/// the session title, at most two lines.
private struct DirectionsTitle: View {
    let title: String

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        Text(verbatim: title)
            .appTextStyle(type.cardTitle)
            .foregroundStyle(colors.ink)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CGFloat(Dimens.pagePadding))
            .padding(.top, 4)
            .padding(.bottom, 8)
    }
}

/// Kotlin `Unavailable`: OFF ("Off-site") and rooms without a position: just the explanation and
/// the official listing (nothing for an unknown session).
private struct DirectionsUnavailable: View {
    let session: Session?

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let session {
                    Text(verbatim: DirectionsScreenUI.unavailableText(session))
                        .appTextStyle(type.body.copy(size: 17))
                        .foregroundStyle(colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if let url = URL(string: session.officialUrl) {
                            openURL(url)
                        }
                    } label: {
                        CapsText(DirectionsText.OFFICIAL_LISTING, style: type.button)
                    }
                    .buttonStyle(.outline)
                    .padding(.top, 16)
                }
            }
            .widthIn(max: CGFloat(Dimens.maxTextWidth))
            .padding(.horizontal, CGFloat(Dimens.pagePadding))
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Kotlin `LiveDirections`: the map, the readout, the route card and the map note, in one
/// scrolling column (compact) or map left / text right (wide).
private struct LiveDirections: View {
    let vm: DirectionsViewModel
    let live: DirectionsScreenUI.Live
    let venue: Venue
    let wide: Bool
    let windowHeight: Double
    let location: DirectionsLocationService
    let camera: MapCameraState
    @Binding var fromOpen: Bool
    @Binding var fromAt: PointXY?

    var body: some View {
        let room: Room = live.room
        let status: LocStatus = location.locStatus(vm)
        let fix: Fix? = vm.fix
        // Recomputed per fix; SwiftUI redraws only what changed.
        let readout: Readout = DirectionsLogic.readout(live.target, live.level, fix, status)
        let action: DirectionsScreenUI.LocationAction? = DirectionsScreenUI.locationAction(readout, status)
        let plan: RoutePlan? = vm.plan
        let route: Route? = plan?.route
        let floor: FloorReminder = FloorReminder.of(room, route)
        let points: [PointXY] = DirectionsScreenUI.mapPoints(route, room)
        let selected: String = DirectionsScreenUI.selectedFrom(plan, vm.options, vm.directionsFrom)
        let calibrate: Bool = vm.calibrate
        let map = VenueMap(
            venue: venue,
            room: room,
            points: points,
            live: route?.live == true,
            here: readout.here,
            fix: fix,
            heading: { vm.heading },
            camera: camera
        )
        let readoutView = LiveReadout(
            readout: readout,
            floor: floor,
            action: action,
            onAction: { location.requestAccess() },
            calibrate: calibrate
        )
        let card = RouteCard(
            plan: plan,
            options: vm.options,
            selected: selected,
            fromOpen: fromOpen,
            onFromOpenChange: { open in
                if open && !fromOpen { fromAt = vm.fix?.pos }
                fromOpen = open
            }
        )
        Group {
            if wide {
                wideLayout(map: map, floor: floor, readout: readoutView, card: card)
            } else {
                compactLayout(map: map, floor: floor, readout: readoutView, card: card)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: calibrate)
        .sheet(isPresented: $fromOpen) {
            FromMenuSheet(menu: vm.options.menu(fromAt), selected: selected) { key in
                fromOpen = false
                vm.setFrom(key)
                camera.refit() // a new route: show all of it
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// About half the window high, whatever the window (PROMPT redesign: 45–55 %).
    private func compactLayout(map: VenueMap, floor: FloorReminder, readout: LiveReadout, card: RouteCard) -> some View {
        let mapHeight: CGFloat = CGFloat(DirectionsScreenUI.compactMapHeight(windowHeight: windowHeight))
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FloorHeadline(reminder: floor)
                map
                    .frame(maxWidth: .infinity)
                    .frame(height: mapHeight)
                readout
                card
                MapNote()
            }
            .padding(.horizontal, CGFloat(Dimens.pagePadding))
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private func wideLayout(map: VenueMap, floor: FloorReminder, readout: LiveReadout, card: RouteCard) -> some View {
        GeometryReader { geo in
            let row: Double = max(0, min(Double(geo.size.width), DirectionsScreenUI.WIDE_MAX_WIDTH) - 16)
            let mapWidth: CGFloat = CGFloat(row * DirectionsScreenUI.WIDE_MAP_WEIGHT)
            let columnWidth: CGFloat = CGFloat(row) - mapWidth
            HStack(alignment: .top, spacing: 0) {
                map
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .frame(width: mapWidth)
                    .frame(maxHeight: .infinity)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        FloorHeadline(reminder: floor)
                        readout
                        card
                        MapNote()
                    }
                    .widthIn(max: CGFloat(Dimens.maxTextWidth))
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: columnWidth)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Kotlin `RouteCard`: the From picker, the summary, the fallback note and the steps.
private struct RouteCard: View {
    let plan: RoutePlan?
    let options: FromOptions
    let selected: String
    let fromOpen: Bool
    let onFromOpenChange: (Bool) -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(Dimens.bannerRadius), style: .circular)
        VStack(alignment: .leading, spacing: 0) {
            FromPicker(options: options, selected: selected, expanded: fromOpen, onExpandedChange: onFromOpenChange)
            if let plan {
                if !plan.summary.isEmpty {
                    CapsText(plan.summary, style: type.routeSummary, color: colors.ink)
                        .padding(.top, 14)
                }
                if plan.showFallbackNote {
                    Text(verbatim: DirectionsText.FALLBACK_NOTE)
                        .appTextStyle(type.tiny)
                        .foregroundStyle(colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                if let route = plan.route {
                    StepsList(steps: route.steps)
                        .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface, in: shape)
        .overlay {
            shape.strokeBorder(colors.line, lineWidth: 1)
        }
    }
}

/// Kotlin `MapNote`: the web's note under its map (without its Google Maps pin link).
private struct MapNote: View {
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        Text(verbatim: DirectionsText.MAP_NOTE)
            .appTextStyle(type.tiny)
            .foregroundStyle(colors.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
    }
}
