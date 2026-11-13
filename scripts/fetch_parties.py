#!/usr/bin/env python3
"""Add the evening parties around the conference to the schedule data.

Usage (from the repository root):

    python3 -I scripts/fetch_parties.py                 # download the list
    python3 -I scripts/fetch_parties.py --html page.html  # or read a saved copy

The parties are not on the official agenda. They come from two places, and every party's
description says which:

- the unofficial, community-run list at https://conferenceparties.com/kubecon26/ (one
  table: time, hosts, event and RSVP link, location);
- data/updates/parties-extra.json: events found elsewhere and checked on the host's own
  page, written by hand (its "_about" describes the fields). It may also name extra days
  after the conference; a day is added to the schedule only while it has a party.

What it adds, for each evening event (starting at 5 PM or later) on the chosen days:

- schedule.json: a session with category "soc", an id starting "party-", the host's RSVP
  page as officialUrl and a note saying how to get in ("Invite needed"). The hosts go in
  the title ("... Hosted by ..."), as on the official agenda's off-site events. A party
  whose end time nobody published has "end": null.
- rooms.json: the venue as a room without a position (code starting "PARTY-"), so the app
  shows its name and address and offers no walking directions.
- details.json: a description with the hosts, the address and the source.

Nothing else in those files changes, and the apps need no update: an off-site place and a
"soc" session are things the released apps already show.

Idempotent: every run first removes the parties, venues and descriptions an earlier run
added, then adds the current list. Events the official agenda already has are skipped (see
ALREADY_OFFICIAL). Afterwards run scripts/make_manifest.py --sync-assets.

The JSON keeps the originals' formatting. Stdlib only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
EXTRA = DATA / "updates" / "parties-extra.json"
SOURCE_URL = "https://conferenceparties.com/kubecon26/"
SOURCE_NAME = "conferenceparties.com/kubecon26"
USER_AGENT = "kubecon-schedule-app/1.0 (unofficial schedule app)"
OFFSET = "-07:00"  # MST: DST ended Sun Nov 1, 2026
EVENING_FROM = 17 * 60  # minutes after midnight

SESSION_PREFIX = "party-"
ROOM_PREFIX = "PARTY-"
ABOUT_MARK = "Evening parties (ids party-*)"
ROOMS_ABOUT_MARK = "PARTY-* rooms"

DAY_KEYS = {"Sunday": "sun", "Monday": "mon", "Tuesday": "tue", "Wednesday": "wed", "Thursday": "thu"}

# (day, text the RSVP link contains): on the official agenda already, so not added again.
ALREADY_OFFICIAL = {
    ("wed", "savephippy.com"),  # "Save Phippy: The Cloud Native Escape Room" (session 1340051)
}

# Event names the list misprints, keyed by text the RSVP link contains.
TITLE_FIXES = {
    "luma.com/kubecon-2026": "Meet OVHcloud at KubeCon: An Evening of Kubernetes Talk",
}

# How to get in, from the list's call to action.
NOTES = [
    (re.compile(r"invite", re.I), "Invite needed"),
    (re.compile(r"rsvp", re.I), "RSVP needed"),
    (re.compile(r"sign up|register", re.I), "Registration needed"),
]

# What to do about each note (the sentence after "<note>: " in the description).
HOW = {
    "Invite needed": "use the listing link below to ask the host for a place.",
    "RSVP needed": "use the listing link below to tell the host you're coming.",
    "Registration needed": "use the listing link below to register.",
    "Tickets needed": "use the listing link below to get a ticket.",
    "Open to all": "no invite needed. The listing link below has the details and a free sign-up.",
}

NO_ADDRESS = re.compile(r"register to see", re.I)


def clean(fragment: str) -> str:
    """Text of an HTML fragment: tags and zero-width marks out, whitespace collapsed."""
    text = html.unescape(re.sub(r"<[^>]+>", " ", fragment))
    text = re.sub(r"[​‌‍‎‏﻿]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def parse_clock(part: str) -> tuple[int, str | None]:
    """ "7:30" / "10PM" -> (minutes on a 12-hour clock, "AM" / "PM" / None)."""
    m = re.fullmatch(r"(\d{1,2})(?::(\d{2}))?\s*([AP]M)?", part.strip(), re.I)
    if not m:
        raise ValueError(f"can't read the time {part!r}")
    hour, minute = int(m.group(1)) % 12, int(m.group(2) or 0)
    return hour * 60 + minute, (m.group(3) or "").upper() or None


def parse_times(text: str) -> tuple[int, int]:
    """ "7–9:30PM" / "7PM–12AM" -> (start, end) in minutes after midnight; end may pass 24 h."""
    parts = re.split(r"\s*[–—-]\s*", text.strip())
    if len(parts) != 2:
        raise ValueError(f"can't read the time range {text!r}")
    (start, start_ap), (end, end_ap) = parse_clock(parts[0]), parse_clock(parts[1])
    if end_ap is None:
        raise ValueError(f"no AM/PM in {text!r}")
    end += 12 * 60 if end_ap == "PM" else 0
    if start_ap is None:
        # "10–11:15PM": the start shares the end's half of the day unless that puts it after the end.
        guess = start + (12 * 60 if end_ap == "PM" else 0)
        start = guess if guess <= end else start + (0 if end_ap == "PM" else 12 * 60)
    else:
        start += 12 * 60 if start_ap == "PM" else 0
    if end <= start:
        end += 24 * 60  # past midnight
    return start, end


def parse_page(page: str) -> list[dict]:
    """The list's rows: day, start, end, hosts, name, call to action, link, venue, address."""
    table = re.search(r"<table.*?</table>", page, re.S)
    if not table:
        raise ValueError("no table on the page")
    out, day = [], None
    for row in re.findall(r"<tr[^>]*>(.*?)</tr>", table.group(0), re.S):
        cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)
        heading = re.search(r"(Sunday|Monday|Tuesday|Wednesday|Thursday)\s*-\s*November\s+(\d+),\s*(\d{4})", clean(row))
        if heading and len(cells) <= 2:
            day = (DAY_KEYS[heading.group(1)], dt.date(int(heading.group(3)), 11, int(heading.group(2))))
            continue
        if len(cells) < 5 or clean(cells[0]) in ("", "Time") or day is None:
            continue
        link = re.search(r'href="([^"]+)"', cells[2])
        cta = re.search(r"<span[^>]*>(.*?)</span>", cells[2], re.S)
        name = clean(re.sub(r"<span[^>]*>.*?</span>", " ", cells[2], flags=re.S))
        name = re.sub(r"\s*[-–]\s*$", "", name)
        place = [clean(p) for p in re.split(r"<br\s*/?>", cells[3])]
        place = [p for p in place if p]
        start, end = parse_times(clean(cells[0]))
        out.append({
            "day": day[0], "date": day[1], "start": start, "end": end,
            "hosts": re.sub(r",\s*&", " &", clean(cells[1])), "name": name,
            "cta": clean(cta.group(1)) if cta else "",
            "link": html.unescape(link.group(1)).strip() if link else "",
            "place": place,
        })
    return out


