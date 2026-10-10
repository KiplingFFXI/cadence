-- TP time uses the regular input poll. Attack packets still read fresh gear.
local out, fails = {}, 0;
local function check(name, condition, detail)
    out[#out + 1] = (condition and 'ok   ' or 'FAIL ') .. name .. (detail and ('  -> ' .. tostring(detail)) or '');
    if (not condition) then fails = fails + 1; end
end

local player, tp = require('core.player'), require('core.tp');
local reads, last_delay, transition = 0, nil, nil;
local read = player.read_loadout;
player.read_loadout = function (...)
    reads = reads + 1;
    return read(...);
end;
local time_to = tp.time_to;
tp.time_to = function (goal, value, now, timing)
    last_delay, transition = timing.modeled_delay, timing.transition;
    return time_to(goal, value, now, timing);
end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
MOCK.player.status = 1;
MOCK.now = 100;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
MOCK.fire('command', { command = '/cadence attack time on' });
MOCK.frame(0.01);
reads = 0;
for _ = 1, 60 do MOCK.frame(1 / 60); end
check('TP time polls inputs five times per second instead of once per frame', reads >= 4 and reads <= 6, reads);
check('TP time still receives the modeled delay', last_delay == 4, last_delay);

local before = reads;
MOCK.items[16535].Delay = 360;
MOCK.fire('packet_in', MOCK.action_packet(1001, 1, 0, 0x01000200, { { message = 1 } }));
MOCK.frame(0.001);
check('an attack packet reads changed weapon delay immediately', reads > before and last_delay == 6, last_delay);

local state = require('core.stat_state');
local old_model = state.info();
MOCK.player.buffs = { 33 };
state.effect_context(MOCK.now, player.read_loadout());
check('a cast snapshot can replace the model between regular polls', state.info() ~= old_model);
MOCK.fire('packet_in', { id = 0x050, data = string.rep('\0', 8), size = 8 });
MOCK.frame(0.001);
check('TP time reads pending uncertainty from the replacement model', transition == true);

MOCK.fire('packet_in', MOCK.zone_packet(1001, 100));
MOCK.items[16535].Delay = 180;
MOCK.player.buffs = {};
MOCK.frame(0.001);
check('zoning cannot reuse the previous weapon snapshot', last_delay == 3, last_delay);

out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
