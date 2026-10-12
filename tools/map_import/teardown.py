"""Convert a local Teardown XML/VOX scene to Blockfield's BFM1 packed map.

No Lua is executed. A content-pinned adapter reconstructs Dust2's ground.lua;
other scripts, lights, joints, water and ropes are counted in the report.
Usage: python tools/map_import/teardown.py SOURCE --output OUTPUT.bfmap
       --scene de_dust2.xml --meters-per-block .6
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, field
import hashlib
import json
import math
from pathlib import Path
import time
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

try:
    from .teardown_vox import read_vox, VoxFile, VoxInstance
    from .voxelize_helpers import write_bfmap, write_topdown_png, exposed_mask
except ImportError:
    from teardown_vox import read_vox, VoxFile, VoxInstance
    from voxelize_helpers import write_bfmap, write_topdown_png, exposed_mask

GROUND_SCRIPT_SHA256 = "44070d85fc08309a745de72a3abd0f162c1c4c44d5aca011d28cb3e803d70467"
MV_TO_TEARDOWN = np.array([[1., 0., 0.], [0., 0., 1.], [0., -1., 0.]])
SOURCE_VOXEL_METERS = .1


def vector(text="0 0 0"):
    result = np.asarray([float(value) for value in text.split()], dtype=np.float64)
    if result.shape != (3,) or not np.isfinite(result).all():
        raise ValueError("Expected three finite coordinates")
    return result


def rotation_matrix(angles):
    """Teardown's documented NASA Euler convention: Ry(y) Rz(z) Rx(x)."""
    x, y, z = np.radians(vector(angles) if isinstance(angles, str) else np.asarray(angles, dtype=np.float64))
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return ry @ rz @ rx


def compose_transform(parent, element):
    local = np.eye(4)
    local[:3, :3] = rotation_matrix(element.get("rot", "0 0 0"))
    local[:3, 3] = vector(element.get("pos", "0 0 0"))
    return np.asarray(parent, dtype=np.float64) @ local


def transform_points(points, transform):
    return np.asarray(points) @ transform[:3, :3].T + transform[:3, 3]


def resolve_source(root, path, scene_path=None):
    root = Path(root).resolve()
    if path.startswith("MOD/"):
        candidate = root / path[4:]
    elif path.startswith("LEVEL/") and scene_path is not None:
        candidate = Path(scene_path).parent / path[6:]
    else:
        candidate = root / path
    resolved = candidate.resolve()
    if not resolved.is_relative_to(root):
        raise ValueError(f"Source reference escapes mod root: {path}")
    if not resolved.is_file():
        raise ValueError(f"Missing source asset: {path}")
    return resolved


def packed_rgb(channels):
    values = np.clip(np.rint(np.asarray(channels) * 255), 0, 255).astype(np.uint32)
    return int(0x01000000 | (values[0] << 16) | (values[1] << 8) | values[2])


def physical_voxel_mask(asset: VoxFile, instance: VoxInstance):
    """Exclude Teardown's reserved slot255 bounds/hole helpers, not red RGB.

    The official Teardown palette's final slot is red and its NOTE row reserved.
    Dust2 uses these at opposite model corners to hold the intended size/pivot.
    Lossless VOX decoding keeps them; only the Teardown map adapter filters them.
    """
    return asset.material_indices[instance.model.voxels[:, 3]] != 255


@dataclass
class SceneItem:
    kind: str
    transform: np.ndarray
    vox_file: VoxFile | None = None
    instance: VoxInstance | None = None
    size: np.ndarray | None = None
    color: int = 0
    image: np.ndarray | None = None
    path: str = ""

    def centers(self):
        if self.kind != "vox":
            raise ValueError("Only VOX items have explicit centers")
        return transform_points(self.instance.centers() @ MV_TO_TEARDOWN.T * SOURCE_VOXEL_METERS, self.transform)

    def bounds(self):
        if self.kind == "vox":
            half = np.asarray(self.instance.model.size) // 2
            size = np.asarray(self.instance.model.size)
            points = np.array([[x, y, z] for x in (-half[0], size[0]-half[0]) for y in (-half[1], size[1]-half[1]) for z in (-half[2], size[2]-half[2])])
            points = (points @ self.instance.rotation.T + self.instance.translation) @ MV_TO_TEARDOWN.T * SOURCE_VOXEL_METERS
        else:
            size = self.size if self.kind == "voxbox" else np.array([self.image.shape[1], int(self.image[:, :, 0].max())+1, self.image.shape[0]])
            points = np.array([[x, y, z] for x in (0, size[0]*.1) for y in (0, size[1]*.1) for z in (0, size[2]*.1)])
        points = transform_points(points, self.transform)
        return points.min(axis=0), points.max(axis=0)


