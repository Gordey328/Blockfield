"""Teardown binary/scene fixtures and independent native-map acceptance checks.

Run: python -m unittest tests.tools.test_teardown_import -v
Optional BLOCKFIELD_TEARDOWN_SOURCE inventories the user's local VOX files;
BLOCKFIELD_TEARDOWN_MAP validates an already converted BFM1 package. Neither
source nor generated map is distributed with the repository.
"""
from __future__ import annotations

import itertools
from collections import deque
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zlib

import numpy as np

from tools.map_import import teardown, teardown_vox


def chunk(name: str, content: bytes = b"", children: bytes = b"") -> bytes:
    return name.encode("ascii") + struct.pack("<II", len(content), len(children)) + content + children


def dictionary(values: dict[str, str]) -> bytes:
    pieces = [struct.pack("<i", len(values))]
    for key, value in values.items():
        for item in (key, value):
            encoded = str(item).encode("utf-8")
            pieces.append(struct.pack("<i", len(encoded)) + encoded)
    return b"".join(pieces)


def transform(key: int, child: int, *, name: str = "", translation=(0, 0, 0),
              rotation: int = 4, layer: int = -1, hidden: bool = False) -> bytes:
    attrs = {"_name": name} if name else {}
    if hidden:
        attrs["_hidden"] = "1"
    frame = {"_t": " ".join(map(str, translation)), "_r": str(rotation)}
    return chunk("nTRN", struct.pack("<i", key) + dictionary(attrs)
                 + struct.pack("<4i", child, -1, layer, 1) + dictionary(frame))


def group(key: int, children: list[int]) -> bytes:
    return chunk("nGRP", struct.pack("<i", key) + dictionary({})
                 + struct.pack("<i", len(children))
                 + b"".join(struct.pack("<i", child) for child in children))


def shape(key: int, model: int) -> bytes:
    return chunk("nSHP", struct.pack("<i", key) + dictionary({})
                 + struct.pack("<2i", 1, model) + dictionary({}))


def vox_fixture(models=(((2, 2, 2), [(0, 0, 0, 1), (1, 1, 1, 2)]),),
                graph: bytes = b"", *, imap: bytes | None = None,
                colors=((0, 0, 0, 255), (21, 42, 63, 255))) -> bytes:
    contents = []
    for size, voxels in models:
        contents.append(chunk("SIZE", struct.pack("<3i", *size)))
        contents.append(chunk("XYZI", struct.pack("<i", len(voxels))
                              + b"".join(bytes(voxel) for voxel in voxels)))
    palette = list(colors) + [(70, 80, 90, 255)] * (256 - len(colors))
    contents.extend((graph, chunk("RGBA", b"".join(bytes(color) for color in palette))))
    if imap is not None:
        contents.append(chunk("IMAP", imap))
    return b"VOX " + struct.pack("<I", 150) + chunk("MAIN", children=b"".join(contents))


def read_bfm_independently(path: Path) -> tuple[np.ndarray, dict]:
    """Parse package without converter helpers: BFM1 LE frame, BE Y-fast cells."""
    data = path.read_bytes()
    if len(data) < 16 or data[:4] != b"BFM1":
        raise ValueError("Not a BFM1 package")
    metadata_size, raw_size, compressed_size = struct.unpack_from("<III", data, 4)
    if not 1 <= metadata_size <= 1024 * 1024 or len(data) != 16 + metadata_size + compressed_size:
        raise ValueError("Invalid BFM1 framing")
    metadata = json.loads(data[16:16 + metadata_size].decode("utf-8", errors="strict"))
    width, height, depth = metadata["dimensions"]
    if metadata["format"] != 1 or not (1 <= width <= 512 and 1 <= height <= 64 and 1 <= depth <= 512):
        raise ValueError("Invalid BFM1 dimensions")
    if raw_size != width * height * depth * 4 or raw_size > 64 * 1024 * 1024:
        raise ValueError("Invalid BFM1 raw byte count")
    decoder = zlib.decompressobj()
    raw = decoder.decompress(data[16 + metadata_size:], raw_size + 1)
    if len(raw) != raw_size or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
        raise ValueError("Invalid BFM1 compressed stream")
    cells = np.frombuffer(raw, dtype=">u4").reshape((depth, width, height))
    if np.any((cells != 0) & ((cells & 0xFF000000) != 0x01000000)):
        raise ValueError("Invalid solid color encoding")
    return cells, metadata


