-- Own completed actions drive recovery independently of combat and saved layouts.
local out, fails = {}, 0;
local function check(name, value, detail)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not value) then fails = fails + 1; end
end
local function close(a, b) return a ~= nil and math.abs(a - b) < 0.002; end
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local recovery, attack, hud = require('core.recovery'), require('core.attack'), require('ui.hud');
local function incoming(event, now) MOCK.now = now; MOCK.fire('packet_in', event); end
local function command(text) MOCK.fire('command', { command = '/cadence ' .. text }); end
local function frame(now) MOCK.now = now; MOCK.frame(0); end
local sequence = 0;
local function action(category, param, message, actor, animation)
    local event = MOCK.action_packet(actor or MOCK.player.server_id, category, param, 1001,
        { { message = message or 230, animation = animation or 0 } });
    sequence = sequence + 1;
    event.data_raw[2], event.data_raw[3] = sequence % 256, math.floor(sequence / 256);
    event.data = MOCK.to_string(event.data_raw);
    return event;
end
local function left(now) local view = recovery.progress(now); return view and view.left; end
MOCK.player.status = 0;
incoming(MOCK.status_packet(1001, 0), 0);
incoming(action(4, 57), 1);
check('the new timer starts off and ignores earlier finishes', not MOCK.settings.current.recovery.enabled and recovery.progress(1) == nil);
command('recovery on');
check('enabling does not invent a previous completed action', MOCK.settings.current.recovery.enabled and recovery.progress(1) == nil);
incoming(action(4, 57), 2);
check('a completed spell starts recovery while idle', close(left(2), 2.5) and not attack.is_active());
check('the estimate identifies spell recovery', recovery.progress(2).kind == 'spell' and recovery.progress(2).estimated);
incoming(MOCK.message_packet(1001, 1001, 0, 0, 18), 2.2);
check('a rejected retry does not restart recovery', close(left(2.2), 2.3));
incoming(action(8, 0x7073, 16), 2.3);
check('an interrupt does not restart or shorten another active gate', close(left(2.3), 2.2));
incoming(action(8, 0x6163, 327), 2.4);
check('an accepted new cast clears the previous estimate', recovery.progress(2.4) == nil);
incoming(action(8, 0x7073, 16), 2.5);
check('an interrupted cast starts no new recovery', recovery.progress(2.5) == nil);

for _, message in ipairs({ 84, 106 }) do
    incoming(action(4, 57, message), 3);
    check('failed cast with real spell id is excluded for message ' .. message, recovery.progress(3) == nil);
end
incoming(action(4, 0, 84), 3.1);
incoming(action(4, 0, 78), 3.2);
incoming(action(6, 32, 100, nil, 28), 3.3);
check('failed auto attacks weapon skills and ordinary abilities create no invented gate', recovery.progress(3.3) == nil);
incoming(action(4, 57, 75, 2002), 3.4);
check('another player cannot start the timer', recovery.progress(3.4) == nil);
for _, flag in ipairs({ 'blocked', 'injected' }) do
    local event = action(4, 57); event[flag] = true; incoming(event, 4);
    check(flag .. ' result is ignored', recovery.progress(4) == nil);
end
local short = action(4, 57); short.size = 15; short.data = short.data:sub(1, 15); incoming(short, 4.1);
incoming(MOCK.action_packet(1001, 4, 57, nil, nil), 4.2);
check('truncated and empty action results cannot create recovery', recovery.progress(4.2) == nil);

for _, message in ipairs({ 75, 85, 236 }) do
    recovery.reset(); incoming(action(4, 57, message), 5);
    check('completed no-effect or resisted outcome still starts recovery ' .. message, close(left(5), 2.5));
end
recovery.reset();
local cast_start = action(8, 0x6163, 327);
incoming(cast_start, 9);
local repeated = action(4, 57);
incoming(repeated, 10); incoming(repeated, 10.7);
check('a duplicate finish keeps the original deadline', close(left(10.7), 1.8));
incoming(cast_start, 10.8);
check('a delayed duplicate cast start cannot clear the completed recovery', close(left(10.8), 1.7));
frame(12.6); incoming(repeated, 12.7);
check('a delayed duplicate cannot bring an expired timer back', recovery.progress(12.7) == nil);
incoming(action(3, 1, 185, nil, 16), 13);
check('Combo uses its source animation duration', close(left(13), 1.916) and recovery.progress(13).kind == 'weaponskill');

local drawn, drawn_left = 0;
local original_draw = hud.draw_recovery;
hud.draw_recovery = function(view) drawn, drawn_left = drawn + 1, view.left; return original_draw(view); end;
command('attack off'); command('resting off'); command('enemy off');
frame(13.2);
check('recovery draws with all other timers disabled', drawn == 1 and close(drawn_left, 1.716));
command('hide'); frame(13.4);
check('hide suppresses drawing but keeps its deadline', drawn == 1 and close(left(13.4), 1.516));
command('hide'); frame(15);
check('expiry automatically hides without a ready message', drawn == 1 and recovery.progress(15) == nil);
incoming(action(4, 57), 16); command('recovery off'); command('recovery on');
check('off clears recovery and on does not resurrect it', recovery.progress(16) == nil);

