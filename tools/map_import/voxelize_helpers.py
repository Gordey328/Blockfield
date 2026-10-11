"""Pure conversion helpers shared by the Blender map pipeline.

Source is GoldSrc Z-up. Blockfield cells are (x east, y up, z south), with
Y-contiguous storage and an explicit occupied bit so solid black survives.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import struct
import zlib

import numpy as np

_BSP_TABLES = {}

TOOL_TEXTURE_NAMES = frozenset({"clip", "aaatrigger", "origin", "null", "hint", "skip", "nowallshot", "sky"})


def is_tool_material(material):
    return bool(material.get("sky")) or material["name"].lower() in TOOL_TEXTURE_NAMES


def bsp_tables(collision):
    key = id(collision)
    if key not in _BSP_TABLES:
        _BSP_TABLES.clear()
        _BSP_TABLES[key] = (
            np.asarray([node["plane"] for node in collision["nodes"]], dtype=np.int32),
            np.asarray([node["children"] for node in collision["nodes"]], dtype=np.int32),
            np.asarray([plane["normal"] for plane in collision["planes"]], dtype=np.float64),
            np.asarray([plane["distance"] for plane in collision["planes"]], dtype=np.float64),
            np.asarray([leaf["contents"] for leaf in collision["leaves"]], dtype=np.int32))
    return _BSP_TABLES[key]


def rotation_matrix(angles):
    """GoldSrc pitch/yaw/roll: Rz(yaw) Ry(pitch) Rx(roll)."""
    pitch, yaw, roll = np.radians(np.asarray(angles, dtype=np.float64))
    cp, sp, cy, sy, cr, sr = (math.cos(pitch), math.sin(pitch),
                             math.cos(yaw), math.sin(yaw),
                             math.cos(roll), math.sin(roll))
    return np.array([[cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr],
                     [sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr],
                     [-sp, cp * sr, cp * cr]], dtype=np.float64)


def bsp_contents(points, collision, root=0):
    """Classify a batch against the original render-hull BSP.

    A negative node child is -(leaf index + 1), rather than a contents value.
    Traversal works in bounded batches without recursive Python point queries.
    """
    points = np.asarray(points, dtype=np.float64)
    count = len(points)
    current = np.full(count, int(root), dtype=np.int32)
    nodes = collision["nodes"]
    node_planes, children, normals, distances, contents = bsp_tables(collision)
    for _ in range(512):
        active = np.flatnonzero(current >= 0)
        if not len(active):
            leaf_indices = -current - 1
            if np.any(leaf_indices >= len(contents)):
                raise ValueError("BSP leaf index outside collision table")
            return contents[leaf_indices]
        selected = current[active]
        if np.any(selected >= len(nodes)):
            raise ValueError("BSP node index outside collision table")
        plane_ids = node_planes[selected]
        signed = np.einsum("ij,ij->i", points[active], normals[plane_ids]) - distances[plane_ids]
        current[active] = children[selected, (signed < 0).astype(np.int32)]
    raise ValueError("BSP has a cycle or exceeds 512 levels")


def classify_solid(points, collision):
    """Union only solid brush models; preserve empty rooms and tunnels."""
    points = np.asarray(points, dtype=np.float64)
    solid = np.zeros(len(points), dtype=np.bool_)
    for model in collision["models"]:
        if not model.get("solid", True) or model.get("voxel_excluded", False):
            continue
        world_model = int(model["model_index"]) == 0
        if world_model:
            solid |= bsp_contents(points, collision, int(model["root"])) == -2
            continue
        origin = np.asarray(model.get("origin", [0, 0, 0]), dtype=np.float64)
        rotation = np.asarray(model.get("rotation", model.get("rotation_matrix", rotation_matrix(model.get("angles", [0, 0, 0])))), dtype=np.float64)
        lo, hi = np.asarray(model["mins"], dtype=np.float64), np.asarray(model["maxs"], dtype=np.float64)
        corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
        world_corners = corners @ rotation.T + origin
        minimum, maximum = world_corners.min(axis=0) - 1e-4, world_corners.max(axis=0) + 1e-4
        selected = np.flatnonzero(~solid & np.all(points >= minimum, axis=1) & np.all(points <= maximum, axis=1))
        if len(selected):
            local_points = (points[selected] - origin) @ rotation
            solid[selected] = bsp_contents(local_points, collision, int(model["root"])) == -2
    return solid


def source_to_grid(points, origin, units_per_block):
    points = np.asarray(points, dtype=np.float64)
    result = np.stack((points[..., 0], points[..., 2], -points[..., 1]), axis=-1)
    return (result - np.asarray(origin, dtype=np.float64)) / units_per_block


def grid_to_source(points, origin, units_per_block):
    transformed = np.asarray(points, dtype=np.float64) * units_per_block + np.asarray(origin, dtype=np.float64)
    return np.stack((transformed[..., 0], -transformed[..., 2], transformed[..., 1]), axis=-1)


def exposed_mask(occupied):
    """occupied array axes are (z, x, y)."""
    padded = np.pad(occupied, 1, constant_values=False)
    adjacent = (padded[:-2, 1:-1, 1:-1] & padded[2:, 1:-1, 1:-1]
                & padded[1:-1, :-2, 1:-1] & padded[1:-1, 2:, 1:-1]
                & padded[1:-1, 1:-1, :-2] & padded[1:-1, 1:-1, 2:])
    return occupied & ~adjacent


def constrain_to_columns(occupied, top):
    """Remove unbounded BSP solid above finite visible geometry; never add cells."""
    return occupied & (np.arange(occupied.shape[2])[None, None, :] < top[:, :, None])


def safe_standing_points(occupied):
    """Cell-centered feet with full 0.9-wide, 2.4-high clearance/support."""
    clearance = (~occupied[:, :, :-3] & ~occupied[:, :, 1:-2] & ~occupied[:, :, 2:-1])
    support = occupied[:, :, :-4]
    # feet y = solid top + .025. Centered footprint lies in one x/z cell.
    walkable = clearance[:, :, 1:] & support
    walkable[0, :, :] = walkable[-1, :, :] = False
    walkable[:, 0, :] = walkable[:, -1, :] = False
    z, x, below = np.where(walkable)
    return np.column_stack((x + .5, below + 1.025, z + .5))


def write_bfmap(path, cells, metadata):
    cells = np.asarray(cells, dtype=np.uint32)
    raw = cells.astype(">u4").tobytes(order="C")
    encoded = json.dumps(metadata, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    compressed = zlib.compress(raw, level=9)
    output = b"BFM1" + struct.pack("<III", len(encoded), len(raw), len(compressed)) + encoded + compressed
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes(output)
    return {"file_bytes": len(output), "raw_bytes": len(raw), "compressed_bytes": len(compressed)}


def write_topdown_png(path, cells, magnification=5):
    """Dependency-free RGB overview of highest blocks; source north is top."""
    cells = np.asarray(cells, dtype=np.uint32)
    occupied = cells != 0
    depth, width, height = cells.shape
    top = height - 1 - np.argmax(occupied[:, :, ::-1], axis=2)
    z, x = np.indices((depth, width))
    values = cells[z, x, top]
    rgb = np.stack(((values >> 16) & 255, (values >> 8) & 255, values & 255), axis=2).astype(np.uint8)
    rgb[~occupied.any(axis=2)] = [45, 51, 61]
    rgb = np.repeat(np.repeat(rgb, magnification, axis=0), magnification, axis=1)
    image_height, image_width = rgb.shape[:2]
    scanlines = b"".join(b"\x00" + row.tobytes() for row in rgb)
    def chunk(name, data):
        return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", image_width, image_height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(scanlines, 6)) + chunk(b"IEND", b"")
    Path(path).write_bytes(png)
