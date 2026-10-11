"""Freeze the map-conversion changes over HEAD for isolated local validation.

Unrelated concurrent gameplay edits stay in the shared workspace. The overlay
list deliberately names only this conversion's ownership; artifacts stay ignored.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

import build

OVERLAYS = [
    "game/main.gd", "game/ui/lab_hud.gd", "game/world/voxel_world.gd",
    "game/world/blockfield_map.gd", "game/world/blockfield_map.gd.uid",
    "game/export_presets.cfg", "tests/world/test_blockfield_map.gd",
    "tests/integration/test_native_map_main.gd", "tests/tools/test_goldsrc_import.py",
    "tools/bootstrap_blender.py", "tools/export_local_maps.py", "tools/render_local_map.gd",
    "tools/map_import/goldsrc.py", "tools/map_import/blender_scene.py",
    "tools/map_import/blender_voxelize.py", "tools/map_import/voxelize_helpers.py",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=build.ROOT / ".cache/mirage-inspection")
    args = parser.parse_args()
    target = args.output.resolve()
    target.mkdir(parents=True, exist_ok=False)
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=build.ROOT,
                              capture_output=True, text=True, check=True).stdout.strip()
    archive = target / "source.zip"
    subprocess.run(["git", "archive", "--format=zip", "--output=" + str(archive), revision],
                   cwd=build.ROOT, check=True)
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            if not (target / entry.filename).resolve().is_relative_to(target):
                raise ValueError("Unsafe source archive entry")
        source.extractall(target)
    hashes = {}
    for relative in OVERLAYS:
        source = build.ROOT / relative
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        hashes[relative] = hashlib.sha256(source.read_bytes()).hexdigest()
    maps = build.ROOT / "game/assets/local_maps"
    if maps.exists():
        shutil.copytree(maps, target / "game/assets/local_maps")
    imported = build.ROOT / "game/.godot/imported"
    if imported.exists():
        shutil.copytree(imported, target / "game/.godot/imported")
    (target / "map-overlay.json").write_text(json.dumps({
        "base_commit": revision, "overlay_sha256": hashes,
        "local_only": True, "excludes_unrelated_workspace_changes": True,
    }, indent=2) + "\n", encoding="utf-8")
    print(target, flush=True)


if __name__ == "__main__":
    main()
