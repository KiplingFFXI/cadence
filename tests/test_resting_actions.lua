local resting = require('core.resting');
local out, failed = {}, 0;
local function check(name, ok, value)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (value ~= nil and (' ' .. tostring(value)) or '');
    if (not ok) then failed = failed + 1; end
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 0.001; end
local function sit(hp, mp, maximum_hp, maximum_mp, extra)
    resting.reset(); resting.on_buffs(0, {});
    resting.on_vitals(-1, hp, mp, 100, maximum_hp, maximum_mp);
    local model = { resting_key = 'actions', hp_base = 10, hp_step = 1, mp_base = 12, mp_step = 1,
        hp_known = true, mp_known = true, regen_known = true, refresh_known = true };
    for key, value in pairs(extra or {}) do model[key] = value; end
    resting.on_model(model); resting.start(0);
end
local function vitals(now, hp, mp, maximum_hp, maximum_mp, tp)
    resting.on_vitals(now, hp, mp, tp or 100, maximum_hp or 1000, maximum_mp or 1000);
end

sit(100, 0, 1000, 0);
vitals(5, 190, 0, 1000, 0); vitals(10, 280, 0, 1000, 0); resting.update(10.6);
local goal = resting.goal_progress(10, 'hp', 'amount', 500);
check('equal cures five seconds apart do not teach Regen', resting.info(10).regen_hp == 0);
check('direct-heal reproduction retains the modeled goal', near(goal.seconds, 141.4) and goal.ticks == 14);

sit(100, 0, 1000, 0);
resting.on_direct_change(3, true, false, false); vitals(3.1, 190, 0, 1000, 0);
resting.on_direct_change(6, true, false, false); vitals(6.1, 280, 0, 1000, 0); resting.update(6.7);
check('equal cures on the three-second grid cannot teach Regen', resting.info(6.7).regen_hp == 0);
check('rejected direct heals preserve the initial countdown', resting.info(6.7).next_tick == 21.4 and resting.info(6.7).accepted == 0);

sit(100, 0, 1000, 0);
vitals(3, 190, 0, 1000, 0); resting.on_direct_change(3.1, true, false, false);
vitals(6, 280, 0, 1000, 0);
check('a new passive candidate is not immediately certain', resting.info(6).regen_hp == 0);
resting.on_direct_change(6.1, true, false, false); resting.update(6.6);
check('cure actions arriving after vitals cancel pending passive learning', resting.info(6.6).regen_hp == 0);

sit(100, 100, 1000, 1000);
vitals(3, 105, 102); vitals(6, 110, 104);
check('matching real passes wait for the action window', resting.info(6).regen_hp == 0 and resting.info(6).regen_mp == 0);
resting.update(6.6);
check('valid three-second Regen and Refresh are learned together', resting.info(6.6).regen_hp == 5 and resting.info(6.6).regen_mp == 2);
resting.on_direct_change(9, true, false, false); vitals(9.1, 200, 106);
vitals(12.1, 205, 108); resting.update(12.7);
check('a cure leaves established Regen and independent Refresh intact', resting.info(12.7).regen_hp == 5 and resting.info(12.7).regen_mp == 2);

sit(100, 100, 1000, 1000);
vitals(3, 100, 98); vitals(6, 100, 96); resting.update(6.6);
check('negative three-second MP changes still teach a drain', resting.info(6.6).regen_mp == -2);
vitals(21, 110, 106);
check('a simultaneous drain is removed before learning resting potency', select(2, resting.next_gains()) == 13);

sit(985, 5, 1000, 10);
vitals(3, 990, 3, 1000, 10); vitals(6, 995, 1, 1000, 10); resting.update(6.6);
check('uncapped rates can be observed before reaching a boundary', resting.info(6.6).regen_hp == 5 and resting.info(6.6).regen_mp == -2);
vitals(9, 1000, 0, 1000, 10); resting.update(9.6);
check('capped gains and drained-to-zero MP do not replace full rates', resting.info(9.6).regen_hp == 5 and resting.info(9.6).regen_mp == -2);

sit(989, 0, 1000, 0);
vitals(3, 995, 0, 1000, 0); vitals(6, 1000, 0, 1000, 0); resting.update(6.6);
check('a capped second passive gain cannot establish a rate', resting.info(6.6).regen_hp == 0);

