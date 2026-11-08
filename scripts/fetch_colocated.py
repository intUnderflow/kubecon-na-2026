#!/usr/bin/env python3
"""Fetch the CNCF-hosted co-located event schedules (Mon Nov 9) and write data/colocated.json + colocated_details.json.

Source: the LF page below embeds Sessionize's full export (sessions, speakers, rooms,
categories) as <script type="application/json" class="sched-data">. Every talk becomes a
session shaped exactly like schedule.json's sessions (plus coloEvent/coloEvents/format/level/
sponsored/topic), so the app can treat co-located talks as ordinary sessions. The file also
carries one entry per event, the co-located Anthropic speakers and the few new position-less
rooms the breaks need. The top level decodes with the app's ScheduleFileDto (_about is a string,
like schedule.json's) and RoomsFileDto. Rules: see RULES below (copied into the file's "_rules").
The bundled details (descriptions + speaker taglines, details.json's shape) go to their own file,
colocated_details.json, next to it: the app parses colocated.json at start-up (the splash waits
for it) and the details only later, with details.json, so they are kept out of that first parse.

Stdlib only (Python 3.9+). From the repository root:
    python3 -I scripts/fetch_colocated.py                    # download the page
    python3 -I scripts/fetch_colocated.py --offline PAGE.html  # use a saved copy of the page
The script validates its output with assertions and exits non-zero on any failure. Then copy both
files to app/src/main/assets.
"""
import argparse
import collections
import datetime
import html
import html.parser
import json
import pathlib
import re
import sys
import time
import unicodedata
import urllib.request

KIT = pathlib.Path(__file__).resolve().parent.parent
PAGE = ("https://events.linuxfoundation.org/kubecon-cloudnativecon-north-america/"
        "co-located-events/cncf-hosted-co-located-schedule/")
EVENT_PAGE = ("https://events.linuxfoundation.org/kubecon-cloudnativecon-north-america/"
              "co-located-events/{slug}/")
UA = "kubecon-schedule-app/1.0 (personal schedule app)"
TZ_NAME = "America/Denver"
OFFSET = "-07:00"  # MST: DST ended Sun Nov 1, 2026
DATES = ("2026-11-08", "2026-11-09")
DETAILS_NAME = "colocated_details.json"  # written next to colocated.json

# New rooms for places that aren't rooms in rooms.json. Never give them positions:
# no lat/lng/x/y/attachNode/finalStep, so the app shows them without Directions (like OFF).
NEW_ROOMS = {
    "FOY": {
        "name": "Meeting room foyers",
        "buildingLabel": "Salt Palace",
        "venue": "Salt Palace Convention Center",
        "venueCode": "SP",
        "level": None,
        "whereText": "The foyer outside each event's meeting room.",
    },
    "LCH4": {
        "name": "Lower Concourse Foyer and Hall 4",
        "buildingLabel": "Salt Palace L1",
        "venue": "Salt Palace Convention Center",
        "venueCode": "SP",
        "level": 1,
        "whereText": "Lower Concourse foyer and Hall 4, reached via the Lower Mezzanine.",
    },
}

# Source locations that aren't a single room, matched by pattern (case-insensitive).
# Everything else must match a rooms.json room by level + name (see map_room).
SPECIAL_ROOMS = [
    (r"\bmeeting room foyers?\b", "FOY"),
    (r"\blower concourse foyer\b.*\bhall 4\b", "LCH4"),
    # The evening reception spans the Lower and Upper Mezzanine; the Upper Mezzanine is a
    # rooms.json room with a real position, so Directions take you to the reception.
    (r"\blower\s*(?:&|and|\+)\s*upper mezzanine\b", "UM"),
    # Registration and coat check (omitted from the output, mapped only for validation).
    (r"\b200 south entrance\b", "REG"),
    (r"\beast registration\b", "COAT"),
]

FORMATS = {  # Sessionize "Session format" -> the app's tag wording
    "breakout session": "Breakout",
    "panel discussion": "Panel",
    "lightning talk": "Lightning talk",
    "keynote session": "Keynote",
}
LEVELS = {"any level": "Any level", "beginner": "Beginner", "intermediate": "Intermediate", "advanced": "Advanced"}
# Category groups that aren't an event's own topic list.
STANDARD_GROUPS = {"all sessions", "session format", "audience level", "subtopic"}
ANTHROPIC_RE = re.compile(r"anthropic", re.I)
SLIDES_RE = re.compile(r"^https://sessionize\.com/download/\S+$")

