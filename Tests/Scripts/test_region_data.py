import copy
import json
import pathlib
import sys
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'Scripts'))
from region_data import load_regions, validate_network, validate_raw, summarize_update, write_json


class RegionDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.regions = load_regions(ROOT/'Data/regions.json')
        cls.network = json.loads((ROOT/'Data/kokura-network.json').read_text())

    def test_all_catalogued_networks(self):
        for key, definition in self.regions.items():
            with self.subTest(region=key):
                validate_network(json.loads((ROOT/f'Data/{key}-network.json').read_text()), definition)

    def test_invalid_networks_rejected_before_import(self):
        mutations = [
            lambda n: n.update(id='wrong-region'),
            lambda n: n.update(edges=[]),
            lambda n: n['nodes'].append(n['nodes'][0]),
            lambda n: n['edges'][0].update(to='missing'),
            lambda n: n['edges'][0].update(distance=float('nan')),
            lambda n: n['edges'][0].update(direction='car-only'),
            lambda n: n['edges'][0].update(shape=[]),
            lambda n: n['edges'][0]['shape'][0].update(latitude=0),
            lambda n: n.update(acquiredAt='unknown'),
            lambda n: n['destinations'][0].update(nodeID='missing'),
            lambda n: n['bounds'].update(north=-1),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                network = copy.deepcopy(self.network)
                mutate(network)
                with self.assertRaises(ValueError):
                    validate_network(network, self.regions['kokura'])

    def test_catalog_rejects_duplicates_and_unsafe_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)/'regions.json'
            definition = self.regions['kokura']
            for definitions in ([definition, definition], [dict(definition, key='../outside')], [dict(definition, license='missing')]):
                path.write_text(json.dumps(definitions))
                with self.assertRaises(ValueError):
                    load_regions(path)

    def test_raw_requires_complete_nodes_and_source_timestamp(self):
        raw = {'osm3s': {'timestamp_osm_base': '2026-09-26T08:24:02Z'}, 'elements': [
            {'type': 'node', 'id': 1, 'lat': 33.88, 'lon': 130.88},
            {'type': 'node', 'id': 2, 'lat': 33.881, 'lon': 130.88},
            {'type': 'way', 'id': 3, 'nodes': [1, 2], 'tags': {'highway': 'footway'}}]}
        validate_raw(raw)
        raw['elements'].pop(0)
        with self.assertRaises(ValueError):
            validate_raw(raw)
        with self.assertRaises(ValueError):
            validate_raw({'elements': []})

    def test_update_reports_removed_and_changed_ids(self):
        updated = copy.deepcopy(self.network)
        removed = updated['edges'].pop()
        updated['edges'][0]['direction'] = 'forward' if updated['edges'][0]['direction'] != 'forward' else 'both'
        report = summarize_update(self.network, updated)
        self.assertEqual(report['removedIDs'], [removed['id']])
        self.assertEqual(report['changedGeometryOrDirectionIDs'], [updated['edges'][0]['id']])
        self.assertIn('backup', report['reportPolicy'])

    def test_new_region_builds_from_catalog_without_script_edits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root/'Scripts').mkdir()
            (root/'Data/raw').mkdir(parents=True)
            for name in ('build_network.py', 'region_data.py'):
                shutil.copy2(ROOT/'Scripts'/name, root/'Scripts'/name)
            new = copy.deepcopy(self.regions['kokura'])
            new.update(key='new-region', networkID='new-region-ground-osm', name='追加地域')
            (root/'Data/regions.json').write_text(json.dumps([new]))
            shutil.copy2(ROOT/'Data/raw/kokura-osm.json', root/'Data/raw/new-region-osm.json')
            candidate = root/'candidate.json'
            command = [sys.executable, str(root/'Scripts/build_network.py'), '--region', 'new-region', '--output', str(candidate)]
            subprocess.run(command, check=True, capture_output=True, text=True)
            network = json.loads(candidate.read_text())
            validate_network(network, new)
            self.assertEqual(network['id'], 'new-region-ground-osm')
            self.assertEqual(network['provenance']['license'], 'ODbL-1.0')
            self.assertIsNone(network['provenance']['fetchedAt'], 'legacy acquisition times must not be invented')
            subprocess.run(command, check=True, capture_output=True, text=True)
            self.assertEqual(json.loads(candidate.read_text())['version'], network['version'])
            self.assertFalse((root/'Data/new-region-network.json').exists(), 'staging must not publish a network')

    def test_failed_serialization_preserves_previous_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)/'network.json'
            path.write_text('original')
            with self.assertRaises(ValueError):
                write_json(path, {'invalid': float('nan')})
            self.assertEqual(path.read_text(), 'original')


if __name__ == '__main__':
    unittest.main()
