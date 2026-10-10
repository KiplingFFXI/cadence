"""Check Cadence's TP, recovery and delay rules against reviewed Phoenix source."""
import hashlib
import itertools
import json
import math
from pathlib import Path
import re
import subprocess

from lupa import luajit21

ROOT = Path(__file__).resolve().parents[1]
GUARDS = Path(__file__).with_name('source_guards.json')
TP = 'scripts/combat/basic/tp.lua'
ERA_TP = 'modules/era/lua/combat/basic/tp.lua'
HEALING = 'scripts/effects/healing.lua'
MODULE_RULES = (r'STORETP|HPHEAL|MPHEAL|CLEAR_MIND|MARTIAL_ARTS|DUAL_WIELD|HASTE_GEAR|HASTE_MAGIC|'
                r'HASTE_ABILITY|TWOHAND_HASTE|DELAYP|DELAY_REDUCTION_CAP|HEALING_TP_CHANGE|'
                r'(^|[^A-Z_])DELAY([^A-Z_]|$)|REGEN|REFRESH|INHIBIT_TP|AFTERMATH|'
                r'SAMURAI_ROLL|HEALERS_ROLL|xi\.effect\.FOOD|xi\.items\.|GEAR_SETS|ENF_MAG_DURATION|SONG_DURATION_BONUS|'
                r'ALL_SONGS_EFFECT|ELEGY_EFFECT|LULLABY_EFFECT|TROUBADOUR|'
                r'xi\.(spells|magic)\.(enfeebling|enhancing)|xi\.aftermath|'
                r'xi\.combat\.tp|xi\.effects\.(healing|slow|haste|elegy|march|hundred_fists|hasso)|'
                r'item_mods|item_latents|blue_spell_mods|blue_traits|traits|augments|merits')
FILES = [TP, ERA_TP, HEALING, 'src/map/ai/states/attack_state.cpp', 'src/map/map_constants.h',
         'src/map/utils/blueutils.cpp', 'scripts/effects/haste.lua', 'scripts/effects/slow.lua',
         'scripts/effects/elegy.lua', 'scripts/effects/march.lua', 'scripts/effects/hasso.lua',
         'scripts/effects/regen.lua', 'scripts/effects/refresh.lua',
         'scripts/globals/spells/enfeebling_spell.lua', 'scripts/globals/spells/enfeebling_song.lua',
         'modules/era/lua/actions/spells/spell_adjustments.lua', 'modules/era/data/merits.yaml',
         'data/enums/mod.yaml', 'data/enums/latent.yaml', 'data/enums/weather.yaml',
         'data/merits.yaml', 'data/status_effects.yaml', 'settings/default/main.lua',
         'scripts/globals/job_utils/corsair.lua', 'scripts/globals/job_utils/dark_knight.lua',
         'scripts/globals/job_utils/dragoon.lua', 'scripts/globals/job_utils/samurai.lua',
         'scripts/globals/job_utils/dancer.lua', 'scripts/globals/aftermath.lua',
         'scripts/globals/gear_sets.lua', 'scripts/globals/item_utils.lua',
         'scripts/enum/item.lua', 'scripts/enum/weaponskill.lua',
         'scripts/effects/food.lua', 'scripts/effects/samurai_roll.lua', 'scripts/effects/healers_roll.lua',
         'scripts/effects/store_tp.lua', 'scripts/effects/bust.lua', 'scripts/effects/inhibit_tp.lua',
         'scripts/effects/arcane_crest.lua', 'scripts/effects/dragon_breaker.lua', 'scripts/effects/sepulcher.lua',
         'scripts/effects/haste_samba_haste.lua', 'scripts/effects/hundred_fists.lua',
         'src/map/items/item_equipment.cpp', 'src/map/latent_effect_container.cpp',
         'src/map/utils/battleutils.cpp', 'src/map/utils/charutils.cpp',
         'src/map/utils/zoneutils.cpp', 'src/map/zone.h', 'src/common/vana_time.h']
FUNCTIONS = {
    'src/map/entities/battle_entity.cpp': ['CBattleEntity::GetWeaponDelay'],
    'src/map/items/item_weapon.cpp': ['CItemWeapon::setDelay'],
    'src/map/status_effect_container.cpp': ['CStatusEffectContainer::TickEffects', 'CStatusEffectContainer::TickRegen'],
}