RULES = [
    "Times: Sessionize startsAt/endsAt are local wall-clock times without an offset. They are America/Denver, "
    "so they get -07:00 (MST; DST ended on Nov 1).",
    "Events: the 11 event items of the 'All Sessions' category. key = group key = 'colo-' + the event's LF page slug. "
    "start/end = first talk start to last talk end (talks only, not breaks). mainRoom = the room with the most talks; "
    "rooms = every room with talks, main room first. supersedes = the all-day placeholder in schedule.json "
    "(category colo, note 'All-Access pass') with the same name, which the event card replaces; infoUrl and passNote "
    "come from that placeholder, and halfDay comes from its '(half day)' title.",
    "Talks: category 'colo', group {key, title: event name}, coloEvent = coloEvents[0] = the event key, note null.",
    "Breaks ('☕ Breaks'): category 'log', group null, renamed to schedule.json's house style ('AM Break'/'PM Break' -> "
    "'☕ Coffee Break', 'Lunch' -> '🍲 Lunch'). coloEvents = every event the break is tagged with; Sessionize staggers "
    "breaks per group of events. coloEvent = that event when there is exactly one, else null.",
    "Experiences ('🎉 Experiences'): ordinary sessions for the day's time blocks. Category 'soc', group null, "
    "coloEvent null, coloEvents empty. This is deliberate: the source tags the Evening Reception with all 11 events "
    "(it is open to every co-located attendee, as its title says), but it belongs in the day's time blocks, not "
    "repeated inside 11 event cards, and its 18:30 end must not keep finished cards alive.",
    "Omitted (listed in 'omitted'): registration and coat check, including both Nov 8 items. schedule.json leaves "
    "these out on purpose. Talks whose title is marked *CANCELED* are omitted too.",
    "Rooms: each source room maps to the rooms.json room on the same level with the same name, sections in any order "
    "('Grand Ballroom IG' = GI, '251 A-C' = 251AC, '151' = Room 151). Non-room places get new position-less rooms "
    "in 'rooms' (FOY, LCH4). 'Lower & Upper Mezzanine' (the Evening Reception) maps to UM, the Upper Mezzanine: "
    "the app shows 'Upper Mezzanine', and Directions work because UM has a position. Room codes stay rooms.json "
    "codes where one fits; a positioned copy of UM would add a duplicate place to the Directions 'From' picker.",
    "Text: titles and names are HTML-unescaped, NFC-normalised and whitespace-collapsed; Unicode is kept. Speaker names "
    "are Sessionize fullName with a stray trailing '-' dropped ('Flynn -' -> 'Flynn', as in schedule.json). "
    "tagline = tagLine, or else 'Speaker Title, Company' from questionAnswers. A tagLine that starts by repeating "
    "the speaker's name loses it ('Alex Van Boxel, Principal System Architect at Collibra' -> 'Principal System "
    "Architect at Collibra'), because the app already shows the name.",
    "Descriptions: Sessionize HTML (<p>, <br>, <ul>/<ol><li>, <a>, <em>/<strong>) is converted to the markdown subset "
    "that details.json uses and DescriptionFormat renders: blank-line paragraphs, '- ' list items, [text](url) or bare "
    "URLs, *em*/**strong**, with a literal \\ * _ [ < backslash-escaped. Text is otherwise kept as Sessionize has it "
    "(e.g. '--' stays '--'; the LF website's WordPress typography turns it into '—'), the same as details.json.",
    "Underscore repair: Sessionize turns a speaker's snake_case into emphasis ('build_id … build_id' arrives as "
    "'build<em>id … build</em>id', so the LF page shows 'buildid … buildid' with italics between). Emphasis that "
    "opens straight after a letter or digit is turned back into literal underscores ('build\\_id … build\\_id'). "
    "The repaired session ids are listed in _meta.underscoreRepairs (on Nov 8 only 1269782, ArgoCon, whose same "
    "paragraph later says 'build_id-scoped').",
    "slidesUrl: the session's 'Presentation Slides' answer (a sessionize.com/download link), as in schedule.json. "
    "null when none was uploaded.",
    "topic: the session's item in its event's own topic category ('<event> Topics'; for Cloud Native AI + Inference "
    "Day the category is just the event name). null when none.",
    "anthropicSpeakers: every speaker here whose tagLine or 'Company' answer mentions Anthropic (schedule.json's "
    "list is the KubeCon speakers whose details.json tagline mentions Anthropic), plus anyone in schedule.json's "
    "anthropicSpeakers who speaks here.",
    "officialUrl: the page's own per-session link ('<page>?id=<id>', the same as its sess-link anchors and JSON-LD). "
    "A session the page doesn't link to falls back to its event's LF page.",
    "Ids: Sessionize session ids. Any id that collides with schedule.json is prefixed 'c'.",
    "isMine / hasAnthropicSpeaker: precomputed like schedule.json (default speaker = schedule.json 'me'; Anthropic "
    "= schedule.json's anthropicSpeakers plus this file's). The app recomputes them at runtime.",
]

FIELD_NOTES = {
    "event": "Always 'colocated' (the CNCF-hosted co-located events schedule, Sessionize event ayajbd6b). These ids "
             "are NOT in the main KubeCon Sessionize event (uo948i5p): never live-fetch them from there. Use "
             "colocated_details.json's 'details', which is complete.",
    "coloEvent": "Key of the event (in 'events') this session belongs to. Set for every talk and for a break that "
                 "belongs to one event only. null for shared breaks and experiences.",
    "coloEvents": "Every event whose agenda includes this session: [coloEvent] for talks, all tagged events for "
                  "breaks, [] for experiences. An event's agenda = the sessions whose coloEvents contain its key, "
                  "ordered by start. Co-located breaks are timed per event (staggered), and none coincides with "
                  "schedule.json's Monday break rows (checked by the script), which belong to the Hyatt Project "
                  "Lightning Talks: show co-located breaks only inside their events' cards. The Evening Reception "
                  "is [] on purpose although the source tags it with all 11 events: it is open to every co-located "
                  "attendee and is an ordinary time-block session.",
    "format": "'Breakout', 'Panel', 'Lightning talk' or 'Keynote'. null when Sessionize gives none "
              "(welcome/closing remarks, breaks).",
    "level": "'Any level', 'Beginner', 'Intermediate' or 'Advanced'. null when not given.",
    "sponsored": "true for sponsored talks (Sessionize subtopic 'Sponsored'; all are short keynotes).",
    "topic": "The talk's topic within its event (e.g. 'Progressive Delivery'). null when none.",
    "slidesUrl": "Uploaded slides (as in schedule.json; the details sheet's Slides link). null when none.",
    "description": "Always null on sessions, as for KubeCon sessions in schedule.json. Descriptions and speaker "
                   "taglines are in colocated_details.json (details.json's shape).",
    "room": "A rooms.json code, or a code in this file's 'rooms' (position-less places such as foyers). "
            "The Evening Reception's 'Lower & Upper Mezzanine' is UM (shown as 'Upper Mezzanine').",
    "events": "One per CNCF-hosted co-located event, alphabetical. start/end/halfDay describe the talks "
              "(first talk start to last talk end, Welcome/Closing Remarks included): use them for the card's hours "
              "and its 'finished', never the placeholder's times (several differ by a few minutes). Agenda breaks "
              "can run past end (e.g. CiliumCon's and FluxCon's lunches start as the event ends). "
              "supersedes = the schedule.json placeholder session id this event replaces (don't show both). "
              "infoUrl = that placeholder's official listing. pageUrl = the event's LF page. "
              "passNote = the placeholder's note.",
    "anthropicSpeakers": "Anthropic colleagues speaking at the co-located events (see _rules). Add them to "
                         "schedule.json's anthropicSpeakers at load: hasAnthropic() checks names at runtime, so the "
                         "precomputed hasAnthropicSpeaker alone does nothing.",
    "omitted": "Source sessions intentionally left out, with the reason.",
}

# Notes for whoever merges this file into the app (not field descriptions).
INTEGRATION = [
    "Assets: the app loads data from app/src/main/assets only; copy data/colocated.json and "
    "data/colocated_details.json there.",
    "Decoding: the top level decodes with ScheduleFileDto (sessions, anthropicSpeakers, fieldNotes, timeZone) and "
    "RoomsFileDto (rooms); 'events' needs its own DTO. colocated_details.json's 'details' is "
    "Map<String, DetailDto>. Every other key is ignored by the app's Json (ignoreUnknownKeys).",
    "Details: merge colocated_details.json's 'details' into the bundled details map (repo.details), lazily like "
    "details.json: they are a separate file so the start-up parse of colocated.json doesn't read them. "
    "These ids are plain digits, so "
    "DetailsRepository.isKubeConId() matches them: never live-fetch or disk-cache event == 'colocated' sessions "
    "(the live fetch would hit the main KubeCon Sessionize event, uo948i5p).",
    "Anthropic: repo.anthropicSpeakers = schedule.json's anthropicSpeakers + this file's.",
    "Day view: leave colo groups (talks) and co-located breaks out of the time blocks; they live in the event cards. "
    "The experience (Evening Reception) is an ordinary time-block session. Hide the 'supersedes' placeholders.",
    "Search: add the event name (group.title) to the search haystack so 'argocon' finds its talks.",
    "Tests pinned to schedule.json (RepositoryTest's 614 sessions / 40 rooms / 558 details, ScheduleRulesTest's "
    "catOf/seriesOf per session) must exclude event == 'colocated' or be updated.",
]


