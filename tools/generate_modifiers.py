"""Generate Cadence's passive modifier data from the pinned Phoenix source tree.

    python tools/generate_modifiers.py --server ../Phoenix
    python tools/generate_modifiers.py --server ../Phoenix --check

Reads git objects only. It does not check out, fetch, or modify the server.
"""
import argparse
import csv
import hashlib
import re
import subprocess
from pathlib import Path

from source_parity import GitSource, check_guards

REF = '465ac4c076aebd70170fe8fde032e5066ce0737e'
MODS = {71: 'mp_heal', 72: 'hp_heal', 73: 'store_tp', 173: 'martial_arts',
        259: 'dual_wield', 295: 'clear_mind', 380: 'delay_percent', 488: 'inhibit_tp',
        167: 'haste_magic', 171: 'delay_flat', 217: 'twohand_haste_ability', 383: 'haste_ability', 384: 'haste_gear', 906: 'desperate_blows',
        369: 'refresh', 370: 'regen', 404: 'regen_down', 405: 'refresh_down',
        9: 'dexterity', 25: 'accuracy', 184: 'food_accuracy_percent', 185: 'food_accuracy_cap',
        288: 'double_attack', 292: 'kick_attacks', 302: 'triple_attack', 306: 'zanshin', 430: 'quad_attack',
        481: 'extra_dual_wield_attack', 482: 'extra_kick_attack', 523: 'ammo_swing',
        865: 'mythic_attacks_twice', 866: 'mythic_attacks_thrice', 978: 'max_swings', 979: 'additional_swing_chance'}
MODS.update({id: 'weapon_skill_' + str(id - 79) for id in range(80, 92)})
ERA_TAGS = {'NULL', 'ROTZ', 'COP', 'TOAU'}
SQL_COLUMNS = {
    'augments': ('augmentId', 'multiplier', 'modId', 'value', 'isPet', 'petType'),
    'blue_spell_list': ('spellid', 'mob_skill_id', 'set_points', 'trait_category', 'trait_category_weight',
                        'primary_sc', 'secondary_sc', 'tertiary_sc', 'knockback'),
    'blue_spell_mods': ('spellId', 'modid', 'value'),
    'blue_traits': ('trait_category', 'trait_points_needed', 'traitid', 'modifier', 'value', 'tier', 'job_points_only'),
    'item_basic': ('itemid', 'subid', 'name', 'sortname', 'name_jp', 'type', 'stackSize', 'flags', 'aH', 'BaseSell'),
    'item_equipment': ('itemId', 'name', 'level', 'ilevel', 'jobs', 'MId', 'shieldSize', 'scriptType',
                       'slot', 'rslot', 'rslotlook', 'su_level'),
    'item_latents': ('itemId', 'modId', 'value', 'latentId', 'latentParam'),
    'item_mods': ('itemId', 'modId', 'value'),
    'spell_list': ('spellid', 'name', 'jobs', 'group', 'family', 'element', 'zonemisc', 'validTargets', 'skill',
                   'mpCost', 'castTime', 'recastTime', 'message', 'magicBurstMessage', 'animation', 'animationTime',
                   'AOE', 'base', 'multiplier', 'CE', 'VE', 'requirements', 'spell_range', 'radius', 'content_tag',
                   'status_effect', 'status_effect_tier'),
    'traits': ('traitid', 'name', 'job', 'level', 'rank', 'modifier', 'value', 'content_tag', 'meritid'),
}


class DataSource(GitSource):
    def git(self, *args):
        # Keep BOMs in the source hashes used by existing generated data.
        return subprocess.check_output(['git', '-C', self.repository, *args], text=True, encoding='utf-8')