@dataclass
class SceneData:
    root: Path
    scene_path: Path
    items: list[SceneItem] = field(default_factory=list)
    spawns: list[dict] = field(default_factory=list)
    report: dict = field(default_factory=dict)
    title: str = "Teardown map"


def collect_scene(source_root, scene="de_dust2.xml") -> SceneData:
    source_root = Path(source_root).resolve()
    scene_path = resolve_source(source_root, scene)
    scene_xml = ET.parse(scene_path).getroot()
    if scene_xml.tag != "scene":
        raise ValueError("Map input must be a Teardown scene XML")
    result = SceneData(source_root, scene_path)
    counts, omitted, hidden = Counter(), Counter(), Counter()
    layers = {layer.get("name"): layer.get("visible", "true") != "false" for layer in scene_xml.findall("./layers/layer")}
    cache, file_hashes = {}, {}
    info_path = source_root / "info.txt"
    provenance = {}
    if info_path.is_file():
        for line in info_path.read_text(encoding="utf-8-sig").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                provenance[key.strip()] = value.strip()
        result.title = provenance.get("name", result.title)

    def digest(path):
        file_hashes[str(path.relative_to(source_root)).replace("\\", "/")] = hashlib.sha256(path.read_bytes()).hexdigest()

    digest(scene_path)
    if info_path.is_file():
        digest(info_path)
    all_source_hashes = {str(path.relative_to(source_root)).replace("\\", "/"): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(source_root.rglob("*")) if path.is_file()}

    def visit(element, parent, xml_path, stack=(), active=True, prefab_anchor=False, dynamic=False, team=""):
        tag = element.tag
        layer = element.get("layer", "")
        active = active and layers.get(layer, True)
        if not active:
            hidden.update(node.tag for node in element.iter())
            return
        counts[tag] += 1
        # A prefab's top object records its editor placement; instance placement
        # replaces that anchor, while all internal child offsets stay relative.
        current = parent if prefab_anchor or tag in ("vertex", "layers", "layer", "parameters") else compose_transform(parent, element)
        dynamic = dynamic or element.get("dynamic") == "true" or tag in ("vehicle", "wheel") or element.get("prop") == "true"
        team = element.get("name", "") if tag == "group" and layer.startswith("spawn.") else team
        if any(key in element.attrib for key in ("scale", "mirrorx", "mirrory", "mirrorz")) and tag in ("vox", "voxbox"):
            raise ValueError(f"Unsupported scaled/mirrored primitive: {element.attrib}")
        if tag == "instance":
            path = resolve_source(source_root, element.get("file", ""), xml_path)
            if path in stack or len(stack) > 32:
                raise ValueError("Cyclic or excessive XML prefab nesting")
            prefab = ET.parse(path).getroot()
            if prefab.tag != "prefab" or len(prefab) != 1:
                raise ValueError("Prefab needs one replaceable top-level anchor")
            digest(path)
            visit(prefab[0], current, path, stack+(path,), active, True, dynamic, team)
            return
        if tag == "vox":
            if element.get("collide") == "false":
                omitted["noncolliding_vox"] += 1
                return
            path = resolve_source(source_root, element.get("file", ""), xml_path)
            if path not in cache:
                cache[path] = read_vox(path)
                digest(path)
            asset = cache[path]
            instances = asset.instances(element.get("object", ""))
            for instance in instances:
                if len(instance.model.voxels):
                    result.items.append(SceneItem("vox", current, asset, instance, path=str(path.relative_to(source_root))))
            if dynamic:
                counts["dynamic_vox_frozen"] += 1
        elif tag == "voxbox":
            size = vector(element.get("size", "0 0 0"))
            if np.any(size <= 0) or np.any(size > 4096) or np.any(size != np.floor(size)):
                raise ValueError("Invalid voxbox dimensions")
            result.items.append(SceneItem("voxbox", current, size=size, color=packed_rgb(vector(element.get("color", "1 1 1")))))
        elif tag == "voxscript":
            path = resolve_source(source_root, element.get("file", ""), xml_path)
            digest(path)
            if hashlib.sha256(path.read_bytes()).hexdigest() == GROUND_SCRIPT_SHA256:
                if not np.allclose(current[:3, :3], np.eye(3), atol=1e-8):
                    raise ValueError("Dust2 ground adapter requires unrotated ground")
                parameters = element.find("parameters")
                if parameters is None:
                    raise ValueError("Ground adapter requires heightmap parameters")
                image_path = resolve_source(source_root, parameters.get("file", ""), xml_path)
                digest(image_path)
                with Image.open(image_path) as image:
                    if max(image.size) > 4096:
                        raise ValueError("Heightmap image exceeds4096 per axis")
                    pixels = np.asarray(image.convert("RGB")).copy()
                tile_size = int(parameters.get("tilesize", "62"))
                if not 1 <= tile_size <= 256:
                    raise ValueError("Heightmap tile size outside1..256")
                result.items.append(SceneItem("ground", current, image=pixels, path=str(image_path.relative_to(source_root))))
                counts["adapted_ground_script"] += 1
            else:
                omitted["unsupported_voxscript:" + str(path.relative_to(source_root))] += 1
            return
        elif tag == "spawnpoint":
            direction = current[:3, :3] @ np.array([0., 0., -1.])
            result.spawns.append({"source_position": current[:3, 3].tolist(), "yaw_radians": math.atan2(-direction[0], -direction[2]), "team": team or "default"})
        elif tag in ("script", "light", "rope", "joint", "water", "environment", "postprocessing", "trigger", "location", "boundary", "vertex"):
            omitted[tag] += 1
        elif tag not in ("scene", "prefab", "group", "body", "vehicle", "wheel", "layers", "layer", "parameters"):
            omitted["unsupported_node:" + tag] += 1
        for child in element:
            visit(child, current, xml_path, stack, active, False, dynamic, team)

    visit(scene_xml, np.eye(4), scene_path)
    if not result.items:
        raise ValueError("Scene contains no supported visible geometry")
    helper_per_asset = {str(path.relative_to(source_root)).replace("\\", "/"): sum(int((asset.material_indices[model.voxels[:, 3]] == 255).sum()) for model in asset.models) for path, asset in cache.items()}
    result.report = {"xml_counts": dict(counts), "omitted_nodes": dict(omitted), "hidden_nodes": dict(hidden), "xml_visible_layers": sorted(key for key, value in layers.items() if value), "source_files_sha256": dict(sorted(file_hashes.items())), "all_source_files_sha256": all_source_hashes, "provenance": provenance, "vox_assets": len(cache), "vox_models": sum(len(asset.models) for asset in cache.values()), "stored_asset_voxels": sum(len(model.voxels) for asset in cache.values() for model in asset.models), "reserved255_helper_voxels_per_asset": {key: value for key, value in sorted(helper_per_asset.items()) if value}, "reserved255_asset_helper_voxels": sum(helper_per_asset.values()), "vox_imap_files": sum("IMAP" in asset.chunks for asset in cache.values()), "voxel_instances": sum(item.kind == "vox" for item in result.items)}
    return result


