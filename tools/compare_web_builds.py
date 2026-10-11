"""Measure two exported Web directories, including reproducible gzip sizes.

Gzip figures describe identical local compression, not observed browser traffic.
The report verifies that engine template changes did not change the game PCK.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path


def inventory(folder: Path) -> dict:
    files = {}
    for path in sorted(folder.rglob("*")):
        if not path.is_file() or ".git" in path.relative_to(folder).parts:
            continue
        data = path.read_bytes()
        files[path.relative_to(folder).as_posix()] = {
            "bytes": len(data),
            "gzip9_bytes": len(gzip.compress(data, compresslevel=9, mtime=0)),
            "sha256": hashlib.sha256(data).hexdigest(),
        }
    if not {"index.wasm", "index.pck", "index.html", "index.js"} <= files.keys():
        raise SystemExit(f"Incomplete Web export: {folder}")
    return {
        "directory": str(folder), "files": files,
        "total_bytes": sum(row["bytes"] for row in files.values()),
        "total_gzip9_bytes": sum(row["gzip9_bytes"] for row in files.values()),
    }


def delta(before: int, after: int) -> dict:
    return {"before": before, "after": after, "saved": before - after,
            "saved_percent": round((before - after) / before * 100, 3)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    before, after = inventory(args.before.resolve()), inventory(args.after.resolve())
    report = {"before": before, "after": after,
              "compression": "Python gzip level 9, mtime=0, each file independently",
              "game_pck_identical": before["files"]["index.pck"]["sha256"] == after["files"]["index.pck"]["sha256"],
              "deltas": {}}
    for key in ("total_bytes", "total_gzip9_bytes"):
        report["deltas"][key] = delta(before[key], after[key])
    for name in ("index.wasm", "index.pck", "index.js"):
        report["deltas"][name] = {
            key: delta(before["files"][name][key], after["files"][name][key])
            for key in ("bytes", "gzip9_bytes")
        }
    if args.report.exists():
        raise SystemExit("Report exists; preserve earlier measurements and choose a new path")
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"game_pck_identical": report["game_pck_identical"],
                      "deltas": report["deltas"], "report": str(args.report)}, indent=2))


if __name__ == "__main__":
    main()
