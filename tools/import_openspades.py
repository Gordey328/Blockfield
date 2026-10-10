#!/usr/bin/env python3
"""Import pinned OpenSpades resources without executing upstream build scripts.

KV6 -> glTF 2.0 binary (exterior faces, per-voxel color, team material).
Opus -> Ogg Vorbis via an explicitly supplied FFmpeg binary.
The nonfree assets must stay bundled with the free noncommercial source/game
distribution. Their license is copied verbatim into the resulting asset tree.
"""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
import shutil
import struct
import subprocess
import sys
from typing import NamedTuple
import urllib.request
import zipfile


class Resource(NamedTuple):
    virtual_path: str
    content: bytes
    source: str
    placeholder: bool = False


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_name(name: str) -> str:
    name = name.replace("\\", "/")
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or ":" in name:
        raise ValueError(f"Unsafe archive member: {name!r}")
    return str(path)


def download_pack(source: Path, pack: Path) -> None:
    location = (source / "Resources/PakLocation.txt").read_text(encoding="utf-8")
    urls = [line.strip() for line in location.splitlines()
            if line.startswith("https://github.com/yvt/openspades-paks/")
            and "OpenSpadesDevPackage" in line]
    if len(urls) != 1:
        raise ValueError("Expected exactly one official dev-package URL")
    pack.parent.mkdir(parents=True, exist_ok=True)
    temporary = pack.with_suffix(".download")
    request = urllib.request.Request(urls[0], headers={"User-Agent": "Blockfield-asset-import/1"})
    with urllib.request.urlopen(request, timeout=60) as response, temporary.open("wb") as output:
        shutil.copyfileobj(response, output)
    with zipfile.ZipFile(temporary) as archive:
        if archive.testzip() is not None:
            raise ValueError("Downloaded package CRC verification failed")
        if "Nonfree/pak000-Nonfree.pak" not in archive.namelist():
            raise ValueError("Official package lacks Nonfree/pak000-Nonfree.pak")
    temporary.replace(pack)


def read_resources(source: Path, pack: Path | None) -> tuple[dict[str, Resource], dict[str, bytes]]:
    resources: dict[str, Resource] = {}
    licenses: dict[str, bytes] = {}
    base = source / "Resources"
    for category in ("Models", "Sounds", "Gfx", "Textures", "Maps", "Locales"):
        for path in sorted((base / category).rglob("*")):
            if not path.is_file() or "_Assets_" in path.parts or path.name == ".DS_Store":
                continue
            relative = path.relative_to(base).as_posix()
            weak = relative.endswith(".weak")
            virtual = relative.removesuffix(".weak")
            if weak and virtual in resources:
                continue
            resources[virtual] = Resource(virtual, path.read_bytes(), f"source:Resources/{relative}", weak)
    for path in sorted((base / "License").glob("*")):
        if path.is_file():
            licenses[path.name] = path.read_bytes()
    for name in ("COPYING", "LICENSE", "LICENSE.md"):
        path = source / name
        if path.is_file():
            licenses[f"OpenSpades-{name}"] = path.read_bytes()
    if pack:
        with zipfile.ZipFile(pack) as archive:
            for info in archive.infolist():
                name = safe_name(info.filename)
                if info.is_dir():
                    continue
                if "LICENSE" in name.upper() or "COPYING" in name.upper():
                    licenses[name.replace("/", "-")] = archive.read(info)
            packs = [(name, archive.read(name)) for name in
                     ("Nonfree/pak000-Nonfree.pak", "OfficialMods/font-unifont.pak")]
        for pak_path, pak_bytes in packs:
            with zipfile.ZipFile(io.BytesIO(pak_bytes)) as pak:
                for info in pak.infolist():
                    name = safe_name(info.filename)
                    if info.is_dir():
                        continue
                    content = pak.read(info)
                    if "LICENSE" in name.upper() or "COPYING" in name.upper():
                        licenses[f"pak000-{name.replace('/', '-')}"] = content
                    resources[name] = Resource(name, content, f"r33:{pak_path}!/{name}")
        if not any("Nonfree" in name for name in licenses):
            raise ValueError("Original pack is missing its license notice")
    return resources, licenses