def standing_error(cells: np.ndarray, feet) -> str:
    """Independent exact 0.9×2.7 BFM standing footprint and four-corner support."""
    feet = np.asarray(feet, dtype=np.float64)
    if feet.shape != (3,) or not np.isfinite(feet).all():
        return "nonfinite feet"
    depth, width, height = cells.shape
    low = feet - (.45, 0, .45)
    high = feet + (.45, 2.7, .45)
    if low[0] < 0 or low[1] < 1 or low[2] < 0 or high[0] > width or high[1] > height or high[2] > depth:
        return "body outside map"
    minimum = np.floor(low + .0001).astype(int)
    maximum = np.floor(high - .0001).astype(int)
    occupied = cells[minimum[2]:maximum[2] + 1,
                     minimum[0]:maximum[0] + 1,
                     minimum[1]:maximum[1] + 1]
    if np.any(occupied):
        return "body overlaps solid cells"
    for dx, dz in itertools.product((-.4499, .4499), repeat=2):
        x, y, z = np.floor(feet + (dx, -.05, dz)).astype(int)
        if not cells[z, x, y]:
            return "footprint lacks four-corner support"
    return ""


def standing_nodes(cells: np.ndarray) -> np.ndarray:
    """Cell-centered supported feet with three clear body cells (2.7+.025<3)."""
    occupied = cells != 0
    nodes = np.zeros(cells.shape, dtype=np.bool_)
    nodes[:, :, 1:-2] = (occupied[:, :, :-3] & ~occupied[:, :, 1:-2]
                         & ~occupied[:, :, 2:-1] & ~occupied[:, :, 3:])
    return nodes


def connectivity_probe(cells: np.ndarray, start_feet, destination_feet) -> dict:
    """Conservative four-way graph; full body sweep, at most one block step.

    This is a map-space diagnostic. It does not simulate acceleration, jumping,
    crouching or source corner-climb code and cannot establish gameplay acceptance.
    The source/destination markers each choose their nearest supported node.
    """
    nodes = standing_nodes(cells)
    indices = np.argwhere(nodes)  # (z,x,y) feet base
    if not len(indices):
        raise ValueError("Map has no supported standing cells")
    points = indices[:, [1, 2, 0]].astype(np.float64) + (.5, .025, .5)

    def nearest(feet):
        distances = np.linalg.norm(points - feet, axis=1)
        index = int(np.argmin(distances))
        return tuple(map(int, indices[index])), points[index].tolist(), float(distances[index])

    start, start_point, start_distance = nearest(np.asarray(start_feet))
    finish, finish_point, finish_distance = nearest(np.asarray(destination_feet))
    depth, width, height = cells.shape
    visited = {start}
    queue = deque([(start, 0)])
    path_length = None
    while queue:
        (z, x, y), distance = queue.popleft()
        if (z, x, y) == finish:
            path_length = distance
            break
        for dx, dz in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, nz = x + dx, z + dz
            if not (0 <= nx < width and 0 <= nz < depth):
                continue
            for ny in (y, y + 1, y - 1):
                node = nz, nx, ny
                if not (1 <= ny <= height - 3) or not nodes[node] or node in visited:
                    continue
                # At the crossing the .9-wide body spans both columns. Raise
                # it to the higher feet before moving, ensuring upper clearance.
                crossing_y = max(y, ny)
                if np.any(cells[z, x, crossing_y:crossing_y + 3]) or np.any(cells[nz, nx, crossing_y:crossing_y + 3]):
                    continue
                visited.add(node)
                queue.append((node, distance + 1))
    return {"standing_nodes": int(len(indices)), "connected": path_length is not None,
            "path_steps": path_length, "visited_nodes": len(visited),
            "start_feet": start_point, "start_marker_distance": start_distance,
            "destination_feet": finish_point, "destination_marker_distance": finish_distance}


