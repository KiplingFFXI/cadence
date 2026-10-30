"""Phoenix dataset patches preserve ordering, deletion, and strict identities."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import source_yaml


class Source:
    ref = 'reviewed'

    def __init__(self, files):
        self.files = files

    def read(self, path):
        return self.files[path]

    def git(self, *args):
        return '\n'.join(sorted(self.files))


class DatasetTests(unittest.TestCase):
    def test_ordered_explicit_and_implicit_roots_apply_once(self):
        source = Source({
            'modules/init.txt': 'era/data\nphoenix/lua\nera/data/wotg\nera/sql\n',
            'data/sample.yaml': 'sample: {a: {id: 1, value: 0}, b: [1, 2]}',
            'modules/era/data/sample.yaml': 'sample: {a: {value: 2}}',
            'modules/phoenix/data/sample.yaml': 'sample: {a: {value: 3}, b: [4]}',
            'modules/era/data/wotg/sample.yaml': 'sample: {a: {value: 5}}',
        })
        self.assertEqual(source_yaml.dataset(source, 'sample'), {'a': {'id': 1, 'value': 5}, 'b': [4]})

    def test_merge_patch_deletes_null_fields_and_replaces_arrays(self):
        original = {'a': {'x': 1, 'y': 2}, 'b': [1, 2]}
        self.assertEqual(source_yaml.merge(original, {'a': {'x': None}, 'b': [3]}), {'a': {'y': 2}, 'b': [3]})
        self.assertEqual(original['a']['x'], 1)

    def test_duplicate_keys_and_invalid_documents_are_rejected(self):
        for value in ('a: 1\na: 2\n', 'a: {id: 1, id: 2}', '[1, 2]', 'a: ['):
            with self.subTest(value=value), self.assertRaisesRegex(RuntimeError, 'Source review required'):
                source_yaml.read(Source({'test': value}), 'test')

    def test_weapon_skill_identity_and_animation_must_be_unique_integers(self):
        for rows in ('first: {id: 1, animation: 2}\n  second: {id: 1, animation: 3}',
                     'first: {id: true, animation: 2}', 'first: {id: 1, animation: 256}',
                     'first: {id: 1, animation: 1.5}'):
            source = Source({'modules/init.txt': '', 'data/weapon_skills.yaml': 'weapon_skills:\n  ' + rows})
            with self.subTest(rows=rows), self.assertRaisesRegex(RuntimeError, 'Source review required'):
                source_yaml.weapon_skills(source)


if __name__ == '__main__':
    unittest.main()
