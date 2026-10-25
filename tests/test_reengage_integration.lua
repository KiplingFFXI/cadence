-- Server combat transitions retain one estimate without teaching the attack or TP clocks idle gaps.
local out, fails = {}, 0;
local function check(name, value, detail)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not value) then fails = fails + 1; end
end
local function close(a, b) return a ~= nil and math.abs(a - b) < 0.002; end
local packets = require('core.packets');
local normal = MOCK.status_packet(1001, 1);
local id, status = packets.status(normal);
check('status fields match Phoenix layout', id == 1001 and status == 1);
for size = 0, 48 do
    local event = { id = 0x037, data = normal.data:sub(1, size), size = size };
    check('short status packet is rejected at ' .. size, not packets.valid(event) and packets.status(event) == nil);
end
local native = newproxy(true);
getmetatable(native).__index = normal;
check('native Ashita status userdata is readable', packets.valid(native) and packets.status(native) == 1001);

MOCK.player.main_job, MOCK.player.sub_job, MOCK.player.sub_level = 1, 0, 0;
MOCK.player.hp, MOCK.player.mp = 900, 100;
MOCK.player.equipment[0] = 16535;
MOCK.items[16535] = { Delay = 480, Skill = 3 };
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local attack, hud, player = require('core.attack'), require('ui.hud'), require('core.player');
local attack_draws, resting_draws, retained_draws = 0, 0, 0;
local draw_attack, draw_resting, draw_reengage = hud.draw_attack, hud.draw_resting, hud.draw_reengage;
hud.draw_attack = function (...) attack_draws = attack_draws + 1; return draw_attack(...); end;
hud.draw_resting = function (...) resting_draws = resting_draws + 1; return draw_resting(...); end;
hud.draw_reengage = function (...) retained_draws = retained_draws + 1; return draw_reengage(...); end;
local MOB = 0x01000200;
local function incoming(event, now)
    MOCK.now = now;
    MOCK.fire('packet_in', event);
end
local function server(value, now, client)
    if (client ~= false) then MOCK.player.status = value; end
    incoming(MOCK.status_packet(MOCK.player.server_id, value), now);
end
local function round(now)
    incoming(MOCK.action_packet(1001, 1, 0, MOB, { { message = 1 } }), now);
end
local function command(text) MOCK.fire('command', { command = '/cadence ' .. text }); end
local function frame(now) MOCK.now = now; MOCK.frame(0); end
server(0, 0);
server(1, 1); round(4); server(0, 5);
check('retention is off by default', attack.reengage_progress(5) == nil);
command('attack reengage on');
command('enemy off');
server(1, 10); round(13); server(0, 14);
local retained = attack.info(14).reengage;
check('confirmed departure keeps a five-second estimate from an eight-second round',
    retained and close(retained.duration, 5) and retained.started == 14, retained and retained.duration);
check('retained timer stays inactive and preserves the last battle target', not attack.is_active()
    and retained and retained.last_target == MOB);
frame(14.1);
check('retention draws with the enemy timer disabled', retained_draws > 0);
incoming(MOCK.assist_packet(1001, MOB + 1), 14.2);
incoming(MOCK.message_packet(1001, MOB, 0, 0, 94), 14.3);
incoming(MOCK.message_packet(1001, MOB, 0, 0, 6), 14.4);
server(0, 14.5);
check('assist wait-longer defeat and repeated idle do not restart retention',
    attack.info(14.5).reengage.started == 14 and attack.info(14.5).reengage.deadline == 19);
MOCK.player.status = 1;
frame(14.6);
check('client animation alone cannot end retained server-idle timing', not attack.is_active()
    and attack.reengage_progress(14.6) ~= nil);
MOCK.player.status = 0;
MOCK.items[16535].Delay = 120;
command('relearn attack'); frame(15);
check('idle equipment and relearning cannot move the saved deadline', attack.info(15).reengage.deadline == 19);
frame(18);
check('automatic visibility follows the countdown', attack.reengage_progress(18) ~= nil);
check('elapsed interval has a short visible finish', attack.reengage_progress(19.1).elapsed);
check('retained interval expires without another packet', attack.reengage_progress(19.5) == nil);

MOCK.items[16535].Delay = 480;
server(1, 20); round(23);
incoming(MOCK.action_packet(1001, 8, 0x6163, MOB, { { message = 327 } }), 24);
incoming(MOCK.message_packet(1001, MOB, 0, 0, 6), 24.1);
check('target death while still engaged does not start retention', attack.is_active() and attack.reengage_progress(24.1) == nil);
server(0, 27);
check('held cleanup anchors at confirmed departure', attack.info(27).reengage.started == 27
    and attack.info(27).reengage.holding == 'spell');