def coarsen_points(points, colors, origin, meters_per_block, dimensions):
    """Return sorted canonical cell-index/color votes; no bounding-box fill."""
    points = np.asarray(points, dtype=np.float64)
    cells = np.floor((points - np.asarray(origin)) / meters_per_block + 1e-9).astype(np.int64)
    dimensions = np.asarray(dimensions)
    if not np.all((cells >= 0) & (cells < dimensions)):
        raise ValueError("Source samples exceed computed map bounds")
    index = cells[:, 1] + dimensions[1] * (cells[:, 0] + dimensions[0] * cells[:, 2])
    colors = np.broadcast_to(np.asarray(colors, dtype=np.uint32), (len(points),))
    pairs = (index.astype(np.uint64) << np.uint64(24)) | (colors.astype(np.uint64) & np.uint64(0xffffff))
    return np.unique(pairs, return_counts=True)


def valid_spawn(cells, feet):
    """Mirror BlockfieldMap.is_valid_spawn's full body and corner support."""
    depth, width, height = cells.shape
    point = np.asarray(feet, dtype=np.float64)
    if point.shape != (3,) or not np.isfinite(point).all():
        return False
    lower, upper = point - [.45, 0, .45], point + [.45, 2.7, .45]
    if lower[0] < 0 or lower[2] < 0 or lower[1] < 1 or np.any(upper > [width, height, depth]):
        return False
    minimum, maximum = np.floor(lower + .0001).astype(int), np.floor(upper - .0001).astype(int)
    if np.any(cells[minimum[2]:maximum[2]+1, minimum[0]:maximum[0]+1, minimum[1]:maximum[1]+1]):
        return False
    for dx in (-.4499, .4499):
        for dz in (-.4499, .4499):
            x, y, z = np.floor(point + [dx, -.05, dz]).astype(int)
            if not cells[z, x, y]:
                return False
    return True


