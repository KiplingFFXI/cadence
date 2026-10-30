-- Sleep, stun, petrification, terror, Lullaby and a penalty stop the auto attack bar where it is, and
-- it carries on from the same spot once they wear off, the way the server's timer does.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end
local function near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 0.05); end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };   -- 4.0 s
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local attack = require('core.attack');

local ME, MOB = 1001, 0x01000200;
local function run_to(t) while (MOCK.now + 1 / 60 < t) do MOCK.frame(1 / 60); end MOCK.now = t; MOCK.frame(0); end
local function round() MOCK.fire('packet_in', MOCK.action_packet(ME, 1, 0, MOB, { { message = 1 } })); end
local function left_now() return select(2, attack.progress(MOCK.now)); end

local function engaged_at(t0)
    attack.reset();
    MOCK.player.buffs = {};
    MOCK.player.status = 0;
    MOCK.now = t0;
    MOCK.frame(1 / 60);
    MOCK.player.status = 1;
    MOCK.frame(1 / 60);
    for _, t in ipairs({ 1.6, 5.6, 9.6, 13.6 }) do run_to(t0 + t); round(); end
end

-- Put to sleep 1 s into a 4 s gap. The bar stops with 3 s left and stays there.
local T = 1000;
engaged_at(T);
run_to(T + 14.6);
MOCK.player.buffs = { 2 };
run_to(T + 15.0);
local held = left_now();
check('the bar stops when you fall asleep', near(held, 3.0, 0.25), held);
run_to(T + 20.0);
check('and stays stopped', near(left_now(), held, 0.001), left_now());

-- Woken up at 20 s. The 3 s that were left carry on from there.
MOCK.player.buffs = {};
run_to(T + 20.4);
local after = left_now();
check('it carries on from the same spot', near(after, held - 0.2, 0.25), after);
run_to(T + 22.0);
check('and counts down again', near(left_now(), after - 1.6, 0.05), left_now());

-- The attack that comes after doesn't teach it a slow delay.
run_to(T + 23.2);
round();
check('the gap with the pause isn\'t learned', near(select(3, attack.progress(MOCK.now)), 4.0, 0.001),
    select(3, attack.progress(MOCK.now)));

-- Every effect that stops attacks on Phoenix does it, terror included.
local NAMES = { [2] = 'sleep', [7] = 'petrification', [10] = 'stun', [19] = 'Sleep II', [28] = 'terror',
    [159] = 'a penalty', [193] = 'Lullaby' };
for _, id in ipairs({ 2, 7, 10, 19, 28, 159, 193 }) do
    T = T + 100;
    engaged_at(T);
    run_to(T + 14.6);
    MOCK.player.buffs = { id };
    run_to(T + 15.0);
    local stopped = left_now();
    run_to(T + 18.0);
    check(NAMES[id] .. ' stops the bar', near(left_now(), stopped, 0.001) and stopped > 2.0, left_now());
    MOCK.player.buffs = {};
end

-- Something that doesn't stop attacks, like paralysis or bind, leaves the bar running.
T = T + 100;
engaged_at(T);
run_to(T + 14.6);
MOCK.player.buffs = { 4, 11 };
run_to(T + 15.0);
local running = left_now();
run_to(T + 16.0);
check('paralysis and bind leave it running', near(left_now(), running - 1.0, 0.05), left_now());
MOCK.player.buffs = {};

-- Asleep while ready and waiting, it's still ready when you wake.
T = T + 100;
engaged_at(T);
run_to(T + 18.0);
MOCK.player.buffs = { 2 };
run_to(T + 22.0);
MOCK.player.buffs = {};
run_to(T + 22.4);
check('ready stays ready', left_now() == 0, left_now());

-- An attack that shows up proves you're awake, even before the buff check catches up.
T = T + 100;
engaged_at(T);
run_to(T + 14.6);
MOCK.player.buffs = { 10 };
run_to(T + 15.0);
MOCK.player.buffs = {};
round();
check('an attack ends the pause', near(left_now(), 4.0, 0.001), left_now());

-- An interrupt does not reveal the spell state's remaining lifetime. Keep that uncertainty until
-- an observed attack supplies a new phase, including when the disabling effect has worn off.
T = T + 100;
engaged_at(T);
run_to(T + 14.0);
MOCK.fire('packet_in', MOCK.action_packet(ME, 8, 0x6163, ME, { { message = 327 } }));
run_to(T + 14.2);
MOCK.player.buffs = { 10 };
run_to(T + 14.8);
MOCK.fire('packet_in', MOCK.action_packet(ME, 8, 0x7073, ME, { { message = 16 } }));
check('stunned mid-spell, the remaining spell suspension stays unknown', left_now() == nil);
run_to(T + 17.0);
check('the stun cannot manufacture a remaining spell duration', left_now() == nil);
MOCK.player.buffs = {};
run_to(T + 17.4);
check('wearing off stun keeps the unobserved spell recovery unknown', left_now() == nil);
round();
check('the next real attack restores the normal phase', near(left_now(), 4));

-- Disengaging while asleep leaves nothing behind for the next fight.
T = T + 100;
engaged_at(T);
run_to(T + 14.6);
MOCK.player.buffs = { 2 };
run_to(T + 15.0);
MOCK.player.status = 0;
MOCK.frame(1 / 60);
MOCK.player.buffs = {};
MOCK.player.status = 1;
MOCK.frame(1 / 60);
check('a new fight starts fresh', near(left_now(), 2.8, 0.05), left_now());

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