# ----------------------------------------------------------------------------- fetching

def fetch_page(url):
    err = None
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "text/html,*/*"})
            with urllib.request.urlopen(req, timeout=45) as r:
                return r.read().decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001
            err = e
            time.sleep(2 * (attempt + 1))
    raise SystemExit("could not download {}: {}".format(url, err))


def denver_tz():
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo(TZ_NAME)
    except Exception:  # noqa: BLE001  (no tz database: fall back to the fixed MST offset)
        return datetime.timezone(datetime.timedelta(hours=-7), "MST")


def extract_sched_data(page):
    m = re.search(r'<script\b[^>]*\bclass="[^"]*\bsched-data\b[^"]*"[^>]*>(.*?)</script>', page, re.S)
    if not m:
        raise SystemExit("no <script class=\"sched-data\"> in the page: has the page layout changed?")
    return json.loads(m.group(1))


def session_links(page):
    """id -> href of the page's own session anchors (<a class="sess-link" href=... data-session-id=...>)."""
    out = {}
    for tag in re.findall(r'<a\b[^>]*\bsess-link\b[^>]*>', page):
        href = re.search(r'\bhref="([^"]+)"', tag)
        sid = re.search(r'\bdata-session-id="([^"]+)"', tag)
        if href and sid:
            out.setdefault(sid.group(1), html.unescape(href.group(1)))
    return out


# ----------------------------------------------------------------------------- text

def clean(s):
    """Unescape, NFC, collapse whitespace (incl. nbsp/zero-width), strip. Keeps Unicode."""
    s = unicodedata.normalize("NFC", html.unescape(s or ""))
    s = re.sub(r"[\u200b\u200c\u200d\ufeff]", "", s)
    return re.sub(r"\s+", " ", s).strip()


def clean_name(s):
    s = clean(s)
    s = re.sub(r"(?:\s+[-–—.])+$", "", s)  # "Flynn -" -> "Flynn"
    return s.strip()


def slugify(name):
    s = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


URL_RE = re.compile(r"https?://[^\s<>\"]+")


def md_escape(text):
    """Escape what DescriptionFormat would otherwise treat as markup, leaving URLs intact."""
    out, pos = [], 0
    for m in URL_RE.finditer(text):
        out.append(re.sub(r"([\\*_\[<])", r"\\\1", text[pos:m.start()]))
        out.append(m.group(0))
        pos = m.end()
    out.append(re.sub(r"([\\*_\[<])", r"\\\1", text[pos:]))
    return "".join(out)


