-- The resizable, two-column settings window, the AUTO ATTACK name and the timer commands.
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
local function calls(name, match)
    local found = {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == name and (match == nil or match(c))) then table.insert(found, c); end
    end
    return found;
end

-- By default it's a landscape window, resizable, with a size it remembers.
check('default size is landscape', s.window.width > s.window.height, s.window.width .. 'x' .. s.window.height);
MOCK.now = 100;
MOCK.fire('command', { command = '/cadence' });
frames(1);
local sized = calls('SetNextWindowSize', function (c) return c[2][1] == s.window.width and c[2][2] == s.window.height; end);
check('window gets its saved size', #sized == 1, #sized);
check('window has size limits', #calls('SetNextWindowSizeConstraints') == 1);

-- Wide enough for two columns, then narrow enough for one.
local tables = calls('BeginTable');
check('two columns when wide', #tables >= 1 and tables[1][3] == 2, tables[1] and tables[1][3]);
MOCK.window_size = { 500, 590 };
frames(1);
tables = calls('BeginTable');
check('one column when narrow', #tables >= 1 and tables[1][3] == 1, tables[1] and tables[1][3]);
MOCK.window_size = nil;

-- The heading says AUTO ATTACK, and the title line too.
frames(1);
local heading_found, title_found = false, false;
for _, c in ipairs(calls('TextColored')) do
    if (c[3] == 'AUTO ATTACK TIMER') then heading_found = true; end
end
for _, c in ipairs(calls('TextUnformatted')) do
    if (type(c[2]) == 'string' and c[2]:find('^Auto attack, resting and enemy timers')) then title_found = true; end
end
check('the heading says AUTO ATTACK TIMER', heading_found);
check('the title line names the three timers', title_found);

-- Resizing saves nothing while the edge is held, and saves once when it's let go.
local saves = MOCK.saved;
MOCK.window_size = { 700, 600 };
MOCK.mouse_down = true;
frames(5);
check('no save while resizing', MOCK.saved == saves, MOCK.saved - saves);
MOCK.mouse_down = false;
frames(5);
check('one save after letting go', MOCK.saved == saves + 1, MOCK.saved - saves);
check('new size kept', s.window.width == 700 and s.window.height == 600, s.window.width .. 'x' .. s.window.height);
MOCK.window_size = nil;
s.window.width, s.window.height = 920, 680;
MOCK.fire('command', { command = '/cadence' });

-- Chat says auto attack timer.
local printed = #MOCK.printed;
MOCK.fire('command', { command = '/cadence attack off' });
check('/cadence attack off', s.attack.enabled == false
    and (MOCK.printed[printed + 1] or ''):find('The auto attack timer is off') ~= nil, MOCK.printed[printed + 1]);
MOCK.fire('command', { command = '/cadence attack on' });
check('/cadence attack on', s.attack.enabled == true);
printed = #MOCK.printed;
MOCK.fire('command', { command = '/cadence swing off' });
check('the old auto attack word isn\'t a command', s.attack.enabled == true and #MOCK.printed == printed + 1
    and (MOCK.printed[printed + 1] or ''):find('Didn\'t recognize "swing"', 1, true) ~= nil, MOCK.printed[printed + 1]);
printed = #MOCK.printed;
MOCK.fire('command', { command = '/cadence resting off' });
check('/cadence resting off', s.resting.enabled == false
    and (MOCK.printed[printed + 1] or ''):find('The resting timer is off') ~= nil, MOCK.printed[printed + 1]);
MOCK.fire('command', { command = '/cadence resting on' });
check('/cadence resting on', s.resting.enabled == true);
printed = #MOCK.printed;
MOCK.fire('command', { command = '/cadence rest off' });
check('the old resting word isn\'t a command', s.resting.enabled == true and #MOCK.printed == printed + 1
    and (MOCK.printed[printed + 1] or ''):find('Didn\'t recognize "rest"', 1, true) ~= nil, MOCK.printed[printed + 1]);

-- The timer's label reads AUTO ATTACK. On a narrow timer it's cut off before the seconds.
local hud = require('ui.hud');
local function header_calls(width, fill, left)
    s.attack.width = width;
    hud.refresh(s);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.draw_attack(fill, left, 3.78, true);
    hud.end_frame();
    MOCK.record_imgui = false;
    local texts, clips = {}, 0;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddText') then table.insert(texts, c[6]); end
        if (c[1] == 'dl:PushClipRect') then clips = clips + 1; end
    end
    return table.concat(texts, '|'), clips;
end
local texts, clips = header_calls(240, 0.5, 1.9);
check('label says AUTO ATTACK', texts:find('AUTO ATTACK', 1, true) ~= nil, texts);
local accent_clips = clips;
texts, clips = header_calls(120, 1, 0);
check('narrow label is cut before the value', clips == accent_clips + 1, clips .. ' vs ' .. accent_clips);
s.attack.width = 240;
hud.refresh(s);

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
