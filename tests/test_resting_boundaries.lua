-- Passive recovery can hit a boundary before the resting gain arrives on the same pass.
local resting = require('core.resting');
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local function sit(hp, mp, hp_max, mp_max, extra)
    resting.reset();
    resting.on_buffs(0, {});
    resting.on_vitals(-1, hp, mp, 0, hp_max, mp_max);
    local model = { resting_key = 'passive boundary', hp_base = 10, hp_step = 1,
        mp_base = 12, mp_step = 1, hp_known = true, mp_known = true };
    for key, value in pairs(extra or {}) do model[key] = value; end
    resting.on_model(model);
    resting.start(0);
end

for _, refresh in ipairs({ 3, 20 }) do
    sit(100, 88, 1000, 100, { refresh = refresh });
    resting.on_vitals(21, 110, 100, 0, 1000, 100);
    local info = resting.info(21);
    local hp, mp, confidence = resting.next_gains();
    check('Refresh ' .. refresh .. ': capped MP keeps the simultaneous HP tick',
        info.accepted == 1 and info.ticks == 1 and info.next_tick == 30);
    check('Refresh ' .. refresh .. ': only uncapped HP teaches the resting amount',
        hp == 11 and mp == 0 and confidence.hp == 'observed'
        and confidence.mp_uncapped == 13 and confidence.mp == 'known');
    local hp_time, mp_time = resting.until_each_full(21);
    check('Refresh ' .. refresh .. ': HP recovery remains calculable after MP fills',
        hp_time ~= nil and hp_time > 0 and mp_time == 0);
end

for _, before in ipairs({ 0, 1 }) do
    sit(100, before, 100, 100, { refresh_down = 2 });
    resting.on_vitals(21, 100, 12, 0, 100, 100);
    local info = resting.info(21);
    local _, mp, confidence = resting.next_gains();
    check('MP ' .. before .. ': drain capped at zero keeps the first recovery tick',
        info.accepted == 1 and info.ticks == 1 and info.next_tick == 30);
    check('MP ' .. before .. ': drain capped at zero cannot inflate healing potency',
        mp == 13 and confidence.mp_uncapped == 13);
    check('MP ' .. before .. ': the full drain rate remains available for the forecast',
        info.regen_mp == -2 and resting.until_full(21) ~= nil);
end

sit(100, 10, 100, 100, { refresh_down = 2 });
resting.on_vitals(21, 100, 20, 0, 100, 100);
local _, mp, confidence = resting.next_gains();
check('an uncapped drain still teaches the clean resting amount',
    mp == 13 and confidence.mp == 'observed');

sit(100, 100, 1000, 1000);
resting.on_buffs(0, { [8] = true });
resting.update(22);
resting.update(31);
resting.update(43);
resting.on_buffs(44, {});
local hp_time, mp_time, _, meta = resting.until_each_full(44);
local goal = resting.goal_progress(44, 'both', 'percent', 80);
check('assumed ticks preserve recovery progress while disease blocks healing',
    resting.info(44).ticks == 3 and resting.seen_at() == nil
    and hp_time ~= nil and mp_time ~= nil);
check('assumed ticks alone cannot establish exact HP or MP timing',
    meta.confidence == 'estimated' and meta.hp_confidence == 'estimated'
    and meta.mp_confidence == 'estimated' and goal.confidence == 'estimated');

out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