def slug(text: str) -> str:
    text = text.replace("&", " and ").replace("è", "e").replace("é", "e")
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def venue_of(place: list[str]) -> tuple[str, dict]:
    """(room code, rooms.json entry) for the list's location cell."""
    if not place or NO_ADDRESS.search(place[0]):
        return ROOM_PREFIX + "ADDRESS-ON-REGISTRATION", {
            "name": "Address on registration",
            "buildingLabel": "Off-site",
            "whereText": "Off-site. The host shares the address when you register.",
        }
    name, address = place[0], ", ".join(place[1:])
    if not address and re.match(r"\d", name):  # the list gives only a street address
        return ROOM_PREFIX + slug(name).upper(), {
            "name": name,
            "buildingLabel": "Off-site",
            "whereText": f"Off-site, at {name}.",
        }
    return ROOM_PREFIX + slug(name).upper(), {
        "name": name,
        "buildingLabel": address or "Off-site",
        "whereText": f"Off-site, at {address}." if address else "Off-site.",
    }


def name_of(row: dict) -> str:
    return next((fix for key, fix in TITLE_FIXES.items() if key in row["link"]), row["name"])


def title_of(row: dict) -> str:
    name = name_of(row)
    hosts = [h.strip() for h in re.split(r",|&|\band\b", row["hosts"]) if h.strip()]
    if hosts and all(h.lower() in name.lower() for h in hosts):
        return name
    return f"{name} Hosted by {row['hosts']}"


