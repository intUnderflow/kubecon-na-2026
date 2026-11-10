#!/usr/bin/env bash
# Takes the iOS screenshots (the twins of docs/screenshots/*.png) in fresh simulators.
#
#   ios/scripts/screenshots.sh <KCNA26.app> <output dir>
#
# <KCNA26.app> is a Debug build for the simulator, e.g.
#   xcodebuild -project ios/KCNA26.xcodeproj -scheme KCNA26 -configuration Debug \
#     -destination 'generic/platform=iOS Simulator' -derivedDataPath build/sim CODE_SIGNING_ALLOWED=NO build
#   ios/scripts/screenshots.sh build/sim/Build/Products/Debug-iphonesimulator/KCNA26.app docs/screenshots/ios
#
# The app's debug screenshot scenes do the staging (launch argument -screenshotScene <name>; see
# ios/Core/Sources/KCNA26Core/App/ScreenshotScene.swift and ios/KCNA26/Sources/App/ScreenshotMode.swift):
# fake time, "speaking as" Lucy Sweet, the RSVPs, the open screen. This script picks the newest
# iOS runtime, an iPhone Pro and the largest iPad Pro, creates and boots fresh simulators, sets a
# clean status bar, grants location, puts the simulated GPS where the Directions scene expects it,
# and takes one screenshot per scene:
#
#   iphone-schedule.png  iphone-monday.png  iphone-session.png  iphone-directions.png
#   iphone-dark-schedule.png  ipad-list-detail.png  ipad-directions.png
#
# scaled (sips -Z) to about 1080 px on the long side, like the Android files. The simulators it
# creates are deleted at the end, also on failure.
#
# macOS only (xcrun simctl, sips); bash 3.2 and BSD tools; python3 reads simctl's JSON.
# Environment (optional): SHOT_WAIT (seconds after launch, default 8), DIRECTIONS_WAIT (default
# 12), FIRST_WAIT (the first launch after install, default 15), MAX_PX (default 1080).

set -euo pipefail

BUNDLE_ID="app.kcna26"
SCENE_ARGUMENT="-screenshotScene"
# ScreenshotScene.DIRECTIONS_LOCATION: ~190 m north of Regency Ballroom B, by the Salt Palace's
# North Foyer (ScreenshotSceneTests checks that this line matches the Swift constant).
LOCATION="40.767297,-111.894890"
SHOT_WAIT="${SHOT_WAIT:-8}"
DIRECTIONS_WAIT="${DIRECTIONS_WAIT:-12}"
FIRST_WAIT="${FIRST_WAIT:-15}"
MAX_PX="${MAX_PX:-1080}"

log() {
  printf '[screenshots %s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  log "error: $*" >&2
  exit 1
}

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <path to KCNA26.app (Debug, iphonesimulator)> <output dir>" >&2
  exit 2
fi

APP="$1"
OUT="$2"
[ -d "$APP" ] || die "no app bundle at $APP"
[ -f "$APP/Info.plist" ] || die "$APP has no Info.plist (not an app bundle?)"
command -v xcrun >/dev/null 2>&1 || die "xcrun not found (macOS with Xcode needed)"
command -v python3 >/dev/null 2>&1 || die "python3 not found"
command -v sips >/dev/null 2>&1 || die "sips not found"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kcna26-screenshots.XXXXXX")"
CREATED=""

