-- Resting keeps its blocking effects current even while its timer is off or hidden at full.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end

MOCK.player.hp_max, MOCK.player.mp_max, MOCK.player.status = 1000, 400, 33;
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local resting = require('core.resting');
local s = MOCK.settings.current;
s.attack.enabled, s.enemy.enabled, s.resting.enabled = false, false, false;
MOCK.frame(0.25);
MOCK.fire('packet_in', MOCK.vitals_packet(1001, 100, 100, 1000));

for _, id in ipairs({ 8, 31, 20 }) do
    MOCK.player.buffs = { id }; MOCK.frame(0.25);
    check('disabled timer sees blocking effect ' .. id, resting.blocked_by() == id);
    MOCK.player.buffs = {}; MOCK.frame(0.25);
    check('disabled timer sees blocking effect ' .. id .. ' end', resting.blocked_by() == nil);
end

MOCK.player.buffs = { 31 }; MOCK.frame(0.25);
MOCK.fire('packet_in', MOCK.vitals_packet(1001, 100, 98, 990)); MOCK.frame(0.25);
MOCK.now = 21;
MOCK.fire('packet_in', MOCK.vitals_packet(1001, 100, 96, 980)); MOCK.frame(0.25);
check('a hidden Plague drain is not learned as recovery', resting.info(MOCK.now).accepted == 0);
s.resting.enabled = true; MOCK.frame(0.25);
check('enabling the timer retains the blocking effect', resting.blocked_by() == 31);

s.resting.hide_when_full = true;
MOCK.fire('packet_in', MOCK.vitals_packet(1001, 1000, 400, 980)); MOCK.frame(0.25);
check('full recovery hides the live timer', resting.is_full());
MOCK.player.buffs = {}; MOCK.frame(0.25);
check('an effect ending while full clears its block', resting.blocked_by() == nil);
MOCK.player.buffs = { 8 }; MOCK.frame(0.25);
check('an effect beginning while full is still tracked', resting.blocked_by() == 8);
MOCK.player.buffs = {}; MOCK.frame(0.25);
check('hidden full recovery never retains an expired block', resting.blocked_by() == nil);

out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