def decode_kv6(data: bytes) -> tuple[tuple[int, int, int], tuple[float, float, float], dict]:
    """Read the same little-endian fields as OpenSpades Core/VoxelModel.cpp."""
    if len(data) < 32 or data[:4] != b"Kvxl":
        raise ValueError("Invalid/truncated KV6 header")
    sx, sy, sz, px, py, pz, count = struct.unpack_from("<IIIfffI", data, 4)
    if not (1 <= sx <= 4096 and 1 <= sy <= 4096 and 1 <= sz <= 64):
        raise ValueError(f"Unsupported KV6 dimensions: {(sx, sy, sz)}")
    expected = 32 + count * 8 + sx * 4 + sx * sy * 2
    if len(data) < expected:
        raise ValueError(f"KV6 truncated: length {len(data)} < expected {expected}")
    x_counts = struct.unpack_from(f"<{sx}I", data, 32 + count * 8)
    xy_counts = struct.unpack_from(f"<{sx * sy}H", data, 32 + count * 8 + sx * 4)
    if sum(xy_counts) != count:
        raise ValueError("KV6 column counts do not sum to voxel count")
    if any(sum(xy_counts[x * sy:(x + 1) * sy]) != x_counts[x] for x in range(sx)):
        raise ValueError("KV6 X and XY counts disagree")
    voxels = {}
    index = 0
    for x in range(sx):
        for y in range(sy):
            last_z = -1
            for _ in range(xy_counts[x * sy + y]):
                blue, green, red, alpha, z, visible, normal = struct.unpack_from("<BBBBHBB", data, 32 + index * 8)
                if z >= sz or z <= last_z:
                    raise ValueError("KV6 Z outside dimensions or unsorted column")
                voxels[x, y, z] = (red, green, blue)
                last_z = z
                index += 1
    if not voxels:
        raise ValueError("Empty KV6 model")
    return (sx, sy, sz), (px, py, pz), voxels


def exterior_air(dimensions: tuple[int, int, int], voxels: dict) -> set:
    """Match HollowFill: enclosed air is solid, only exterior faces render."""
    sx, sy, sz = dimensions
    visited = set()
    queue = deque()
    for x in range(sx):
        for y in range(sy):
            for z in (0, sz - 1):
                if (x, y, z) not in voxels and (x, y, z) not in visited:
                    visited.add((x, y, z))
                    queue.append((x, y, z))
    for x in range(sx):
        for z in range(sz):
            for y in (0, sy - 1):
                if (x, y, z) not in voxels and (x, y, z) not in visited:
                    visited.add((x, y, z))
                    queue.append((x, y, z))
    for y in range(sy):
        for z in range(sz):
            for x in (0, sx - 1):
                if (x, y, z) not in voxels and (x, y, z) not in visited:
                    visited.add((x, y, z))
                    queue.append((x, y, z))
    while queue:
        x, y, z = queue.popleft()
        for dx, dy, dz in ((-1, 0, 0), (1, 0, 0), (0, -1, 0), (0, 1, 0), (0, 0, -1), (0, 0, 1)):
            cell = x + dx, y + dy, z + dz
            if 0 <= cell[0] < sx and 0 <= cell[1] < sy and 0 <= cell[2] < sz:
                if cell not in visited and cell not in voxels:
                    visited.add(cell)
                    queue.append(cell)
    return visited


# Source-space CCW faces. Reflection to (x, -z, -y) reverses their winding.
FACES = (
    ((-1, 0, 0), ((0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0))),
    ((1, 0, 0), ((1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1))),
    ((0, -1, 0), ((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1))),
    ((0, 1, 0), ((0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0))),
    ((0, 0, -1), ((0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0))),
    ((0, 0, 1), ((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1))),
)