cleanup() {
  local status=$?
  set +e
  for udid in $CREATED; do
    log "deleting simulator $udid"
    xcrun simctl shutdown "$udid" >/dev/null 2>&1
    xcrun simctl delete "$udid" >/dev/null 2>&1
  done
  rm -rf "$WORK"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# --- pick the runtime and the device types -------------------------------------------------

cat > "$WORK/pick.py" <<'PY'
import json
import re
import sys

data = json.load(sys.stdin)


def version(runtime):
    return tuple(int(x) for x in re.findall(r"\d+", runtime.get("version", "")))


runtimes = [
    r for r in data.get("runtimes", [])
    if r.get("isAvailable") and (r.get("platform") == "iOS" or ".SimRuntime.iOS-" in r.get("identifier", ""))
]
if not runtimes:
    sys.exit("no available iOS simulator runtime")
runtime = max(runtimes, key=version)

types = runtime.get("supportedDeviceTypes") or data.get("devicetypes", [])


def family(t):
    if t.get("productFamily"):
        return t["productFamily"]
    name = t.get("name", "")
    for f in ("iPhone", "iPad"):
        if name.startswith(f):
            return f
    return ""


phones = [t for t in types if family(t) == "iPhone"]
pads = [t for t in types if family(t) == "iPad"]


def pick_phone():
    for t in phones:
        if t["name"] == "iPhone 17 Pro":
            return t
    numbered = []
    for i, t in enumerate(phones):
        m = re.match(r"^iPhone (\d+) Pro$", t["name"])
        if m:
            numbered.append((int(m.group(1)), i))
    if numbered:
        return phones[max(numbered)[1]]
    pros = [t for t in phones if " Pro" in t["name"] and "Max" not in t["name"]]
    if pros:
        return pros[-1]
    return phones[-1] if phones else None


def pick_pad():
    best = None
    for i, t in enumerate(pads):
        if not t["name"].startswith("iPad Pro"):
            continue
        m = re.search(r"(\d+(?:\.\d+)?)-inch", t["name"])
        key = (float(m.group(1)) if m else 0.0, i)
        if best is None or key > best[0]:
            best = (key, t)
    if best:
        return best[1]
    return pads[-1] if pads else None


phone = pick_phone()
pad = pick_pad()
if phone is None or pad is None:
    sys.exit("runtime %s has no iPhone or no iPad device type" % runtime.get("name"))
for line in (runtime["identifier"], runtime.get("name", ""), phone["identifier"], phone["name"], pad["identifier"], pad["name"]):
    print(line)
PY

xcrun simctl list -j > "$WORK/simctl.json"
python3 "$WORK/pick.py" < "$WORK/simctl.json" > "$WORK/picked.txt" || die "couldn't pick a runtime and devices"
RUNTIME_ID="$(sed -n 1p "$WORK/picked.txt")"
RUNTIME_NAME="$(sed -n 2p "$WORK/picked.txt")"
PHONE_TYPE="$(sed -n 3p "$WORK/picked.txt")"
PHONE_NAME="$(sed -n 4p "$WORK/picked.txt")"
PAD_TYPE="$(sed -n 5p "$WORK/picked.txt")"
PAD_NAME="$(sed -n 6p "$WORK/picked.txt")"
log "runtime: $RUNTIME_NAME ($RUNTIME_ID)"
log "iPhone: $PHONE_NAME; iPad: $PAD_NAME"

# --- simulator helpers ---------------------------------------------------------------------

# new_simulator <label> <device type>: creates a fresh simulator (deleted on exit) and sets
# NEW_UDID. Not run in $(...), so CREATED keeps the UDID for the clean-up.
NEW_UDID=""
new_simulator() {
  local label="$1" type="$2"
  NEW_UDID="$(xcrun simctl create "kcna26 screenshots $label" "$type" "$RUNTIME_ID")"
  [ -n "$NEW_UDID" ] || die "simctl create gave no UDID for $label"
  CREATED="$CREATED $NEW_UDID"
}

# A clean status bar: 9:41, full Wi-Fi and battery (applied after boot and again before each shot).
# Cosmetic: a failure only warns.
clean_status_bar() {
  xcrun simctl status_bar "$1" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName "" \
    --batteryState charged --batteryLevel 100 \
    || log "warning: simctl status_bar override failed (the shots keep the real status bar)"
}

prepare_simulator() {
  local udid="$1"
  log "booting $udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  log "status bar, app, location permission and position, light appearance"
  clean_status_bar "$udid"
  xcrun simctl install "$udid" "$APP"
  # Belt and braces: the Directions scenes feed their own fix and never ask for permission.
  xcrun simctl privacy "$udid" grant location "$BUNDLE_ID" || log "warning: simctl privacy grant location failed"
  xcrun simctl location "$udid" set "$LOCATION" || log "warning: simctl location set failed"
  xcrun simctl ui "$udid" appearance light
  # The first launch after an install is slow (and may show one-off system UI): warm up.
  launch_scene "$udid" schedule
  sleep "$FIRST_WAIT"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

launch_scene() {
  local udid="$1" scene="$2"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$BUNDLE_ID" "$SCENE_ARGUMENT" "$scene" >/dev/null
}

# shoot <udid> <scene> <file name> <seconds to wait>
shoot() {
  local udid="$1" scene="$2" file="$3" wait="$4"
  log "$scene -> $file"
  clean_status_bar "$udid"
  launch_scene "$udid" "$scene"
  sleep "$wait"
  xcrun simctl io "$udid" screenshot --type=png "$OUT/$file" >/dev/null
  sips -Z "$MAX_PX" "$OUT/$file" >/dev/null
  log "  $(sips -g pixelWidth -g pixelHeight "$OUT/$file" | awk '/pixelWidth/ { w = $2 } /pixelHeight/ { h = $2 } END { print w "x" h }') px"
}

finish_simulator() {
  local udid="$1"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
}

# --- iPhone --------------------------------------------------------------------------------

new_simulator iPhone "$PHONE_TYPE"
PHONE="$NEW_UDID"
log "iPhone simulator $PHONE"
prepare_simulator "$PHONE"
shoot "$PHONE" schedule iphone-schedule.png "$SHOT_WAIT"
shoot "$PHONE" monday iphone-monday.png "$SHOT_WAIT"
shoot "$PHONE" session iphone-session.png "$SHOT_WAIT"
shoot "$PHONE" directions iphone-directions.png "$DIRECTIONS_WAIT"
xcrun simctl ui "$PHONE" appearance dark
shoot "$PHONE" schedule iphone-dark-schedule.png "$SHOT_WAIT"
finish_simulator "$PHONE"

# --- iPad ----------------------------------------------------------------------------------

new_simulator iPad "$PAD_TYPE"
PAD="$NEW_UDID"
log "iPad simulator $PAD"
prepare_simulator "$PAD"
shoot "$PAD" list-detail ipad-list-detail.png "$SHOT_WAIT"
shoot "$PAD" ipad-directions ipad-directions.png "$DIRECTIONS_WAIT"
finish_simulator "$PAD"

log "done: $(cd "$OUT" && echo *.png)"
