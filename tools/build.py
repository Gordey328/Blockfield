"""Reproducible Godot validation and web export (Python 3 standard library)."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
from bootstrap import VERSION, main as bootstrap

ROOT=Path(__file__).resolve().parents[1]

def source_state():
    revision=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,capture_output=True,text=True,check=True).stdout.strip()
    dirty=subprocess.run(['git','status','--porcelain'],cwd=ROOT,capture_output=True,text=True,check=True).stdout.strip()
    return {'source_commit':revision,'source_dirty':bool(dirty)}

def engine():
    suffix='win64_console.exe' if sys.platform=='win32' else 'linux.x86_64'
    path=ROOT/'.tools'/'godot'/f'Godot_v{VERSION}-stable_{suffix}'
    if not path.exists(): bootstrap()
    return path

def run(name, args, timeout=180):
    command=[str(engine()),'--headless','--path',str(ROOT/'game'),*args]
    result=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout)
    output=result.stdout+'\n'+result.stderr
    folder=ROOT/'.cache'/'logs'; folder.mkdir(parents=True,exist_ok=True)
    (folder/(name+'.log')).write_text(output,encoding='utf-8')
    errors=[line for line in output.splitlines() if re.search(r'SCRIPT ERROR|Parse Error|^ERROR:|FAIL:',line)]
    if result.returncode or errors:
        print('\n'.join(errors or output.splitlines()[-20:]))
        raise SystemExit(f'{name} failed; see .cache/logs/{name}.log')
    summaries=[line for line in output.splitlines() if re.search(r'assertions|checks|PASS|failures',line,re.I)]
    print(name+': OK'+(' — '+'; '.join(summaries) if summaries else ''),flush=True)
    return output

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--export',action='store_true')
    args=parser.parse_args()
    run('import',['--editor','--import','--quit'])
    for label in ('world','session','integration'):
        path=ROOT/'tests'/label/f'test_{"lab" if label=="integration" else label}.gd'
        if path.exists():run('test-'+label,['--script',str(path)])
    suites=[('grenade','tests/gameplay/test_grenade.gd'),('vxl-save','tests/world/test_vxl_save.gd'),('falling-clusters','tests/world/test_falling_clusters.gd'),('lighting','tests/world/test_lighting.gd'),('topdown','tests/world/test_topdown.gd'),('presentation','tests/presentation/test_presentation.gd'),('localization','tests/presentation/test_localization.gd'),('effects','tests/presentation/test_effects.gd'),('post-effects','tests/presentation/test_post_effects.gd'),('extensions','tests/presentation/test_extensions.gd'),('ui','tests/ui/test_ui.gd')]
    for name,path in suites:
        path=ROOT/path
        if path.exists():run('test-'+name,['--script',str(path)],timeout=300)
    run('runtime-smoke',['--quit-after','120'])
    if args.export:
        folder=ROOT/'build'/'web';folder.mkdir(parents=True,exist_ok=True)
        run('export',['--export-release','Web',str(folder/'index.html')])
        (folder/'.nojekyll').write_text('')
        (folder/'build-info.json').write_text(json.dumps({'engine':VERSION,'iteration':1,'status':'development','upstream':'dcf449c845d509bbde9d79239b32d201c1389961',**source_state()},indent=2)+'\n',encoding='utf-8')
        shutil.copy2(ROOT/'LICENSE',folder/'LICENSE.txt')
        shutil.copytree(ROOT/'game'/'assets'/'openspades'/'licenses',folder/'notices',dirs_exist_ok=True)
        shutil.copytree(ROOT/'licenses',folder/'notices'/'engine',dirs_exist_ok=True)
        print(f'Web build: {folder}',flush=True)

if __name__=='__main__':main()
