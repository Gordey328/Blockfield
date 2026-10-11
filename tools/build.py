"""Reproducible Godot validation and web export (Python 3 standard library)."""
from __future__ import annotations
import argparse
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
    suites += [('protocol','tests/network/test_protocol.gd')]
    suites += [('ws-transport','tests/network/test_ws_transport.gd'),('shared-grenade','tests/network/test_grenade_rules.gd')]
    suites += [('voxel-data','tests/world/test_voxel_data.gd'),('voxel-adapter','tests/world/test_voxel_adapter.gd'),('player-rules','tests/network/test_player_rules.gd'),('match-objectives','tests/network/test_match_objectives.gd')]
    suites += [('match-simulation','tests/network/test_match_simulation.gd'),('client-prediction','tests/network/test_client_prediction.gd'),('map-transfer','tests/network/test_map_transfer.gd')]
    suites += [('session-registry','tests/network/test_session_registry.gd'),('input-queue','tests/network/test_input_queue.gd'),('server-runtime','tests/network/test_server_runtime.gd')]
    suites += [('simulation-codec','tests/network/test_simulation_codec.gd'),('client-replica','tests/network/test_client_replica.gd')]
    suites += [('events-codec','tests/network/test_events_codec.gd'),('hit-history','tests/network/test_hit_history.gd'),('match-rewind','tests/network/test_match_rewind.gd'),('events-delivery','tests/network/test_events_delivery.gd'),('network-session','tests/network/test_network_session.gd'),('network-controller','tests/network/test_network_controller.gd'),('network-identity','tests/ui/test_network_identity.gd'),('network-menu','tests/ui/test_network_menu.gd'),('weapon-simulation','tests/presentation/test_weapon_simulation.gd'),('network-adversarial','tests/network/test_network_adversarial.gd'),('match-reset','tests/network/test_match_reset.gd'),('epoch-reset-contract','tests/network/test_epoch_reset_contract.gd'),('runtime-epoch','tests/network/test_runtime_epoch.gd'),('network-scene','tests/network/test_network_scene.gd')]
    suites += [('dedicated-round','tests/network/test_dedicated_round.gd'),('server-book','tests/ui/test_server_book.gd')]
    suites += [('snapshot-fanout','tests/network/test_snapshot_fanout.gd'),('hit-volume-acceleration','tests/gameplay/test_hit_volume_acceleration.gd'),('network-scene-epoch','tests/network/test_network_scene_epoch.gd')]
    suites += [('world-preparation','tests/world/test_world_preparation.gd'),('long-reset','tests/network/test_long_reset.gd')]
    suites += [('offline-lifecycle','tests/integration/test_offline_lifecycle.gd')]
    suites += [('source-input','tests/integration/test_source_input.gd')]
    suites += [('camera-target-rays','tests/gameplay/test_camera_target_rays.gd')]
    suites += [('hottracked-player','tests/presentation/test_hottracked_player.gd')]
    suites += [('source-rays','tests/world/test_source_rays.gd'),('audio-environment','tests/audio/test_environment.gd'),('audio-environment-pcm','tests/audio/render_environment.gd')]
    suites += [('client-schedule','tests/network/test_client_schedule.gd')]
    suites += [('client-input-clock','tests/network/test_client_input_clock.gd')]
    suites += [('map-backpressure','tests/network/test_map_backpressure.gd')]
    suites += [('mobile-controls','tests/ui/test_mobile_controls.gd')]
    suites += [('mobile-look','tests/integration/test_mobile_look.gd')]
    suites += [('block-damage-visual','tests/world/test_block_damage_visual.gd')]
    suites += [('block-impact-optimization','tests/world/test_block_impact_optimization.gd'),('minimap-impact-upload','tests/ui/test_minimap_impact_upload.gd')]
    suites += [('impact-fragment-updates','tests/presentation/test_impact_fragment_updates.gd')]
    suites += [('impact-pcm','tests/audio/test_impact_pcm.gd')]
    suites += [('network-block-damage','tests/network/test_network_block_damage.gd')]
    suites += [('audio-optimization','tests/audio/test_audio_optimization.gd'),('vxl-jobs','tests/world/test_vxl_jobs.gd'),('model-cache-bounds','tests/presentation/test_model_cache_bounds.gd'),('vxl-main','tests/integration/test_vxl_main.gd')]
    suites += [('tdm-bots','tests/ai/test_tdm_bots.gd'),('offline-tdm','tests/session/test_offline_tdm.gd'),('offline-tdm-scene','tests/integration/test_offline_tdm_scene.gd')]
    suites += [('combat-hud','tests/ui/test_combat_hud.gd')]
    for name,path in suites:
        path=ROOT/path
        if path.exists():run('test-'+name,(['--fixed-fps','60'] if name in ('network-scene','network-scene-epoch','network-block-damage','offline-lifecycle','source-input','mobile-controls','mobile-look','offline-tdm-scene') else [])+['--script',str(path)],timeout=300)
    latency_report=ROOT/'.cache'/'benchmarks'/'network-latency.json'
    run_command('test-network-latency',[sys.executable,str(ROOT/'tools'/'latency_proxy.py'),
                '--godot',str(engine()),'--project',str(ROOT/'game'),'--report',str(latency_report)],timeout=50)
    latency_log=latency_report.with_suffix('.log').read_text(encoding='utf-8',errors='replace')
    if re.search(r'SCRIPT ERROR|Parse Error|^ERROR:|FAIL:',latency_log,re.MULTILINE):
        raise SystemExit('Network latency engine diagnostics failed; see '+str(latency_report.with_suffix('.log')))
    run('runtime-smoke',['--quit-after','120'])
    run('server-launcher-smoke',['--quit-after','60','--','--server','--game-port=0','--map-port=0'])
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
    (folder/'build-info.json').write_text(json.dumps({'engine':VERSION,'iteration':1,'status':'development','upstream':'dcf449c845d509bbde9d79239b32d201c1389961',**source_state(),**template_metadata},indent=2)+'\n',encoding='utf-8')
    shutil.copy2(ROOT/'LICENSE',folder/'LICENSE.txt')
    shutil.copytree(ROOT/'game'/'assets'/'openspades'/'licenses',folder/'notices',dirs_exist_ok=True)
    shutil.copytree(ROOT/'licenses',folder/'notices'/'engine',dirs_exist_ok=True)
    if (ROOT/'game'/'assets'/'fonts'/'OFL.txt').exists():
        (folder/'notices'/'fonts').mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/'game'/'assets'/'fonts'/'OFL.txt',folder/'notices'/'fonts'/'Inter-OFL.txt')
    print(f'Web build: {folder}',flush=True)

if __name__=='__main__':main()
