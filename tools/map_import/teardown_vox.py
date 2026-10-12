"""Bounded MagicaVoxel v150 reader for local Teardown map conversion.

Spec: https://github.com/ephtracy/voxel-model . RGB uses the stored XYZI index
and RGBA[index-1]. IMAP only reorders display/material indices; remapping RGB
alone would corrupt colors. Rendering/material properties are retained as data.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import struct

import numpy as np


def decode_rotation(code: int | str) -> np.ndarray:
    """Decode the spec's row-major signed permutation, rejecting bad axes."""
    code = int(code)
    first, second = code & 3, (code >> 2) & 3
    if not 0 <= code < 128 or first > 2 or second > 2 or first == second:
        raise ValueError("Invalid VOX rotation encoding")
    axes = [first, second, 3 - first - second]
    result = np.zeros((3, 3), dtype=np.float64)
    for row, axis in enumerate(axes):
        result[row, axis] = -1 if code & (1 << (4 + row)) else 1
    return result


class _Reader:
    def __init__(self, data):
        self.data = memoryview(data)
        self.offset = 0

    def take(self, size):
        if size < 0 or self.offset + size > len(self.data):
            raise ValueError("Truncated VOX chunk")
        value = self.data[self.offset:self.offset + size]
        self.offset += size
        return value

    def integer(self):
        return struct.unpack("<i", self.take(4))[0]

    def count(self):
        value = self.integer()
        if value < 0 or value > 1_000_000:
            raise ValueError("Invalid VOX count")
        return value

    def string(self):
        size = self.count()
        return bytes(self.take(size)).decode("utf-8", errors="strict")

    def dictionary(self):
        result = {}
        for _ in range(self.count()):
            key, value = self.string(), self.string()
            if key in result:
                raise ValueError("Duplicate VOX dictionary key")
            result[key] = value
        return result

    def finish(self):
        if self.offset != len(self.data):
            raise ValueError("Unexpected trailing VOX chunk content")


@dataclass
class VoxModel:
    size: tuple[int, int, int]
    voxels: np.ndarray  # x,y,z,index uint8; gravity is +Z in this space


@dataclass
class VoxInstance:
    model: VoxModel
    rotation: np.ndarray
    translation: np.ndarray
    name: str = ""

    def centers(self):
        # MV centers integer voxel bounds around the floored half size. Adding
        # .5 is essential for odd dimensions and reflected object rotations.
        local = self.model.voxels[:, :3].astype(np.float64) + .5 - np.asarray(self.model.size) // 2
        return local @ self.rotation.T + self.translation


