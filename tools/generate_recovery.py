"""Build reviewed action signatures, item recovery and spell cast estimates from Phoenix Git objects."""
import argparse
import hashlib
from pathlib import Path
import re
import sqlite3

from generate_modifiers import REF, SQL_COLUMNS, DataSource, lua, sql_rows
import source_parity
import source_yaml

ROOT = Path(__file__).resolve().parents[1]
TABLES = ('abilities', 'item_usable', 'spell_list')
JOBS = ('ranger', 'dark_knight', 'samurai', 'thief', 'corsair', 'dancer', 'rune_fencer', 'dragoon')
HELPERS = tuple('scripts/globals/job_utils/' + job + '.lua' for job in JOBS)
ERA_HELPERS = tuple('modules/era/lua/globals/job_utils/' + job + '.lua'
                    for job in ('ranger', 'samurai', 'corsair', 'dragoon'))
# These source rows resemble misplaced animation IDs. Keep them unknown until reviewed.
QUARANTINE = {
    4352: ('derfland_pear', 1, 0, 26),
    4526: ('silkworm_egg', 1, 0, 28),
    5144: ('serving_of_crimson_jelly', 1, 0, 26),
    5557: ('serving_of_mont_blanc', 1, 29, 29),
    5697: ('pepperoni_pizza', 1, 0, 28),
    5782: ('sugar_rusk', 1, 0, 26),
}
ITEM_SECONDS = {0, 1, 3, 5, 8, 12}
OVERLAY_FIELDS = {'abilities': ('animation', 'animationTime', 'actionType'),
                  'item_usable': ('activation', 'animation', 'animationTime'),
                  'spell_list': ('castTime', 'animationTime')}


def numeric(value, label, maximum=65535):
    try:
        number = float(value)
    except (TypeError, ValueError) as error:
        raise RuntimeError('Source review required for ' + label) from error
    if not 0 <= number <= maximum:
        raise RuntimeError('Source review required for ' + label)
    return int(number) if number.is_integer() else number


def tables(source):
    """Apply loaded SQL updates in init order to an isolated, in-memory copy of these tables."""
    with sqlite3.connect(':memory:') as database:
        for table in TABLES:
            columns = SQL_COLUMNS[table]
            database.execute('CREATE TABLE ' + table + ' (' + ','.join('`' + c + '` ' +
                             ('TEXT' if c in ('name', 'jobs', 'content_tag') else 'NUMERIC') for c in columns) + ')')
            rows = list(sql_rows(source.read, 'sql/' + table + '.sql'))
            database.executemany('INSERT INTO ' + table + ' VALUES (' + ','.join('?' for _ in columns) + ')', rows)
        paths = [line.split(':', 1)[1] for line in source.git('grep', '-Il', '-i', '-E',
                 r'weapon_skills|abilities|item_usable|spell_list', source.ref, '--', 'modules').splitlines()]
        applied = set()
        for entry in source_parity.module_entries(source):
            for path in paths:
                if path in applied or not path.endswith('.sql') or not (path == entry or path.startswith(entry + '/')):
                    continue
                text = source.read(path)
                applied.add(path)
                text = re.sub(r'--[^\n]*|/\*.*?\*/', '', text, flags=re.S)
                for statement in text.split(';'):
                    statement = statement.strip()
                    match = re.match(r'UPDATE\s+`?(\w+)`?\s+SET\b', statement, re.I)
                    if match and match[1].lower() in TABLES:
                        update = re.fullmatch(r'(.*?)\bWHERE\s+(.+)', statement[match.end():], re.I | re.S)
                        if not update:
                            raise RuntimeError('Source review required for recovery SQL condition: ' + path)
                        assignments = update[1]
                        fields = OVERLAY_FIELDS[match[1].lower()]
                        selected = []
                        for field in fields:
                            value = re.search(r'(?:^|,)\s*`?' + field + r'`?\s*=\s*(\d+(?:\.\d+)?)\s*(?=,|$)', assignments, re.I)
                            if value:
                                selected.append('`' + field + '`=' + value[1])
                            elif re.search(r'\b' + field + r'`?\s*=', assignments, re.I):
                                raise RuntimeError('Source review required for recovery SQL value: ' + path)
                        if not selected:
                            continue
                        try:
                            database.execute('UPDATE ' + match[1] + ' SET ' + ','.join(selected) + ' WHERE ' + update[2])
                        except sqlite3.Error as error:
                            raise RuntimeError('Source review required for recovery SQL overlay: ' + path) from error
                    elif re.search(r'\b(?:INSERT|REPLACE|DELETE|ALTER)\b.*?\b(?:weapon_skills|abilities|item_usable|spell_list)\b', statement, re.I | re.S):
                        raise RuntimeError('Source review required for recovery SQL overlay: ' + path)
        result = {}
        for table in TABLES:
            result[table] = [dict(zip(SQL_COLUMNS[table], row)) for row in database.execute('SELECT * FROM ' + table)]
        return result


