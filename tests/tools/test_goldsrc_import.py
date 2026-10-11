"""Binary fixtures cover geometry placement, palettes, BSP volume and studio pose.

Run with Python unittest. Optional BLOCKFIELD_GOLDSRC_SOURCE tests a supplied map
in a temporary output directory; the fixture is never distributed with the repo.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import struct
import tempfile
import unittest

from tools.map_import import goldsrc


def miptex(name: str = "stone", width: int = 16, height: int = 16) -> bytes:
    levels = [bytes([1, 255] * (width * height // (4 ** i) // 2)) for i in range(4)]
    offsets, cursor = [], 40
    for level in levels:
        offsets.append(cursor)
        cursor += len(level)
    palette = bytearray(768)
    palette[3:6] = bytes((21, 42, 63))
    palette[765:768] = bytes((0, 0, 255))
    return struct.pack("<16s6I", name.encode(), width, height, *offsets) + b"".join(levels) + struct.pack("<H", 256) + palette


def wad(texture: bytes, name: str = "stone") -> bytes:
    return struct.pack("<4sii", b"WAD3", 1, 12 + len(texture)) + texture + struct.pack("<iii4B16s", 12, len(texture), len(texture), 0x43, 0, 0, 0, name.encode())


def bsp_fixture() -> bytes:
    lumps = [b""] * 15
    lumps[0] = b'{"classname" "worldspawn"}\0'
    lumps[1] = struct.pack("<4fi", 0, 0, 1, 0, 2)
    texture = miptex()
    lumps[2] = struct.pack("<ii", 1, 8) + texture
    lumps[3] = b"".join(struct.pack("<3f", *p) for p in [(0, 0, 0), (16, 0, 0), (16, 16, 0), (0, 16, 0)])
    # Plane separates EMPTY (+z) from SOLID (-z).
    lumps[5] = struct.pack("<i8h2H", 0, -2, -1, 0, 0, -16, 16, 16, 16, 0, 1)
    lumps[6] = struct.pack("<8f2i", 1, 0, 0, 0, 0, 1, 0, 0, 0, 0)
    lumps[7] = struct.pack("<Hhihh4Bi", 0, 0, 0, 4, 0, 255, 255, 255, 255, -1)
    lumps[10] = b"".join(struct.pack("<ii6h2H4B", contents, -1, 0, 0, -16, 16, 16, 16, 0, 0, 0, 0, 0, 0) for contents in [-2, -1])
    lumps[12] = b"".join(struct.pack("<2H", *edge) for edge in [(0, 0), (0, 1), (1, 2), (2, 3), (3, 0)])
    lumps[13] = struct.pack("<4i", 1, 2, 3, 4)
    lumps[14] = struct.pack("<9f7i", 0, 0, -16, 16, 16, 16, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1)
    offset = 124
    directory = []
    for lump in lumps:
        directory.append(struct.pack("<ii", offset, len(lump)))
        offset += len(lump)
    return struct.pack("<i", 30) + b"".join(directory) + b"".join(lumps)


def studio_fixture() -> bytes:
    """One bone, RLE frame-0 translation, textured triangle fan."""
    data = bytearray(244)
    def append(value: bytes) -> int:
        offset = len(data)
        data.extend(value)
        return offset
    bone = append(struct.pack("<32s8i12f", b"root", -1, 0, *([-1] * 6), 10, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1))
    sequence = append(bytes(176))
    animation = append(struct.pack("<6H", 12, 0, 0, 0, 0, 0) + struct.pack("<2Bh", 1, 1, 5))
    texture_header = append(bytes(80))
    pixels = append(bytes([1] * 256))
    append(bytes([21, 42, 63] * 256))
    skins = append(struct.pack("<h", 0))
    body = append(bytes(76))
    model = append(bytes(112))
    mesh = append(bytes(20))
    vertices = append(b"".join(struct.pack("<3f", *p) for p in [(0, 0, 0), (16, 0, 0), (0, 16, 0)]))
    bone_ids = append(bytes(3))
    triangles = append(struct.pack("<h", -3) + b"".join(struct.pack("<4h", *loop) for loop in [(0, 0, 0, 0), (1, 0, 16, 0), (2, 0, 0, 16)]) + struct.pack("<h", 0))
    struct.pack_into("<4si64si", data, 0, b"IDST", 10, b"fixture", len(data))
    header = [0] * 27
    header[1:3] = [1, bone]
    header[7:9] = [1, sequence]
    header[11:14] = [1, texture_header, pixels]
    header[14:17] = [1, 1, skins]
    header[17:19] = [1, body]
    struct.pack_into("<27i", data, 136, *header)
    struct.pack_into("<i", data, sequence + 124, animation)
    struct.pack_into("<64s4i", data, texture_header, b"texture", 0, 16, 16, pixels)
    struct.pack_into("<64s3i", data, body, b"body", 1, 1, model)
    struct.pack_into("<64sif10i", data, model, b"model", 0, 24, 1, mesh, 3, bone_ids, vertices, 0, 0, 0, 0, 0)
    struct.pack_into("<5i", data, mesh, 1, triangles, 0, 0, 0)
    return bytes(data)


class GoldSrcImportTests(unittest.TestCase):
    def test_entities_preserve_windows_paths_and_quotes(self):
        entities = goldsrc.parse_entities(b'{"wad" "C:\\maps\\dust.wad;" "message" "a \\"quote\\""}\0')
        self.assertEqual(entities[0]["wad"], "C:\\maps\\dust.wad;")
        self.assertEqual(entities[0]["message"], 'a "quote"')
        with self.assertRaises(goldsrc.FormatError):
            goldsrc.parse_entities(b'{"key"}')

    def test_wad_palette_and_mask_index_255(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.wad"
            path.write_bytes(wad(miptex("{fence"), "{fence"))
            textures = goldsrc.read_wad(path)
            name, image = goldsrc.decode_miptex(textures["{fence"])
            self.assertEqual(name, "{fence")
            self.assertEqual(image.getpixel((0, 0)), (21, 42, 63, 255))
            self.assertEqual(image.getpixel((1, 0)), (0, 0, 255, 0))

    def test_bad_mip_palette_is_rejected(self):
        texture = miptex()[:-4]
        with self.assertRaises(goldsrc.FormatError):
            goldsrc.decode_miptex(texture)

    def test_bsp_ranges_and_node_children_are_validated(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.bsp"
            path.write_bytes(bsp_fixture()[:123])
            with self.assertRaises(goldsrc.FormatError):
                goldsrc.read_bsp(path)
            data = bytearray(bsp_fixture())
            node_offset = struct.unpack_from("<i", data, 4 + 5 * 8)[0]
            struct.pack_into("<h", data, node_offset + 4, -300)
            path.write_bytes(data)
            with self.assertRaises(goldsrc.FormatError):
                goldsrc.read_bsp(path)

    def test_brush_placement_winding_and_uv(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.bsp"
            path.write_bytes(bsp_fixture())
            bsp = goldsrc.read_bsp(path)
            bsp["entities"].append({"model": "*0", "classname": "func_wall", "origin": "100 200 300", "angles": "0 90 0"})
            meshes, models = goldsrc._brush_meshes(bsp, [0])
            self.assertEqual(meshes[0]["faces"][0]["indices"], [0, 1, 2, 3])
            self.assertEqual(meshes[0]["faces"][0]["uv"], [[0, 1], [1, 1], [1, 0], [0, 0]])
            for actual, expected in zip(meshes[0]["vertices"][1], [100, 216, 300]):
                self.assertAlmostEqual(actual, expected)
            self.assertEqual(models[0]["root"], 0)
            self.assertEqual(models[0]["entity_index"], 1)

    def test_studio_pose_texture_and_fan(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "prop.mdl"
            path.write_bytes(studio_fixture())
            materials = goldsrc._Materials(root / "output")
            meshes = goldsrc._studio_meshes(path, {"model": "prop.mdl", "classname": "cycler_sprite", "origin": "100 0 0", "angles": "0 90 0"}, 2, root, materials)
            self.assertEqual(len(meshes[0]["faces"]), 1)
            for actual, expected in zip(meshes[0]["vertices"][0], [100, 15, 0]):
                self.assertAlmostEqual(actual, expected)
            self.assertEqual(meshes[0]["faces"][0]["uv"], [[0, 1], [1, 1], [0, 0]])
            self.assertFalse(meshes[0]["solid"])
            self.assertTrue((root / "output" / materials.materials[0]["texture"]).exists())

    def test_export_volume_keeps_room_air_and_floor_solid(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            (source / "test.bsp").write_bytes(bsp_fixture())
            scene = goldsrc.export_scene(source, root / "output")
            collision = scene["collision"]
            self.assertEqual(collision["nodes"][0]["children"], [-2, -1])
            self.assertEqual(collision["leaves"][1]["contents"], -1)
            self.assertEqual(collision["leaves"][0]["contents"], -2)
            self.assertEqual(scene["counts"]["bsp_faces"], 1)
            self.assertEqual(json.loads((root / "output" / "scene.json").read_text())["format"], 1)
            self.assertEqual(scene["issues"], [])

    def test_output_cannot_modify_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                goldsrc.export_scene(root, root / "output")

    @unittest.skipUnless(os.environ.get("BLOCKFIELD_GOLDSRC_SOURCE"), "Optional user-owned real map fixture")
    def test_supplied_map_has_complete_resources_and_air_spawns(self):
        with tempfile.TemporaryDirectory() as directory:
            scene = goldsrc.export_scene(Path(os.environ["BLOCKFIELD_GOLDSRC_SOURCE"]), Path(directory))
            self.assertFalse([issue for issue in scene["issues"] if issue["kind"] in {"missing_model", "unsupported_model", "missing_texture"}])
            placed = sum(entity.get("model", "").lower().endswith(".mdl") for entity in scene["entities"])
            self.assertEqual(scene["counts"]["placed_models"], placed)
            collision = scene["collision"]
            checked = 0
            for entity in scene["entities"]:
                if entity.get("classname") not in {"info_player_start", "info_player_deathmatch"}:
                    continue
                point = list(map(float, entity["origin"].split()))
                index = collision["models"][0]["root"]
                steps = 0
                while index >= 0:
                    node = collision["nodes"][index]
                    plane = collision["planes"][node["plane"]]
                    behind = sum(point[i] * plane["normal"][i] for i in range(3)) < plane["distance"]
                    index = node["children"][int(behind)]
                    steps += 1
                    self.assertLess(steps, len(collision["nodes"]))
                self.assertEqual(collision["leaves"][-index - 1]["contents"], -1)
                checked += 1
            self.assertGreater(checked, 0)


if __name__ == "__main__":
    unittest.main()
