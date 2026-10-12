"""Reproducible Godot validation and web export (Python 3 standard library)."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
from bootstrap import VERSION, main as bootstrap

ROOT=Path(__file__).resolve().parents[1]

def source_state():
    revision=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,capture_output=True,text=True,check=True).stdout.strip()
    dirty=subprocess.run(['git','status','--porcelain'],cwd=ROOT,capture_output=True,text=True,check=True).stdout.strip()
    return {'source_commit':revision,'source_dirty':bool(dirty)}

def engine():
    suffix='win64_console.exe' if sys.platform=='win32' else 'linux.x86_64'
    path=ROOT/'.tools'/'godot'/f'Godot_v{VERSION}-stable_{suffix}'
    if not path.exists(): bootstrap()
    return path

def run(name, args, timeout=180):
    command=[str(engine()),'--headless','--path',str(ROOT/'game'),*args]
    return run_command(name, command, timeout)

def run_command(name, command, timeout=180):
    with subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                          text=True,encoding='utf-8',errors='replace') as process:
        try:
            stdout,stderr=process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as failure:
            # The Windows console launcher owns a GUI-binary child even when
            # headless. Kill this exact invocation's tree before its parent;
            # otherwise a timeout leaves the actual engine running forever.
            if sys.platform=='win32':
                subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],
                               stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            else:
                process.kill()
            stdout,stderr=process.communicate()
            output=stdout+'\n'+stderr
            folder=ROOT/'.cache'/'logs'; folder.mkdir(parents=True,exist_ok=True)
            (folder/(name+'.log')).write_text(output,encoding='utf-8')
            print('\n'.join(output.splitlines()[-30:]),flush=True)
            raise SystemExit(f'{name} timed out after {timeout}s; see .cache/logs/{name}.log') from failure
        result=subprocess.CompletedProcess(command,process.returncode,stdout,stderr)
    output=result.stdout+'\n'+result.stderr
    folder=ROOT/'.cache'/'logs'; folder.mkdir(parents=True,exist_ok=True)
    (folder/(name+'.log')).write_text(output,encoding='utf-8')
    errors=[line for line in output.splitlines() if re.search(r'SCRIPT ERROR|Parse Error|^ERROR:|FAIL:',line)]
    if result.returncode or errors:
        print('\n'.join(errors or output.splitlines()[-20:]))
        raise SystemExit(f'{name} failed; see .cache/logs/{name}.log')
    summaries=[line for line in output.splitlines() if re.search(r'assertions|checks|PASS|failures',line,re.I)]
    print(name+': OK'+(' — '+'; '.join(summaries) if summaries else ''),flush=True)
    return output

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--export',action='store_true')
    args=parser.parse_args()
    run('import',['--editor','--import','--quit'])
    for label in ('world','session','integration'):
        path=ROOT/'tests'/label/f'test_{"lab" if label=="integration" else label}.gd'
        if path.exists():run('test-'+label,(['--fixed-fps','60'] if label=='integration' else [])+['--script',str(path)])
    suites=[('grenade','tests/gameplay/test_grenade.gd'),('vxl-save','tests/world/test_vxl_save.gd'),('falling-clusters','tests/world/test_falling_clusters.gd'),('lighting','tests/world/test_lighting.gd'),('topdown','tests/world/test_topdown.gd'),('presentation','tests/presentation/test_presentation.gd'),('localization','tests/presentation/test_localization.gd'),('effects','tests/presentation/test_effects.gd'),('post-effects','tests/presentation/test_post_effects.gd'),('extensions','tests/presentation/test_extensions.gd'),('ui','tests/ui/test_ui.gd')]
    suites += [('focus','tests/gameplay/test_focus.gd'),('source-parity','tests/gameplay/test_source_parity.gd'),('character-actions','tests/presentation/test_character_actions.gd'),('corpse','tests/presentation/test_corpse.gd'),('weapon-native','tests/presentation/test_weapon_native.gd'),('water','tests/world/test_water.gd'),('irradiance','tests/world/test_irradiance.gd'),('world-resources','tests/world/test_world_resources.gd'),('audio','tests/audio/test_audio.gd')]
    suites += [('source-motion','tests/gameplay/test_source_motion.gd'),('spectator-view','tests/presentation/test_spectator_view.gd'),('reflection','tests/world/test_reflection.gd')]
    suites += [('console','tests/ui/test_console.gd'),('camera-effects','tests/presentation/test_camera_effects.gd')]
    suites += [('hdr-exposure','tests/presentation/test_hdr_exposure.gd'),('audio-pcm','tests/audio/render_audio.gd')]
    suites += [('voxel-data','tests/world/test_voxel_data.gd'),('voxel-adapter','tests/world/test_voxel_adapter.gd')]
    suites += [('weapon-simulation','tests/presentation/test_weapon_simulation.gd')]
    suites += [('hit-volume-acceleration','tests/gameplay/test_hit_volume_acceleration.gd')]
    suites += [('world-preparation','tests/world/test_world_preparation.gd')]
    suites += [('offline-lifecycle','tests/integration/test_offline_lifecycle.gd')]
    suites += [('source-input','tests/integration/test_source_input.gd')]
    suites += [('camera-target-rays','tests/gameplay/test_camera_target_rays.gd')]
    suites += [('hottracked-player','tests/presentation/test_hottracked_player.gd')]
    suites += [('source-rays','tests/world/test_source_rays.gd'),('audio-environment','tests/audio/test_environment.gd'),('audio-environment-pcm','tests/audio/render_environment.gd')]
    suites += [('mobile-controls','tests/ui/test_mobile_controls.gd')]
    suites += [('mobile-look','tests/integration/test_mobile_look.gd')]
    suites += [('mobile-aim-assist','tests/integration/test_mobile_aim_assist.gd')]
    suites += [('block-damage-visual','tests/world/test_block_damage_visual.gd')]
    suites += [('block-impact-optimization','tests/world/test_block_impact_optimization.gd'),('minimap-impact-upload','tests/ui/test_minimap_impact_upload.gd')]
    suites += [('impact-fragment-updates','tests/presentation/test_impact_fragment_updates.gd')]
    suites += [('impact-pcm','tests/audio/test_impact_pcm.gd')]
    suites += [('audio-optimization','tests/audio/test_audio_optimization.gd'),('vxl-jobs','tests/world/test_vxl_jobs.gd'),('model-cache-bounds','tests/presentation/test_model_cache_bounds.gd'),('vxl-main','tests/integration/test_vxl_main.gd')]
    suites += [('tdm-bots','tests/ai/test_tdm_bots.gd'),('offline-tdm','tests/session/test_offline_tdm.gd'),('offline-tdm-scene','tests/integration/test_offline_tdm_scene.gd')]
    suites += [('combat-hud','tests/ui/test_combat_hud.gd')]
    suites += [('game-shell','tests/ui/test_game_shell.gd'),('game-launch','tests/integration/test_game_launch.gd')]
    suites += [('blockfield-map','tests/world/test_blockfield_map.gd'),('native-map-main','tests/integration/test_native_map_main.gd')]
    suites += [('collapse-optimization','tests/world/test_collapse_optimization.gd'),
               ('empty-chunk-optimization','tests/world/test_empty_chunk_optimization.gd'),
               ('live-shot-acceleration','tests/gameplay/test_live_shot_acceleration.gd'),
               ('presentation-optimization','tests/presentation/test_presentation_optimization.gd'),
               ('corpse-optimization','tests/presentation/test_corpse_optimization.gd'),
               ('corpse-static','tests/presentation/test_static_corpse.gd'),
               ('tdm-weapon-readout-optimization','tests/gameplay/test_tdm_weapon_readout_optimization.gd'),
               ('player-state-copy-optimization','tests/gameplay/test_player_state_copy_optimization.gd'),
               ('world-dirty-optimization','tests/world/test_world_dirty_optimization.gd'),
               ('main-optimization','tests/integration/test_main_optimization.gd')]
    suites += [('shared-grenade','tests/simulation/test_grenade_rules.gd'),('player-rules','tests/simulation/test_player_rules.gd'),('match-objectives','tests/simulation/test_match_objectives.gd'),('match-simulation','tests/simulation/test_match_simulation.gd'),('match-reset','tests/simulation/test_match_reset.gd'),('actor-presentation','tests/ui/test_actor_presentation.gd')]
    for name,path in suites:
        path=ROOT/path
        if path.exists():run('test-'+name,(['--fixed-fps','60'] if name in ('ui','game-shell','game-launch','offline-lifecycle','source-input','mobile-controls','mobile-look','mobile-aim-assist','offline-tdm-scene','native-map-main') else [])+['--script',str(path)],timeout=300)
    run('runtime-smoke',['--quit-after','120'])
    if args.export: export_web()

def export_web():
    folder=ROOT/'build'/'web';folder.mkdir(parents=True,exist_ok=True)
    from web_release_template import select
    preset, original, template_metadata = select(ROOT)
    try:
        run('export',['--export-release','Web',str(folder/'index.html')])
    finally:
        preset.write_bytes(original)
    (folder/'.nojekyll').write_text('')
    maps=[]
    map_source=ROOT/'game'/'assets'/'maps'
    if map_source.is_dir():
        (folder/'maps').mkdir(parents=True,exist_ok=True)
        for path in sorted(map_source.iterdir()):
            if path.is_file() and path.suffix.lower() in ('.bfmap','.md'):
                shutil.copy2(path,folder/'maps'/path.name)
                if path.suffix.lower()=='.bfmap':
                    maps.append({'path':'maps/'+path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    (folder/'build-info.json').write_text(json.dumps({'engine':VERSION,'iteration':1,'status':'development','upstream':'dcf449c845d509bbde9d79239b32d201c1389961','bundled_maps':maps,**source_state(),**template_metadata},indent=2)+'\n',encoding='utf-8')
    shutil.copy2(ROOT/'LICENSE',folder/'LICENSE.txt')
    shutil.copytree(ROOT/'game'/'assets'/'openspades'/'licenses',folder/'notices',dirs_exist_ok=True)
    shutil.copytree(ROOT/'licenses',folder/'notices'/'engine',dirs_exist_ok=True)
    if (ROOT/'game'/'assets'/'fonts'/'OFL.txt').exists():
        (folder/'notices'/'fonts').mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/'game'/'assets'/'fonts'/'OFL.txt',folder/'notices'/'fonts'/'Inter-OFL.txt')
    print(f'Web build: {folder}',flush=True)

if __name__=='__main__':main()
