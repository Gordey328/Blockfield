"""Package the frozen Linux authority and matching Docker/Caddy configuration."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import zipfile

ROOT=Path(__file__).resolve().parents[1]

def package(source: Path, destination: Path):
    source=source.resolve()
    server=source/'build/server'
    metadata=json.loads((server/'build-info.json').read_text(encoding='utf-8'))
    revision=metadata.get('source_commit','')
    if metadata.get('source_dirty') is not False or not re.fullmatch(r'[0-9a-f]{40}',revision):
        raise RuntimeError('Package requires a frozen clean source revision')
    for name,digest in metadata['files'].items():
        if name not in ('blockfield.x86_64','blockfield.pck'):
            raise RuntimeError('Unexpected server metadata file')
        if hashlib.sha256((server/name).read_bytes()).hexdigest()!=digest:
            raise RuntimeError('Server artifact hash mismatch: '+name)
    if set(metadata['files'])!={'blockfield.x86_64','blockfield.pck'}:
        raise RuntimeError('Server metadata is incomplete')
    configs=['deploy/Dockerfile','deploy/compose.yaml','deploy/Caddyfile','deploy/.env.example',
             'docs/server-deployment.md','LICENSE','.dockerignore']
    for name in configs:
        if not (source/name).is_file(): raise RuntimeError('Missing frozen deployment file: '+name)
    destination.mkdir(parents=True,exist_ok=True)
    output=destination/('blockfield-server-'+revision[:12]+'.zip')
    if output.exists(): raise RuntimeError('Package already exists: '+str(output))
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for file in sorted(server.rglob('*')):
            if file.is_file(): archive.write(file,file.relative_to(source).as_posix())
        for name in configs: archive.write(source/name,name)
        archive.writestr('START-HERE.txt',
            'Blockfield development authority, frozen source '+revision+'\n'
            'Linux Godot export; Docker/Linux/TLS execution is not verified on the build host.\n'
            'Extract this ZIP, copy deploy/.env.example to deploy/.env, set your DNS domain,\n'
            'then run from the extracted root:\n'
            'docker compose --env-file deploy/.env -f deploy/compose.yaml up --build -d\n'
            'Browser endpoints: wss://YOUR-DOMAIN/play and wss://YOUR-DOMAIN/map\n'
            'Read docs/server-deployment.md and the bundled license notices.\n')
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None: raise RuntimeError('ZIP integrity check failed')
        for name,digest in metadata['files'].items():
            if hashlib.sha256(archive.read('build/server/'+name)).hexdigest()!=digest:
                raise RuntimeError('Packaged artifact hash mismatch')
    result={'file':str(output),'source_commit':revision,
            'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'bytes':output.stat().st_size}
    output.with_suffix('.zip.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,required=True,help='Frozen release archive directory')
    parser.add_argument('--destination',type=Path,default=ROOT/'build/packages')
    args=parser.parse_args()
    package(args.source,args.destination)