def choose_spawn(cells, requested):
    """Nearest supported, cell-centered standing point; never carve terrain."""
    requested = np.asarray(requested, dtype=np.float64)
    occupied = cells != 0
    z, x, y = np.where(occupied[:, :, :-3] & ~occupied[:, :, 1:-2] & ~occupied[:, :, 2:-1] & ~occupied[:, :, 3:])
    points = np.column_stack((x+.5, y+1.01, z+.5))
    if not len(points):
        raise ValueError("Converted map has no supported standing spawn")
    order = np.argsort(np.sum((points-requested)**2, axis=1), kind="stable")
    for index in order:
        if valid_spawn(cells, points[index]):
            return points[index].tolist(), int(len(points))
    raise ValueError("Converted map has no clear 0.9x2.7 standing spawn")


GROUND_COLORS = {32: (.475, .329, .294), 48: (.514, .467, .404), 64: (.855, .773, .667), 80: (.851, .804, .741), 96: (.357, .345, .329), 112: (.588, .478, .337), 128: (.737, .671, .561), 144: (.639, .580, .498)}


def rasterize_ground(item, cells, origin, meters_per_block):
    """Conservative heightmap columns, reproducing source red/blue semantics.

    A coarser x/z footprint keeps the highest occupied fine column; sand fills
    beneath that column and its highest source top receives plurality RGB.
    """
    image = item.image
    r, b = image[:, :, 0], image[:, :, 2]
    extra_top = np.isin(b, list(GROUND_COLORS))
    fine_height = r.astype(np.int32) + extra_top
    z, x = np.where(fine_height > 0)
    points = np.column_stack((x+.5, fine_height[z, x]-.5, z+.5))*.1 + item.transform[:3, 3]
    grid = np.floor((points-np.asarray(origin))/meters_per_block+1e-9).astype(int)
    base_y = max(0, int(math.floor((item.transform[1, 3]-origin[1]) / meters_per_block + 1e-9)))
    tops = np.full(cells.shape[:2], -1, dtype=np.int32)
    np.maximum.at(tops, (grid[:, 2], grid[:, 0]), grid[:, 1])
    sand = packed_rgb(GROUND_COLORS[128])
    for y in range(base_y, int(tops.max())+1):
        cells[:, :, y][tops >= y] = sand
    colors = np.full(len(x), sand, dtype=np.uint32)
    for code, rgb in GROUND_COLORS.items():
        colors[b[z, x] == code] = packed_rgb(rgb)
    highest = grid[:, 1] == tops[grid[:, 2], grid[:, 0]]
    pairs, counts = coarsen_points(points[highest], colors[highest], origin, meters_per_block, [cells.shape[1], cells.shape[2], cells.shape[0]])
    order = np.lexsort((pairs & np.uint64(0xffffff), -counts, pairs >> np.uint64(24)))
    indices = (pairs[order] >> np.uint64(24)).astype(np.int64)
    unique, first = np.unique(indices, return_index=True)
    cells.ravel()[unique] = np.uint32(0x01000000) | (pairs[order][first] & np.uint64(0xffffff)).astype(np.uint32)
    return {"pixels": int(image.shape[0]*image.shape[1]), "source_ground_voxels": int(fine_height.sum()), "unrecognized_blue_top_pixels": int((~extra_top).sum()), "coarse_ground_columns": int((tops >= 0).sum())}