def sql_rows(read, path):
    """Require the reviewed column layout and account for every data statement."""
    text = read(path)
    table = Path(path).stem
    columns = SQL_COLUMNS[table]
    schema = re.search(r'CREATE TABLE(?: IF NOT EXISTS)? `' + re.escape(table) + r'` \((.*?)\n\)', text, re.S)
    if not schema or tuple(re.findall(r'^\s*`([^`]+)`', schema[1], re.M)) != columns:
        raise RuntimeError('Source review required for SQL schema: ' + path)
    primary = re.search(r'PRIMARY KEY\s*\(([^)]*)\)', schema[1])
    indexes = [columns.index(name) for name in re.findall(r'`([^`]+)`', primary[1])] if primary else []
    seen, count = set(), 0
    for number, line in enumerate(text.splitlines(), 1):
        if not re.match(r'\s*(?:INSERT|REPLACE|UPDATE|DELETE)\b', line, re.I):
            continue
        match = re.fullmatch(r'\s*INSERT INTO `' + re.escape(table) + r'` VALUES\s*\((.*)\);\s*(?:--.*)?', line)
        if not match:
            raise RuntimeError(f'Unsupported SQL data statement: {path}:{number}')
        try:
            row = next(csv.reader([match[1]], quotechar="'", escapechar='\\', skipinitialspace=True, strict=True))
        except csv.Error as error:
            raise RuntimeError(f'Unreadable SQL row: {path}:{number}') from error
        if len(row) != len(columns):
            raise RuntimeError(f'Unexpected SQL row width: {path}:{number}')
        key = tuple(row[index] for index in indexes)
        if indexes and key in seen:
            raise RuntimeError(f'Duplicate SQL primary key: {path}:{number}')
        seen.add(key)
        count += 1
        yield row
    if not count:
        raise RuntimeError('No SQL data rows found: ' + path)


def display_name(value):
    return ' '.join(word.upper() if word.lower() in ('hp', 'mp', 'tp') else word.title()
                    for word in value.replace('_', ' ').split())