class GitSource:
    def __init__(self, repository, ref):
        self.repository = str(repository)
        self.ref = self.git('rev-parse', '--verify', ref + '^{commit}').strip()
        self.cache = {}

    def git(self, *args):
        return subprocess.check_output(['git', '-C', self.repository, *args], text=True, encoding='utf-8-sig')

    def read(self, path):
        if path not in self.cache:
            self.cache[path] = self.git('show', self.ref + ':' + path)
        return self.cache[path]

    def candidates(self):
        result = subprocess.run(['git', '-C', self.repository, 'grep', '-Il', '-i', '-E', MODULE_RULES,
                                 self.ref, '--', 'modules'], text=True, encoding='utf-8', capture_output=True)
        if result.returncode not in (0, 1):
            raise RuntimeError('Cannot read Phoenix module candidates: ' + result.stderr)
        return [line.split(':', 1)[1] for line in result.stdout.splitlines()]


def fingerprint(text, language='lua'):
    # Keep quoted values and YAML nesting. Code spacing and comments do not change a rule.
    comments = {'lua': r'--\[\[.*?\]\]|--[^\n]*', 'cpp': r'/\*.*?\*/|//[^\n]*',
                'data': r'#[^\n]*', 'sql': r'/\*(?![!+]).*?\*/|--(?=\s|$)[^\n]*|#[^\n]*'}[language]
    pattern = (r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|' + comments + r'|'
               r'[A-Za-z_]\w*|\d+(?:\.\d+)?|'
               r'<<=|>>=|\.\.\.|\.\.|==|~=|!=|<=|>=|&&|\|\||\+\+|--|<<|>>|'
               r'\+=|-=|\*=|/=|%=|&=|\|=|\^=|->|::|[^\s]')

    def tokens(value):
        return [token for token in re.findall(pattern, value, re.S)
                if not re.fullmatch(comments, token, re.S)]

    if language == 'data':
        lines = []
        for line in text.splitlines():
            parts = tokens(line)
            # Block and multiline scalars need their exact contents, including spaces and # characters.
            if any(part in ('|', '>', "'", '"') for part in parts):
                return hashlib.sha256(text.replace('\r\n', '\n').encode('utf-8')).hexdigest()
            if parts:
                lines.append(str(len(line) - len(line.lstrip())) + ':' + '\0'.join(parts))
        code = '\n'.join(lines)
    else:
        code = '\0'.join(tokens(text))
    return hashlib.sha256(code.encode('utf-8')).hexdigest()


def file_fingerprint(source, path):
    language = ('cpp' if path.endswith(('.cpp', '.h', '.hpp')) else
                'data' if path.endswith(('.yaml', '.yml')) else 'sql' if path.endswith('.sql') else 'lua')
    return fingerprint(source.read(path), language)


def function_body(text, name):
    match = re.search(re.escape(name) + r'\([^;]*?\)\s*(?:const\s*)?(?:->[^\n]+)?\s*\{', text)
    if not match:
        raise RuntimeError('Cannot find source function ' + name)
    start = match.end() - 1
    depth = 0
    for at in range(start, len(text)):
        if text[at] == '{':
            depth += 1
        elif text[at] == '}':
            depth -= 1
            if depth == 0:
                return text[match.start():at + 1]
    raise RuntimeError('Cannot read source function ' + name)


def module_entries(source):
    return ['modules/' + line.split('#', 1)[0].strip().rstrip('/')
            for line in source.read('modules/init.txt').splitlines() if line.split('#', 1)[0].strip()]


def loaded_modules(source):
    entries = module_entries(source)
    return sorted(path for path in source.candidates() if path.endswith(('.lua', '.cpp', '.h', '.hpp', '.sql', '.yaml', '.yml'))
                  and any(path == entry or path.startswith(entry + '/') for entry in entries))


def observed_guards(source):
    result = {path: file_fingerprint(source, path) for path in FILES}
    for path, functions in FUNCTIONS.items():
        for name in functions:
            result[path + ':' + name] = fingerprint(function_body(source.read(path), name), 'cpp')
    modules = {path: file_fingerprint(source, path) for path in loaded_modules(source)}
    return {'rules': result, 'modules': modules, 'load_order': module_entries(source)}


def check_guards(source, manifest=None):
    manifest = manifest or json.loads(GUARDS.read_text(encoding='utf-8'))
    actual = observed_guards(source)
    for group in ('rules', 'modules'):
        expected = manifest[group]
        changed = [path for path in sorted(set(expected) | set(actual[group]))
                   if expected.get(path) != actual[group].get(path)]
        if changed:
            raise RuntimeError('Source review required for %s:\n  %s' % (group, '\n  '.join(changed)))
    if actual['load_order'] != manifest.get('load_order'):
        raise RuntimeError('Source review required for modules/init.txt load order.')
    return manifest