def linear_color(channel: int) -> float:
    value = channel / 255.0
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def kv6_to_glb(data: bytes, name: str) -> tuple[bytes, dict]:
    dimensions, pivot, voxels = decode_kv6(data)
    outside = exterior_air(dimensions, voxels)
    groups = [{"positions": [], "normals": [], "colors": [], "indices": []} for _ in range(2)]
    faces = 0
    for (x, y, z), rgb in sorted(voxels.items()):
        team = rgb == (0, 0, 0)  # Same customColor sentinel as OptimizedVoxelModel.fs.
        group = groups[int(team)]
        for normal, corners in FACES:
            neighbour = x + normal[0], y + normal[1], z + normal[2]
            within = all(0 <= neighbour[axis] < dimensions[axis] for axis in range(3))
            if within and neighbour not in outside:
                continue
            base = len(group["positions"])
            for cx, cy, cz in corners:
                group["positions"].append((x + cx - pivot[0], -(z + cz - pivot[2]), -(y + cy - pivot[1])))
                group["normals"].append((normal[0], -normal[2], -normal[1]))
                group["colors"].append((1.0, 1.0, 1.0, 1.0) if team else (*map(linear_color, rgb), 1.0))
            group["indices"].extend((base, base + 2, base + 1, base, base + 3, base + 2))
            faces += 1
    blob = bytearray()
    document = {
        "asset": {"version": "2.0", "generator": "Blockfield OpenSpades KV6 importer"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}], "meshes": [{"name": name, "primitives": []}],
        "buffers": [{"byteLength": 0}], "bufferViews": [], "accessors": [],
        "materials": [
            {"name": "VoxelColors", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 1}},
            {"name": "TeamColor", "pbrMetallicRoughness": {"baseColorFactor": [0.025, 0.23, 0.64, 1], "metallicFactor": 0, "roughnessFactor": 1}},
        ],
    }

    def accessor(values: list, format_string: str, component_type: int, kind: str, target: int, bounds: bool = False) -> int:
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        for value in values:
            blob.extend(struct.pack(format_string, *value) if isinstance(value, tuple) else struct.pack(format_string, value))
        view = len(document["bufferViews"])
        document["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob) - offset, "target": target})
        entry = {"bufferView": view, "componentType": component_type, "count": len(values), "type": kind}
        if bounds:
            entry["min"] = [min(value[axis] for value in values) for axis in range(3)]
            entry["max"] = [max(value[axis] for value in values) for axis in range(3)]
        index = len(document["accessors"])
        document["accessors"].append(entry)
        return index

    for index, group in enumerate(groups):
        if not group["indices"]:
            continue
        primitive = {
            "attributes": {
                "POSITION": accessor(group["positions"], "<fff", 5126, "VEC3", 34962, True),
                "NORMAL": accessor(group["normals"], "<fff", 5126, "VEC3", 34962),
                "COLOR_0": accessor(group["colors"], "<ffff", 5126, "VEC4", 34962),
            },
            "indices": accessor(group["indices"], "<I", 5125, "SCALAR", 34963),
            "material": index, "mode": 4,
        }
        document["meshes"][0]["primitives"].append(primitive)
    document["buffers"][0]["byteLength"] = len(blob)
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    blob += b"\x00" * (-len(blob) % 4)
    glb = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(json_bytes) + 8 + len(blob))
    glb += struct.pack("<I4s", len(json_bytes), b"JSON") + json_bytes
    glb += struct.pack("<I4s", len(blob), b"BIN\x00") + blob
    metadata = {"dimensions": dimensions, "pivot": pivot, "voxels": len(voxels), "faces": faces,
                "triangles": faces * 2, "team_material": bool(groups[1]["indices"]),
                "coordinate_transform": "(x - xpivot, -(z - zpivot), -(y - ypivot))", "units": "original KV6 voxel"}
    return glb, metadata


def write_if_changed(path: Path, data: bytes) -> None:
    if path.exists() and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def ospfont_to_bmfont(data: bytes, atlas_data: bytes, atlas_name: str) -> tuple[bytes, dict]:
    """Preserve original bitmap glyphs/offsets using Godot's AngelCode importer.

    Structure matches Client/IFont.cpp and Tools/BdfToOSFont.cpp GlyphInfo.
    """
    from PIL import Image
    if len(data) < 24 or data[:16] != b"OpenSpadesFontFl":
        raise ValueError("Invalid OpenSpades bitmap font header")
    count, size = struct.unpack_from("<II", data, 16)
    if len(data) != 24 + count * 16 or not 1 <= size <= 256:
        raise ValueError("Invalid OpenSpades bitmap font bounds")
    with Image.open(io.BytesIO(atlas_data)) as atlas:
        width, height = atlas.size
    # Include atlas provenance/orientation in the descriptor so changing the
    # atlas invalidates Godot's embedded bitmap-font cache as well.
    face = f"OpenSpades GNU Unifont r33-{sha256(atlas_data)[:8]}-bottomup"
    lines = [f'info face="{face}" size={size} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0',
             f"common lineHeight={size} base={size} scaleW={width} scaleH={height} pages=1 packed=0",
             f'page id=0 file="{atlas_name}"', f"chars count={count}"]
    seen = set()
    for index in range(count):
        code, x, y, w, h, advance, off_x, off_y = struct.unpack_from("<IHHBBHhh", data, 24 + index * 16)
        if code in seen or code > 0x10ffff:
            raise ValueError("Duplicate/invalid font Unicode character")
        seen.add(code)
        if w == 0 or h == 0:
            x = y = 0
        elif x + w > width or y + h > height:
            raise ValueError("Bitmap font glyph outside atlas")
        lines.append(f"char id={code} x={x} y={y} width={w} height={h} xoffset={off_x} yoffset={off_y} xadvance={advance} page=0 chnl=15")
    return ("\n".join(lines) + "\n").encode("utf-8"), {"glyphs": count, "font_size": size, "atlas_size": [width, height]}