def lua(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n') + "'"
    if isinstance(value, list):
        return '{ ' + ', '.join(lua(v) for v in value) + ' }'
    return '{ ' + ', '.join((str(k) if isinstance(k, str) and re.fullmatch(r'[a-zA-Z_]\w*', k)
                            else '[' + lua(k) + ']') + ' = ' + lua(v) for k, v in value.items()) + ' }'


def generate(server, ref=REF):
    snapshot = DataSource(server, ref)
    ref, sources, git, source = snapshot.ref, snapshot.cache, snapshot.git, snapshot.read

    def rows(path):
        return sql_rows(source, path)

    equipment = {int(r[0]): r for r in rows('sql/item_equipment.sql')}
    levels = {id: int(r[2]) for id, r in equipment.items()}
    basic = {r[2]: int(r[0]) for r in rows('sql/item_basic.sql')}
    names = {id: name for name, id in basic.items()}
    items = {}

    def item(id):
        return items.setdefault(id, {'name': names.get(id, ''), 'level': levels.get(id, 0), 'mods': {}, 'latents': []})

    weapon_mods = {}
    for r in rows('sql/item_mods.sql'):
        if int(r[1]) in MODS:
            item(int(r[0]))['mods'][int(r[1])] = int(r[2])
        if int(r[1]) in (256, 355):
            weapon_mods.setdefault(int(r[0]), {})[int(r[1])] = int(r[2])
    for r in rows('sql/item_latents.sql'):
        if int(r[1]) in MODS:
            item(int(r[0]))['latents'].append({'mod': int(r[1]), 'value': int(r[2]),
                                              'condition': int(r[3]), 'param': int(r[4])})

    traits, trait_names = {}, {}
    for r in rows('sql/traits.sql'):
        trait_names[int(r[0])] = display_name(r[1])
        # Active era SQL removes the modern native Desperate Blows bonus.
        if r[1] == 'desperate blows':
            r[3], r[6], r[8] = '75', '0', '2502'
        if int(r[5]) in MODS and r[7] in ERA_TAGS and int(r[3]) <= 75:
            key = (int(r[2]), int(r[0]), int(r[4]))
            trait = traits.setdefault(key, {'job': key[0], 'trait': key[1], 'rank': key[2],
                                            'level': int(r[3]), 'mods': {}})
            trait['mods'][int(r[5])] = int(r[6])
    blue_traits = {}
    for r in rows('sql/blue_traits.sql'):
        if int(r[3]) in MODS and r[6] == '0':
            key = (int(r[0]), int(r[5]))
            trait = blue_traits.setdefault(key, {'category': key[0], 'rank': key[1], 'trait': int(r[2]),
                                                 'name': trait_names[int(r[2])], 'points': int(r[1]), 'mods': {}})
            trait['mods'][int(r[3])] = int(r[4])
    spells = {int(r[0]): r for r in rows('sql/spell_list.sql')}
    blue_spells, valid_blue_spells = {}, {}
    for r in rows('sql/blue_spell_list.sql'):
        spell = spells.get(int(r[0]))
        if spell is None:
            continue
        level = int(spell[2][2:][30:32], 16)
        if spell[24] in ERA_TAGS and level <= 75:
            valid_blue_spells[int(r[0])] = True
            blue_spells[int(r[0])] = {'name': display_name(spell[1]), 'category': int(r[3]),
                                      'weight': int(r[4]), 'level': level, 'mods': {}}
    for r in rows('sql/blue_spell_mods.sql'):
        spell = blue_spells.get(int(r[0]))
        if spell is not None and int(r[1]) in MODS:
            spell['mods'][int(r[1])] = int(r[2])

    augments, augment_ids = {}, {}
    for r in rows('sql/augments.sql'):
        augment_ids[int(r[0])] = True
        if int(r[2]) in MODS and r[4] == '0':
            augments.setdefault(int(r[0]), []).append({'mod': int(r[2]), 'base': int(r[3]), 'multiplier': max(1, int(r[1]))})

    effect_ids = {m[1]: int(m[2]) for m in re.finditer(r'^  ([a-z0-9_]+):\s*\n\s+id:\s*(\d+)', source('data/status_effects.yaml'), re.M)}
    all_effect_ids = dict(effect_ids)
    song_roll_effects = {}
    for match in re.finditer(r'^  (\w+):\n(.*?)(?=^  \w+:|\Z)', source('data/status_effects.yaml'), re.M | re.S):
        if re.search(r'^\s+- (song|roll)$', match[2], re.M):
            song_roll_effects[effect_ids[match[1]]] = True
    wanted_effects = ('food', 'enchantment', 'samurai_roll', 'healers_roll', 'store_tp', 'bust', 'aftermath', 'inhibit_tp',
                      'signet', 'sigil', 'sj_restriction', 'obliviscence', 'arcane_crest', 'dragon_breaker', 'sepulcher',
                      'firestorm', 'hailstorm', 'windstorm', 'sandstorm', 'thunderstorm', 'rainstorm', 'aurorastorm', 'voidstorm',
                      'haste', 'slow', 'elegy', 'march', 'hasso', 'spirit_surge', 'weakness', 'hundred_fists', 'last_resort',
                      'regen', 'refresh', 'healing', 'sanction', 'disease', 'plague', 'curse_ii', 'blindness', 'accuracy_boost',
                      'accuracy_down', 'aggressor', 'focus', 'footwork', 'fighters_roll', 'hunters_roll', 'madrigal')
    missing_effects = set(wanted_effects) - effect_ids.keys()
    if missing_effects:
        raise RuntimeError('Missing required status effects: ' + ', '.join(sorted(missing_effects)))
    effect_ids = {k: effect_ids[k] for k in wanted_effects}

    foods, activated = {}, {}
    mod_by_name = {m[1].upper(): int(m[2]) for m in re.finditer(r'^  (\w+):\s+(\d+)', source('data/enums/mod.yaml'), re.M)
                   if int(m[2]) in MODS}
    if set(mod_by_name.values()) != set(MODS):
        raise RuntimeError('Missing required modifier enum IDs.')
    effect_mods = {}
    for full in git('grep', '-l', '-E', 'xi.mod.(' + '|'.join(mod_by_name) + ')([^A-Z_]|$)', ref, '--', 'scripts/effects').splitlines():
        path = full.split(':', 1)[1]
        name = Path(path).stem
        if name not in all_effect_ids:
            continue
        text = source(path).split('onEffectGain', 1)[-1].split('onEffectTick', 1)[0]
        mods = {mod_by_name[n]: True for n in re.findall(r'(?:effect|target):addMod\(xi.mod.(\w+)', text) if n in mod_by_name}
        if name in ('sanction', 'sigil'):
            mods.update({369: True, 370: True})
        if mods:
            effect_mods[all_effect_ids[name]] = {'name': name, 'mods': mods}
    pattern = 'xi.effect.FOOD|xi.mod.(' + '|'.join(mod_by_name) + ')([^A-Z_]|$)'
    food_paths = git('grep', '-l', '-E', pattern, ref, '--', 'scripts/items').splitlines()
    for full in food_paths:
        path = full.split(':', 1)[1]
        text = source(path)
        name = Path(path).stem
        id = basic.get(name)
        if id is None:
            match = re.search(r'^-- ID: (\d+)', text, re.M)
            id = int(match[1]) if match else None
        if id is None:
            continue
        mods, party_mods = {}, {}
        for mod, value in re.findall(r'effect:addMod\(xi\.mod\.(\w+),\s*(-?\d+)\)', text):
            if mod in mod_by_name:
                mods[mod_by_name[mod]] = int(value)
        for mod, values in re.findall(r'\{\s*xi\.mod\.(\w+),\s*((?:-?\d+\s*,?\s*)+)\}', text):
            if mod in mod_by_name:
                party_mods[mod_by_name[mod]] = [int(v) for v in values.split(',') if v.strip()]
        duration = re.search(r'duration\s*=\s*(\d+)', text)
        record = {'name': name, 'mods': mods, 'party_mods': party_mods,
                  'duration': int(duration[1]) if duration else 0}
        if 'xi.effect.FOOD' in text:
            foods[id] = record
        elif mods and 'xi.effect.ENCHANTMENT' in text:
            record['remove_on_unequip'] = 'onItemUnequip' in text
            icon = re.search(r'icon\s*=\s*xi.effect.(\w+)', text)
            record['effect'] = effect_ids.get(icon[1].lower(), 162) if icon else 162
            record['status_effect'] = 162
            record['stackable'] = True
            activated[id] = record

    item_enums = {m[1]: int(m[2]) for m in re.finditer(r'^\s*(\w+)\s*=\s*(\d+),', source('scripts/enum/item.lua'), re.M)}
    sets = []
    for match in re.finditer(r'^    \[(\d+)\] =.*?(?=^    \[\d+\] =|\Z)', source('scripts/globals/gear_sets.lua'), re.M | re.S):
        text = match[0]
        mods = {}
        for mod, values in re.findall(r'\{\s*xi\.mod\.(\w+),\s*((?:-?\d+\s*,?\s*)+)\}', text):
            if mod in mod_by_name:
                mods[mod_by_name[mod]] = [int(v) for v in values.split(',') if v.strip()]
        if not mods:
            continue
        minimum = re.search(r'minEquipped\s*=\s*(\d+)', text)
        maximum = re.search(r'maxEquipped\s*=\s*(\d+)', text)
        sets.append({'id': int(match[1]), 'items': [item_enums[n] for n in re.findall(r'xi\.item\.(\w+)', text)],
                     'minimum': int(minimum[1]) if minimum else 2,
                     'maximum': int(maximum[1]) if maximum else 99, 'mods': mods})

    # Include the executable formula and overrides in provenance, not just SQL rows.
    for path in ('scripts/effects/healing.lua', 'scripts/combat/basic/tp.lua', 'modules/era/lua/combat/basic/tp.lua',
                 'modules/era/lua/globals/job_utils/corsair.lua', 'modules/era/data/merits.yaml', 'data/merits.yaml',
                 'scripts/globals/aftermath.lua', 'scripts/effects/food.lua', 'src/map/items/item_equipment.cpp',
                 'scripts/globals/job_utils/corsair.lua', 'scripts/effects/samurai_roll.lua',
                 'scripts/effects/store_tp.lua', 'scripts/effects/bust.lua', 'scripts/effects/inhibit_tp.lua',
                 'scripts/effects/arcane_crest.lua', 'scripts/effects/dragon_breaker.lua', 'scripts/effects/sepulcher.lua',
                 'src/map/latent_effect_container.cpp', 'src/map/utils/battleutils.cpp', 'modules/init.txt',
                 'src/map/entities/battle_entity.cpp', 'src/map/utils/charutils.cpp', 'src/map/utils/blueutils.cpp', 'src/common/vana_time.h',
                 'data/enums/latent.yaml', 'data/enums/weather.yaml',
                 'modules/era/sql/soa/job_adjustments.sql', 'modules/era/sql/rov/job_adjustments.sql',
                 'modules/era/lua/globals/job_utils/dark_knight.lua', 'modules/era/lua/globals/job_utils/dragoon.lua',
                 'modules/era/lua/globals/job_utils/samurai.lua', 'modules/era/lua/effects/era_signet_effects.lua',
                 'scripts/globals/job_utils/dancer.lua', 'scripts/effects/haste_samba_haste.lua',
                 'scripts/effects/haste.lua', 'scripts/effects/slow.lua', 'scripts/effects/elegy.lua',
                 'scripts/effects/march.lua', 'scripts/effects/regen.lua', 'scripts/effects/refresh.lua'):
        source(path)
    weaponskills = {int(m[2]): m[1].lower() for m in re.finditer(
        r'^\s*(\w+)\s*=\s*(\d+),', source('scripts/enum/weaponskill.lua'), re.M)}
    relic_effects = {}
    for match in re.finditer(r'^    \[(\d+)\]\s*= \{ mods = \{ (.*?) \}, duration = getTier1RelicDuration',
                             source('scripts/globals/aftermath.lua'), re.M):
        relic_effects[int(match[1])] = {mod_by_name[name]: int(value) for name, value in
            re.findall(r'xi.mod.(\w+),\s*(-?\d+)', match[2]) if name in mod_by_name}
    relic_aftermath = {}
    for id, mods in sorted(weapon_mods.items()):
        if mods.get(256) not in relic_effects or mods.get(355) not in weaponskills or levels.get(id, 99) > 75:
            continue
        script = source('scripts/actions/weaponskills/' + weaponskills[mods[355]] + '.lua')
        slot = re.search(r'xi.aftermath.addStatusEffect\(player, tp, xi.slot.(MAIN|RANGED), xi.aftermath.type.RELIC\)', script)
        if slot:
            relic_aftermath[id] = {'weaponskill': mods[355], 'store_tp': relic_effects[mods[256]].get(73, 0),
                                    'mods': relic_effects[mods[256]],
                                    'slot': 0 if slot[1] == 'MAIN' else 2, 'duration_per_tp': 0.02}
    zones = {re.sub(r'[^a-z0-9]', '', m[1].lower()): int(m[2])
             for m in re.finditer(r'^  (\w+):\s*(\d+)', source('data/enums/zone.yaml'), re.M)}
    region_enum = source('src/map/zone.h').split('enum class REGION_TYPE', 1)[1].split('};', 1)[0]
    regions = {m[1]: int(m[2]) for m in re.finditer(r'^\s*(\w+)\s*=\s*(\d+)', region_enum, re.M)}
    region_code = source('src/map/utils/zoneutils.cpp').split('auto GetCurrentRegion(', 1)[1].split('auto GetCurrentContinent(', 1)[0]
    zone_regions = {id: regions['UNKNOWN'] for id in zones.values()}
    pending = []
    for match in re.finditer(r'case xi::ZoneId::(\w+):|return REGION_TYPE::(\w+);', region_code):
        if match[1]:
            pending.append(zones[re.sub(r'[^a-z0-9]', '', match[1].lower())])
        else:
            for id in pending:
                zone_regions[id] = regions[match[2]]
            pending = []
    zone_assault, zone_dynamis = {}, {}
    for path in git('ls-tree', '-r', '--name-only', ref, 'data/zones').splitlines():
        if not path.endswith('/zone.yaml'):
            continue
        zone = zones.get(re.sub(r'[^a-z0-9]', '', path.split('/')[2]))
        if zone is None:
            continue
        text = source(path)
        types = re.search(r'^type:\s*\[([^\]]*)\]', text, re.M)
        values = set(types[1].replace(' ', '').split(',')) if types else set()
        zone_assault[zone] = 'instanced' in values and 28 <= zone_regions[zone] <= 32
        zone_dynamis[zone] = 'dynamis' in values
    coverage = {}
    for mod in MODS:
        fixed = [i for i in items.values() if mod in i['mods']]
        coverage[mod] = {'fixed': len(fixed), 'negative': sum(i['mods'][mod] < 0 for i in fixed),
                         'latents': sum(sum(l['mod'] == mod for l in i['latents']) for i in items.values()),
                         'augments': sum(any(a['mod'] == mod for a in rows) for rows in augments.values()),
                         'sets': sum(mod in s['mods'] for s in sets),
                         'foods': sum(mod in f['mods'] or mod in f['party_mods'] for f in foods.values()),
                         'activated': sum(mod in a['mods'] for a in activated.values()),
                         'blue_spells': sum(mod in s['mods'] for s in blue_spells.values())}
    data = {
        'source': {'repository': 'https://github.com/phoenixffxi/Phoenix', 'ref': ref,
                   'profile': 'Phoenix TOAU level 75', 'restrict_content': True, 'max_level': 75,
                   'enabled_content': ['ROTZ', 'COP', 'TOAU'], 'deployed_runtime_verified': False,
                   'note': 'All item rows are retained for equipped IDs. Source presence does not prove obtainable content.'},
        'mod_ids': {v: k for k, v in MODS.items()}, 'effect_ids': effect_ids, 'song_roll_effects': song_roll_effects,
        'relevant_effects': {v: True for v in set(effect_ids.values()) | set(effect_mods)}, 'effect_mods': effect_mods,
        'zone_regions': dict(sorted(zone_regions.items())), 'zone_assault': zone_assault, 'zone_dynamis': zone_dynamis,
        'merit_ids': {'store_tp': 0x444, 'desperate_blows': 0x9C6, 'ikishoten': 0xAC4, 'double_attack': 0x188},
        'items': dict(sorted(items.items())), 'levels': dict(sorted(levels.items())),
        'traits': [traits[k] for k in sorted(traits)], 'blue_traits': [blue_traits[k] for k in sorted(blue_traits)],
        'blue_spells': dict(sorted(blue_spells.items())), 'valid_blue_spells': valid_blue_spells, 'augments': dict(sorted(augments.items())),
        'augment_ids': dict(sorted(augment_ids.items())), 'foods': dict(sorted(foods.items())),
        'activated_items': dict(sorted(activated.items())), 'sets': sets, 'relic_aftermath': relic_aftermath,
        'rolls': {effect_ids['samurai_roll']: {'powers': [8,32,10,12,14,4,16,20,22,24,40], 'bonus':10, 'bonus_job':12, 'phantom_base':4, 'mod':73},
                  effect_ids['healers_roll']: {'powers': [2,3,10,4,4,5,1,6,7,7,12], 'bonus':3, 'bonus_job':3, 'phantom_base':3, 'mod':71}},
        'weather_elements': {4:1,5:1,6:6,7:6,8:4,9:4,10:3,11:3,12:2,13:2,14:5,15:5,16:7,17:7,18:8,19:8},
        'coverage': coverage, 'source_hashes': {p:hashlib.sha256(t.encode()).hexdigest() for p,t in sorted(sources.items())},
        'coverage_notes': {
            'included': ['signed fixed item modifiers', 'conditional item latents', 'player augments', 'equipment sets',
                         'observed item enchantments', 'observed relic aftermath', 'era job and blue traits',
                         'eligible set Blue Magic spell modifiers', 'food modifiers'],
            'indirect': ['Caster Regen and Refresh potency, song instruments and ability enhancements change received effect power; unknown power remains uncertain.',
                         'Current maximum HP and MP come from client totals, including gear and effects.',
                         'Weapon base delay and weapon identity come from equipped client resources.'],
            'excluded': ['Pet modifiers and pet augment rows do not modify the player.',
                         'Ranged delay, Snapshot, ability recast, spell recast and movement speed are outside the melee interval.',
                         'Haste Samba, Dancer, Scholar, geomancy and post-75 traits are outside the configured TOAU profile.'],
            'uncertain': ['Unseen latent conditions and unsupported augment formats remain unknown.',
                          'Food identity, received spell or roll power and existing enchantments cannot be reconstructed from icons alone.',
                          'Avatar perpetuation and unidentified passive effects require observed net recovery.',
                          'All item rows are retained for equipped IDs; level and source presence do not establish era acquisition.'],
        },
    }
    text = '-- Generated by tools/generate_modifiers.py. Regenerate; do not edit.\n'
    text += '-- Phoenix live ' + ref + '; local TOAU/75 profile, not deployed runtime verification.\n'
    text += 'return {\n'
    for key, value in data.items():
        if isinstance(value, dict) and len(value) > 20:
            text += '    ' + key + ' = {\n'
            for k, v in value.items():
                text += '        [' + lua(k) + '] = ' + lua(v) + ',\n'
            text += '    },\n'
        else:
            text += '    ' + key + ' = ' + lua(value) + ',\n'
    return text + '};\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, default=Path(__file__).resolve().parents[2] / 'Phoenix')
    parser.add_argument('--ref', default=REF)
    parser.add_argument('--output', type=Path,
                        default=Path(__file__).resolve().parents[1] / 'cadence/data/phoenix_modifiers.lua')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    snapshot = GitSource(args.server, args.ref)
    check_guards(snapshot)
    destination = args.output
    text = generate(args.server, snapshot.ref)
    if args.check:
        if not destination.exists() or destination.read_text(encoding='utf-8') != text:
            raise SystemExit('Generated modifier data is out of date.')
        print('Modifier data matches source ' + snapshot.ref + '.')
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text, encoding='utf-8', newline='\n')
        print(destination)


if __name__ == '__main__':
    main()