class _HtmlToMd(html.parser.HTMLParser):
    """Sessionize description HTML -> markdown subset (see RULES)."""

    BLOCK = {"p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "table", "tr"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []
        self.lists = []      # stack of [kind, counter]
        self.marks = []      # stack of (tag, index into out, href)
        self.repairs = 0     # emphasis turned back into snake_case underscores (see RULES)

    def _emit(self, s):
        self.out.append(s)

    def handle_starttag(self, tag, attrs):
        if tag in self.BLOCK:
            self._emit(" " if self.lists else "\n\n")  # <li><p>…</p></li> stays one item
        elif tag == "br":
            self._emit("\n")
        elif tag in ("ul", "ol"):
            self.lists.append([tag, 0])
            self._emit("\n\n")
        elif tag == "li":
            kind = self.lists[-1] if self.lists else ["ul", 0]
            kind[1] += 1
            self._emit("\n" + ("{}. ".format(kind[1]) if kind[0] == "ol" else "- "))
        elif tag in ("a", "em", "i", "strong", "b"):
            self.marks.append((tag, len(self.out), dict(attrs).get("href")))

    def handle_startendtag(self, tag, attrs):
        if tag == "br":
            self._emit("\n")
        else:
            self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        if tag in self.BLOCK:
            self._emit(" " if self.lists else "\n\n")
        elif tag in ("ul", "ol"):
            if self.lists:
                self.lists.pop()
            self._emit("\n\n")
        elif tag == "li":
            self._emit("\n")
        elif tag in ("a", "em", "i", "strong", "b"):
            idx = next((i for i in range(len(self.marks) - 1, -1, -1) if self.marks[i][0] == tag), None)
            if idx is None:
                return
            _, start, href = self.marks.pop(idx)
            inner = "".join(self.out[start:])
            del self.out[start:]
            lead = inner[: len(inner) - len(inner.lstrip())]
            trail = inner[len(inner.rstrip()):]
            core = inner.strip()
            if not core:
                self._emit(inner)
                return
            if tag == "a":
                href = (href or "").strip()
                plain = re.sub(r"\\(.)", r"\1", core)
                if not re.match(r"https?://", href):
                    rendered = core
                elif plain.rstrip("/") == href.rstrip("/"):
                    rendered = href  # a bare URL; DescriptionFormat links it
                elif ")" in href or " " in href:
                    rendered = "{} ({})".format(core, href)
                else:
                    rendered = "[{}]({})".format(core, href)
            else:
                before = next((c for c in reversed(self.out[:start]) if c), "")[-1:]
                if before.isalnum() and not lead:
                    # "build<em>id … build</em>id": Sessionize read the speaker's snake_case "_" as
                    # emphasis. Put the literal underscores back.
                    rendered = "\\_" + core + "\\_"
                    self.repairs += 1
                else:
                    d = "*" if tag in ("em", "i") else "**"
                    rendered = d + core + d
            self._emit(lead + rendered + trail)

    def handle_data(self, data):
        self._emit(md_escape(re.sub(r"\s+", " ", data)))

    def result(self):
        text = "".join(self.out)
        lines = [re.sub(r"^(#+\s)", r"\\\1", ln.strip()) for ln in text.split("\n")]  # no accidental headings
        text = "\n".join(lines)
        text = re.sub(r"\n{3,}", "\n\n", text).strip()
        # One list per run of items: </ul><ul> and </li><li> leave blank lines between items.
        text = re.sub(r"(?m)^((?:- |\d+\. ).*)\n\n+(?=(?:- |\d+\. ))", r"\1\n", text)
        text = re.sub(r"(?m)^((?:- |\d+\. ).*)\n\n+(?=(?:- |\d+\. ))", r"\1\n", text)
        return text


def description_md(raw):
    """-> (markdown, number of underscore repairs)."""
    raw = unicodedata.normalize("NFC", raw or "")
    if not raw.strip():
        return "", 0
    if not re.search(r"<\s*/?\s*[a-zA-Z][^>]*>", raw):  # plain text
        text = raw.replace("\r\n", "\n").replace("\r", "\n")
        lines = [md_escape(re.sub(r"[ \t\u00a0]+", " ", ln).strip()) for ln in text.split("\n")]
        return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip(), 0
    p = _HtmlToMd()
    p.feed(raw.replace("\r\n", "\n"))
    p.close()
    return p.result(), p.repairs


# ----------------------------------------------------------------------------- rooms

def _room_key(name):
    """'Grand Ballroom IG' -> 'GI', 'Room 151' -> '151', '251 A–C' -> '251AC', '255 BC' -> '255BC'."""
    s = clean(name).upper()
    s = re.sub(r"\b(GRAND BALLROOM|BALLROOM|ROOM)\b", "", s)
    s = re.sub(r"[\s\-–—]+", "", s)
    m = re.fullmatch(r"(\d*)([A-Z]*)", s)
    if m:  # sections in any order
        s = m.group(1) + "".join(sorted(m.group(2)))
    return s


def map_room(source_name, rooms):
    for pat, code in SPECIAL_ROOMS:
        if re.search(pat, source_name, re.I):
            return code
    parts = [clean(p) for p in source_name.split("|")]
    level = next((int(m.group(1)) for p in parts for m in [re.fullmatch(r"Level (\d+)", p, re.I)] if m), None)
    name = parts[-1]
    venue = parts[0].lower() if len(parts) > 1 else ""
    want = _room_key(name)
    hits = []
    for code, r in rooms.items():
        if r.get("venueCode") != "SP" or "salt palace" not in venue:
            continue
        if level is not None and r.get("level") != level:
            continue
        if _room_key(r["name"]) == want:
            hits.append(code)
    if len(hits) == 1:
        return hits[0]
    raise SystemExit("can't map source room {!r} to rooms.json (candidates: {}). Add it to SPECIAL_ROOMS or "
                     "NEW_ROOMS.".format(source_name, hits))


# ----------------------------------------------------------------------------- transform

def build(page, fetched_at, fetched_from):
    sched = json.loads((KIT / "data" / "schedule.json").read_text(encoding="utf-8"))
    rooms_json = json.loads((KIT / "data" / "rooms.json").read_text(encoding="utf-8"))["rooms"]
    data = extract_sched_data(page)
    src = data["all"]
    links = session_links(page)
    event_pages = set(re.findall(r'href="(https://events\.linuxfoundation\.org/kubecon-cloudnativecon-north-america/'
                                 r'co-located-events/[a-z0-9-]+/)"', page))
    tz = denver_tz()
    day_by_date = {d["date"]: d["key"] for d in sched["days"]}
    sched_ids = {s["id"] for s in sched["sessions"]}
    me = sched.get("me")
    anthropic = set(sched.get("anthropicSpeakers", []))

    # Categories
    item = {}  # item id -> (group title, item name)
    for c in src["categories"]:
        for it in c["items"]:
            item[it["id"]] = (c["title"], it["name"])

    def kind_of(name):
        n = name.lower()
        if "registration" in n:
            return "registration"
        if "break" in n:
            return "break"
        if "experience" in n:
            return "experience"
        return "event"

    event_items = [it for c in src["categories"] if c["title"].strip().lower() == "all sessions" for it in c["items"]]
    assert event_items, "no 'All Sessions' category"
    event_names = sorted({clean(it["name"]) for it in event_items if kind_of(it["name"]) == "event"}, key=str.casefold)
    key_of = {n: "colo-" + slugify(n) for n in event_names}
    order = {n: i for i, n in enumerate(event_names)}

    # Speakers
    speakers = {}
    anthropic_found = set()  # speakers whose tagLine or Company mentions Anthropic (see RULES)
    q_title = {q["id"] for q in src["questions"] if q["question"].strip().lower() == "speaker title"}
    q_company = {q["id"] for q in src["questions"] if q["question"].strip().lower() == "company"}
    q_slides = {q["id"] for q in src["questions"] if q["question"].strip().lower() == "presentation slides"}
    assert q_title and q_company and q_slides, "Sessionize questions renamed? {}".format(
        [q["question"] for q in src["questions"]])
    for sp in src["speakers"]:
        qa = {a["questionId"]: clean(a.get("answerValue")) for a in sp.get("questionAnswers") or []}
        title = next((qa[q] for q in q_title if qa.get(q)), "")
        company = next((qa[q] for q in q_company if qa.get(q)), "")
        name = clean_name(sp.get("fullName") or "{} {}".format(sp.get("firstName", ""), sp.get("lastName", "")))
        tagline = clean(sp.get("tagLine"))
        if ANTHROPIC_RE.search(tagline) or ANTHROPIC_RE.search(company):
            anthropic_found.add(name)
        if name and tagline.lower().startswith(name.lower()):  # "Alex Van Boxel, Principal …" -> "Principal …"
            tagline = re.sub(r"^[\s,|:–—-]+", "", tagline[len(name):])
        speakers[sp["id"]] = {"name": name, "tagline": tagline or ", ".join(x for x in (title, company) if x)}
    anthropic_all = anthropic | anthropic_found

    room_name = {r["id"]: r["name"] for r in src["rooms"]}
    room_code = {rid: map_room(n, {**rooms_json, **NEW_ROOMS}) for rid, n in room_name.items()}

    # Placeholders in schedule.json that the event cards replace
    placeholders = {}
    for s in sched["sessions"]:
        if s["category"] == "colo" and s.get("note") == "All-Access pass" and s["room"] != "OFF":
            base = clean(re.sub(r"\(\s*half day\s*\)", "", s["title"], flags=re.I))
            assert base not in placeholders, "two placeholders named {!r}".format(base)
            placeholders[base] = s

    def iso(local):
        dt = datetime.datetime.strptime(local[:19], "%Y-%m-%dT%H:%M:%S")
        off = dt.replace(tzinfo=tz).utcoffset()
        assert off == datetime.timedelta(hours=-7), "{} is not MST in {}".format(local, TZ_NAME)
        return dt.strftime("%Y-%m-%dT%H:%M:%S") + OFFSET

    sessions, details, omitted, repairs = [], {}, [], []
    for s in src["sessions"]:
        sid = str(s["id"])
        title = clean(s["title"])
        cats = [item[c] for c in s.get("categoryItems") or [] if c in item]
        tagged = [clean(n) for g, n in cats if g.strip().lower() == "all sessions"]
        kinds = {kind_of(n) for n in tagged}
        evs = sorted({n for n in tagged if kind_of(n) == "event"}, key=lambda n: order[n])
        if "registration" in kinds:
            omitted.append({"id": sid, "title": title, "start": iso(s["startsAt"]), "reason": "registration / coat check"})
            continue
        if re.match(r"^\W*cancel+ed\W", title, re.I):
            omitted.append({"id": sid, "title": title, "start": iso(s["startsAt"]), "reason": "canceled",
                            "coloEvent": key_of[evs[0]] if evs else None})
            continue
        assert s.get("status", "Accepted") == "Accepted", (sid, s.get("status"))
        start, end = iso(s["startsAt"]), iso(s["endsAt"])
        day = day_by_date[start[:10]]
        fmt = next((n for g, n in cats if g.strip().lower() == "session format"), None)
        lvl = next((n for g, n in cats if g.strip().lower() == "audience level"), None)
        sponsored = any(g.strip().lower() == "subtopic" and n.strip().lower() == "sponsored" for g, n in cats)
        if fmt is not None:
            k = re.sub(r"[^a-z ]", "", fmt.lower()).strip()
            fmt = FORMATS.get(k) or clean(re.sub(r"^[^\w]+", "", fmt))
        if lvl is not None:
            lvl = LEVELS.get(lvl.strip().lower(), clean(lvl))
        spk_ids = [x["id"] if isinstance(x, dict) else x for x in s.get("speakers") or []]
        spk = [speakers[x] for x in spk_ids if x in speakers]
        names = [x["name"] for x in spk]
        slides = next((clean(a.get("answerValue")) for a in s.get("questionAnswers") or []
                       if a.get("questionId") in q_slides and clean(a.get("answerValue"))), None)
        topics = [(g, clean(n)) for g, n in cats if g.strip().lower() not in STANDARD_GROUPS]
        assert len(topics) <= 1, "session {} has several topics: {}".format(sid, topics)
        topic_group, topic = topics[0] if topics else (None, None)

        if "experience" in kinds:
            kind, category, group, colo_event, colo_events = "experience", "soc", None, None, []
        elif "break" in kinds:
            kind, category, group = "break", "log", None
            colo_events = [key_of[n] for n in evs]
            colo_event = colo_events[0] if len(colo_events) == 1 else None
            t = title.lower()
            title = "🍲 Lunch" if "lunch" in t else "☕ Coffee Break" if "break" in t or "coffee" in t else "☕ " + title
        else:
            assert len(evs) == 1, "talk {} {!r} is tagged with {} events: {}".format(sid, title, len(evs), evs)
            kind, category = "talk", "colo"
            key = key_of[evs[0]]
            group, colo_event, colo_events = {"key": key, "title": evs[0]}, key, [key]

        out_id = "c" + sid if sid in sched_ids else sid
        sessions.append({
            "id": out_id,
            "event": "colocated",
            "day": day,
            "start": start,
            "end": end,
            "endIsEstimate": False,
            "room": room_code[s["roomId"]],
            "title": title,
            "speakers": names,
            "note": None,
            "category": category,
            "group": group,
            "isMine": bool(me) and me in names,
            "hasAnthropicSpeaker": not (bool(me) and me in names) and any(n != me and n in anthropic_all for n in names),
            "officialUrl": None,  # filled in below, once events are known
            "description": None,
            "slidesUrl": slides,
            "coloEvent": colo_event,
            "coloEvents": colo_events,
            "format": fmt,
            "level": lvl,
            "sponsored": sponsored,
            "topic": topic,
            "_kind": kind,
            "_src": s,
            "_topicGroup": topic_group,
        })
        desc, repaired = description_md(s.get("description"))
        if repaired:
            repairs.append(out_id)
        if desc or spk:
            details[out_id] = {"description": desc, "speakers": [dict(x) for x in spk]}

    # Events
    events = []
    for n in event_names:
        key = key_of[n]
        talks = sorted((x for x in sessions if x["_kind"] == "talk" and x["coloEvent"] == key), key=lambda x: x["start"])
        assert talks, "event {!r} has no talks".format(n)
        counts = collections.Counter(x["room"] for x in talks)
        main = max(counts, key=lambda r: (counts[r], -[x["room"] for x in talks].index(r)))
        ph = placeholders.get(n)
        assert ph, "no schedule.json placeholder for {!r}".format(n)
        page_url = EVENT_PAGE.format(slug=slugify(n))
        half = bool(re.search(r"\(\s*half day\s*\)", ph["title"], re.I))
        start, end = min(x["start"] for x in talks), max(x["end"] for x in talks)
        events.append({
            "key": key,
            "name": n,
            "mainRoom": main,
            "rooms": [main] + [r for r, _ in counts.most_common() if r != main],
            "start": start,
            "end": end,
            "halfDay": half,
            "talkCount": len(talks),
            "supersedes": ph["id"],
            "infoUrl": ph.get("officialUrl") or page_url,
            "pageUrl": page_url if page_url in event_pages else None,
            "passNote": ph.get("note"),
            "_placeholder": ph,
        })
    ev_by_key = {e["key"]: e for e in events}

    # officialUrl: the page's own per-session link; otherwise the event page.
    for x in sessions:
        sid = str(x["_src"]["id"])
        ev = ev_by_key.get(x["coloEvent"] or "")
        fallback = (ev["pageUrl"] or ev["infoUrl"]) if ev else PAGE
        if links:
            x["officialUrl"] = links.get(sid) or fallback
        else:  # a page without anchors (e.g. only the JSON was saved): the page's documented URL format
            x["officialUrl"] = PAGE + "?id=" + sid

    def sort_key(x):
        ev = ev_by_key.get(x["coloEvent"] or (x["coloEvents"][0] if x["coloEvents"] else ""))
        main_first = 0 if ev and x["room"] == ev["mainRoom"] else 1
        return (x["start"], order.get(ev["name"], 99) if ev else 99, main_first, x["end"], x["id"])

    sessions.sort(key=sort_key)
    used_new = sorted({x["room"] for x in sessions if x["room"] in NEW_ROOMS})
    # Anthropic colleagues speaking here: found in this source, or already in schedule.json's list.
    anthropic_speakers = sorted({n for x in sessions for n in x["speakers"] if n in anthropic_all}, key=str.casefold)

    report = {
        "events": events, "sessions": sessions, "details": details, "omitted": omitted,
        "src": src, "links": links, "room_name": room_name, "room_code": room_code,
        "rooms_json": rooms_json, "sched": sched, "sched_ids": sched_ids, "item": item,
        "placeholders": placeholders, "event_names": event_names, "key_of": key_of, "kind_of": kind_of,
        "anthropic_sched": anthropic, "anthropic_speakers": anthropic_speakers, "me": me, "q_slides": q_slides,
        "repairs": repairs,
    }
    validate(report)

    strip = lambda d: {k: v for k, v in d.items() if not k.startswith("_")}  # noqa: E731
    fetched = datetime.datetime.fromisoformat(fetched_at)
    when = "{:%b} {}, {} at {}:{:%M} {} MST".format(fetched, fetched.day, fetched.year, fetched.hour % 12 or 12,
                                                   fetched, "AM" if fetched.hour < 12 else "PM")
    doc = {
        # A string, like schedule.json's and rooms.json's, so ScheduleFileDto can decode this file.
        "_about": "CNCF-hosted co-located events at KubeCon + CloudNativeCon NA 2026 (Salt Palace, Monday Nov 9), "
                  "copied from the LF co-located schedule (Sessionize export) on {}. One entry per talk, shaped "
                  "like schedule.json's sessions, plus the events, their breaks and the Evening Reception. All "
                  "times are MST (UTC-07:00, zone America/Denver). Registration and coat check are left out on "
                  "purpose. Generated by scripts/fetch_colocated.py: rules in _rules, source and counts in _meta, "
                  "merge notes in _integration.".format(when),
        "_meta": {
            "source": PAGE,
            "sourceData": "Sessionize 'All' export embedded in the page as <script type=\"application/json\" "
                          "class=\"sched-data\"> (Sessionize event ayajbd6b, "
                          "https://cncf-hosted-co-located-events-north-america-2026.sessionize.com).",
            "fetchedAt": fetched_at,
            "fetchedFrom": fetched_from,
            "generator": "scripts/fetch_colocated.py",
            "counts": {
                "events": len(events),
                "talks": sum(1 for x in sessions if x["_kind"] == "talk"),
                "breaks": sum(1 for x in sessions if x["_kind"] == "break"),
                "experiences": sum(1 for x in sessions if x["_kind"] == "experience"),
                "omitted": len(omitted),
                "sourceSessions": len(src["sessions"]),
                "withSlides": sum(1 for x in sessions if x["slidesUrl"]),
                "withTopic": sum(1 for x in sessions if x["topic"]),
                "anthropicSpeakers": len(anthropic_speakers),
            },
            "underscoreRepairs": repairs,
        },
        "_rules": RULES,
        "_integration": INTEGRATION,
        "timeZone": TZ_NAME,
        "anthropicSpeakers": anthropic_speakers,
        "fieldNotes": FIELD_NOTES,
        "events": [strip(e) for e in events],
        "sessions": [strip(x) for x in sessions],
        "rooms": {k: NEW_ROOMS[k] for k in used_new},
        "omitted": omitted,
    }
    validate_doc(doc)
    details_doc = {
        "_about": "Descriptions and speaker taglines (the same shape as details.json) for the sessions in "
                  "colocated.json, copied from the same LF co-located schedule on {}. A file of its own so that "
                  "the app's start-up parse of colocated.json stays small: the app reads these lazily, with "
                  "details.json. Complete for colocated.json's sessions (breaks carry their menus). Generated "
                  "by scripts/fetch_colocated.py together with colocated.json.".format(when),
        "_meta": {
            "source": PAGE,
            "fetchedAt": fetched_at,
            "generator": "scripts/fetch_colocated.py",
            "count": sum(1 for x in sessions if x["id"] in details),
        },
        "fieldNotes": {
            "details": "Session id -> {description, speakers: [{name, tagline}]}, the same shape as details.json. "
                       "Every id is a session in colocated.json.",
        },
        "details": {x["id"]: details[x["id"]] for x in sessions if x["id"] in details},
    }
    validate_details_doc(details_doc, doc)
    return doc, details_doc, report


# ----------------------------------------------------------------------------- validation

ISO_RE = re.compile(r"^2026-11-0[89]T\d\d:\d\d:00-07:00$")


def validate(r):
    events, sessions, details, omitted, src = r["events"], r["sessions"], r["details"], r["omitted"], r["src"]
    known_rooms = set(r["rooms_json"]) | set(NEW_ROOMS)
    categories = set(r["sched"]["categories"])

    # Every source session is accounted for exactly once.
    out_src_ids = [str(x["_src"]["id"]) for x in sessions] + [o["id"] for o in omitted]
    assert sorted(out_src_ids) == sorted(str(s["id"]) for s in src["sessions"]), "sessions lost or duplicated"

    # Counts per event: recount talks straight from the source categories.
    for e in events:
        n = e["name"]
        want = 0
        for s in src["sessions"]:
            tagged = [clean(r["item"][c][1]) for c in s.get("categoryItems") or []
                      if c in r["item"] and r["item"][c][0].strip().lower() == "all sessions"]
            kinds = {r["kind_of"](t) for t in tagged}
            if n in tagged and kinds == {"event"} and not re.match(r"^\W*cancel+ed\W", clean(s["title"]), re.I):
                want += 1
        got = sum(1 for x in sessions if x["_kind"] == "talk" and x["coloEvent"] == e["key"])
        assert got == want == e["talkCount"] and got >= 5, "talk count for {}: {} vs {}".format(n, got, want)
    assert len(events) == len(r["placeholders"]) == 11, "expected 11 events and 11 placeholders"
    assert sorted(e["supersedes"] for e in events) == sorted(p["id"] for p in r["placeholders"].values())
    assert [e["name"] for e in events] == sorted((e["name"] for e in events), key=str.casefold)

    ids = [x["id"] for x in sessions]
    assert len(ids) == len(set(ids)), "duplicate session ids"
    assert not (set(ids) & r["sched_ids"]), "id collision with schedule.json"
    for x in sessions:
        assert x["room"] in known_rooms, "unknown room {} for {}".format(x["room"], x["id"])
        assert ISO_RE.match(x["start"]) and ISO_RE.match(x["end"]), (x["id"], x["start"], x["end"])
        assert x["end"] > x["start"], "end before start: {}".format(x["id"])
        assert x["day"] == {"2026-11-08": "sun", "2026-11-09": "mon"}[x["start"][:10]], x["id"]
        assert x["category"] in categories, x["category"]
        assert x["title"] and x["title"] == x["title"].strip() and "  " not in x["title"], repr(x["title"])
        assert all(n and n == n.strip() for n in x["speakers"]), x["speakers"]
        assert x["officialUrl"].startswith("https://"), x["officialUrl"]
        if x["_kind"] == "talk":
            assert x["category"] == "colo" and x["group"] and x["group"]["key"] == x["coloEvent"], x["id"]
            assert x["coloEvents"] == [x["coloEvent"]] and x["coloEvent"] in {e["key"] for e in events}
            assert x["note"] != "All-Access pass"  # would make the app treat it as an all-day row
        else:
            assert x["group"] is None, "breaks/experiences have no group: {}".format(x["id"])
            assert x["category"] in ("log", "soc", "com"), x["id"]
        if x["_kind"] == "break":
            assert x["coloEvents"] and set(x["coloEvents"]) <= {e["key"] for e in events}, x["id"]
    for code, room in NEW_ROOMS.items():
        assert code not in r["rooms_json"], "new room code {} already exists in rooms.json".format(code)
        assert not ({"lat", "lng", "x", "y", "attachNode", "finalStep"} & set(room)), "new rooms get no position"
    # Every source room maps (registration rooms included) and levels agree with rooms.json.
    for rid, name in r["room_name"].items():
        code = r["room_code"][rid]
        m = re.search(r"\bLevel (\d+)\b", name)
        lv = ({**r["rooms_json"], **NEW_ROOMS}[code]).get("level")
        if m and lv is not None:
            assert int(m.group(1)) == lv, "level mismatch: {!r} -> {}".format(name, code)
    for e in events:
        ph = e["_placeholder"]
        assert e["mainRoom"] == ph["room"], "{}: main room {} but placeholder room {}".format(e["name"], e["mainRoom"], ph["room"])
        hours = (datetime.datetime.fromisoformat(e["end"]) - datetime.datetime.fromisoformat(e["start"])).total_seconds() / 3600
        assert e["halfDay"] == (hours <= 5), "{}: halfDay={} but {:.1f} h".format(e["name"], e["halfDay"], hours)
        assert ISO_RE.match(e["start"]) and ISO_RE.match(e["end"])
    assert set(details) <= set(ids)
    for x in sessions:
        if x["_kind"] == "talk" and x["speakers"]:
            assert x["id"] in details and [s["name"] for s in details[x["id"]]["speakers"]] == x["speakers"], x["id"]
    for d in details.values():
        assert "<p>" not in d["description"] and "&#039;" not in d["description"] and "&amp;" not in d["description"]

    # Anthropic: re-derive straight from the raw source (every question answer, not just Company) and check
    # the list and every precomputed flag.
    me, sched_anth = r["me"], r["anthropic_sched"]
    out_names = {n for x in sessions for n in x["speakers"]}
    raw_anth = set()
    for sp in src["speakers"]:
        texts = [sp.get("tagLine") or ""] + [a.get("answerValue") or "" for a in sp.get("questionAnswers") or []]
        if any(ANTHROPIC_RE.search(t) for t in texts):
            raw_anth.add(clean_name(sp.get("fullName") or ""))
    want_anth = (raw_anth | sched_anth) & out_names
    assert set(r["anthropic_speakers"]) == want_anth, "anthropicSpeakers {} != {}".format(
        r["anthropic_speakers"], sorted(want_anth))
    for x in sessions:
        mine = bool(me) and me in x["speakers"]
        anth = not mine and any(n != me and n in want_anth for n in x["speakers"])
        assert x["isMine"] == mine and x["hasAnthropicSpeaker"] == anth, "mine/Anthropic flags for {}".format(x["id"])

    # Slides: one per source session that has a 'Presentation Slides' answer, and only sessionize download links.
    for x in sessions:
        has = any(a.get("questionId") in r["q_slides"] and clean(a.get("answerValue"))
                  for a in x["_src"].get("questionAnswers") or [])
        assert bool(x["slidesUrl"]) == has, "slidesUrl for {}".format(x["id"])
        assert x["slidesUrl"] is None or SLIDES_RE.match(x["slidesUrl"]), (x["id"], x["slidesUrl"])

    # Topics come from the session's own event's topic category; breaks and experiences have none.
    for x in sessions:
        if x["topic"] is None:
            continue
        assert x["_kind"] == "talk", "non-talk {} has topic {!r}".format(x["id"], x["topic"])
        group = re.sub(r"\s+topics$", "", x["_topicGroup"].strip(), flags=re.I)
        assert clean(group) == x["group"]["title"], "topic of {} is from {!r}, not its event".format(
            x["id"], x["_topicGroup"])

    # Underscore repairs only ever turn emphasis into literal underscores inside a word.
    for sid in r["repairs"]:
        assert re.search(r"\w\\_\S", details[sid]["description"]), "repair in {} left no '\\_' in a word".format(sid)

    # fieldNotes.coloEvents promises that no co-located break coincides with a schedule.json Monday break, so the
    # cards are the only place they show. If one ever does, de-duplicate it and update that note.
    sched_breaks = {(s["start"], s["end"]) for s in r["sched"]["sessions"] if s["category"] == "log"} | \
        {(s["start"], s["title"]) for s in r["sched"]["sessions"] if s["category"] == "log"}
    for x in sessions:
        if x["_kind"] == "break":
            assert (x["start"], x["end"]) not in sched_breaks and (x["start"], x["title"]) not in sched_breaks, \
                "break {} duplicates a schedule.json break: de-duplicate it and update fieldNotes".format(x["id"])

    # Soft check: talks in the same room shouldn't overlap.
    by_room = collections.defaultdict(list)
    for x in sessions:
        if x["_kind"] == "talk":
            by_room[x["room"]].append(x)
    for room, xs in by_room.items():
        xs.sort(key=lambda x: x["start"])
        for a, b in zip(xs, xs[1:]):
            if b["start"] < a["end"]:
                print("warning: overlap in {}: {} {} / {} {}".format(room, a["id"], a["title"][:40], b["id"], b["title"][:40]),
                      file=sys.stderr)


def validate_doc(doc):
    """The written shape must decode with the app's DTOs (data/Dto.kt): ScheduleFileDto for the top level and
    sessions, RoomsFileDto for 'rooms'. kotlinx.serialization can't turn an object into a String, so a wrong
    type here would make the whole repository fail to load. The details are checked by validate_details_doc."""
    S, B, N = (str,), (bool,), (int, float)
    opt = lambda *t: tuple(t) + (type(None),)  # noqa: E731

    def check(obj, fields, where):
        assert isinstance(obj, dict), "{} is not an object".format(where)
        for k, (types, required) in fields.items():
            if k not in obj:
                assert not required, "{}: missing {}".format(where, k)
                continue
            v = obj[k]
            ok = isinstance(v, types) and not (isinstance(v, bool) and bool not in types)
            assert ok, "{}.{} = {!r} is not {}".format(where, k, v, [t.__name__ for t in types])

    check(doc, {"_about": (S, True), "timeZone": (S, True), "anthropicSpeakers": ((list,), True),
                "fieldNotes": ((dict,), True), "sessions": ((list,), True), "rooms": ((dict,), True),
                "events": ((list,), True)}, "top level")
    assert "details" not in doc, "the details belong in " + DETAILS_NAME
    assert all(isinstance(n, str) for n in doc["anthropicSpeakers"])
    assert all(isinstance(k, str) and isinstance(v, str) for k, v in doc["fieldNotes"].items()), \
        "fieldNotes must be Map<String, String>"
    session_dto = {
        "id": (S, True), "event": (S, True), "day": (S, True), "start": (S, True), "end": (opt(str), False),
        "endIsEstimate": (B, False), "room": (S, True), "title": (S, True), "speakers": ((list,), False),
        "note": (opt(str), False), "category": (S, True), "group": (opt(dict), False), "isMine": (B, False),
        "hasAnthropicSpeaker": (B, False), "officialUrl": (S, False), "description": (opt(str), False),
        "slidesUrl": (opt(str), False),
    }
    for x in doc["sessions"]:
        where = "session " + str(x.get("id"))
        check(x, session_dto, where)
        assert all(isinstance(n, str) for n in x["speakers"]), where
        if x["group"] is not None:
            check(x["group"], {"key": (S, True), "title": (S, True)}, where + ".group")
        check(x, {"coloEvent": (opt(str), True), "coloEvents": ((list,), True), "format": (opt(str), True),
                  "level": (opt(str), True), "sponsored": (B, True), "topic": (opt(str), True)}, where)
    room_dto = {"name": (S, True), "buildingLabel": (opt(str), False), "venue": (opt(str), False),
                "venueCode": (opt(str), False), "level": (opt(int), False), "lat": (opt(*N), False),
                "lng": (opt(*N), False), "x": (opt(*N), False), "y": (opt(*N), False),
                "whereText": (opt(str), False), "attachNode": (opt(str), False), "finalStep": (opt(str), False)}
    for code, room in doc["rooms"].items():
        check(room, room_dto, "room " + code)


def validate_details_doc(ddoc, doc):
    """colocated_details.json must decode with the app's ColocatedDetailsDto ('details': Map<String, DetailDto>),
    and hold exactly the details of colocated.json's sessions (every one of them has some), in its order."""
    S = (str,)
    assert isinstance(ddoc, dict) and isinstance(ddoc.get("_about"), str), "details top level"
    assert isinstance(ddoc.get("details"), dict), "details: missing 'details'"
    ids = [x["id"] for x in doc["sessions"]]
    assert list(ddoc["details"]) == ids, "details must cover colocated.json's sessions, in its order"
    assert ddoc["_meta"]["count"] == len(ids)
    for sid, d in ddoc["details"].items():
        assert isinstance(d, dict), "details " + sid
        assert isinstance(d.get("description", ""), S), "details {}.description".format(sid)
        assert isinstance(d.get("speakers", []), list), "details {}.speakers".format(sid)
        for sp in d.get("speakers", []):
            assert isinstance(sp, dict) and isinstance(sp.get("name"), str), "details {} speaker".format(sid)
            assert isinstance(sp.get("tagline", ""), S), "details {} speaker tagline".format(sid)


# ----------------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--offline", metavar="PAGE_HTML", help="read a saved copy of the schedule page instead of downloading it")
    ap.add_argument("--out", default=str(KIT / "data" / "colocated.json"), help="output file (default data/colocated.json)")
    ap.add_argument("--details-out", help="details output file (default: {} next to --out)".format(DETAILS_NAME))
    args = ap.parse_args()

    tz = denver_tz()
    if args.offline:
        path = pathlib.Path(args.offline)
        page = path.read_text(encoding="utf-8")
        fetched = datetime.datetime.fromtimestamp(path.stat().st_mtime, tz)
        fetched_from = "saved copy of the page (--offline); fetchedAt = the file's modification time"
    else:
        page = fetch_page(PAGE)
        fetched = datetime.datetime.now(tz)
        fetched_from = "live download"
    fetched_at = fetched.replace(microsecond=0).isoformat()

    doc, details_doc, rep = build(page, fetched_at, fetched_from)
    out = pathlib.Path(args.out)
    details_out = pathlib.Path(args.details_out) if args.details_out else out.with_name(DETAILS_NAME)
    assert details_out.resolve() != out.resolve(), "--details-out must differ from --out"
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    details_out.write_text(json.dumps(details_doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    back = json.loads(out.read_text(encoding="utf-8"))
    back_details = json.loads(details_out.read_text(encoding="utf-8"))
    validate_doc(back)  # what the app will read, not just what we meant to write
    validate_details_doc(back_details, back)
    assert back == doc and back_details == details_doc, "the written files don't round-trip"

    c = doc["_meta"]["counts"]
    rel = lambda f: f.relative_to(KIT) if f.is_relative_to(KIT) else f  # noqa: E731
    print("wrote {}: {} events, {} talks, {} breaks, {} experiences; {} omitted (of {} source sessions)".format(
        rel(out), c["events"], c["talks"], c["breaks"], c["experiences"], c["omitted"], c["sourceSessions"]))
    print("wrote {}: details for {} sessions".format(rel(details_out), details_doc["_meta"]["count"]))
    for e in rep["events"]:
        ph = e["_placeholder"]
        hm = lambda t: t[11:16]  # noqa: E731
        diff = "" if (ph["start"], ph["end"]) == (e["start"], e["end"]) else \
            "  (placeholder said {}–{})".format(hm(ph["start"]), hm(ph["end"] or ""))
        print("  {:<34} {:>2} talks  {}–{}  {:<6} rooms {}{}{}".format(
            e["name"], e["talkCount"], hm(e["start"]), hm(e["end"]), e["mainRoom"], "+".join(e["rooms"]),
            "  half day" if e["halfDay"] else "", diff))
    for o in doc["omitted"]:
        print("  omitted {} {} ({})".format(o["id"], o["title"], o["reason"]))
    print("  slides: {} sessions; topic: {} sessions; underscore repairs: {}".format(
        c["withSlides"], c["withTopic"], ", ".join(doc["_meta"]["underscoreRepairs"]) or "none"))
    for n in doc["anthropicSpeakers"]:
        talks = ["{} {} ({}, {})".format(x["id"], x["title"], x["group"]["title"] if x["group"] else x["category"],
                                         x["start"][11:16]) for x in doc["sessions"] if n in x["speakers"]]
        print("  Anthropic speaker {}: {}".format(n, "; ".join(talks)))
    print("  rooms: " + "; ".join("{} -> {}".format(rep["room_name"][k].replace("Salt Palace | ", ""), v)
                                  for k, v in sorted(rep["room_code"].items(), key=lambda kv: kv[1])))


if __name__ == "__main__":
    main()
