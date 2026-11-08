#!/usr/bin/env python3
"""Write data/manifest.json, which the app checks to pick up new schedule data.

    {"version": 7, "updatedAt": "2026-11-08T21:15:00Z",
     "files": {"schedule.json": {"sha256": "...", "bytes": 364257}, ...}}

It covers every data/*.json except test_vectors.json and the manifest itself.

The app downloads a data set only when its version is higher than the one it already has
(bundled or downloaded), so the version must never go down. It is one more than the highest
version found in the working tree's manifest, the app assets' manifest and every version of
data/manifest.json in the git history (all branches, remote-tracking ones included). It stays
the same only when the data files equal that highest version's files, so running the script
twice is harmless, and a `git revert` of a data change, or a merge that brings back an older
manifest, still gets a new, higher version. Never publish an older manifest by hand: fix
forward (edit the data, run this script, push).

If data/manifest.json exists but doesn't parse (merge conflict markers, for example) it stops
with an error rather than guess: resolve the file (either side will do), then run it again.

The APK bundles its own copy in app/src/main/assets/manifest.json. That copy is refreshed too
when the asset JSON files are identical to data/. With --sync-assets the data files are copied
into the assets first, so the next APK build bundles exactly what was published.

Stdlib only (git is optional). Usage, from the repo root:

    python3 scripts/make_manifest.py [--sync-assets] [--check]

--check writes nothing and exits 1 if data/manifest.json is not what this script would write
(stale files, or a version that isn't above every one published before).
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
ASSETS = ROOT / "app" / "src" / "main" / "assets"
MANIFEST = "manifest.json"
EXCLUDE = {MANIFEST, "test_vectors.json"}


class ManifestError(Exception):
    pass


def file_table(folder: pathlib.Path) -> dict:
    files = {}
    for p in sorted(folder.glob("*.json")):
        if p.name in EXCLUDE or not p.is_file():
            continue
        b = p.read_bytes()
        json.loads(b)  # refuse to publish a file the app could not parse
        files[p.name] = {"sha256": hashlib.sha256(b).hexdigest(), "bytes": len(b)}
    return files


def parse_manifest(raw) -> dict:
    """A manifest dict with an int version; raises ManifestError otherwise."""
    try:
        m = json.loads(raw)
    except ValueError as e:
        raise ManifestError(str(e)) from None
    if not isinstance(m, dict) or not isinstance(m.get("version"), int) or isinstance(m.get("version"), bool):
        raise ManifestError("no integer \"version\"")
    return m


def read_manifest(path: pathlib.Path, strict: bool):
    """The manifest at [path], None if it doesn't exist. A broken one raises if [strict], else is None."""
    if not path.is_file():
        return None
    try:
        return parse_manifest(path.read_bytes())
    except ManifestError:
        if strict:
            raise
        return None


def git(cwd: pathlib.Path, *args: str, stdin: bytes = None):
    try:
        r = subprocess.run(["git", *args], cwd=cwd, input=stdin, capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout if r.returncode == 0 else None


def git_history(data: pathlib.Path) -> list:
    """Every parseable version of data/manifest.json in the git history (all refs). [] without git."""
    prefix = git(data, "rev-parse", "--show-prefix")
    if prefix is None:
        return []  # not a git work tree, or no git
    path = prefix.decode().strip() + MANIFEST
    commits = git(data, "log", "--all", "--format=%H", "--", MANIFEST)
    if not commits:
        return []
    revs = [f"{c}:{path}" for c in commits.decode().split()]
    out = git(data, "cat-file", "--batch", stdin=("\n".join(revs) + "\n").encode())
    if out is None:
        return []
    found, i = [], 0
    while i < len(out):
        nl = out.index(b"\n", i)
        header = out[i:nl].split()
        i = nl + 1
        if len(header) == 3 and header[1] == b"blob":
            size = int(header[2])
            blob, i = out[i:i + size], i + size + 1  # content, then "\n"
            try:
                found.append(parse_manifest(blob))
            except ManifestError:
                pass  # an old broken commit can't have reached any phone
        # "<rev> missing": the commit deleted the file
    return found


def next_manifest(files: dict, known: list, now: str) -> dict:
    """Keep the top version if every manifest at that version has these files; else top + 1."""
    top = max((m["version"] for m in known), default=0)
    at_top = [m for m in known if m["version"] == top]
    if top > 0 and all(m.get("files") == files for m in at_top):
        return {"version": top, "updatedAt": at_top[0].get("updatedAt", ""), "files": files}
    return {"version": top + 1, "updatedAt": now, "files": files}


def render(manifest: dict) -> str:
    return json.dumps(manifest, indent=2, sort_keys=False) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--data", type=pathlib.Path, default=DATA)
    ap.add_argument("--assets", type=pathlib.Path, default=ASSETS)
    ap.add_argument("--sync-assets", action="store_true", help="copy data/*.json into the app assets first")
    ap.add_argument("--check", action="store_true", help="write nothing; exit 1 if the manifest is stale")
    args = ap.parse_args()

    files = file_table(args.data)
    if not files:
        print(f"no data files in {args.data}", file=sys.stderr)
        return 1

    target = args.data / MANIFEST
    try:
        current = read_manifest(target, strict=True)
    except ManifestError as e:
        print(
            f"{target} doesn't parse ({e}). Merge conflict? Resolve it (either side will do) "
            "and run this again; the version is picked from the git history, so it still goes up.",
            file=sys.stderr,
        )
        return 2

    known = [m for m in [current, read_manifest(args.assets / MANIFEST, strict=False)] if m] + git_history(args.data)
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    manifest = next_manifest(files, known, now)
    changed = current != manifest

    if args.check:
        if changed:
            have = current["version"] if current else "none"
            print(
                f"{target} is out of date (version {have}, should be {manifest['version']}): "
                "run scripts/make_manifest.py",
                file=sys.stderr,
            )
            return 1
        print(f"manifest up to date (version {manifest['version']})")
        return 0

    if changed:
        target.write_text(render(manifest), encoding="utf-8")
        print(f"wrote {target}: version {manifest['version']}, {len(files)} files")
    else:
        print(f"no data changes: version stays {manifest['version']}")

    if args.assets.is_dir():
        if args.sync_assets:
            for name in files:
                shutil.copyfile(args.data / name, args.assets / name)
        assets_files = {n: e for n, e in file_table(args.assets).items() if n in files}
        if assets_files == files:
            bundled = args.assets / MANIFEST
            if read_manifest(bundled, strict=False) != manifest:
                bundled.write_text(render(manifest), encoding="utf-8")
                print(f"wrote {bundled}")
        else:
            differ = sorted(n for n in files if assets_files.get(n) != files[n])
            print(
                f"warning: {args.assets} differs from data/ ({', '.join(differ)}); "
                "its manifest was left alone. Run with --sync-assets to bundle the published data.",
                file=sys.stderr,
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
