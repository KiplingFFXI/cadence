"""Check Cadence's TP, resting, attack and action timing against reviewed Phoenix source."""
import csv
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
                r'EngageLockout|setEngageLockedUntil|m_engageLockedUntil|CheckLatentsWeaponDraw|OnDisengage|'
                r'canAct|LastSpellFinished|m_spellFinishedTime|OnCastFinished|MagicParalyzed|MagicIntimidated|'
                r'weapon_skills|animation_locks|animationTime|[` ]spell_list[` ]|item_usable|[` ]abilities[` ]|'
                r'setAnimation\(|setCastTime|castTime|untargetableAndUnactionable|'
                r'CItemState|CRangeState|CAbilityState|OnItemFinish|ITEM_START|ITEM_USE|ITEM_STATE_EXIT|'
                r'item_mods|item_latents|blue_spell_mods|blue_traits|traits|augments|merits')
FILES = [TP, ERA_TP, HEALING, 'src/map/ai/states/attack_state.cpp', 'src/map/map_constants.h',
         'src/map/utils/blueutils.cpp', 'scripts/effects/haste.lua', 'scripts/effects/slow.lua',
         'scripts/effects/elegy.lua', 'scripts/effects/march.lua', 'scripts/effects/hasso.lua',
         'scripts/effects/regen.lua', 'scripts/effects/refresh.lua',
         'scripts/globals/spells/enfeebling_spell.lua', 'scripts/globals/spells/enfeebling_song.lua',
         'modules/era/lua/actions/spells/spell_adjustments.lua', 'modules/era/data/merits.yaml',
         'modules/era/data/skills.yaml',
         'data/enums/mod.yaml', 'data/enums/latent.yaml', 'data/enums/weather.yaml',
         'data/merits.yaml', 'data/skills.yaml', 'data/status_effects.yaml', 'settings/default/main.lua',
         'scripts/globals/job_utils/corsair.lua', 'scripts/globals/job_utils/dark_knight.lua',
         'scripts/globals/job_utils/dragoon.lua', 'scripts/globals/job_utils/samurai.lua',
         'scripts/globals/job_utils/dancer.lua', 'scripts/globals/aftermath.lua',
         'scripts/globals/gear_sets.lua', 'scripts/globals/item_utils.lua',
         'scripts/enum/item.lua', 'data/weapon_skills.yaml', 'data/animation_locks.yaml', 'data/enums/region.yaml',
         'src/map/data/yaml/merge.cpp', 'src/map/data/datasets/weapon_skills/dataset.cpp',
         'src/map/data/datasets/weapon_skills/yaml.h', 'src/map/data/datasets/animation_locks/dataset.h',
         'src/map/data/datasets/animation_locks/dataset.cpp', 'src/map/data/datasets/animation_locks/yaml.h',
         'scripts/effects/food.lua', 'scripts/effects/samurai_roll.lua', 'scripts/effects/healers_roll.lua',
         'scripts/effects/store_tp.lua', 'scripts/effects/bust.lua', 'scripts/effects/inhibit_tp.lua',
         'scripts/effects/arcane_crest.lua', 'scripts/effects/dragon_breaker.lua', 'scripts/effects/sepulcher.lua',
         'scripts/effects/haste_samba_haste.lua', 'scripts/effects/hundred_fists.lua',
         'src/map/items/item_equipment.cpp', 'src/map/latent_effect_container.cpp',
         'src/map/utils/battleutils.cpp', 'src/map/utils/charutils.cpp',
         'src/map/utils/zoneutils.cpp', 'src/map/zone.h', 'src/common/vana_time.h',
         'src/map/packets/char_status.cpp', 'src/map/action/interrupts.cpp',
         'src/map/enums/msg_basic.h', 'src/map/enums/action/category.h',
         'sql/abilities.sql', 'src/map/ai/states/range_state.h', 'src/map/enums/four_cc.h',
         'scripts/globals/job_utils/ranger.lua', 'scripts/globals/job_utils/thief.lua',
         'scripts/globals/job_utils/rune_fencer.lua']
