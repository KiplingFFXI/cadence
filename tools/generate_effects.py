"""Build narrow enemy timing metadata from pinned Phoenix Git objects.

Only ordinary supported spells and fixed duration gear are modeled. Other actions
remain observed with unknown durations. No Checkmate installation is required.
"""
import argparse
import csv
import hashlib
import re
import subprocess
from pathlib import Path

from generate_modifiers import REF, lua
import source_parity

EFFECTS = {'SLEEP_I': 2, 'SLEEP_II': 19, 'LULLABY': 193, 'STUN': 10,
           'PETRIFICATION': 7, 'TERROR': 28, 'SLOW': 13, 'HASTE': 33, 'ELEGY': 194}
MODS = {'elegy_effect': 'elegy', 'lullaby_effect': 'lullaby', 'all_songs_effect': 'songs',
        'song_duration_bonus': 'song_duration', 'enf_mag_duration': 'enfeebling_duration'}
GUARDED = (
    'scripts/globals/spells/enfeebling_spell.lua',
    'scripts/globals/spells/enfeebling_song.lua',
    'modules/phoenix/lua/globals/spells/enfeebling_spell.lua',
    'modules/era/lua/actions/spells/spell_adjustments.lua',
    'modules/era/data/merits.yaml',
    'data/merits.yaml',
    'data/enums/mod.yaml',
    'modules/init.txt',
)


def generate(server):
    sources = {}

    def source(path):
        if path not in sources:
            sources[path] = subprocess.check_output(['git', '-C', str(server), 'show', REF + ':' + path],
                                                    text=True, encoding='utf-8')
        return sources[path]

    def rows(path):
        for line in source(path).splitlines():
            match = re.match(r'INSERT INTO `[^`]+` VALUES \((.*)\);', line)
            if match:
                yield next(csv.reader([match[1]], quotechar="'", escapechar='\\', skipinitialspace=True))

    for path in GUARDED:
        source(path)
    spell_rows = {r[1].upper(): r for r in rows('sql/spell_list.sql')
                  if r[24] in ('NULL', 'ROTZ', 'COP', 'TOAU')}
    ids = {name: int(row[0]) for name, row in spell_rows.items()}
    spells = {}
    for song, path in ((False, GUARDED[0]), (True, GUARDED[1])):
        pattern = r'\[xi\.magic\.spell\.(\w+)\s*\]\s*=\s*\{([^{}]*)\}'
        for name, body in re.findall(pattern, source(path)):
            fields = [field.strip() for field in body.split(',')]
            effect = EFFECTS.get(fields[0].replace('xi.effect.', ''))
            if effect is None or name not in ids:
                continue
            seconds = fields[4 if song else 5]
            if not seconds.isdigit():
                raise RuntimeError('Unreadable duration: ' + name)
            row = {'effect': effect, 'seconds': int(seconds)}
            if song:
                key = fields[5].replace('xi.mod.', '').lower()
                row['song'] = MODS[key]
            else:
                row['enfeebling'] = spell_rows[name][8] == '@SKILL_ENFEEBLING'
            if effect == 10:
                row.update(seconds=8, random=True)
            spells[ids[name]] = row
    enum = source('data/enums/mod.yaml')
    mod_ids = {}
    for name, key in MODS.items():
        match = re.search(r'^\s*' + name + r':\s*(\d+)', enum, re.M)
        if not match:
            raise RuntimeError('Missing duration modifier: ' + name)
        mod_ids[int(match[1])] = key
    equipment = {int(r[0]): int(r[2]) for r in rows('sql/item_equipment.sql')}
    gear = {}
    for row in rows('sql/item_mods.sql'):
        key = mod_ids.get(int(row[1]))
        if key:
            item = gear.setdefault(int(row[0]), {'level': equipment.get(int(row[0]), 0)})
            item[key] = int(row[2])
    latents = sorted({int(r[0]) for r in rows('sql/item_latents.sql') if int(r[1]) in mod_ids})
    augments, augment_ids = {}, {}
    for row in rows('sql/augments.sql'):
        augment_ids[int(row[0])] = True
        key = mod_ids.get(int(row[2]))
        if key and row[4] == '0':
            augments.setdefault(int(row[0]), []).append({'key': key, 'base': int(row[3]),
                                                        'multiplier': max(1, int(row[1]))})

    era = source('modules/era/data/merits.yaml')
    if not re.search(r'enfeebling_magic_duration:\s*\n\s*max_upgrades: 0', era):
        raise RuntimeError('Enfeebling duration merits changed; review the timing model.')
    result = {
        'source': REF, 'spells': dict(sorted(spells.items())), 'gear': dict(sorted(gear.items())),
        'latent_items': {id: True for id in latents}, 'troubadour': 348,
        'augments': dict(sorted(augments.items())), 'augment_ids': dict(sorted(augment_ids.items())),
        'merits': {'slow_ii': 0x0902, 'enfeebling_duration': 0x090C, 'enfeebling_duration_max': 0},
        'source_hashes': {path: hashlib.sha256(value.encode()).hexdigest() for path, value in sorted(sources.items())},
    }
    lines = ['-- Enemy timing inputs before resists. Unknown sources keep their uncertainty.',
             '-- Built by tools/generate_effects.py from Phoenix ' + REF + '.', 'return {']
    for key, value in result.items():
        lines.append('    ' + key + ' = ' + lua(value) + ',')
    lines.append('}')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, default=Path('../Phoenix'))
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target = Path(__file__).resolve().parents[1] / 'cadence/data/phoenix_effects.lua'
    source_parity.check_guards(source_parity.GitSource(args.server, REF))
    output = generate(args.server)
    if args.check:
        if target.read_text(encoding='utf-8') != output:
            raise SystemExit('Timing effect metadata differs from the pinned source.')
        print('Timing effect data matches pinned source.')
    else:
        target.write_text(output, encoding='utf-8', newline='')
        print('Wrote ' + str(target))


if __name__ == '__main__':
    main()
