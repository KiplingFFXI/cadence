-- A paralyzed ranged attack while engaged. Phoenix's RangedParalyzed (interrupts.cpp) sends the cat
-- 12 'splg' interrupt first, then the cat 4 / param 0 / msg 84 packet. A paralyzed item goes the
-- other way. ItemParalyzed sends cat 4 first, then the cat 9 'spit'.
local out, fails = {}, 0;
local function say(fmt, ...) table.insert(out, string.format(fmt, ...)); end

MOCK.items[16535] = { Delay = 240, Skill = 3 };   -- 240 delay sword, estimate 4.0 s
MOCK.player.equipment[0] = 16535;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local attack = require('core.attack');

local ME, MOB = 1001, 0x01000200;
local function packet(e) MOCK.fire('packet_in', e); end
local function at(t) MOCK.now = t; end

local function run(label, want, steps)
    attack.reset();
    MOCK.player.status = 0; at(99); MOCK.fire('d3d_present');
    MOCK.player.status = 1; at(100); MOCK.fire('d3d_present');       -- engage at 100
    at(102); packet(MOCK.action_packet(ME, 1, 0x306B7461, MOB, { { message = 1 } }));   -- round, next due 106
    steps();
    local _, left, delay = attack.progress(MOCK.now);
    say('%-44s t=%.1f  bar says next attack in %.2f s (delay %.2f)', label, MOCK.now, left, delay);
    if (math.abs(left - want) > 0.005) then
        fails = fails + 1;
        say('FAIL %s: want %.2f s', label, want);
    end
end

run('ranged, clean finish (cat 2)', 3.8, function ()
    at(103); packet(MOCK.action_packet(ME, 12, 0x676C6163, MOB, { { message = 0 } }));   -- 'calg'
    at(105); packet(MOCK.action_packet(ME, 2, 0, MOB, { { message = 352 } }));           -- finish
end);

run('ranged, paralyzed (splg then cat4 msg84)', 3.8, function ()
    at(103); packet(MOCK.action_packet(ME, 12, 0x676C6163, MOB, { { message = 0 } }));   -- 'calg'
    at(105); packet(MOCK.action_packet(ME, 12, 0x676C7073, ME, { { message = 0 } }));    -- 'splg' interrupt
    packet(MOCK.action_packet(ME, 4, 0, ME, { { message = 84 } }));                      -- IsParalyzed2
end);

run('item, paralyzed (cat4 msg84 then spit)', 3.4, function ()
    at(103); packet(MOCK.action_packet(ME, 9, 0x74696163, ME, { { message = 0 } }));     -- 'cait'
    at(105); packet(MOCK.action_packet(ME, 4, 0, ME, { { message = 84 } }));
    packet(MOCK.action_packet(ME, 9, 0x74697073, ME, { { message = 0 } }));             -- 'spit'
end);

say('');
say('The server carries the 3.0 s that was left, so both ranged cases should read 3.8 s (3.0 + 0.8 hold).');
if (fails > 0) then
    say('%d FAILED', fails);
end
return table.concat(out, '\n');