# Dispatch scripts can introduce a new helper or action lock without changing a SQL signature.
TREE_GUARDS = ('scripts/actions/abilities', 'scripts/actions/weaponskills', 'scripts/globals/job_utils')
FUNCTIONS = {
    'src/map/ai/ai_container.cpp': ['CAIContainer::Internal_Engage', 'CAIContainer::Internal_ChangeTarget',
                                  'CAIContainer::Internal_Disengage', 'CAIContainer::Tick',
                                  'CAIContainer::finishCurrentState', 'CAIContainer::CheckCompletedStates',
                                  'CAIContainer::Reset', 'CAIContainer::CanChangeState'],
    'src/map/ai/controllers/player_controller.cpp': ['CPlayerController::Engage', 'CPlayerController::setEngageLockedUntil',
                                                  'CPlayerController::Cast', 'CPlayerController::canAct',
                                                  'CPlayerController::getLastSpellFinishedTime',
                                                  'CPlayerController::setLastSpellFinishedTime'],
    'src/map/ai/states/magic_state.cpp': ['CMagicState::Update', 'CMagicState::CanChangeState'],
    'src/map/ai/states/weaponskill_state.cpp': ['CWeaponSkillState::Update', 'CWeaponSkillState::CanChangeState'],
    'src/map/ai/states/range_state.cpp': ['CRangeState::CanUseRangedAttack', 'CRangeState::init',
                                        'CRangeState::Update', 'CRangeState::CanChangeState'],
    'src/map/ai/states/ability_state.cpp': ['CAbilityState::init', 'CAbilityState::Update',
                                          'CAbilityState::CanChangeState', 'CAbilityState::Cleanup'],
    'src/map/ai/states/item_state.cpp': ['CItemState::init', 'CItemState::Update', 'CItemState::Cleanup',
                                       'CItemState::CanChangeState', 'CItemState::TryInterrupt', 'CItemState::FinishItem'],
    'src/map/ai/states/inactive_state.cpp': ['CInactiveState::init', 'CInactiveState::Update', 'CInactiveState::CanChangeState'],
    'src/map/entities/battle_entity.cpp': ['CBattleEntity::GetWeaponDelay', 'CBattleEntity::OnDisengage',
                                          'CBattleEntity::OnWeaponSkillFinished'],
    'src/map/entities/char_entity.cpp': ['CCharEntity::OnDisengage', 'CCharEntity::OnCastFinished',
                                       'CCharEntity::OnAbility', 'CCharEntity::OnItemFinish', 'CCharEntity::OnWeaponSkillFinished'],
    'src/map/items/item_weapon.cpp': ['CItemWeapon::setDelay'],
    'src/map/status_effect_container.cpp': ['CStatusEffectContainer::TickEffects', 'CStatusEffectContainer::TickRegen'],
    'src/map/weapon_skill.cpp': ['CWeaponSkill::getAnimationTime', 'CWeaponSkill::setAnimationTime'],
    'src/map/items/item_usable.cpp': ['CItemUsable::getAnimationTime', 'CItemUsable::setAnimationTime',
                                     'CItemUsable::getActivationTime', 'CItemUsable::setActivationTime'],
    'src/map/utils/itemutils.cpp': ['LoadItemList'],
    'src/map/spell.cpp': ['LoadSpellList', 'CSpell::getCastTime', 'CSpell::setCastTime'],
    'src/map/ability.cpp': ['LoadAbilitiesList'],
    'src/map/action/action.cpp': ['action_t::normalize'],
    'src/map/packets/s2c/0x028_battle2.cpp': ['GP_SERV_COMMAND_BATTLE2::pack'],
    'src/map/lua/lua_base_entity.cpp': ['CLuaBaseEntity::untargetableAndUnactionable'],
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

    def tree_digest(self, path):
        return self.git('rev-parse', self.ref + ':' + path).strip()

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


def loaded_gitlinks(source):
    """Read enabled submodule revisions from Git objects without checking out private content."""
    entries = module_entries(source)
    links = {}
    for row in source.git('ls-tree', '-rz', source.ref, '--', 'modules').split('\0'):
        if not row:
            continue
        metadata, path = row.split('\t', 1)
        mode, kind, revision = metadata.split()
        if mode == '160000' and kind == 'commit' and any(
                path == entry or path.startswith(entry + '/') or entry.startswith(path + '/') for entry in entries):
            links[path] = revision
    return links


def observed_guards(source):
    result = {path: file_fingerprint(source, path) for path in FILES}
    result.update({path + ':tree': source.tree_digest(path) for path in TREE_GUARDS})
    result.update({path + ':gitlink': revision for path, revision in loaded_gitlinks(source).items()})
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
    spell_recovery_reference(source)
    # Quarantine and accepted duration rules also apply before a refresh can decide it is unchanged.
    from generate_recovery import build
    build(source)
    return manifest


def lua_runtime(addon=ROOT / 'cadence'):
    runtime = luajit21.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute('package.path = [[%s/?.lua;]] .. package.path' % str(addon).replace('\\', '/'))
    runtime.execute("""
        local function names() return setmetatable({}, {__index=function(_, key) return key end}); end
        xi = {combat={tp={}},mod=names(),effect=names(),merit=names(),slot=names(),skill=names(),job=names(),
              objType=names(),region={LIMBUS=27,RONFAURE_FRONT=33,VALDEAUNIA_FRONT=40},
              settings={main={HEALING_TP_CHANGE=-100}},expansion={SOA=10},pre=function() return true end};
        package.preload['modules/module_utils'] = function() return true end;
        package.preload['scripts/quests/adoulin/Dances_with_Luopans'] = function() return true end;
        Module={new=function() return {addOverride=function(_,name,fn)
            assert(name == 'xi.combat.tp.calculateTPReturn'); xi.combat.tp.calculateTPReturn=fn;
        end} end};
        parity_actor=function(c)
            return {isDualWielding=function() return c.dual end, isUsingH2H=function() return c.h2h end,
                getObjType=function() return 'PC' end, getMainJob=function() return c.main_job or xi.job.WAR end,
                getEquippedItem=function() return c.shield and {} or nil end,
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


def check_reengage(source, addon=ROOT / 'cadence'):
    text = source.read('src/map/ai/states/attack_state.cpp')
    constants = {}
    for name in ('kEngageDelay', 'kEngageCooldown'):
        match = re.search(r'\b' + name + r'\s*=\s*(\d+(?:\.\d+)?)(ms|s)\s*;', text)
        if not match:
            raise RuntimeError('Source review required for re-engage constant ' + name)
        constants[name] = float(match[1]) / (1000 if match[2] == 'ms' else 1)

    runtime = lua_runtime(addon)
    attack = runtime.eval("require('core.attack')")
    count = 0
    # Incoming status cannot prove the departure cause. The HUD uses the guarded formula's upper bound.
    for interval in (0.1, 1.499, 1.5, 3, 4.499, 4.5, 4.501, 8, 16, 30):
        attack.reset()
        attack.engage(0, interval, 'reengage-parity', False, interval)
        attack.disengage(1, True)
        view = attack.reengage_progress(1)
        expected = max(constants['kEngageCooldown'], interval - constants['kEngageDelay'])
        same(view.duration, expected, 're-engage delay ' + str(interval), tolerance=1e-9)
        same(view.left, expected, 're-engage countdown ' + str(interval), tolerance=1e-9)
        count += 1
    return count


def animation_rows(source, table, id_column):
    text = source.read('sql/' + table + '.sql')
    schema = re.search(r'CREATE TABLE `' + re.escape(table) + r'` \((.*?)\) ENGINE=', text, re.S)
    columns = re.findall(r'^\s*`([^`]+)`', schema[1], re.M) if schema else []
    if 'animationTime' not in columns or id_column not in columns:
        raise RuntimeError('Source review required for ' + table + ' animation columns.')
    ids = set()
    for line in text.splitlines():
        if not re.match(r'\s*(?:INSERT|REPLACE|UPDATE|DELETE)\b', line, re.I):
            continue
        match = re.fullmatch(r'\s*INSERT INTO `' + re.escape(table) + r'` VALUES\s*\((.*)\);\s*(?:--.*)?', line)
        if not match:
            raise RuntimeError('Source review required for ' + table + ' animation rows.')
        try:
            row = next(csv.reader([match[1]], quotechar="'", escapechar='\\', skipinitialspace=True, strict=True))
            if len(row) != len(columns):
                raise ValueError('column count')
            action_id = int(row[columns.index(id_column)])
            seconds = int(row[columns.index('animationTime')]) / 1000
        except (csv.Error, ValueError) as error:
            raise RuntimeError('Source review required for ' + table + ' animation values.') from error
        if action_id in ids or seconds < 0:
            raise RuntimeError('Source review required for ' + table + ' animation values.')
        ids.add(action_id)
        yield action_id, seconds
    if not ids:
        raise RuntimeError('Source review required: no ' + table + ' animation rows.')


def spell_recovery_reference(source):
    gate = function_body(source.read('src/map/ai/controllers/player_controller.cpp'), 'CPlayerController::canAct')
    match = re.search(r'return\s+timeSinceLastSpell\s*>\s*(\d+(?:\.\d+)?)(ms|s)\s*;', gate)
    if not match:
        raise RuntimeError('Source review required for the spell recovery gate.')
    spell_seconds = float(match[1]) / (1000 if match[2] == 'ms' else 1)
    count = 0
    # Also checked before an automatic refresh decides there are no relevant data changes.
    for spell_id, seconds in animation_rows(source, 'spell_list', 'spellid'):
        if spell_id < 768:
            if seconds > spell_seconds:
                raise RuntimeError('Source review required for spell animation exceeding recovery gate: ' + str(spell_id))
            count += 1
    if not count:
        raise RuntimeError('Source review required: no supported spell animation rows.')
    return spell_seconds, count


def check_action_recovery(source, addon=ROOT / 'cadence'):
    spell_seconds, spells = spell_recovery_reference(source)
    runtime = lua_runtime(addon)
    recovery = runtime.eval("require('core.recovery')")
    recovery.reset()
    recovery.on_spell(0, 1)
    view = recovery.progress(0)
    same(view.duration, spell_seconds, 'spell recovery duration')
    same(view.left, spell_seconds, 'spell recovery countdown')
    count = 1 + spells
    from generate_recovery import build
    expected = build(source)
    for skill_id, seconds in expected['weaponskill_seconds'].items():
        recovery.reset()
        recovery.on_weaponskill(0, skill_id)
        view = recovery.progress(0)
        if seconds > 0:
            same(view.duration, seconds, 'weapon skill recovery duration ' + str(skill_id))
            same(view.left, seconds, 'weapon skill recovery countdown ' + str(skill_id))
        count += 1
    actual = runtime.eval("require('data.phoenix_recovery')")

    def constants(value):
        if luajit21.lua_type(value) == 'table':
            return {key: constants(item) for key, item in value.items()}
        return value

    for key, value in expected.items():
        if constants(actual[key]) != value:
            raise RuntimeError('Source parity failed for action recovery data: ' + key)
    for id, animations in expected['weaponskills'].items():
        seconds = expected['weaponskill_seconds'][id]
        ability = expected['abilities'].get(id, {})
        for animation in animations:
            ambiguous = ability.get('category') == 3 and animation in ability.get('animations', {})
            wanted = ('unknown', None, 'unknown') if ambiguous else (
                'weaponskill', seconds, 'timed' if seconds > 0 else 'none')
            if recovery.classify(3, id, animation) != wanted:
                raise RuntimeError('Source parity failed for weapon skill signature: ' + str(id))
            count += 1
    for id, seconds in expected['spell_attack_seconds'].items():
        if recovery.classify(4, id, 0) != ('spell', max(spell_seconds, seconds), 'timed'):
            raise RuntimeError('Source parity failed for spell recovery: ' + str(id))
        count += 1
    match = re.search(r'm_returnWeaponDelay\s*=\s*(\d+)ms', source.read('src/map/ai/states/range_state.h'))
    if not match:
        raise RuntimeError('Source review required for ranged recovery duration.')
    same(recovery.classify(2, 0, 0)[1], int(match[1]) / 1000, 'ranged recovery duration')
    count += 1
    for id, row in expected['abilities'].items():
        for animation in row['animations']:
            ambiguous = row['category'] == 3 and animation in expected['weaponskills'].get(id, {})
            wanted = ('unknown', None, 'unknown') if ambiguous else (
                row['kind'], row['seconds'], 'timed' if row['seconds'] > 0 else 'none')
            if recovery.classify(row['category'], id, animation) != wanted:
                raise RuntimeError('Source parity failed for ability signature: ' + str(id))
            count += 1
    for id, seconds in expected['items'].items():
        if recovery.classify(5, id, 0) != ('item', seconds, 'timed' if seconds > 0 else 'none'):
            raise RuntimeError('Source parity failed for item recovery: ' + str(id))
        count += 1
    for id in expected['quarantined_items']:
        if recovery.classify(5, id, 0) != ('item', None, 'unknown'):
            raise RuntimeError('Source parity failed for quarantined item: ' + str(id))
        count += 1
    count += len(expected['spell_casts'])
    return count


def check(source, addon=ROOT / 'cadence'):
    manifest = check_guards(source)
    counts = {'tp': check_tp(source, addon), 'recovery': check_recovery(source, addon),
              'delay': check_delay(addon, manifest['profile']['delay_reduction_cap']),
              'reengage': check_reengage(source, addon),
              'action_recovery': check_action_recovery(source, addon)}
    return counts
