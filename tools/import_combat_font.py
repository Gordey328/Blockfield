"""Fetch the pinned, OFL-licensed Inter 4.1 combat font from its authors."""
from pathlib import Path
import hashlib
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://raw.githubusercontent.com/rsms/inter/v4.1/'
FONT_SHA256 = '4989b125924991b90d05b2d16e0e388c48f7d5bb8b30539bbf9c755278d0ccaf'


def main():
    destination = ROOT / 'game' / 'assets' / 'fonts'
    destination.mkdir(parents=True, exist_ok=True)
    font = urllib.request.urlopen(BASE + 'docs/font-files/InterVariable.ttf', timeout=60).read()
    if hashlib.sha256(font).hexdigest() != FONT_SHA256:
        raise RuntimeError('Pinned Inter font hash mismatch')
    license_text = urllib.request.urlopen(BASE + 'LICENSE.txt', timeout=60).read()
    (destination / 'InterVariable.ttf').write_bytes(font)
    (destination / 'OFL.txt').write_bytes(license_text)
    print('Inter 4.1: verified SHA256; font and OFL notice imported')


if __name__ == '__main__':
    main()
