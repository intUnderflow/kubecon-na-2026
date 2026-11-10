# KubeCon NA 2026 (Android)

An unofficial offline Android app for KubeCon + CloudNativeCon North America 2026 and the CNCF Maintainer Summit (Salt Lake City, November 8–12, 2026).

## Install

### [Download the APK](https://github.com/intUnderflow/kubecon-na-2026/releases/latest/download/kubecon-na-2026.apk)

Needs Android 12 or later.

1. On your phone, tap the link above to download `kubecon-na-2026.apk`.
2. Open the file. If Android asks, allow your browser or Files app to install apps.
3. Tap **Install**. That's it.

**Updates:** download the new APK from the same link and install it over the old one. Your settings stay.

## Screenshots

| Schedule | Monday | Directions | Session |
|---|---|---|---|
| <img src="docs/screenshots/cover-schedule.png" width="200" alt="Schedule"> | <img src="docs/screenshots/cover-monday.png" width="200" alt="Monday's co-located events"> | <img src="docs/screenshots/cover-directions.png" width="200" alt="Directions"> | <img src="docs/screenshots/cover-session.png" width="200" alt="Session details"> |

| Inner screen: list and detail | Inner screen: directions | Dark theme |
|---|---|---|
| <img src="docs/screenshots/inner-list-detail.png" width="300" alt="List and detail on the inner screen"> | <img src="docs/screenshots/inner-directions.png" width="300" alt="Directions on the inner screen"> | <img src="docs/screenshots/dark-schedule.png" width="200" alt="Dark theme"> |

## Features

- **Schedule.** Day tabs open on today, in conference time (America/Denver). Sessions sit in half-hour blocks; live sessions show the minutes left, and finished ones drop off. Search covers titles, speakers, rooms and categories for the rest of the week.
- **My talks.** Pick your name under "I'm speaking as" (the app asks on first launch; the default is None). Your talks get a banner, a highlight and a mark on the day tab, plus reminders 30 and 10 minutes before.
- **RSVP.** Tap the star on the sessions you plan to attend. You get a reminder before each one (Off, 5, 10 or 15 minutes; 10 by default), an "Up next" row for today, a note when two RSVP’d sessions clash, and an RSVP’d filter that shows only those sessions and your own talks. RSVPs stay on your phone; they don’t register you with the organisers.
- **Co-located events.** Monday's CNCF-hosted co-located events are cards showing what's on now and next, each with its full agenda.
- **Session details.** Full description, speakers and their taglines, room, time and a link to the official page.
- **Indoor directions.** A venue map with your position and step-by-step walking directions between rooms and entrances, with reminders when the route changes floor. The "From" list puts the nearest places first.
- **Offline, with live data updates.** All data ships inside the app. When online, it checks this repository for newer schedule data and switches to it once the download has passed its checks.
- **Foldable layouts.** One column on the cover screen, list and detail side by side on the inner screen. Folding or unfolding keeps your place.
- Talks with Anthropic speakers carry a small Anthropic badge.

## Privacy and permissions

- **Location:** used only while Directions is open, to show where you are (and which way you face) on the map. It stays on the device and is never stored or sent anywhere.
- **Notifications and alarms:** for the reminders, which are scheduled on the device (and re-armed after a reboot).
- **Network:** the app makes only two kinds of request, and neither sends anything about you:
  - the data update check, which fetches `data/manifest.json` and any changed data files from `raw.githubusercontent.com/intUnderflow/kubecon-na-2026`;
  - session descriptions missing from the bundled data, fetched from Sessionize's public API.
- No accounts, analytics, ads or trackers. Your settings and RSVPs stay on the device.

## Updating the data

Installed apps pick up new data from the `main` branch of this repository: on start, and when they come back to the foreground after at least 15 minutes.

1. `python3 -I scripts/fetch_details.py` refreshes session descriptions (`data/details.json`).
2. `python3 -I scripts/fetch_colocated.py` refreshes the co-located events (`data/colocated.json`, `data/colocated_details.json`).
3. `python3 -I scripts/apply_updates.py <updates file>` applies a day's schedule changes to `data/schedule.json`. If you keep the updates file in `data/updates/`, strip personal fields (such as `youUpvoted`) first.
4. `python3 -I scripts/make_manifest.py --sync-assets` bumps the version in `data/manifest.json` and copies the data into the app's assets.
5. Run `cd android && ./gradlew testDebugUnitTest`, then commit and push.

Apps ignore data whose version isn't higher than the one they have, so never hand-edit `data/manifest.json` back to an older version: fix forward (edit the data, run the script, push). Each file is verified by SHA-256 and size, and the whole set is parsed and cross-checked before the app switches to it. If anything fails, the app keeps the data it has.

## Building from source

You need JDK 17 or later (Android Studio's bundled JDK works) and the Android SDK (compile SDK 37).

The Android app is the Gradle project in `android/`:

```sh
cd android
./gradlew assembleDebug   # app/build/outputs/apk/debug/app-debug.apk
```

Release builds are signed only when these Gradle properties are set, for example in `~/.gradle/gradle.properties` (keep them out of the repository):

```properties
KCNA26_STORE_FILE=/path/to/release.jks
KCNA26_STORE_PASSWORD=…
KCNA26_KEY_ALIAS=…
KCNA26_KEY_PASSWORD=…
```

Without them, `./gradlew assembleRelease` builds an unsigned APK. A fork can point the app at its own data with `-PKCNA26_DATA_BASE_URL=https://raw.githubusercontent.com/<you>/<repo>/main/data/`.

## Credits

- Schedule data comes from the official KubeCon + CloudNativeCon North America 2026 and CNCF agendas via Sessionize. Session descriptions and speaker taglines are written by the speakers. The data is not covered by the MIT licence.
- Fonts: [Barlow Condensed](https://github.com/jpt/barlow) and [Atkinson Hyperlegible](https://www.brailleinstitute.org/freefont/), both under the SIL Open Font License 1.1 (see `android/app/src/main/assets/licenses/`).
- App icon: the Kubernetes logo from the CNCF artwork repository (https://github.com/cncf/artwork). Kubernetes is a registered trademark of The Linux Foundation; use follows the Linux Foundation trademark usage guidelines (https://www.linuxfoundation.org/trademark-usage).

This is an unofficial community app. It is not affiliated with or endorsed by the CNCF, the Linux Foundation or Anthropic.

## License

MIT (see [LICENSE](LICENSE)). It covers the code; the schedule data and fonts keep their own terms.