incoming(action(4, 57), 20);
incoming(MOCK.status_packet(1001, 2), 20.1);
check('server death clears immediately before a frame', recovery.progress(20.1) == nil);
incoming(action(4, 57), 20.2);
check('a late result while dead stays hidden', recovery.progress(20.2) == nil);
incoming(MOCK.status_packet(1001, 0), 21);
incoming(action(4, 57), 22);
MOCK.player.status = 2; frame(22.1);
check('client death clears even before server status catches up', recovery.progress(22.1) == nil);
MOCK.player.status = 0;
incoming(action(4, 57), 23); incoming(MOCK.zone_packet(1001), 23.1);
check('zoning clears recovery', recovery.progress(23.1) == nil);
incoming(action(4, 57), 24);
MOCK.settings.callbacks.cadence_settings_update(MOCK.settings.current);
check('character settings reload clears recovery', recovery.progress(24) == nil);

-- Attachment changes the drawing position, not which actions start recovery.
local s = MOCK.settings.current;
local joins, attack_draws = {}, 0;
local original_join, original_attack = hud.join_below, hud.draw_attack;
hud.join_below = function(enemy_attached, recovery_attached)
    joins[1], joins[2] = enemy_attached, recovery_attached;
    return original_join(enemy_attached, recovery_attached);
end;
hud.draw_attack = function(...) attack_draws = attack_draws + 1; return original_attack(...); end;
command('attack on');
s.attack.x, s.attack.y, s.attack.width = 120, 120, 260;
s.recovery.x, s.recovery.y, s.recovery.width = 600, 400, 340;
hud.refresh(s);
local standalone_width = hud.element_size('recovery');
command('recovery attach on'); hud.place_all();
incoming(action(4, 57), 25);
local before_drawn = drawn;
frame(25.1);
local attack_width, attack_height = hud.element_size('attack');
local recovery_width, recovery_height = hud.element_size('recovery');
local recovery_pos = MOCK.positions['##cadence_recovery'];
check('live recovery attaches while the enabled auto attack host is idle and hidden',
    drawn == before_drawn + 1 and attack_draws == 0 and joins[2] == true
    and recovery_pos and close(recovery_pos[1], 120) and close(recovery_pos[2], 120 + attack_height - 1)
    and close(recovery_width, attack_width), ('draws %d/%d, host %d, attached %s, position %s, width %s, host height %s')
        :format(drawn, before_drawn, attack_draws, tostring(joins[2]), recovery_pos and table.concat(recovery_pos, ',') or 'nil',
            tostring(recovery_width), tostring(attack_height)));

local mob = 0x01000200;
MOCK.entities[0x200] = { ServerId = mob, Name = 'Young Quadav', Status = 1, SpawnFlags = 0x10 };
MOCK.player.target_index = 0x200;
command('enemy on'); command('enemy attach on');
incoming(MOCK.action_packet(mob, 1, 0, MOCK.player.server_id, { { message = 1 } }), 25.2);
frame(25.3);
local enemy_pos = MOCK.positions['##cadence_enemy'];
check('a visible recovery strip sits before the attached enemy strip', joins[1] == true and joins[2] == true
    and enemy_pos and close(enemy_pos[2], 120 + attack_height + recovery_height - 2));
before_drawn = drawn;
frame(27.5);
enemy_pos = MOCK.positions['##cadence_enemy'];
check('expired recovery removes its attachment and leaves no gap above the enemy', drawn == before_drawn
    and recovery.progress(27.5) == nil and joins[1] == true and not joins[2]
    and enemy_pos and close(enemy_pos[2], 120 + attack_height - 1));

incoming(action(4, 57), 28); command('attack off');
before_drawn = drawn; frame(28.1);
recovery_pos = MOCK.positions['##cadence_recovery'];
recovery_width = hud.element_size('recovery');
check('turning auto attack off uses recovery\'s standalone position and width', drawn == before_drawn + 1
    and not joins[2] and recovery_pos and close(recovery_pos[1], 600) and close(recovery_pos[2], 400)
    and close(recovery_width, standalone_width) and s.recovery.attached and s.recovery.enabled,
    ('draws %d/%d, joined %s, position %s, width %s, attached %s, enabled %s'):format(drawn, before_drawn,
        tostring(joins[2]), recovery_pos and table.concat(recovery_pos, ',') or 'nil', tostring(recovery_width),
        tostring(s.recovery.attached), tostring(s.recovery.enabled)));
command('recovery attach off'); command('enemy off');
MOCK.player.target_index, MOCK.entities[0x200] = 0, nil;
require('core.enemy').reset();
hud.join_below, hud.draw_attack = original_join, original_attack;

command('recovery width 321'); command('recovery height 1.2'); command('recovery source off');
command('recovery labeltext Cooldown'); command('color recovery_fill_start 123456');
check('new timer commands preserve independent settings', MOCK.settings.current.recovery.width == 321
    and close(MOCK.settings.current.recovery.height_scale, 1.2) and not MOCK.settings.current.recovery.show_source
    and MOCK.settings.current.recovery.label_text == 'Cooldown');
