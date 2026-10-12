"""Data acceptance for real downloaded-map survival conversions (no engine)."""
from pathlib import Path
from contextlib import redirect_stdout
import hashlib
import io
import tempfile
import unittest
import urllib.parse
from unittest.mock import patch
import zipfile

import numpy as np

import prepare_survival_maps as maps
from map_import.teardown import valid_spawn
from map_import.voxelize_helpers import write_bfmap


class SurvivalMapDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.packages = {}
        for key in maps.MAPS:
            path = maps.ROOT / f'game/assets/maps/survival_{key}.bfmap'
            cls.packages[key] = maps.read_bfmap(path)

    def test_two_actual_sources_and_bounded_geometry(self):
        self.assertEqual(len(self.packages), 2)
        for key, (cells, metadata) in self.packages.items():
            with self.subTest(map=key):
                width, height, depth = metadata['dimensions']
                self.assertLessEqual(width, 96)
                self.assertLessEqual(depth, 96)
                self.assertLessEqual(height, 32)
                self.assertLessEqual(width * depth, 8192)
                self.assertEqual(cells.shape, (depth, width, height))
                statistics = metadata['conversion']['statistics']
                self.assertGreater(statistics['retained_primitives'], 50)
                self.assertGreater(statistics['source_samples_in_crop'], 800_000)
                self.assertGreater(statistics['brush_samples_in_crop'], 100_000)
                self.assertGreater(np.count_nonzero(cells[:, :, 4:]), 2500)
                self.assertGreater(len(np.unique(cells[:, :, 4:][cells[:, :, 4:] != 0])), 20)
                self.assertTrue(np.all((cells == 0) | ((cells >> 24) == 1)))

    def test_source_identity_is_not_repo_mit(self):
        for key, (_, metadata) in self.packages.items():
            with self.subTest(map=key):
                spec = maps.MAPS[key]
                source = metadata['provenance']
                self.assertEqual(source['author'], spec['author'])
                self.assertEqual(source['archive_sha256'], spec['sha256'])
                self.assertTrue(source['source_url'].endswith(spec['workshop_id']))
                self.assertFalse(source['scripts_executed'])
                self.assertIn('not repository MIT', source['license'])
                self.assertGreater(len(source['source_files_sha256']), 20)
                self.assertTrue(all(len(value) == 64 for value in source['source_files_sha256'].values()))
                self.assertTrue(any(name.endswith('.vox') for name in source['source_files_sha256']))
                self.assertTrue(any(name.endswith('.xml') for name in source['source_files_sha256']))

    def test_body_clearance_supply_and_connected_distant_sectors(self):
        for key, (cells, metadata) in self.packages.items():
            with self.subTest(map=key):
                arena = metadata['survival_arena']
                self.assertTrue(arena['supported'])
                self.assertTrue(arena['single_surface'])
                self.assertFalse(arena['stacked_surfaces'])
                self.assertEqual(arena['floor_y'], 4)
                self.assertGreaterEqual(arena['navigation_ceiling'], 7)
                owner = arena['owner_spawn']
                self.assertEqual(metadata['spawn'], owner)
                self.assertEqual(arena['supply_point'], owner)
                self.assertTrue(valid_spawn(cells, owner))
                connected = maps.connected_floor(cells, owner)
                self.assertEqual(arena['connected_floor_columns'], len(connected))
                sectors = arena['spawn_sectors']
                self.assertGreaterEqual(len(sectors), 4)
                for point in sectors:
                    self.assertEqual(len(point), 3)
                    self.assertTrue(all(isinstance(value, (int, float)) for value in point))
                    self.assertTrue(valid_spawn(cells, point))
                    self.assertIn((int(point[0]), int(point[2])), connected)
                    self.assertGreaterEqual(float(np.linalg.norm(np.array(point) - owner)), 12)
                for index, first in enumerate(sectors):
                    for second in sectors[index + 1:]:
                        self.assertGreaterEqual(float(np.linalg.norm(np.array(first)-second)), 6)

    def test_archives_match_recorded_member_bytes(self):
        for key, (_, metadata) in self.packages.items():
            path = maps.CACHE / maps.MAPS[key]['archive']
            if not path.is_file():
                continue  # Built resources remain testable without ignored raw downloads.
            with self.subTest(map=key):
                self.assertEqual(maps.sha256(path), metadata['provenance']['archive_sha256'])
                with zipfile.ZipFile(path) as archive:
                    expected = {member.filename.replace('\\', '/'): hashlib.sha256(archive.read(member)).hexdigest()
                                for member in archive.infolist() if not member.is_dir()}
                self.assertEqual(expected, metadata['provenance']['source_files_sha256'])

    def test_preview_is_code_rendered_resource_and_provenance_present(self):
        for key in maps.MAPS:
            preview = maps.ROOT / f'game/assets/ui/menu/map_survival_{key}.png'
            self.assertTrue(preview.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'))
            self.assertLess(preview.stat().st_size, 100_000)
            provenance = maps.ROOT / f'game/assets/maps/survival_{key}_provenance.md'
            self.assertIn(maps.MAPS[key]['sha256'], provenance.read_text(encoding='utf-8'))

    def test_packed_black_and_axis_order_round_trip(self):
        cells = np.zeros((3, 4, 5), dtype=np.uint32)
        cells[2, 1, 3] = 0x01000000  # Solid black must remain distinct from air.
        cells[1, 3, 2] = 0x01ABCDEF
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'test.bfmap'
            write_bfmap(path, cells, {'dimensions': [4, 5, 3]})
            decoded, _ = maps.read_bfmap(path)
            np.testing.assert_array_equal(cells, decoded)

    def test_body_clearance_rejects_high_obstruction(self):
        cells = np.zeros((8, 8, 12), dtype=np.uint32)
        cells[:, :, :4] = 0x01000000
        self.assertTrue(valid_spawn(cells, [3.5, 4.01, 3.5]))
        cells[3, 3, 6] = 0x01FFFFFF
        self.assertFalse(valid_spawn(cells, [3.5, 4.01, 3.5]))
        with self.assertRaisesRegex(ValueError, 'Unsafe owner'):
            maps.connected_floor(cells, [3.5, 4.01, 3.5])

    def test_zip_traversal_rejected_before_outside_write(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'bad.zip'
            with zipfile.ZipFile(archive, 'w') as zipped:
                zipped.writestr('../outside.xml', '<scene/>')
            spec = {'archive': 'bad.zip', 'sha256': maps.sha256(archive),
                    'workshop_id': 'other', 'directory': 'mira'}
            with patch.object(maps, 'CACHE', root):
                with self.assertRaisesRegex(ValueError, 'Unsafe archive'):
                    maps.extract_archive(spec)
            self.assertFalse((root / 'outside.xml').exists())

    def test_public_page_archive_lookup_without_exposing_signed_query(self):
        for key, filename in [('minecraft_chunk', 'minecraft-page.html'), ('mira_hq', 'mira-page.html')]:
            path = maps.CACHE / filename
            if not path.is_file():
                continue
            with self.subTest(map=key):
                # Actual URL stays local and is never emitted to logs/docs.
                url = maps.archive_url_from_page(path.read_text(encoding='utf-8-sig'), maps.MAPS[key]['mirror_filename'])
                parsed = urllib.parse.urlsplit(url)
                self.assertEqual(parsed.scheme, 'https')
                self.assertTrue(parsed.path.endswith('.zip'))

    def test_reconversion_reproduces_exact_resource_bytes(self):
        if not all((maps.CACHE / spec['archive']).is_file() for spec in maps.MAPS.values()):
            self.skipTest('Ignored pinned raw archives are not present')
        actual_root = maps.ROOT
        with tempfile.TemporaryDirectory() as temporary:
            isolated_root = Path(temporary)
            with patch.object(maps, 'ROOT', isolated_root), redirect_stdout(io.StringIO()):
                for key in maps.MAPS:
                    maps.build_map(key)
            for key in maps.MAPS:
                for relative in (f'game/assets/maps/survival_{key}.bfmap',
                                 f'game/assets/ui/menu/map_survival_{key}.png'):
                    with self.subTest(resource=relative):
                        self.assertEqual((isolated_root / relative).read_bytes(), (actual_root / relative).read_bytes())


if __name__ == '__main__':
    unittest.main(verbosity=2)
