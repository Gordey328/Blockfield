"""Export a private Godot terrain/presentation benchmark from frozen source.

The ordinary entry point is replaced only in an ignored archive copy. Metadata
marks these deliberate overrides dirty/private, so normal Pages publication
refuses this diagnostic folder. No production project files are changed.
"""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import zipfile
import build

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--import-cache', type=Path)
    args = parser.parse_args()
    revision = subprocess.run(
        ['git', 'rev-parse', '--verify', args.revision + '^{commit}'],
        cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    folder = ROOT / '.cache' / ('arsenal-benchmark-' + revision[:12])
    folder.mkdir(parents=True, exist_ok=False)
    archive = folder / 'source.zip'
    subprocess.run(['git', 'archive', '--format=zip', '--output=' + str(archive),
                    revision], cwd=ROOT, check=True)
    with zipfile.ZipFile(archive) as source:
        source.extractall(folder)
    if args.import_cache:
        shutil.copytree(args.import_cache.resolve(), folder / 'game/.godot')
    destination = folder / 'game/benchmark'
    destination.mkdir()
    scripts = folder / 'tests/gameplay'
    shutil.copy2(scripts / 'arsenal_web_benchmark.gd', destination)
    scene = (scripts / 'arsenal_web_benchmark.tscn').read_text(encoding='utf-8')
    scene = scene.replace('res://../tests/gameplay/', 'res://benchmark/')
    scene += 'source_hint = "' + revision + '"\n'
    (destination / 'arsenal_web_benchmark.tscn').write_text(scene, encoding='utf-8')
    project = folder / 'game/project.godot'
    original = project.read_text(encoding='utf-8')
    entry = 'run/main_scene="res://scenes/entry.tscn"'
    if original.count(entry) != 1:
        raise RuntimeError('Expected the ordinary entry scene exactly once')
    project.write_text(original.replace(entry,
                       'run/main_scene="res://benchmark/arsenal_web_benchmark.tscn"'),
                       encoding='utf-8')
    engine_path = build.engine()
    build.ROOT = folder
    build.engine = lambda: engine_path
    build.source_state = lambda: {
        'source_commit': revision, 'source_dirty': True,
        'status': 'private diagnostic', 'diagnostic_source_clean': True,
        'diagnostic_overrides': ['benchmark scene copied into game/benchmark',
                                 'run/main_scene changed in private archive'],
    }
    build.run('arsenal-benchmark-import', ['--editor', '--import', '--quit'])
    build.export_web()
    print(json.dumps({'source_commit': revision,
                      'private_web': str(folder / 'build/web')}, indent=2), flush=True)


if __name__ == '__main__':
    main()
