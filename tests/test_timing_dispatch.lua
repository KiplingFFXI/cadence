-- Normal packet dispatch keeps attack suspension separate from the action recovery bar.
local out, failures = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failures = failures + 1; end
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 0.001; end
MOCK.player.status = 0;
MOCK.player.equipment[0] = 16535;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
local player = require('core.player');
local loadout_reads, buff_reads = 0, 0;
local read_loadout, read_buffs = player.read_loadout, player.read_buffs;
player.read_loadout = function(...) loadout_reads = loadout_reads + 1; return read_loadout(...); end;
player.read_buffs = function(...) buff_reads = buff_reads + 1; return read_buffs(...); end;
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local attack, recovery = require('core.attack'), require('core.recovery');
local function frame(now) MOCK.now = now; MOCK.frame(0); end
local function command(text) MOCK.fire('command', { command = '/cadence ' .. text }); end
local function incoming(e, now) MOCK.now = now; MOCK.fire('packet_in', e); end
local sequence = 0;
local function action(category, param, message, animation, result_param)
    local e = MOCK.action_packet(1001, category, param, 1001,
        { { message = message or 0, animation = animation or 0, damage = result_param or 0 } });
    sequence = sequence + 1;
    e.data_raw[2], e.data_raw[3] = sequence % 256, math.floor(sequence / 256);
    e.data = MOCK.to_string(e.data_raw);
    return e;
end
local function fresh(now)
    MOCK.player.status = 0; incoming(MOCK.status_packet(1001, 0), now - 1); frame(now - 1);
    MOCK.player.status = 1; incoming(MOCK.status_packet(1001, 1), now); frame(now);
    recovery.reset();
end
local function left(now) return select(2, attack.progress(now)); end
command('recovery on');
fresh(100);
incoming(action(3, 68, 100, 214), 102.7);
check('Super Jump holds attacks for five seconds through normal dispatch', near(left(105), 2.8));
check('Super Jump has its own action recovery estimate too', near(recovery.progress(105).left, 2.7));
fresh(120);
incoming(action(3, 68, 185, 50), 122.7);
check('the weapon skill sharing Super Jump ID keeps its own animation tail', near(left(122.7), 2.933)
    and near(recovery.progress(122.7).left, 2.833));
for i, case in ipairs({ { 32, 1, 1.5 }, { 1, 16, 1.916 } }) do
    local now = 125 + i * 4;
    fresh(now);
    incoming(action(3, case[1], 185, case[2]), now + 2.7);
    check('weapon skill ' .. case[1] .. ' uses its source duration for both timers',
        near(left(now + 2.7), case[3] + 0.1) and near(recovery.progress(now + 2.7).left, case[3]));
end
fresh(140);
incoming(action(6, 35, 100, 3), 142.7);
check('an ordinary ability delays attacks without inventing global recovery', near(left(142.7), 2.1)
    and recovery.progress(142.7) == nil);
for i, case in ipairs({ { 4606, 5 }, { 4112, 0.4 } }) do
    local now = 160 + i * 20;
    fresh(now);
    incoming(action(9, 0x6163, 28, 0, case[1]), now + 2.7);
    incoming(action(5, case[1], 24, 11), now + 5.7);
    check('item ' .. case[1] .. ' uses its own attack tail', near(left(now + 5.7), case[2] + 0.1));
end
fresh(220);
incoming(action(9, 0x6163, 28, 0, 4352), 222.7);
incoming(action(5, 4352, 24, 30), 225.7);
local _, unknown_left, _, _, why = attack.progress(240);
check('an unvalidated item cannot become Ready after its notice expires', unknown_left == nil and why == 'recovery'
    and recovery.progress(240) == nil);
incoming(action(6, 35, 100, 3), 241);
check('a subsequent accepted ability resolves unknown timing using the preserved phase', near(left(241), 2.1));
for i, case in ipairs({ { 57, 2 }, { 793, 1 }, { 830, 4 } }) do
    local now = 260 + i * 20;
    fresh(now);
    incoming(action(8, 0x6163, 327, 0, case[1]), now + 2.7);
    incoming(action(4, case[1], 230), now + 5.7);
    check('spell ' .. case[1] .. ' separates source attack animation from the global gate',
        near(left(now + 5.7), case[2] + 0.1) and near(recovery.progress(now + 5.7).left, math.max(2.5, case[2])));
