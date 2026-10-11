"""Export an isolated genuine-Main mobile Web probe without shared imports/builds."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

import build

ROOT = Path(__file__).resolve().parents[1]

PREVIEW_HTML = """<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Blockfield isolated mobile input probe</title>
<style>body{margin:12px;background:#07121c;color:#dfedf5;font:14px system-ui}button{padding:10px;margin:0 8px 10px 0}iframe{display:block;border:1px solid #456;background:#101e29}pre{white-space:pre-wrap;max-width:1000px;max-height:420px;overflow:auto;padding:10px;background:#101e29}h1{font-size:20px;margin:4px 0 10px}</style>
<h1>Actual Godot Web mobile input probe</h1>
<p>Use Run DOM touch checks inside the game. Authored browser events cross the JS/WASM boundary; physical-phone comfort remains untested.</p>
<button data-size="844,390">Landscape844x390</button>
<button data-size="390,844">Portrait390x844</button>
<button data-size="568,320">Small568x320</button>
<button data-size="1280,720">Desktop1280x720</button>
<span id="preview-size">Iframe844x390</span>
<iframe id="game" title="Actual Blockfield mobile test scene" src="index.html" width="844" height="390" allow="autoplay; fullscreen; gamepad"></iframe>
<h2>DOM-backed mobile check results</h2>
<pre id="mobile-probe-results">Waiting for genuine Main readiness...</pre>
<script>
const game=document.getElementById('game');
document.querySelectorAll('button[data-size]').forEach(button=>button.addEventListener('click',()=>{
 const [width,height]=button.dataset.size.split(',').map(Number);
 game.width=width;game.height=height;
 document.getElementById('preview-size').textContent='Iframe'+width+'x'+height;
}));
window.addEventListener('message',event=>{
 if(event.origin!==window.location.origin||event.source!==game.contentWindow||event.data?.type!=='blockfield-mobile-probe')return;
 document.getElementById('mobile-probe-results').textContent=JSON.stringify(event.data.report,null,2);
});
</script></html>
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Checkout containing game/")
    parser.add_argument("--name", required=True, help="Unique lowercase diagnostic name")
    parser.add_argument("--godot", type=Path, help="Optional absolute engine executable")
    parser.add_argument("--import-cache", type=Path, help="Existing .godot directory; copied before normal editor import")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", args.name):
        raise SystemExit("Name must use 1..64 lowercase letters, digits and hyphens")
    source = args.source.resolve()
    if not (source / "game" / "project.godot").is_file():
        raise SystemExit("Source must contain game/project.godot")
    if args.godot and (not args.godot.is_absolute() or not args.godot.is_file()):
        raise SystemExit("--godot must be an existing absolute engine executable")
    if args.import_cache and not args.import_cache.is_dir():
        raise SystemExit("--import-cache must be an existing .godot directory")
    target = ROOT / ".cache" / ("mobile-probe-" + args.name)
    if target.exists():
        raise SystemExit("Preserve existing diagnostic: choose a new --name")
    engine = args.godot.resolve() if args.godot else build.engine().resolve()
    shutil.copytree(source / "game", target / "game", ignore=shutil.ignore_patterns(".godot"))
    if args.import_cache:
        # Reuse imported assets only. A different diagnostic's script UID/editor
        # caches describe its generated scene and must not leak into this one.
        imported = args.import_cache.resolve() / "imported"
        if imported.is_dir():
            shutil.copytree(imported, target / "game" / ".godot" / "imported")
    probe = target / "game" / "__probe"
    probe.mkdir()
    shutil.copy2(ROOT / "tests" / "browser" / "mobile_probe.gd", probe / "mobile.gd")
    (probe / "mobile.tscn").write_text(
        '[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://__probe/mobile.gd" id="1"]\n'
        '[node name="MobileProbe" type="Node"]\nscript=ExtResource("1")\n',
        encoding="utf-8",
    )
    config = target / "game" / "project.godot"
    text = config.read_text(encoding="utf-8")
    text, replacements = re.subn(r'(?m)^run/main_scene="[^"]+"$', 'run/main_scene="res://__probe/mobile.tscn"', text)
    if replacements != 1:
        raise SystemExit("Expected exactly one existing main_scene; diagnostic preserved")
    # Native validation can already have isolated userdata. Replace those keys
    # in this copied project instead of inserting duplicate application entries.
    text = re.sub(r"(?m)^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n?", "", text)
    text = text.replace(
        "[application]", '[application]\nconfig/use_custom_user_dir=true\n'
        f'config/custom_user_dir_name="blockfield-mobile-probe-{args.name}"', 1,
    )
    config.write_text(text, encoding="utf-8")
    files = ["ui/mobile_controls.gd", "ui/lab_hud.gd", "gameplay/player_controller.gd", "__probe/mobile.gd"]
    if (target / "game/gameplay/touch_aim_assist.gd").is_file():
        files.append("gameplay/touch_aim_assist.gd")
    identity = {
        "source": str(source), "engine": str(engine), "kind": "test-only-mobile-web-probe",
        "physical_phone_tested": False,
        "sha256": {name: hashlib.sha256((target / "game" / name).read_bytes()).hexdigest() for name in files},
    }
    build.ROOT = target
    build.engine = lambda: engine
    build.run("import", ["--editor", "--import", "--quit"])
    folder = target / "build" / "web"
    folder.mkdir(parents=True)
    from web_release_template import select
    preset, original, template_metadata = select(target)
    try:
        build.run("export", ["--export-release", "Web", str(folder / "index.html")])
    finally:
        preset.write_bytes(original)
    identity.update(template_metadata)
    (target / "identity.json").write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")
    (folder / ".nojekyll").write_text("", encoding="utf-8")
    (folder / "build-info.json").write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")
    (folder / "preview.html").write_text(PREVIEW_HTML, encoding="utf-8")
    print(folder, flush=True)


if __name__ == "__main__":
    main()
