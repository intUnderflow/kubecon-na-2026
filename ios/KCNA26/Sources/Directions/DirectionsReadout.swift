import SwiftUI
import UIKit

// Kotlin ui/directions/DirectionsReadout.kt: the floor headline, the floor instruction, the live
// readout under the map and the compass calibration hint. Texts, colours and the show/hide rules
// are Core's (`DirectionsLogic.readout`, `FloorReminder`, `DirectionsScreenUI`).

/// A line of ``TextRun``s as one `Text` (Kotlin `buildAnnotatedString` with `SpanStyle`s): each
/// run in `style` (bold runs in its bold face), coloured by its role; runs without a role take
/// the line's foreground style. Apply `.appTextStyle(style)` to the result.
func directionsRunsText(_ runs: [TextRun], style: AppTextStyle, colors: AppColors) -> Text {
    var line = Text(verbatim: "")
    for run in runs {
        var piece: Text = Text(verbatim: run.text).appFont(run.bold ? style.bold : style)
        if let role = run.role {
            piece = piece.foregroundStyle(Color(argb: role.argb(in: colors.palette)))
        }
        line = line + piece
    }
    return line
}

/// Kotlin `FloorHeadline`: "LEVEL 2 · SALT PALACE · 251 A–C" in large type (the engine's
/// ``FloorReminder/headline``, the web's `.loc`), the level in pink so the floor stands out.
/// VoiceOver reads the headline in plain words.
struct FloorHeadline: View {
    let reminder: FloorReminder

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(reminder: FloorReminder) {
        self.reminder = reminder
    }

    var body: some View {
        let style: AppTextStyle = type.display.copy(size: 30, lineHeight: 32)
        directionsRunsText(DirectionsScreenUI.headlineRuns(reminder), style: style, colors: colors)
            .appTextStyle(style)
            .foregroundStyle(colors.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text(verbatim: reminder.headline))
    }
}

/// Kotlin `FloorInstruction`: "Room is on Level 2: take the North Foyer escalator up", with the
/// up/down step icon. Nothing without an instruction (OFF).
struct FloorInstruction: View {
    let reminder: FloorReminder

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(reminder: FloorReminder) {
        self.reminder = reminder
    }