end
fresh(330);
incoming(action(8, 0x6163, 327, 0, 65535), 332.7);
incoming(action(4, 65535, 230), 335.7);
check('an unknown spell animation leaves both recovery estimates unknown', left(335.7) == nil
    and recovery.progress(335.7).known == false and recovery.progress(335.7).left == nil);
fresh(340);
incoming(action(12, 0x6163), 342.7);
incoming(action(2, 0, 352, 26), 345.7);
check('a ranged shot uses its return-weapon delay', near(left(345.7), 0.9) and near(recovery.progress(345.7).left, 0.8));
for i, category in ipairs({ 8, 9, 12 }) do
    local now = 360 + i * 20;
    fresh(now);
    incoming(action(category, 0x6163, 327, 0, category == 8 and 57 or 4606), now + 2.7);
    incoming(action(category, 0x7073, 0, 0, category == 8 and 57 or 0), now + 3.7);
    local _, remaining, _, _, held = attack.progress(now + 30);
    check('interrupt category ' .. category .. ' does not invent an exact remaining suspension', remaining == nil and held == 'recovery');
    incoming(action(1, 0, 1), now + 31);
    check('an observed attack resolves interrupted category ' .. category, near(left(now + 31), 4));
end
for i, message in ipairs({ 84, 106 }) do
    local now = 425 + i * 10;
    fresh(now);
    incoming(action(8, 0x6163, 327, 0, 57), now + 2.7);
    incoming(action(4, 57, message), now + 3.7);
    check('a failed spell finish keeps the pending cast for its interrupt ' .. message,
        attack.info(now + 3.7).holding == 'spell' and recovery.progress(now + 3.7) == nil);
    incoming(action(8, 0x7073, 0, 0, 57), now + 3.8);
    check('the following spell interrupt preserves unknown timing ' .. message, left(now + 30) == nil);
end
fresh(456);
for _, category in ipairs({ 8, 9, 12 }) do
    for _, message in ipairs({ 84, 106 }) do
        incoming(action(category, 0x6163, message), 457);
        check('a failed start cannot freeze attacks ' .. category .. '/' .. message,
            attack.info(457).holding == nil and near(left(457), 1.8));
    end
end
fresh(460);
local unchanged = left(462);
incoming(MOCK.action_packet(1001, 3, 68, nil, nil), 462);
incoming(MOCK.action_packet(1001, 8, 0x6163, 1001, {}), 462);
check('empty result packets cannot alter a running attack timer', near(left(462), unchanged));
command('attack off'); frame(463);
incoming(action(3, 68, 100, 214), 464);
command('attack on'); frame(465);
check('reenabling attacks during combat waits for a real round', attack.is_active() and left(465) == nil);
incoming(action(1, 0, 1), 466);
check('the first round after reenabling starts the current delay', near(left(466), 4));
for _, timer in ipairs({ 'attack', 'resting', 'enemy', 'enemycast', 'recovery' }) do command(timer .. ' off'); end
require('ui.settings_window').set_open(false);
frame(470); loadout_reads, buff_reads = 0, 0;
for i = 1, 600 do frame(470 + i / 60); end
incoming(action(1, 0, 1), 480);
incoming(MOCK.vitals_packet(1001, 100, 0, 100), 480.1);
check('all timers off while engaged performs no loadout or buff polling', loadout_reads == 0 and buff_reads == 0,
    loadout_reads .. '/' .. buff_reads);
command('attack on'); frame(481);
check('enabling after all-off frames still waits for the current combat phase', attack.is_active() and left(481) == nil);
incoming(action(1, 0, 1), 482);
check('the all-off gap is discarded when a new round arrives', near(left(482), 4));
local errors = false;
for _, line in ipairs(MOCK.printed) do errors = errors or line:find('Drawing stopped', 1, true) ~= nil; end
check('dispatch adds no drawing errors or game commands', not errors and #MOCK.commands == 0);
out[#out + 1] = failures == 0 and 'ALL PASSED' or (failures .. ' FAILED');
return table.concat(out, '\n');