@dataclass
class VoxFile:
    models: list[VoxModel]
    palette: np.ndarray  # canonical uint32 0x01RRGGBB; index0 always air
    nodes: dict
    layers: dict
    imap: np.ndarray
    materials: dict = field(default_factory=dict)
    chunks: dict = field(default_factory=dict)

    @property
    def material_indices(self):
        """Stored index→display index, independent of the unchanged RGB lookup."""
        inverse = np.empty(256, dtype=np.uint8)
        inverse[self.imap] = np.arange(256, dtype=np.uint8)
        return (inverse.astype(np.uint16) + 1).astype(np.uint8)

    def instances(self, object_name="") -> list[VoxInstance]:
        """Flatten visible graph, or a named object with its layout offset reset.

        The selected-object anchor is horizontally centered/bottom aligned in
        its rotated model bounds. This models XML's reusable named VOX pieces;
        full-file imports retain the complete authored world-editor layout.
        """
        if not self.nodes:
            if object_name:
                raise ValueError(f"Named VOX object absent: {object_name}")
            if len(self.models) != 1:
                raise ValueError("Multiple models require a VOX scene graph")
            model = self.models[0]
            return [VoxInstance(model, np.eye(3), np.array([0., 0., model.size[2] // 2]))]
        referenced = {child for node in self.nodes.values() for child in node.get("children", [])}
        roots = [key for key in self.nodes if key not in referenced]
        if not roots:
            raise ValueError("VOX graph has no root")
        chosen = [key for key, node in self.nodes.items() if node["attrs"].get("_name") == object_name] if object_name else roots
        if object_name and len(chosen) != 1:
            raise ValueError(f"Named VOX object absent or ambiguous: {object_name}")
        output = []

        def visit(key, rotation, translation, chain, selected_root=False):
            if key in chain or len(chain) > 128 or key not in self.nodes:
                raise ValueError("Invalid/cyclic VOX scene graph")
            node = self.nodes[key]
            if node["attrs"].get("_hidden") == "1" or self.layers.get(node.get("layer", -1), {}).get("_hidden") == "1":
                return
            local_rotation, local_translation = np.eye(3), np.zeros(3)
            if node["kind"] == "nTRN":
                frame = min(node["frames"], key=lambda frame: int(frame.get("_f", 0)))
                local_rotation = decode_rotation(frame.get("_r", 4))
                local_translation = np.asarray([int(v) for v in frame.get("_t", "0 0 0").split()], dtype=np.float64)
                if local_translation.shape != (3,):
                    raise ValueError("Invalid VOX translation")
                if selected_root:
                    local_translation = np.zeros(3)
            next_rotation = rotation @ local_rotation
            next_translation = rotation @ local_translation + translation
            if node["kind"] == "nSHP":
                model_id, _ = min(node["models"], key=lambda entry: int(entry[1].get("_f", 0)))
                if not 0 <= model_id < len(self.models):
                    raise ValueError("VOX shape references missing model")
                output.append(VoxInstance(self.models[model_id], next_rotation, next_translation))
            for child in node.get("children", []):
                visit(child, next_rotation, next_translation, chain | {key})

        for key in chosen:
            visit(key, np.eye(3), np.zeros(3), set(), bool(object_name))
        if object_name and output:
            # Recenter the selected object bounds, retaining relative transforms
            # if the name points to a group. Use model bounds, not occupied bounds.
            corners = []
            for instance in output:
                half = np.asarray(instance.model.size) // 2
                size = np.asarray(instance.model.size)
                local = np.array([[x, y, z] for x in (-half[0], size[0]-half[0]) for y in (-half[1], size[1]-half[1]) for z in (-half[2], size[2]-half[2])])
                corners.append(local @ instance.rotation.T + instance.translation)
            bounds = np.concatenate(corners)
            low, high = bounds.min(axis=0), bounds.max(axis=0)
            anchor = np.array([(low[0]+high[0])/2, (low[1]+high[1])/2, low[2]])
            for instance in output:
                instance.translation = instance.translation - anchor
                instance.name = object_name
        return output


def read_vox(source: str | Path | bytes) -> VoxFile:
    data = bytes(source) if isinstance(source, (bytes, bytearray, memoryview)) else Path(source).read_bytes()
    if len(data) > 128 * 1024 * 1024 or len(data) < 20 or data[:4] != b"VOX ":
        raise ValueError("Unsupported/invalid VOX framing")
    version = struct.unpack_from("<I", data, 4)[0]
    if version not in (150, 200):
        raise ValueError(f"Unsupported VOX version {version}")
    if data[8:12] != b"MAIN":
        raise ValueError("VOX needs a MAIN root")
    models, nodes, layers, materials, chunks = [], {}, {}, {}, {}
    palette, pending_size = None, None
    imap = np.asarray(list(range(1, 256)) + [0], dtype=np.uint8)

    def parse_chunks(start, end, depth=0):
        nonlocal pending_size, palette, imap
        if depth > 64:
            raise ValueError("VOX chunk nesting exceeds limit")
        offset = start
        while offset < end:
            if offset + 12 > end:
                raise ValueError("Truncated VOX chunk header")
            kind, content_size, child_size = struct.unpack_from("<4sII", data, offset)
            content_start = offset + 12
            content_end, child_end = content_start + content_size, content_start + content_size + child_size
            if child_end > end:
                raise ValueError("VOX chunk lengths exceed parent")
            name = kind.decode("ascii", errors="strict")
            chunks[name] = chunks.get(name, 0) + 1
            reader = _Reader(data[content_start:content_end])
            if name == "SIZE":
                if pending_size is not None:
                    raise ValueError("VOX SIZE is missing its XYZI")
                pending_size = tuple(reader.integer() for _ in range(3))
                if any(v < 1 or v > 256 for v in pending_size):
                    raise ValueError("VOX model dimensions outside 1..256")
                reader.finish()
            elif name == "XYZI":
                if pending_size is None:
                    raise ValueError("VOX XYZI lacks SIZE")
                count = reader.count()
                voxels = np.frombuffer(reader.take(count*4), dtype=np.uint8).reshape((-1, 4)).copy()
                reader.finish()
                if np.any(voxels[:, :3] >= pending_size) or np.any(voxels[:, 3] == 0):
                    raise ValueError("VOX voxel outside model or uses air index")
                # Do not count duplicate records as more occupancy/color votes.
                if len(voxels) and len(np.unique(voxels[:, :3], axis=0)) != len(voxels):
                    raise ValueError("Duplicate VOX voxel coordinate")
                models.append(VoxModel(pending_size, voxels))
                pending_size = None
            elif name == "RGBA":
                if palette is not None or content_size != 1024:
                    raise ValueError("Invalid/duplicate VOX palette")
                rgb = np.frombuffer(reader.take(1024), dtype=np.uint8).reshape((256, 4)).astype(np.uint32)
                palette = np.zeros(256, dtype=np.uint32)
                palette[1:] = 0x01000000 | (rgb[:255, 0] << 16) | (rgb[:255, 1] << 8) | rgb[:255, 2]
            elif name == "IMAP":
                if content_size != 256:
                    raise ValueError("Invalid VOX IMAP length")
                imap = np.frombuffer(reader.take(256), dtype=np.uint8).copy()
                if len(np.unique(imap)) != 256:
                    raise ValueError("VOX IMAP must be a permutation")
            elif name in ("nTRN", "nGRP", "nSHP"):
                key, attrs = reader.integer(), reader.dictionary()
                if key < 0 or key in nodes:
                    raise ValueError("Invalid/duplicate VOX node ID")
                node = {"kind": name, "attrs": attrs}
                if name == "nTRN":
                    child, reserved, layer, count = reader.integer(), reader.integer(), reader.integer(), reader.count()
                    if reserved != -1 or count < 1:
                        raise ValueError("Invalid VOX transform")
                    node.update(children=[child], layer=layer, frames=[reader.dictionary() for _ in range(count)])
                elif name == "nGRP":
                    node["children"] = [reader.integer() for _ in range(reader.count())]
                else:
                    count = reader.count()
                    if count < 1:
                        raise ValueError("VOX shape must have a model")
                    node["models"] = [(reader.integer(), reader.dictionary()) for _ in range(count)]
                reader.finish()
                nodes[key] = node
            elif name == "LAYR":
                key, attrs, reserved = reader.integer(), reader.dictionary(), reader.integer()
                reader.finish()
                if key < 0 or key in layers or reserved != -1:
                    raise ValueError("Invalid VOX layer")
                layers[key] = attrs
            elif name == "MATL":
                key, attrs = reader.integer(), reader.dictionary()
                reader.finish()
                materials[key] = attrs
            if child_size:
                parse_chunks(content_end, child_end, depth+1)
            offset = child_end
        if offset != end:
            raise ValueError("Invalid VOX chunk boundary")

    parse_chunks(8, len(data))
    if pending_size is not None or not models:
        raise ValueError("Incomplete VOX model sequence")
    if palette is None:
        raise ValueError("VOX without explicit RGBA is unsupported by this converter")
    result = VoxFile(models, palette, nodes, layers, imap, materials, chunks)
    # Validate disconnected/missing nodes, cycles and model refs even if hidden.
    for key, node in nodes.items():
        for child in node.get("children", []):
            if child not in nodes:
                raise ValueError("VOX node references missing child")
        for model_id, attrs in node.get("models", []):
            if not 0 <= model_id < len(models):
                raise ValueError("VOX shape references missing model")
            if int(attrs.get("_f", 0)) < 0:
                raise ValueError("VOX shape frame index must be nonnegative")
        for frame in node.get("frames", []):
            decode_rotation(frame.get("_r", 4))
            translation = frame.get("_t", "0 0 0").split()
            if len(translation) != 3:
                raise ValueError("Invalid VOX translation")
            try:
                components = [int(value) for value in translation]
                frame_index = int(frame.get("_f", 0))
            except ValueError as error:
                raise ValueError("Invalid VOX transform frame") from error
            if any(value < -2147483648 or value > 2147483647 for value in components) or frame_index < 0:
                raise ValueError("VOX transform frame outside integer bounds")
    # A cyclic component can be disconnected from an otherwise valid root;
    # visibility and root flattening must never hide malformed source data.
    visiting, visited = set(), set()

    def validate_graph(key, depth=0):
        if key in visiting or depth > 128:
            raise ValueError("Invalid/cyclic VOX scene graph")
        if key in visited:
            return
        visiting.add(key)
        for child in nodes[key].get("children", []):
            validate_graph(child, depth+1)
        visiting.remove(key)
        visited.add(key)

    for key in nodes:
        validate_graph(key)
    return result
