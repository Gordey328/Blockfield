"""Export the pinned Linux headless authority; no hosting/account changes."""
from pathlib import Path
import hashlib
import json
import shutil
import build
from bootstrap import install_templates, VERSION


def main():
    install_templates(('linux_release.x86_64',))
    folder = build.ROOT/'build'/'server'
    folder.mkdir(parents=True, exist_ok=True)
    build.run('server-import', ['--editor', '--import', '--quit'])
    build.run('server-launcher-smoke', ['--quit-after', '60', '--', '--server', '--game-port=0', '--map-port=0'])
    build.run('server-export', ['--export-release', 'Linux Dedicated Server', str(folder/'blockfield.x86_64')])
    for name in ('blockfield.x86_64', 'blockfield.pck'):
        path = folder/name
        if not path.is_file():
            raise SystemExit('Dedicated export missing '+name)
    shutil.copy2(build.ROOT/'LICENSE', folder/'LICENSE.txt')
    shutil.copytree(build.ROOT/'licenses', folder/'notices', dirs_exist_ok=True)
    metadata = {'engine': VERSION, 'status': 'development', **build.source_state(),
                'files': {name: hashlib.sha256((folder/name).read_bytes()).hexdigest()
                          for name in ('blockfield.x86_64', 'blockfield.pck')}}
    (folder/'build-info.json').write_text(json.dumps(metadata, indent=2)+'\n', encoding='utf-8')
    print('Linux dedicated build: '+str(folder), flush=True)


if __name__ == '__main__':
    main()
