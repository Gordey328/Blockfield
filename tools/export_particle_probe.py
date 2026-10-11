"""Export an isolated rendered particle benchmark from an immutable source."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

import build

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Immutable checkout containing game/")
    parser.add_argument("--name", required=True)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--import-cache", type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", args.name):
        raise SystemExit("Name must use 1..64 lowercase letters, digits and hyphens")
    source = args.source.resolve()
    if not (source / "game/project.godot").is_file():
        raise SystemExit("Source must contain game/project.godot")
    if args.godot and (not args.godot.is_absolute() or not args.godot.is_file()):
        raise SystemExit("--godot must be an existing absolute engine executable")
    if args.import_cache and not args.import_cache.is_dir():
        raise SystemExit("--import-cache must be an existing .godot directory")
    target = ROOT / ".cache" / ("particle50-probe-" + args.name)
    if target.exists():
        raise SystemExit("Preserve existing diagnostic: choose a new --name")
    engine = args.godot.resolve() if args.godot else build.engine().resolve()
    shutil.copytree(source / "game", target / "game", ignore=shutil.ignore_patterns(".godot"))
    if args.import_cache:
        imported = args.import_cache.resolve() / "imported"
        if imported.is_dir():
            shutil.copytree(imported, target / "game/.godot/imported")
    probe = target / "game/__probe"
    probe.mkdir()
    shutil.copy2(ROOT / "tests/browser/particle_budget_probe.gd", probe / "particles.gd")
    shutil.copy2(ROOT / "tests/presentation/benchmark_particle_budget.gd", probe / "benchmark_particle_budget.gd")
    (probe / "particles.tscn").write_text(
        '[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://__probe/particles.gd" id="1"]\n'
        '[node name="ParticleBudgetProbe" type="Node"]\nscript=ExtResource("1")\n', encoding="utf-8"
    )
    config = target / "game/project.godot"
    text, replacements = re.subn(
        r'(?m)^run/main_scene="[^"]+"$', 'run/main_scene="res://__probe/particles.tscn"',
        config.read_text(encoding="utf-8")
    )
    if replacements != 1:
        raise SystemExit("Expected exactly one main_scene; diagnostic preserved")
    text = re.sub(r"(?m)^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n?", "", text)
    text = text.replace("[application]", '[application]\nconfig/use_custom_user_dir=true\n'
                        f'config/custom_user_dir_name="blockfield-particle-probe-{args.name}"', 1)
    config.write_text(text, encoding="utf-8")
    identity = {"source": str(source), "engine": str(engine), "kind": "isolated-particle-web-probe",
                "sha256": {name: hashlib.sha256((target / "game" / name).read_bytes()).hexdigest()
                           for name in ["presentation/openspades_effects.gd", "__probe/particles.gd",
                                        "__probe/benchmark_particle_budget.gd"]}}
    build.ROOT = target
    build.engine = lambda: engine
    build.run("import", ["--editor", "--import", "--quit"])
    folder = target / "build/web"
    folder.mkdir(parents=True)
    from web_release_template import select
    preset, original, template_metadata = select(target)
    try:
        build.run("export", ["--export-release", "Web", str(folder / "index.html")])
    finally:
        preset.write_bytes(original)
    identity.update(template_metadata)
    (target / "identity.json").write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")
    (folder / "build-info.json").write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")
    (folder / ".nojekyll").write_text("", encoding="utf-8")
    print(folder, flush=True)


if __name__ == "__main__":
    main()