server(1, 27.5);
check('re-engage immediately restores the first-attack timer', attack.is_active()
    and attack.reengage_progress(27.5) == nil and close(attack.info(27.5).next_in, 2.8));
round(31);
local samples = attack.info(31).samples;
incoming(MOCK.assist_packet(1001, MOB + 2), 31.1);
server(1, 31.2);
check('same-engagement target changes do not reset phase or learn idle time', close(attack.info(31.2).next_in, 7.8)
    and attack.info(31.2).samples == samples);

MOCK.settings.current.style.shared_spot = true;
MOCK.player.status = 33;
attack_draws, resting_draws = 0, 0;
frame(31.3);
check('resting takes drawing priority before the next server status arrives', attack_draws == 0 and resting_draws == 1);
server(33, 31.4);
check('resting transition never creates a retained cooldown', attack.reengage_progress(31.4) == nil);
server(1, 40); round(43); server(2, 44);
check('death clears instead of retaining a cooldown', attack.reengage_progress(44) == nil);

server(0, 50); server(1, 51); round(54);
for _, flag in ipairs({ 'blocked', 'injected', 'is_injected', 'blocked_original' }) do
    local event = MOCK.status_packet(1001, 0); event[flag] = true;
    incoming(event, 54.1);
end
incoming(MOCK.status_packet(2002, 0), 54.2);
check('blocked injected and other-character status cannot end combat', attack.is_active());
server(0, 55); command('attack reengage off');
check('turning retention off clears an existing estimate', attack.reengage_progress(55) == nil);
command('attack reengage on');
server(1, 60); round(63); server(0, 64);
MOCK.zoning = true; frame(64.1); MOCK.zoning = false;
check('missing player during zoning clears retained display', attack.reengage_progress(64.1) == nil);
incoming(MOCK.zone_packet(1001, 100), 65);
server(0, 65.1);
check('zone reset cannot recreate the preceding cooldown', attack.reengage_progress(65.1) == nil);
server(1, 66); round(69); server(0, 70);
MOCK.settings.switch_character(MOCK.settings.current);
MOCK.player.status = 0; frame(70.1);
check('character settings clear retained timing and old server state', not attack.is_active()
    and attack.reengage_progress(70.1) == nil);

incoming(MOCK.zone_packet(1001, 100), 75);
server(1, 76); server(0, 77);
check('joined-late combat remains unknown until a round is seen', attack.reengage_progress(77).unknown);
incoming(MOCK.zone_packet(1001, 100), 80);
server(0, 81);
check('loading already idle does not manufacture a countdown', attack.reengage_progress(81) == nil);

MOCK.player.equipment[0], MOCK.player.equipment[4] = 18206, 15174;
MOCK.items[18206] = { Delay = 504, Skill = 6 };
MOCK.items[15174] = { Delay = 0, Skill = 0 };
server(1, 85);
local initial = attack.info(85);
check('first interval is sampled before drawn-weapon haste latents', close(initial.sampled_delay, 8.4), initial.sampled_delay);
check('counterfactual sampling leaves the live drawn model intact', require('core.stat_state').info().haste_gear > 0);
server(0, 86);
check('departure before the first round uses the sheathed sample', close(attack.info(86).reengage.duration, 5.4));

MOCK.player.equipment[0], MOCK.player.equipment[4] = 16535, 0;
for i, kind in ipairs({ 'melee', 'failed round' }) do
    local start = 90 + (i - 1) * 40;
    command('relearn attack');
    server(1, start);
    for _, offset in ipairs({ 3, 11, 19, 27 }) do round(start + offset); end
    check(kind .. ' transition fixture has three calibrated gaps', attack.info(start + 27).samples == 3);
    incoming({ id = 0x050, data = string.rep(string.char(0), 8), size = 8 }, start + 34.9);
    if (kind == 'melee') then
        round(start + 35);
    else
        incoming(MOCK.action_packet(1001, 4, 0, MOB, { { message = 84 } }), start + 35);
    end
    check(kind .. ' samples while equipment is still settling', require('core.stat_state').info().transition);
    server(0, start + 35.05);
    local pending = attack.info(start + 35.05).reengage;
    check(kind .. ' cannot use old calibration during a pending equipment change',
        pending and pending.unknown and pending.sampled_delay == nil and pending.duration == nil);
end

local reads, original_read = 0, player.read_loadout;
player.read_loadout = function (...) reads = reads + 1; return original_read(...); end;
command('hide');
for _ = 1, 60 do MOCK.frame(1 / 60); end
check('hidden retained frames add no inventory/loadout polling', reads == 0, reads);
check('tracking sends no game commands', #MOCK.commands == 0);
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