command('resetsection recovery');
check('section reset includes the new timer', not MOCK.settings.current.recovery.enabled and MOCK.settings.current.recovery.width == 240);
command('undo');
check('section undo restores recovery choices', MOCK.settings.current.recovery.enabled and MOCK.settings.current.recovery.width == 321);
command('preview recovery'); frame(30);
check('forced preview can show recovery without a real action', drawn > 1 and recovery.progress(30) == nil);
require('ui.settings_window').set_open(false);
local player, reads, buff_reads = require('core.player'), 0, 0;
local read_loadout, read_buffs = player.read_loadout, player.read_buffs;
player.read_loadout = function(...) reads = reads + 1; return read_loadout(...); end;
player.read_buffs = function(...) buff_reads = buff_reads + 1; return read_buffs(...); end;
incoming(action(4, 57), 40);
reads, buff_reads = 0, 0;
for i = 1, 60 do frame(40 + i / 60); end
check('recovery-only frames add no gear or buff polling', reads == 0 and buff_reads == 0, reads .. '/' .. buff_reads);

-- A start only supersedes recovery when the complete packet confirms the accepted action.
for i, category in ipairs({ 8, 9, 12 }) do
    local now = 50 + i * 4;
    recovery.reset(); incoming(action(4, 57), now);
    local truncated = action(category, 0x6163, 327);
    truncated.size, truncated.data = 33, truncated.data:sub(1, 33);
    incoming(truncated, now + 0.1);
    incoming(MOCK.action_packet(1001, category, 0x6163, nil, nil), now + 0.2);
    incoming(MOCK.action_packet(1001, category, 0x6163, 1001, {}), now + 0.3);
    check('truncated and empty starts preserve recovery for category ' .. category, close(left(now + 0.3), 2.2));
    for _, message in ipairs({ 84, 106 }) do incoming(action(category, 0x6163, message), now + 0.4); end
    check('failed starts preserve recovery for category ' .. category, close(left(now + 0.4), 2.1));
    incoming(action(category, 0x6163, 327), now + 0.5);
    check('a complete accepted start clears recovery for category ' .. category, recovery.progress(now + 0.5) == nil);
end

for i, case in ipairs({
    { 'ranged attacks with zero header parameter', 2, 0, 352, 26, 0.8, 'ranged' },
    { 'Super Jump', 3, 68, 100, 214, 5, 'superjump' },
    { 'Spinning Axe sharing the Super Jump id', 3, 68, 185, 50, 2.833, 'weaponskill' },
    { 'validated timed items', 5, 4606, 24, 11, 5, 'item' },
}) do
    local now = 70 + i * 6;
    recovery.reset(); incoming(action(case[2], case[3], case[4], nil, case[5]), now);
    local observed = recovery.progress(now);
    check(case[1] .. ' use the confirmed action duration', observed and observed.known and observed.estimated
        and close(observed.left, case[6]) and observed.kind == case[7]);
end
for i, case in ipairs({
    { 'Provoke', 6, 35, 100, 3 },
    { 'Potion', 5, 4112, 24, 30 },
}) do
    local now = 100 + i * 4;
    recovery.reset(); incoming(action(4, 57), now);
    incoming(action(case[2], case[3], case[4], nil, case[5]), now + 0.1);
    check(case[1] .. ' clears an older estimate without inventing a countdown', recovery.progress(now + 0.1) == nil);
end

command('recovery seconds off'); command('recovery source off'); command('recovery label off');
command('recovery numbers off');
for i, case in ipairs({ { 5, 4352, 30, 'item' }, { 3, 68, 4095, 'unknown' } }) do
    local now = 120 + i * 6;
    recovery.reset(); incoming(action(case[1], case[2], 24, nil, case[3]), now);
    local observed = recovery.progress(now);
    check('unvalidated ' .. case[4] .. ' timing has an explicit unknown state', observed and observed.known == false
        and observed.left == nil and observed.duration == nil and observed.fill == 0 and observed.kind == case[4]);
    MOCK.imgui_calls, MOCK.record_imgui = {}, true; frame(now + 0.1); MOCK.record_imgui = false;
    local unknown_visible, number_visible = false, false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'dl:AddText') then
            unknown_visible = unknown_visible or call[6] == 'Unknown';
            number_visible = number_visible or call[6]:find('~', 1, true) ~= nil;
        end
    end
    check('unknown ' .. case[4] .. ' timing remains visible with every recovery readout off', unknown_visible and not number_visible);
    frame(now + 5);
    check('unknown ' .. case[4] .. ' notice expires without a ready claim', recovery.progress(now + 5) == nil);
end
check('feature sends no game commands', #MOCK.commands == 0);
if (fails > 0) then out[#out + 1] = ('\n%d FAILED'):format(fails); else out[#out + 1] = 'ALL PASSED'; end
return table.concat(out, '\n');
