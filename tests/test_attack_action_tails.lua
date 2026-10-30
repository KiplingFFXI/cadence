-- Attack holds keep their own timing, including zero and unknown action tails.
local attack = require('core.attack');
local out, failures = {}, 0;
local function check(name, value, detail)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not value) then failures = failures + 1; end
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 0.001; end
local function remaining(now) local _, left = attack.progress(now); return left; end
local function fresh()
    attack.reset();
    attack.engage(100, 4, 'plain');
end
fresh();
check('a normal attack timer reports no holding reason', select(5, attack.progress(100)) == nil);
attack.on_ability(102.7, 5);
check('Super Jump preserves remaining phase through its five-second suspension', near(remaining(105), 2.8));
fresh();
attack.on_ability(102.7);
check('ordinary ability fallback still uses two seconds', near(remaining(103), 1.8));
fresh();
attack.on_ability(102.7, 0);
check('a validated zero-tail ability adds no invented two-second hold', near(remaining(102.7), 0.1));
fresh();
attack.on_cast_begin(102.7, 'item');
attack.on_cast_end(105.7, 5);
check('an item keeps its source tail instead of the old generic delay', near(remaining(106.3), 4.5));
fresh();
attack.on_cast_begin(102.7, 'item');
attack.on_cast_end(105.7, 0.4);
check('a zero-tail item can keep its next-server-pass estimate', near(remaining(105.7), 0.5));
fresh();
attack.on_cast_begin(102.7, 'spell');
attack.on_cast_end(105.7);
check('spell attack recovery stays separate from the global spell gate', near(remaining(105.7), 2.1));
fresh();
attack.on_cast_begin(102.7, 'ranged');
attack.on_cast_end(105.7);
check('ranged fallback keeps its own return-weapon tail', near(remaining(105.7), 0.9));
fresh();
attack.on_cast_begin(102.7, 'item');
attack.on_cast_end(105.7, false);
local fill, left, _, _, why = attack.progress(200);
local info = attack.info(200);
check('an unknown item tail cannot become Ready by waiting', fill == 0 and left == nil and why == 'recovery');
check('unknown attack recovery suppresses numeric forecasts', info.next_in == nil and info.holding == 'recovery' and not info.overdue);
attack.on_paralyzed(200, 4, 'plain', true, false);
check('an ambiguous failed action cannot clear unknown recovery', remaining(200) == nil);
attack.on_ability(201, 0);
check('an accepted zero-tail ability resolves uncertainty and preserves phase', near(remaining(201), 0.1));
attack.on_ability(202, false);
check('an unrecognized ability also exposes uncertainty', remaining(202) == nil);
attack.on_cast_begin(203, 'spell');
attack.on_cast_end(205, 2);
check('an accepted new cast resolves older unknown recovery', near(remaining(205), 2));
attack.on_ability(206, false);
attack.on_round(210, 4, 'plain', true, false);
check('an observed round completely resynchronizes unknown recovery', near(remaining(210), 4) and attack.info(210).holding == nil);
attack.on_ability(211, false);
attack.on_out_of_reach('too far');
check('a real attack rejection replaces unknown recovery with its observed reason', attack.info(211).holding == nil and attack.info(211).reason == 'too far');
attack.on_ability(212, false);
attack.reset(); attack.engage(300, 4, 'plain');
check('lifecycle reset cannot retain an old unknown hold', near(remaining(300), 2.8));
if (jit) then jit.off(); end
for _ = 1, 100 do attack.progress(300); end
collectgarbage('collect'); collectgarbage('stop');
local before = collectgarbage('count');
for _ = 1, 1000 do attack.progress(300); end
local bytes = (collectgarbage('count') - before) * 1024 / 1000;
collectgarbage('restart');
check('steady attack progress reuses its state', bytes < 1, ('%.2f bytes/frame'):format(bytes));
out[#out + 1] = failures == 0 and 'ALL PASSED' or (failures .. ' FAILED');
return table.concat(out, '\n');
