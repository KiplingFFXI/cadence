-- Hiding during events when a game update breaks the patterns. The server's event status takes
-- over, and the interface and map checks switch off.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.event_check = 0;
MOCK.ui_check = 0;
MOCK.menu_check = 0;
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');

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

check('no address read when the pattern is missing', MOCK.memory_calls.read_uint32 == 0, MOCK.memory_calls.read_uint32);

MOCK.now = 100;
MOCK.fire('command', { command = '/cadence' });
frames(3, 1 / 60);
check('window shows outside events', windows_named('cadence##cadence_settings') == 3);

-- The memory flag is ignored. Only the server status counts.
MOCK.in_event = true;
frames(3, 1 / 60);
check('flag ignored without the pattern', windows_named('cadence##cadence_settings') == 3);
check('no flag reads without the pattern', MOCK.memory_calls.read_uint8 == 0, MOCK.memory_calls.read_uint8);

MOCK.player.status_server = 4;
frames(3, 1 / 60);
check('event status hides everything', #MOCK.imgui_calls == 0, #MOCK.imgui_calls);

MOCK.player.status_server = 0;
frames(3, 1 / 60);
check('back when the event status ends', windows_named('cadence##cadence_settings') == 3);

-- The interface and map options are greyed out with a note, and never hide anything.
local function disabled_before(label)
    for i, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'Checkbox' and c[2] == label) then
            local before = MOCK.imgui_calls[i - 1];
            return before and before[1] == 'BeginDisabled' and before[2] == true;
        end
    end
    return nil;
end
check('game UI checkbox greyed out', disabled_before('Hide with the game UI') == true);
check('map checkbox greyed out', disabled_before('Hide on the map') == true);
-- Draws one frame with the mouse on every (?), and returns each tip's text, in order.
local function tips_shown()
    local imgui = require('imgui');
    rawset(imgui, 'IsItemHovered', function () return true; end);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    rawset(imgui, 'IsItemHovered', nil);
    local tips, inside = {}, false;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'BeginTooltip') then inside = true; end
        if (c[1] == 'EndTooltip') then inside = false; end
        if (inside and c[1] == 'TextUnformatted') then table.insert(tips, tostring(c[2])); end
    end
    return tips;
end
local greyed = 0;
for _, tip in ipairs(tips_shown()) do
    if (tip:find('let cadence see', 1, true)) then greyed = greyed + 1; end
end
check('both tips say why they\'re greyed out', greyed == 2, greyed);
MOCK.ui_hidden, MOCK.menu_name = true, 'map0    ';
frames(3, 1 / 60);
check('never hides without the patterns', windows_named('cadence##cadence_settings') == 3);
MOCK.ui_hidden, MOCK.menu_name = false, nil;

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
