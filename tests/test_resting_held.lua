-- A duplicate packet must not replace recovery waiting for the next buff read.
local resting = require('core.resting');
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local function sit(blocked, hp, mp, hp_max, mp_max)
    resting.reset();
    resting.on_buffs(0, { [blocked] = true });
    resting.on_vitals(-1, hp, mp, 0, hp_max, mp_max);
    resting.on_model({ resting_key = 'held recovery', hp_base = 10, hp_step = 1,
        mp_base = 12, mp_step = 1, hp_known = true, mp_known = true });
    resting.start(0);
end

for _, blocked in ipairs({ 8, 31, 20 }) do
    for _, case in ipairs({
        { name = 'HP and MP', hp = 100, mp = 100, hp_max = 1000, mp_max = 1000,
            hp_gain = 10, mp_gain = 12 },
        { name = 'HP only', hp = 100, mp = 0, hp_max = 1000, mp_max = 0,
            hp_gain = 10, mp_gain = 0 },
        { name = 'MP only', hp = 1000, mp = 100, hp_max = 1000, mp_max = 1000,
            hp_gain = 0, mp_gain = 12 },
    }) do
        local label = blocked .. ' ' .. case.name;
        sit(blocked, case.hp, case.mp, case.hp_max, case.mp_max);
        local hp, mp = case.hp + case.hp_gain, case.mp + case.mp_gain;
        resting.on_vitals(21, hp, mp, 0, case.hp_max, case.mp_max);
        resting.on_vitals(21.05, hp, mp, 0, case.hp_max, case.mp_max);
        resting.on_buffs(21.1, {});
        local info = resting.info(21.1);
        check(label .. ': recovery survives a duplicate before the buff read', info.ticks == 1
            and info.accepted == 1 and info.last_tick == 21 and info.next_tick == 30);
        check(label .. ': clean resources teach their recovery amounts',
            (case.hp_gain == 0 or (info.next_hp == 11 and info.gain_confidence.hp == 'observed'))
            and (case.mp_gain == 0 or (info.next_mp == 13 and info.gain_confidence.mp == 'observed')));
    end

    sit(blocked, 100, 100, 1000, 1000);
    resting.on_vitals(21, 100, 100, 0, 1000, 1000);
    resting.on_vitals(21.05, 100, 100, 0, 1000, 1000);
    resting.on_buffs(21.1, {});
    check(blocked .. ': duplicates without recovery do not establish a tick', resting.info(21.1).accepted == 0
        and resting.info(21.1).last_tick == nil);

    sit(blocked, 100, 100, 1000, 1000);
    resting.on_vitals(21, 110, 112, 0, 1000, 1000);
    resting.on_vitals(21.05, 110, 112, 0, 1000, 1000);
    resting.on_buffs(21.1, { [blocked] = true });
    check(blocked .. ': recovery remains excluded while the effect is present',
        resting.info(21.1).accepted == 0 and resting.blocked_by() == blocked);

    sit(blocked, 100, 100, 1000, 1000);
    resting.on_vitals(21, 200, 112, 0, 1000, 1000);
    resting.on_vitals(21.05, 200, 112, 0, 1000, 1000);
    resting.on_direct_change(21.08, true, false, false);
    resting.on_buffs(21.1, {});
    local info = resting.info(21.1);
    check(blocked .. ': a late cure leaves independent MP timing intact', info.accepted == 1
        and info.last_tick == 21 and info.next_tick == 30 and info.next_mp == 13
        and info.gain_confidence.mp == 'observed');
    check(blocked .. ': the late cure does not teach HP potency', info.next_hp == 11
        and info.gain_confidence.hp == 'known');

    sit(blocked, 100, 0, 1000, 0);
    resting.on_vitals(21, 200, 0, 0, 1000, 0);
    resting.on_vitals(21.05, 200, 0, 0, 1000, 0);
    resting.on_direct_change(21.08, true, false, false);
    resting.on_buffs(21.1, {});
    check(blocked .. ': a late cure alone cannot establish recovery', resting.info(21.1).accepted == 0
        and resting.info(21.1).next_tick == 21.4 and resting.next_gains() == 10);
end

out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
