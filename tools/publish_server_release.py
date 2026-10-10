"""Publish an already verified frozen server ZIP as a development GitHub release."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import urllib.error
import urllib.parse
import urllib.request
from github_api import api, credential


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--repo', default='Gordey328/Blockfield')
    args = parser.parse_args()
    package = args.package.resolve()
    metadata = json.loads(package.with_suffix('.zip.json').read_text(encoding='utf-8'))
    revision = metadata['source_commit']
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    if not re.fullmatch(r'[0-9a-f]{40}', revision) or digest != metadata['sha256']:
        raise RuntimeError('Frozen package identity/hash check failed')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repo):
        raise RuntimeError('Invalid repository')
    base = '/repos/' + args.repo
    tag = 'godot-' + revision[:12]
    try:
        release = api(base + '/releases/tags/' + tag)
    except RuntimeError as error:
        if 'HTTP 404' not in str(error):
            raise
        release = api(base + '/releases', 'POST', {
            'tag_name': tag, 'target_commitish': revision,
            'name': 'Godot development build ' + revision[:12],
            'prerelease': True, 'draft': False,
            'body': 'Browser client: https://gordey328.github.io/Blockfield/\n\n'
                    'This checkpoint includes the offline lab and a dedicated authority. '
                    'The attached ZIP contains the Linux export, matching Docker/Caddy configuration, '
                    'build hashes and deployment instructions. Its frozen source is ' + revision + '.\n\n'
                    'Docker/Linux execution and public TLS/WSS deployment remain unverified on the '
                    'Windows build host. A server host and DNS domain must be configured separately. '
                    'See docs/parity.md for remaining full-port acceptance.\n\n'
                    'Server ZIP SHA256: `' + digest + '`.'
        })
    if release.get('target_commitish') != revision or not release.get('prerelease'):
        raise RuntimeError('Existing release does not match this development checkpoint')
    assets = api(base + '/releases/' + str(release['id']) + '/assets')
    existing = [asset for asset in assets if asset['name'] == package.name]
    if existing:
        asset = existing[0]
        if asset.get('digest') != 'sha256:' + digest:
            raise RuntimeError('Existing release asset has a different or unavailable digest')
    else:
        token = credential()
        if not token:
            raise RuntimeError('Existing GitHub credential unavailable')
        url = 'https://uploads.github.com' + base + '/releases/' + str(release['id']) + '/assets?name=' + urllib.parse.quote(package.name)
        request = urllib.request.Request(url, method='POST', data=package.read_bytes(), headers={
            'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + token,
            'User-Agent': 'Blockfield-build', 'Content-Type': 'application/zip',
            'X-GitHub-Api-Version': '2022-11-28'})
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                asset = json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError('Release upload failed: HTTP ' + str(error.code)) from None
    if asset.get('state') != 'uploaded' or asset.get('size') != package.stat().st_size:
        raise RuntimeError('Uploaded release asset is incomplete')
    download = asset['browser_download_url']
    if not download.startswith('https://github.com/' + args.repo + '/releases/download/' + tag + '/'):
        raise RuntimeError('Unexpected published asset URL')
    # Independently verify the public download, without sending a credential.
    actual = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(download, timeout=90) as response:
        while chunk := response.read(1024 * 1024):
            actual.update(chunk)
            size += len(chunk)
            if size > package.stat().st_size:
                raise RuntimeError('Public release download exceeds the package size')
    if size != package.stat().st_size or actual.hexdigest() != digest:
        raise RuntimeError('Public release download hash mismatch')
    print(json.dumps({'release': release['html_url'], 'download': download,
                      'source_commit': revision, 'sha256': digest, 'bytes': size}), flush=True)


if __name__ == '__main__':
    main()
