-- Recovery estimates follow accepted action results and expire without promising readiness.
local out, failed = {}, 0;
local function check(name, yes, detail)
    out[#out + 1] = (yes and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not yes) then failed = failed + 1; end
end
local function near(a, b)
    return a ~= nil and math.abs(a - b) < 1e-6;
end
local recovery = require('core.recovery');

check('loading cannot invent recovery', recovery.progress(0) == nil);
recovery.on_spell(10, 57);
local first = recovery.progress(10);
check('a completed spell starts its separate 2.5 second estimate', first and first.duration == 2.5
    and first.left == 2.5 and first.fill == 0 and first.kind == 'spell' and first.estimated == true and first.known == true);
local middle = recovery.progress(11.25);
check('frames reuse the same view and advance the countdown', first == middle and near(middle.left, 1.25)
    and near(middle.fill, 0.5));
check('the final fraction remains estimated', recovery.progress(12.499).estimated == true);
check('expiry hides immediately without a Ready state', recovery.progress(12.5) == nil
    and recovery.progress(12.6) == nil);

recovery.on_weaponskill(20, 3);
local weapon = recovery.progress(20);
check('Shoulder Tackle uses its source two second recovery', weapon and weapon.duration == 2
    and weapon.left == 2 and weapon.kind == 'weaponskill' and weapon.estimated == true and weapon.known == true);
check('weapon skill recovery also hides at expiry', recovery.progress(22) == nil);

recovery.on_spell(30, 57);
recovery.on_weaponskill(30.1, 3);
check('a shorter overlapping hold cannot shorten an existing deadline', near(recovery.progress(31).left, 1.5)
    and recovery.progress(31).kind == 'spell');
recovery.on_weaponskill(31, 3);
check('a later hold preserves the longer deadline', near(recovery.progress(32).left, 1)
    and recovery.progress(32).kind == 'weaponskill');

recovery.reset();
recovery.on_spell(40, 57);
recovery.on_spell(40, 57);
check('a repeated same-time result cannot extend the deadline', near(recovery.progress(41).left, 1.5));
recovery.on_weaponskill(39.9, 3);
check('an out-of-order event cannot change the running estimate', near(recovery.progress(41).left, 1.5)
    and recovery.progress(41).kind == 'spell');
recovery.on_cast_begin(39.9);
check('an older cast-start timestamp cannot clear newer recovery', recovery.progress(41) ~= nil);
recovery.on_cast_begin(41);
check('an accepted new cast clears the previous estimate', recovery.progress(41) == nil);
recovery.on_spell(41.25, 57);
check('the new cast completion can start another estimate', near(recovery.progress(41.5).left, 2.25));
recovery.reset();
check('reset clears recovery for disable, zone or character changes', recovery.progress(42) == nil);

for _, bad in ipairs({ false, '10', -1, math.huge, -math.huge, 0 / 0 }) do
    recovery.reset();
    recovery.on_spell(bad, 57);
    recovery.on_weaponskill(bad, 3);
    check('invalid event time cannot create a timer: ' .. tostring(bad), recovery.progress(0) == nil);
    recovery.on_spell(50, 57);
    recovery.on_cast_begin(bad);
    check('invalid reads and cast starts cannot corrupt valid recovery: ' .. tostring(bad),
        recovery.progress(bad) == nil and near(recovery.progress(51).left, 1.5));
end
recovery.reset();
recovery.on_spell(nil, 57);
check('missing event time cannot create a timer', recovery.progress(0) == nil);
recovery.on_spell(60, 57);
check('a clock moving backward clears obsolete recovery', recovery.progress(59) == nil
    and recovery.progress(60) == nil);

recovery.on_spell(60, 57, 'spell result');
recovery.on_weaponskill(60.1, 3, 'weapon skill result');
recovery.on_spell(61, 57, 'spell result');
recovery.on_weaponskill(61.1, 3, 'weapon skill result');
check('replayed results cannot restart either overlapping hold', near(recovery.progress(61.25).left, 1.25)
    and recovery.progress(61.25).kind == 'spell');
recovery.on_spell(61.5, 57, 'another spell result');
check('a distinct result can extend the estimated deadline', near(recovery.progress(62).left, 2));
recovery.on_cast_begin(62.1);
recovery.on_spell(62.2, 57, 'spell result');
check('a late result after an accepted cast cannot restart recovery', recovery.progress(62.2) == nil);
recovery.on_spell(62.3, 57, 'next spell result');
check('the accepted cast can finish with a distinct packet', near(recovery.progress(62.3).left, 2.5));
recovery.reset();
recovery.on_spell(65, 57, 'spell result');
recovery.on_spell(68, 57, 'spell result');
check('a late replay expires the old hold without restarting it while hidden', recovery.progress(68) == nil);
recovery.on_spell(68.1, 57, 'new spell result');
check('a distinct packet starts recovery after hidden expiry', near(recovery.progress(68.1).left, 2.5));
recovery.progress(70.6);
recovery.on_spell(71, 57, 'new spell result');
check('a late result after visible expiry cannot restart recovery', recovery.progress(71) == nil);
recovery.on_weaponskill(71.1, 3, 'new weapon skill result');
check('a distinct weapon skill result starts its own hold', near(recovery.progress(71.1).left, 2));
recovery.on_cast_begin(72);
recovery.on_weaponskill(72.1, 3, 'new weapon skill result');
check('an accepted cast also keeps weapon skill replay history', recovery.progress(72.1) == nil);
recovery.reset();
recovery.on_spell(73, 57, 'new spell result');
check('an explicit reset clears keys for a new character or connection', near(recovery.progress(73).left, 2.5));
recovery.reset();
recovery.on_spell(75, 57);
recovery.on_spell(76, 57);
check('callers without keys retain ordinary longer-deadline behavior', near(recovery.progress(77).left, 1.5));

recovery.reset();
recovery.on_cast_begin(80, 'first cast start');
recovery.on_spell(81, 57, 'first cast result');
recovery.on_cast_begin(81.2, 'first cast start');
check('a late duplicate cast start cannot clear its completed spell recovery', near(recovery.progress(81.2).left, 2.3));
recovery.on_cast_begin(81.3, 'second cast start');
check('a distinct accepted cast still clears the previous estimate', recovery.progress(81.3) == nil);
recovery.on_spell(82, 57, 'second cast result');
recovery.on_cast_begin(82.1, 'second cast start');
recovery.on_cast_begin(82.2, 'first cast start');
check('accepted cast starts retain history across later starts and finishes', near(recovery.progress(82.2).left, 2.3));
recovery.progress(84.5);
recovery.on_spell(85, 57, 'later cast result');
recovery.on_cast_begin(85.1, 'first cast start');
check('expiry keeps cast-start replay history', near(recovery.progress(85.1).left, 2.4));
recovery.reset();
recovery.on_spell(86, 57, 'reset cast result');
recovery.on_cast_begin(86.1, 'first cast start');
check('explicit reset also clears remembered cast starts', recovery.progress(86.1) == nil);

if (jit) then jit.off(); end
recovery.reset();
recovery.on_spell(70, 57);
for _ = 1, 20 do recovery.progress(71); end
collectgarbage('collect'); collectgarbage('stop');
local before = collectgarbage('count');
for _ = 1, 1000 do recovery.progress(71); end
local bytes = (collectgarbage('count') - before) * 1024 / 1000;
collectgarbage('restart');
check('steady recovery frames allocate no result tables', bytes < 8, ('%.2f bytes/frame'):format(bytes));

local function actions()
    recovery.reset();
    recovery.on_cast_begin(79, 'spell start');
    recovery.on_spell(80, 57, 'spell result');
    recovery.on_weaponskill(80.1, 3, 'weapon skill result');
end
for _ = 1, 20 do actions(); end
collectgarbage('collect'); collectgarbage('stop');
before = collectgarbage('count');
for _ = 1, 1000 do actions(); end
bytes = (collectgarbage('count') - before) * 1024 / 1000;
collectgarbage('restart');
check('repeated action handling reuses bounded replay storage', bytes < 8, ('%.2f bytes/pair'):format(bytes));

out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
