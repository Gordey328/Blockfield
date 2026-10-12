"""Validate/export a frozen Git revision while specialists continue in the workspace."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import sys
import zipfile
import build

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--revision', default='HEAD')
    parser.add_argument('--import-cache', type=Path, help='Seed the frozen project with an existing .godot cache; parser/import and selected checks still run')
    parser.add_argument('--suite', action='append', default=[], help='Pass a named fixture selection to build.py; default remains all fixtures')
    args = parser.parse_args()
    revision = subprocess.run(['git', 'rev-parse', '--verify', args.revision + '^{commit}'],
                              cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    folder = ROOT / '.cache' / ('release-' + revision[:12])
    folder.mkdir(parents=True, exist_ok=False)
    archive = folder / 'source.zip'
    subprocess.run(['git', 'archive', '--format=zip', '--output=' + str(archive), revision],
                   cwd=ROOT, check=True)
    with zipfile.ZipFile(archive) as source:
        source.extractall(folder)
    if args.import_cache:
        shutil.copytree(args.import_cache.resolve(), folder / 'game' / '.godot')
    engine_path = build.engine()
    build.ROOT = folder
    build.engine = lambda: engine_path
    build.source_state = lambda: {'source_commit': revision, 'source_dirty': False}
    # Fixtures exercise persisted settings. Give each freeze a private directory,
    # then restore the exact archived project bytes before shipping the export.
    config = folder / 'game' / 'project.godot'
    original_config = config.read_bytes()
    private_config = original_config.decode('utf-8').replace(
        '[application]', '[application]\nconfig/use_custom_user_dir=true\n'
        'config/custom_user_dir_name="blockfield-check-' + revision[:12] + '"', 1)
    config.write_text(private_config, encoding='utf-8')
    sys.argv = [str(folder / 'tools' / 'build.py')]
    for suite in args.suite:
        sys.argv += ['--suite', suite]
    try:
        build.main()
    finally:
        config.write_bytes(original_config)
    build.export_web()
    source_web = folder / 'build' / 'web'
    destination = ROOT / 'build' / 'web'
    destination.mkdir(parents=True, exist_ok=True)
    # Preserve the separate ignored gh-pages checkout used for publication.
    shutil.copytree(source_web, destination, dirs_exist_ok=True)
    print(json.dumps({'source_commit': revision, 'export': str(destination)}), flush=True)


if __name__ == '__main__':
    main()
