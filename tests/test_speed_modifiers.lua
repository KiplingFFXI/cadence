local modifiers = require('core.modifiers');
local delay = require('core.delay');
local data, effects = modifiers.data, modifiers.data.effect_ids;
local out, failed = {}, 0;
local function check(name, condition, detail)
    out[#out + 1] = (condition and 'ok   ' or 'FAIL ') .. name .. (detail and (' ' .. tostring(detail)) or '');
    if (not condition) then failed = failed + 1; end
end
local function player(job, level)
    return { main_job = job or 1, main_level = level or 75, sub_job = 0, sub_level = 0,
        equipment = {}, buffs = {}, buff_counts = {}, effects = {}, effect_epochs = {}, merits = {},
        max_hp = 900, max_mp = 300, hp = 450, mp = 150, tp = 0, engaged = false,
        pet_present = false, zone = 100, flags = {} };
end
local function loadout(model, skill)
    return { main = { id = 1, delay = 240, skill = skill or 3 }, main_job = 1, main_level = 75,
        sub_job = 0, sub_level = 0, buffs = {}, modifiers = model };
end
local function changed(a, b, field) return a[field] ~= b[field]; end

do
    local p = player();
    local base = modifiers.calculate(p);
    p.equipment[4] = { id = 15270 };
    local fast = modifiers.calculate(p);
    check('Walahra Turban adds five percent gear haste', fast.haste_gear == 500 and fast.delay_known);
    check('gear haste changes speed without TP or recovery reset', changed(base, fast, 'delay_key') and not changed(base, fast, 'tp_key') and not changed(base, fast, 'resting_key'));
    check('five percent haste shortens four seconds to3.8', delay.estimate(loadout(fast)) == 3.8);
    p.equipment[5] = { id = 14378 };
    local slow = modifiers.calculate(p);
    check('Hecatomb penalty subtracts from gear haste', slow.haste_gear == -800);
    check('net negative gear haste lengthens interval', delay.estimate(loadout(slow)) == 4.32);
    check('negative haste does not reduce TP per hit', delay.tp_delay(loadout(slow)) == 240);
    p.main_level = 72;
    local synced = modifiers.calculate(p);
    check('suppressed equipment does not retain negative haste under level sync', synced.haste_gear == 0);
    check('scaled accuracy remains uncertain', not synced.rounds_known);
end

do
    local m = { haste_magic = 0, haste_ability = 0, haste_gear = 5000 };
    check('gear haste caps at25 percent', delay.estimate(loadout(m)) == 3);
    m.haste_gear = -15000;
    check('combined slow cannot exceed double delay', delay.estimate(loadout(m)) == 8);
    m.haste_magic, m.haste_ability, m.haste_gear = 5000, 5000, 5000;
    check('all haste categories obey overall80 percent cap', delay.estimate(loadout(m)) == 0.8);
    m.haste_magic, m.haste_ability, m.haste_gear = 0, 0, 0;
    m.twohand_haste_ability = 1000;
    check('twohand haste does not affect onehand weapon', delay.estimate(loadout(m, 3)) == 4);
    check('twohand haste affects twohand weapon', delay.estimate(loadout(m, 12)) == 3.6);
end

do
    local p = player();
    p.equipment[0] = { id = 17590 };
    local before = modifiers.calculate(p);
    p.buffs[effects.food], p.food = true, { id = 4468 };
    local after = modifiers.calculate(p);
    check('Primate Staff food latent reduces delay by1383ms', after.delay_flat == -1383);
    check('Primate flat delay does not alter TP key', before.tp_key == after.tp_key);
    check('Primate flat delay uses milliseconds', delay.estimate(loadout(after)) == 2.617);
    check('Primate flat delay does not affect TP formula', delay.tp_delay(loadout(after)) == 240);
    p.food = { id = 4596 };
    check('alternative Primate foods do not stack', modifiers.calculate(p).delay_flat == -1383);
    p.food = nil;
    check('unknown food leaves conditional delay uncertain', not modifiers.calculate(p).delay_known);
    p = player();
    p.equipment[1] = { id = 19024 };
    after = modifiers.calculate(p);
    check('Sword Strap reduces delay bythree percent', after.delay_percent == -3 and delay.estimate(loadout(after)) == 3.88);
    check('Sword Strap also alters TP delay', delay.tp_delay(loadout(after)) == 232);
end

do
    local p = player();
    p.equipment[0] = { id = 16555, augments = { { id = 49, value = 2 }, { id = 50, value = 0 }, { id = 756, value = 9 } } };
    local r = modifiers.calculate(p);
    check('signed haste augments and flat delay decode', r.haste_gear == 200 and r.delay_flat == -10);
    p.equipment[0].augments = { { id = 115, value = 20 } };
    check('pet Store TP augment does not affect player', modifiers.calculate(p).store_tp == 0);
    p.equipment[0].augments_known = false;
    check('unsupported augment format keeps speed uncertain', not modifiers.calculate(p).delay_known);
end

do
    local p = player();
    p.equipment[10] = { id = 15290 };
    p.buffs[effects.haste], p.buff_counts[effects.haste] = true, 1;
    p.activated_items = { [15290] = { expires_at = 200 } };
    p.activated_item_effects_known = { [effects.haste] = true };
    p.now = 100;
    local r = modifiers.calculate(p);
    check('known Haste Belt does not double count spell haste icon', r.haste_magic == 1000 and r.delay_known);
    p.buff_counts[effects.haste] = 2;
    p.effects[effects.haste] = { haste_magic = 1465 };
    r = modifiers.calculate(p);
    check('separately known Haste spell stacks with Haste Belt', r.haste_magic == 2465 and r.delay_known);
    p.effects, p.activated_items, p.activated_item_effects_known = {}, {}, { [effects.haste] = false };
    p.buff_counts[effects.haste] = 1;
    r = modifiers.calculate(p);
    check('cold Haste icon remains uncertain', not r.delay_known and #r.unknown_sources > 0);
    p = player();
    p.buffs[effects.march], p.buff_counts[effects.march], p.effect_epochs[effects.march] = true, 2, 1;
    local first = modifiers.calculate(p);
    p.effect_epochs[effects.march] = 2;
    local refreshed = modifiers.calculate(p);
    check('two March icons inform starting estimate', first.haste_magic == 1200 and not first.delay_known);
    check('same-icon recast changes speed context only', changed(first, refreshed, 'delay_key') and not changed(first, refreshed, 'tp_key') and not changed(first, refreshed, 'resting_key'));
end

do
    local p = player(8);
    p.buffs[effects.last_resort] = true;
    p.merits[data.merit_ids.desperate_blows] = 3;
    local r = modifiers.calculate(p);
    check('era Desperate Blows adds onlythree500 merits', r.desperate_blows == 0 and r.twohand_haste_ability == 1500 and r.delay_known);
    p.main_level = 30;
    check('modern native Desperate Blows is removed by eraSQL', modifiers.calculate(p).twohand_haste_ability == 0);
    p = player();
    p.buffs[effects.spirit_surge] = true;
    r = modifiers.calculate(p);
    check('era Spirit Surge uses magic haste', r.haste_magic == 2500 and r.haste_ability == 0);
end

do
    local p = player();
    local base = modifiers.calculate(p);
    p.equipment[5] = { id = 13787 };
    local r = modifiers.calculate(p);
    check('Dalmatica contributes passive Refresh separately from hMP', r.refresh == 1 and r.mp_heal == 0 and r.passive_mp == 1);
    check('passive Refresh changes recovery only', changed(base, r, 'resting_key') and not changed(base, r, 'delay_key') and not changed(base, r, 'tp_key'));
    p.equipment[0] = { id = 16555, augment_mods = { [370] = -3, [369] = -3, [404] = 2, [405] = 1 } };
    r = modifiers.calculate(p);
    check('negative raw Regen and Refresh clamp before drains', r.passive_hp == -2 and r.passive_mp == -1);
    p.buffs[effects.regen], p.buffs[effects.refresh] = true, true;
    check('unknown active regeneration prevents exact net recovery claim', not modifiers.calculate(p).regen_known and not modifiers.calculate(p).refresh_known);
    p.effects = { [effects.regen] = { regen = 10 }, [effects.refresh] = { refresh = 3 } };
    r = modifiers.calculate(p);
    check('known passive effects combine with gear once', r.passive_hp == 5 and r.passive_mp == 0);
    p = player(15);
    check('known no-pet SMN needs no perpetuation guess', modifiers.calculate(p).refresh_known);
    p.pet_present = true;
    check('active unknown avatar makes net MP recovery uncertain', not modifiers.calculate(p).refresh_known);
    p.pet_id = 0;
    check('Fire Spirit id zero is an active pet', not modifiers.calculate(p).refresh_known);
end

do
    local p = player();
    p.buffs[effects.aftermath] = true;
    local r = modifiers.calculate(p);
    check('unidentified aftermath covers speed and recovery uncertainty', not r.delay_known and not r.regen_known and not r.refresh_known);
    p.effects[effects.aftermath] = { store_tp = 0, mods = { [384] = 1000 } };
    r = modifiers.calculate(p);
    check('proven Apocalypse aftermath supplies gear haste', r.haste_gear == 1000 and r.delay_known and r.tp_known);
    check('known contribution identifies effect and amount', (function()
        for _, row in ipairs(r.contributions) do if (row.kind == 'effect' and row.field == 'haste_gear' and row.value == 1000) then return true; end end
        return false;
    end)());
    p.effects[effects.aftermath] = { store_tp = 0, mods = { [370] = 10 } };
    check('proven Excalibur aftermath contributes passive Regen', modifiers.calculate(p).passive_hp == 10);
end

do
    local p = player();
    local initial = modifiers.calculate(p);
    p.equipment[0] = { id = 16555, augment_mods = { [25] = 10, [288] = 5 } };
    local r = modifiers.calculate(p);
    check('accuracy and multiattack change round forecast only', changed(initial, r, 'rounds_key') and not changed(initial, r, 'delay_key') and not changed(initial, r, 'tp_key') and not changed(initial, r, 'resting_key'));
    p.equipment[0].augment_mods = {};
    check('irrelevant equipment preserves model context', modifiers.calculate(p).rounds_key == initial.rounds_key);
end

check('full signed haste inventory is pinned', data.coverage[384].fixed == 2153 and data.coverage[384].negative == 37 and data.coverage[384].latents == 16);
check('flat delay inventory includes all seven latents and eight player augments', data.coverage[171].latents == 7 and data.coverage[171].augments == 8);
check('recovery inventory separates healing from passive gains', data.coverage[71].fixed == 120 and data.coverage[72].fixed == 47 and data.coverage[369].fixed == 180 and data.coverage[370].fixed == 96);
check('coverage explicitly retains era acquisition uncertainty', #data.coverage_notes.uncertain >= 4 and data.source.deployed_runtime_verified == false);
do
    local p = player();
    p.equipment[11], p.equipment[12] = { id = 16006 }, { id = 16006 };
    check('equipment sets count worn slots including duplicate eligible IDs', modifiers.calculate(p).hp_heal == 10);
    p = player();
    local before = modifiers.calculate(p);
    p.buffs[31] = true;
    local r = modifiers.calculate(p);
    check('unidentified Plague makes net MP recovery uncertain', not r.refresh_known and r.resting_key ~= before.resting_key);
    p.buffs, p.equipment = {}, { [0] = { id = 16555, augments_known = false, extra = 'private item extra' } };
    r = modifiers.calculate(p);
    check('uncertain item keys retain no raw Extra bytes', not r.tp_key:find('private item extra', 1, true));
    p = player();
    p.merits[data.merit_ids.double_attack] = 0;
    before = modifiers.calculate(p);
    p.merits[data.merit_ids.double_attack] = 5;
    r = modifiers.calculate(p);
    check('Double Attack merits change rounds only', r.double_attack == before.double_attack + 5 and r.rounds_key ~= before.rounds_key and r.tp_key == before.tp_key);
    p = player(12);
    p.merits[data.merit_ids.store_tp], p.merits[data.merit_ids.ikishoten] = 0, 0;
    before = modifiers.calculate(p);
    p.merits[data.merit_ids.ikishoten] = 3;
    r = modifiers.calculate(p);
    check('Ikishoten merit identity changes rounds without ordinary per-hit TP', r.rounds_key ~= before.rounds_key and r.tp_key == before.tp_key);
end
if (failed > 0) then out[#out + 1] = tostring(failed) .. ' FAILED'; end
return table.concat(out, '\n');
