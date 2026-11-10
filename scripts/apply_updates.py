#!/usr/bin/env python3
"""Apply a day's updates file to data/schedule.json (and data/unconference.json, if present).

Usage (from the repository root):

    python3 -I scripts/apply_updates.py data/updates/2026-11-08-sunday.json

The updates file (see data/updates/) has this shape:

    {
      "_about": "Updates for Sun Nov 8, 2026, checked at 2:03 PM MST against ...",
      "checkedAt": "2026-11-08T14:03:00-07:00",      (optional; else read from _about)
      "sessionUpdates": [ { full schedule.json session, plus optional "discussionUrl" } ],
      "topicUpdates":   [ { "number": 115, "title": ..., "votes": ..., "comments": ...,
                            "youUpvoted": ..., "picked": null | {"sessionId", "start", "room", "roomName"} } ]
    }

What it does (its "howToApply"):

- schedule.json: each entry of sessionUpdates replaces the session with the same id
  (all fields given). The precomputed isMine / hasAnthropicSpeaker flags are recomputed
  the documented way (the app works them out at runtime anyway). Key order follows the
  existing session so diffs stay small; new keys (discussionUrl) go at the end.
- unconference.json: for each entry of topicUpdates, the topic with the same number gets
  the given title, votes, comments, youUpvoted and picked (null when not picked). Other
  topic fields are left alone. "checkedAt" records when the votes and picks were checked.
  The app's unconference (voting) feature was removed after the Summit's voting ended, and
  data/unconference.json with it. When that file doesn't exist, topicUpdates are skipped
  (the script says so) and only schedule.json is updated.
- Each updated file gets a provenance sentence in "_about", and the copies the apps bundle
  (android/app/src/main/assets/ and ios/KCNA26/Resources/Data/) are refreshed.

Everything is validated before anything is written: every id and number must exist,
times must carry a UTC offset, rooms must exist in rooms.json, and picked.sessionId must
match a session (with the same start and room). On any error nothing is written and the
exit status is 1.

Idempotent: running it again with the same file changes nothing. The JSON keeps the
originals' formatting (indent 1, ensure_ascii=False, trailing newline). Stdlib only.
"""

import datetime as dt
import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
# The copies each app bundles: the Android app's assets and the iOS app's resources.
ASSETS = [
    ROOT / "android" / "app" / "src" / "main" / "assets",
    ROOT / "ios" / "KCNA26" / "Resources" / "Data",
]
SCHEDULE = "schedule.json"
UNCONFERENCE = "unconference.json"
ROOMS = "rooms.json"

PRECOMPUTED = ("isMine", "hasAnthropicSpeaker")
TOPIC_FIELDS = ("title", "votes", "comments", "youUpvoted", "picked")
PICKED_FIELDS = ("sessionId", "start", "room", "roomName")
DISCUSSION_NOTE = (
    "Optional. The GitHub discussion behind an unconference session (its proposal and replies). "
    "Show it in the details as \"Proposal and replies on GitHub\"."
)
MONTHS = {m: i for i, m in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], start=1)}
ZONE_OFFSETS = {"MST": -7, "MDT": -6}


class Errors:
    def __init__(self):
        self.items = []
        self.warnings = []

    def add(self, where, msg):
        self.items.append(f"{where}: {msg}")

    def warn(self, where, msg):
        self.warnings.append(f"{where}: {msg}")


# ------------------------------------------------------------------ JSON in/out


def read_json(path):
    """Returns (data, style) where style reproduces the file's formatting."""
    raw = path.read_text(encoding="utf-8")
    data = json.loads(raw)
    indent = None
    m = re.search(r"\n( +)\S", raw)
    if m:
        indent = len(m.group(1))
    style = {
        "indent": indent,
        "ensure_ascii": not any(ord(c) > 127 for c in raw) and "\\u" in raw,
        "newline": raw.endswith("\n"),
    }
    if dump(data, style) != raw:
        print(f"warning: {path.name} does not round-trip exactly; its formatting may change", file=sys.stderr)
    return data, style