def helper_body(text, name):
    match = re.search(r'^xi\.job_utils\.\w+\.' + re.escape(name) + r'\s*=\s*function\b(.*?)(?=^xi\.job_utils\.|\Z)', text, re.M | re.S)
    if not match:
        raise RuntimeError('Source review required for ability helper: ' + name)
    return match[1]


def animation_table(text, name='animationTable'):
    match = re.search(r'local\s+' + name + r'\s*=\s*\{(.*?)\n\s*\}', text, re.S)
    if not match:
        raise RuntimeError('Source review required for ability animation table: ' + name)
    values = {int(value) for value in re.findall(r'\]\s*=\s*(\d+)', match[1])}
    if not values:
        raise RuntimeError('Source review required for ability animation values: ' + name)
    return values


def build(source):
    rows = tables(source)
    texts = {job: source.read(path) for job, path in zip(JOBS, HELPERS)}
    for path in ERA_HELPERS:
        source.read(path)
    skills, skill_seconds = {}, {}
    locks = source_yaml.dataset(source, 'animation_locks').get('weapon_skill')
    if not isinstance(locks, dict):
        raise RuntimeError('Source review required for weapon skill animation locks.')
    for animation, milliseconds in locks.items():
        if type(animation) is not int or not 0 <= animation <= 65535 or type(milliseconds) is not int or not 0 <= milliseconds <= 65535:
            raise RuntimeError('Source review required for weapon skill animation lock value.')
    for row in source_yaml.weapon_skills(source).values():
        id, animation = row['id'], row['animation']
        skills[id] = {animation: True}
        skill_seconds[id] = locks.get(animation, 2000) / 1000
    abilities, names = {}, {}
    for row in rows['abilities']:
        category = int(row['actionType'])
        if category not in (3, 6, 14, 15):
            continue
        id = int(row['abilityId'])
        names[row['name']] = id
        abilities[id] = {'category': category,
                         'animations': {int(numeric(row['animation'], 'ability animation', 4095)): True},
                         'seconds': 0, 'kind': 'ability',
                         'attack_seconds': numeric(row['animationTime'], 'ability attack suspension', 120000) / 1000}

    def add(name, values, replace=False):
        if name not in names:
            raise RuntimeError('Source review required for missing ability: ' + name)
        entry = abilities[names[name]]
        if replace:
            entry['animations'] = {}
        entry['animations'].update({value: True for value in sorted(values)})

    for name, delta in (('eagle_eye_shot', 1), ('shadowbind', 1), ('bounty_shot', -1)):
        add(name, {next(iter(abilities[names[name]]['animations'])) + delta})
    for name, helper, text in (('weapon_bash', 'useWeaponBash', texts['dark_knight']),
                                ('blade_bash', 'useBladeBash', source.read(ERA_HELPERS[1]))):
        body = text if name == 'blade_bash' else helper_body(text, helper)
        add(name, animation_table(body) | {0}, replace=True)
    for name, helper in (('steal', 'useSteal'), ('despoil', 'useDespoil'), ('larceny', 'useLarceny'), ('mug', 'useMug')):
        values = {int(value) for value in re.findall(r'action:setAnimation\(target:getID\(\),\s*(\d+)\)', helper_body(texts['thief'], helper))}
        add(name, values)
    add('konzen-ittai', animation_table(helper_body(texts['samurai'], 'useKonzenIttai')) | {37}, replace=True)
    add('wild_card', set(range(132, 138)), replace=True)
    add('cutting_cards', set(range(321, 327)), replace=True)
    roll_animations = {int(row['animation']) for row in rows['abilities']
                       if row['name'].endswith('_roll') and row['name'] != 'phantom_roll'}
    add('double-up', roll_animations | {98}, replace=True)
    pairs = re.findall(r'\[xi\.skill\.\w+\s*\]\s*=\s*\{\s*(\d+),\s*(\d+)\s*\}', texts['dancer'])
    if not pairs:
        raise RuntimeError('Source review required for Dancer animation pairs.')
    for name in ('quickstep', 'box_step', 'stutter_step', 'feather_step'):
        add(name, {int(pair[0]) for pair in pairs}, replace=True)
    for name in ('desperate_flourish', 'violent_flourish', 'wild_flourish'):
        add(name, {int(pair[1]) for pair in pairs})
    rune_animations = animation_table(texts['rune_fencer'], 'weaponAnimationMap')
    for name, offset in (('swipe', 0), ('lunge', 0), ('gambit', 10), ('rayke', 20)):
        add(name, {value + offset for value in rune_animations}, replace=True)
    jump = helper_body(texts['dragoon'], 'useSuperJump')
    match = re.search(r'untargetableAndUnactionable\((\d+)\)', jump)
    if not match:
        raise RuntimeError('Source review required for Super Jump recovery.')
    jump = abilities[names['super_jump']]
    jump.update(seconds=int(match[1]) / 1000, kind='superjump')
    jump['attack_seconds'] = max(jump['attack_seconds'], jump['seconds'])
    for entry in abilities.values():
        entry['animations'] = dict(sorted(entry['animations'].items()))
    items, quarantined = {}, {}
    for row in rows['item_usable']:
        id = int(row['itemid'])
        seconds = numeric(row['animationTime'], 'item recovery duration', 255)
        activation = numeric(row['activation'], 'item activation', 60)
        if id in QUARANTINE:
            if (row['name'], activation, int(row['animation']), seconds) != QUARANTINE[id]:
                raise RuntimeError('Source review required for quarantined item: ' + str(id))
            quarantined[id] = True
        elif seconds not in ITEM_SECONDS:
            raise RuntimeError('Source review required for item recovery duration: ' + str(id))
        else:
            items[id] = seconds
    if set(quarantined) != set(QUARANTINE):
        raise RuntimeError('Source review required for removed quarantined item.')
    spells = {int(row['spellid']): numeric(row['castTime'], 'spell cast duration', 120000) / 1000
              for row in rows['spell_list']}
    spell_attack = {int(row['spellid']): numeric(row['animationTime'], 'spell attack suspension', 120000) / 1000
                    for row in rows['spell_list']}
    ranged = re.search(r'm_returnWeaponDelay\s*=\s*(\d+)ms', source.read('src/map/ai/states/range_state.h'))
    logic = re.search(r'kLogicUpdateRate\s*=\s*(\d+(?:\.\d+)?)f', source.read('src/map/map_constants.h'))
    if not ranged or not logic or float(logic[1]) <= 0:
        raise RuntimeError('Source review required for attack suspension intervals.')
    tails = {'ranged': int(ranged[1]) / 1000, 'item_min': int(1000 / float(logic[1])) / 1000}
    return {'source': source.ref, 'weaponskills': dict(sorted(skills.items())),
            'weaponskill_seconds': dict(sorted(skill_seconds.items())),
            'abilities': dict(sorted(abilities.items())), 'items': dict(sorted(items.items())),
            'quarantined_items': dict(sorted(quarantined.items())), 'spell_casts': dict(sorted(spells.items())),
            'spell_attack_seconds': dict(sorted(spell_attack.items())), 'attack_tails': tails}


def generate(server, ref=REF):
    source = DataSource(server, ref)
    result = build(source)
    result['source_hashes'] = {path: hashlib.sha256(text.encode()).hexdigest()
                               for path, text in sorted(source.cache.items())}
    lines = ['-- Reviewed Phoenix action signatures and base timings. Missing values stay unknown.',
             '-- Built by tools/generate_recovery.py from Phoenix ' + source.ref + '.', 'return {']
    for key, value in result.items():
        lines.append('    ' + key + ' = ' + lua(value) + ',')
    return '\n'.join([*lines, '}']) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, default=ROOT.parent / 'Phoenix')
    parser.add_argument('--ref', default=REF)
    parser.add_argument('--output', type=Path, default=ROOT / 'cadence/data/phoenix_recovery.lua')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source = source_parity.GitSource(args.server, args.ref)
    source_parity.check_guards(source)
    output = generate(args.server, source.ref)
    if args.check:
        if not args.output.exists() or args.output.read_text(encoding='utf-8') != output:
            raise SystemExit('Action recovery data differs from the pinned source.')
        print('Action recovery data matches source ' + source.ref + '.')
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding='utf-8', newline='\n')
        print('Wrote ' + str(args.output))


if __name__ == '__main__':
    main()
