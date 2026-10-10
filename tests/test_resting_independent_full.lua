-- One unknown recovery rate cannot hide the other stat's estimate.
local resting = require('core.resting');
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 0.001; end
local function sit(hp, mp, hp_max, mp_max, model)
    resting.reset(); resting.on_buffs(0, {});
    resting.on_vitals(-1, hp, mp, 300, hp_max, mp_max);
    if (model) then resting.on_model(model); end
    resting.start(0);
end

sit(100, 0, 900, 100);
resting.on_vitals(21, 110, 0, 200, 900, 100);
resting.on_vitals(30, 121, 0, 100, 900, 100);
local hp, mp, has_mp, meta = resting.until_each_full(30);
check('observed HP retains its independent ETA while MP is unknown', near(hp, 302) and mp == nil and has_mp);
check('HP retains its count and confidence while MP is explicitly unknown', meta.hp_ticks == 30
    and meta.hp_confidence == 'estimated' and meta.mp_ticks == nil and meta.mp_confidence == 'unknown');
check('combined full ETA remains unknown when MP cannot be predicted', resting.until_full(30) == nil
    and meta.full_in == nil and meta.confidence == 'unknown');

sit(0, 10, 900, 100);
resting.on_vitals(21, 0, 22, 200, 900, 100);
resting.on_vitals(30, 0, 35, 100, 900, 100);
hp, mp, has_mp, meta = resting.until_each_full(30);
check('observed MP retains its independent ETA while HP is unknown', hp == nil and near(mp, 52) and has_mp);
check('unknown HP does not borrow MP confidence or tick count', meta.hp_confidence == 'unknown'
    and meta.hp_ticks == nil and meta.mp_ticks == 5);
check('combined full ETA remains unknown when HP cannot be predicted', resting.until_full(30) == nil);

sit(100, 0, 900, 100, { resting_key = 'hp-only-model', hp_base = 31, hp_step = 4, hp_known = true });
hp, mp, has_mp, meta = resting.until_each_full(0);
check('a partial model can predict HP before any recovery observation', hp ~= nil and mp == nil
    and meta.hp_ticks ~= nil and meta.mp_ticks == nil and meta.mp_confidence == 'unknown');
check('a partial model still cannot predict when both stats are full', resting.until_full(0) == nil);

sit(100, 0, 900, 0);
resting.on_vitals(21, 110, 0, 200, 900, 0);
resting.on_vitals(30, 121, 0, 100, 900, 0);
hp, mp, has_mp, meta = resting.until_each_full(30);
check('a no-MP job keeps its existing HP estimate and combined ETA', near(hp, 302) and mp == 0
    and not has_mp and near(resting.until_full(30), hp));

sit(10, 0, 30, 100, { resting_key = 'passive-hp', regen = 5, regen_known = true });
hp, mp, has_mp, meta = resting.until_each_full(0);
check('positive passive HP recovery can estimate fullness without healing potency', near(hp, 12) and mp == nil);
check('passive-only prediction is estimated and needs no resting ticks', meta.hp_confidence == 'estimated'
    and meta.hp_ticks == 0 and meta.confidence == 'unknown');

sit(0, 10, 100, 30);
resting.on_vitals(3, 0, 15, 300, 100, 30);
resting.on_vitals(6, 0, 20, 300, 100, 30);
resting.update(6.6);
hp, mp, has_mp, meta = resting.until_each_full(6.6);
check('observed passive MP can independently predict fullness', hp == nil and near(mp, 5.4));
check('an observed passive rate does not claim exact resting potency', meta.mp_confidence == 'estimated'
    and meta.mp_ticks == 0 and resting.until_full(6.6) == nil);

sit(10, 10, 30, 30, { resting_key = 'passive-both', regen = 5, refresh = 5,
    regen_known = true, refresh_known = true });
hp, mp, has_mp, meta = resting.until_each_full(0);
check('both passive rates can produce a conservative combined estimate', near(hp, 12) and near(mp, 12)
    and near(resting.until_full(0), 12) and meta.confidence == 'estimated');

sit(90, 100, 100, 100, { resting_key = 'unknown-mp-drain', hp_base = 10, hp_step = 1,
    hp_known = true, refresh_down = 2 });
hp, mp, has_mp, meta = resting.until_each_full(0);
check('unknown recovery of draining MP does not suppress calculable HP', near(hp, 21.4) and mp == 0);
check('MP full now cannot falsely establish combined fullness after it drains', resting.until_full(0) == nil
    and meta.full_in == nil and meta.confidence == 'unknown');

sit(90, 100, 100, 100, { resting_key = 'known-drain', hp_base = 10, hp_step = 1,
    mp_base = 12, mp_step = 1, hp_known = true, mp_known = true, refresh_down = 2 });
hp, mp, has_mp, meta = resting.until_each_full(0);
check('known concurrent drain still waits until both stats are full together', near(hp, 21.4)
    and mp == 0 and near(resting.until_full(0), 31.4) and meta.ticks == 2);

sit(10, 0, 30, 0, { resting_key = 'blocked', regen = 5, regen_known = true });
resting.on_buffs(0, { [8] = true });
hp, mp, has_mp, meta = resting.until_each_full(0);
check('blocked recovery keeps the existing unavailable ETA', hp == nil and mp == 0
    and resting.until_full(0) == nil and meta.hp_confidence == 'blocked');

out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
