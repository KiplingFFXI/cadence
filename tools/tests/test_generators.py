"""Candidate revisions must parse completely without freezing data coverage."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import generate_effects as effects
import generate_modifiers as modifiers
import source_parity
from lupa import luajit21


def table_text(rows, columns=modifiers.SQL_COLUMNS['item_mods']):
    return ('CREATE TABLE `item_mods` (\n' +
            '\n'.join('  `' + name + '` int,' for name in columns) +
            '\n  PRIMARY KEY (`itemId`,`modId`)\n) ENGINE=Aria;\n' + '\n'.join(rows))


class SQLParserTests(unittest.TestCase):
    def read_rows(self, text):
        return list(modifiers.sql_rows(lambda path: text, 'sql/item_mods.sql'))

    def test_sql_spacing_and_inline_comments_are_parsed(self):
        text = table_text(['INSERT INTO `item_mods` VALUES(11405,25,20); -- Footwork',
                           '  INSERT INTO `item_mods` VALUES (11406,73,-4);'])
        self.assertEqual(self.read_rows(text), [['11405', '25', '20'], ['11406', '73', '-4']])

    def test_coverage_can_increase_and_decrease(self):
        for count in (2, 6, 1):
            text = table_text([f'INSERT INTO `item_mods` VALUES ({item},73,5);' for item in range(count)])
            self.assertEqual(len(self.read_rows(text)), count)

    def test_changed_column_order_requires_review(self):
        text = table_text(['INSERT INTO `item_mods` VALUES (1,73,5);'], ('modId', 'itemId', 'value'))
        with self.assertRaisesRegex(RuntimeError, 'SQL schema'):
            self.read_rows(text)

    def test_extra_or_missing_columns_fail(self):
        for row in ('1,73', '1,73,5,9'):
            with self.subTest(row=row), self.assertRaisesRegex(RuntimeError, 'SQL row width'):
                self.read_rows(table_text(['INSERT INTO `item_mods` VALUES (' + row + ');']))

    def test_unsupported_statements_cannot_silently_disappear(self):
        for statement in ('INSERT IGNORE INTO `item_mods` VALUES (2,73,7);',
                          'INSERT INTO `item_mods` VALUES\n(2,73,7);',
                          'INSERT INTO `item_mods` VALUES (2,73,7)',
                          'UPDATE `item_mods` SET value=8 WHERE itemId=1;',
                          'DELETE FROM `item_mods` WHERE itemId=1;',
                          'REPLACE INTO `item_mods` VALUES (1,73,8);'):
            with self.subTest(statement=statement), self.assertRaisesRegex(RuntimeError, 'SQL data statement'):
                self.read_rows(table_text(['INSERT INTO `item_mods` VALUES (1,73,5);', statement]))

    def test_multirow_insert_cannot_be_partially_parsed(self):
        with self.assertRaisesRegex(RuntimeError, 'SQL row width'):
            self.read_rows(table_text(['INSERT INTO `item_mods` VALUES (1,73,5),(2,73,6);']))

    def test_missing_data_is_not_a_successful_refresh(self):
        with self.assertRaisesRegex(RuntimeError, 'No SQL data rows'):
            self.read_rows(table_text(['-- INSERT INTO `item_mods` VALUES (1,73,5);']))

    def test_duplicate_rows_cannot_overwrite_each_other(self):
        with self.assertRaisesRegex(RuntimeError, 'Duplicate SQL primary key'):
            self.read_rows(table_text(['INSERT INTO `item_mods` VALUES (1,73,5);',
                                       'INSERT INTO `item_mods` VALUES (1,73,7);']))


class FoodParserTests(unittest.TestCase):
    def parse(self, body):
        indented = '\n'.join('    ' + line for line in body.splitlines())
        return modifiers.food_modifiers('itemObject.onEffectGain = function(target, effect)\n' + indented + '\nend',
                                        {'DEX': 9, 'STORETP': 73}, {'HUME_M': 1, 'ELVAAN_M': 3, 'ELVAAN_F': 4})

    def test_fixed_bonus_calls_add_instead_of_overwriting(self):
        self.assertEqual(self.parse('effect:addMod(xi.mod.DEX, 2)\neffect:addMod(xi.mod.DEX, 3)'),
                         ({9: 5}, {}, {}))

    def test_unreviewed_conditional_is_unknown_instead_of_last_branch_winning(self):
        self.assertEqual(self.parse('if target:getMainLvl() > 30 then\n'
                                    'effect:addMod(xi.mod.STORETP, 5)\nelse\n'
                                    'effect:addMod(xi.mod.STORETP, 10)\nend'), ({}, {}, {73: True}))

    def test_dynamic_bonus_is_unknown_instead_of_silently_zero(self):
        self.assertEqual(self.parse('effect:addMod(xi.mod.STORETP, target:getMainLvl())'), ({}, {}, {73: True}))

    def test_one_sided_race_condition_keeps_the_other_race_bonus_zero(self):
        fixed, races, unknown = self.parse('local race = target:getRace()\nif race == xi.race.ELVAAN_M or '
                                          'race == xi.race.ELVAAN_F then\neffect:addMod(xi.mod.DEX, 2)\nelse\nend')
        self.assertEqual((fixed, races, unknown), ({}, {1: {9: 0}, 3: {9: 2}, 4: {9: 2}}, {}))

    def test_branch_with_extra_behavior_is_not_treated_as_a_literal_race_bonus(self):
        fixed, races, unknown = self.parse('local race = target:getRace()\nif race == xi.race.ELVAAN_M then\n'
                                          'effect:addMod(xi.mod.DEX, 2)\nhelper(effect)\nelse\n'
                                          'effect:addMod(xi.mod.DEX, 3)\nend')
        self.assertEqual((fixed, races, unknown), ({}, {}, {9: True}))


class GeneratorCLITests(unittest.TestCase):
    def test_output_and_check_use_the_resolved_revision(self):
        for module in (modifiers, effects):
            with self.subTest(module=module.__name__), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / 'candidate' / 'data.lua'
                snapshot_target = 'GitSource' if module is modifiers else 'source_parity.GitSource'
                guard_target = 'check_guards' if module is modifiers else 'source_parity.check_guards'
                args = ['generator', '--server', directory, '--ref', 'phoenix/live', '--output', str(output)]
                with patch.object(sys, 'argv', args), \
                     patch(module.__name__ + '.' + snapshot_target) as snapshot, \
                     patch(module.__name__ + '.' + guard_target) as guards, \
                     patch.object(module, 'generate', return_value='return {}\n') as generate:
                    snapshot.return_value.ref = 'a' * 40
                    module.main()
                    self.assertEqual(output.read_bytes(), b'return {}\n')
                    snapshot.assert_called_once_with(Path(directory), 'phoenix/live')
                    guards.assert_called_once_with(snapshot.return_value)
                    generate.assert_called_once_with(Path(directory), 'a' * 40)
                    with patch.object(sys, 'argv', args + ['--check']):
                        module.main()
                    output.write_text('stale\n', encoding='utf-8')
                    with patch.object(sys, 'argv', args + ['--check']), self.assertRaises(SystemExit):
                        module.main()

    def test_missing_check_output_has_a_clear_error(self):
        for module in (modifiers, effects):
            with self.subTest(module=module.__name__), tempfile.TemporaryDirectory() as directory:
                snapshot_target = 'GitSource' if module is modifiers else 'source_parity.GitSource'
                guard_target = 'check_guards' if module is modifiers else 'source_parity.check_guards'
                with patch.object(sys, 'argv', ['generator', '--output', str(Path(directory) / 'missing'), '--check']), \
                     patch(module.__name__ + '.' + snapshot_target), \
                     patch(module.__name__ + '.' + guard_target), \
                     patch.object(module, 'generate', return_value='return {}\n'), self.assertRaises(SystemExit):
                    module.main()


REPOSITORY = Path(os.environ.get('CADENCE_SOURCE_REPO', source_parity.ROOT.parent / 'Phoenix'))


@unittest.skipUnless((REPOSITORY / '.git').exists(), 'Set CADENCE_SOURCE_REPO to the reviewed Phoenix repository')
class ReviewedGeneratorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.outputs = {module.__name__: module.generate(REPOSITORY, modifiers.REF[:12])
                       for module in (modifiers, effects)}

    def test_short_revision_resolves_to_the_full_commit_and_current_output(self):
        for module, name in ((modifiers, 'modifiers'), (effects, 'effects')):
            with self.subTest(module=module.__name__):
                output = self.outputs[module.__name__]
                self.assertIn(modifiers.REF, output)
                target = source_parity.ROOT / 'cadence' / 'data' / ('phoenix_' + name + '.lua')
                self.assertEqual(output, target.read_text(encoding='utf-8'))

    def test_kyoshu_kyahan_accuracy_latent_is_not_dropped_by_sql_spacing(self):
        data = luajit21.LuaRuntime().execute(self.outputs[modifiers.__name__])
        latents = data['items'][11405]['latents']
        self.assertTrue(any(latent['mod'] == 25 and latent['value'] == 20 and
                            latent['condition'] == 13 and latent['param'] == 406
                            for _, latent in latents.items()))

    def test_racial_food_bonuses_match_executed_phoenix_source_for_every_race(self):
        runtime = luajit21.LuaRuntime()
        data = runtime.execute(self.outputs[modifiers.__name__])
        source = modifiers.DataSource(REPOSITORY, modifiers.REF)
        runtime.execute('xi = { mod = setmetatable({ DEX = 9 }, { __index = function(_, key) return key end }) }')
        runtime.execute(source.read('scripts/enum/race.lua'))
        for item_id, name in ((4331, 'imperial_omelette'), (4564, 'royal_omelette')):
            food = runtime.execute(source.read('scripts/items/' + name + '.lua'))
            for race in range(1, 9):
                runtime.globals().race = race
                runtime.execute('actual = {}; target = { getRace = function() return race end }; '
                                'effect = { addMod = function(_, id, value) actual[id] = (actual[id] or 0) + value end }')
                food.onEffectGain(runtime.globals().target, runtime.globals().effect)
                record = data['foods'][item_id]
                expected = runtime.globals().actual[9]
                actual = record['mods'][9] or 0
                if record['race_mods']:
                    actual += record['race_mods'][race][9] or 0
                with self.subTest(food=name, race=race):
                    self.assertEqual(actual, expected)


if __name__ == '__main__':
    unittest.main()
