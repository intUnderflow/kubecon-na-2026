# KubeCon NA 2026 for iOS

The iOS (SwiftUI) version of the app: a native port of the Android app in `../android/`, with
the same screens, rules, texts and bundled data. iOS 17 or later, iPhone and iPad.

## Layout

```
ios/
  KCNA26.xcodeproj        the app (one target, KCNA26)
  KCNA26/
    Sources/              SwiftUI views and the iOS services (an Xcode synchronized folder:
                          new files join the target automatically)
      App/  Platform/  Theme/  Components/  Schedule/  Going/  Session/  Settings/  Directions/
    Resources/Data/       the bundled schedule data (copied from ../data by scripts/make_manifest.py)
    Resources/Fonts/      Barlow Condensed and Atkinson Hyperlegible (Info.plist UIAppFonts)
    Resources/Licenses/   the fonts' licences
    Assets.xcassets       app icon, accent and launch colours
    Info.plist            keys that have no build setting (merged with the generated ones)
  Core/                   Swift package KCNA26Core: everything that isn't UI
    Sources/KCNA26Core/   data, schedule rules, routing, sync, reminders, view models
    Tests/KCNA26CoreTests/
```

The Xcode target compiles `KCNA26/Sources` and `Core/Sources/KCNA26Core` into one module, so the
views use Core's types directly (no `import`, nothing needs to be `public`). The same Core sources
also form a Swift package with its own tests, which build and run on macOS and Linux:

```sh
cd ios/Core && swift test
```

Core is a port of the Kotlin code, file by file, and every Kotlin unit test has a Swift twin of
the same name. [Core/CONVENTIONS.md](Core/CONVENTIONS.md) explains how Kotlin maps to Swift
(time zones, ordered JSON, stable sorting, UTF-16 string rules, rounding) and documents each
area's API. [KCNA26/UI_CONVENTIONS.md](KCNA26/UI_CONVENTIONS.md) describes the SwiftUI side:
theme, components, icons and the screens' entry points.

## Platform differences from Android

- **Reminders** are local notifications (`UNUserNotificationCenter`). iOS keeps at most 64
  pending, so the app schedules the soonest 60 and tops them up whenever it opens or anything
  changes. A tap on a reminder opens Directions to the session.
- **Directions** uses Core Location for position and heading (true heading when available).
- **Data updates** are checked at launch and when the app comes back to the foreground after at
  least 15 minutes, like Android. The crash guard for downloaded data uses a launch marker:
  iOS can't catch a crash, so a launch that finds the previous run's marker still set counts it.
- **Wide windows** (iPad, landscape on large phones) show the schedule list and session details
  side by side, like a foldable's inner screen.

## Debugging

- Fake time: run with the launch argument `-fakeNow 2026-11-11T09:00:00-07:00` (Debug builds;
  the shared scheme has it, disabled, under Run > Arguments). `-fakeNow clear` goes back to the
  real time. The fake time keeps ticking and survives restarts.
- Screenshots: `-screenshotScene <name>` (Debug builds) stages one of the README screenshots
  (`schedule`, `monday`, `session`, `directions`, `list-detail`, `ipad-directions`; the scenes
  are in Core's `App/ScreenshotScene.swift`, the app's hooks in `App/ScreenshotMode.swift`).
  `scripts/screenshots.sh <KCNA26.app> <dir>` takes them all in fresh simulators; the
  **iOS screenshots** workflow (`.github/workflows/ios-screenshots.yml`, run by hand or by a
  commit message containing `[screenshots]`) commits them to `docs/screenshots/ios/`.
- Data source: the `KCNA26_DATA_BASE_URL` build setting (Info.plist `KCNA26DataBaseURL`) is where
  the app looks for newer data; it must end with `/`.

## Builds

GitHub Actions (`.github/workflows/ios.yml`) runs the Core tests on macOS and Linux and builds the
app for the simulator (Debug) and for devices (Release, unsigned) on every push that touches
`ios/`. Publishing a GitHub release, or running the **iOS release** workflow
(`.github/workflows/ios-release.yml`), attaches an unsigned `kubecon-na-2026.ipa` to the release;
the main README explains how to install it.