def lua_runtime(addon=ROOT / 'cadence'):
    runtime = luajit21.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute('package.path = [[%s/?.lua;]] .. package.path' % str(addon).replace('\\', '/'))
    runtime.execute("""
        local function names() return setmetatable({}, {__index=function(_, key) return key end}); end
        xi = {combat={tp={}},mod=names(),effect=names(),merit=names(),slot=names(),skill=names(),
              objType=names(),region={LIMBUS=27,RONFAURE_FRONT=33,VALDEAUNIA_FRONT=40},
              settings={main={HEALING_TP_CHANGE=-100}},expansion={SOA=10},pre=function() return true end};
        package.preload['modules/module_utils'] = function() return true end;
        package.preload['scripts/quests/adoulin/Dances_with_Luopans'] = function() return true end;
        Module={new=function() return {addOverride=function(_,name,fn)
            assert(name == 'xi.combat.tp.calculateTPReturn'); xi.combat.tp.calculateTPReturn=fn;
        end} end};
        parity_actor=function(c)
            return {isDualWielding=function() return c.dual end, isUsingH2H=function() return c.h2h end,
                getObjType=function() return 'PC' end, getEquippedItem=function() return c.shield and {} or nil end,
                getSkillRank=function() return c.skilled and 1 or 0 end, getMod=function(_,k) return c.mods[k] or 0 end,
                getMerit=function() return 0 end, getBaseDelay=function() return c.base end,
                hasStatusEffect=function(_,k) return k=='MEIKYO_SHISUI' and c.meikyo end};
        end;
        parity_heal=function(fn,c,tick)
            local hp,mp=0,0;
            local actor={getPet=function() return nil end, hasStatusEffect=function(_,k) return c.effects[k] end,
                getCurrentRegion=function() return c.region end, getMod=function(_,k) return c.mods[k] or 0 end,
                isAutomaton=function() return false end, getMainLvl=function() return c.level end,
                getMaxHP=function() return c.max_hp end, addTP=function() end, getObjType=function() return 'PC' end,
                getEminenceProgress=function() return false end, addHPLeaveSleeping=function(_,v) hp=v end,
                updateEnmityFromCure=function() end, addMP=function(_,v) mp=v end};
            fn(actor,{getTickCount=function() return tick end});
            return hp,mp;
        end;
    """)
    return runtime


def same(actual, expected, label, tolerance=0):
    if abs(actual - expected) > tolerance:
        raise RuntimeError('Source parity failed for %s: addon %r, source %r.' % (label, actual, expected))


def check_tp(source, addon=ROOT / 'cadence'):
    runtime = lua_runtime(addon)
    runtime.execute(source.read(TP))
    runtime.execute(source.read(ERA_TP))
    tp = runtime.eval("require('core.tp')")
    delay = runtime.eval("require('core.delay')")
    native = runtime.globals().xi.combat.tp
    count = 0
    # Every formula boundary, extreme reduction and both fist/dual-wield paths are compared with Phoenix Lua.
    for units, weapon, reduction, stp in itertools.product(
            (1, 48, 96, 179, 180, 181, 449, 450, 451, 479, 480, 481, 529, 530, 531, 600, 999),
            ('single', 'dual', 'fists', 'bare', 'shield'), (0, 15, 50), (0, 25, 67)):
        h2h = weapon in ('fists', 'bare', 'shield')
        bare = weapon in ('bare', 'shield')
        base = 480 if bare else units + (240 if h2h else 0)
        if weapon == 'dual':
            base += 180
        for percent in (-30, 0, 20):
            mods = {'DUAL_WIELD': reduction, 'MARTIAL_ARTS': reduction * 4, 'DELAYP': percent, 'STORETP': stp}
            actor = runtime.globals().parity_actor(runtime.table_from({
                'base': base, 'dual': weapon == 'dual', 'h2h': h2h, 'shield': weapon == 'shield',
                'skilled': weapon != 'shield', 'mods': mods}, recursive=True))
            loadout = {'main_job': 2, 'main_level': 75, 'sub_job': 1, 'sub_level': 37,
                       'buffs': {}, 'sub_used': weapon == 'shield', 'modifiers': {
                           'dual_wield': reduction, 'martial_arts': reduction * 4,
                           'delay_percent': percent, 'store_tp': stp, 'tp_key': 'parity'}}
            if not bare:
                loadout['main'] = {'id': 1, 'skill': 1 if h2h else 3, 'delay': units}
            if weapon == 'dual':
                loadout['sub'] = {'id': 2, 'skill': 2, 'delay': 180}
            data = runtime.table_from(loadout, recursive=True)
            label = 'TP ' + str((units, weapon, reduction, stp, percent))
            same(delay.tp_delay(data), native.getModifiedDelayAndCanZanshin(actor, base).modifiedDelay, label + ' delay')
            same(tp.per_hit_for(data)[0], native.getSingleMeleeHitTPReturn(actor, False), label)
            count += 1
    return count