def dump(data, style):
    text = json.dumps(data, indent=style["indent"], ensure_ascii=style["ensure_ascii"])
    return text + ("\n" if style["newline"] else "")


def write_atomic(path, text):
    # mkstemp creates the temp file 0600: give it the target's mode (0644 if new) so the
    # rewritten JSON stays readable like the rest of the repository.
    try:
        mode = os.stat(path).st_mode & 0o777
    except FileNotFoundError:
        mode = 0o644
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


# ------------------------------------------------------------------ time


def parse_time(value):
    """ISO 8601 with a UTC offset ("…-07:00" or "…Z") -> aware datetime, else None."""
    if not isinstance(value, str) or "T" not in value:
        return None
    s = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        t = dt.datetime.fromisoformat(s)
    except ValueError:
        return None
    return t if t.tzinfo is not None else None


def schedule_zone(schedule):
    """schedule.json's timeZone (America/Denver), or None if this Python has no tz database."""
    try:
        from zoneinfo import ZoneInfo

        return ZoneInfo(schedule.get("timeZone") or "America/Denver")
    except Exception:
        return None


def local_date(t, zone):
    """The calendar date of [t] in the schedule's zone (else in the time's own offset)."""
    return (t.astimezone(zone) if zone is not None else t).date().isoformat()


def checked_at(updates, errors):
    """When the updates were checked: "checkedAt", or "… Sun Nov 8, 2026, checked at 2:03 PM MST …"."""
    explicit = updates.get("checkedAt")
    if explicit is not None:
        if parse_time(explicit) is None:
            errors.add("checkedAt", f"{explicit!r} is not an ISO time with a UTC offset")
            return None
        return explicit
    about = updates.get("_about") or ""
    date = re.search(r"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* (\d{1,2}), (\d{4})", about)
    clock = re.search(r"\bchecked at (\d{1,2}):(\d{2}) ?([AP]M) (MST|MDT)\b", about)
    if not (date and clock):
        errors.warn("_about", "no \"checked at H:MM AM/PM MST\" time found; checkedAt not set")
        return None
    hour = int(clock.group(1)) % 12 + (12 if clock.group(3) == "PM" else 0)
    tz = dt.timezone(dt.timedelta(hours=ZONE_OFFSETS[clock.group(4)]))
    t = dt.datetime(int(date.group(3)), MONTHS[date.group(1)], int(date.group(2)), hour, int(clock.group(2)), tzinfo=tz)
    return t.isoformat()


