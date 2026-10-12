"""Use the existing Git credential helper without exposing its credential."""
from __future__ import annotations
import argparse
import json
import os
import subprocess
import urllib.error
import urllib.request

def credential():
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='never')
    result = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n', text=True, capture_output=True, env=env, timeout=25)
    fields = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    return fields.get('password')

def api(path, method='GET', body=None):
    token = credential()
    if not token:
        raise RuntimeError('No existing GitHub credential available for noninteractive API access')
    req = urllib.request.Request('https://api.github.com'+path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Accept': 'application/vnd.github+json','Authorization':'Bearer '+token,
                 'User-Agent':'Blockfield-build','X-GitHub-Api-Version':'2022-11-28','Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            return json.load(response) if response.status != 204 else {}
    except urllib.error.HTTPError as exc:
        try: message = json.loads(exc.read()).get('message', 'Request failed')
        except Exception: message = 'Request failed'
        raise RuntimeError(f'GitHub API HTTP {exc.code}: {message}') from None

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=['check','create','pages','runs'])
    parser.add_argument('--repo',default='Gordey328/Blockfield')
    args=parser.parse_args()
    if args.action=='check':
        user=api('/user'); print(json.dumps({'login':user['login']}))
    elif args.action=='create':
        user=api('/user')
        if user['login']!=args.repo.split('/')[0]: raise RuntimeError('Authenticated account does not match requested owner')
        repo=api('/user/repos','POST',{'name':args.repo.split('/')[1],'description':'OpenSpades port to Godot: offline voxel combat with bots and a browser test lab','private':False,'auto_init':False})
        print(json.dumps({'url':repo['html_url'],'clone_url':repo['clone_url']}))
    elif args.action=='pages':
        try: page=api('/repos/'+args.repo+'/pages')
        except RuntimeError as exc:
            if 'HTTP 404' not in str(exc): raise
            page=api('/repos/'+args.repo+'/pages','POST',{'build_type':'workflow'})
        print(json.dumps({'url':page.get('html_url'),'build_type':page.get('build_type')}))
    else:
        runs=api('/repos/'+args.repo+'/actions/runs?per_page=5')
        print(json.dumps([{'id':r['id'],'status':r['status'],'conclusion':r['conclusion'],'url':r['html_url'],'head_sha':r['head_sha']} for r in runs['workflow_runs']]))

if __name__=='__main__':
    try: main()
    except Exception as exc: raise SystemExit(str(exc))
