"""Reload a saved Blender scene and export its colors + BSP solids to Blockfield.

blender --background csgo_mirage.blend --python tools/map_import/blender_voxelize.py
        -- --output csgo_mirage.bfmap --units-per-block 28

The original solid BSP distinguishes buildings from their empty rooms. Meshes
evaluated from this actual .blend provide UV color samples and static prop shells.
Changing brush geometry in Blender requires updating its BSP/collision metadata;
this first importer does not regenerate a BSP after arbitrary Blender mesh edits.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import time

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from voxelize_helpers import (classify_solid, constrain_to_columns, exposed_mask, grid_to_source,
                              safe_standing_points, source_to_grid, write_bfmap, write_topdown_png)


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--units-per-block", type=float, default=28)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--no-props", action="store_true")
    parser.add_argument("--render-spawn", type=Path)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])


def progress(stage, **values):
    print(json.dumps({"stage": stage, **values}, ensure_ascii=False), flush=True)


class SurfaceSampler:
    def __init__(self):
        self.vertices, self.triangles, self.uvs, self.materials, self.props, self.structural = [], [], [], [], [], []
        self.images = {}
        self.ignored_objects = []
        graph = bpy.context.evaluated_depsgraph_get()
        for obj in bpy.context.scene.objects:
            if obj.type != "MESH":
                continue
            if obj.get("blockfield_excluded", False):
                self.ignored_objects.append(obj.name)
                continue
            evaluated = obj.evaluated_get(graph)
            mesh = evaluated.to_mesh()
            mesh.calc_loop_triangles()
            uv_data = mesh.uv_layers.active.data if mesh.uv_layers.active else None
            offset = len(self.vertices)
            self.vertices.extend([evaluated.matrix_world @ vertex.co for vertex in mesh.vertices])
            for triangle in mesh.loop_triangles:
                material = mesh.materials[triangle.material_index] if len(mesh.materials) > triangle.material_index else None
                if material and material.get("blockfield_excluded", False):
                    continue
                indices = [offset + index for index in triangle.vertices]
                uvs = [list(uv_data[loop].uv) for loop in triangle.loops] if uv_data else [[0, 0]] * 3
                index = len(self.triangles)
                self.triangles.append(indices)
                self.uvs.append(np.asarray(uvs, dtype=np.float64))
                self.materials.append(material)
                if obj.get("blockfield_kind") == "bsp" and obj.get("blockfield_solid", True):
                    self.structural.append(index)
                if obj.get("blockfield_kind") == "mdl" or obj.get("blockfield_classname") == "func_illusionary":
                    self.props.append(index)
            evaluated.to_mesh_clear()
        if not self.triangles:
            raise ValueError("Saved Blender scene has no visible geometry")
        self.array = np.asarray(self.vertices, dtype=np.float64)
        self.bvh = BVHTree.FromPolygons(self.vertices, self.triangles, all_triangles=True)

    def structural_envelope(self, dimensions, origin, scale):
        """Finite 2D upper bounds from visible structural BSP, never sky/tools.

        Downward rays obtain roofs and ground. Vertical-only wall silhouettes
        supplement rays so walls without a visible top polygon retain thickness.
        A one-cell column margin accounts for center sampling of thin source walls.
        """
        if not self.structural:
            raise ValueError("No visible solid BSP geometry to bound original collision")
        width, height, depth = map(int, dimensions)
        polygons = [self.triangles[index] for index in self.structural]
        bvh = BVHTree.FromPolygons(self.vertices, polygons, all_triangles=True)
        top = np.zeros((depth, width), dtype=np.float64)
        for z in range(depth):
            for x in range(width):
                source_xy = grid_to_source([x + .5, height + 1, z + .5], origin, scale)
                location, normal, index, distance = bvh.ray_cast(Vector(source_xy), Vector((0, 0, -1)), (height + 4) * scale)
                if index is not None:
                    top[z, x] = max(0, (location.z - origin[1]) / scale)
        for index in self.structural:
            source_vertices = self.array[self.triangles[index]]
            normal = np.cross(source_vertices[1] - source_vertices[0], source_vertices[2] - source_vertices[0])
            magnitude = np.linalg.norm(normal)
            if magnitude < 1e-8 or abs(normal[2]) / magnitude > .075:
                continue
            vertices = source_to_grid(source_vertices, origin, scale)
            columns = vertices[:, [0, 2]]
            pairs = ((0, 1), (1, 2), (2, 0))
            a_id, b_id = max(pairs, key=lambda pair: np.linalg.norm(columns[pair[0]] - columns[pair[1]]))
            a, b = columns[a_id], columns[b_id]
            delta = b - a
            denominator = float(np.dot(delta, delta))
            if denominator < 1e-8:
                continue
            minimum = np.maximum(np.floor(columns.min(axis=0) - 1).astype(int), 0)
            maximum = np.minimum(np.ceil(columns.max(axis=0) + 1).astype(int), [width - 1, depth - 1])
            xs, zs = np.meshgrid(np.arange(minimum[0], maximum[0] + 1), np.arange(minimum[1], maximum[1] + 1))
            centers = np.column_stack((xs.reshape(-1) + .5, zs.reshape(-1) + .5))
            along = np.clip(((centers - a) @ delta) / denominator, 0, 1)
            distance = np.linalg.norm(centers - (a + along[:, None] * delta), axis=1)
            selected = distance <= .85
            target_x, target_z = xs.reshape(-1)[selected], zs.reshape(-1)[selected]
            top[target_z, target_x] = np.maximum(top[target_z, target_x], vertices[:, 1].max())
        bounded = top.copy()
        for dz in (-1, 0, 1):
            for dx in (-1, 0, 1):
                src_z = slice(max(0, -dz), min(depth, depth - dz))
                src_x = slice(max(0, -dx), min(width, width - dx))
                dst_z = slice(max(0, dz), min(depth, depth + dz))
                dst_x = slice(max(0, dx), min(width, width + dx))
                bounded[dst_z, dst_x] = np.maximum(bounded[dst_z, dst_x], top[src_z, src_x])
        return np.ceil(bounded + (bounded > 0) * .025).astype(np.int32)

    def texture(self, material):
        key = material.name if material else ""
        if key not in self.images:
            cached = None
            if material and material.use_nodes:
                nodes = [node for node in material.node_tree.nodes if node.type == "TEX_IMAGE" and node.image]
                if nodes:
                    image = nodes[0].image
                    width, height = image.size
                    pixels = np.empty(width * height * 4, dtype=np.float32)
                    image.pixels.foreach_get(pixels)
                    cached = pixels.reshape((height, width, 4))
            self.images[key] = cached
        return self.images[key]

    def sample_uv(self, index, uv):
        material = self.materials[index]
        pixels = self.texture(material)
        if pixels is not None:
            height, width = pixels.shape[:2]
            column = int(math.floor(float(uv[0]) * width)) % width
            row = int(math.floor(float(uv[1]) * height)) % height
            rgba = pixels[row, column]
            return rgba[:3], float(rgba[3])
        if material and material.use_nodes:
            shader = material.node_tree.nodes.get("Principled BSDF")
            if shader:
                rgba = shader.inputs["Base Color"].default_value
                return np.asarray(rgba[:3]), float(rgba[3])
        return np.asarray([.56, .49, .37]), 1.0

    def nearest(self, point):
        location, normal, index, distance = self.bvh.find_nearest(Vector(point))
        if index is None:
            return None, math.inf
        a, b, c = self.array[self.triangles[index]]
        v0, v1, v2 = b - a, c - a, np.asarray(location) - a
        d00, d01, d11 = np.dot(v0, v0), np.dot(v0, v1), np.dot(v1, v1)
        d20, d21 = np.dot(v2, v0), np.dot(v2, v1)
        denominator = d00 * d11 - d01 * d01
        if abs(denominator) < 1e-12:
            uv = self.uvs[index].mean(axis=0)
        else:
            v, w = (d11 * d20 - d01 * d21) / denominator, (d00 * d21 - d01 * d20) / denominator
            uv = (1 - v - w) * self.uvs[index][0] + v * self.uvs[index][1] + w * self.uvs[index][2]
        rgb, alpha = self.sample_uv(index, uv)
        return (rgb if alpha >= .5 else None), float(distance)

    def rasterize_props(self, occupied, origin, scale):
        added = 0
        max_z, max_x, max_y = occupied.shape
        for index in self.props:
            vertices = self.array[self.triangles[index]]
            edge = max(np.linalg.norm(vertices[a] - vertices[b]) for a, b in ((0, 1), (1, 2), (2, 0)))
            samples = max(1, min(128, int(math.ceil(edge / scale * 2))))
            for row in range(samples + 1):
                v = row / samples
                w = np.arange(samples - row + 1) / samples
                barycentric = np.column_stack((1 - v - w, np.full(len(w), v), w))
                points = barycentric @ vertices
                cells = np.floor(source_to_grid(points, origin, scale)).astype(np.int32)
                uvs = barycentric @ self.uvs[index]
                for cell, uv in zip(cells, uvs):
                    x, y, z = cell
                    if 0 <= x < max_x and 2 <= y < max_y and 0 <= z < max_z:
                        _, alpha = self.sample_uv(index, uv)
                        if alpha >= .5 and not occupied[z, x, y]:
                            occupied[z, x, y] = True
                            added += 1
        return added


def select_spawns(occupied, entities, origin, scale):
    candidates = safe_standing_points(occupied)
    if not len(candidates):
        raise ValueError("No safe supported player spawn survived voxel conversion")
    team_spawns, source_spawns, adjustments = {"0": [], "1": []}, [], []
    spawn_yaw = 0.0
    for entity in entities:
        classname = entity.get("classname")
        if classname not in {"info_player_start", "info_player_deathmatch"}:
            continue
        position = entity.get("origin", [0, 0, 0])
        if isinstance(position, str):
            position = [float(value) for value in position.split()]
        position = np.asarray(position, dtype=np.float64)
        # GoldSrc player spawn origins are hull centers, 36 source units above feet.
        feet = position.copy()
        feet[2] -= 36
        intended = source_to_grid(feet, origin, scale)
        distance = ((candidates - intended) ** 2 * np.array([1, 2, 1])).sum(axis=1)
        chosen = candidates[int(np.argmin(distance))]
        team = "0" if classname == "info_player_start" else "1"
        team_spawns[team].append(chosen.tolist())
        if not source_spawns:
            angle = float(entity.get("angle", 0))
            if "angles" in entity:
                angles = entity["angles"]
                angle = float(angles.split()[1] if isinstance(angles, str) else angles[1])
            spawn_yaw = -math.radians(angle) - math.pi / 2
        source_spawns.append(chosen)
        adjustments.append({"classname": classname, "source_origin": position.tolist(), "grid_feet": chosen.tolist(), "adjustment_blocks": float(np.linalg.norm(chosen - intended))})
    if source_spawns:
        # Prefer the authentic first source spawn, rather than an arbitrary rooftop.
        spawn = source_spawns[0].tolist()
    else:
        center = np.array([occupied.shape[1] / 2, 8, occupied.shape[0] / 2])
        spawn = candidates[int(np.argmin(((candidates - center) ** 2).sum(axis=1)))].tolist()
    for team in team_spawns:
        if not team_spawns[team]:
            team_spawns[team] = [spawn]
    return spawn, team_spawns, adjustments, int(len(candidates)), spawn_yaw


def main():
    started = time.perf_counter()
    args = arguments()
    if not bpy.data.filepath or not Path(bpy.data.filepath).is_file():
        raise ValueError("Must load the actual saved .blend before voxelizing")
    if args.units_per_block <= 0:
        raise ValueError("units-per-block must be positive")
    text = bpy.data.texts.get("BLOCKFIELD_SOURCE_METADATA.json")
    if not text:
        raise ValueError("Blender scene is missing embedded BSP and provenance metadata")
    source = json.loads(text.as_string())
    sampler = SurfaceSampler()
    used_vertices = sampler.array[np.unique(np.asarray(sampler.triangles).reshape(-1))]
    # Ignore oversized sky geometry, but preserve the entire visible horizontal layout.
    transformed = np.column_stack((used_vertices[:, 0], used_vertices[:, 2], -used_vertices[:, 1]))
    scale = args.units_per_block
    origin = np.floor(transformed.min(axis=0) / scale) * scale - 2 * scale
    upper = np.ceil(transformed.max(axis=0) / scale) * scale + 2 * scale
    dimensions = np.ceil((upper - origin) / scale).astype(np.int32)
    cropped_top = max(0, int(dimensions[1]) - 64)
    dimensions[1] = min(dimensions[1], 64)
    if dimensions[0] > 512 or dimensions[2] > 512:
        raise ValueError(f"Horizontal dimensions {dimensions.tolist()} exceed512; increase units-per-block")
    width, height, depth = map(int, dimensions)
    occupied = np.zeros((depth, width, height), dtype=np.bool_)
    total = width * height * depth
    progress("classifying_bsp", dimensions=dimensions.tolist(), cells=total, units_per_block=scale)
    for first in range(0, total, 180000):
        indices = np.arange(first, min(total, first + 180000))
        y = indices % height
        x = (indices // height) % width
        z = indices // (width * height)
        points = grid_to_source(np.column_stack((x + .5, y + .5, z + .5)), origin, scale)
        occupied.reshape(-1)[indices] = classify_solid(points, source["collision"])
        progress("classifying_bsp", completed=int(indices[-1] + 1), total=total)
    bsp_before_envelope = int(occupied.sum())
    envelope = sampler.structural_envelope(dimensions, origin, scale)
    occupied = constrain_to_columns(occupied, envelope)
    finite_removed = bsp_before_envelope - int(occupied.sum())
    progress("visible_structural_envelope", removed_unbounded_cells=finite_removed, retained_bsp_cells=int(occupied.sum()),
             columns_with_structure=int((envelope > 0).sum()))
    occupied[:, :, :2] = True
    prop_added = 0 if args.no_props else sampler.rasterize_props(occupied, origin, scale)
    progress("props_voxelized", added_cells=prop_added, triangles=len(sampler.props))
    cells = np.zeros(occupied.shape, dtype=np.uint32)
    cells[occupied] = 0x0196876F
    cells[:, :, :2] = 0x016B6459
    exposed = exposed_mask(occupied)
    # Paint one layer behind the surface as well, so a first bullet does not expose
    # unrelated default earth inside plaster, wood or stone.
    paint = exposed.copy()
    paint[1:, :, :] |= exposed[:-1, :, :]
    paint[:-1, :, :] |= exposed[1:, :, :]
    paint[:, 1:, :] |= exposed[:, :-1, :]
    paint[:, :-1, :] |= exposed[:, 1:, :]
    paint[:, :, 1:] |= exposed[:, :, :-1]
    paint[:, :, :-1] |= exposed[:, :, 1:]
    paint &= occupied
    z, x, y = np.where(paint)
    points = grid_to_source(np.column_stack((x + .5, y + .5, z + .5)), origin, scale)
    progress("sampling_blender_uv", samples=len(points), triangles=len(sampler.triangles))
    colored = 0
    for index, point in enumerate(points):
        rgb, distance = sampler.nearest(point)
        if rgb is not None and distance <= scale * 2.5:
            channels = np.clip(np.rint(rgb * 255), 0, 255).astype(int)
            cells[z[index], x[index], y[index]] = 0x01000000 | int(channels[0]) << 16 | int(channels[1]) << 8 | int(channels[2])
            colored += 1
        if index and index % 30000 == 0:
            progress("sampling_blender_uv", completed=index, total=len(points))
    spawn, teams, adjustments, safe_count, spawn_yaw = select_spawns(occupied, source["entities"], origin, scale)
    blend_hash = hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()
    limitations = ["Original BSP collision retained; arbitrary Blender brush edits need regenerated collision metadata.",
                   "Static GoldSrc entities and model geometry use their initial poses; scripts, doors, ladders and objectives are not ported.",
                   f"{scale:g} source units per block quantizes thin trim, stairs and openings; local spawn clearances are checked, whole-map connectivity is not established.",
                   "Source lighting/lightmaps omitted; original texture color is shaded by Blockfield.",
                   "Only exposed cells and one interior band receive source UV colors; deeper solids use concrete/earth color.",
                   "Two continuous supported bottom layers added for voxel collapse rules.",
                   "Tool-only/faceless brush submodels omitted from block occupancy. Worldspawn room-air remains classified by the original BSP.",
                   "Unbounded outside BSP solids are capped by the highest visible structural surface and a one-cell margin; empty-footprint columns retain only bottom support.",
                   "Sky/tool surfaces omitted; clip-hull-only invisible restrictions do not become visible blocks.",
                   "Visual props and illusionary brushes become static destructible sampled surface shells, including originally non-solid decoration."]
    if cropped_top:
        limitations.append(f"Top {cropped_top} source-grid layers above64-height limit cropped.")
    metadata = {"format": 1, "title": "Mirage · voxel conversion", "dimensions": dimensions.tolist(),
                "spawn": spawn, "yaw_radians": spawn_yaw, "team_spawns": teams, "water_enabled": False,
                "conversion": {"pipeline": "extracted GoldSrc → saved Blender → voxel blocks", "units_per_block": scale,
                               "source_to_grid": "((source.x,source.z,-source.y)-origin)/units_per_block", "origin": origin.tolist(),
                               "occupancy": "BSP-solid intersect visible structural column envelope, excluding tool-only submodels, plus static visual shells", "blender_version": bpy.app.version_string,
                               "blend_sha256": blend_hash, "solid_cells": int(occupied.sum()), "surface_cells": int(exposed.sum()),
                               "colored_cells": colored, "prop_added_cells": prop_added, "safe_standing_cells": safe_count,
                               "bsp_solid_before_envelope": bsp_before_envelope, "unbounded_bsp_cells_removed": finite_removed,
                               "structural_columns": int((envelope > 0).sum()), "excluded_tool_models": source.get("tool_only_models", []),
                               "source_spawn_adjustments": adjustments, "limitations": limitations},
                "provenance": source.get("provenance", {})}
    sizes = write_bfmap(args.output, cells, metadata)
    topdown_path = args.output.with_name("voxel-topdown.png")
    write_topdown_png(topdown_path, cells)
    report = {**metadata, "source_blend": str(Path(bpy.data.filepath).resolve()), "output": str(args.output.resolve()),
              "triangles": len(sampler.triangles), "packed_images_sampled": len(sampler.images), "ignored_objects": sampler.ignored_objects,
              "topdown_preview": str(topdown_path.resolve()), **sizes, "elapsed_seconds": round(time.perf_counter() - started, 3)}
    report_path = args.report or args.output.with_suffix(".report.json")
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    progress("complete", output=str(args.output.resolve()), report=str(report_path.resolve()), sizes=sizes, spawn=spawn,
             solid_cells=int(occupied.sum()), colored_cells=colored, elapsed_seconds=report["elapsed_seconds"])
    if args.render_spawn:
        scene = bpy.context.scene
        camera = scene.camera
        entity = next((entry for entry in source["entities"] if entry.get("classname") == "info_player_start"), None)
        if entity:
            position = [float(value) for value in entity["origin"].split()]
            angles = [float(value) for value in entity.get("angles", "0 0 0").split()]
            camera.location = Vector(position) + Vector((0, 0, 28))
            direction = Vector((math.cos(math.radians(angles[1])), math.sin(math.radians(angles[1])), -.035))
            camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
            camera.data.type = "PERSP"
            camera.data.lens = 23
            camera.data.clip_start = 1
            scene.render.resolution_x, scene.render.resolution_y = 1400, 900
            scene.render.resolution_percentage = 100
            scene.render.filepath = str(args.render_spawn.resolve())
            scene.eevee.taa_render_samples = 16
            args.render_spawn.parent.mkdir(parents=True, exist_ok=True)
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