def link_key(url: str) -> str:
    return re.sub(r"[?#].*$", "", re.sub(r"^https?://(www\.)?", "", url.strip().lower())).rstrip("/")


def extra_rows(extra: dict) -> list[dict]:
    """parties-extra.json's entries in the shape of the list's rows."""
    out = []
    for p in extra.get("parties", []):
        label = p.get("name") or "an entry"
        for field in ("day", "date", "start", "name", "hosts", "link"):
            if not p.get(field):
                raise ValueError(f"parties-extra.json: {label} has no {field}")
        def minutes(text: str) -> int:
            m = re.fullmatch(r"(\d{1,2}):(\d{2})", text)
            if not m or int(m.group(1)) > 23 or int(m.group(2)) > 59:
                raise ValueError(f"parties-extra.json: {label}: {text!r} is not a 24-hour HH:MM time")
            return int(m.group(1)) * 60 + int(m.group(2))
        start = minutes(p["start"])
        end = minutes(p["end"]) if p.get("end") else None
        if end is not None and end <= start:
            end += 24 * 60  # past midnight
        out.append({
            "day": p["day"], "date": dt.date.fromisoformat(p["date"]), "start": start, "end": end,
            "hosts": p["hosts"].strip(), "name": p["name"].strip(), "cta": "", "link": p["link"].strip(),
            "place": [x.strip() for x in (p.get("venue") or "", p.get("address") or "") if x.strip()],
            "note": (p.get("access") or "RSVP needed").strip(), "about": (p.get("about") or "").strip(),
            "room": (p.get("room") or "").strip(), "where": (p.get("where") or "").strip(),
            "source": "host", "checked": extra.get("checked", ""),
        })
    return out


def stamp(date: dt.date, minutes: int) -> str:
    moment = dt.datetime.combine(date, dt.time()) + dt.timedelta(minutes=minutes)
    return moment.strftime("%Y-%m-%dT%H:%M:%S") + OFFSET


def write(path: pathlib.Path, obj, indent: int) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=indent) + "\n", encoding="utf-8")


def read(path: pathlib.Path, indent: int):
    raw = path.read_text(encoding="utf-8")
    obj = json.loads(raw)
    if json.dumps(obj, ensure_ascii=False, indent=indent) + "\n" != raw:
        raise ValueError(f"{path.name}: unexpected formatting (expected indent {indent})")
    return obj