    var body: some View {
        if let instruction = reminder.instruction {
            HStack(alignment: .center, spacing: 10) {
                if let direction = reminder.direction {
                    StepIcon(direction)
                }
                Text(verbatim: instruction)
                    .appTextStyle(type.body.copy(size: 17, weight: .bold))
                    .foregroundStyle(colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Kotlin `LiveReadout`: everything under the map (the web's lvPaint #lv-d / #lv-s, without the
/// arrow):
/// - the line: "120 M NORTH-EAST · ±12 M", "YOU’RE ABOUT HERE · ±10 M" or the state
///   ("FINDING YOU…", "LOCATION IS OFF", "NO GPS FIX YET"); VoiceOver announces its changes
///   (Kotlin's polite live region), queued behind other speech;
/// - the floor instruction;
/// - the floor reminder when about here, or what to do without a fix, plus `action`
///   (allow location / turn it on);
/// - "GPS is weak indoors: follow the steps." above ±50 m;
/// - the small figure-8 hint while `calibrate` (the map's heading cone needs the compass). The
///   caller animates its appearance (`.animation(_:value: calibrate)` on the column, so the
///   views below move smoothly, like Compose's `expandVertically`).
struct LiveReadout: View {
    let readout: Readout
    let floor: FloorReminder
    let action: DirectionsScreenUI.LocationAction?
    let onAction: () -> Void
    let calibrate: Bool

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(
        readout: Readout,
        floor: FloorReminder,
        action: DirectionsScreenUI.LocationAction?,
        onAction: @escaping () -> Void,
        calibrate: Bool
    ) {
        self.readout = readout
        self.floor = floor
        self.action = action
        self.onAction = onAction
        self.calibrate = calibrate
    }

    var body: some View {
        let lineStyle: AppTextStyle = type.display.copy(
            size: CGFloat(DirectionsScreenUI.readoutFontSize(readout)),
            lineHeight: CGFloat(DirectionsScreenUI.READOUT_LINE_HEIGHT)
        )
        let detailStyle: AppTextStyle = readout.here ? type.body.copy(size: 16, weight: .bold) : type.small.copy(size: 15)
        let detailColor: Color = Color(argb: DirectionsScreenUI.detailRole(readout).argb(in: colors.palette))
        VStack(alignment: .leading, spacing: 0) {
            directionsRunsText(DirectionsScreenUI.readoutRuns(readout), style: lineStyle, colors: colors)
                .appTextStyle(lineStyle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(verbatim: readout.line))
                .accessibilityAddTraits(.updatesFrequently)
            if DirectionsScreenUI.showsFloorInstruction(readout, floor) && floor.instruction != nil {
                FloorInstruction(reminder: floor)
                    .padding(.top, 10)
            }
            if let detail = readout.detail {
                Text(verbatim: detail)
                    .appTextStyle(detailStyle)
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            if let weak = readout.weakGps {
                Text(verbatim: weak)
                    .appTextStyle(type.small.copy(size: 15, weight: .bold))
                    .foregroundStyle(colors.note)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            if let action {
                Button(action: onAction) {
                    CapsText(action.label, style: type.button)
                }
                .buttonStyle(.outline)
                .padding(.top, 10)
            }
            if calibrate {
                CalibrationHint()
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: readout.line) { _, line in
            DirectionsAnnouncer.announce(line)
        }
    }
}

/// Kotlin's polite live region on the readout line: VoiceOver speaks a changed line once the
/// current speech is done (`accessibilitySpeechQueueAnnouncement`), never interrupting it.
@MainActor
enum DirectionsAnnouncer {
    static func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let queued = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: queued)
    }
}

/// Kotlin `CalibrationHint` (shown while the view model's `calibrate` is on): a small,
/// unobtrusive figure-8 hint, because the heading cone needs a calibrated compass.
struct CalibrationHint: View {
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init() {}

    var body: some View {
        let text: Text = Text(verbatim: DirectionsText.CALIBRATE_TITLE).appFont(type.tiny.bold).foregroundStyle(colors.ink)
            + Text(verbatim: " ")
            + Text(verbatim: DirectionsText.CALIBRATE_BODY)
        HStack(alignment: .center, spacing: 8) {
            FigureEight()
                .frame(width: 34, height: 20)
            text
                .appTextStyle(type.tiny)
                .foregroundStyle(colors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Kotlin `FigureEight`: a lemniscate with a small phone travelling along it (2.4 s a lap).
/// Still when Reduce Motion is on (Android: no animation at animator scale 0).
private struct FigureEight: View {
    @Environment(\.appColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let note: Color = colors.note
        let ink: Color = colors.ink
        TimelineView(.animation(paused: reduceMotion)) { context in
            let u: Double = reduceMotion ? 0 : DirectionsScreenUI.figureEightPhase(atMs: context.date.timeIntervalSinceReferenceDate * 1000)
            Canvas { ctx, size in
                let a: Double = Double(size.width) / 2 - 4
                let cx: Double = Double(size.width) / 2
                let cy: Double = Double(size.height) / 2
                var path = Path()
                let points: [MapOffset] = DirectionsScreenUI.figureEightPath(a: a, cx: cx, cy: cy)
                for (i, p) in points.enumerated() {
                    let q = CGPoint(x: p.x, y: p.y)
                    if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
                }
                path.closeSubpath()
                ctx.stroke(path, with: .color(note), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

                let p: MapOffset = DirectionsScreenUI.figureEightPoint(u, a: a, cx: cx, cy: cy)
                let deg: Double = DirectionsScreenUI.figureEightPhoneDeg(u, a: a, cx: cx, cy: cy)
                var phone = ctx
                phone.translateBy(x: p.x, y: p.y)
                phone.rotate(by: .degrees(deg))
                phone.fill(Path(roundedRect: CGRect(x: -3, y: -5, width: 6, height: 10), cornerRadius: 1.5), with: .color(ink))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Readout") {
    ThemePreview {
        let floor = FloorReminder(
            level: 2, building: "Salt Palace", roomName: "251 A–C",
            action: "take the North Foyer escalator up", direction: .up, hops: 1
        )
        FloorHeadline(reminder: floor)
        LiveReadout(
            readout: Readout(
                headline: "120 m north-east", distance: "120 m", direction: "north-east",
                accuracy: "±12 m", detail: nil, weakGps: nil, here: false
            ),
            floor: floor,
            action: nil,
            onAction: {},
            calibrate: true
        )
        LiveReadout(
            readout: Readout(
                headline: DirectionsText.LOCATION_OFF, distance: nil, direction: nil,
                accuracy: nil, detail: DirectionsText.LOCATION_OFF_SUB, weakGps: nil, here: false
            ),
            floor: floor,
            action: .allowLocation,
            onAction: {},
            calibrate: false
        )
    }
}
