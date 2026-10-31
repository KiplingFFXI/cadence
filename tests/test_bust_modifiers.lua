-- Bust carries a dynamic modifier subtype; its icon cannot identify the penalty.
local modifiers, resting = require('core.modifiers'), require('core.resting');
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local snapshot = { main_job = 17, main_level = 75, sub_job = 7, sub_level = 37,
    equipment = {}, buffs = {}, merits = {}, blue_spells = {},
    max_hp = 900, max_mp = 300, hp = 100, mp = 100, engaged = false, pet_present = false,
    region = 0, zone = 100, flags = {} };
local before = modifiers.calculate(snapshot);
snapshot.buffs[309] = true;
local model = modifiers.calculate(snapshot);
local fields = {};
for _, row in ipairs(model.unknown_sources) do
    if (row.id == 309) then fields[row.field] = true; end
end
check('Bust covers every tracked dynamic subtype from the pinned roll data', fields.accuracy
    and fields.store_tp and fields.double_attack and fields.refresh and fields.regen and fields.delay_percent);
check('an unidentified Bust cannot promise exact passive recovery or attack calculations', not model.refresh_known
    and not model.regen_known and not model.tp_known and not model.delay_known and not model.rounds_known);
check('Bust keeps known trait contributions without inventing a penalty', model.refresh == 1 and model.store_tp == 0
    and model.double_attack == 0 and model.delay_percent == 0);
check('the current source does not turn Healer Bust into a resting MP penalty', model.hp_known and model.mp_known
    and not fields.mp_heal and not fields.hp_heal);
check('Bust changes every affected learning key', model.resting_key ~= before.resting_key
    and model.delay_key ~= before.delay_key and model.tp_key ~= before.tp_key and model.rounds_key ~= before.rounds_key);

-- Evoker Bust (-1 REFRESH) cancels /PLD Auto Refresh (+1). No passive MP packets appear.
resting.reset(); resting.on_model(model); resting.on_vitals(-1, 100, 100, 0, 900, 300); resting.start(0);
for _, tick in ipairs({ { 21, 110, 112 }, { 30, 121, 125 }, { 42, 133, 139 } }) do
    resting.on_vitals(tick[1], tick[2], tick[3], 0, 900, 300);
end
local hp, mp, confidence = resting.next_gains();
local _, _, _, full = resting.until_each_full(42);
check('an uncertain passive subtraction cannot reject real resting ticks', resting.info(42).accepted == 3);
check('an uncertain passive remainder cannot replace known resting potency', hp == 13 and mp == 15
    and confidence.hp == 'known' and confidence.mp == 'known');
check('full times retain uncertainty while the passive penalty is unidentified', full.confidence == 'estimated'
    and full.hp_confidence == 'estimated' and full.mp_confidence == 'estimated');

-- Independent three-second observations can still resolve the net rate and teach resting potency.
resting.reset(); resting.on_model(model); resting.on_vitals(-1, 100, 100, 0, 900, 300); resting.start(0);
resting.on_vitals(3, 100, 102, 0, 900, 300); resting.on_vitals(6, 100, 104, 0, 900, 300); resting.update(6.6);
for _, tick in ipairs({ { 21, 110, 118 }, { 30, 121, 133 }, { 42, 133, 149 } }) do
    resting.on_vitals(tick[1], tick[2], tick[3], 0, 900, 300);
end
hp, mp, confidence = resting.next_gains();
check('observed passive MP remains usable despite the unidentified icon', resting.info(42).regen_mp == 2
    and mp == 15 and confidence.mp == 'observed');

resting.reset(); resting.on_model(model); resting.on_vitals(-1, 900, 100, 0, 900, 300); resting.start(0);
resting.on_vitals(3, 900, 112, 0, 900, 300);
check('uncertain MP-only recovery outside the resting window cannot establish a tick', resting.info(3).accepted == 0);
resting.on_vitals(21, 900, 124, 0, 900, 300);
check('MP-only recovery can tentatively establish the expected first tick', resting.info(21).accepted == 1);
resting.on_direct_change(21.2, false, true, false);
check('a late direct MP action still revokes tentative resting evidence', resting.info(21.2).accepted == 0
    and resting.info(21.2).next_tick == 21.4);

snapshot.buffs = {};
local restored = modifiers.calculate(snapshot);
check('removing Bust clears only its uncertainty', restored.refresh_known and restored.regen_known
    and restored.tp_known and restored.delay_known and restored.rounds_known
    and restored.resting_key == before.resting_key);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
