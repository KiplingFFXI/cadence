"""Source and addon mutations must fail the formula and rule checks."""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from generate_modifiers import REF
import source_parity as parity


class ChangedSource:
    def __init__(self, source, changes=None, added=None):
        self.source, self.changes, self.added = source, changes or {}, added or {}

    def read(self, path):
        if path in self.added:
            return self.added[path]
        text = self.source.read(path)
        if path in self.changes:
            before, after = self.changes[path]
            if before not in text:
                raise AssertionError('Mutation anchor missing: ' + path)
            text = text.replace(before, after, 1)
        return text

    def candidates(self):
        return self.source.candidates() + list(self.added)


class FingerprintTests(unittest.TestCase):
    def test_comments_and_spacing_do_not_change_a_guard(self):
        self.assertEqual(parity.fingerprint('local x = 3 -- note\nreturn x'),
                         parity.fingerprint('local x=3\n-- another note\nreturn x'))

    def test_quoted_comment_characters_remain_part_of_the_rule(self):
        self.assertNotEqual(parity.fingerprint("return '--a'"), parity.fingerprint("return '--b'"))

    def test_identifier_and_operator_boundaries_remain_part_of_the_rule(self):
        self.assertNotEqual(parity.fingerprint('return not x'), parity.fingerprint('return notx'))
        self.assertNotEqual(parity.fingerprint('return a & & b;'), parity.fingerprint('return a && b;'))

    def test_cpp_decrement_does_not_hide_the_rest_of_the_line(self):
        self.assertNotEqual(parity.fingerprint('n--; delay = 3;', 'cpp'),
                            parity.fingerprint('n--; delay = 4;', 'cpp'))
        self.assertEqual(parity.fingerprint('return 3; // note', 'cpp'),
                         parity.fingerprint('return 3; /* other note */', 'cpp'))

    def test_cpp_function_stops_at_its_matching_brace(self):
        body = parity.function_body('int A::f(bool p) { if(p) { return 1; } return 2; }\nint g() {}', 'A::f')
        self.assertTrue(body.endswith('return 2; }'))
        self.assertNotIn('int g', body)


REPOSITORY = Path(os.environ.get('CADENCE_SOURCE_REPO', parity.ROOT.parent / 'Phoenix'))


@unittest.skipUnless((REPOSITORY / '.git').exists(), 'Set CADENCE_SOURCE_REPO to the reviewed Phoenix repository')
class SourceParityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = parity.GitSource(REPOSITORY, REF)
        cls.manifest = json.loads(parity.GUARDS.read_text(encoding='utf-8'))

    def test_reviewed_source_matches_all_guards(self):
        parity.check_guards(self.source)

    def test_tp_native_formula_matches_the_addon(self):
        self.assertGreater(parity.check_tp(self.source), 2000)

    def test_recovery_native_formula_matches_the_addon(self):
        self.assertGreater(parity.check_recovery(self.source), 1500)

    def test_delay_matches_the_reviewed_cpp_reference(self):
        self.assertGreater(parity.check_delay(reduction_cap=self.manifest['profile']['delay_reduction_cap']), 500)

    def test_changed_tp_source_formula_fails_without_a_hash_check(self):
        changed = ChangedSource(self.source, {parity.ERA_TP: ('* 65 / 270', '* 66 / 270')})
        with self.assertRaisesRegex(RuntimeError, 'Source parity failed for TP'):
            parity.check_tp(changed)

    def test_changed_recovery_source_formula_fails_without_a_hash_check(self):
        changed = ChangedSource(self.source, {parity.HEALING: ('local healMP = 12 +', 'local healMP = 13 +')})
        with self.assertRaisesRegex(RuntimeError, 'Source parity failed for resting MP'):
            parity.check_recovery(changed)

    def test_changed_cpp_cap_requires_review(self):
        path = 'src/map/entities/battle_entity.cpp'
        changed = ChangedSource(self.source, {path: ('0.4375f', '0.44f')})
        with self.assertRaisesRegex(RuntimeError, 'Source review required for rules'):
            parity.check_guards(changed)

    def test_new_loaded_timing_override_requires_review(self):
        added = {'modules/phoenix/lua/new_timing.lua': "m:addOverride('xi.effects.healing.onEffectTick', function() end)"}
        with self.assertRaisesRegex(RuntimeError, 'new_timing.lua'):
            parity.check_guards(ChangedSource(self.source, added=added))

    def test_disabled_module_removal_requires_review(self):
        changed = ChangedSource(self.source, {'modules/init.txt': ('\nera/lua\n', '\n# era/lua\n')})
        with self.assertRaisesRegex(RuntimeError, 'Source review required for modules'):
            parity.check_guards(changed)

    def test_changed_module_load_order_requires_review(self):
        before = 'era/lua\n\n# Phoenix modules\nphoenix/cpp\nphoenix/lua'
        after = 'phoenix/lua\n\n# Phoenix modules\nphoenix/cpp\nera/lua'
        changed = ChangedSource(self.source, {'modules/init.txt': (before, after)})
        with self.assertRaisesRegex(RuntimeError, 'modules/init.txt load order'):
            parity.check_guards(changed)

    def test_module_comments_and_trailing_slashes_do_not_change_load_order(self):
        changed = ChangedSource(self.source, {'modules/init.txt': ('\nera/lua\n', '\nera/lua/ # same entry\n')})
        parity.check_guards(changed)

    def test_unloaded_module_does_not_change_the_reviewed_rules(self):
        added = {'modules/testing/new_timing.lua': "m:addOverride('xi.combat.tp.calculateTPReturn', function() end)"}
        parity.check_guards(ChangedSource(self.source, added=added))

    def addon_change(self, path, before, after, check):
        with tempfile.TemporaryDirectory(prefix='cadence_parity_') as folder:
            addon = Path(folder) / 'cadence'
            for name in ('core/delay.lua', 'core/tp.lua', 'core/modifiers.lua', 'data/phoenix_modifiers.lua'):
                destination = addon / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(parity.ROOT / 'cadence' / name, destination)
            target = addon / path
            text = target.read_text(encoding='utf-8')
            self.assertIn(before, text)
            target.write_text(text.replace(before, after, 1), encoding='utf-8')
            with self.assertRaisesRegex(RuntimeError, 'Source parity failed'):
                check(addon)

    def test_changed_addon_tp_formula_fails(self):
        self.addon_change('core/tp.lua', '50 + (d - 180) * 15 / 180', '51 + (d - 180) * 15 / 180',
                          lambda addon: parity.check_tp(self.source, addon))

    def test_changed_addon_recovery_formula_fails(self):
        self.addon_change('core/modifiers.lua', 'result.mp_base = 12 +', 'result.mp_base = 13 +',
                          lambda addon: parity.check_recovery(self.source, addon))

    def test_changed_addon_hundred_fists_formula_fails(self):
        self.addon_change('core/delay.lua', 'clamp(weapon_ms - martial_ms, 1600, 8000) * 0.25',
                          'clamp(weapon_ms - martial_ms, 1600, 8000) * 0.30', parity.check_delay)

    def test_fixture_pin_matches_generator_and_ci(self):
        self.assertEqual(self.manifest['ref'], REF)
        workflow = (parity.ROOT / '.github/workflows/verify.yml').read_text(encoding='utf-8')
        self.assertIn('ref: ' + REF, workflow)


if __name__ == '__main__':
    unittest.main()
