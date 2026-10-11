"""Export the actual offline TDM scene with a separate diagnostic Web overlay.

Production game bytes come from an existing frozen release archive; this helper
only changes its copied entry scene and private user directory. It never writes
to build/web or the Pages checkout.
"""
from pathlib import Path
import argparse
import hashlib
import re
import shutil

import build

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", required=True, type=Path)
    parser.add_argument("--fixture", type=Path, help="Explicit test-only fixture override")
    args = parser.parse_args()
    source = args.release.resolve()
    if source.parent != ROOT / ".cache" or not source.name.startswith("release-"):
        raise SystemExit("Expected an existing frozen .cache/release-* archive")
    if not (source / "game" / "scenes" / "offline_tdm.tscn").is_file():
        raise SystemExit("Frozen archive does not contain the offline TDM scene")
    fixture = args.fixture.resolve() if args.fixture else source / "tests" / "browser" / "offline_tdm_probe.gd"
    if not fixture.is_file():
        raise SystemExit("Offline TDM diagnostic fixture does not exist")
    destination = ROOT / ".cache" / ("web-offline-tdm-" + source.name.removeprefix("release-"))
    if destination.exists():
        raise SystemExit("Probe archive already exists; preserve previous evidence")
    shutil.copytree(source / "game", destination / "game", ignore=shutil.ignore_patterns(".godot"))
    probe = destination / "game" / "__probe"
    probe.mkdir()
    shutil.copy2(fixture, probe / "offline_tdm.gd")
    print("Fixture SHA256: " + hashlib.sha256(fixture.read_bytes()).hexdigest(), flush=True)
    (probe / "offline_tdm.tscn").write_text(
        '[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://__probe/offline_tdm.gd" id="1"]\n'
        '[node name="OfflineTDMProbe" type="Node"]\n'
        'script=ExtResource("1")\n', encoding="utf-8"
    )
    config = destination / "game" / "project.godot"
    text = config.read_text(encoding="utf-8")
    text, count = re.subn(r'run/main_scene="[^"]+"', 'run/main_scene="res://__probe/offline_tdm.tscn"', text)
    if count != 1:
        raise SystemExit("Expected one entry scene")
    text = text.replace(
        "[application]", '[application]\nconfig/use_custom_user_dir=true\n'
        'config/custom_user_dir_name="blockfield-offline-tdm-probe"', 1
    )
    config.write_text(text, encoding="utf-8")
    engine = build.engine()
    build.ROOT = destination
    build.engine = lambda: engine
    build.run("offline-tdm-probe-import", ["--editor", "--import", "--quit"])
    output = destination / "build" / "web"
    output.mkdir(parents=True)
    build.run("offline-tdm-probe-export", ["--export-release", "Web", str(output / "index.html")])
    print("Test-only Web export: " + str(output), flush=True)


if __name__ == "__main__":
    main()
