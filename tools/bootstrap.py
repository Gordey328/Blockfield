"""Download the pinned standalone engine and only the web export templates."""
from __future__ import annotations
import io
import os
import sys
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '4.7.2'
BASE = f'https://godot-releases.nbg1.your-objectstorage.com/{VERSION}-stable/'

def request(url: str, **kwargs):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Blockfield-build', **kwargs.pop('headers', {})}, **kwargs), timeout=90)

def download(url: str, dest: Path):
    if dest.exists():
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    temp = dest.with_suffix(dest.suffix + '.tmp')
    with request(url) as source, temp.open('wb') as target:
        while part := source.read(1024 * 1024):
            target.write(part)
    temp.replace(dest)
    print(f'Downloaded {dest.name}: {dest.stat().st_size:,} bytes', flush=True)

class RemoteZip(io.RawIOBase):
    """Seekable range reader; avoids downloading templates for unrelated platforms."""
    def __init__(self, url):
        with request(url, method='HEAD') as response:
            self.url = response.url
            self.size = int(response.headers['Content-Length'])
        self.pos = 0
        self.cache_start = -1
        self.cache = b''
    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else (self.pos if whence == 1 else self.size) + offset
        return self.pos
    def read(self, n=-1):
        n = self.size - self.pos if n < 0 else min(n, self.size-self.pos)
        if n <= 0: return b''
        if not (self.cache_start <= self.pos and self.pos+n <= self.cache_start+len(self.cache)):
            end = min(self.size-1, self.pos+max(n, 65536)-1)
            with request(self.url, headers={'Range': f'bytes={self.pos}-{end}'}) as response:
                if response.status != 206:
                    raise RuntimeError('Template host did not honor byte ranges; refusing full multi-platform download')
                self.cache_start = self.pos
                self.cache = response.read()
        start = self.pos-self.cache_start
        result = self.cache[start:start+n]
        self.pos += len(result)
        return result

def main():
    folder = ROOT / '.tools' / 'godot'
    platform = 'win64.exe' if sys.platform == 'win32' else 'linux.x86_64'
    archive = ROOT / '.cache' / f'Godot_v{VERSION}-stable_{platform}.zip'
    download(BASE + archive.name, archive)
    folder.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as source:
        for item in source.infolist():
            if Path(item.filename).name == item.filename and (item.filename.endswith('.exe') or item.filename.endswith('.x86_64')):
                target = folder / item.filename
                if not target.exists():
                    target.write_bytes(source.read(item))
                    if sys.platform != 'win32': target.chmod(0o755)
    binary = f'Godot_v{VERSION}-stable_win64_console.exe' if sys.platform == 'win32' else f'Godot_v{VERSION}-stable_linux.x86_64'
    print('Engine: ' + str(folder / binary), flush=True)
    data_home = Path(os.environ['APPDATA']) if sys.platform == 'win32' else Path(os.environ.get('XDG_DATA_HOME', Path.home()/'.local/share'))
    templates = data_home / ('Godot' if sys.platform == 'win32' else 'godot') / 'export_templates' / f'{VERSION}.stable'
    templates.mkdir(parents=True, exist_ok=True)
    needed = [name for name in ('web_nothreads_debug.zip', 'web_nothreads_release.zip') if not (templates/name).exists()]
    if needed:
        print('Reading remote template archive index', flush=True)
        with zipfile.ZipFile(RemoteZip(BASE + f'Godot_v{VERSION}-stable_export_templates.tpz')) as source:
            for item in source.infolist():
                name = Path(item.filename).name
                if name in needed or name == 'version.txt':
                    (templates/name).write_bytes(source.read(item))
                    print(f'Installed template {name}: {item.file_size:,} bytes', flush=True)
    print('Templates: ' + str(templates), flush=True)

if __name__ == '__main__': main()
