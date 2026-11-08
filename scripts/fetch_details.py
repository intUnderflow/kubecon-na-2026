#!/usr/bin/env python3
"""Fetch full descriptions and speaker taglines for every KubeCon session.

Writes data/details.json:  {"<session id>": {"description": "...", "speakers": [{"name": "...", "tagline": "..."}]}}

Source: Sessionize's public per-session markdown for the KubeCon NA 2026 event
(https://sessionize.com/api/v2/uo948i5p/view/markdown/session/<id>).
Maintainer Summit sessions already carry their descriptions in schedule.json.

Stdlib only. Usage:  python3 scripts/fetch_details.py   (from the repository root)
"""
import concurrent.futures as cf
import json
import pathlib
import re
import sys
import time
import urllib.request

KIT = pathlib.Path(__file__).resolve().parent.parent
URL = "https://sessionize.com/api/v2/uo948i5p/view/markdown/session/{}"
UA = "kubecon-schedule-app/1.0 (personal schedule app)"


def parse(md: str) -> dict:
    """Split the markdown on '## ' headings; keep the Description and Speaker(s) sections."""
    sections, cur = {}, None
    for line in md.replace("\r\n", "\n").split("\n"):
        h = re.match(r"^#{2,3}\s+(.+?)\s*$", line)
        if h:
            cur = h.group(1).lower()
            sections[cur] = []
        elif cur is not None:
            sections[cur].append(line)
    speakers = []
    for line in sections.get("speakers", sections.get("speaker", [])):
        if not re.match(r"^\s*[-*]\s+", line):
            continue
        line = re.sub(r"^\s*[-*]\s+", "", line).strip()
        m = re.match(r"^\[([^\]]+)\]\([^)]*\)\s*(?:[—–-]\s*(.*))?$", line) or re.match(r"^\**([^—–*]+?)\**\s*(?:[—–]\s*(.*))?$", line)
        speakers.append({"name": m.group(1).strip(), "tagline": (m.group(2) or "").strip()} if m else {"name": line, "tagline": ""})
    return {"description": "\n".join(sections.get("description", [])).strip(), "speakers": speakers}


def fetch(sid: str):
    for attempt in range(4):
        try:
            req = urllib.request.Request(URL.format(sid), headers={"User-Agent": UA, "Accept": "text/markdown, text/plain, */*"})
            with urllib.request.urlopen(req, timeout=20) as r:
                return sid, parse(r.read().decode("utf-8", "replace"))
        except Exception as e:  # noqa: BLE001
            err = e
            time.sleep(1.5 * (attempt + 1))
    return sid, err


def main():
    sched = json.loads((KIT / "data" / "schedule.json").read_text())
    ids = sorted({s["id"] for s in sched["sessions"] if s["event"] == "kubecon"})
    out, failed = {}, []
    with cf.ThreadPoolExecutor(max_workers=8) as pool:
        for i, (sid, res) in enumerate(pool.map(fetch, ids), 1):
            if isinstance(res, dict) and (res["description"] or res["speakers"]):
                out[sid] = res
            else:
                failed.append((sid, res))
            if i % 50 == 0:
                print(f"{i}/{len(ids)}", file=sys.stderr)
    (KIT / "data" / "details.json").write_text(json.dumps(out, ensure_ascii=False, indent=0) + "\n")
    print(f"wrote {len(out)} of {len(ids)} sessions to data/details.json; {len(failed)} empty or failed")
    for sid, res in failed[:10]:
        print("  ", sid, res if not isinstance(res, dict) else "no description or speakers")
    # Sessions with no speakers (breaks, receptions) legitimately come back nearly empty.
    sys.exit(0 if len(out) >= 0.6 * len(ids) else 1)


if __name__ == "__main__":
    main()