def voxelize_scene(scene: SceneData, meters_per_block=.6):
    if not math.isfinite(meters_per_block) or not .1 <= meters_per_block <= 4:
        raise ValueError("meters-per-block must lie in0.1..4")
    bounds = [item.bounds() for item in scene.items]
    low = np.min([entry[0] for entry in bounds], axis=0)
    high = np.max([entry[1] for entry in bounds], axis=0)
    # Horizontal margin plus two permanent bottom support layers. The source's
    # original positions remain recoverable through conversion.origin_meters.
    origin = np.floor(low/meters_per_block)*meters_per_block - np.array([1., 2., 1.])*meters_per_block
    dimensions = np.ceil((high-origin)/meters_per_block-1e-9).astype(int) + [1, 4, 1]
    if np.any(dimensions < 1) or np.any(dimensions > [512, 64, 512]):
        raise ValueError(f"Converted dimensions {dimensions.tolist()} exceed512x64x512; increase meters-per-block")
    cells = np.zeros((dimensions[2], dimensions[0], dimensions[1]), dtype=np.uint32)
    ground_stats = []
    # Terrain is the base; structures retain their source palette when sampled
    # cells overlap the ground after quantization.
    for item in scene.items:
        if item.kind == "ground":
            ground_stats.append(rasterize_ground(item, cells, origin, meters_per_block))
    votes = Counter()
    source_samples = 0
    reserved_helpers = 0
    for number, item in enumerate(scene.items):
        if item.kind == "ground":
            continue
        if item.kind == "vox":
            mask = physical_voxel_mask(item.vox_file, item.instance)
            reserved_helpers += int((~mask).sum())
            points = item.centers()[mask]
            colors = item.vox_file.palette[item.instance.model.voxels[mask, 3]]
        else:
            # One thin floor primitive in Dust2. This bounded fine rasterization
            # also supports general small XML voxel boxes without Lua execution.
            if int(np.prod(item.size)) > 8_000_000:
                raise ValueError("voxbox exceeds8M sample safety limit")
            z, x, y = np.indices((int(item.size[2]), int(item.size[0]), int(item.size[1])))
            points = transform_points(np.column_stack((x.ravel()+.5, y.ravel()+.5, z.ravel()+.5))*.1, item.transform)
            colors = item.color
        source_samples += len(points)
        keys, counts = coarsen_points(points, colors, origin, meters_per_block, dimensions)
        votes.update(dict(zip(keys.tolist(), counts.tolist())))
        if number % 100 == 0:
            print(json.dumps({"stage": "voxelizing", "items": number, "total": len(scene.items), "source_samples": source_samples}), flush=True)
    unique_sample_cells = 0
    multicolor_cells = 0
    if votes:
        pairs = np.fromiter(votes.keys(), dtype=np.uint64)
        counts = np.fromiter(votes.values(), dtype=np.int64)
        order = np.lexsort((pairs & np.uint64(0xffffff), -counts, pairs >> np.uint64(24)))
        indices = (pairs[order] >> np.uint64(24)).astype(np.int64)
        unique, first = np.unique(indices, return_index=True)
        unique_sample_cells = int(len(unique))
        multicolor_cells = int(np.count_nonzero(np.diff(np.r_[first, len(indices)]) > 1))
        cells.ravel()[unique] = np.uint32(0x01000000) | (pairs[order][first] & np.uint64(0xffffff)).astype(np.uint32)
    cells[:, :, :2] = packed_rgb((.42, .39, .35))
    requested = scene.spawns or [{"source_position": ((low+high)/2).tolist(), "yaw_radians": 0., "team": "default"}]
    adjusted = []
    safe_count = 0
    for spawn in requested:
        desired = (np.asarray(spawn["source_position"])-origin)/meters_per_block
        selected, safe_count = choose_spawn(cells, desired)
        adjusted.append({**spawn, "requested_grid": desired.tolist(), "spawn": selected, "adjustment_meters": float(np.linalg.norm((np.asarray(selected)-desired)*meters_per_block))})
    limitations = ["Static destructible voxel map only: Teardown scripts, vehicles, joints, physics materials and objectives are not ported.", "XML editor visible layers are selected; hidden scene variants and hidden MagicaVoxel objects are omitted.", "Prefab authored top-level placement is replaced by XML instance placement; named VOX object layout offsets are reset to a horizontal-center/bottom anchor.", "Occupied source voxel centers are unioned into coarse cells. Thin decoration, foliage and doors can become one full block; openings can narrow by up to one block per side.", "Per-cell plurality retains a source RGB, including solid black and interior colors. Equal counts choose the smallest RGB; source PBR/glass/emission/texture overlays are omitted.", "Teardown reserved material/display slot255 helper voxels are excluded after IMAP material-index mapping. These preserve model bounds/pivots in source; coarse negative-space subtraction is not performed.", "Dust2 ground.lua is reconstructed only after its exact SHA256 matches the pinned adapter; Lua is never evaluated. Coarse ground footprints retain the maximum fine-column height.", "Ropes, source lights, water, scripted effects and noncolliding voxel decoration are omitted and counted explicitly.", "Two continuous bottom support layers are added for Blockfield's collapse rules.", "Spawn is relocated to the nearest supported full0.9x2.7 standing position. Whole-map passage connectivity is not established."]
    metadata = {"format": 1, "title": scene.title + " · Teardown conversion", "dimensions": dimensions.tolist(), "spawn": adjusted[0]["spawn"], "yaw_radians": adjusted[0]["yaw_radians"], "pitch_radians": 0., "team_spawns": adjusted, "water_enabled": False, "conversion": {"pipeline": "local Teardown XML/MagicaVoxel → packed colored blocks", "meters_per_block": meters_per_block, "source_voxel_meters": .1, "origin_meters": origin.tolist(), "source_to_grid": "(Teardown Y-up meters-origin)/meters_per_block", "magica_to_teardown": "(x,z,-y)*0.1", "occupancy": "union of occupied source voxel-center bins; max-height ground columns", "solid_cells": int(np.count_nonzero(cells)), "surface_cells": int(exposed_mask(cells != 0).sum()), "source_voxel_samples": source_samples, "safe_standing_candidates": safe_count, "limitations": limitations}, "provenance": scene.report.get("provenance", {})}
    report = {**scene.report, "source_scene": str(scene.scene_path), "source_bounds_meters": [low.tolist(), high.tolist()], "ground": ground_stats, "source_spawn_adjustments": adjusted, "dimensions": dimensions.tolist(), "origin_meters": origin.tolist(), "meters_per_block": meters_per_block, "solid_cells": metadata["conversion"]["solid_cells"], "surface_cells": metadata["conversion"]["surface_cells"], "source_voxel_samples": source_samples, "reserved255_placed_helper_voxels_excluded": reserved_helpers, "unique_coarse_sample_cells": unique_sample_cells, "multicolor_coarse_cells": multicolor_cells, "source_samples_merged_by_coarsening": source_samples-unique_sample_cells, "cropped_source_cells": 0, "limitations": limitations}
    return cells, metadata, report


def convert_map(source, output, scene="de_dust2.xml", meters_per_block=.6):
    started = time.perf_counter()
    source = Path(source).resolve()
    output = Path(output).resolve()
    if output.is_relative_to(source):
        raise ValueError("Converted output must stay outside the source mod directory")
    scene_data = collect_scene(source, scene)
    cells, metadata, report = voxelize_scene(scene_data, meters_per_block)
    sizes = write_bfmap(output, cells, metadata)
    preview = output.with_name(output.stem+"-topdown.png")
    write_topdown_png(preview, cells, magnification=4)
    report.update(metadata=metadata, output=str(output), topdown_preview=str(preview), **sizes, elapsed_seconds=round(time.perf_counter()-started, 3))
    report["output_sha256"] = hashlib.sha256(output.read_bytes()).hexdigest()
    report_path = output.with_suffix(".report.json")
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--scene", default="de_dust2.xml")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--meters-per-block", type=float, default=.6)
    args = parser.parse_args()
    report = convert_map(args.source, args.output, args.scene, args.meters_per_block)
    print(json.dumps({key: report[key] for key in ("output", "output_sha256", "dimensions", "solid_cells", "file_bytes", "elapsed_seconds")}), flush=True)


if __name__ == "__main__":
    main()
