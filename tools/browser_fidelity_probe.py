"""Export a separate actual-Main Web test scene from a validated release archive."""
from pathlib import Path
import argparse
import shutil
import hashlib
import build

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--release', required=True, type=Path)
    parser.add_argument('--fixture', type=Path, help='Explicit separately committed test-only fixture override')
    args = parser.parse_args()
    source = args.release.resolve()
    if source.parent != ROOT/'.cache' or not source.name.startswith('release-'):
        raise SystemExit('Expected an existing frozen .cache/release-* archive')
    destination = ROOT/'.cache'/('web-fidelity-'+source.name.removeprefix('release-'))
    if destination.exists(): raise SystemExit('Probe archive already exists; preserve previous evidence')
    shutil.copytree(source/'game', destination/'game', ignore=shutil.ignore_patterns('.godot'))
    probe = destination/'game'/'__probe'
    probe.mkdir()
    fixture = args.fixture.resolve() if args.fixture else source/'tests'/'browser'/'fidelity_probe.gd'
    shutil.copy2(fixture,probe/'fidelity.gd')
    print('Fixture SHA256: '+hashlib.sha256(fixture.read_bytes()).hexdigest(),flush=True)
    (probe/'fidelity.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://__probe/fidelity.gd" id="1"]\n[node name="FidelityProbe" type="Node"]\nscript=ExtResource("1")\n',encoding='utf-8')
    config = destination/'game'/'project.godot'
    text = config.read_text(encoding='utf-8')
    import re
    text,count = re.subn(r'run/main_scene="[^"]+"','run/main_scene="res://__probe/fidelity.tscn"',text)
    if count != 1: raise SystemExit('Expected one entry scene')
    text = text.replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="blockfield-fidelity-probe"',1)
    config.write_text(text,encoding='utf-8')
    engine = build.engine()
    build.ROOT = destination
    build.engine = lambda: engine
    build.run('probe-import',['--editor','--import','--quit'])
    output = destination/'build'/'web'
    output.mkdir(parents=True)
    build.run('probe-export',['--export-release','Web',str(output/'index.html')])
    print('Test-only Web export: '+str(output),flush=True)

if __name__=='__main__': main()
