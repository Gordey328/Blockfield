"""Export an isolated local inspection build including ignored local map packages."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

import build
from web_release_template import select


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=build.ROOT / "build" / "local-maps")
    parser.add_argument("--source", type=Path, help="Optional frozen source root containing game/ and notices")
    args = parser.parse_args()
    if args.source:
        executable = build.engine()
        build.ROOT = args.source.resolve()
        if not (build.ROOT / "game/project.godot").is_file():
            raise RuntimeError("Frozen source must contain game/project.godot")
        build.engine = lambda: executable
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    preset = build.ROOT / "game" / "export_presets.cfg"
    original = preset.read_bytes()
    local_filter = b'exclude_filter="assets/local_maps/*"'
    if original.count(local_filter) != 1:
        raise RuntimeError("Expected the default local-map exclusion in the Web preset")
    try:
        preset.write_bytes(original.replace(local_filter, b'exclude_filter=""', 1))
        _, _, template = select(build.ROOT)
        build.run("export-local-maps", ["--export-release", "Web", str(output / "index.html")], timeout=300)
    finally:
        preset.write_bytes(original)
    if preset.read_bytes() != original:
        raise RuntimeError("Default export preset was not restored")
    maps = sorted((build.ROOT / "game" / "assets" / "local_maps").glob("*.bfmap"))
    overlay = build.ROOT / "map-overlay.json"
    if overlay.exists():
        state = {"source_commit": json.loads(overlay.read_text(encoding="utf-8"))["base_commit"],
                 "source_dirty": True, "source_snapshot_sha256": hashlib.sha256(overlay.read_bytes()).hexdigest()}
    else:
        state = build.source_state()
    (output / "build-info.json").write_text(json.dumps({
        "engine": build.VERSION, "status": "local-map-inspection", "local_only": True,
        "maps": [path.name for path in maps], **state, **template,
        "inspection_source": str(build.ROOT),
    }, indent=2) + "\n", encoding="utf-8")
    shutil.copy2(build.ROOT / "LICENSE", output / "LICENSE.txt")
    shutil.copytree(build.ROOT / "game/assets/openspades/licenses", output / "notices", dirs_exist_ok=True)
    shutil.copytree(build.ROOT / "licenses", output / "notices/engine", dirs_exist_ok=True)
    fonts = build.ROOT / "game/assets/fonts/OFL.txt"
    if fonts.exists():
        (output / "notices/fonts").mkdir(parents=True, exist_ok=True)
        shutil.copy2(fonts, output / "notices/fonts/Inter-OFL.txt")
    print(f"Local map inspection build: {output}", flush=True)


if __name__ == "__main__":
    main()
