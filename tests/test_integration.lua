-- Runs the whole addon inside the mock and checks what it draws, saves and never does.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;

MOCK.items[16535] = { Delay = 240, Skill = 3 };        -- a 240 delay sword
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');

local function balance_report()
    local counts = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        local name = call[1];
        local n = 1;
        if (name == 'PopStyleVar' or name == 'PopStyleColor') then n = call[2] or 1; end
        counts[name] = (counts[name] or 0) + n;
    end
    local function c(k) return counts[k] or 0; end
    local problems = {};
    local pairs_ = {
        { 'Begin', 'End' }, { 'PushStyleVar', 'PopStyleVar' }, { 'PushStyleColor', 'PopStyleColor' },
        { 'PushFont', 'PopFont' }, { 'PushTextWrapPos', 'PopTextWrapPos' },
    };
    for _, p in ipairs(pairs_) do
        if (c(p[1]) ~= c(p[2])) then table.insert(problems, ('%s %d vs %s %d'):format(p[1], c(p[1]), p[2], c(p[2]))); end
    end
    if (c('BeginTabBar') ~= c('EndTabBar')) then table.insert(problems, 'tab bar'); end
    if (c('BeginTabItem') ~= c('EndTabItem')) then table.insert(problems, 'tab item'); end
    return problems, counts;
end

local function frames(n, dt)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do MOCK.frame(dt); end
    MOCK.record_imgui = false;
    local problems, counts = balance_report();
    return problems, counts;
end

local function windows_named(name)
    local n = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'Begin' and call[2] == name) then n = n + 1; end
    end
    return n;
end

local function errors_printed()
    for _, line in ipairs(MOCK.printed) do
        if (line:find('Drawing stopped')) then return line; end
    end
    return nil;
end

