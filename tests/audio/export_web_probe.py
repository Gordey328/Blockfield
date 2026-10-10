"""Export the actual audio service/PCM fixture as a gesture-started Web probe.

This is isolated from Main and preferences. Only the unused terrain type is a
stub; production audio, resource loading, voices and the mixer remain real.
"""
from pathlib import Path
import argparse
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[2]

def prepare(environment=False):
    project=ROOT/('.cache/audio-environment-web-probe' if environment else '.cache/audio-web-probe')
    (project/'audio').mkdir(parents=True,exist_ok=True)
    (project/'presentation').mkdir(exist_ok=True)
    (project/'world').mkdir(exist_ok=True)
    (project/'build').mkdir(exist_ok=True)
    (project/'build/.gdignore').write_text('')
    for name in ('audio/openspades_audio.gd','audio/audio_environment.gd','world/voxel_data.gd','world/vxl_reader.gd','presentation/openspades_extensions.gd'):
        shutil.copy2(ROOT/'game'/name,project/name)
    shutil.copytree(ROOT/'game/assets/openspades/sounds',project/'assets/openspades/sounds',dirs_exist_ok=True)
    shutil.copy2(ROOT/'game/assets/openspades/manifest.json',project/'assets/openspades/manifest.json')
    (project/'terrain_type.gd').write_text('''class_name VoxelWorld
extends Node3D
var data: VoxelData = VoxelData.new()
func cast_voxel(_origin: Vector3,_direction: Vector3,_distance: float)->Dictionary:
    assert(false,"The isolated PCM fixture must not query terrain")
    return {}
''')
    source=(ROOT/'tests/audio'/('render_environment.gd' if environment else 'render_audio.gd')).read_text(encoding='utf-8')
    source=source.replace('preload("res://world/voxel_world.gd")','preload("res://terrain_type.gd")')
    source=source.replace('extends SceneTree','extends Node\n@onready var root: Viewport = get_tree().root')
    start=source.index('func _initialize()')
    end=source.index('func check(',start)
    source=source[:start]+'''func _ready() -> void:
    var button := Button.new()
    button.text = "Run browser PCM proof"
    button.position = Vector2(24,24)
    button.size = Vector2(350,60)
    add_child(button)
    button.pressed.connect(func():button.disabled=true;_run())

'''.replace('    ','\t')+source[end:]
    source=source.replace('await process_frame','await get_tree().process_frame')
    source=source.replace('create_timer(', 'get_tree().create_timer(')
    source=source.replace('DirAccess.make_dir_recursive_absolute(output)','pass # No browser artifact writes.')
    start=source.index('\tvar file:=FileAccess.open(' if environment else '\tvar json := FileAccess.open(')
    end=source.index('\taudio.stop();world.free()' if environment else '\tawait finish()',start)
    source=source[:start]+'''\treport.playback = "STREAM"
\treport.erase("wav_format")
\treport.capture_format = "Godot mixer stereo float32; no browser WAV writes"
\treport.preferences = "untouched"
\treport.browser_listening_verified = false
\tvar report_text := JSON.stringify(report)
\tJavaScriptBridge.eval("var r="+report_text+";var p=document.createElement('pre');p.id='audio-probe-results';p.style='position:absolute;top:0;left:0;background:white;color:black;z-index:10000;white-space:pre-wrap';p.textContent=JSON.stringify(r,null,2);document.body.appendChild(p);",true)
'''+source[end:]
    if environment:
        source='\n'.join(line for line in source.split('\n') if 'check(write_wav(' not in line)
        start=source.index('func write_wav(')
        source=source[:start]
    else:
        start=source.index('\tif not frames.is_empty():')
        end=source.index('\tresults.append(metrics)',start)
        source=source[:start]+source[end:]
        start=source.index('func write_wav(')
        end=source.index('func finish()',start)
        source=source[:start]+source[end:]
    source=source.replace('quit(1 if failures else 0)','if not OS.has_feature("web"): get_tree().quit(1 if failures else 0)')
    (project/'probe.gd').write_text(source,encoding='utf-8',newline='\n')
    (project/'main.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://probe.gd" id="1"]
[node name="AudioProbe" type="Node"]
script = ExtResource("1")
''')
    (project/'project.godot').write_text('''config_version=5
[application]
config/name="Blockfield browser audio proof"
run/main_scene="res://main.tscn"
[display]
window/size/viewport_width=640
window/size/viewport_height=360
[rendering]
renderer/rendering_method="gl_compatibility"
[audio]
driver/enable_input=false
''')
    preset=(ROOT/'game/export_presets.cfg').read_text(encoding='utf-8')
    (project/'export_presets.cfg').write_text(preset.replace('export_path="../build/web/index.html"','export_path="build/index.html"'),encoding='utf-8')
    return project

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--godot',required=True)
    parser.add_argument('--environment',action='store_true',help='Probe production obstruction/reverb/limiting with deterministic PCM signals')
    args=parser.parse_args()
    project=prepare(args.environment)
    # Allow a few idle editor frames after imports before resource teardown.
    subprocess.run([args.godot,'--headless','--path',str(project),'--editor','--import','--quit-after','3'],check=True)
    subprocess.run([args.godot,'--headless','--path',str(project),'--export-release','Web',str(project/'build/index.html')],check=True)
    print(project/'build/index.html',flush=True)
