"""Export a separate actual-Main grenade feedback/mixer scene from frozen source."""
from pathlib import Path
import argparse
import json
import re
import shutil
import build

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--import-cache', type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.name):
        raise SystemExit('Use lowercase letters, digits and hyphens for name')
    target = ROOT / '.cache' / ('grenade-probe-' + args.name)
    if target.exists():
        raise SystemExit('Preserve existing evidence; choose a new name')
    shutil.copytree(args.source / 'game', target / 'game', ignore=shutil.ignore_patterns('.godot'))
    if args.import_cache:
        shutil.copytree(args.import_cache, target / 'game/.godot')
    probe = target / 'game/__probe'
    probe.mkdir()
    shutil.copy2(args.source / 'tests/browser/grenade_feedback_probe.gd', probe / 'grenade.gd')
    (probe / 'grenade.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://__probe/grenade.gd" id="1"]\n[node name="GrenadeProbe" type="Node"]\nscript=ExtResource("1")\n', encoding='utf-8')
    config = target / 'game/project.godot'
    source = re.sub(r'run/main_scene="[^"]+"', 'run/main_scene="res://__probe/grenade.tscn"', config.read_text(encoding='utf-8'))
    source = source.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="blockfield-grenade-proof"', 1)
    config.write_text(source, encoding='utf-8')
    (target / 'identity.json').write_text(json.dumps({'source': str(args.source.resolve())}, indent=2), encoding='utf-8')
    engine = build.engine()
    build.ROOT = target
    build.engine = lambda: engine
    build.run('import', ['--editor', '--import', '--quit'])
    folder = target / 'build/web'
    folder.mkdir(parents=True)
    build.run('export', ['--export-release', 'Web', str(folder / 'index.html')])
    print(folder, flush=True)

if __name__ == '__main__':
    main()
