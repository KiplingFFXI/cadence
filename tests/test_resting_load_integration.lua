-- An ongoing rest stays observable across loading, zoning and hidden timer settings.
local out, failures = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failures = failures + 1; end
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 0.001; end
MOCK.now, MOCK.player.status, MOCK.player.hp_max = 100, 33, 1000;
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local resting, hud = require('core.resting'), require('ui.hud');
local function frame(now) MOCK.now = now; MOCK.frame(0); end
local function command(text) MOCK.fire('command', { command = '/cadence ' .. text }); end
local function incoming(e, now) MOCK.now = now; MOCK.fire('packet_in', e); end
local function vitals(now, hp, tp) incoming(MOCK.vitals_packet(1001, hp, 0, tp or 0), now); end
local displayed;
local draw_resting = hud.draw_resting;
hud.draw_resting = function(view)
    displayed = { left = view.left, unknown = view.phase_unknown, full = view.full };
    return draw_resting(view);
end;
vitals(100, 100, 900);
MOCK.imgui_calls, MOCK.record_imgui = {}, true; frame(100.1); MOCK.record_imgui = false;
local observing = false;
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'dl:AddText' and call[6] == 'Observing') then observing = true; end
end
check('cold loading while resting draws Observing with no numeric countdown', observing and displayed
    and displayed.unknown and displayed.left == nil);
vitals(102, 120, 800); frame(102.1);
check('the first tick after reload establishes timing immediately', resting.info(102.1).accepted == 1
    and not displayed.unknown and near(resting.seen_at(), 102));
vitals(111, 141, 700); vitals(120, 163, 600); frame(120.1);
check('subsequent packet gaps establish the ongoing pattern', resting.pattern_known() and near(resting.info(120.1).next_tick, 132));
MOCK.player.status = 0; frame(130);
MOCK.player.status = 33; frame(131);
check('a new sit observed after loading gets the ordinary first-tick countdown', not resting.info(131).phase_unknown
    and near(resting.info(131).next_tick, 152.4));
vitals(133, 183, 500);
check('an early gain on a new sit cannot reset that countdown', resting.info(133).accepted == 0
    and near(resting.info(133).next_tick, 152.4));
incoming(MOCK.zone_packet(1001), 150); vitals(150.1, 200, 400); frame(150.2);
check('a first resting observation after zone reset also keeps phase unknown', resting.info(150.2).phase_unknown);
vitals(152, 225, 300); frame(152.1);
check('the next post-zone tick restores the ongoing timing', not resting.info(152.1).phase_unknown and resting.info(152.1).accepted == 1);
for _, timer in ipairs({ 'attack', 'resting', 'enemy', 'enemycast', 'recovery' }) do command(timer .. ' off'); end
MOCK.player.status = 0; frame(160);
MOCK.player.status = 33; frame(161);
vitals(182, 235, 200); frame(182.1);
check('all timers disabled still observes a genuine rest and its first tick', resting.is_active()
    and not resting.info(182.1).phase_unknown and resting.info(182.1).accepted == 1);
command('resting on'); frame(183);
check('reenabling resting keeps the observed phase instead of restarting it', displayed and not displayed.unknown
    and resting.info(183).accepted == 1 and near(resting.seen_at(), 182));
for _, timer in ipairs({ 'attack', 'resting', 'enemy', 'enemycast', 'recovery' }) do command(timer .. ' off'); end
MOCK.player.status = 0; frame(190); frame(195);
command('resting on'); frame(196);
check('a stand while disabled prevents a stale resting timer on reenable', not resting.is_active());
MOCK.player.status = 0; incoming(MOCK.zone_packet(1001), 200); frame(200.1);
MOCK.player.status = 33; frame(201);
check('an observed standing state after zoning makes the next sit fresh', not resting.info(201).phase_unknown
    and near(resting.info(201).next_tick, 222.4));
local errors = false;
for _, line in ipairs(MOCK.printed) do errors = errors or line:find('Drawing stopped', 1, true) ~= nil; end
check('resting lifecycle adds no drawing errors or game commands', not errors and #MOCK.commands == 0);
out[#out + 1] = failures == 0 and 'ALL PASSED' or (failures .. ' FAILED');
return table.concat(out, '\n');
