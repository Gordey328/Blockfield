"""Export identical actual-Main CPU diagnostics from baseline/candidate sources."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

import build
from export_block_impact_probe import instrument
from web_release_template import select

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    'main.gd': ('_process', '_update_graphics'),
    'presentation/character_view.gd': ('_apply_pose',),
    'presentation/corpse.gd': ('step',),
    'gameplay/lab_soldier.gd': ('_process',),
    'ui/lab_hud.gd': ('_process',),
    'ui/lab_palette.gd': ('_process',),
    'ui/lab_map.gd': ('_draw',),
    'world/voxel_world.gd': ('_process', 'process_rebuild_work'),
    'gameplay/player_controller.gd': ('_physics_process', '_shoot'),
    'gameplay/offline_tdm_session.gd': ('update',),
    'ai/tdm_bot_director.gd': ('commands',),
    'simulation/match_simulation.gd': ('step_fixed',),
    'presentation/openspades_effects.gd': ('update_effects',),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--import-cache', type=Path)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.name):
        raise SystemExit('Use lowercase letters, digits and hyphens')
    target = ROOT / '.cache' / ('maxopt-probe-' + args.name)
    if target.exists():
        raise SystemExit('Choose a fresh name to preserve evidence')
    shutil.copytree(args.source / 'game', target / 'game', ignore=shutil.ignore_patterns('.godot'))
    if args.import_cache:
        shutil.copytree(args.import_cache / 'imported', target / 'game/.godot/imported')
    probe = target / 'game/__probe'
    probe.mkdir()
    shutil.copy2(ROOT / 'tests/browser/impact_profile_recorder.gd', probe / 'recorder.gd')
    shutil.copy2(ROOT / 'tests/browser/max_optimization_probe.gd', probe / 'maxopt.gd')
    for path, methods in TARGETS.items():
        module = target / 'game' / path
        module.write_text(instrument(module.read_text(encoding='utf-8'), methods, path), encoding='utf-8')
    (probe / 'maxopt.tscn').write_text('[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://__probe/maxopt.gd" id="1"]\n'
        '[node name="MaxOptimizationProbe" type="Node"]\nscript=ExtResource("1")\n', encoding='utf-8')
    config = target / 'game/project.godot'
    text = re.sub(r'run/main_scene="[^"]+"', 'run/main_scene="res://__probe/maxopt.tscn"', config.read_text(encoding='utf-8'))
    text = text.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\n'
        'config/custom_user_dir_name="blockfield-maxopt-probe"', 1)
    config.write_text(text, encoding='utf-8')
    identity = {'source': str(args.source.resolve()), 'targets': TARGETS,
        'scripts': {str(p.relative_to(target / 'game')): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in (target / 'game').rglob('*.gd')}}
    (target / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n', encoding='utf-8')
    if args.prepare_only:
        print(target, flush=True)
        return
    engine = build.engine()
    build.ROOT = target
    build.engine = lambda: engine
    build.run('import', ['--editor', '--import', '--quit'])
    folder = target / 'build/web'
    folder.mkdir(parents=True)
    preset, original, metadata = select(target)
    try:
        build.run('export', ['--export-release', 'Web', str(folder / 'index.html')])
    finally:
        preset.write_bytes(original)
    identity.update(metadata)
    (folder / 'build-info.json').write_text(json.dumps(identity, indent=2) + '\n', encoding='utf-8')
    print(folder, flush=True)


if __name__ == '__main__':
    main()
