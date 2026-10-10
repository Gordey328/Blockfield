"""Generate/export a tiny isolated browser GPU probe using the production HDR code.

Usage: python tests/presentation/export_hdr_probe.py --godot PATH
Open .cache/hdr-web-probe/build/index.html via an HTTP server. The page exposes
window.hdrProbeResult and a visible JSON <pre>; zero failures is required.
"""
from pathlib import Path
import argparse
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FILES = ["hdr_exposure.gd", "hdr_scene_viewport.gd", "hdr_reduce.gdshader",
         "hdr_gain.gdshader", "hdr_present.gdshader", "hdr_bloom.gd",
         "hdr_bloom.gdshader", "hdr_composite.gdshaderinc"]


def prepare() -> Path:
    project = ROOT / ".cache/hdr-web-probe"
    (project / "presentation").mkdir(parents=True, exist_ok=True)
    (project / "build").mkdir(exist_ok=True)
    (project / "build/.gdignore").write_text("")
    for name in FILES:
        (project / "presentation" / name).write_bytes(
            (ROOT / "game/presentation" / name).read_bytes())
    probe = (ROOT / "tests/presentation/render_hdr_exposure.gd").read_text()
    probe = probe.replace("extends SceneTree", "extends Node\n@onready var root: Viewport = get_tree().root")
    probe = probe.replace("func _initialize()", "func _ready()")
    probe = probe.replace("await process_frame", "await get_tree().process_frame")
    probe = probe.replace("quit(1)", "get_tree().quit(1)")
    probe = probe.replace('DirAccess.make_dir_recursive_absolute(output)', "pass # Browser probe does not write evidence files.")
    probe = "\n".join(line for line in probe.splitlines()
                      if ".save_png(" not in line and "FileAccess.open(" not in line)
    probe = probe.replace("quit(1 if failures else 0)", '''if OS.has_feature("web"):
        var result: String = JSON.stringify(metrics)
        var report: String = "var r="+result+";var c=document.getElementById('canvas');var g=c?c.getContext('webgl2'):null;r.float_color_buffer=!!(g&&g.getExtension('EXT_color_buffer_float'));var p=document.createElement('pre');p.id='hdr-probe-results';p.style='position:absolute;top:0;left:0;background:white;color:black;z-index:10000;white-space:pre-wrap;max-width:100vw';p.textContent=JSON.stringify(r,null,2);document.body.appendChild(p);window.hdrProbeResult=r;"
        JavaScriptBridge.eval(report,true)
    else:
        get_tree().quit(1 if failures else 0)'''.replace("    ", "\t"))
    (project / "probe.gd").write_text(probe, newline="\n")
    (project / "main.tscn").write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://probe.gd" id="1"]
[node name="HdrProbe" type="Node"]
script = ExtResource("1")
''')
    (project / "project.godot").write_text('''config_version=5
[application]
config/name="Blockfield HDR WebGL proof"
run/main_scene="res://main.tscn"
[display]
window/size/viewport_width=512
window/size/viewport_height=384
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
''')
    preset = (ROOT / "game/export_presets.cfg").read_text()
    preset = preset.replace('export_path="../build/web/index.html"', 'export_path="build/index.html"')
    (project / "export_presets.cfg").write_text(preset)
    return project


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    target = prepare()
    subprocess.run([args.godot, "--headless", "--path", str(target), "--editor", "--import"], check=True)
    subprocess.run([args.godot, "--headless", "--path", str(target), "--export-release", "Web",
                    str(target / "build/index.html")], check=True)
    print(target / "build/index.html")
