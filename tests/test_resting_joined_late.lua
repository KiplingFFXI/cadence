-- Joining an ongoing rest learns its phase without inventing another first-tick wait.
local resting = require('core.resting');
local out, failures = {}, 0;
local function check(name, value, detail)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not value) then failures = failures + 1; end
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 0.001; end
local model = { resting_key = 'plain', hp_base = 10, hp_step = 1, mp_base = 12, mp_step = 1,
    hp_known = true, mp_known = true, regen = 0, refresh = 0 };
local function begin(mp, mp_max, late)
    resting.reset(); resting.on_buffs(100, {});
    resting.on_model(model);
    resting.on_vitals(100, 100, mp, 900, 1000, mp_max);
    resting.start(100, late);
end
begin(100, 500, true);
local fill, left, ticks, _, _, _, unknown = resting.progress(100);
local hp, mp, _, meta = resting.until_each_full(100);
check('an already-resting load begins with an unknown phase', fill == 0 and left == nil and ticks == 0 and unknown);
check('unknown phase gives neither an invented full time nor tick count', hp == nil and mp == nil and meta.full_in == nil and meta.ticks == nil);
resting.update(150);
check('waiting alone never manufactures recovery ticks', resting.info(150).ticks == 0 and resting.info(150).phase_unknown);
resting.on_vitals(151, 120, 120, 800, 1000, 500);
check('the next strong tick establishes the ongoing phase immediately', resting.info(151).accepted == 1
    and not resting.info(151).phase_unknown and resting.seen_at() == 151);
resting.on_vitals(160, 141, 141, 700, 1000, 500);
resting.on_vitals(169, 163, 163, 600, 1000, 500);
check('two following short gaps establish the long gap', resting.info(169).accepted == 3
    and resting.pattern_known() and near(resting.info(169).next_tick, 181));
resting.on_model({ resting_key = 'changed', hp_base = 15, hp_step = 1, mp_base = 17, mp_step = 1,
    hp_known = true, mp_known = true, regen = 0, refresh = 0 });
hp, mp = resting.next_gains();
check('a changed model cannot invent the earlier tick count', hp == nil and mp == nil);
resting.on_vitals(181, 190, 190, 500, 1000, 500);
resting.on_vitals(190, 218, 218, 400, 1000, 500);
hp, mp = resting.next_gains();
check('new uncapped samples restore potency after a model change', hp == 29 and mp == 29);
begin(0, 0, true);
resting.on_vitals(102, 110, 0, 900, 1000, 0);
resting.on_vitals(111, 121, 0, 900, 1000, 0);
resting.on_vitals(120, 133, 0, 900, 1000, 0);
check('HP-only recovery with no TP loss also finds the early phase', resting.info(120).accepted == 3
    and near(resting.info(120).next_tick, 132));
begin(0, 0, true);
resting.on_direct_change(102, true, false, false);
resting.on_vitals(102.1, 150, 0, 900, 1000, 0);
check('a known cure cannot initialize an unknown phase', resting.info(102.1).phase_unknown and resting.info(102.1).accepted == 0);
begin(0, 0, true);
resting.on_vitals(102, 150, 0, 900, 1000, 0);
resting.on_direct_change(102.2, true, false, false);
check('a late cure packet restores the preceding unknown phase', resting.info(102.2).phase_unknown
    and resting.info(102.2).accepted == 0 and resting.info(102.2).next_tick == nil);
begin(0, 0, true);
resting.on_buffs(101, { [8] = true });
resting.update(130);
check('a blocking effect cannot create a guessed phase after reload', resting.info(130).phase_unknown and resting.info(130).ticks == 0);
resting.on_vitals(131, 110, 0, 900, 1000, 0);
resting.on_buffs(131.1, {});
check('the first recovery as a blocking effect wears off sets the phase', not resting.info(131.1).phase_unknown and resting.seen_at() == 131);
begin(0, 0, false);
resting.on_vitals(102, 120, 0, 800, 1000, 0);
check('a genuine new sit still rejects recovery before its first-tick window', resting.info(102).accepted == 0
    and near(resting.info(102).next_tick, 121.4));
resting.on_vitals(121, 141, 0, 700, 1000, 0);
check('a genuine first tick still initializes fresh resting', resting.info(121).accepted == 1);
resting.reset(); resting.on_vitals(200, 1000, 500, 0, 1000, 500); resting.start(200, true);
hp, mp, _, meta = resting.until_each_full(200);
check('already-full stats stay correctly full with an unknown phase', hp == 0 and mp == 0 and meta.full_in == 0);
resting.on_max_vitals(201, 1500, 750);
hp, mp, _, meta = resting.until_each_full(201);
check('a maximum increase does not invent a fresh resting phase', hp == nil and mp == nil and meta.confidence == 'unknown');
resting.reset(); resting.on_model(model);
resting.on_vitals(200, 1000, 500, 500, 1000, 500); resting.start(200, true);
resting.on_vitals(202, 1000, 500, 400, 1000, 500);
resting.on_vitals(211, 1000, 500, 300, 1000, 500);
resting.on_vitals(220, 1000, 500, 200, 1000, 500);
resting.on_max_vitals(221, 1500, 750);
hp, mp = resting.next_gains();
check('TP-only ticks establish phase without inventing capped HP or MP potency', resting.pattern_known() and hp == nil and mp == nil);
resting.on_vitals(232, 1050, 540, 100, 1500, 750);
hp, mp = resting.next_gains();
check('an uncapped tick restores both potency forecasts after a maximum increase', hp == 51 and mp == 41);
resting.reset(); resting.start(300);
check('a new rest after reset has a fresh first-tick countdown', near(resting.info(300).next_tick, 321.4) and not resting.info(300).phase_unknown);
out[#out + 1] = failures == 0 and 'ALL PASSED' or (failures .. ' FAILED');
return table.concat(out, '\n');
