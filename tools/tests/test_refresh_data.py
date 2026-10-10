"""Data changes prepare one complete update; unsupported changes leave files intact."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import generate_modifiers
import refresh_data as refresh

OLD = '1' * 40
NEW = '2' * 40


def data(ref=OLD, value=3, source='sql/item_mods.sql', digest='before'):
    return {'source': {'ref': ref, 'profile': 'TOAU'}, 'items': {1: {'name': 'Test gear', 'mods': {73: value}}},
            'mod_ids': {'store_tp': 73}, 'coverage': {73: {'fixed': 1}}, 'source_hashes': {source: digest}}


def text(table):
    return 'return ' + generate_modifiers.lua(table) + '\n'


class FakeSource:
    def __init__(self, repository, ref):
        self.ref = NEW if ref == 'phoenix/live' else ref

    def read(self, path):
        if path.endswith('.sql'):
            return 'INSERT INTO `item_mods` VALUES (1,73,%s);' % (3 if self.ref == OLD else 5)
        return 'local changed = ' + ('1' if self.ref == OLD else '2')


class RefreshTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix='cadence_refresh_')
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.before, self.after = data(), data(NEW, 5, digest='after')
        files = {
            refresh.DATA_FILES[0]: text(self.before), refresh.DATA_FILES[1]: text(self.before),
            'tools/generate_modifiers.py': "# Keep this comment.\r\nREF = '%s'\r\n" % OLD,
            'tools/source_guards.json': json.dumps({'ref': OLD, 'rules': {'test': 'reviewed'},
                                                   'modules': {}, 'load_order': [], 'profile': {'cap': 0.93}}),
            'cadence/cadence.lua': "addon.version = '1.2.0';\r\n-- Keep this too.\r\n",
            'CHANGELOG.md': '# Changelog\r\n\r\n## 1.2.0\r\n\r\nExisting release notes.\r\n',
        }
        for path, value in files.items():
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(value, encoding='utf-8', newline='')
        self.originals = self.contents()
        self.addCleanup(patch.stopall)
        patch.object(refresh, 'GitSource', FakeSource).start()
        self.guards = patch.object(refresh, 'check_guards').start()
        self.modules = patch.object(refresh, 'check_module_changes').start()
        self.generator = patch.object(refresh.generate_modifiers, 'generate', side_effect=self.generate).start()
        patch.object(refresh.generate_effects, 'generate', side_effect=self.generate).start()

    def generate(self, server, ref):
        return text(self.before if ref == OLD else self.after)

    def contents(self):
        return {path: (self.root / path).read_bytes() for path in refresh.UPDATE_FILES}

    def run_refresh(self, ref='phoenix/live'):
        return refresh.prepare('server', ref, self.root)

    def test_same_revision_does_not_write_or_generate(self):
        result, report = self.run_refresh(OLD)
        self.assertEqual(result['changed'], 'false')
        self.assertIn('No update', report)
        self.guards.assert_called_once()
        self.generator.assert_not_called()
        self.assertEqual(self.originals, self.contents())

    def test_provenance_only_change_does_not_advance_version_or_pin(self):
        self.after = data(NEW, digest='after')
        result, report = self.run_refresh()
        self.assertEqual(result['changed'], 'false')
        self.assertIn('data is unchanged', report)
        self.assertEqual(self.originals, self.contents())

    def test_value_change_prepares_one_synchronized_patch_update(self):
        result, report = self.run_refresh()
        self.assertEqual(result, {'changed': 'true', 'version': '1.2.1', 'source': NEW,
                                  'branch': 'data-refresh-' + NEW[:12]})
        self.assertIn('Test gear', report)
        self.assertIn('1.2.1', (self.root / 'cadence/cadence.lua').read_text())
        self.assertIn('## 1.2.1', (self.root / 'CHANGELOG.md').read_text())
        self.assertIn('Existing release notes.', (self.root / 'CHANGELOG.md').read_text())
        self.assertIn("REF = '%s'\r\n" % NEW, (self.root / 'tools/generate_modifiers.py').read_bytes().decode())
        self.assertEqual(self.before['source']['ref'], OLD)
        for path in refresh.DATA_FILES:
            self.assertEqual(refresh.source_ref(refresh.read_data((self.root / path).read_text())), NEW)
        guard = json.loads((self.root / 'tools/source_guards.json').read_text())
        self.assertEqual(guard['ref'], NEW)
        guard['ref'] = OLD
        self.assertEqual(guard, json.loads(self.originals['tools/source_guards.json']))
        self.assertEqual(set(self.contents()), set(self.originals))

    def test_removed_data_is_reported(self):
        self.after['items'] = {}
        self.after['coverage'][73]['fixed'] = 0
        result, report = self.run_refresh()
        self.assertEqual(result['changed'], 'true')
        self.assertIn('| Modifiers: items | 0 | 1 | 0 |', report)
        self.assertIn('| store_tp | fixed | 1 | 0 |', report)

    def test_changed_rule_stops_before_generation_and_writes_nothing(self):
        self.guards.side_effect = RuntimeError('Source review required for rules: tp.lua')
        with self.assertRaisesRegex(RuntimeError, 'Source review required'):
            self.run_refresh()
        self.generator.assert_not_called()
        self.assertEqual(self.originals, self.contents())

    def test_changed_loaded_module_stops_before_generation(self):
        self.modules.side_effect = RuntimeError('Source review required for loaded module changes')
        with self.assertRaisesRegex(RuntimeError, 'loaded module changes'):
            self.run_refresh()
        self.generator.assert_not_called()
        self.assertEqual(self.originals, self.contents())

    def test_unsupported_input_change_stops_even_when_output_is_unchanged(self):
        self.before = data(source='scripts/items/food.lua')
        self.after = data(NEW, source='scripts/items/food.lua', digest='after')
        for path in refresh.DATA_FILES:
            (self.root / path).write_text(text(self.before))
        original = self.contents()
        with self.assertRaisesRegex(RuntimeError, 'generator inputs.*'):
            self.run_refresh()
        self.assertEqual(original, self.contents())

    def test_new_dynamic_source_requires_review(self):
        self.after['source_hashes']['scripts/items/new_food.lua'] = 'new'
        with self.assertRaisesRegex(RuntimeError, 'new_food.lua'):
            self.run_refresh()
        self.assertEqual(self.originals, self.contents())

    def test_non_insert_sql_change_requires_review(self):
        with patch.object(FakeSource, 'read', side_effect=('CREATE TABLE old;', 'CREATE TABLE new;')):
            with self.assertRaisesRegex(RuntimeError, 'generator inputs'):
                self.run_refresh()
        self.assertEqual(self.originals, self.contents())

    def test_source_comment_only_change_is_allowed(self):
        self.before = data(source='scripts/items/food.lua')
        self.after = data(NEW, source='scripts/items/food.lua', digest='after')
        for path in refresh.DATA_FILES:
            (self.root / path).write_text(text(self.before))
        with patch.object(FakeSource, 'read', side_effect=lambda path: 'return 1 -- comment'):
            result, _ = self.run_refresh()
        self.assertEqual(result['changed'], 'false')

    def test_profile_changes_count_as_meaningful(self):
        before = data()
        after = copy.deepcopy(before)
        after['source']['max_level'] = 99
        self.assertNotEqual(refresh.semantic(before), refresh.semantic(after))

    def test_missing_or_disagreeing_pins_stop(self):
        manifest = self.root / 'tools/source_guards.json'
        manifest.write_text(json.dumps({'ref': NEW}))
        with self.assertRaisesRegex(RuntimeError, 'pin disagree'):
            self.run_refresh()
        self.generator.assert_not_called()

    def test_candidate_data_must_name_resolved_sha(self):
        self.after['source']['ref'] = 'phoenix/live'
        with self.assertRaisesRegex(RuntimeError, 'resolved source revision'):
            self.run_refresh()
        self.assertEqual(self.originals, self.contents())

    def test_stale_baseline_is_not_overwritten(self):
        self.before['items'][1]['mods'][73] = 4
        with self.assertRaisesRegex(RuntimeError, 'Checked-in data'):
            self.run_refresh()
        self.assertEqual(self.originals, self.contents())

    def test_write_failure_rolls_back_all_files(self):
        real_replace = refresh.bump_version.os.replace
        calls = 0

        def fail_fourth(source, destination):
            nonlocal calls
            calls += 1
            if calls == 4:
                raise OSError('test replacement failure')
            return real_replace(source, destination)

        with patch.object(refresh.bump_version.os, 'replace', side_effect=fail_fourth):
            with self.assertRaisesRegex(OSError, 'replacement failure'):
                self.run_refresh()
        self.assertEqual(self.originals, self.contents())

    def test_data_loader_has_no_global_io(self):
        with self.assertRaises(Exception):
            refresh.read_data("return {source_hashes={}, leaked=os.getenv('PATH')}")

    def test_pending_notes_join_new_release_without_changing_published_notes(self):
        for eol in ('\n', '\r\n'):
            published = '## 1.2.0' + eol + eol + 'Published notes.' + eol
            old = eol.join(['# Changelog', '', '## Unreleased', '', '- Pending fix.', '', published])
            result = refresh.release_notes(old, '1.2.1', 'Data update.', ['- Updated equipment.'])
            self.assertNotIn('## Unreleased', result)
            self.assertIn(eol.join(['## 1.2.1', '', '- Pending fix.', '', 'Data update.']), result)
            self.assertTrue(result.endswith(published))


class ModuleChangeTests(unittest.TestCase):
    class Source:
        ref = OLD

        def __init__(self, changes='', body='return 1'):
            self.changes, self.body = changes, body

        def git(self, *args):
            return self.changes

        def read(self, path):
            return 'phoenix/lua\nphoenix/data\n' if path == 'modules/init.txt' else self.body

    def test_new_indirect_override_requires_review(self):
        candidate = self.Source('A\0modules/phoenix/lua/indirect.lua\0', 'return helper()')
        with self.assertRaisesRegex(RuntimeError, 'indirect.lua'):
            refresh.check_module_changes(self.Source(), candidate)


    def test_removed_loaded_yaml_requires_review(self):
        candidate = self.Source('D\0modules/phoenix/data/new.yaml\0')
        with self.assertRaisesRegex(RuntimeError, 'new.yaml'):
            refresh.check_module_changes(self.Source(), candidate)

    def test_changed_loaded_code_requires_review(self):
        candidate = self.Source('M\0modules/phoenix/lua/indirect.lua\0', 'return 2')
        with self.assertRaisesRegex(RuntimeError, 'indirect.lua'):
            refresh.check_module_changes(self.Source(), candidate)

    def test_comments_and_unloaded_modules_do_not_block(self):
        for candidate in (self.Source(), self.Source('M\0modules/phoenix/lua/indirect.lua\0', 'return 1 -- note'),
                          self.Source('A\0modules/testing/indirect.lua\0', 'return 2')):
            refresh.check_module_changes(self.Source(), candidate)


@unittest.skipUnless(os.name == 'nt', 'The documentation suite enumerates files with Windows dir')
class FutureReleaseTests(unittest.TestCase):
    def test_prepared_data_patch_passes_player_documentation_checks(self):
        with tempfile.TemporaryDirectory(prefix='cadence_future_release_') as folder:
            root = Path(folder)
            for name in ('cadence', 'docs', 'tests', 'tools'):
                shutil.copytree(refresh.ROOT / name, root / name,
                                ignore=shutil.ignore_patterns('.venv', '__pycache__', 'out', 'fonts'))
            for name in ('README.md', 'CHANGELOG.md', 'LICENSE'):
                shutil.copyfile(refresh.ROOT / name, root / name)
            baseline = {path: (root / path).read_text(encoding='utf-8') for path in refresh.DATA_FILES}
            old = refresh.source_ref(refresh.read_data(baseline[refresh.DATA_FILES[0]]))

            class Candidate:
                def __init__(self, server, ref):
                    self.ref = NEW if ref == 'phoenix/live' else ref

                def read(self, path):
                    return 'INSERT INTO `item_mods` VALUES (65530,73,5);'

            def generate(path, server, ref):
                if ref == old:
                    return baseline[path]
                result = refresh.read_data(baseline[path])
                if isinstance(result['source'], dict):
                    result['source']['ref'] = ref
                    result['items'][65530] = {'name': 'Future equipment', 'level': 75,
                                             'mods': {73: 5}, 'latents': {}}
                    result['coverage'][73]['fixed'] += 1
                    result['source_hashes']['sql/item_mods.sql'] = 'changed'
                else:
                    result['source'] = ref
                return text(result)

            with patch.object(refresh, 'GitSource', Candidate), patch.object(refresh, 'check_guards'), \
                 patch.object(refresh, 'check_module_changes'), \
                 patch.object(refresh.generate_modifiers, 'generate',
                              side_effect=lambda server, ref: generate(refresh.DATA_FILES[0], server, ref)), \
                 patch.object(refresh.generate_effects, 'generate',
                              side_effect=lambda server, ref: generate(refresh.DATA_FILES[1], server, ref)):
                result, _ = refresh.prepare('server', 'phoenix/live', root)
            self.assertEqual(result['changed'], 'true')
            process = subprocess.run([sys.executable, str(root / 'tests/run.py'), 'test_docs.lua'],
                                     cwd=root, text=True, capture_output=True)
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)

if __name__ == '__main__':
    unittest.main()
