"""Source and addon mutations must fail the formula and rule checks."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
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
        return self.source.candidates() + [path for path, text in self.added.items()
                                           if re.search(parity.MODULE_RULES, text, re.I)]


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

    def test_yaml_mapping_indentation_changes_the_guard(self):
        self.assertNotEqual(parity.fingerprint('mods:\n  hpheal: 10\n  mpheal: 5\n', 'data'),
                            parity.fingerprint('mods:\n  hpheal: 10\nmpheal: 5\n', 'data'))

    def test_yaml_comments_and_value_spacing_do_not_change_the_guard(self):
        self.assertEqual(parity.fingerprint('mods:\n  hpheal: 10 # value\n', 'data'),
                         parity.fingerprint('# another note\nmods:\n  hpheal:   10\n', 'data'))
        self.assertNotEqual(parity.fingerprint('name: "#one"\n', 'data'),
                            parity.fingerprint('name: "#two"\n', 'data'))

    def test_yaml_scalar_contents_remain_exact(self):
        for before, after in (('note: |\n  #one\n', 'note: |\n  #two\n'),
                              ('note: >\n  first word\n', 'note: >\n  first  word\n'),
                              ('note: "first\n  next line"\n', 'note: "first\n  next  line"\n')):
            with self.subTest(before=before):
                self.assertNotEqual(parity.fingerprint(before, 'data'), parity.fingerprint(after, 'data'))

    def test_sql_comments_are_ignored_but_values_are_not(self):
        self.assertEqual(parity.fingerprint('UPDATE traits SET value=2; -- note\n', 'sql'),
                         parity.fingerprint('/* another note */ UPDATE traits SET value = 2; # tail\n', 'sql'))
        self.assertNotEqual(parity.fingerprint("SELECT '#one';", 'sql'),
                            parity.fingerprint("SELECT '#two';", 'sql'))

    def test_sql_executable_comments_and_adjacent_minus_signs_remain_rules(self):
        for before, after in (('UPDATE traits SET value=value--1;', 'UPDATE traits SET value=value--2;'),
                              ('/*! UPDATE traits SET value=1; */', '/*! UPDATE traits SET value=2; */')):
            with self.subTest(before=before):
                self.assertNotEqual(parity.fingerprint(before, 'sql'), parity.fingerprint(after, 'sql'))

    def test_module_patterns_include_signed_delay_recovery_and_duration_inputs(self):
        for token in ('DELAY', 'REGEN', 'REFRESH', 'REGEN_DOWN', 'REFRESH_DOWN', 'INHIBIT_TP',
                      'SONG_DURATION_BONUS', 'ENF_MAG_DURATION', 'xi.effect.FOOD', 'xi.aftermath',
                      'EngageLockout', 'setEngageLockedUntil', 'm_engageLockedUntil',
                      'CheckLatentsWeaponDraw', 'OnDisengage'):
            with self.subTest(token=token):
                self.assertRegex(token, parity.MODULE_RULES)


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

    def test_reengage_matches_the_reviewed_cpp_constants(self):
        self.assertEqual(parity.check_reengage(self.source), 10)

    def test_changed_reengage_source_constants_fail_without_a_hash_check(self):
        path = 'src/map/ai/states/attack_state.cpp'
        for replacement in (('= 3s;', '= 4s;'), ('= 1500ms;', '= 1600ms;')):
            with self.subTest(replacement=replacement), self.assertRaisesRegex(RuntimeError, 'Source parity failed for re-engage'):
                parity.check_reengage(ChangedSource(self.source, {path: replacement}))

    def test_changed_reengage_transitions_and_packet_layout_require_review(self):
        changes = {
            'src/map/ai/ai_container.cpp': ('finished->Cleanup(tick);', 'finished->Cleanup(tick + 1s);'),
            'src/map/ai/controllers/player_controller.cpp': ('timer::now() >= m_engageLockedUntil', 'timer::now() > m_engageLockedUntil'),
            'src/map/ai/states/range_state.cpp': ('MsgBasic::WaitLonger', 'MsgBasic::CannotPerformAction'),
            'src/map/entities/char_entity.cpp': ('timer::now() + state.EngageLockout()', 'timer::now() + state.EngageLockout() + 1s'),
            'src/map/entities/battle_entity.cpp': ('setBattleTarget(std::nullopt);\n    if (animation == xi::Animation::Attack)',
                                                 'setBattleTarget(std::nullopt);\n    if (animation == xi::Animation::None)'),
            'src/map/packets/char_status.cpp': ('uint8_t                   BufStatus[32];', 'uint8_t                   BufStatus[33];'),
        }
        for path, replacement in changes.items():
            with self.subTest(path=path), self.assertRaisesRegex(RuntimeError, re.escape(path)):
                parity.check_guards(ChangedSource(self.source, {path: replacement}))

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

    def test_changed_generator_assumptions_require_review(self):
        changes = {
            'scripts/globals/job_utils/corsair.lua': ('8, 32, 10, 12, 14', '9, 32, 10, 12, 14'),
            'scripts/globals/aftermath.lua': ('tp * 0.02', 'tp * 0.03'),
            'data/enums/mod.yaml': ('storetp:                   73', 'storetp:                   74'),
            'data/enums/latent.yaml': ('hp_under_percent:        0', 'hp_under_percent:        1'),
            'data/enums/weather.yaml': ('hot_spell:      4', 'hot_spell:      5'),
            'data/merits.yaml': ('id:           0x0444', 'id:           0x0445'),
            'settings/default/main.lua': ('DELAY_REDUCTION_CAP = 0.80', 'DELAY_REDUCTION_CAP = 0.90'),
        }
        for path, replacement in changes.items():
            with self.subTest(path=path), self.assertRaisesRegex(RuntimeError, re.escape(path)):
                parity.check_guards(ChangedSource(self.source, {path: replacement}))

    def test_changed_shared_source_helper_requires_review(self):
        path = 'scripts/globals/item_utils.lua'
        changed = ChangedSource(self.source, {path: ('local result     = 0', 'local result     = 1')})
        with self.assertRaisesRegex(RuntimeError, re.escape(path)):
            parity.check_guards(changed)

    def test_changed_hand_to_hand_job_eligibility_requires_review(self):
        changes = {
            'data/skills.yaml': ('hand_to_hand:      {war: d', 'hand_to_hand:      {war: none'),
            'modules/era/data/skills.yaml': ('hand_to_hand: {pup: b_plus}', 'hand_to_hand: {pup: none}'),
        }
        for path, replacement in changes.items():
            with self.subTest(path=path), self.assertRaisesRegex(RuntimeError, re.escape(path)):
                parity.check_guards(ChangedSource(self.source, {path: replacement}))

    def test_supported_base_sql_data_remains_refreshable(self):
        path = 'sql/item_mods.sql'
        changed = ChangedSource(self.source, added={path: self.source.read(path) +
                                '\nINSERT INTO `item_mods` VALUES (99999,73,10);\n'})
        parity.check_guards(changed)

    def test_loaded_yaml_and_header_overrides_require_review(self):
        for path, text in (
                ('modules/phoenix/data/recovery.yaml', 'mods:\n  regen: 5\n'),
                ('modules/era/data/recovery.yml', 'mods:\n  refresh_down: 1\n'),
                ('modules/phoenix/cpp/timing.h', 'constexpr auto mod = xi::Mod::DELAY;'),
                ('modules/phoenix/cpp/timing.hpp', 'constexpr auto mod = xi::Mod::REFRESH;')):
            with self.subTest(path=path), self.assertRaisesRegex(RuntimeError, re.escape(path)):
                parity.check_guards(ChangedSource(self.source, added={path: text}))

    def test_actual_git_scan_includes_lowercase_recovery_module(self):
        path = 'modules/phoenix/lua/globals/disable_sanction_bonuses.lua'
        self.assertIn(path, self.source.candidates())
        self.assertIn(path, self.manifest['modules'])

    def test_changed_yaml_module_nesting_requires_review(self):
        path = 'modules/phoenix/data/recovery.yaml'
        reviewed = ChangedSource(self.source, added={path: 'mods:\n  regen: 5\n  refresh: 1\n'})
        manifest = dict(self.manifest, **parity.observed_guards(reviewed))
        moved = ChangedSource(self.source, added={path: 'mods:\n  regen: 5\nrefresh: 1\n'})
        with self.assertRaisesRegex(RuntimeError, re.escape(path)):
            parity.check_guards(moved, manifest)

    def test_new_loaded_timing_override_requires_review(self):
        added = {'modules/phoenix/lua/new_timing.lua': "m:addOverride('xi.effects.healing.onEffectTick', function() end)"}
        with self.assertRaisesRegex(RuntimeError, 'new_timing.lua'):
            parity.check_guards(ChangedSource(self.source, added=added))

    def test_new_loaded_reengage_override_requires_review(self):
        added = {'modules/phoenix/cpp/reengage.cpp': 'player->setEngageLockedUntil(timer::now());'}
        with self.assertRaisesRegex(RuntimeError, 'reengage.cpp'):
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
            for name in ('core/delay.lua', 'core/attack.lua', 'core/tp.lua', 'core/modifiers.lua', 'data/phoenix_modifiers.lua'):
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

    def test_changed_addon_reengage_constants_fail(self):
        for before, after in (('REENGAGE_MIN_SECONDS = 1.5', 'REENGAGE_MIN_SECONDS = 1.6'),
                              ('REENGAGE_GATE_SECONDS = 3.0', 'REENGAGE_GATE_SECONDS = 4.0')):
            with self.subTest(before=before):
                self.addon_change('core/attack.lua', before, after, lambda addon: parity.check_reengage(self.source, addon))

    def test_fixture_pin_matches_generator_and_ci(self):
        self.assertEqual(self.manifest['ref'], REF)
        workflow = (parity.ROOT / '.github/workflows/verify.yml').read_text(encoding='utf-8')
        self.assertIn('ref: ${{ steps.source.outputs.ref }}', workflow)
        step = workflow.split('      - name: Read the reviewed Phoenix revision\n', 1)[1].split('\n      - name:', 1)[0]
        self.assertIn('id: source', step)
        command = re.search(r'python -c "([^"\n]+)"', step).group(1)
        with tempfile.TemporaryDirectory(prefix='cadence_ci_pin_') as folder:
            output = Path(folder) / 'output.txt'
            result = subprocess.run([sys.executable, '-c', command], cwd=parity.ROOT,
                                    env=dict(os.environ, GITHUB_OUTPUT=str(output)), capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text(encoding='utf-8'), 'ref=' + REF + '\n')


if __name__ == '__main__':
    unittest.main()
