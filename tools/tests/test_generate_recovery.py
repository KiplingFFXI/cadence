"""Recovery data preserves packet signatures, source timing units and deliberate unknowns."""
import os
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import generate_recovery as generator
import source_parity as parity
from generate_modifiers import REF

REPOSITORY = Path(os.environ.get('CADENCE_SOURCE_REPO', parity.ROOT.parent / 'Phoenix'))


class ChangedSource:
    def __init__(self, source, path, before, after):
        self.source, self.ref, self.cache = source, source.ref, {}
        self.path, self.before, self.after = path, before, after

    def read(self, path):
        text = self.source.read(path)
        if path == self.path:
            if self.before not in text:
                raise AssertionError('Missing mutation anchor: ' + path)
            text = text.replace(self.before, self.after, 1)
        return text

    def git(self, *args):
        return self.source.git(*args)

    def candidates(self):
        return self.source.candidates()

    def tree_digest(self, path):
        return self.source.tree_digest(path)


@unittest.skipUnless((REPOSITORY / '.git').exists(), 'Set CADENCE_SOURCE_REPO to the reviewed Phoenix repository')
class RecoveryDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = parity.GitSource(REPOSITORY, REF)
        cls.data = generator.build(cls.source)

    def test_generated_file_matches_the_reviewed_source(self):
        self.assertEqual((parity.ROOT / 'cadence/data/phoenix_recovery.lua').read_text(encoding='utf-8'),
                         generator.generate(REPOSITORY, REF))

    def test_source_coverage_and_distinct_zero_unknown_values(self):
        self.assertEqual(len(self.data['weaponskills']), 226)
        self.assertEqual(len(self.data['weaponskill_seconds']), 226)
        self.assertEqual(len(self.data['abilities']), 600)
        self.assertEqual(len(self.data['items']), 3181)
        self.assertEqual(len(self.data['quarantined_items']), 6)
        self.assertEqual(len(self.data['spell_casts']), 893)
        self.assertEqual(len(self.data['spell_attack_seconds']), 893)
        for id in (4112, 4132, 4381, 5149, 14790, 15762):
            self.assertEqual(self.data['items'][id], 0)
        for id, seconds in ((4181, 3), (4606, 5), (14672, 5), (17040, 3), (4257, 12)):
            self.assertEqual(self.data['items'][id], seconds)
        self.assertNotIn(65535, self.data['items'])
        for id in generator.QUARANTINE:
            self.assertNotIn(id, self.data['items'])
            self.assertTrue(self.data['quarantined_items'][id])

    def test_overlapping_ids_keep_their_distinct_animation_signatures(self):
        self.assertEqual(self.data['weaponskills'][68], {50: True})
        self.assertEqual(self.data['abilities'][68], {'category': 3, 'animations': {214: True},
                                                    'seconds': 5, 'kind': 'superjump', 'attack_seconds': 5})
        self.assertEqual(self.data['weaponskills'][66], {48: True})
        self.assertEqual(self.data['abilities'][66]['animations'], {204: True})
        for id in (26, 41, 45, 46, 57, 66, 67, 77, 150, 168, 170):
            self.assertEqual(self.data['abilities'][id]['seconds'], 0)

    def test_weapon_skill_locks_follow_animation_data_and_missing_key_fallback(self):
        for id, seconds in ((1, 1.916), (32, 1.5), (68, 2.833)):
            self.assertEqual(self.data['weaponskill_seconds'][id], seconds)
        path = 'data/animation_locks.yaml'
        changed = ChangedSource(self.source, path, '16:  1916', '16:  2500')
        self.assertEqual(generator.build(changed)['weaponskill_seconds'][1], 2.5)
        missing = ChangedSource(self.source, path, '    16:  1916 # hm_0 ROM/76/39.DAT\n', '')
        self.assertEqual(generator.build(missing)['weaponskill_seconds'][1], 2)
        for source in (changed, missing):
            with self.assertRaisesRegex(RuntimeError, 'animation_locks.yaml'):
                parity.check_guards(source)

    def test_current_ability_signatures_include_updated_pet_commands_and_cutting_cards(self):
        for id, animation in ((78, 85), (80, 83), (136, 94), (138, 94), (139, 94), (140, 94), (178, 168)):
            self.assertEqual(self.data['abilities'][id]['animations'], {animation: True})
        self.assertEqual(set(self.data['abilities'][339]['animations']), set(range(321, 327)))

    def test_attack_suspension_is_separate_from_global_action_recovery(self):
        self.assertEqual(self.data['abilities'][35]['seconds'], 0)
        self.assertEqual(self.data['abilities'][35]['attack_seconds'], 2)
        for id in range(141, 149):
            self.assertEqual(self.data['abilities'][id]['attack_seconds'], 2)
        self.assertEqual(self.data['abilities'][382]['attack_seconds'], 0)
        self.assertEqual(self.data['attack_tails'], {'ranged': 0.8, 'item_min': 0.4})
        for id, seconds in ((1, 2), (793, 1), (830, 4), (896, 1.5)):
            self.assertEqual(self.data['spell_attack_seconds'][id], seconds)

    def test_attack_suspension_applies_loaded_ability_and_spell_overrides(self):
        ability = ChangedSource(self.source, 'modules/era/sql/wotg/automaton.sql',
                                 '`animationTime` = 2000', '`animationTime` = 1500')
        self.assertEqual(generator.build(ability)['abilities'][141]['attack_seconds'], 1.5)
        path = 'modules/era/sql/wotg/spell_adjustments.sql'
        original = self.source.read(path)
        spell = ChangedSource(self.source, path, original,
                               original + '\nUPDATE `spell_list` SET `animationTime` = 1750 WHERE `spellid` = 1;\n')
        self.assertEqual(generator.build(spell)['spell_attack_seconds'][1], 1.75)
        for source in (ability, spell):
            with self.assertRaisesRegex(RuntimeError, 'Source review required'):
                parity.check_guards(source)

    def test_active_lua_animation_variants_are_included(self):
        expected = {26: {186, 187}, 57: {188, 189}, 77: {0, 201, 202, 203},
                    168: {0, 201, 202, 203}, 41: {181, 182}, 45: {183, 184},
                    285: {188, 189}, 228: {181, 182}, 328: {181, 182},
                    201: set(range(14, 24)), 368: set(range(5, 15)),
                    372: set(range(15, 25)), 375: set(range(25, 35))}
        for id, animations in expected.items():
            with self.subTest(id=id):
                self.assertEqual(set(self.data['abilities'][id]['animations']), animations)
        self.assertEqual(self.data['abilities'][190]['category'], 14)
        self.assertEqual(self.data['abilities'][368]['category'], 15)

    def test_enemy_spell_cast_times_include_loaded_era_overrides(self):
        self.assertEqual(self.data['spell_casts'][1], 2)
        self.assertEqual(self.data['spell_casts'][144], 2.25)
        self.assertEqual(self.data['spell_casts'][204], 19)
        source = ChangedSource(self.source, 'modules/era/sql/wotg/spell_adjustments.sql',
                               '`castTime` = 3750', '`castTime` = 4250')
        self.assertEqual(generator.build(source)['spell_casts'][29], 4.25)
        with self.assertRaisesRegex(RuntimeError, 'spell_adjustments.sql'):
            parity.check_guards(source)

    def test_supported_item_row_additions_can_refresh(self):
        row = "INSERT INTO `item_usable` VALUES (60000,'fixture',1,1,30,3,0,0,0,0);\n"
        text = self.source.read('sql/item_usable.sql')
        changed = ChangedSource(self.source, 'sql/item_usable.sql', text, text + row)
        self.assertEqual(generator.build(changed)['items'][60000], 3)
        parity.check_guards(changed)

    def test_quarantine_change_and_unreviewed_duration_stop_refresh(self):
        for before, after in (("4352,'derfland_pear',1,1,0,26", "4352,'derfland_pear',1,1,0,0"),
                              ("4112,'potion',1,1,30,0", "4112,'potion',1,1,30,13")):
            changed = ChangedSource(self.source, 'sql/item_usable.sql', before, after)
            for check in (generator.build, parity.check_guards):
                with self.subTest(before=before, check=check.__name__), self.assertRaisesRegex(RuntimeError, 'Source review required'):
                    check(changed)

    def test_malformed_schema_and_duplicate_item_rows_stop_generation(self):
        path = 'sql/item_usable.sql'
        original = self.source.read(path)
        for before, after in (('`animationTime`', '`animationLength`'),
                              (original, original + "\nINSERT INTO `item_usable` VALUES (4112,'duplicate',1,1,30,3,0,0,0,0);\n")):
            with self.subTest(after=after[:40]), self.assertRaisesRegex(RuntimeError, 'SQL'):
                generator.build(ChangedSource(self.source, path, before, after))

    def test_timing_packet_and_animation_mutations_require_review(self):
        cases = (
            ('src/map/ai/ai_container.cpp',
             'return !GetCurrentState() || GetCurrentState()->CanChangeState();',
             'return false;\n    return !GetCurrentState() || GetCurrentState()->CanChangeState();'),
            ('src/map/ai/states/range_state.h', 'm_returnWeaponDelay = 800ms', 'm_returnWeaponDelay = 900ms'),
            ('src/map/map_constants.h', 'kLogicUpdateRate = 2.5f', 'kLogicUpdateRate = 5.0f'),
            ('src/map/ai/states/item_state.cpp', 'GetEntryTime() + m_castTime + m_animationTime',
             'GetEntryTime() + m_castTime + m_animationTime + 1s'),
            ('src/map/entities/char_entity.cpp', 'action.actionid   = PItem->getID();', 'action.actionid   = PItem->getID() + 16;'),
            ('src/map/action/action.cpp', 'actiontype != ActionCategory::MagicFinish', 'actiontype == ActionCategory::MagicFinish'),
            ('src/map/packets/s2c/0x028_battle2.cpp', 'action.actionid, bitOffset, 32', 'action.actionid, bitOffset, 16'),
            ('src/map/utils/itemutils.cpp', 'std::chrono::seconds(rset->get<uint32>("animationTime"))',
             'std::chrono::milliseconds(rset->get<uint32>("animationTime"))'),
            ('scripts/globals/job_utils/dragoon.lua', 'untargetableAndUnactionable(5000)', 'untargetableAndUnactionable(6000)'),
            ('scripts/globals/job_utils/ranger.lua', 'action:getAnimation(target:getID()) + 1', 'action:getAnimation(target:getID()) + 2'),
        )
        for path, before, after in cases:
            with self.subTest(path=path), self.assertRaisesRegex(RuntimeError, 'Source review required'):
                parity.check_guards(ChangedSource(self.source, path, before, after))

    def test_unreviewed_action_dispatch_tree_stops_refresh(self):
        changed = ChangedSource(self.source, '', '', '')
        changed.tree_digest = lambda path: 'f' * 40
        with self.assertRaisesRegex(RuntimeError, 'scripts/actions/abilities:tree'):
            parity.check_guards(changed)

    def test_ranged_constant_and_super_jump_data_match_without_hash_checks(self):
        for path, before, after in (
            ('src/map/ai/states/range_state.h', 'm_returnWeaponDelay = 800ms', 'm_returnWeaponDelay = 900ms'),
            ('scripts/globals/job_utils/dragoon.lua', 'untargetableAndUnactionable(5000)', 'untargetableAndUnactionable(6000)')):
            with self.subTest(path=path), self.assertRaisesRegex(RuntimeError, 'Source parity failed'):
                parity.check_action_recovery(ChangedSource(self.source, path, before, after))


if __name__ == '__main__':
    unittest.main()