def checked_label(iso):
    """"2:03 PM MST Nov 8" for the provenance sentence."""
    t = parse_time(iso)
    zone = {-7: "MST", -6: "MDT"}.get(int(t.utcoffset().total_seconds() // 3600), t.strftime("UTC%z"))
    hour = t.hour % 12 or 12
    return f"{hour}:{t.minute:02d} {'AM' if t.hour < 12 else 'PM'} {zone} {t.strftime('%b')} {t.day}"


# ------------------------------------------------------------------ validation


def validate_sessions(updates, schedule, rooms, errors):
    by_id = {s["id"]: s for s in schedule["sessions"]}
    days = {d["key"]: d["date"] for d in schedule.get("days", [])}
    categories = set(schedule.get("categories", {}))
    events = {s.get("event") for s in schedule["sessions"]}
    zone = schedule_zone(schedule)
    known_keys = {k for s in schedule["sessions"] for k in s} | {"discussionUrl"}
    seen = set()
    for i, u in enumerate(updates):
        where = f"sessionUpdates[{i}]"
        if not isinstance(u, dict):
            errors.add(where, "not an object")
            continue
        sid = u.get("id")
        where = f"sessionUpdates[{i}] ({sid})"
        if not isinstance(sid, str) or sid not in by_id:
            errors.add(where, "id not found in schedule.json")
            continue
        if sid in seen:
            errors.add(where, "id given twice")
        seen.add(sid)
        for key in ("event", "day", "start", "room", "title", "category"):
            if not isinstance(u.get(key), str) or not u[key]:
                errors.add(where, f"{key} missing or not a string")
        for key in sorted(set(u) - known_keys):
            errors.warn(where, f"new key {key!r} (kept)")
        start = parse_time(u.get("start"))
        if start is None:
            errors.add(where, f"start {u.get('start')!r} is not an ISO time with a UTC offset")
        end = None
        if u.get("end") is not None:
            end = parse_time(u["end"])
            if end is None:
                errors.add(where, f"end {u['end']!r} is not an ISO time with a UTC offset")
            elif start is not None and end <= start:
                errors.add(where, "end is not after start")
        if u.get("day") not in days:
            errors.add(where, f"day {u.get('day')!r} not in schedule.json days")
        elif start is not None and local_date(start, zone) != days[u["day"]]:
            errors.add(where, f"start is not on {u['day']} ({days[u['day']]})")
        if u.get("room") not in rooms:
            errors.add(where, f"room {u.get('room')!r} not in rooms.json")
        if u.get("category") not in categories:
            errors.add(where, f"category {u.get('category')!r} not in schedule.json categories")
        if u.get("event") not in events:
            errors.add(where, f"event {u.get('event')!r} is not one the schedule uses")
        if "endIsEstimate" in u and not isinstance(u["endIsEstimate"], bool):
            errors.add(where, "endIsEstimate is not true/false")
        speakers = u.get("speakers", [])
        if not isinstance(speakers, list) or not all(isinstance(x, str) and x.strip() for x in speakers):
            errors.add(where, "speakers is not a list of names")
        group = u.get("group")
        if group is not None and not (isinstance(group, dict) and isinstance(group.get("key"), str)
                                      and isinstance(group.get("title"), str)):
            errors.add(where, "group is not null or {key, title}")
        for key in ("note", "description", "slidesUrl", "officialUrl"):
            if u.get(key) is not None and not isinstance(u[key], str):
                errors.add(where, f"{key} is not a string")
        url = u.get("discussionUrl")
        if url is not None and not (isinstance(url, str) and url.startswith("https://")):
            errors.add(where, "discussionUrl is not an https:// URL")


def validate_topics(updates, unconf, sessions_after, rooms, errors):
    by_number = {t["number"]: t for t in unconf["topics"]}
    sessions = {s["id"]: s for s in sessions_after}
    seen, picked_sessions = set(), {}
    for i, u in enumerate(updates):
        where = f"topicUpdates[{i}]"
        if not isinstance(u, dict):
            errors.add(where, "not an object")
            continue
        n = u.get("number")
        where = f"topicUpdates[{i}] (#{n})"
        if isinstance(n, bool) or not isinstance(n, int) or n not in by_number:
            errors.add(where, "number not found in unconference.json")
            continue
        if n in seen:
            errors.add(where, "number given twice")
        seen.add(n)
        for key in sorted(set(u) - {"number", *TOPIC_FIELDS}):
            errors.add(where, f"unsupported key {key!r} (only {', '.join(TOPIC_FIELDS)} are updated)")
        if "title" in u and not (isinstance(u["title"], str) and u["title"].strip()):
            errors.add(where, "title is empty or not a string")
        for key in ("votes", "comments"):
            if key in u and (isinstance(u[key], bool) or not isinstance(u[key], int) or u[key] < 0):
                errors.add(where, f"{key} is not a whole number ≥ 0")
        if "youUpvoted" in u and not isinstance(u["youUpvoted"], bool):
            errors.add(where, "youUpvoted is not true/false")
        p = u.get("picked")
        if p is None:
            continue
        if not isinstance(p, dict):
            errors.add(where, "picked is not null or an object")
            continue
        for key in PICKED_FIELDS:
            if not isinstance(p.get(key), str) or not p[key]:
                errors.add(where, f"picked.{key} missing or not a string")
        for key in sorted(set(p) - set(PICKED_FIELDS)):
            errors.add(where, f"unsupported key picked.{key}")
        start = parse_time(p.get("start"))
        if start is None:
            errors.add(where, f"picked.start {p.get('start')!r} is not an ISO time with a UTC offset")
        room = rooms.get(p.get("room"))
        if room is None:
            errors.add(where, f"picked.room {p.get('room')!r} not in rooms.json")
        elif p.get("roomName") != room.get("name"):
            errors.add(where, f"picked.roomName {p.get('roomName')!r} is not rooms.json's {room.get('name')!r}")
        s = sessions.get(p.get("sessionId"))
        if s is None:
            errors.add(where, f"picked.sessionId {p.get('sessionId')!r} not found in schedule.json")
            continue
        if start is not None and parse_time(s["start"]) != start:
            errors.add(where, f"picked.start differs from {s['id']}'s start {s['start']}")
        if p.get("room") != s.get("room"):
            errors.add(where, f"picked.room differs from {s['id']}'s room {s.get('room')}")
        other = picked_sessions.get(s["id"])
        if other is not None:
            errors.add(where, f"{s['id']} is already picked for #{other}")
        picked_sessions[s["id"]] = n
    slots = unconf.get("slots")
    if isinstance(slots, int) and len(picked_sessions) > slots:
        errors.warn("topicUpdates", f"{len(picked_sessions)} topics picked for {slots} slots")


# ------------------------------------------------------------------ apply


def recompute_flags(session, me, anthropic):
    speakers = session.get("speakers") or []
    mine = me is not None and me in speakers
    return {
        "isMine": mine,
        "hasAnthropicSpeaker": not mine and any(sp in anthropic and sp != me for sp in speakers),
    }


def replaced_session(old, update, me, anthropic):
    """The update as a full replacement, in the old session's key order (new keys last)."""
    flags = recompute_flags(update, me, anthropic)
    out = {}
    for key in old:
        if key in update:
            out[key] = update[key]
        elif key in PRECOMPUTED:
            out[key] = flags[key]
    for key in update:
        if key not in out:
            out[key] = update[key]
    return out


def updated_topic(old, update):
    out = dict(old)
    for key in TOPIC_FIELDS:
        if key in update:
            out[key] = update[key]
    if "picked" in update and "picked" not in old:
        # Put the new field after youUpvoted, next to the other per-topic state.
        keys = list(out)
        keys.remove("picked")
        at = keys.index("youUpvoted") + 1 if "youUpvoted" in keys else len(keys)
        keys.insert(at, "picked")
        out = {k: out[k] for k in keys}
    return out


def with_after(d, key, value, after):
    """d with d[key] = value; a new key goes right after [after] (or at the end)."""
    if key in d:
        out = dict(d)
        out[key] = value
        return out
    out = {}
    for k, v in d.items():
        out[k] = v
        if k == after:
            out[key] = value
    out.setdefault(key, value)
    return out


def add_provenance(about, sentence):
    if sentence in about:
        return about
    return (about.rstrip() + " " + sentence).strip()


def source_label(path):
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.name


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: python3 -I scripts/apply_updates.py <updates.json>", file=sys.stderr)
        return 2
    src = Path(argv[1])
    updates = json.loads(src.read_text(encoding="utf-8"))
    if not isinstance(updates, dict):
        print("error: the updates file is not a JSON object", file=sys.stderr)
        return 1

    schedule, schedule_style = read_json(DATA / SCHEDULE)
    rooms = read_json(DATA / ROOMS)[0]["rooms"]
    # unconference.json is optional: the app's unconference feature was removed (voting is over).
    unconf, unconf_style = read_json(DATA / UNCONFERENCE) if (DATA / UNCONFERENCE).is_file() else (None, None)

    session_updates = updates.get("sessionUpdates") or []
    topic_updates = updates.get("topicUpdates") or []
    errors = Errors()
    if not isinstance(session_updates, list) or not isinstance(topic_updates, list):
        errors.add("updates", "sessionUpdates and topicUpdates must be lists")
        session_updates, topic_updates = [], []
    skipped_topics = 0
    if unconf is None and topic_updates:
        skipped_topics = len(topic_updates)
        print(
            f"note: data/{UNCONFERENCE} does not exist (the unconference feature was removed); "
            f"skipping {skipped_topics} topicUpdate{'' if skipped_topics == 1 else 's'}.",
            file=sys.stderr,
        )
        topic_updates = []
    when = checked_at(updates, errors)

    validate_sessions(session_updates, schedule, rooms, errors)
    me = schedule.get("me")
    anthropic = set(schedule.get("anthropicSpeakers", []))
    by_id = {u["id"]: u for u in session_updates if isinstance(u, dict) and isinstance(u.get("id"), str)}
    sessions_after = [
        replaced_session(s, by_id[s["id"]], me, anthropic) if s["id"] in by_id else s
        for s in schedule["sessions"]
    ]
    if unconf is not None:
        validate_topics(topic_updates, unconf, sessions_after, rooms, errors)

    for w in errors.warnings:
        print(f"warning: {w}", file=sys.stderr)
    if errors.items:
        for e in errors.items:
            print(f"error: {e}", file=sys.stderr)
        print(f"{len(errors.items)} error(s); nothing written.", file=sys.stderr)
        return 1

    label = source_label(src)
    checked = f", checked {checked_label(when)}" if when else ""

    # schedule.json
    new_schedule = dict(schedule)
    new_schedule["sessions"] = sessions_after
    if session_updates:
        if any(s.get("discussionUrl") for s in sessions_after):
            notes = schedule.get("fieldNotes", {})
            if "discussionUrl" not in notes:
                new_schedule["fieldNotes"] = {**notes, "discussionUrl": DISCUSSION_NOTE}
        n = len(session_updates)
        new_schedule["_about"] = add_provenance(
            schedule.get("_about", ""),
            f"Updated from {label}{checked}: {n} session{'' if n == 1 else 's'} replaced.",
        )

    outputs = [(SCHEDULE, new_schedule, schedule_style)]

    # unconference.json (only if it still exists)
    new_unconf = None
    if unconf is not None:
        topic_by_number = {u["number"]: u for u in topic_updates}
        new_unconf = dict(unconf)
        new_unconf["topics"] = [
            updated_topic(t, topic_by_number[t["number"]]) if t["number"] in topic_by_number else t
            for t in unconf["topics"]
        ]
        if topic_updates:
            if when:
                new_unconf = with_after(new_unconf, "checkedAt", when, after="_about")
            picked = sum(1 for t in new_unconf["topics"] if t.get("picked"))
            n = len(topic_updates)
            new_unconf["_about"] = add_provenance(
                unconf.get("_about", ""),
                f"Updated from {label}{checked}: votes, replies, upvotes and titles for {n} "
                f"topic{'' if n == 1 else 's'}; {picked} picked for today (see each topic's picked).",
            )
        outputs.append((UNCONFERENCE, new_unconf, unconf_style))

    changed = []
    for name, data, style in outputs:
        text = dump(data, style)
        for target in (DATA / name, *(a / name for a in ASSETS)):
            if not target.parent.is_dir():
                print(f"warning: {target.parent} missing; skipped", file=sys.stderr)
                continue
            if target.exists() and target.read_text(encoding="utf-8") == text:
                continue
            write_atomic(target, text)
            changed.append(target.relative_to(ROOT).as_posix())

    if new_unconf is None:
        skipped = f" ({skipped_topics} topicUpdates skipped: no {UNCONFERENCE})" if skipped_topics else ""
        print(f"{len(session_updates)} sessions replaced{skipped}.")
    else:
        picked = sum(1 for t in new_unconf["topics"] if t.get("picked"))
        print(f"{len(session_updates)} sessions replaced, {len(topic_updates)} topics updated, {picked} picked.")
    print("wrote: " + ", ".join(changed) if changed else "already up to date; nothing written.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