class TeardownVoxTests(unittest.TestCase):
    def test_vox_palette_keeps_solid_black_and_indices(self):
        parsed = teardown_vox.read_vox(vox_fixture())
        self.assertEqual(parsed.models[0].size, (2, 2, 2))
        np.testing.assert_array_equal(parsed.models[0].voxels, [[0, 0, 0, 1], [1, 1, 1, 2]])
        self.assertEqual(int(parsed.palette[0]), 0)
        self.assertEqual(int(parsed.palette[1]), 0x01000000)
        self.assertEqual(int(parsed.palette[2]), 0x01152A3F)

    def test_imap_display_reorder_does_not_change_stored_rgb(self):
        imap = bytearray(list(range(1, 256)) + [0])
        imap[0], imap[1] = imap[1], imap[0]
        parsed = teardown_vox.read_vox(vox_fixture(imap=bytes(imap)))
        self.assertEqual(list(parsed.imap[:2]), [2, 1])
        self.assertEqual(int(parsed.palette[parsed.models[0].voxels[0, 3]]), 0x01000000)
        self.assertEqual(int(parsed.palette[parsed.models[0].voxels[1, 3]]), 0x01152A3F)

    def test_truncated_invalid_or_duplicated_voxels_are_rejected(self):
        fixtures = [vox_fixture()[:-1], b"wrong framing",
                    vox_fixture(models=[((2, 2, 2), [(2, 0, 0, 1)])]),
                    vox_fixture(models=[((2, 2, 2), [(0, 0, 0, 0)])]),
                    vox_fixture(models=[((2, 2, 2), [(0, 0, 0, 1), (0, 0, 0, 2)])]),
                    vox_fixture(models=[((0, 2, 2), [])]),
                    vox_fixture(imap=bytes(256))]
        for value in fixtures:
            with self.subTest(length=len(value)):
                with self.assertRaises(ValueError):
                    teardown_vox.read_vox(value)

    def test_unknown_chunks_preserve_framing(self):
        parsed = teardown_vox.read_vox(vox_fixture(graph=chunk("TEST", b"opaque extension")))
        self.assertEqual(len(parsed.models), 1)
        self.assertEqual(parsed.chunks["TEST"], 1)
        invalid = vox_fixture(graph=b"TEST" + struct.pack("<II", 0xFFFFFFFF, 0))
        with self.assertRaises(ValueError):
            teardown_vox.read_vox(invalid)

    def test_rotation_codes_use_signed_row_major_axes(self):
        np.testing.assert_array_equal(teardown_vox.decode_rotation(4), np.eye(3))
        # Swap x/y and negate new x: +90 degrees about MV Z.
        np.testing.assert_array_equal(teardown_vox.decode_rotation(17), [[0, -1, 0], [1, 0, 0], [0, 0, 1]])
        for code in (3, 0, 12, 128, -1):
            with self.subTest(code=code):
                with self.assertRaises(ValueError):
                    teardown_vox.decode_rotation(code)

    def test_full_graph_retains_parent_rotation_and_local_translation(self):
        graph = (transform(0, 1, translation=(10, 20, 30), rotation=17)
                 + group(1, [2]) + transform(2, 3, translation=(2, 3, 4)) + shape(3, 0))
        parsed = teardown_vox.read_vox(vox_fixture(graph=graph))
        instance, = parsed.instances()
        np.testing.assert_allclose(instance.translation, [7, 22, 34])
        # First cell center is -.5 on each axis before the graph transform.
        np.testing.assert_allclose(instance.centers(), [[7.5, 21.5, 33.5], [6.5, 22.5, 34.5]])

    def test_named_object_excludes_siblings_and_resets_editor_layout(self):
        models = [((3, 5, 2), [(0, 0, 0, 1)]), ((2, 2, 2), [(0, 0, 0, 2)])]
        graph = (transform(0, 1) + group(1, [2, 4])
                 + transform(2, 3, name="door", translation=(150, -60, 20), rotation=17) + shape(3, 0)
                 + transform(4, 5, name="wall", translation=(30, 40, 10)) + shape(5, 1))
        parsed = teardown_vox.read_vox(vox_fixture(models=models, graph=graph))
        instance, = parsed.instances("door")
        self.assertIs(instance.model, parsed.models[0])
        np.testing.assert_array_equal(instance.rotation, [[0, -1, 0], [1, 0, 0], [0, 0, 1]])
        # Odd dimensions must remain centered after rotation; bottom is Z=0.
        np.testing.assert_allclose(instance.centers(), [[2., -1., .5]])
        self.assertEqual(len(parsed.instances()), 2)
        with self.assertRaises(ValueError):
            parsed.instances("missing")

    def test_hidden_graph_and_hidden_layers_are_skipped(self):
        graph = (transform(0, 1) + group(1, [2, 4, 6])
                 + transform(2, 3, hidden=True) + shape(3, 0)
                 + transform(4, 5, layer=8) + shape(5, 0)
                 + transform(6, 7) + shape(7, 0)
                 + chunk("LAYR", struct.pack("<i", 8) + dictionary({"_hidden": "1"}) + struct.pack("<i", -1)))
        parsed = teardown_vox.read_vox(vox_fixture(graph=graph))
        self.assertEqual(len(parsed.instances()), 1)

    def test_missing_graph_references_and_duplicate_ids_are_rejected(self):
        for graph in (transform(0, 7), shape(0, 7), shape(0, 0) + shape(0, 0)):
            with self.subTest(graph=graph[:4]):
                with self.assertRaises(ValueError):
                    teardown_vox.read_vox(vox_fixture(graph=graph))

    def test_cyclic_disconnected_or_hidden_malformed_graph_is_rejected(self):
        invalid = [transform(0, 1) + group(1, [0]),
                   shape(0, 0) + transform(1, 2) + group(2, [1]),
                   transform(0, 1, hidden=True, rotation=0) + shape(1, 0),
                   transform(0, 1, hidden=True, translation=(1, 2)) + shape(1, 0)]
        for graph in invalid:
            with self.subTest(graph_bytes=len(graph)):
                with self.assertRaises(ValueError):
                    teardown_vox.read_vox(vox_fixture(graph=graph))


