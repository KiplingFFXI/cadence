-- TP per hit and landed hits per round have different reset boundaries.
local tp = require('core.tp');
local out, fails = {}, 0;
local function check(name, value)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name;
    if (not value) then fails = fails + 1; end
end
local loadout = { main = { id = 1, delay = 450, skill = 10 }, sub_job = 1, sub_level = 37,
    main_job = 12, main_level = 75, buffs = {}, modifiers = { store_tp = 46, tp_known = true,
        tp_key = '46', rounds_key = 'accuracy-a', dual_wield = 0, martial_arts = 0, delay_percent = 0 } };
tp.forget(); tp.on_zone(); tp.on_engage(loadout); tp.on_target(1); tp.on_vitals(0, 0);
for i = 1, 3 do
    tp.on_round(i * 8, 1, false, true, loadout);
    tp.on_vitals(i * 8 + 0.1, i * 167);
end
check('ordinary gains establish167 without adding Store TP twice', tp.per_hit() == 167 and select(2, tp.per_hit()));
check('successful-hit targets use current TP and requested goal', tp.hits_to(1000, 0) == 6 and tp.hits_to(2000, 1000) == 6 and tp.hits_to(3000, 2500) == 3);
check('at the goal no successful hits remain', tp.hits_to(2000, 2000) == 0);
local before = tp.info(25);
check('evidence includes clean samples and measured rounds', before.samples == 3 and before.recent_rounds == 3 and before.source == 'observed');
tp.on_target(2);
check('new target resets hit-rate evidence only', tp.info(25).recent_rounds == 0 and tp.per_hit() == 167 and select(2, tp.per_hit()));
check('known hit count stays known while rounds relearn', not tp.hits_estimated() and tp.is_estimated());
tp.on_round(32, 1, false, true, loadout); tp.on_vitals(32.1, 668);
loadout.modifiers.rounds_key = 'accuracy-b'; tp.on_loadout(loadout);
check('accuracy gear resets rounds without losing TP per hit', tp.info(33).recent_rounds == 0 and select(2, tp.per_hit()));
tp.on_round(40, 1, false, true, loadout); tp.on_vitals(40.1, 835);
loadout.modifiers.delay_key = 'new-haste'; tp.on_loadout(loadout);
check('haste-only changes keep hit and TP evidence', tp.info(41).recent_rounds == 1 and select(2, tp.per_hit()));
loadout.modifiers.store_tp, loadout.modifiers.tp_key = 45, '45'; tp.on_loadout(loadout);
check('Store TP changes keep hit-rate evidence but update TP', tp.info(41).recent_rounds == 1 and tp.per_hit() == 166 and not select(2, tp.per_hit()));
loadout.buffs[54] = true; tp.on_loadout(loadout);
check('Meikyo normal hits cannot reach the goal', tp.hits_to(1000, 0) == nil);
loadout.buffs[54] = nil; loadout.modifiers.transition = true; tp.on_loadout(loadout);
check('transition is visibly estimated', tp.is_estimated());
tp.on_round(48, 1, false, true, loadout);
check('rejected sample has a useful reason', tp.info(48).last_rejection == 'equipment or effect changing');

do
    local modifiers = require('core.modifiers');
    local snapshot = { main_job = 16, main_level = 75, sub_job = 0, sub_level = 0,
        equipment = {}, buffs = {}, merits = {}, blue_spells = {}, blue_spells_known = true,
        max_hp = 900, max_mp = 300, region = 0, flags = {} };
    local blue_loadout = { main = { id = 1, delay = 450, skill = 10 }, main_job = 16, main_level = 75,
        sub_job = 0, sub_level = 0, buffs = {}, modifiers = modifiers.calculate(snapshot) };
    tp.forget(); tp.on_zone(); tp.on_engage(blue_loadout); tp.on_target(1); tp.on_vitals(60, 0);
    for i = 1, 3 do
        tp.on_round(60 + i * 8, 1, false, true, blue_loadout);
        tp.on_vitals(60.1 + i * 8, i * 115);
    end
    check('BLU can establish observed TP and round evidence', tp.per_hit() == 115 and select(2, tp.per_hit())
        and tp.info(85).recent_rounds == 3);
    snapshot.blue_spells = { 532 };
    blue_loadout.modifiers = modifiers.calculate(snapshot);
    tp.on_loadout(blue_loadout);
    check('setting a direct DEX spell resets rounds but preserves learned TP per hit', tp.info(85).recent_rounds == 0
        and tp.per_hit() == 115 and select(2, tp.per_hit()));
end
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
