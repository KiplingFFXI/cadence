-- A game update that breaks only the menu pattern. Hiding with the game UI still works, and only the
-- map option is greyed out, with a tip that says so.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.menu_check = 0;
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local player = require('core.player');

local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do MOCK.frame(1 / 60); end
    MOCK.record_imgui = false;
end
local function windows_named(name)
    local n = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'Begin' and call[2] == name) then n = n + 1; end
    end
    return n;
end
local function disabled_before(label)
    for i, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'Checkbox' and c[2] == label) then
            local before = MOCK.imgui_calls[i - 1];
            return before and before[1] == 'BeginDisabled' and before[2] == true;
        end
    end
    return nil;
end
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

check('the interface can still be checked', player.can_check_interface());
check('the map can\'t', not player.can_check_map());

MOCK.now = 100;
MOCK.fire('command', { command = '/cadence' });
frames(1);
check('map checkbox greyed out', disabled_before('Hide on the map') == true);
check('game UI checkbox live', disabled_before('Hide with the game UI') == false);
local map_tip, ui_tip = nil, nil;
for _, tip in ipairs(tips_shown()) do
    if (tip:find('map is open', 1, true)) then map_tip = tip; end
    if (tip:find('Scroll Lock', 1, true)) then ui_tip = tip; end
end
check('the map tip says why it\'s greyed out', map_tip and map_tip:find('greyed out', 1, true) ~= nil, map_tip);
check('the game UI tip doesn\'t', ui_tip and ui_tip:find('greyed out', 1, true) == nil, ui_tip);

MOCK.ui_hidden = true;
frames(2);
check('Scroll Lock still hides everything', #MOCK.imgui_calls == 0, #MOCK.imgui_calls);
MOCK.ui_hidden = false;
MOCK.menu_name = 'map0    ';
frames(2);
check('the map never hides it', windows_named('cadence##cadence_settings') == 2);
MOCK.menu_name = nil;

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
