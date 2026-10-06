-- Sleep II (buff 19) and Lullaby (193) stop attacks on Phoenix (HasPreventActionEffect), so both must
-- stay in DISABLED_BY. Without them the gap they stretch is learned as clean.
local out, fails = {}, 0;
local function say(fmt, ...) table.insert(out, string.format(fmt, ...)); end

MOCK.items[16535] = { Delay = 240, Skill = 3 };   -- estimate 4.0 s
MOCK.player.equipment[0] = 16535;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local attack = require('core.attack');

local ME, MOB = 1001, 0x01000200;
local base = 0;
local function advance(to) to = base + to; while (MOCK.now + 1 / 60 < to) do MOCK.frame(1 / 60); end MOCK.now = to; end
local function round() MOCK.fire('packet_in', MOCK.action_packet(ME, 1, 0x306B7461, MOB, { { message = 1 } })); end

local function run(buff)
    base = MOCK.now;
    attack.reset();
    MOCK.player.buffs = {};
    MOCK.player.status = 0; advance(1);
    MOCK.player.status = 1; advance(2);
    for _, t in ipairs({ 3.6, 7.6, 11.6, 15.6 }) do advance(t); round(); end
    advance(16.5); MOCK.player.buffs = { buff };      -- put to sleep mid-gap
    advance(19.5); MOCK.player.buffs = {};            -- a hit wakes you
    advance(21.2); round();                           -- 5.6 s gap, under the 6.0 s cut-off
    local _, _, d = attack.progress(MOCK.now);
    say('buff %3d during the gap: delay in use %.2f s (true delay 4.00)', buff, d);
    if (math.abs(d - 4.0) > 0.005) then
        fails = fails + 1;
        say('FAIL buff %d', buff);
    end
end

run(2);     -- Sleep I
run(19);    -- Sleep II
run(193);   -- Lullaby
if (fails > 0) then
    say('%d FAILED', fails);
end
return table.concat(out, '\n');
