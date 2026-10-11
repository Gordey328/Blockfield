"""Select the accepted, hash-pinned reduced Web template for release exports."""
import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE_SHA256 = 'a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922'


def select(project_root):
    template = ROOT / 'build/templates/godot-4.7.2-web-blockfield.zip'
    if not template.is_file():
        raise RuntimeError('Reduced Web template missing: build it with tools/build_web_template.py; see docs/web-template-size.md')
    if hashlib.sha256(template.read_bytes()).hexdigest() != TEMPLATE_SHA256:
        raise RuntimeError('Reduced Web template SHA256 does not match the accepted binary')
    preset = Path(project_root) / 'game/export_presets.cfg'
    original = preset.read_bytes()
    text = original.decode('utf-8')
    options = re.search(r'(?ms)^\[preset\.0.options\]\s*\n.*?(?=^\[|\Z)', text)
    if not options:
        raise RuntimeError('Web preset options missing')
    selected, count = re.subn(r'^custom_template/release="[^"]*"',
                             'custom_template/release="' + template.as_posix() + '"',
                             options[0], flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError('Expected one Web release template option')
    preset.write_text(text[:options.start()] + selected + text[options.end():], encoding='utf-8')
    return preset, original, {'template_kind': 'reduced', 'template_sha256': TEMPLATE_SHA256}