class TeardownSceneTests(unittest.TestCase):
    def test_nasa_euler_and_nested_xml_translation(self):
        # Known quarter turns: Ry(90)Rx(90). The order affects all three axes.
        expected = [[0, 1, 0], [0, 0, -1], [-1, 0, 0]]
        np.testing.assert_allclose(teardown.rotation_matrix([90, 90, 0]), expected, atol=1e-12)
        parent = teardown.compose_transform(np.eye(4), ET.fromstring('<group pos="10 20 30" rot="0 90 0"/>'))
        combined = teardown.compose_transform(parent, ET.fromstring('<vox pos="1 2 3" rot="90 0 0"/>'))
        np.testing.assert_allclose(combined[:3, 3], [13, 22, 29])
        np.testing.assert_allclose(combined[:3, :3], expected, atol=1e-12)

    def test_default_selects_map_hidden_layers_and_prefab_anchor(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'main.xml').write_text('<scene><script file="menu.lua"/></scene>')
            (root / 'part.xml').write_text('<prefab><group pos="99 98 97" rot="50 60 70">'
                                          '<voxbox pos="2 3 4" size="10 20 30" color="0 0 0"/>'
                                          '</group></prefab>')
            (root / 'de_dust2.xml').write_text('<scene><instance pos="10 20 30" rot="0 90 0" file="MOD/part.xml"/>'
                                              '<group layer="hidden"><vox file="missing.vox"/></group>'
                                              '<layers><layer name="hidden" visible="false"/></layers></scene>')
            scene = teardown.collect_scene(root)
            self.assertEqual(scene.scene_path.name, 'de_dust2.xml')
            item, = scene.items
            self.assertEqual(item.kind, 'voxbox')
            self.assertEqual(item.color, 0x01000000)
            np.testing.assert_allclose(item.transform[:3, 3], [14, 23, 28])
            np.testing.assert_allclose(item.transform[:3, :3], [[0, 0, 1], [0, 1, 0], [-1, 0, 0]], atol=1e-12)
            self.assertEqual(scene.report['hidden_nodes']['vox'], 1)
            with self.assertRaises(ValueError):
                teardown.collect_scene(root, 'main.xml')

    def test_xml_named_object_uses_magica_axes_and_meter_scale(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            graph = (transform(0, 1) + group(1, [2, 4])
                     + transform(2, 3, name='selected', translation=(50, 100, 10)) + shape(3, 0)
                     + transform(4, 5, name='other') + shape(5, 1))
            (root / 'part.vox').write_bytes(vox_fixture(models=[((2, 2, 2), [(0, 0, 0, 1)]),
                                                               ((2, 2, 2), [(1, 1, 1, 2)])], graph=graph))
            (root / 'de_dust2.xml').write_text('<scene><vox pos="2 3 4" file="MOD/part.vox" object="selected"/></scene>')
            scene = teardown.collect_scene(root)
            item, = scene.items
            # MV (-.5,-.5,+.5) -> Teardown (-.05,+.05,+.05).
            np.testing.assert_allclose(item.centers(), [[1.95, 3.05, 4.05]])
            self.assertEqual(scene.report['voxel_instances'], 1)

    def test_external_paths_cycles_invalid_positions_and_scale_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'loop.xml').write_text('<prefab><group><instance file="MOD/loop.xml"/></group></prefab>')
            invalid = ['<scene><vox file="MOD/../outside.vox"/></scene>',
                       '<scene><instance file="MOD/loop.xml"/></scene>',
                       '<scene><voxbox pos="nan 0 0" size="1 1 1"/></scene>',
                       '<scene><voxbox scale="2" size="1 1 1"/></scene>',
                       '<scene><voxbox size="0 2 3"/></scene>']
            for text in invalid:
                with self.subTest(xml=text):
                    (root / 'de_dust2.xml').write_text(text)
                    with self.assertRaises(ValueError):
                        teardown.collect_scene(root)

    def test_unknown_voxscript_is_counted_without_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'danger.lua').write_text('error("MUST NOT EXECUTE")')
            (root / 'de_dust2.xml').write_text('<scene><voxbox size="2 2 2"/>'
                                              '<voxscript file="MOD/danger.lua"/></scene>')
            scene = teardown.collect_scene(root)
            self.assertEqual(len(scene.items), 1)
            self.assertEqual(scene.report['omitted_nodes']['unsupported_voxscript:danger.lua'], 1)

    def test_coarsening_votes_use_y_fast_indices_and_boundary_bins(self):
        points = [[.05, .05, .05], [.15, .15, .15], [.05, .65, .05],
                  [.65, .05, .05], [.05, .05, .65]]
        keys, counts = teardown.coarsen_points(points, [0x01000000, 0x01112233, 0x01112233,
                                                       0x01000000, 0x01112233], [0, 0, 0], .6, [3, 5, 2])
        self.assertEqual((keys >> np.uint64(24)).tolist(), [0, 0, 1, 5, 15])
        self.assertEqual((keys & np.uint64(0xFFFFFF)).tolist(), [0, 0x112233, 0x112233, 0, 0x112233])
        self.assertEqual(counts.tolist(), [1, 1, 1, 1, 1])
        with self.assertRaises(ValueError):
            teardown.coarsen_points([[-.05, 0, 0]], 0x01000000, [0, 0, 0], .6, [3, 5, 2])

    def test_reserved_helper_filter_keeps_legitimate_red_and_uses_imap_slots(self):
        colors = [(70, 80, 90, 255)] * 256
        colors[0] = colors[254] = (255, 0, 0, 255)
        colors[1] = (0, 0, 0, 255)
        colors[2] = (17, 34, 51, 255)
        models = [((4, 1, 1), [(0, 0, 0, 1), (1, 0, 0, 2), (2, 0, 0, 3), (3, 0, 0, 255)])]
        normal = teardown_vox.read_vox(vox_fixture(models=models, colors=colors))
        instance, = normal.instances()
        self.assertEqual(int(normal.palette[1]), int(normal.palette[255]))
        np.testing.assert_array_equal(teardown.physical_voxel_mask(normal, instance), [True, True, True, False])
        # Display/material slot1 references raw255; slot255 references raw1.
        # RGB stays stored-index based, but reserved-slot membership must invert
        # IMAP rather than dropping any raw255 or any red-colored voxel.
        imap = bytearray(list(range(1, 256)) + [0])
        imap[0], imap[254] = imap[254], imap[0]
        reordered = teardown_vox.read_vox(vox_fixture(models=models, colors=colors, imap=bytes(imap)))
        selected, = reordered.instances()
        np.testing.assert_array_equal(teardown.physical_voxel_mask(reordered, selected), [False, True, True, True])
        self.assertEqual(int(reordered.palette[1]), 0x01FF0000)
        self.assertEqual(int(reordered.palette[255]), 0x01FF0000)

    def test_reserved_helpers_do_not_vote_or_become_solid_coarse_cells(self):
        colors = [(70, 80, 90, 255)] * 256
        colors[0] = colors[254] = (255, 0, 0, 255)
        colors[1] = (0, 0, 0, 255)
        colors[2] = (17, 34, 51, 255)
        asset = teardown_vox.read_vox(vox_fixture(
            models=[((4, 1, 1), [(0, 0, 0, 1), (1, 0, 0, 2), (2, 0, 0, 3), (3, 0, 0, 255)])], colors=colors))
        instance, = asset.instances()
        position = np.eye(4)
        position[:3, 3] = [.3, 1., .3]
        scene = teardown.SceneData(Path('.'), Path('synthetic.xml'),
                                    items=[teardown.SceneItem('vox', position, asset, instance)])
        with redirect_stdout(io.StringIO()):
            cells, metadata, report = teardown.voxelize_scene(scene, .6)
        point = np.asarray([.3, 1.05, .3])
        x, y, z = np.floor((point - metadata['conversion']['origin_meters']) / .6).astype(int)
        # Three physical votes tie: actual black wins the deterministic RGB
        # tie. The excluded red helper would otherwise make red the plurality.
        self.assertEqual(int(cells[z, x, y]), 0x01000000)
        self.assertEqual(metadata['conversion']['source_voxel_samples'], 3)

    def test_ground_uses_red_height_blue_surface_and_ignores_green(self):
        image = np.array([[[2, 0, 32], [2, 255, 128], [0, 127, 96], [0, 255, 0]]], dtype=np.uint8)
        item = teardown.SceneItem('ground', np.eye(4), image=image)
        cells = np.zeros((1, 4, 5), dtype=np.uint32)
        report = teardown.rasterize_ground(item, cells, [0, 0, 0], .1)
        # Source sand=(.737,.671,.561), red rock=(.475,.329,.294).
        self.assertEqual(cells[0, 0, :].tolist(), [0x01BCAB8F, 0x01BCAB8F, 0x0179544B, 0, 0])
        self.assertEqual(cells[0, 1, :].tolist(), [0x01BCAB8F, 0x01BCAB8F, 0x01BCAB8F, 0, 0])
        self.assertEqual(cells[0, 2, :].tolist(), [0x015B5854, 0, 0, 0, 0])
        self.assertEqual(cells[0, 3, :].tolist(), [0, 0, 0, 0, 0])
        self.assertEqual(report['source_ground_voxels'], 7)
        changed = image.copy()
        changed[:, :, 1] = 91
        other = np.zeros_like(cells)
        teardown.rasterize_ground(teardown.SceneItem('ground', np.eye(4), image=changed), other, [0, 0, 0], .1)
        np.testing.assert_array_equal(other, cells)

    def test_coarse_ground_uses_highest_fine_column(self):
        image = np.array([[[1, 0, 128], [5, 0, 128]], [[2, 0, 128], [3, 0, 128]]], dtype=np.uint8)
        cells = np.zeros((1, 1, 6), dtype=np.uint32)
        report = teardown.rasterize_ground(teardown.SceneItem('ground', np.eye(4), image=image), cells, [0, 0, 0], .2)
        self.assertEqual(cells[0, 0, :].tolist(), [0x01BCAB8F, 0x01BCAB8F, 0x01BCAB8F, 0, 0, 0])
        self.assertEqual(report['source_ground_voxels'], 15)
        self.assertEqual(report['coarse_ground_columns'], 1)

    def test_spawn_relocation_checks_full_body_and_does_not_carve(self):
        cells = np.zeros((7, 7, 7), dtype=np.uint32)
        cells[:, :, 0] = 0x01000000
        cells[3, 3, 2] = 0x01112233
        before = cells.copy()
        chosen, count = teardown.choose_spawn(cells, [3.5, 1.01, 3.5])
        self.assertGreater(count, 0)
        self.assertEqual(standing_error(cells, chosen), '')
        np.testing.assert_array_equal(cells, before)
        self.assertFalse(teardown.valid_spawn(cells, [3.5, 1.01, 3.5]))
        cells.fill(0)
        with self.assertRaises(ValueError):
            teardown.choose_spawn(cells, [3.5, 1.01, 3.5])

    def test_full_conversion_keeps_room_air_and_writes_portable_package(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            source.mkdir()
            # A closed six-face shell, not a solid bounding box.
            occupied = [(x, y, z, 1) for x, y, z in itertools.product(range(50), repeat=3)
                        if min(x, y, z) == 0 or max(x, y, z) == 49]
            (source / 'room.vox').write_bytes(vox_fixture(models=[((50, 50, 50), occupied)]))
            (source / 'de_dust2.xml').write_text('<scene><vox file="MOD/room.vox"/>'
                                                '<spawnpoint pos="0 1 0"/></scene>')
            output = root / 'converted' / 'room.bfmap'
            with redirect_stdout(io.StringIO()):
                report = teardown.convert_map(source, output, meters_per_block=.6)
            cells, metadata = read_bfm_independently(output)
            origin = np.asarray(metadata['conversion']['origin_meters'])

            def cell_at(point):
                x, y, z = np.floor((np.asarray(point) - origin) / .6).astype(int)
                return int(cells[z, x, y])

            self.assertEqual(cell_at([0, 2, 0]), 0)
            self.assertEqual(cell_at([-2.45, 2, 0]), 0x01000000)
            self.assertEqual(standing_error(cells, metadata['spawn']), '')
            self.assertEqual(report['solid_cells'], int(np.count_nonzero(cells)))
            self.assertEqual(report['raw_bytes'], int(cells.size * 4))
            self.assertTrue(output.with_suffix('.report.json').is_file())
            self.assertTrue(output.with_name('room-topdown.png').is_file())

    def test_output_cannot_overwrite_user_source(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            text = '<scene><voxbox size="10 10 10"/></scene>'
            scene_path = source / 'de_dust2.xml'
            scene_path.write_text(text)
            for output in (scene_path, source / 'output' / 'test.bfmap'):
                with self.subTest(path=str(output)):
                    with self.assertRaises(ValueError):
                        teardown.convert_map(source, output)
            self.assertEqual(scene_path.read_text(), text)

    def test_tall_map_is_rejected_instead_of_cropped_and_scale_is_bounded(self):
        scene = teardown.SceneData(Path('.'), Path('tall.xml'),
                                    items=[teardown.SceneItem('voxbox', np.eye(4),
                                                            size=np.array([1, 1000, 1]), color=0x01000000)])
        for scale in (.6, .01, 5., float('nan'), float('inf')):
            with self.subTest(scale=scale):
                with self.assertRaises(ValueError):
                    teardown.voxelize_scene(scene, scale)


class IndependentMapOracleTests(unittest.TestCase):
    def test_standing_oracle_detects_wall_ceiling_and_corner_hole(self):
        cells = np.zeros((8, 8, 8), dtype=np.uint32)
        cells[:, :, 0] = 0x01000000
        self.assertEqual(standing_error(cells, [3.5, 1.025, 3.5]), "")
        cells[3, 3, 3] = 0x01112233
        self.assertEqual(standing_error(cells, [3.5, 1.025, 3.5]), "body overlaps solid cells")
        cells[3, 3, 3] = 0
        cells[3, 4, 0] = 0
        self.assertEqual(standing_error(cells, [4., 1.025, 3.5]), "footprint lacks four-corner support")
        self.assertEqual(standing_error(cells, [.3, 1.025, 3.5]), "body outside map")

    def test_standing_nodes_and_connectivity_preserve_hollow_room(self):
        cells = np.zeros((9, 9, 9), dtype=np.uint32)
        cells[:, :, 0] = 0x01000000
        # Enclosed room with one opening. It must remain air, and the full body
        # must pass the opening; a one-block-high gap is insufficient.
        cells[2:7, 2, 1:6] = cells[2:7, 6, 1:6] = 0x01112233
        cells[2, 2:7, 1:6] = cells[6, 2:7, 1:6] = 0x01112233
        cells[2:7, 2:7, 6] = 0x01112233
        cells[2, 4, 1:4] = 0
        nodes = standing_nodes(cells)
        self.assertTrue(nodes[4, 4, 1])
        self.assertFalse(nodes[4, 2, 1])
        for z, x, y in np.argwhere(nodes):
            self.assertEqual(standing_error(cells, [x + .5, y + .025, z + .5]), "")
        self.assertTrue(connectivity_probe(cells, [4.5, 1.025, .5], [4.5, 1.025, 4.5])["connected"])
        cells[2, 4, 2] = 0x01000000
        self.assertFalse(connectivity_probe(cells, [4.5, 1.025, .5], [4.5, 1.025, 4.5])["connected"])

    def test_connectivity_step_requires_head_clearance(self):
        cells = np.zeros((1, 5, 7), dtype=np.uint32)
        cells[:, :, 0] = 0x01000000
        cells[:, 2:, 1] = 0x01000000
        self.assertTrue(connectivity_probe(cells, [1.5, 1.025, .5], [3.5, 2.025, .5])["connected"])
        # Both endpoint standing volumes fit; the raised crossing does not.
        cells[0, 1, 4] = 0x01000000
        self.assertEqual(standing_error(cells, [1.5, 1.025, .5]), "")
        self.assertEqual(standing_error(cells, [2.5, 2.025, .5]), "")
        self.assertFalse(connectivity_probe(cells, [1.5, 1.025, .5], [3.5, 2.025, .5])["connected"])

    @unittest.skipUnless(os.environ.get("BLOCKFIELD_TEARDOWN_SOURCE"), "Optional user-owned real map fixture")
    def test_supplied_vox_inventory_independent_raw_chunk_counts(self):
        source = Path(os.environ["BLOCKFIELD_TEARDOWN_SOURCE"])
        paths = list(source.rglob("*.vox"))
        model_count = voxel_count = imap_count = 0
        for path in paths:
            raw = path.read_bytes()
            self.assertEqual(raw[:8], b"VOX " + struct.pack("<I", 150))
            expected_models = expected_voxels = imaps = 0

            def scan(start, end):
                nonlocal expected_models, expected_voxels, imaps
                while start < end:
                    name, count, children = struct.unpack_from("<4sII", raw, start)
                    content = start + 12
                    self.assertLessEqual(content + count + children, end)
                    if name == b"SIZE":
                        expected_models += 1
                    if name == b"XYZI":
                        expected_voxels += struct.unpack_from("<I", raw, content)[0]
                    imaps += name == b"IMAP"
                    scan(content + count, content + count + children)
                    start = content + count + children

            scan(8, len(raw))
            parsed = teardown_vox.read_vox(path)
            self.assertEqual(len(parsed.models), expected_models, str(path))
            self.assertEqual(sum(len(model.voxels) for model in parsed.models), expected_voxels, str(path))
            model_count += expected_models
            voxel_count += expected_voxels
            imap_count += imaps
        self.assertEqual((len(paths), model_count, voxel_count, imap_count), (347, 457, 9_055_974, 257))

    @unittest.skipUnless(os.environ.get("BLOCKFIELD_TEARDOWN_MAP"), "Optional converted local package fixture")
    def test_supplied_package_has_valid_cells_and_exact_standing_spawn(self):
        path = Path(os.environ["BLOCKFIELD_TEARDOWN_MAP"])
        cells, metadata = read_bfm_independently(path)
        self.assertGreater(int(np.count_nonzero(cells)), 10_000)
        self.assertTrue(metadata["title"].strip())
        self.assertEqual(standing_error(cells, metadata["spawn"]), "")
        # Keep actual-map count proof tied to its conversion report when supplied.
        report_path = os.environ.get("BLOCKFIELD_TEARDOWN_REPORT")
        if report_path:
            report = json.loads(Path(report_path).read_text(encoding="utf-8"))
            self.assertEqual(report["solid_cells"], int(np.count_nonzero(cells)))

    @unittest.skipUnless(os.environ.get("BLOCKFIELD_TEARDOWN_MAP"), "Optional converted local package fixture")
    def test_supplied_dust2_t_and_ct_supported_connectivity_diagnostic(self):
        path = Path(os.environ["BLOCKFIELD_TEARDOWN_MAP"])
        cells, metadata = read_bfm_independently(path)
        conversion = metadata['conversion']
        # Independently summed source group translations in de_dust2.xml.
        source_ct = np.array([17.16998, 2.58, -23.60001])
        target = (source_ct - conversion['origin_meters']) / conversion['meters_per_block']
        probe = connectivity_probe(cells, metadata['spawn'], target)
        self.assertEqual(probe['standing_nodes'], conversion['safe_standing_candidates'])
        self.assertLess(probe['destination_marker_distance'], 3.)
        self.assertTrue(probe['connected'], json.dumps(probe))
        print('TEARDOWN_CONNECTIVITY ' + json.dumps(probe, separators=(',', ':')))


if __name__ == "__main__":
    unittest.main()
