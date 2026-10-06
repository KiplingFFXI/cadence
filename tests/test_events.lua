-- Hiding during events. The XIUI event flag, the option, the settings window, and what keeps running.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;

local function frames(n, dt)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do MOCK.frame(dt); end
    MOCK.record_imgui = false;
end
local function windows_named(name)
    local n = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'Begin' and call[2] == name) then n = n + 1; end
    end
    return n;
end
local function balanced()
    local begins, ends, push, pop = 0, 0, 0, 0;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'Begin') then begins = begins + 1; end
        if (c[1] == 'End') then ends = ends + 1; end
        if (c[1] == 'PushStyleVar') then push = push + 1; end
        if (c[1] == 'PopStyleVar') then pop = pop + (c[2] or 1); end
    end
    return begins == ends and push == pop;
end

-- The pattern is looked up once, in FFXiMain.dll, exactly as XIUI does it. The other two finds are
-- the interface and map checks.
local f = MOCK.finds.event_check;
check('patterns looked up once at load', MOCK.memory_calls.find == 3, MOCK.memory_calls.find);
check('pattern matches XIUI', f and f.name == 'FFXiMain.dll' and f.size == 0 and f.offset == 0 and f.usage == 0
    and f.pattern == 'A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3');
check('flag address read once at load', MOCK.reads_at[MOCK.event_check + 1] == 1, MOCK.reads_at[MOCK.event_check + 1]);
check('addresses read once at load', MOCK.memory_calls.read_uint32 == 3, MOCK.memory_calls.read_uint32);
check('on by default', s.style.hide_during_events == true);

-- Engaged, the auto attack timer shows.
MOCK.now = 100;
MOCK.player.status = 1;
frames(5, 1 / 60);
check('engaged shows the auto attack timer', windows_named('##cadence_attack') == 5, windows_named('##cadence_attack'));

-- An event starts. The flag turns on before the server's status changes.
MOCK.in_event = true;
local reads = MOCK.memory_calls.read_uint8;
frames(5, 1 / 60);
check('event hides the auto attack timer', windows_named('##cadence_attack') == 0, windows_named('##cadence_attack'));
check('nothing at all is drawn during the event', #MOCK.imgui_calls == 0, #MOCK.imgui_calls);
check('one flag read per frame', MOCK.memory_calls.read_uint8 - reads == 5, MOCK.memory_calls.read_uint8 - reads);
check('no address lookups after load', MOCK.memory_calls.find == 3 and MOCK.reads_at[MOCK.event_check + 1] == 1
    and MOCK.reads_at[MOCK.ui_check + 10] == 1 and MOCK.reads_at[MOCK.menu_check] == 1);

-- The settings window opened during an event stays hidden, and comes back after.
MOCK.fire('command', { command = '/cadence' });
MOCK.player.status = 4;
frames(5, 1 / 60);
check('settings window hidden during the event', windows_named('cadence##cadence_settings') == 0);
MOCK.in_event = false;
MOCK.player.status = 0;
frames(3, 1 / 60);
check('settings window back after the event', windows_named('cadence##cadence_settings') == 3,
    windows_named('cadence##cadence_settings'));
check('samples back after the event', windows_named('##cadence_attack') == 3, windows_named('##cadence_attack'));
check('balanced after the event', balanced());
MOCK.fire('command', { command = '/cadence' });

-- Resting ticks are still tracked while hidden.
local resting = require('core.resting');
MOCK.player.status = 33;
MOCK.player.mp_max = 400;
MOCK.fire('packet_in', MOCK.vitals_packet(1001, 500, 100, 0));
frames(1, 1 / 60);
MOCK.in_event = true;
local t0 = MOCK.now;
MOCK.now = t0 + 21.2;
MOCK.fire('packet_in', MOCK.vitals_packet(1001, 510, 112, 0));
frames(1, 1 / 60);
check('resting tick seen while hidden', resting.seen_at() ~= nil, tostring(resting.seen_at()));
MOCK.in_event = false;
frames(1, 1 / 60);
check('resting timer back after the event', windows_named('##cadence_resting') == 1, windows_named('##cadence_resting'));

-- Turned off, the timers stay up during an event and the flag isn't read.
MOCK.player.status = 1;
frames(2, 1 / 60);
s.style.hide_during_events = false;
MOCK.in_event = true;
reads = MOCK.reads_at[MOCK.event_flag_address];
frames(3, 1 / 60);
check('option off keeps the timer up', windows_named('##cadence_attack') == 3, windows_named('##cadence_attack'));
check('option off reads nothing', MOCK.reads_at[MOCK.event_flag_address] == reads,
    MOCK.reads_at[MOCK.event_flag_address] - reads);
MOCK.in_event = false;
s.style.hide_during_events = true;

-- Reset look leaves it alone.
s.style.hide_during_events = false;
require('ui.presets').reset(s);
check('reset look keeps the option', s.style.hide_during_events == false);
s.style.hide_during_events = true;

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