-- Idle, nothing is drawn.
MOCK.now = 10;
local problems = frames(30);
check('idle draws nothing', #MOCK.imgui_calls == 0 or windows_named('##cadence_attack') == 0, #MOCK.imgui_calls);

-- Engaged, the auto attack timer shows.
MOCK.player.status = 1;
problems = frames(10);
check('engaged draws the auto attack timer', windows_named('##cadence_attack') == 10, windows_named('##cadence_attack'));
check('engaged balanced', #problems == 0, table.concat(problems, '; '));

-- Your melee round arrives.
local blocked = false;
local function packet(e) e.blocked = false; MOCK.fire('packet_in', e); if (e.blocked) then blocked = true; end end
packet(MOCK.action_packet(1001, 1, 0x306B7461, 0x01000200, { { message = 1 }, { message = 15 } }));
problems = frames(5);
check('after round balanced', #problems == 0, table.concat(problems, '; '));

-- A job ability, a spell start and finish, a paralysis.
packet(MOCK.action_packet(1001, 6, 35, 1001, { { message = 100 } }));
packet(MOCK.action_packet(1001, 8, 0x68776163, 1001, { { message = 327 } }));
frames(5);
packet(MOCK.action_packet(1001, 4, 1, 1001, { { message = 230 } }));
packet(MOCK.action_packet(1001, 4, 0, 0x01000200, { { message = 84 } }));
problems = frames(5);
check('actions balanced', #problems == 0, table.concat(problems, '; '));

-- Out of range message.
packet(MOCK.message_packet(1001, 0x01000200, 0, 0, 4, 0x200));

-- Resting.
MOCK.player.status = 33;
MOCK.player.mp_max = 400;
packet(MOCK.vitals_packet(1001, 600, 100, 0));
problems = frames(10);
check('resting draws the resting timer', windows_named('##cadence_resting') == 10, windows_named('##cadence_resting'));
check('resting hides the auto attack timer', windows_named('##cadence_attack') == 0, windows_named('##cadence_attack'));
MOCK.now = MOCK.now + 21;
packet(MOCK.vitals_packet(1001, 612, 112, 0));
problems = frames(3);
check('resting tick balanced', #problems == 0, table.concat(problems, '; '));

-- cadence sends nothing and hides nothing. /check and /checkparam replies pass straight through.
MOCK.player.status = 1;
MOCK.entities[0x200] = { ServerId = 0x01000200, Name = 'Goblin Tinkerer', Status = 1 };
local passed = 0;
for _, msg in ipairs({ { 0x01000200, 42, 68, 174 }, { 1001, 300, 0, 712 }, { 1001, 250, 0, 715 } }) do
    local reply = MOCK.message_packet(1001, msg[1], msg[2], msg[3], msg[4], 0x200);
    reply.blocked = false;
    MOCK.fire('packet_in', reply);
    if (not reply.blocked) then passed = passed + 1; end
end
frames(200, 1 / 60);
check('check replies pass through', passed == 3, passed);
check('never sends a command', #MOCK.commands == 0, #MOCK.commands);
local printed_before = #MOCK.printed;
MOCK.fire('command', { command = '/cadence check' });
check('check isn\'t a command', #MOCK.printed == printed_before + 1
    and (MOCK.printed[printed_before + 1] or ''):find('Didn\'t recognize "check". Type /cadence help', 1, true) ~= nil,
    MOCK.printed[printed_before + 1]);

-- Settings window with previews.
local saves_before = MOCK.saved;
MOCK.fire('command', { command = '/cadence' });
problems, counts = frames(5);
check('config window drawn', windows_named('cadence##cadence_settings') == 5, windows_named('cadence##cadence_settings'));
check('preview draws both timers', windows_named('##cadence_attack') == 5 and windows_named('##cadence_resting') == 5);
check('config balanced', #problems == 0, table.concat(problems, '; '));
check('no save while just looking', MOCK.saved == saves_before, MOCK.saved - saves_before);

-- Shift + drag moves an element and saves once on release.
MOCK.key_shift = true;
MOCK.window_pos['##cadence_attack'] = { 900, 500 };
MOCK.mouse_down = true;
frames(3);
local s = MOCK.settings.current;
check('drag moved the auto attack timer', s.attack.x == 900 and s.attack.y == 500, s.attack.x .. ',' .. s.attack.y);
local saves_mid = MOCK.saved;
MOCK.mouse_down = false;
frames(1);
check('saved once on release', MOCK.saved == saves_mid + 1, MOCK.saved - saves_mid);
MOCK.window_pos['##cadence_attack'] = nil;
MOCK.key_shift = false;

-- Close settings, reset, lock, help.
MOCK.fire('command', { command = '/cadence' });
MOCK.fire('command', { command = '/cadence reset' });
check('reset stacks resting then auto attack', s.resting.y == 620 and s.attack.y > s.resting.y + 30, s.resting.y .. ',' .. s.attack.y);
MOCK.fire('command', { command = '/cadence lock' });
check('lock sets flag', s.style.locked == true);
MOCK.fire('command', { command = '/cadence unlock' });
local e = { command = '/cadence wat' };
MOCK.fire('command', e);
check('commands are blocked from the game', e.blocked == true);
local other = { command = '/echo hi' };
MOCK.fire('command', other);
check('other commands pass through', not other.blocked);

-- Zoning resets and the player entity is nil for a while.
MOCK.zoning = true;
problems = frames(5);
check('zoning draws nothing', #MOCK.imgui_calls == 0, #MOCK.imgui_calls);
MOCK.zoning = false;
packet(MOCK.zone_packet(1001));
problems = frames(5);
check('after zone balanced', #problems == 0, table.concat(problems, '; '));

check('never blocks an unrelated packet', not blocked);
check('no drawing errors', errors_printed() == nil, errors_printed());

-- A character switch hands cadence a new settings table.
local fresh = require('ui.defaults').make();
fresh.attack.enabled = false;
for _, fn in pairs(MOCK.settings.callbacks) do fn(fresh); end
MOCK.player.status = 1;
frames(3);
check('new character settings apply', windows_named('##cadence_attack') == 0);

--[[
    Logging in on another character. Ashita's settings library raises the settings callback from its
    own 0x00A handler, while party memory still holds the last character. Ashita doesn't say which
    handler runs first. Either way the new character's rounds count.
]]
local attack = require('core.attack');
local BOB, MOB = 2002, 0x01000200;
MOCK.entities[0x200] = { ServerId = MOB, Name = 'Goblin Thug', Status = 1, SpawnFlags = 0x10 };
local function log_in(cadence_first)
    MOCK.player.server_id, MOCK.player.status, MOCK.zoning = 1001, 0, true;
    if (cadence_first) then
        packet(MOCK.zone_packet(BOB));
        MOCK.settings.switch_character(nil);
    else
        MOCK.settings.switch_character(nil);
        packet(MOCK.zone_packet(BOB));
    end
    MOCK.player.server_id, MOCK.zoning = BOB, false;
    MOCK.frame();
end
-- Five rounds 4 s apart, then the seconds left half a second after the last one. 3.5 when they count.
local function left_after_rounds()
    MOCK.player.status, MOCK.player.target_index = 1, 0x200;
    MOCK.frame();
    local t = MOCK.now;
    for i = 1, 5 do
        MOCK.now = t + 2.8 + (i - 1) * 4;
        packet(MOCK.action_packet(BOB, 1, 0, MOB, { { message = 1 } }));
        MOCK.frame();
    end
    local _, left = attack.progress(MOCK.now + 0.5);
    MOCK.player.status = 0;
    MOCK.frame();
    return left;
end
log_in(false);
local left = left_after_rounds();
check('settings library first, the new character\'s rounds count', left ~= nil and left > 3, left);
log_in(true);
left = left_after_rounds();
check('cadence first, the new character\'s rounds count', left ~= nil and left > 3, left);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
table.insert(out, 'printed: ' .. table.concat(MOCK.printed, ' | '));
return table.concat(out, '\n');
