-- Server percentages reject stale maximum HP/MP without claiming a rounded estimate is exact.
local player = require('core.player');
local out, failures = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failures = failures + 1; end
end
local function native(hp, mp) MOCK.player.hp_max, MOCK.player.mp_max = hp, mp; end
local function fresh(hp, mp)
    player.reset_vitals(); native(hp, mp); return player.max_vitals();
end
local hp, mp, hq, mq = fresh(300, 100);
check('before packets the native maxima remain exact inputs', hp == 300 and mp == 100 and not hq and not mq);
player.on_max_vitals(300, 100);
player.on_vitals(300, 100, 25, 25);
hp, mp, hq, mq = player.max_vitals();
check('both weakened caps are disproved by the new current percentages', hp == 1200 and mp == 400 and hq == true and mq == true);
player.on_vitals(310, 110, 25, 27);
hp, mp, hq, mq = player.max_vitals();
check('consistent estimates do not change with every recovery tick', hp == 1200 and mp == 400 and hq == true and mq == true);
native(1200, 400);
hp, mp, hq, mq = player.max_vitals();
check('coherent changed native maxima replace estimates with exact inputs', hp == 1200 and mp == 400 and not hq and not mq);

player.on_max_vitals(600, 200);
hp, mp, hq, mq = player.max_vitals();
check('a new exact status packet clears older percentage evidence and wins over memory', hp == 600 and mp == 200 and not hq and not mq);
native(900, 300);
hp, mp = player.max_vitals();
check('the exact packet stays authoritative until another current snapshot', hp == 600 and mp == 200);
player.on_vitals(300, 100, 50, 50);
hp, mp = player.max_vitals();
check('an incoherent changed native value cannot replace the exact packet', hp == 600 and mp == 200);
native(601, 201);
player.on_vitals(300, 100, 49, 49);
hp, mp, hq, mq = player.max_vitals();
check('a later coherent native change is accepted after the next snapshot', hp == 601 and mp == 201 and not hq and not mq);

fresh(300, 100);
player.on_vitals(30, 10, 1, 1);
hp, mp, hq, mq = player.max_vitals();
check('one percent supplies only an unknown lower bound', hp == 1501 and mp == 501 and hq == 'unknown' and mq == 'unknown');
check('an unknown bound cannot look full', hp > 30 and mp > 10);
player.on_vitals(3, 1, 1, 1);
hp, mp, hq, mq = player.max_vitals();
check('an unchanged previously rejected native cap cannot later revive as exact', hp == 1501 and mp == 501 and hq == 'unknown' and mq == 'unknown');
player.on_vitals(31, 11, 2, 2);
hp, mp, hq, mq = player.max_vitals();
check('a bounded percentage resolves unknown quality while retaining a consistent cap', hp == 1501 and mp == 501 and hq == true and mq == true);
player.on_vitals(1501, 501, 100, 100);
hp, mp, hq, mq = player.max_vitals();
check('an observed full snapshot supplies exact maxima', hp == 1501 and mp == 501 and not hq and not mq);

fresh(300, 0);
player.on_vitals(300, 0, 25, 0);
hp, mp, hq, mq = player.max_vitals();
check('HP-only jobs can estimate HP without inventing an MP pool', hp == 1200 and hq == true and mp == 0 and not mq);
player.on_vitals(400, 0, 0, 0);
hp, mp, hq = player.max_vitals();
check('a missing percentage does not reinterpret positive current HP', hp == 1200 and mp == 0 and hq == true);
for _, percent in ipairs({ -1, 101, math.huge, 1.5 }) do
    player.on_vitals(300, 0, percent, 0);
end
player.on_vitals(nil, nil, nil, nil);
player.on_max_vitals(-1, 20);
hp, mp, hq = player.max_vitals();
check('invalid snapshots cannot replace valid maximum evidence', hp == 1200 and mp == 0 and hq == true);
native(800, 0); player.reset_vitals();
hp, mp, hq, mq = player.max_vitals();
check('a lifecycle reset removes all old values and source quality', hp == 800 and mp == 0 and not hq and not mq);

-- A float-derived server percentage may fall on either side of an exact integer division.
fresh(1000, 1000);
player.on_vitals(290, 290, 28, 29);
hp, mp, hq, mq = player.max_vitals();
check('float rounding at an integer edge does not reject coherent native caps', hp == 1000 and mp == 1000 and not hq and not mq);
player.on_vitals(250, 250, 20, 20);
hp, mp, hq, mq = player.max_vitals();
check('a genuine contradiction still replaces native caps with bounded estimates', hp == 1250 and mp == 1250 and hq == true and mq == true);

fresh(300, 100);
player.on_vitals(300, 100, 99, 99);
hp, mp, hq, mq = player.max_vitals();
check('rounding tolerance never treats 99 percent as full', hp > 300 and mp > 100 and hq == true and mq == true);
fresh(nil, nil);
player.on_vitals(0, 0, 0, 0);
hp, mp, hq, mq = player.max_vitals();
check('unavailable native stats with empty vitals supply unknown numeric bounds', hp == 1 and mp == 1
    and hq == 'unknown' and mq == 'unknown');
player.on_vitals(300, 100, 0, nil);
hp, mp, hq, mq = player.max_vitals();
check('missing percentages still keep unavailable bounds above current vitals', hp == 301 and mp == 101
    and hq == 'unknown' and mq == 'unknown');
native(1200, 400);
hp, mp, hq, mq = player.max_vitals();
check('unknown fallback bounds do not block native stats becoming available', hp == 1200 and mp == 400 and not hq and not mq);
fresh(0, 0);
player.on_vitals(0, 0, 0, 0);
hp, mp, hq, mq = player.max_vitals();
check('zero native HP is unavailable while zero native MP remains a valid pool', hp == 1 and hq == 'unknown' and mp == 0 and not mq);

fresh(900, 300);
player.on_vitals(900, 300, 0, 0);
native(300, 100);
hp, mp, hq, mq = player.max_vitals();
check('changed native caps may clamp older current values when percentages are absent', hp == 300 and mp == 100 and not hq and not mq);
native(900, 300);
hp, mp = player.max_vitals();
check('native caps may recover after that clamp without an intervening current packet', hp == 900 and mp == 300);
player.on_vitals(900, 300, 100, 100);
native(300, 100);
hp, mp = player.max_vitals();
check('a valid percentage snapshot still rejects contradictory changed native caps', hp == 900 and mp == 300);
player.on_max_vitals(600, 200);
native(299, 99);
hp, mp = player.max_vitals();
check('an exact status packet remains pinned even without percentage evidence', hp == 600 and mp == 200);
player.reset_vitals(); native(300, 100);
player.on_vitals(400, 150, 0, 0);
hp, mp, hq, mq = player.max_vitals();
check('the first native read cannot contradict a newer current packet without percentage data', hp > 400 and mp > 150
    and hq == 'unknown' and mq == 'unknown');

if (jit) then jit.off(); end
for _ = 1, 100 do player.max_vitals(); end
collectgarbage('collect'); collectgarbage('stop');
local before = collectgarbage('count');
for _ = 1, 1000 do player.max_vitals(); end
local bytes = (collectgarbage('count') - before) * 1024 / 1000;
collectgarbage('restart');
check('steady source selection allocates no frame tables', bytes < 1);
out[#out + 1] = failures == 0 and 'ALL PASSED' or (failures .. ' FAILED');
return table.concat(out, '\n');