def check_recovery(source, addon=ROOT / 'cadence'):
    runtime = lua_runtime(addon)
    native = runtime.execute(source.read(HEALING)).onEffectTick
    modifiers = runtime.eval("require('core.modifiers')")
    count = 0
    for job, level, max_hp, signet, region in itertools.product((1, 3, 4, 16), (1, 10, 37, 75),
                                                               (299, 300, 900, 1500), (False, True), (0, 27, 28)):
        snapshot = {'main_job': job, 'main_level': level, 'sub_job': 3, 'sub_level': min(37, level // 2),
                    'equipment': {}, 'buffs': {253: True} if signet else {}, 'merits': {}, 'blue_spells': {},
                    'max_hp': max_hp, 'max_mp': 300, 'hp': 100, 'mp': 0, 'region': region, 'flags': {}}
        model = modifiers.calculate(runtime.table_from(snapshot, recursive=True))
        inputs = runtime.table_from({'level': level, 'max_hp': max_hp, 'region': region,
                                     'effects': {'SIGNET': signet}, 'mods': {'HPHEAL': model.hp_heal,
                                     'MPHEAL': model.mp_heal, 'CLEAR_MIND': model.clear_mind}}, recursive=True)
        for tick in (2, 3, 9, 20):
            hp, mp = runtime.globals().parity_heal(native, inputs, tick)
            same(model.hp_base + (tick - 2) * model.hp_step, hp, 'resting HP ' + str((job, level, max_hp, signet, region, tick)))
            same(model.mp_base + (tick - 2) * model.mp_step, mp, 'resting MP ' + str((job, level, tick)))
            count += 1
    return count


def delay_reference(case, reduction_cap):
    # Independent arithmetic for the guarded C++ GetWeaponDelay. Values are milliseconds.
    weapon = math.floor(case['main'] * 1000 / 60) + case['flat']
    if case['sub']:
        weapon += math.floor(case['sub'] * 1000 / 60)
    martial = math.floor(case['martial'] * 1000 / 60)
    if case['fists']:
        return math.floor(min(8000, max(1600, weapon - martial)) / 4)
    haste = [min(0.25, case['gear'] / 10000), min(0.4375, max(-1, case['magic'] / 10000)),
             min(0.25, max(-0.25, case['ability'] / 10000))]
    value = math.floor((weapon - martial) * (100 - case['dual']) / 100)
    value = math.floor(value * min(2, max(1 - reduction_cap, 1 - sum(haste))))
    value = math.floor(value * (100 + case['percent']) / 100)
    return min(weapon * 2, max(math.floor(weapon / 5), value))


def check_delay(addon=ROOT / 'cadence', reduction_cap=0.93):
    runtime = lua_runtime(addon)
    delay = runtime.eval("require('core.delay')")
    count = 0
    for main, style, haste, percent, fists in itertools.product((96, 180, 240, 366, 480, 600),
            ('single', 'dual', 'h2h'), ((0, 0, 0), (2500, 4375, 2500), (-3000, -7000, -1000),
                                     (5000, 6000, 3000), (1500, 1465, 0)), (-30, 0, 20), (False, True)):
        h2h = style == 'h2h'
        case = {'main': main + (240 if h2h else 0), 'sub': 180 if style == 'dual' else 0,
                'martial': 120 if h2h else 0, 'dual': 30 if style == 'dual' else 0,
                'flat': -100, 'percent': percent, 'gear': haste[0], 'magic': haste[1], 'ability': haste[2],
                'fists': fists}
        model = {'martial_arts': case['martial'], 'dual_wield': case['dual'], 'delay_flat': case['flat'],
                 'delay_percent': percent, 'haste_gear': haste[0], 'haste_magic': haste[1], 'haste_ability': haste[2]}
        loadout = {'main': {'id': 1, 'delay': main, 'skill': 1 if h2h else 3}, 'main_job': 2, 'main_level': 75,
                   'sub_job': 1, 'sub_level': 37, 'modifiers': model, 'buffs': {46: True} if fists else {}}
        if case['sub']:
            loadout['sub'] = {'id': 2, 'delay': case['sub'], 'skill': 2}
        actual = delay.estimate(runtime.table_from(loadout, recursive=True)) * 1000
        # The server uses float32 and Lua uses doubles. Three integer casts can differ by up to 3 ms.
        same(actual, delay_reference(case, reduction_cap), 'attack delay ' + str(case), tolerance=3.000001)
        count += 1
    return count


def check(source, addon=ROOT / 'cadence'):
    manifest = check_guards(source)
    counts = {'tp': check_tp(source, addon), 'recovery': check_recovery(source, addon),
              'delay': check_delay(addon, manifest['profile']['delay_reduction_cap'])}
    return counts
