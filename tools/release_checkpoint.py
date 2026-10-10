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
    engine_path = build.engine()
    build.ROOT = folder
    build.engine = lambda: engine_path
    build.source_state = lambda: {'source_commit': revision, 'source_dirty': False}
    sys.argv = [str(folder / 'tools' / 'build.py'), '--export']
    build.main()
    source_web = folder / 'build' / 'web'
    destination = ROOT / 'build' / 'web'
    destination.mkdir(parents=True, exist_ok=True)
    # Preserve the separate ignored gh-pages checkout used for publication.
    shutil.copytree(source_web, destination, dirs_exist_ok=True)
    print(json.dumps({'source_commit': revision, 'export': str(destination)}), flush=True)


if __name__ == '__main__':
    main()
