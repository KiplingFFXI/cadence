-- Known modifiers seed TP, then observations replace the estimate without counting them twice.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end
local tp = require('core.tp');
local delay = require('core.delay');
local attack = require('core.attack');
local loadout = { main = { id = 1, delay = 450, skill = 8 }, sub = nil, sub_used = false,
    main_job = 12, main_level = 75, sub_job = 1, sub_level = 37, buffs = {},
    modifiers = { store_tp = 46, martial_arts = 0, dual_wield = 0, delay_percent = 0, tp_key = '46' } };

tp.on_engage(loadout);
check('450 delay and 46 Store TP gives 167', tp.per_hit() == 167, tp.per_hit());
check('six normal hits cross 1000', 6 * tp.per_hit() == 1002);
loadout.modifiers.store_tp, loadout.modifiers.tp_key = 45, '45';
tp.on_loadout(loadout);
check('one less Store TP misses the six-hit threshold', tp.per_hit() == 166 and 6 * tp.per_hit() == 996);
loadout.modifiers.store_tp, loadout.modifiers.tp_key = -6, '-6';
tp.on_loadout(loadout);
check('negative Store TP is kept', tp.per_hit() == 108, tp.per_hit());
loadout.modifiers.store_tp, loadout.modifiers.tp_key = 46, '46';
tp.on_loadout(loadout);
tp.on_vitals(0, 0);
tp.on_round(8, 1, false, true, loadout);
tp.on_vitals(8.1, 170);
tp.on_round(16, 1, false, true, loadout);
tp.on_vitals(16.1, 340);
check('observed 170 replaces the modeled 167', tp.per_hit() == 170 and select(2, tp.per_hit()));
local learned_key = delay.key(loadout);
loadout.modifiers = { store_tp = 46, martial_arts = 0, dual_wield = 0, delay_percent = 0, tp_key = '46' };
tp.on_loadout(loadout);
check('an unrelated change keeps observed TP', tp.per_hit() == 170 and select(2, tp.per_hit()));
check('an unrelated change keeps the delay key', delay.key(loadout) == learned_key);

-- An equipment notification can precede the memory update. Discard that batch, not good history.
tp.on_round(24, 1, false, true, loadout);
loadout.modifiers.transition = true;
tp.on_loadout(loadout);
tp.on_vitals(24.1, 507);
check('a crossing packet cannot replace observed TP', tp.per_hit() == 170 and select(2, tp.per_hit()));
loadout.modifiers.transition = false;
tp.on_loadout(loadout);
check('an irrelevant settled swap keeps observations', tp.per_hit() == 170);
loadout.modifiers.store_tp, loadout.modifiers.tp_key = 50, '50';
tp.on_loadout(loadout);
check('armor alone updates the estimate immediately', tp.per_hit() == 172 and not select(2, tp.per_hit()));
check('Store TP alone does not change attack timing', delay.key(loadout) == learned_key);

loadout.buffs[54] = true;
tp.on_loadout(loadout);
check('Meikyo Shisui predicts no normal-hit TP', tp.per_hit() == 0 and tp.rounds_to(1000, 0) == nil);
loadout.buffs[54] = nil;
check('out-of-combat estimate uses current Meikyo state', tp.per_hit_for(loadout) == 172);
tp.on_loadout(loadout);
check('normal-hit TP returns after Meikyo Shisui', tp.per_hit() == 172);

local dual = { main = { id = 2, delay = 240, skill = 3 }, sub = { id = 3, delay = 210, skill = 3 },
    sub_used = true, main_job = 13, main_level = 75, sub_job = 1, sub_level = 37, buffs = {},
    modifiers = { store_tp = 0, dual_wield = 35, martial_arts = 0, delay_percent = -3, tp_key = 'dual' } };
check('DW and delay gear apply before the single floor', delay.tp_delay(dual) == 141, delay.tp_delay(dual));
local haste_free = delay.tp_delay(dual);
dual.buffs[33] = true;
check('Haste does not change TP delay', delay.tp_delay(dual) == haste_free);
dual.modifiers.delay_percent = -30;
check('TP delay percentage reduction caps at 15 percent', delay.tp_delay(dual) == 124, delay.tp_delay(dual));
local fists = { main = nil, sub = nil, sub_used = false, main_job = 2, main_level = 75,
    sub_job = 1, sub_level = 37, buffs = {}, modifiers = { martial_arts = 200, delay_percent = 0 } };
check('Martial Arts equipment affects each fist TP delay', delay.tp_delay(fists) == 140, delay.tp_delay(fists));
fists.sub_used = true;
check('the occupied-sub exception uses one attack', delay.tp_delay(fists) == 280, delay.tp_delay(fists));

-- Changing the model never restarts the attack clock already counting down.
attack.engage(100, delay.estimate(loadout), delay.key(loadout));
local _, left_before = attack.progress(101);
loadout.modifiers.store_tp, loadout.modifiers.tp_key = 55, '55';
tp.on_loadout(loadout);
local _, left_after = attack.progress(101);
check('the current countdown is preserved', left_before == left_after);

table.insert(out, fails == 0 and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