def transcode_audio(content: bytes, source_path: str, destination: Path, ffmpeg: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".source")
    temporary.write_bytes(content)
    try:
        result = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(temporary),
                                 "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", "4", str(destination)],
                                capture_output=True, text=True, check=False)
        if result.returncode:
            raise ValueError(f"FFmpeg failed for {source_path}: {result.stderr.strip()}")
        if destination.stat().st_size < 32 or destination.read_bytes()[:4] != b"OggS":
            raise ValueError(f"Invalid Ogg output for {source_path}")
    finally:
        temporary.unlink(missing_ok=True)


def import_assets(source: Path, pack: Path | None, output: Path, ffmpeg: str, allow_placeholders: bool) -> dict:
    resources, licenses = read_resources(source, pack)
    output.mkdir(parents=True, exist_ok=True)
    for name, content in licenses.items():
        write_if_changed(output / "licenses" / name, content)
    previous = {}
    manifest_path = output / "manifest.json"
    if manifest_path.exists():
        previous = {entry["virtual_path"]: entry for entry in json.loads(manifest_path.read_text(encoding="utf-8")).get("assets", [])}
    manifest = {"upstream": "https://github.com/yvt/openspades", "upstream_version": "v0.1.3",
                "dev_pack": "r33" if pack else None, "pack_sha256": sha256(pack.read_bytes()) if pack else None,
                "assets": [], "skipped": [], "warnings": []}
    for virtual_path, resource in sorted(resources.items()):
        parts = PurePosixPath(virtual_path).parts
        extension = PurePosixPath(virtual_path).suffix.lower()
        content = resource.content
        metadata = {}
        if resource.placeholder and not allow_placeholders:
            manifest["warnings"].append(f"Unresolved upstream fallback excluded: {virtual_path}")
            manifest["skipped"].append({"virtual_path": virtual_path, "source": resource.source,
                                        "reason": "Unresolved .weak placeholder, not an original asset"})
            continue
        if extension == ".kv6":
            destination = output / "models" / Path(*parts[1:]).with_suffix(".glb")
            content, metadata = kv6_to_glb(resource.content, PurePosixPath(virtual_path).stem)
            write_if_changed(destination, content)
        elif parts[0] == "Sounds" and extension in (".opus", ".wav", ".ogg", ".mp3"):
            destination = output / "sounds" / Path(*parts[1:]).with_suffix(".ogg")
            prior = previous.get(virtual_path, {})
            if prior.get("source_sha256") != sha256(content) or not destination.exists() or sha256(destination.read_bytes()) != prior.get("output_sha256"):
                transcode_audio(content, virtual_path, destination, ffmpeg)
            content = destination.read_bytes()
        elif extension in (".png", ".jpg", ".jpeg", ".tga", ".bmp"):
            destination = output / "images" / Path(*parts).with_suffix(".png")
            if extension != ".png":
                from PIL import Image
                image_bytes = io.BytesIO()
                with Image.open(io.BytesIO(content)) as image:
                    image = image.convert("RGBA")
                    if extension == ".tga":
                        # Core/TargaReader.cpp always decodes bottom-up/left-right;
                        # its spec-compliant orientation adjustment is #if 0.
                        # Pillow obeys descriptor flags, so undo those adjustments.
                        if resource.content[17] & 0x20:
                            image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
                        if resource.content[17] & 0x10:
                            image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                        metadata["orientation"] = "OpenSpades TargaReader (ignores TGA origin flags)"
                    image.save(image_bytes, format="PNG")
                content = image_bytes.getvalue()
            write_if_changed(destination, content)
        elif extension in (".ttf", ".otf"):
            destination = output / "fonts" / Path(*parts)
            write_if_changed(destination, content)
        elif extension == ".ospfont":
            destination = output / "fonts" / Path(*parts).with_suffix(".fnt")
            atlas_path = str(PurePosixPath(virtual_path).with_suffix(".tga"))
            if atlas_path not in resources:
                raise ValueError(f"Font atlas missing: {atlas_path}")
            atlas_output = output / "images" / Path(*parts).with_suffix(".png")
            # Relative path from fonts/Gfx/Fonts to images/Gfx/Fonts.
            atlas_name = "../../../images/" + PurePosixPath(virtual_path).with_suffix(".png").as_posix()
            content, metadata = ospfont_to_bmfont(content, resources[atlas_path].content, atlas_name)
            metadata["atlas_output"] = atlas_output.relative_to(output).as_posix()
            metadata["atlas_source_sha256"] = sha256(resources[atlas_path].content)
            write_if_changed(destination, content)
        elif parts[0] == "Maps" and extension == ".vxl":
            destination = output / "maps" / Path(*parts[1:])
            write_if_changed(destination, content)
        elif parts[0] == "Locales" and extension in (".json", ".po", ".pot"):
            destination = output / "locales" / Path(*parts[1:])
            write_if_changed(destination, content)
            if extension in (".po", ".pot"):
                metadata["catalog_messages"] = max(0, sum(line.startswith("msgid ") for line in content.decode("utf-8").splitlines()) - 1)
        else:
            manifest["skipped"].append({"virtual_path": virtual_path, "source": resource.source})
            continue
        if resource.placeholder:
            manifest["warnings"].append(f"Placeholder: {virtual_path}")
        manifest["assets"].append({"virtual_path": virtual_path, "output": destination.relative_to(output).as_posix(),
                                   "source": resource.source, "source_sha256": sha256(resource.content),
                                   "output_sha256": sha256(content), "bytes": len(content), "placeholder": resource.placeholder,
                                   **metadata})
    manifest["counts"] = {category: sum(asset["output"].startswith(category + "/") for asset in manifest["assets"])
                           for category in ("models", "sounds", "images", "maps", "locales", "fonts")}
    manifest["total_bytes"] = sum(asset["bytes"] for asset in manifest["assets"])
    write_if_changed(manifest_path, (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
    return manifest


def verify_glb(data: bytes) -> dict:
    """Validate binary extents, indices, finite data and outward triangle normals."""
    if len(data) < 28:
        raise ValueError("GLB truncated")
    magic, version, length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ValueError("Invalid GLB header")
    json_length, json_kind = struct.unpack_from("<I4s", data, 12)
    if json_kind != b"JSON" or json_length % 4:
        raise ValueError("Invalid GLB JSON chunk")
    document = json.loads(data[20:20 + json_length])
    binary_start = 20 + json_length
    binary_length, binary_kind = struct.unpack_from("<I4s", data, binary_start)
    binary = data[binary_start + 8:]
    if binary_kind != b"BIN\x00" or binary_length != len(binary):
        raise ValueError("Invalid GLB binary chunk")
    if document["buffers"][0]["byteLength"] > len(binary):
        raise ValueError("GLB buffer exceeds chunk")

    def read_accessor(index: int) -> list:
        entry = document["accessors"][index]
        view = document["bufferViews"][entry["bufferView"]]
        components = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[entry["type"]]
        scalar = {5126: "f", 5125: "I"}[entry["componentType"]]
        fmt = "<" + scalar * components
        size = struct.calcsize(fmt)
        if view["byteOffset"] % 4 or view["byteOffset"] + view["byteLength"] > len(binary):
            raise ValueError("Invalid GLB buffer view alignment/extent")
        if entry["count"] * size > view["byteLength"]:
            raise ValueError("GLB accessor exceeds buffer view")
        values = [struct.unpack_from(fmt, binary, view["byteOffset"] + i * size) for i in range(entry["count"])]
        if any(not math.isfinite(component) for value in values for component in value):
            raise ValueError("GLB nonfinite accessor data")
        return values

    triangles = 0
    for primitive in document["meshes"][0]["primitives"]:
        positions = read_accessor(primitive["attributes"]["POSITION"])
        normals = read_accessor(primitive["attributes"]["NORMAL"])
        colors = read_accessor(primitive["attributes"]["COLOR_0"])
        indices = [value[0] for value in read_accessor(primitive["indices"])]
        if len(indices) % 3 or len(positions) != len(normals) or len(positions) != len(colors):
            raise ValueError("GLB attribute/triangle counts disagree")
        if any(index >= len(positions) for index in indices):
            raise ValueError("GLB index outside vertex range")
        if any(not (0 <= component <= 1) for color in colors for component in color):
            raise ValueError("GLB color outside normalized range")
        for offset in range(0, len(indices), 3):
            a, b, c = [positions[index] for index in indices[offset:offset + 3]]
            ab = tuple(b[axis] - a[axis] for axis in range(3))
            ac = tuple(c[axis] - a[axis] for axis in range(3))
            cross = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
            normal = normals[indices[offset]]
            if sum(cross[axis] * normal[axis] for axis in range(3)) <= 0:
                raise ValueError("GLB degenerate/inward triangle")
        triangles += len(indices) // 3
    return {"triangles": triangles, "primitives": len(document["meshes"][0]["primitives"])}


def verify_assets(output: Path, ffmpeg: str | None) -> dict:
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    verified = {"models": 0, "sounds": 0, "images": 0, "files": 0, "triangles": 0}
    for entry in manifest["assets"]:
        relative = safe_name(entry["output"])
        path = output / relative
        data = path.read_bytes()
        if sha256(data) != entry["output_sha256"] or len(data) != entry["bytes"]:
            raise ValueError(f"Output checksum/size mismatch: {relative}")
        verified["files"] += 1
        if relative.endswith(".glb"):
            info = verify_glb(data)
            if info["triangles"] != entry["triangles"]:
                raise ValueError(f"Model triangle count mismatch: {relative}")
            verified["triangles"] += info["triangles"]
            verified["models"] += 1
        elif relative.startswith("sounds/"):
            if data[:4] != b"OggS":
                raise ValueError(f"Invalid Ogg header: {relative}")
            if ffmpeg:
                result = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(path), "-f", "null", "-"],
                                        capture_output=True, text=True, check=False)
                if result.returncode:
                    raise ValueError(f"Audio decode failed: {relative}: {result.stderr.strip()}")
            verified["sounds"] += 1
        elif relative.startswith("images/"):
            from PIL import Image
            with Image.open(io.BytesIO(data)) as image:
                image.verify()
            verified["images"] += 1
    if manifest["counts"]["models"] != verified["models"]:
        raise ValueError("Manifest model count mismatch")
    return verified


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(".cache/openspades"))
    parser.add_argument("--pack", type=Path, default=Path(".cache/assets/OpenSpadesDevPackage-r33.zip"))
    parser.add_argument("--output", type=Path, default=Path("game/assets/openspades"))
    parser.add_argument("--download", action="store_true", help="Download missing official dev pack after reading PakLocation.txt")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"), help="FFmpeg executable supporting libvorbis")
    parser.add_argument("--allow-placeholders", action="store_true", help="Explicit development-only fallback; never a parity build")
    parser.add_argument("--pack-sha256", help="Optional required SHA-256 for reproducible pack verification")
    parser.add_argument("--verify", action="store_true", help="Verify existing manifest hashes, all GLB geometry and PNG data; decode sounds if --ffmpeg is supplied")
    args = parser.parse_args()
    try:
        if args.verify:
            print(json.dumps(verify_assets(args.output.resolve(), args.ffmpeg), indent=2))
            return 0
        if not args.pack.exists() and args.download:
            download_pack(args.source, args.pack)
        pack = args.pack if args.pack.exists() else None
        if not pack and not args.allow_placeholders:
            raise ValueError("Original dev pack missing; supply --download or --pack")
        if pack and args.pack_sha256 and sha256(pack.read_bytes()) != args.pack_sha256.lower():
            raise ValueError("Pack SHA-256 does not match expected checksum")
        if not args.ffmpeg or not Path(args.ffmpeg).is_file():
            raise ValueError("Supply --ffmpeg path to a local FFmpeg binary")
        manifest = import_assets(args.source.resolve(), pack.resolve() if pack else None, args.output.resolve(), args.ffmpeg, args.allow_placeholders)
        print(json.dumps({"counts": manifest["counts"], "bytes": manifest["total_bytes"], "warnings": manifest["warnings"],
                          "pack_sha256": manifest["pack_sha256"]}, indent=2))
        return 0
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        print(f"Asset import failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
