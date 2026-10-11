"""Export an isolated actual-Main audio/VXL diagnostic, preserving production build."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import build

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT)
    parser.add_argument('--name', required=True)
    parser.add_argument('--import-cache', type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.name):
        raise SystemExit('Name must use lowercase letters, digits and hyphens')
    target = ROOT / '.cache' / ('optimization-probe-' + args.name)
    if target.exists():
        raise SystemExit('Preserve existing diagnostic; choose a new name')
    shutil.copytree(args.source / 'game', target / 'game', ignore=shutil.ignore_patterns('.godot'))
    if args.import_cache:
        shutil.copytree(args.import_cache, target / 'game/.godot')
    probe = target / 'game/__probe'
    probe.mkdir()
    shutil.copy2(ROOT / 'tests/browser/optimization_probe.gd', probe / 'optimization.gd')
    (probe / 'optimization.tscn').write_text(
        '[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://__probe/optimization.gd" id="1"]\n'
        '[node name="OptimizationProbe" type="Node"]\nscript=ExtResource("1")\n', encoding='utf-8')
    config = target / 'game/project.godot'
    text = re.sub(r'run/main_scene="[^"]+"', 'run/main_scene="res://__probe/optimization.tscn"', config.read_text(encoding='utf-8'))
    text = text.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="blockfield-optimization-probe"', 1)
    config.write_text(text, encoding='utf-8')
    hashes = {str(path.relative_to(target / 'game')): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in (target / 'game').rglob('*.gd')}
    (target / 'identity.json').write_text(json.dumps({'source': str(args.source.resolve()), 'scripts': hashes}, indent=2) + '\n', encoding='utf-8')
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
