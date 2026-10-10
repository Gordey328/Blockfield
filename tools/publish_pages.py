"""Publish an already checked Web export using GitHub Pages branch hosting."""
from pathlib import Path
import argparse
import json
import subprocess
from github_api import api

ROOT=Path(__file__).resolve().parents[1]

def git(*args,cwd=ROOT):
    result=subprocess.run(['git',*args],cwd=cwd,capture_output=True,text=True,check=True)
    return result.stdout.strip()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--repo',default='Gordey328/Blockfield')
    args=parser.parse_args()
    folder=ROOT/'build'/'web'
    for name in ('index.html','index.js','index.wasm','index.pck','.nojekyll','LICENSE.txt'):
        if not (folder/name).is_file():raise RuntimeError('Missing checked export: '+name)
    remote='https://github.com/'+args.repo+'.git'
    if not (folder/'.git').exists():
        git('init','-b','gh-pages',cwd=folder)
        git('config','user.name',git('config','user.name'),cwd=folder)
        git('config','user.email',git('config','user.email'),cwd=folder)
        git('remote','add','origin',remote,cwd=folder)
    elif git('remote','get-url','origin',cwd=folder)!=remote:
        raise RuntimeError('Export checkout has a different remote')
    git('config','core.autocrlf','false',cwd=folder)
    (folder/'.gitattributes').write_text('* -text\n',encoding='utf-8')
    git('add','--all',cwd=folder)
    changed=git('status','--porcelain',cwd=folder)
    if changed:git('commit','-m','Publish checked Godot Web development build',cwd=folder)
    git('push','origin','HEAD:gh-pages',cwd=folder)
    api('/repos/'+args.repo+'/pages','PUT',{'build_type':'legacy','source':{'branch':'gh-pages','path':'/'}})
    queued=api('/repos/'+args.repo+'/pages/builds','POST')
    print(json.dumps({'status':queued.get('status'),'url':'https://'+args.repo.split('/')[0].lower()+'.github.io/'+args.repo.split('/')[1]+'/'}))

if __name__=='__main__':main()