sit(100, 100, 1000, 1000);
resting.on_direct_change(20.9, true, false, false); vitals(21, 200, 112);
local next_hp, next_mp, confidence = resting.next_gains();
check('MP still establishes a real tick coincident with a cure', resting.info(21).accepted == 1 and resting.info(21).next_tick == 30);
check('coincident cure HP is excluded while clean MP learns', next_hp == 11 and confidence.hp == 'known' and next_mp == 13 and confidence.mp == 'observed');
vitals(30, 211, 125);
check('clean recovery learns normally after the coincident cure', resting.next_gains() == 12 and select(2, resting.next_gains()) == 14);

sit(100, 100, 1000, 1000);
vitals(21, 200, 112); resting.on_direct_change(21.1, true, false, false);
next_hp, next_mp, confidence = resting.next_gains();
check('a late cure action removes its contaminated HP sample', next_hp == 11 and confidence.hp == 'known');
check('a late cure preserves the independent MP tick and countdown', next_mp == 13 and resting.info(21.1).accepted == 1 and resting.info(21.1).next_tick == 30);

sit(100, 100, 1000, 1000);
vitals(21, 110, 137); resting.on_direct_change(21.1, false, true, false);
next_hp, next_mp, confidence = resting.next_gains();
check('a late MP transfer leaves independent HP timing and potency intact', next_hp == 11 and confidence.hp == 'observed'
    and next_mp == 13 and confidence.mp == 'known' and resting.info(21.1).accepted == 1);

sit(100, 0, 1000, 0);
vitals(21, 110, 0, 1000, 0); resting.on_direct_change(21.1, false, true, true);
check('an action affecting unchanged resources cannot revoke the HP tick', resting.info(21.1).accepted == 1
    and resting.info(21.1).next_tick == 30);

sit(100, 0, 1000, 0);
vitals(21, 190, 0, 1000, 0); resting.on_direct_change(21.1, true, false, false);
check('late cure-only evidence cannot move the resting clock', resting.info(21.1).accepted == 0 and resting.info(21.1).next_tick == 21.4);
check('late cure-only evidence cannot establish resting potency', resting.next_gains() == 10);

sit(100, 0, 1000, 0);
vitals(21, 190, 0, 1000, 0); vitals(21.05, 190, 0, 1000, 0);
resting.on_direct_change(21.1, true, false, false);
check('duplicate vitals cannot hide a late cure from the timing rollback', resting.info(21.1).accepted == 0
    and resting.info(21.1).next_tick == 21.4 and resting.next_gains() == 10);

sit(100, 100, 1000, 1000);
vitals(21, 200, 112); vitals(21.05, 200, 112);
resting.on_direct_change(21.1, true, false, false);
next_hp, next_mp, confidence = resting.next_gains();
check('duplicate vitals retain independent MP evidence during late cure attribution', next_hp == 11
    and confidence.hp == 'known' and next_mp == 13 and confidence.mp == 'observed'
    and resting.info(21.1).accepted == 1 and resting.info(21.1).next_tick == 30);

sit(100, 100, 1000, 1000);
resting.on_direct_change(21, false, true, true); vitals(21.1, 100, 125, 1000, 1000, 0);
check('direct MP restoration and TP drain are not a resting tick', resting.info(21.1).accepted == 0 and resting.info(21.1).next_tick == 21.4);
vitals(24, 100, 127, 1000, 1000, 0); vitals(27, 100, 129, 1000, 1000, 0); resting.update(27.6);
check('expired action exclusions allow later clean passive observations', resting.info(27.6).regen_mp == 2);

sit(100, 100, 1000, 1000);
resting.on_buffs(0, { [8] = true });
vitals(3, 190, 100); resting.on_direct_change(3.1, true, false, false); resting.on_buffs(3.2, { [8] = true });
vitals(6, 280, 100); resting.on_direct_change(6.1, true, false, false); resting.on_buffs(6.2, { [8] = true }); resting.update(6.8);
check('held changes under disease honor late direct-heal actions', resting.info(6.8).regen_hp == 0);

sit(100, 100, 1000, 1000);
vitals(3, 105, 100); vitals(4, 105, 101); vitals(6, 110, 101); resting.update(6.6);
check('unrelated MP packets do not break the HP pass sequence', resting.info(6.6).regen_hp == 5);
resting.on_direct_change(7, true, true, true); resting.stop(); resting.start(7.1);
vitals(10.1, 115, 102); vitals(13.1, 120, 103); resting.update(13.7);
check('a new rest clears old direct-action exclusions', resting.info(13.7).regen_hp == 5);

if (failed > 0) then out[#out + 1] = tostring(failed) .. ' FAILED'; end
return table.concat(out, '\n');
