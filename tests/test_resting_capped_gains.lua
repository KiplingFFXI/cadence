-- Final capped recovery still establishes tick timing without teaching a truncated potency.
local resting = require('core.resting');
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local function sit(hp, mp, hp_max, mp_max, regen, refresh)
    resting.reset();
    resting.on_model({ resting_key = 'capped', hp_base = 10, hp_step = 1, hp_known = true,
        mp_base = 12, mp_step = 1, mp_known = true, regen = regen or 0, refresh = refresh or 0,
        regen_known = true, refresh_known = true });
    resting.on_vitals(-1, hp, mp, 958, hp_max, mp_max);
    resting.start(0);
end

-- The captured HP-only rest restored its last eight HP 23.084 seconds after the observed sit.
sit(71, 0, 79, 0);
resting.on_vitals(23.084, 79, 0, 958, 79, 0);
local info = resting.info(23.084);
local _, _, ticks, gained_hp = resting.progress(23.084);
check('the capped final HP gain records one actual tick', info.accepted == 1 and ticks == 1 and gained_hp == 8);
check('fullness stays correct without learning eight as the resting potency', resting.is_full()
    and info.gain_confidence.hp_uncapped == 11 and info.gain_confidence.hp == 'known');
resting.on_vitals(23.2, 79, 0, 958, 79, 0);
check('a duplicate full snapshot cannot add a second tick', resting.info(23.2).accepted == 1);

sit(900, 295, 900, 300);
resting.on_vitals(21, 900, 300, 958, 900, 300);
info = resting.info(21);
check('a final MP gain below twelve records timing independently of HP', info.accepted == 1
    and info.gain_confidence.mp_uncapped == 13 and info.gain_confidence.mp == 'known');
sit(898, 297, 900, 300);
resting.on_vitals(21, 900, 300, 958, 900, 300);
check('both capped resources still count only one recovery tick', resting.info(21).accepted == 1);
sit(71, 100, 79, 300); resting.on_vitals(21, 79, 100, 958, 79, 300);
check('known missing MP still disproves an HP-only small gain', resting.info(21).accepted == 0);
sit(71, 100, 79, 300); resting.on_vitals(21, 79, 130, 958, 79, 300);
resting.on_direct_change(21.2, false, true, false);
check('independent capped HP timing survives a late direct MP action', resting.info(21.2).accepted == 1);
sit(100, 295, 900, 300); resting.on_vitals(21, 130, 300, 958, 900, 300);
resting.on_direct_change(21.2, true, false, false);
check('independent capped MP timing survives a late direct HP action', resting.info(21.2).accepted == 1);

sit(71, 0, 79, 0); resting.on_vitals(21, 79, 0, 958, 79, 0, true, false);
check('an estimated HP cap cannot lower the minimum tick evidence', resting.info(21).accepted == 0);
sit(900, 295, 900, 300); resting.on_vitals(21, 900, 300, 958, 900, 300, false, true);
check('an estimated MP cap cannot lower the minimum tick evidence', resting.info(21).accepted == 0);

sit(71, 0, 79, 0); resting.on_vitals(3, 79, 0, 958, 79, 0);
check('a small final gain outside the resting window is not a tick', resting.info(3).accepted == 0);
sit(71, 0, 79, 0, 8); resting.on_vitals(21, 79, 0, 958, 79, 0);
check('known passive HP filling the cap is not a resting tick', resting.info(21).accepted == 0);
sit(900, 295, 900, 300, 0, 5); resting.on_vitals(21, 900, 300, 958, 900, 300);
check('known passive MP filling the cap is not a resting tick', resting.info(21).accepted == 0);
sit(194, 0, 200, 0);
resting.on_vitals(3, 196, 0, 958, 200, 0); resting.on_vitals(6, 198, 0, 958, 200, 0);
resting.update(6.6); resting.on_vitals(21, 200, 0, 958, 200, 0);
check('observed passive recovery filling the cap is also excluded', resting.info(21).accepted == 0);

sit(71, 0, 79, 0); resting.on_direct_change(21, true, false, false);
resting.on_vitals(21.1, 79, 0, 958, 79, 0);
check('a known direct cure to full is excluded', resting.info(21.1).accepted == 0);
sit(71, 0, 79, 0); resting.on_vitals(21, 79, 0, 958, 79, 0);
resting.on_direct_change(21.2, true, false, false);
check('a late cure packet revokes capped HP timing', resting.info(21.2).accepted == 0
    and resting.info(21.2).next_tick == 21.4);
sit(900, 295, 900, 300); resting.on_vitals(21, 900, 300, 958, 900, 300);
resting.on_direct_change(21.2, false, true, false);
check('a late direct MP packet revokes capped MP timing', resting.info(21.2).accepted == 0
    and resting.info(21.2).next_tick == 21.4);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
