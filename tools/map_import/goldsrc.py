"""Read-only GoldSrc BSP30/WAD3/IDST10 extraction for offline map conversion.

Format layouts are independently implemented from Valve's published headers:
https://github.com/ValveSoftware/halflife/blob/master/utils/common/bsplib.h
https://github.com/ValveSoftware/halflife/blob/master/utils/common/wadlib.h
https://github.com/ValveSoftware/halflife/blob/master/engine/studio.h

No engine, game SDK, or source assets are bundled. Coordinates remain GoldSrc
Z-up source units. Mesh placement is baked; collision trees remain model-local.
UV v is flipped for Blender's bottom-origin convention; PNG rows remain original.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
from typing import Any

from PIL import Image


class FormatError(ValueError):
    """The source has an unsupported or invalid binary layout."""


def _slice(data: bytes, offset: int, length: int, label: str) -> bytes:
    if offset < 0 or length < 0 or offset + length > len(data):
        raise FormatError(f"{label}: range {offset}+{length} exceeds {len(data)} bytes")
    return data[offset:offset + length]


def _unpack(fmt: str, data: bytes, offset: int, label: str) -> tuple:
    return struct.unpack(fmt, _slice(data, offset, struct.calcsize(fmt), label))


def _records(data: bytes, fmt: str, label: str) -> list[tuple]:
    if len(data) % struct.calcsize(fmt):
        raise FormatError(f"{label}: partial record")
    return list(struct.iter_unpack(fmt, data))


def _name(data: bytes) -> str:
    return data.split(b"\0", 1)[0].decode("latin1")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_entities(data: bytes) -> list[dict[str, str]]:
    """Parse quoted pairs, retaining literal Windows paths in WAD keys."""
    value = data.rstrip(b"\0").decode("latin1")
    tokens = re.findall(r'"(?:\\"|[^"])*"|[{}]', value)
    entities: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    pending: str | None = None
    for token in tokens:
        if token == "{":
            if current is not None:
                raise FormatError("entities: nested block")
            current, pending = {}, None
        elif token == "}":
            if current is None or pending is not None:
                raise FormatError("entities: incomplete pair/block")
            entities.append(current)
            current = None
        else:
            if current is None:
                raise FormatError("entities: pair outside block")
            content = token[1:-1].replace('\\"', '"')
            if pending is None:
                pending = content
            else:
                current[pending] = content
                pending = None
    if current is not None:
        raise FormatError("entities: unterminated block")
    return entities


def read_bsp(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    if _unpack("<i", data, 0, "BSP version")[0] != 30:
        raise FormatError("Only GoldSrc BSP version 30 is supported")
    lumps = [_slice(data, o, n, f"BSP lump {i}") for i, (o, n) in
             enumerate(_records(_slice(data, 4, 120, "BSP directory"), "<ii", "BSP directory"))]
    result = {
        "entities": parse_entities(lumps[0]),
        "planes": _records(lumps[1], "<4fi", "planes"),
        "textures": lumps[2],
        "vertices": _records(lumps[3], "<3f", "vertices"),
        "nodes": _records(lumps[5], "<i8h2H", "nodes"),
        "texinfo": _records(lumps[6], "<8f2i", "texinfo"),
        "faces": _records(lumps[7], "<Hhihh4Bi", "faces"),
        "clipnodes": _records(lumps[9], "<i2h", "clipnodes"),
        "leaves": _records(lumps[10], "<ii6h2H4B", "leaves"),
        "edges": _records(lumps[12], "<2H", "edges"),
        "surfedges": [item[0] for item in _records(lumps[13], "<i", "surfedges")],
        "models": _records(lumps[14], "<9f7i", "models"),
    }
    for i, node in enumerate(result["nodes"]):
        if not 0 <= node[0] < len(result["planes"]):
            raise FormatError(f"node {i}: invalid plane")
        for child in node[1:3]:
            count = len(result["nodes"]) if child >= 0 else len(result["leaves"])
            index = child if child >= 0 else -child - 1
            if not 0 <= index < count:
                raise FormatError(f"node {i}: invalid child {child}")
    if not result["models"]:
        raise FormatError("BSP has no world model")
    return result


def read_wad(path: Path) -> dict[str, bytes]:
    data = path.read_bytes()
    magic, count, offset = _unpack("<4sii", data, 0, "WAD header")
    if magic != b"WAD3":
        raise FormatError(f"{path.name}: expected WAD3")
    entries = _records(_slice(data, offset, count * 32, "WAD directory"), "<iii4B16s", "WAD directory")
    textures = {}
    for position, disk_size, size, kind, compression, _pad1, _pad2, raw_name in entries:
        if kind != 0x43:  # Mipmapped, palette-bearing GoldSrc textures.
            continue
        if compression != 0 or disk_size != size:
            raise FormatError(f"{path.name}: compressed texture {_name(raw_name)}")
        textures[_name(raw_name).lower()] = _slice(data, position, disk_size, "WAD texture")
    return textures


def decode_miptex(data: bytes) -> tuple[str, Image.Image]:
    raw_name, width, height, *offsets = _unpack("<16s6I", data, 0, "miptex")
    name = _name(raw_name)
    if width < 8 or height < 8 or width > 8192 or height > 8192 or width % 8 or height % 8:
        raise FormatError(f"{name}: invalid mip dimensions {width}x{height}")
    if not offsets[0]:
        raise FormatError(f"{name}: pixels reside in an external WAD")
    pixels = _slice(data, offsets[0], width * height, f"{name} pixels")
    palette_offset = offsets[3] + (width // 8) * (height // 8)
    count = _unpack("<H", data, palette_offset, f"{name} palette count")[0]
    if count != 256:
        raise FormatError(f"{name}: expected 256 palette colors, got {count}")
    palette = _slice(data, palette_offset + 2, 768, f"{name} palette")
    image = Image.frombytes("P", (width, height), pixels)
    image.putpalette(palette)
    if name.startswith("{"):
        image.info["transparency"] = 255
    return name, image.convert("RGBA")


def _vec(value: str | None, default: tuple = (0, 0, 0)) -> list[float]:
    if value is None:
        return list(default)
    values = [float(part) for part in value.split()]
    if len(values) != 3 or not all(math.isfinite(v) for v in values):
        raise FormatError(f"Invalid vector: {value!r}")
    return values


def _angles(entity: dict) -> list[float]:
    if "angles" in entity:
        return _vec(entity["angles"])
    angle = float(entity.get("angle", 0))
    if angle == -1:
        return [-90, 0, 0]
    if angle == -2:
        return [90, 0, 0]
    return [0, angle, 0]


def _rotation_xyz(roll: float, pitch: float, yaw: float) -> list[list[float]]:
    """Rz(yaw) Ry(pitch) Rx(roll), arguments in radians."""
    sr, cr, sp, cp, sy, cy = math.sin(roll), math.cos(roll), math.sin(pitch), math.cos(pitch), math.sin(yaw), math.cos(yaw)
    return [[cp * cy, sr * sp * cy - cr * sy, cr * sp * cy + sr * sy],
            [cp * sy, sr * sp * sy + cr * cy, cr * sp * sy - sr * cy],
            [-sp, sr * cp, cr * cp]]


def entity_rotation(angles: list[float], studio: bool = False) -> list[list[float]]:
    """Valve AngleMatrix pitch/yaw/roll; studio rendering negates pitch."""
    pitch, yaw, roll = [math.radians(v) for v in angles]
    return _rotation_xyz(roll, -pitch if studio else pitch, yaw)


def _transform(point: tuple | list, rotation: list[list[float]], origin: list, scale: float = 1) -> list[float]:
    return [sum(rotation[i][j] * point[j] * scale for j in range(3)) + origin[i] for i in range(3)]


def _concat(parent: tuple, local: tuple) -> tuple:
    a, ao = parent
    b, bo = local
    return ([[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)],
            _transform(bo, a, ao))


def _safe_filename(name: str) -> str:
    clean = re.sub(r"[^A-Za-z0-9_.-]", "_", name).strip(".") or "texture"
    return clean[:90] + "_" + hashlib.sha256(name.encode("utf8")).hexdigest()[:10] + ".png"


class _Materials:
    def __init__(self, output: Path):
        self.output = output
        self.materials: list[dict] = []
        self.ids: dict[str, int] = {}
        (output / "textures").mkdir(parents=True, exist_ok=True)

    def add(self, key: str, name: str, image: Image.Image, source: str,
            masked: bool = False, flags: int = 0) -> int:
        if key in self.ids:
            return self.ids[key]
        relative = "textures/" + _safe_filename(key)
        image.save(self.output / relative)
        material = {"name": name, "texture": relative, "width": image.width, "height": image.height,
                    "masked": masked, "sky": name.lower().startswith("sky"), "source": source, "flags": flags}
        index = len(self.materials)
        self.materials.append(material)
        self.ids[key] = index
        return index


def _bsp_materials(bsp: dict, source_root: Path, materials: _Materials, provenance: list, issues: list) -> list[int]:
    wad_names = [name.split("\\")[-1].split("/")[-1].lower() for name in
                 bsp["entities"][0].get("wad", "").split(";") if name]
    available = {path.name.lower(): path for path in sorted(source_root.rglob("*.wad"))}
    paths = [available[name] for name in wad_names if name in available]
    paths += [path for path in available.values() if path not in paths]
    wad_textures: dict[str, list[tuple[bytes, Path]]] = {}
    for path in paths:
        for name, data in read_wad(path).items():
            wad_textures.setdefault(name, []).append((data, path))
    used_wads: set[Path] = set()
    data = bsp["textures"]
    count = _unpack("<i", data, 0, "BSP mip count")[0]
    offsets = _unpack(f"<{count}i", data, 4, "BSP mip directory")
    ids = []
    for index, offset in enumerate(offsets):
        if offset < 0:
            issues.append({"kind": "missing_texture", "texture_index": index, "reason": "BSP offset -1"})
            image = Image.new("RGBA", (16, 16), (255, 0, 255, 255))
            ids.append(materials.add(f"missing_{index}", f"missing_{index}", image, "missing"))
            continue
        raw_name, width, height, *mips = _unpack("<16s6I", data, offset, f"BSP mip {index}")
        name = _name(raw_name)
        source = "embedded_bsp"
        if mips[0]:
            _decoded_name, image = decode_miptex(data[offset:])
        elif name.lower() in wad_textures:
            candidates = wad_textures[name.lower()]
            matching = [(texture, path) for texture, path in candidates if
                        _unpack("<2I", texture, 16, "WAD mip dimensions") == (width, height)]
            if not matching:
                raise FormatError(f"{name}: no WAD candidate matches BSP dimensions {width}x{height}")
            texture, wad_path = matching[0]
            _decoded_name, image = decode_miptex(texture)
            source = wad_path.relative_to(source_root).as_posix()
            used_wads.add(wad_path)
        else:
            issues.append({"kind": "missing_texture", "name": name, "reason": "Not found in provided WADs"})
            image = Image.new("RGBA", (max(width, 16), max(height, 16)), (255, 0, 255, 255))
            source = "missing"
        ids.append(materials.add("bsp:" + name.lower(), name, image, source, name.startswith("{")))
    for path in sorted(used_wads):
        provenance.append({"path": path.relative_to(source_root).as_posix(), "sha256": _sha256(path)})
    return ids


def _is_solid(classname: str) -> bool:
    return not (classname.startswith("trigger_") or classname.startswith("env_") or
                classname in {"func_illusionary", "func_ladder", "func_bomb_target", "func_water"})


def _brush_meshes(bsp: dict, material_ids: list[int]) -> tuple[list[dict], list[dict]]:
    owners = {int(entity["model"][1:]): (i, entity) for i, entity in enumerate(bsp["entities"])
              if entity.get("model", "").startswith("*")}
    meshes, models = [], []
    for model_index, model in enumerate(bsp["models"]):
        entity_index, entity = owners.get(model_index, (None, {"classname": "worldspawn"}))
        classname = entity.get("classname", "unknown")
        origin = _vec(entity.get("origin"))
        angles = _angles(entity)
        rotation = entity_rotation(angles)
        solid = _is_solid(classname)
        mesh = {"name": f"bsp_{model_index}_{classname}", "kind": "bsp", "model_index": model_index,
                "entity_index": entity_index, "classname": classname, "solid": solid, "vertices": [], "faces": []}
        lookup = {}
        first, count = model[14:16]
        if first < 0 or first + count > len(bsp["faces"]):
            raise FormatError(f"model {model_index}: invalid face range")
        for face_index in range(first, first + count):
            face = bsp["faces"][face_index]
            plane, side, first_edge, edge_count, tex_index = face[:5]
            if not 0 <= tex_index < len(bsp["texinfo"]) or not 0 <= plane < len(bsp["planes"]):
                raise FormatError(f"face {face_index}: invalid plane/texture")
            if first_edge < 0 or edge_count < 3 or first_edge + edge_count > len(bsp["surfedges"]):
                raise FormatError(f"face {face_index}: invalid surfedge range")
            texinfo = bsp["texinfo"][tex_index]
            if not 0 <= texinfo[8] < len(material_ids):
                raise FormatError(f"face {face_index}: invalid material")
            indices, points = [], []
            for signed_edge in bsp["surfedges"][first_edge:first_edge + edge_count]:
                if abs(signed_edge) >= len(bsp["edges"]):
                    raise FormatError(f"face {face_index}: invalid edge")
                vertex_id = bsp["edges"][abs(signed_edge)][0 if signed_edge >= 0 else 1]
                if vertex_id >= len(bsp["vertices"]):
                    raise FormatError(f"face {face_index}: invalid vertex")
                point = bsp["vertices"][vertex_id]
                if vertex_id not in lookup:
                    lookup[vertex_id] = len(mesh["vertices"])
                    mesh["vertices"].append(_transform(point, rotation, origin))
                indices.append(lookup[vertex_id])
                points.append(point)
            normal = [sum((points[i][(j + 1) % 3] - points[(i + 1) % len(points)][(j + 1) % 3]) *
                          (points[i][(j + 2) % 3] + points[(i + 1) % len(points)][(j + 2) % 3])
                          for i in range(len(points))) for j in range(3)]
            expected = bsp["planes"][plane][:3]
            if sum(normal[j] * expected[j] * (-1 if side else 1) for j in range(3)) < 0:
                indices.reverse()
                points.reverse()
            # UV dimensions follow BSP mip header, not any potentially altered material.
            mip_offset = _unpack(f"<{_unpack('<i', bsp['textures'], 0, 'count')[0]}i", bsp["textures"], 4, "mips")[texinfo[8]]
            width, height = _unpack("<2I", bsp["textures"], mip_offset + 16, "mip size") if mip_offset >= 0 else (16, 16)
            uv = [[(sum(p[j] * texinfo[j] for j in range(3)) + texinfo[3]) / width,
                   1 - (sum(p[j] * texinfo[j + 4] for j in range(3)) + texinfo[7]) / height] for p in points]
            mesh["faces"].append({"indices": indices, "uv": uv, "material": material_ids[texinfo[8]], "source_face": face_index})
        meshes.append(mesh)
        models.append({"model_index": model_index, "root": model[9], "mins": list(model[:3]), "maxs": list(model[3:6]),
                       "model_origin": list(model[6:9]), "origin": origin, "angles": angles, "rotation": rotation,
                       "entity_index": entity_index, "classname": classname, "solid": solid})
    return meshes, models


def _studio_pose(data: bytes, header: tuple[int, ...], entity: dict) -> list[tuple]:
    count, offset = header[1:3]
    bones = [_unpack("<32s8i12f", data, offset + i * 112, "studio bone") for i in range(count)]
    # Snapshot frame 0 of selected sequence, first blend. No animation is exported.
    sequence_count, sequence_offset = header[7:9]
    sequence = min(max(int(entity.get("sequence", 0)), 0), max(sequence_count - 1, 0))
    anim_offset = None
    if sequence_count:
        seq = sequence_offset + sequence * 176
        anim_offset = _unpack("<i", data, seq + 124, "sequence animation")[0]
        group = _unpack("<i", data, seq + 156, "sequence group")[0]
        if group:
            raise FormatError("External studio sequence groups are unsupported")
    controller_count, controller_offset = header[3:5]
    controller_values = [float(v) for v in entity.get("controller", "0 0 0 0").split()]
    adjustments = []
    for i in range(controller_count):
        _bone, kind, start, end, rest, control = _unpack("<iiffii", data, controller_offset + 24 * i, "controller")
        value = controller_values[control] if 0 <= control < len(controller_values) else rest
        if kind & 0x8000:
            adjustment = value * 360 / 256 + start
        else:
            adjustment = start + (end - start) * max(0, min(255, value)) / 255
        adjustments.append(math.radians(adjustment) if kind & 0x38 else adjustment)
    pose: list[tuple] = []
    for i, bone in enumerate(bones):
        parent = bone[1]
        controllers = bone[3:9]
        values = list(bone[9:15])
        scales = bone[15:21]
        if anim_offset is not None:
            animation = anim_offset + i * 12
            channels = _unpack("<6H", data, animation, "bone animation")
            for j, channel in enumerate(channels):
                if channel:
                    valid, total = _unpack("<2B", data, animation + channel, "animation run")
                    if not 0 < valid <= total:
                        raise FormatError("Invalid studio animation run")
                    values[j] += _unpack("<h", data, animation + channel + 2, "animation frame 0")[0] * scales[j]
        for j, controller in enumerate(controllers):
            if controller >= 0:
                if controller >= len(adjustments):
                    raise FormatError("Invalid bone controller")
                values[j] += adjustments[controller]
        local = (_rotation_xyz(*values[3:6]), values[:3])
        if parent >= i or parent < -1:
            raise FormatError("Studio bone hierarchy is not parent-first")
        pose.append(_concat(pose[parent], local) if parent >= 0 else local)
    return pose


def _studio_meshes(path: Path, entity: dict, entity_index: int, source_root: Path,
                   materials: _Materials) -> list[dict]:
    data = path.read_bytes()
    magic, version = _unpack("<4si", data, 0, "studio header")
    if magic != b"IDST" or version != 10:
        raise FormatError("Only studio IDST version 10 is supported")
    length = _unpack("<i", data, 72, "studio length")[0]
    if length != len(data):
        raise FormatError("Studio header/file length disagreement")
    # Fixed-width integers after five vec3s and flags, starting at byte 136.
    header = _unpack("<27i", data, 136, "studio counts")
    texture_count, texture_offset = header[11:13]
    texture_data = data
    texture_source = path
    if not texture_count:
        sibling = path.with_name(path.stem + "T.mdl")
        if not sibling.exists():
            raise FormatError("Studio has external textures but companion T.mdl is missing")
        texture_data = sibling.read_bytes()
        if _unpack("<4si", texture_data, 0, "texture studio header") != (b"IDST", 10):
            raise FormatError("Invalid companion texture studio")
        texture_count, texture_offset = _unpack("<2i", texture_data, 180, "texture counts")
        texture_source = sibling
    texture_ids = []
    for i in range(texture_count):
        raw_name, flags, width, height, offset = _unpack("<64s4i", texture_data, texture_offset + i * 80, "studio texture")
        if not 0 < width <= 8192 or not 0 < height <= 8192:
            raise FormatError("Invalid studio texture dimensions")
        pixels = _slice(texture_data, offset, width * height, "studio pixels")
        palette = _slice(texture_data, offset + width * height, 768, "studio palette")
        image = Image.frombytes("P", (width, height), pixels)
        image.putpalette(palette)
        if flags & 0x40:
            image.info["transparency"] = 255
        texture_ids.append(materials.add(f"mdl:{entity['model'].lower()}:{i}", _name(raw_name), image.convert("RGBA"),
                                         texture_source.relative_to(source_root).as_posix(), bool(flags & 0x40), flags))
    pose = _studio_pose(data, header, entity)
    skin_refs, skin_families, skin_offset = header[14:17]
    skin = max(0, min(int(entity.get("skin", 0)), skin_families - 1))
    skins = _unpack(f"<{skin_refs}h", data, skin_offset + skin * skin_refs * 2, "studio skin")
    body_count, body_offset = header[17:19]
    body = int(entity.get("body", 0))
    origin, angles = _vec(entity.get("origin")), _angles(entity)
    rotation = entity_rotation(angles, studio=True)
    scale = float(entity.get("scale", 1)) or 1
    meshes = []
    for body_index in range(body_count):
        raw_name, model_count, base, model_offset = _unpack("<64s3i", data, body_offset + body_index * 76, "body part")
        if model_count <= 0 or base <= 0:
            raise FormatError("Invalid studio body part")
        model_number = body // base % model_count
        model = _unpack("<64sif10i", data, model_offset + model_number * 112, "studio model")
        _model_name, _kind, _radius, mesh_count, mesh_offset, vertex_count, bone_offset, vertex_offset = model[:8]
        points = [_unpack("<3f", data, vertex_offset + i * 12, "studio vertex") for i in range(vertex_count)]
        bone_ids = _slice(data, bone_offset, vertex_count, "vertex bones")
        vertices = []
        for p, bone in zip(points, bone_ids):
            if bone >= len(pose):
                raise FormatError("Invalid vertex bone")
            vertices.append(_transform(_transform(p, *pose[bone]), rotation, origin, scale))
        mesh = {"name": f"mdl_{entity_index}_{path.stem}_{body_index}", "kind": "mdl", "model_index": None,
                "entity_index": entity_index, "classname": entity.get("classname", "unknown"), "solid": False,
                "source_model": entity["model"], "pose": "sequence_frame_0_first_blend", "vertices": vertices, "faces": []}
        for mesh_index in range(mesh_count):
            _triangle_count, triangle_offset, skinref, _normal_count, _normal_offset = _unpack("<5i", data, mesh_offset + mesh_index * 20, "studio mesh")
            if not 0 <= skinref < len(skins) or not 0 <= skins[skinref] < len(texture_ids):
                raise FormatError("Invalid studio skin reference")
            material = texture_ids[skins[skinref]]
            texture = materials.materials[material]
            cursor = triangle_offset
            emitted = 0
            while True:
                count = _unpack("<h", data, cursor, "triangle command")[0]
                cursor += 2
                if not count:
                    break
                if abs(count) < 3:
                    raise FormatError("Studio strip/fan has fewer than 3 vertices")
                loops = [_unpack("<4h", data, cursor + i * 8, "triangle vertex") for i in range(abs(count))]
                cursor += abs(count) * 8
                for i in range(2, len(loops)):
                    loop_ids = (0, i - 1, i) if count < 0 else ((i - 2, i - 1, i) if i % 2 == 0 else (i - 1, i - 2, i))
                    triangle = [loops[j] for j in loop_ids]
                    if any(not 0 <= loop[0] < vertex_count for loop in triangle):
                        raise FormatError("Invalid triangle vertex")
                    mesh["faces"].append({"indices": [loop[0] for loop in triangle],
                                          "uv": [[loop[2] / texture["width"], 1 - loop[3] / texture["height"]] for loop in triangle],
                                          "material": material})
                    emitted += 1
                if emitted > 1000000:
                    raise FormatError("Unbounded studio triangle stream")
            if emitted != _triangle_count:
                raise FormatError(f"Studio triangle count mismatch: {_triangle_count} versus {emitted}")
        meshes.append(mesh)
    return meshes


def export_scene(source_root: Path, output_dir: Path) -> dict:
    source_root = source_root.resolve()
    output_dir = output_dir.resolve()
    if source_root == output_dir or source_root in output_dir.parents:
        raise ValueError("Extraction output must be outside the source directory")
    bsps = sorted(source_root.rglob("*.bsp"))
    if len(bsps) != 1:
        raise ValueError(f"Expected one BSP below {source_root}, found {len(bsps)}")
    bsp_path = bsps[0]
    bsp = read_bsp(bsp_path)
    # User may supply an archive wrapper directory rather than the game root.
    game_root = bsp_path.parent.parent if bsp_path.parent.name.lower() == "maps" else source_root
    output_dir.mkdir(parents=True, exist_ok=True)
    materials = _Materials(output_dir)
    provenance = [{"path": bsp_path.relative_to(game_root).as_posix(), "sha256": _sha256(bsp_path)}]
    issues: list[dict] = []
    material_ids = _bsp_materials(bsp, game_root, materials, provenance, issues)
    meshes, models = _brush_meshes(bsp, material_ids)
    available = {path.relative_to(game_root).as_posix().lower(): path for path in game_root.rglob("*.mdl")}
    used: set[Path] = set()
    imported = 0
    for i, entity in enumerate(bsp["entities"]):
        reference = entity.get("model", "").replace("\\", "/")
        if not reference.lower().endswith(".mdl"):
            continue
        path = available.get(reference.lower())
        if path is None:
            issues.append({"kind": "missing_model", "entity_index": i, "model": reference})
            continue
        try:
            studio_meshes = _studio_meshes(path, entity, i, game_root, materials)
        except (FormatError, ValueError) as exc:
            issues.append({"kind": "unsupported_model", "entity_index": i, "model": reference, "reason": str(exc)})
            continue
        meshes.extend(studio_meshes)
        used.add(path)
        imported += 1
    for path in sorted(used):
        provenance.append({"path": path.relative_to(game_root).as_posix(), "sha256": _sha256(path)})
    sprites = [{"entity_index": i, "model": entity.get("model")} for i, entity in enumerate(bsp["entities"])
               if entity.get("model", "").lower().endswith(".spr")]
    if sprites:
        issues.append({"kind": "sprites_not_geometry", "count": len(sprites), "entities": sprites})
    decals = sum(entity.get("classname") == "infodecal" for entity in bsp["entities"])
    if decals:
        issues.append({"kind": "decals_not_baked", "count": decals})
    scene = {"format": 1, "name": bsp_path.stem, "coordinates": "GoldSrc Z-up source units",
             "uv_convention": "Blender bottom-origin; PNG original top-origin rows",
             "source": {"root": str(game_root), "bsp": str(bsp_path), "sha256": _sha256(bsp_path), "format": "GoldSrc BSP30"},
             "provenance": provenance, "entities": bsp["entities"], "materials": materials.materials, "meshes": meshes,
             "collision": {"planes": [{"normal": list(p[:3]), "distance": p[3]} for p in bsp["planes"]],
                           "nodes": [{"plane": node[0], "children": list(node[1:3])} for node in bsp["nodes"]],
                           "leaves": [{"contents": leaf[0]} for leaf in bsp["leaves"]], "models": models,
                           "negative_child": "-1-leaf_index", "solid_contents": [-2], "sky_contents": [-6]},
             "issues": issues,
             "limitations": ["MDL animation is a static frame-0 snapshot of the selected sequence and first blend.",
                             "MDL props are visual surfaces; original cycler_sprite entities have no solid collision.",
                             "Lightmaps, animated materials, sprites, decals, scripted events and sounds are not baked."],
             "counts": {"bsp_models": len(models), "bsp_faces": len(bsp["faces"]), "meshes": len(meshes),
                        "materials": len(materials.materials), "entities": len(bsp["entities"]),
                        "placed_models": imported, "unique_models": len(used), "sprites": len(sprites), "decals": decals}}
    (output_dir / "scene.json").write_text(json.dumps(scene, ensure_ascii=True, separators=(",", ":")), encoding="utf8")
    report = {key: scene[key] for key in ("source", "provenance", "counts", "issues", "limitations")}
    (output_dir / "extraction-report.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    return scene


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    scene = export_scene(args.source, args.output)
    print(json.dumps({"output": str(args.output.resolve() / "scene.json"), "counts": scene["counts"], "issues": scene["issues"]}, indent=2))


if __name__ == "__main__":
    main()