def without_sentence(about: str, mark: str) -> str:
    """`about` without the sentence an earlier run added (it starts with `mark`)."""
    return re.sub(r"\s*" + re.escape(mark) + r".*?\.(?=\s|$)", "", about).rstrip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--html", type=pathlib.Path, help="a saved copy of the list page (default: download it)")
    ap.add_argument("--days", default="tue,wed,thu", help="schedule day keys to take the list's parties from (default: tue,wed,thu)")
    ap.add_argument("--extra", type=pathlib.Path, default=EXTRA, help="hand-checked parties from other sources (default: data/updates/parties-extra.json, if it exists)")
    ap.add_argument("--checked", help='when the list was read, e.g. "Nov 10, 2026 at 12:10 PM MST" (default: now)')
    ap.add_argument("--data", type=pathlib.Path, default=DATA)
    args = ap.parse_args()

    if args.html:
        page = args.html.read_text(encoding="utf-8", errors="replace")
    else:
        req = urllib.request.Request(SOURCE_URL, headers={"User-Agent": USER_AGENT})
        page = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", errors="replace")
    checked = args.checked
    if not checked:
        now = dt.datetime.now(dt.timezone(dt.timedelta(hours=-7)))
        checked = now.strftime("%b %-d, %Y at %-I:%M %p MST")
    days = {d.strip() for d in args.days.split(",") if d.strip()}

    schedule = read(args.data / "schedule.json", 1)
    rooms_file = read(args.data / "rooms.json", 1)
    details = read(args.data / "details.json", 0)
    if "soc" not in schedule["categories"]:
        raise ValueError('schedule.json has no "soc" category')
    extra = json.loads(args.extra.read_text(encoding="utf-8")) if args.extra.is_file() else {}
    # The conference's own days are the ones with official sessions; a day an earlier run
    # added for parties is dropped here and comes back below if it still has one.
    official_days = [
        d for d in schedule["days"]
        if any(s["day"] == d["key"] and not s["id"].startswith(SESSION_PREFIX) for s in schedule["sessions"])
    ]
    extra_days = {d["key"]: d for d in extra.get("days", []) if d["key"] not in {o["key"] for o in official_days}}
    day_dates = {d["key"]: d["date"] for d in official_days + list(extra_days.values())}

    listed = parse_page(page)
    # A venue's address is sometimes cut short on one row and complete on another: take the
    # longest spelling the page has for that venue.
    best = {}
    for r in listed:
        if len(r["place"]) > 1 and len(", ".join(r["place"][1:])) > len(", ".join(best.get(r["place"][0], [""])[1:])):
            best[r["place"][0]] = r["place"]
    for r in listed:
        if len(r["place"]) > 1:
            r["place"] = best[r["place"][0]]
    rows = [dict(r, source="list", checked=checked) for r in listed if r["day"] in days and r["start"] >= EVENING_FROM]
    for row in extra_rows(extra):  # not again if the list already has it
        same = lambda r: r["day"] == row["day"] and (
            link_key(r["link"]) == link_key(row["link"]) or slug(name_of(r)) == slug(row["name"]))
        if not any(same(r) for r in rows):
            rows.append(row)
    sessions, venues, descriptions, skipped = [], {}, {}, []
    for row in rows:
        if any(day == row["day"] and key in row["link"] for day, key in ALREADY_OFFICIAL):
            skipped.append(row["name"])
            continue
        if day_dates.get(row["day"]) != row["date"].isoformat():
            raise ValueError(f"{row['name']}: {row['date']} is not the schedule's {row['day']}")
        if not row["link"]:
            raise ValueError(f"{row['name']}: no RSVP link")
        if row.get("room"):  # inside the conference venue: one of its own rooms, with directions
            if row["room"].startswith(ROOM_PREFIX) or row["room"] not in rooms_file["rooms"] or not row.get("where"):
                raise ValueError(f"{row['name']}: \"room\" must be a rooms.json code and come with \"where\"")
            code, venue = row["room"], None
        else:
            code, venue = venue_of(row["place"])
            venue = venues.setdefault(code, venue)  # the first spelling of a venue's address wins
        sid = SESSION_PREFIX + row["day"] + "-" + slug(name_of(row))[:48].strip("-")
        if any(s["id"] == sid for s in sessions):
            raise ValueError(f"duplicate party id {sid}")
        note = row.get("note") or next((n for rx, n in NOTES if rx.search(row["cta"])), "Invite needed")
        sessions.append({
            "id": sid, "event": "kubecon", "day": row["day"],
            "start": stamp(row["date"], row["start"]),
            "end": stamp(row["date"], row["end"]) if row["end"] is not None else None,
            "endIsEstimate": False, "room": code, "title": title_of(row), "speakers": [],
            "note": note, "category": "soc", "group": None, "isMine": False,
            "hasAnthropicSpeaker": False, "officialUrl": row["link"],
        })
        if venue is None:
            where = f"Where: {row['where']}."
        elif venue["name"] == "Address on registration":
            where = "Where: off-site. The host shares the address when you register."
        elif venue["buildingLabel"] == "Off-site":
            where = f"Where: {venue['name']} (off-site, not part of the conference venue)."
        else:
            where = f"Where: {venue['name']}, {venue['buildingLabel']} (off-site, not part of the conference venue)."
        if row["source"] == "list":
            credit = f"From the unofficial party list at {SOURCE_NAME}, checked {row['checked']}."
        else:
            credit = "From the host's own event page" + (f", checked {row['checked']}." if row["checked"] else ".")
        descriptions[sid] = {
            "description": "\n\n".join(filter(None, [
                f"Hosted by {row['hosts']}.",
                row.get("about"),
                where,
                f"{note}: {HOW.get(note, 'see the listing link below for how to join.')} "
                "Marking RSVP in this app only saves it on your device.",
                f"{credit} Times and places can change, so check the host's page.",
            ])),
            "speakers": [],
        }
    if not sessions:
        raise ValueError("no evening parties on those days; nothing changed")

    # Out with an earlier run's parties, in with these (kept in start order, after the
    # official sessions that start at the same time).
    kept = [s for s in schedule["sessions"] if not s["id"].startswith(SESSION_PREFIX)]
    if any(s["id"] in {k["id"] for k in kept} for s in sessions):
        raise ValueError("a party id collides with an official session id")
    for s in sorted(sessions, key=lambda s: (s["start"], s["title"])):
        at = next((i for i, k in enumerate(kept) if k["start"] > s["start"]), len(kept))
        kept.insert(at, s)
    schedule["sessions"] = kept
    used = {s["day"] for s in sessions}
    added_days = sorted((d for k, d in extra_days.items() if k in used), key=lambda d: d["date"])
    schedule["days"] = official_days + [
        {k: d[k] for k in ("key", "date", "label", "short", "subtitle")} for d in added_days
    ]
    schedule["_about"] = (
        without_sentence(schedule["_about"], ABOUT_MARK)
        + f" {ABOUT_MARK} are not on the official agenda: they come from the unofficial list at"
        f" {SOURCE_NAME}, checked {checked}, and from hosts' own pages listed in"
        " data/updates/parties-extra.json (scripts/fetch_parties.py)."
    )

    rooms = {k: v for k, v in rooms_file["rooms"].items() if not k.startswith(ROOM_PREFIX)}
    if set(venues) & set(rooms):
        raise ValueError("a party venue code collides with a room code")
    rooms.update(sorted(venues.items()))
    rooms_file["rooms"] = rooms
    rooms_file["_about"] = (
        without_sentence(rooms_file["_about"], ROOMS_ABOUT_MARK)
        + f" {ROOMS_ABOUT_MARK} are off-site party venues without a position (scripts/fetch_parties.py)."
    )

    details = {k: v for k, v in details.items() if not k.startswith(SESSION_PREFIX)}
    details.update(descriptions)

    write(args.data / "schedule.json", schedule, 1)
    write(args.data / "rooms.json", rooms_file, 1)
    write(args.data / "details.json", details, 0)
    by_day = {d: sum(1 for s in sessions if s["day"] == d) for d in day_dates if d in used}
    print(f"{len(sessions)} parties at {len(venues)} venues: " + ", ".join(f"{d} {n}" for d, n in by_day.items()))
    if added_days:
        print("days added for them: " + ", ".join(d["key"] for d in added_days))
    if skipped:
        print("already on the official agenda, skipped: " + "; ".join(skipped))
    print("next: python3 -I scripts/make_manifest.py --sync-assets")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError) as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
