"""Prepare/export an isolated actual-Main probe for custom Web templates.

Use --prepare-only before obtaining the serial engine lease, then --resume to
import/export that exact private project. Neither operation touches game/ or
build/web. The pack contains byte-identical original assets, with attribution.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import zipfile

import build

ROOT = Path(__file__).resolve().parents[1]
ASSETS = {
    "head.glb": ("Models/Player/Head.kv6", "model", "models/Player/Head.glb"),
    "icon.png": ("Gfx/AlertIcon.png", "texture", "images/Gfx/AlertIcon.png"),
    "alert.ogg": ("Sounds/Feedback/Alert.opus", "sound", "sounds/Feedback/Alert.ogg"),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fixture_pack(source: Path) -> tuple[bytes, dict]:
    manifest = {"version": 1, "id": "web-template-original-fixture",
                "title": "Original bundled assets: Web template verification",
                "authors": ["OpenSpades authors; see bundled licenses"],
                "license": "Original bundled licenses apply; see assets/openspades/licenses",
                "assets": {}}
    payloads = {}
    for name, (virtual, kind, relative) in ASSETS.items():
        data = (source / "game/assets/openspades" / relative).read_bytes()
        payloads[name] = data
        manifest["assets"][virtual] = {"file": name, "type": kind,
                                            "sha256": hashlib.sha256(data).hexdigest()}
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
        for name, data in {"blockfield-pack.json": json.dumps(manifest).encode(), **payloads}.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            output.writestr(info, data)
    return archive.getvalue(), manifest


def prepare(source: Path, target: Path, fixture: Path, template: Path | None,
            import_cache: Path | None) -> None:
    if target.exists():
        raise SystemExit("Probe project already exists; use --resume or a new name")
    if not (source / "game/project.godot").is_file() or not fixture.is_file():
        raise SystemExit("Expected a frozen source project and a saved probe fixture")
    if (source / "game/__probe").exists():
        raise SystemExit("Source has a reserved __probe directory; preserve it and choose clean source")
    if import_cache is not None and not import_cache.is_dir():
        raise SystemExit("Import cache does not exist")
    # Validate payloads/configuration before creating any copied project.
    pack_bytes, manifest = fixture_pack(source)
    config = (source / "game/project.godot").read_text(encoding="utf-8")
    config, count = re.subn(r'run/main_scene="[^"]+"',
                           'run/main_scene="res://__probe/template.tscn"', config)
    if count != 1:
        raise SystemExit("Expected exactly one configured entry scene")
    config = re.sub(r'^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n',
                    '', config, flags=re.MULTILINE)
    config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\n'
                            f'config/custom_user_dir_name="blockfield-{target.name}"', 1)
    presets = (source / "game/export_presets.cfg").read_text(encoding="utf-8")
    preset_header = re.search(r'(?ms)^\[preset\.0\]\n.*?(?=^\[)', presets)
    options = re.search(r'(?ms)^\[preset\.0.options\]\n.*?(?=^\[|\Z)', presets)
    if not preset_header or not options or 'name="Web"' not in preset_header[0]:
        raise SystemExit("Expected Web preset 0 with its options")
    header, count = re.subn(r'^include_filter="([^"]*)"',
                           lambda match: f'include_filter="{match[1]},*.bin,*.zip"',
                           preset_header[0], flags=re.MULTILINE)
    if count != 1:
        raise SystemExit("Expected one Web include filter")
    option_text = options[0]
    if template is not None:
        option_text, count = re.subn(r'^custom_template/release="[^"]*"',
                                    'custom_template/release="' + template.as_posix() + '"',
                                    option_text, flags=re.MULTILINE)
        if count != 1:
            raise SystemExit("Expected one Web release-template option")
    presets = presets[:options.start()] + option_text + presets[options.end():]
    presets = presets[:preset_header.start()] + header + presets[preset_header.end():]
    shutil.copytree(source / "game", target / "game", ignore=shutil.ignore_patterns(".godot"))
    if import_cache is not None:
        shutil.copytree(import_cache, target / "game/.godot",
                        ignore=shutil.ignore_patterns("editor", "shader_cache"))
    probe = target / "game/__probe"
    probe.mkdir()
    shutil.copy2(fixture, probe / "template.gd")
    shutil.copy2(source / "game/assets/openspades/models/Player/Head.glb", probe / "head.glb.bin")
    (probe / "original-pack.zip").write_bytes(pack_bytes)
    (probe / "template.tscn").write_text(
        '[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://__probe/template.gd" id="1"]\n'
        '[node name="TemplateProbe" type="Node"]\nscript=ExtResource("1")\n', encoding="utf-8")
    (target / "game/project.godot").write_text(config, encoding="utf-8")
    (target / "game/export_presets.cfg").write_text(presets, encoding="utf-8")
    identity = {"source": str(source), "fixture_sha256": sha256(fixture),
                "template": str(template) if template else "source-preset",
                "template_sha256": sha256(template) if template else None,
                "pack_sha256": hashlib.sha256(pack_bytes).hexdigest(), "pack_manifest": manifest,
                "production_entry_sha256": sha256(source / "game/project.godot"),
                "scripts": {str(path.relative_to(source / "game")): sha256(path)
                            for path in (source / "game").rglob("*.gd") if ".godot" not in path.parts}}
    (target / "identity.json").write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--fixture", type=Path, default=ROOT / "tests/browser/template_probe.gd")
    parser.add_argument("--template", type=Path)
    parser.add_argument("--engine", type=Path)
    parser.add_argument("--import-cache", type=Path)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9-]+", args.name):
        raise SystemExit("Name must use lowercase letters, digits and hyphens")
    source, fixture = args.source.resolve(), args.fixture.resolve()
    target = ROOT / ".cache" / ("template-probe-" + args.name)
    template = args.template.resolve() if args.template else None
    if template is not None and not template.is_file():
        raise SystemExit("Custom template does not exist")
    if args.resume:
        if not (target / "identity.json").is_file():
            raise SystemExit("No prepared probe; omit --resume first")
        identity = json.loads((target / "identity.json").read_text(encoding="utf-8"))
        if identity["source"] != str(source) or identity["fixture_sha256"] != sha256(fixture):
            raise SystemExit("Prepared probe source/fixture differs; preserve evidence and use a new name")
        if template is not None and identity["template_sha256"] != sha256(template):
            raise SystemExit("Prepared template differs; preserve evidence and use a new name")
    else:
        prepare(source, target, fixture, template, args.import_cache.resolve() if args.import_cache else None)
    print("Private probe project: " + str(target / "game"), flush=True)
    if args.prepare_only:
        return
    output = target / "build/web"
    if (output / "index.html").exists():
        raise SystemExit("Probe export already exists; preserve browser evidence and use a new name")
    engine = args.engine.resolve() if args.engine else build.engine()
    if not engine.is_file():
        raise SystemExit("Exporting engine does not exist")
    build.ROOT = target
    build.engine = lambda: engine
    build.run("template-probe-import", ["--editor", "--import", "--quit"], timeout=300)
    output.mkdir(parents=True, exist_ok=True)
    build.run("template-probe-export", ["--export-release", "Web", str(output / "index.html")], timeout=300)
    print("Test-only Web export: " + str(output), flush=True)


if __name__ == "__main__":
    main()
