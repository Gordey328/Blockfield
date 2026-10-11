"""Export an isolated actual-Main weapon/terrain diagnostic from chosen source."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import build

ROOT = Path(__file__).resolve().parents[1]

PROFILE_TARGETS = {
    'main.gd': ('_process', '_update_graphics', '_blocks_changed'),
    'world/voxel_world.gd': ('_process', 'process_rebuild_work', 'rebuild_now', '_present_transaction', 'advance_visual_preparation', 'get_stats'),
    'gameplay/player_controller.gd': ('_physics_process', '_shoot'),
    'presentation/openspades_effects.gd': ('update_effects', '_update_particles', '_update_casings', '_sync_fragment_batch'),
    'audio/openspades_audio.gd': ('compute_ambience', '_play', '_start_voice', '_new_player', '_process'),
    'ui/lab_map.gd': ('_process', '_upload_terrain'),
    'ui/lab_hud.gd': ('_process',),
}


def argument_names(signature):
    """Split GDScript parameters only at top-level commas, preserving defaults/types."""
    pieces, start, depth, quote = [], 0, 0, None
    for index, char in enumerate(signature):
        if quote:
            if char == quote and (index == 0 or signature[index - 1] != '\\'):
                quote = None
        elif char in "'\"":
            quote = char
        elif char in '([{':
            depth += 1
        elif char in ')]}':
            depth -= 1
        elif char == ',' and depth == 0:
            pieces.append(signature[start:index].strip())
            start = index + 1
    pieces.append(signature[start:].strip())
    names = [re.match(r'([A-Za-z_][A-Za-z0-9_]*)', piece).group(1) for piece in pieces if piece]
    return ', '.join(names)


def instrument(source, names, label):
    """Wrap synchronous methods in an isolated copy; signatures/defaults stay exact."""
    wrappers = []
    for name in names:
        pattern = re.compile(r'^func ' + re.escape(name) + r'\((.*)\)(\s*->\s*[^:]+)?\s*:\s*$', re.MULTILINE)
        matches = list(pattern.finditer(source))
        if len(matches) != 1:
            raise SystemExit(f'Expected exactly one single-line {label}.{name} signature; found {len(matches)}')
        match = matches[0]
        arguments, returns = match.group(1), match.group(2) or ''
        original = '_impact_original_' + name.lstrip('_')
        definition = f'func {name}({arguments}){returns}:'
        source = source[:match.start()] + f'func {original}({arguments}){returns}:' + source[match.end():]
        wrapper = definition + '\n\tvar profile_ticket := IMPACT_DIAGNOSTIC_PROFILE.enter(' + json.dumps(label + '.' + name) + ')\n'
        call = original + '(' + argument_names(arguments) + ')'
        if returns.strip() == '-> void' or not returns:
            wrapper += '\t' + call + '\n\tIMPACT_DIAGNOSTIC_PROFILE.leave(profile_ticket)\n'
        else:
            wrapper += '\tvar profile_value = ' + call + '\n\tIMPACT_DIAGNOSTIC_PROFILE.leave(profile_ticket)\n\treturn profile_value\n'
        wrappers.append(wrapper)
    source = re.sub(r'^(extends [^\n]+)$', r'\1\nconst IMPACT_DIAGNOSTIC_PROFILE = preload("res://__probe/recorder.gd")', source, count=1, flags=re.MULTILINE)
    return source + '\n' + '\n'.join(wrappers)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT)
    parser.add_argument('--name', required=True)
    parser.add_argument('--import-cache', type=Path)
    parser.add_argument('--profile', action='store_true', help='Use warmed Title CPU diagnostic and identical isolated timing wrappers')
    parser.add_argument('--prepare-only', action='store_true', help='Prepare isolated files without importing or invoking Godot')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.name):
        raise SystemExit('Name must use lowercase letters, digits and hyphens')
    target = ROOT / '.cache' / ('block-impact-probe-' + args.name)
    if target.exists():
        raise SystemExit('Preserve existing diagnostic; choose a new name')
    shutil.copytree(args.source / 'game', target / 'game', ignore=shutil.ignore_patterns('.godot'))
    if args.import_cache:
        shutil.copytree(args.import_cache, target / 'game/.godot')
    probe = target / 'game/__probe'
    probe.mkdir()
    script = 'block_impact_profile.gd' if args.profile else 'block_impact_probe.gd'
    shutil.copy2(ROOT / 'tests/browser' / script, probe / 'impact.gd')
    if args.profile:
        shutil.copy2(ROOT / 'tests/browser/impact_profile_recorder.gd', probe / 'recorder.gd')
        shutil.copy2(ROOT / 'tests/world/profile_block_impact.gd', probe / 'native.gd')
        for path, methods in PROFILE_TARGETS.items():
            module = target / 'game' / path
            module.write_text(instrument(module.read_text(encoding='utf-8'), methods, path), encoding='utf-8')
    (probe / 'impact.tscn').write_text(
        '[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://__probe/impact.gd" id="1"]\n'
        '[node name="BlockImpactProbe" type="Node"]\nscript=ExtResource("1")\n', encoding='utf-8')
    config = target / 'game/project.godot'
    text = re.sub(r'run/main_scene="[^"]+"', 'run/main_scene="res://__probe/impact.tscn"', config.read_text(encoding='utf-8'))
    user_dir = 'blockfield-impact-profile' if args.profile else 'blockfield-impact-probe'
    text = text.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + user_dir + '"', 1)
    config.write_text(text, encoding='utf-8')
    hashes = {str(path.relative_to(target / 'game')): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in (target / 'game').rglob('*.gd')}
    (target / 'identity.json').write_text(json.dumps({'source': str(args.source.resolve()), 'scripts': hashes,
        'diagnostic_profile': args.profile, 'profile_targets': PROFILE_TARGETS if args.profile else {},
        'recorder_sample_cap': 8192 if args.profile else 0}, indent=2) + '\n', encoding='utf-8')
    if args.prepare_only:
        print(target / 'game', flush=True)
        return
    engine = build.engine()
    build.ROOT = target
    build.engine = lambda: engine
    build.run('import', ['--editor', '--import', '--quit'])
    folder = target / 'build/web'
    folder.mkdir(parents=True)
    build.run('export', ['--export-release', 'Web', str(folder / 'index.html')])
    print(folder, flush=True)


if __name__ == '__main__':
    main()
