"""Reproduce two bounded survival adaptations from pinned public Teardown ZIPs.

Only XML/VOX data is read. Lua, executables, sounds and downloaded scripts are
never executed. Raw archives stay in ignored .cache/survival-map-sources.
Usage: python tools/prepare_survival_maps.py [--download] [--map ID]
"""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
import re
import stat
import struct
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
import zlib

import numpy as np
from PIL import Image, ImageDraw

from map_import.teardown import (collect_scene, coarsen_points, physical_voxel_mask,
    resolve_source, transform_points, valid_spawn)
from map_import.teardown_vox import read_vox
from map_import.voxelize_helpers import exposed_mask, write_bfmap

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache/survival-map-sources'
MAPS = {
    'minecraft_chunk': {
        'title': 'Minecraft · Chunk', 'original_title': 'Small Minecraft Chunk',
        'author': 'The_Wolfian', 'workshop_id': '2652603687',
        'mirror': 'https://dlcfun.com/en/teardown/small-minecraft-chunk-mod',
        'archive': 'minecraft-2652603687.zip', 'mirror_filename': '2652603687.zip',
        'sha256': 'b2db060c30f373ac78a3d32f27596f56245a34811b27a27e575affedb044b86a',
        'directory': 'minecraft/2652603687', 'scene': 'original.xml', 'scale': .4,
        'origin': [-18.6, 11.2, -5.9], 'dimensions': [92, 30, 48],
        'crop_low': [-17.8, 11.2, -5.1], 'crop_high': [17.4, 23.2, 12.5],
        'owner_hint': [51, 4.01, 36], 'floor_color': 0x01608B35,
        'removed_names': ['Ground', 'Stone', 'Mine', 'PlankRoof'],
        'adaptations': ['Original version; only the upper chunk is retained.',
            'Ground plane, underground stone/cave/mine and plank roof are removed.',
            'The shaft/farm depressions and map-edge apron are filled to one standing floor.',
            'Upper tree foliage is cropped at 23.2 source meters; house, farm and tree retain source geometry.'],
    },
    'mira_hq': {
        'title': 'Among Us · Mira HQ', 'original_title': '[Alpha] Mira HQ (Among US)',
        'author': 'CapnSoda202', 'workshop_id': '2905630454',
        'mirror': 'https://dlcfun.com/en/teardown/alpha-mira-hq-among-us-mod',
        'archive': 'mira-hq.zip', 'mirror_filename': 'Alpha_Mira_HQ_Among_US.zip',
        'sha256': '36f3b034af618adba80b1a1cc2697dd74108bcfd59533996c05bff2f7a58385d',
        'directory': 'mira', 'scene': 'main.xml', 'scale': .6,
        'origin': [24.0, 45.7, 48.4], 'dimensions': [66, 20, 88],
        'crop_low': [25.2, 47.8, 49.6], 'crop_high': [62.4, 55.3, 100.0],
        'owner_hint': [37, 4.01, 43], 'floor_color': 0x01ECE9DC,
        'removed_names': [],
        'adaptations': ['Cafeteria, janitor room, adjoining eastern corridor and balcony are cropped from the actual map.',
            'The rest of the station is omitted; the elevated station is translated to a local ground plane.',
            'A continuous foundation fills small floor gaps and creates a narrow exterior apron.',
            'Overhead geometry is clipped at 55.3 source meters; polygon primitives are omitted, not replaced with invented walls.'],
    },
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def archive_url_from_page(page: str, filename: str) -> str:
    """Read a page-provided URL without logging its transient signed query."""
    if len(page) > 8_000_000:
        raise ValueError('Mirror page exceeds safety budget')
    chunks = re.findall(r'self\.__next_f\.push\((\[.*?\])\)', page)
    stream = ''.join(str(json.loads(chunk)[1]) for chunk in chunks
                     if len(json.loads(chunk)) > 1 and isinstance(json.loads(chunk)[1], str))
    name_position = stream.find(filename)
    if name_position < 0:
        raise ValueError('Pinned public archive is absent from mirror page')
    earlier = stream[:name_position]
    candidates = re.findall(r'"file":"(https://[^"\s]+)"', earlier)
    if not candidates:
        raise ValueError('No public archive URL before pinned filename')
    url = candidates[-1].replace('\\u0026', '&')
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https':
        raise ValueError('Archive must be HTTPS')
    return url


def download_archive(spec: dict) -> Path:
    """Use the public mirror page's own link; do not persist its signed query."""
    target = CACHE / spec['archive']
    if target.is_file() and sha256(target) == spec['sha256']:
        return target
    headers = {'User-Agent': 'Mozilla/5.0', 'Referer': spec['mirror']}
    request = urllib.request.Request(spec['mirror'], headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        page = response.read(8_000_001).decode('utf-8')
    url = archive_url_from_page(page, spec['mirror_filename'])
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
        data = response.read(8_000_001)
    if len(data) > 8_000_000 or hashlib.sha256(data).hexdigest() != spec['sha256']:
        raise ValueError('Archive differs from the pinned source; review before updating')
    CACHE.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return target


def extract_archive(spec: dict) -> tuple[Path, dict[str, str]]:
    archive = CACHE / spec['archive']
    if not archive.is_file() or sha256(archive) != spec['sha256']:
        raise ValueError(f"Missing/pin mismatch: {archive}; use --download")
    extraction = CACHE / ('minecraft' if spec['workshop_id'] == '2652603687' else 'mira')
    extraction.mkdir(parents=True, exist_ok=True)
    extraction = extraction.resolve()
    hashes = {}
    with zipfile.ZipFile(archive) as zipped:
        if len(zipped.infolist()) > 256 or sum(x.file_size for x in zipped.infolist()) > 16_000_000:
            raise ValueError('Archive exceeds member/expanded-size budget')
        for member in zipped.infolist():
            destination = (extraction / member.filename.replace('\\', '/')).resolve()
            if not destination.is_relative_to(extraction) or stat.S_ISLNK(member.external_attr >> 16):
                raise ValueError('Unsafe archive member')
            if member.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
                continue
            data = zipped.read(member)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            hashes[member.filename.replace('\\', '/')] = hashlib.sha256(data).hexdigest()
    return CACHE / spec['directory'], dict(sorted(hashes.items()))


def prepare_scene(source: Path, spec: dict):
    """Inline source prefabs, normalize author XML typos, retain brush data."""
    tree = ET.parse(source / spec['scene'])
    changes = {'removed_nodes': {}, 'rotation_normalizations': [], 'brushes': {}}
    brushes = []
    cache = {}
    def visit(parent, xml_path):
        for element in list(parent):
            name = element.get('name', '')
            if name in spec['removed_names']:
                parent.remove(element)
                changes['removed_nodes'][name] = changes['removed_nodes'].get(name, 0) + 1
                continue
            if element.tag == 'voxbox' and element.get('brush') == 'hole':
                # The retained Mira crop excludes these greenhouse cutouts.
                # Never interpret a subtractive editor helper as a solid box.
                parent.remove(element)
                changes['removed_nodes']['subtractive_hole_helper'] = changes['removed_nodes'].get('subtractive_hole_helper', 0) + 1
                continue
            if element.tag == 'instance':
                path = resolve_source(source, element.get('file', ''), xml_path)
                prefab = ET.parse(path).getroot()
                if prefab.tag != 'prefab' or len(prefab) != 1:
                    raise ValueError('Unsupported source prefab')
                # Existing collector discards the prefab anchor's transform.
                element.tag = 'group'
                element.attrib.pop('file', None)
                for child in prefab[0]:
                    element.append(child)
            rotation = element.get('rot')
            if rotation is not None:
                values = rotation.replace('\\', '').split()
                if len(values) == 1 and float(values[0]) == 0:
                    values = ['0', '0', '0']
                if len(values) == 2:
                    values.append('0')
                normalized = ' '.join(values)
                if len(values) != 3:
                    raise ValueError('Unsupported malformed rotation')
                if normalized != rotation:
                    changes['rotation_normalizations'].append({'name': name, 'before': rotation, 'after': normalized})
                    element.set('rot', normalized)
            if element.tag == 'voxbox':
                brush = None
                if element.get('brush'):
                    path = resolve_source(source, element.get('brush'), xml_path)
                    if path not in cache:
                        cache[path] = read_vox(path)
                    asset = cache[path]
                    instances = asset.instances(element.get('object', ''))
                    if len(instances) != 1:
                        raise ValueError('Brush requires exactly one source model')
                    model = instances[0].model
                    dense = np.zeros(model.size, dtype=np.uint32)
                    voxels = model.voxels[physical_voxel_mask(asset, instances[0])]
                    dense[tuple(voxels[:, :3].T)] = asset.palette[voxels[:, 3]]
                    colors, counts = np.unique(dense[dense != 0], return_counts=True)
                    if not len(colors):
                        raise ValueError('Empty source brush')
                    fallback = int(colors[np.argmax(counts)])
                    dense[dense == 0] = fallback
                    brush = dense
                    changes['brushes'][str(path.relative_to(source)).replace('\\', '/')] = sha256(path)
                brushes.append(brush)
            visit(element, xml_path)
    visit(tree.getroot(), source / spec['scene'])
    derived = source / '_survival_scene.xml'
    tree.write(derived, encoding='utf-8', xml_declaration=True)
    scene = collect_scene(source, derived.name)
    if len(brushes) != sum(item.kind == 'voxbox' for item in scene.items):
        raise ValueError('Brush/geometry order differs from source traversal')
    return scene, brushes, changes


def rasterize(scene, brushes, spec):
    width, height, depth = spec['dimensions']
    cells = np.zeros((depth, width, height), dtype=np.uint32)
    origin, low, high = [np.array(spec[key], float) for key in ('origin', 'crop_low', 'crop_high')]
    scale = spec['scale']
    stats = {'source_samples_in_crop': 0, 'source_vox_samples_in_crop': 0,
        'brush_samples_in_crop': 0, 'retained_primitives': 0, 'omitted_primitives': 0}
    box_index = 0
    for item in scene.items:
        brush = None
        if item.kind == 'voxbox':
            brush = brushes[box_index]
            box_index += 1
        item_low, item_high = item.bounds()
        if np.any(item_high < low) or np.any(item_low >= high):
            stats['omitted_primitives'] += 1
            continue
        if item.kind == 'vox':
            mask = physical_voxel_mask(item.vox_file, item.instance)
            points = item.centers()[mask]
            colors = item.vox_file.palette[item.instance.model.voxels[mask, 3]]
        elif item.kind == 'voxbox':
            if int(np.prod(item.size)) > 8_000_000:
                raise ValueError('Voxbox exceeds 8M source samples')
            indices = np.indices(item.size.astype(int)).reshape(3, -1).T
            points = transform_points((indices + .5) * .1, item.transform)
            if brush is None:
                colors = np.full(len(points), item.color, dtype=np.uint32)
            else:
                # Source MagicaVoxel +Z is up; Teardown +Y is up and Z=-MV.Y.
                # Texture offset/randomization/PBR are intentionally simplified.
                bx, by, bz = brush.shape
                colors = brush[indices[:, 0] % bx, (by - 1 - indices[:, 2]) % by, indices[:, 1] % bz]
        else:
            stats['omitted_primitives'] += 1
            continue
        keep = np.all((points >= low) & (points < high), axis=1)
        points, colors = points[keep], colors[keep]
        if not len(points):
            stats['omitted_primitives'] += 1
            continue
        stats['retained_primitives'] += 1
        stats['source_samples_in_crop'] += len(points)
        stats['source_vox_samples_in_crop'] += len(points) if item.kind == 'vox' else 0
        stats['brush_samples_in_crop'] += len(points) if brush is not None else 0
        pairs, counts = coarsen_points(points, colors, origin, scale, spec['dimensions'])
        indices = (pairs >> np.uint64(24)).astype(np.int64)
        # Per-primitive palette plurality; last source primitive tints overlaps.
        order = np.lexsort((pairs & np.uint64(0xFFFFFF), -counts, indices))
        sorted_indices = indices[order]
        first = np.r_[True, sorted_indices[1:] != sorted_indices[:-1]]
        selected = order[first]
        cells.reshape(-1)[indices[selected]] = (pairs[selected] & np.uint64(0xFFFFFF)).astype(np.uint32) | np.uint32(0x01000000)
    # Flat foundation is explicitly authored adaptation; geometry above stays source.
    floor = 4
    stats['source_cells_before_foundation'] = int(np.count_nonzero(cells))
    cells[:, :, :floor - 1] = np.uint32(spec['floor_color'])
    missing = cells[:, :, floor - 1] == 0
    stats['foundation_surface_cells_added'] = int(missing.sum())
    cells[:, :, floor - 1][missing] = np.uint32(spec['floor_color'])
    stats['solid_cells'] = int(np.count_nonzero(cells))
    stats['surface_cells'] = int(exposed_mask(cells != 0).sum())
    return cells, stats


def connected_floor(cells, start):
    depth, width, _ = cells.shape
    clear = ~np.any(cells[:, :, 4:7] != 0, axis=2)
    clear[0] = clear[-1] = False
    clear[:, 0] = clear[:, -1] = False
    origin = (int(start[0]), int(start[2]))
    if not clear[origin[1], origin[0]] or not valid_spawn(cells, start):
        raise ValueError('Unsafe owner spawn')
    seen = {origin}
    queue = deque([origin])
    while queue:
        x, z = queue.popleft()
        for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            next_point = x + dx, z + dz
            if 0 <= next_point[0] < width and 0 <= next_point[1] < depth and next_point not in seen and clear[next_point[1], next_point[0]]:
                seen.add(next_point)
                queue.append(next_point)
    return seen


def arena_metadata(cells, spec):
    depth, width, _ = cells.shape
    hint = np.array(spec['owner_hint'])
    safe = [(x + .5, 4.01, z + .5) for z in range(3, depth - 3) for x in range(3, width - 3)
            if valid_spawn(cells, (x + .5, 4.01, z + .5))]
    safe.sort(key=lambda point: float(np.sum((np.array(point) - hint) ** 2)))
    if not safe:
        raise ValueError('No clear standing surface')
    owner = list(safe[0])
    connected = connected_floor(cells, owner)
    candidates = [list(point) for point in safe if (int(point[0]), int(point[2])) in connected
                  and np.linalg.norm(np.array(point) - owner) >= 12.0]
    sectors = []
    for target in ((3, 3), (width-4, 3), (3, depth-4), (width-4, depth-4),
                   (width/2, 3), (width/2, depth-4), (3, depth/2), (width-4, depth/2)):
        choices = sorted(candidates, key=lambda point: (point[0]-target[0])**2 + (point[2]-target[1])**2)
        for choice in choices:
            if all(np.linalg.norm(np.array(choice)-sector) >= 6 for sector in sectors):
                sectors.append(choice)
                break
    if len(sectors) < 4:
        raise ValueError('Need at least four distinct connected distant spawn sectors')
    return {'title': spec['title'], 'supported': True, 'single_surface': True,
        'stacked_surfaces': False, 'authored': False, 'floor_y': 4.0,
        'owner_spawn': owner, 'player_spawn': owner, 'supply_point': owner,
        'supply_points': [owner], 'spawn_sectors': sectors, 'navigation_ceiling': cells.shape[2] - 3,
        'walk_speed': 3.2, 'breach_damage': 40.0, 'breach_windup_ticks': 45,
        'breach_cycle_ticks': 90, 'connected_floor_columns': len(connected)}


def render_preview(path, cells):
    """Orthographic pixel render of the actual converted cells; no source images."""
    occupied = cells != 0
    depth, width, height = cells.shape
    canvas = Image.new('RGB', (1000, 720), (24, 30, 38))
    draw = ImageDraw.Draw(canvas)
    unit = min(880 / (width + depth), 510 / ((width + depth) * .48 + height * 1.15))
    def project(x, y, z):
        return (500 + (x-z + (depth-width)/2) * unit,
                115 + (x+z) * unit * .48 - (y-4) * unit * 1.15)
    positions = np.argwhere(occupied & exposed_mask(occupied))
    positions = sorted(positions.tolist(), key=lambda p: (p[0] + p[1], p[2]))
    for z, x, y in positions:
        value = int(cells[z, x, y])
        rgb = tuple((value >> shift) & 255 for shift in (16, 8, 0))
        if x == width-1 or not occupied[z, x+1, y]:
            draw.polygon([project(x+1,y,z),project(x+1,y,z+1),project(x+1,y+1,z+1),project(x+1,y+1,z)], fill=tuple(int(c*.7) for c in rgb))
        if z == depth-1 or not occupied[z+1, x, y]:
            draw.polygon([project(x,y,z+1),project(x+1,y,z+1),project(x+1,y+1,z+1),project(x,y+1,z+1)], fill=tuple(int(c*.84) for c in rgb))
        if y == height-1 or not occupied[z, x, y+1]:
            draw.polygon([project(x,y+1,z),project(x+1,y+1,z),project(x+1,y+1,z+1),project(x,y+1,z+1)], fill=rgb)
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.resize((600, 432), Image.Resampling.LANCZOS).save(path, optimize=True)


def build_map(key, download=False):
    spec = MAPS[key]
    if download:
        download_archive(spec)
    source, hashes = extract_archive(spec)
    scene, brushes, changes = prepare_scene(source, spec)
    cells, stats = rasterize(scene, brushes, spec)
    arena = arena_metadata(cells, spec)
    provenance = {'original_title': spec['original_title'], 'author': spec['author'],
        'source_url': 'https://steamcommunity.com/sharedfiles/filedetails/?id=' + spec['workshop_id'],
        'download_page': spec['mirror'], 'downloaded_utc_date': '2026-10-12',
        'archive_sha256': spec['sha256'], 'source_files_sha256': hashes,
        'license': 'No separate redistribution/adaptation license found in source archive or inspected pages. Original author and underlying game rights retained; not repository MIT.',
        'scripts_executed': False}
    metadata = {'format': 1, 'title': spec['title'], 'dimensions': spec['dimensions'],
        'spawn': arena['owner_spawn'], 'yaw_radians': 0.0, 'pitch_radians': 0.0,
        'team_spawns': [], 'water_enabled': False, 'survival_arena': arena,
        'conversion': {'pipeline': 'pinned Teardown XML/VOX → cropped colored survival blocks',
            'meters_per_block': spec['scale'], 'origin_meters': spec['origin'],
            'crop_source_meters': [spec['crop_low'], spec['crop_high']], 'statistics': stats,
            'adaptations': spec['adaptations'], 'xml_adaptations': changes,
            'limitations': ['Static source geometry only; Lua/game logic/AI/audio/lights/joints omitted.',
                'Brush colors tiled from actual VOX palette; brush offset, PBR, transparency and texture randomization simplified.',
                'Thin features coarsened; voxagons/polygons unsupported and reported.',
                'Foundation added for one supported surface; native/render/input checks are separate acceptance.'],
            'omitted_nodes': scene.report.get('omitted_nodes', {})}, 'provenance': provenance}
    output = ROOT / f'game/assets/maps/survival_{key}.bfmap'
    sizes = write_bfmap(output, cells, metadata)
    preview = ROOT / f'game/assets/ui/menu/map_survival_{key}.png'
    render_preview(preview, cells)
    manifest = {'map_id': key, 'dimensions': spec['dimensions'], 'arena': arena,
        'statistics': stats, 'output_sha256': sha256(output), 'preview_sha256': sha256(preview), **sizes}
    (CACHE / f'{key}-conversion.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    write_provenance(output.with_name(output.stem + '_provenance.md'), key, metadata, manifest)
    print(json.dumps(manifest, ensure_ascii=False))
    return manifest


def write_provenance(path, key, metadata, manifest):
    spec, source = MAPS[key], metadata['provenance']
    text = f"# {spec['title']} — source and adaptation\n\n"
    text += f"Real downloaded Teardown community map: **{spec['original_title']}**, by **{spec['author']}**.\n\n"
    text += f"- Author/source page: {source['source_url']}\n- Public download page: {source['download_page']}\n"
    text += f"- Download date: {source['downloaded_utc_date']} UTC\n- Raw archive: ignored `.cache/survival-map-sources/{spec['archive']}`\n"
    text += f"- Archive SHA-256: `{source['archive_sha256']}`\n- BFM SHA-256: `{manifest['output_sha256']}`\n"
    text += f"- Preview SHA-256: `{manifest['preview_sha256']}`; code-rendered from the converted map.\n\n"
    text += source['license'] + '\n\nThis record attributes the source and records the adaptation; it does not assert an author-granted reuse license. The author/title come from the pinned archive’s `info.txt`, and the Workshop identity from `id.txt`. Minecraft rights belong to Mojang/Microsoft; Among Us rights belong to Innersloth. No affiliation is claimed. The same source rights apply to the geometry-derived preview.\n\n'
    text += '## Geometry changes\n\n' + '\n'.join('- ' + item for item in spec['adaptations']) + '\n\n'
    text += f"Dimensions {spec['dimensions']} (X/Y/Z); {spec['scale']} source meters per game block. "
    text += f"{manifest['statistics']['retained_primitives']} original primitives and {manifest['statistics']['source_samples_in_crop']:,} occupied source samples retained before coarsening. "
    text += f"{manifest['statistics']['brush_samples_in_crop']:,} samples use actual source VOX brush colors. "
    text += f"{len(manifest['arena']['spawn_sectors'])} supported emergence sectors share {manifest['arena']['connected_floor_columns']} clear connected floor columns.\n\n"
    text += 'No downloaded code is executed. Lua, sounds, animated actors and mission logic are not imported. Source voxagons/polygons are omitted; source materials become opaque destructible colored blocks. Source editor brush phase/offset and PBR are simplified. Derived XML repairs are recorded inside BFM metadata.\n\n'
    text += '## Reproduction\n\n`python tools/prepare_survival_maps.py --download --map ' + key + '`\n\n'
    text += 'The download helper uses the public page-provided archive URL without retaining signed query parameters, then verifies the pinned SHA-256. A changed archive requires explicit review before the pin is updated. ZIP paths, symlinks, member count and expanded bytes are bounded.\n\n'
    text += '## Source file SHA-256\n\n' + '\n'.join(f'- `{name}`: `{digest}`' for name, digest in source['source_files_sha256'].items()) + '\n'
    path.write_text(text, encoding='utf-8')


def read_bfmap(path):
    data = Path(path).read_bytes()
    if data[:4] != b'BFM1':
        raise ValueError('Invalid map header')
    json_size, raw_size, compressed_size = struct.unpack('<III', data[4:16])
    if len(data) != 16 + json_size + compressed_size:
        raise ValueError('Map byte lengths differ')
    metadata = json.loads(data[16:16+json_size])
    raw = zlib.decompress(data[16+json_size:])
    if len(raw) != raw_size:
        raise ValueError('Uncompressed map byte length differs')
    width, height, depth = metadata['dimensions']
    return np.frombuffer(raw, dtype='>u4').astype(np.uint32).reshape(depth, width, height), metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true')
    parser.add_argument('--map', choices=MAPS)
    options = parser.parse_args()
    for key in ([options.map] if options.map else MAPS):
        build_map(key, options.download)


if __name__ == '__main__':
    main()
