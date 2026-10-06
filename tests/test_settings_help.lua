-- The settings window's (?) after every setting, what the tips say, and opening where you left it.
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
local imgui = require('imgui');
local WINDOW = 'cadence##cadence_settings';

local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do MOCK.frame(1 / 60); end
    MOCK.record_imgui = false;
end

MOCK.now = 100;
MOCK.fire('command', { command = '/cadence' });
frames(1);

-- Every setting is followed by its (?) before the next setting starts. Color swatches with no name
-- belong to the setting next to them, and the ON/OFF chips to their heading.
local WIDGETS = { Checkbox = true, SliderInt = true, SliderFloat = true, BeginCombo = true, InputTextWithHint = true,
    InputText = true, Button = true, SmallButton = true, ColorEdit4 = true };
local function is_setting(c)
    if (not WIDGETS[c[1]]) then return false; end
    local label = tostring(c[2]);
    return not (label:find('^##') or label:find('^ON##') or label:find('^OFF##'));
end
local missing, settings_seen = {}, 0;
local calls = MOCK.imgui_calls;
for i, c in ipairs(calls) do
    if (is_setting(c)) then
        settings_seen = settings_seen + 1;
        local helped = false;
        for j = i + 1, #calls do
            if (is_setting(calls[j])) then break; end
            if (calls[j][1] == 'TextDisabled' and calls[j][2] == '(?)') then helped = true; break; end
        end
        if (not helped) then table.insert(missing, tostring(c[2])); end
    end
end
check('every setting has a (?)', #missing == 0, table.concat(missing, ', '));
check('the three tabs have their settings', settings_seen >= 60, settings_seen);
local headings = 0;
for i, c in ipairs(calls) do
    if (c[1] == 'TextColored' and tostring(c[3]):find('TIMER$') and calls[i + 2] and calls[i + 2][1] == 'TextDisabled') then
        headings = headings + 1;
    end
end
check('each timer heading has a (?)', headings == 3, headings);

-- Hovering a (?) shows its tip.
rawset(imgui, 'IsItemHovered', function () return true; end);
frames(1);
rawset(imgui, 'IsItemHovered', nil);
local tips, inside = {}, false;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'BeginTooltip') then inside = true; end
    if (c[1] == 'EndTooltip') then inside = false; end
    if (inside and c[1] == 'TextUnformatted') then table.insert(tips, tostring(c[2])); end
end
local helps = 0;
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'TextDisabled') then helps = helps + 1; end end
check('each (?) has a tip', #tips == helps and helps > 0, #tips .. ' of ' .. helps);

-- What the tips and the window's own text say.
local all_text = {};
for _, tip in ipairs(tips) do table.insert(all_text, tip); end
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'TextUnformatted' or c[1] == 'TextColored') then table.insert(all_text, tostring(c[3] or c[2])); end
end
local problems = {};
for _, words in ipairs(all_text) do
    if (words:find('XIUI', 1, true)) then table.insert(problems, 'names XIUI: ' .. words); end
    if (words:find(';', 1, true)) then table.insert(problems, 'semicolon: ' .. words); end
    if (words:find('[\128-\255]')) then table.insert(problems, 'not plain ASCII: ' .. words); end
    if (words:find(' - ', 1, true)) then table.insert(problems, 'dash: ' .. words); end
end
check('no tip or note names XIUI, and they read plainly', #problems == 0, table.concat(problems, ' | '));
local short = true;
for _, tip in ipairs(tips) do if (#tip > 200) then short = false; end end
check('tips stay short', short);
-- ImGui can break a wrapped line right after a period, comma, ! or ? or a double quote. One of those between
-- two other characters could then start a line with a stray mark, like the period after "asleep" or the ) of (?).
local stray = nil;
for _, tip in ipairs(tips) do
    if (tip:find('%S[%.,;!%?"]%S')) then stray = stray or tip; end
end
check('no tip can wrap with a stray mark at the start of a line', #tips >= 80 and stray == nil, stray or #tips);

-- The window opens where it was left. It starts at its default spot.
local function placed()
    local last = nil;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'SetNextWindowPos') then last = c[2]; end
        if (c[1] == 'Begin' and c[2] == WINDOW) then return last and last[1], last and last[2]; end
    end
end
frames(1);
local x, y = placed();
check('opens at the default spot', x == 120 and y == 10, tostring(x) .. ',' .. tostring(y));

local saves = MOCK.saved;
MOCK.window_pos[WINDOW] = { 300, 200 };
MOCK.mouse_down = true;
frames(1);
check('not saved while dragging', MOCK.saved == saves and s.window.x == 120);
MOCK.mouse_down = false;
frames(1);
check('saved once you let go', MOCK.saved > saves and s.window.x == 300 and s.window.y == 200, s.window.x .. ',' .. s.window.y);
MOCK.window_pos[WINDOW] = nil;
MOCK.fire('command', { command = '/cadence' });
MOCK.fire('command', { command = '/cadence' });
frames(1);
x, y = placed();
check('reopens where it was left', x == 300 and y == 200, tostring(x) .. ',' .. tostring(y));

-- A spot saved on a bigger screen is pulled back onto this one.
s.window.x, s.window.y = 5000, 4000;
frames(1);
x, y = placed();
check('pulled back onto the screen', x <= 1600 - 464 and y <= 1200 - 240 and x >= 0 and y >= 0, tostring(x) .. ',' .. tostring(y));

-- A window left hanging off the bottom right keeps its size and gets pulled back into view.
local function sized()
    local last = nil;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'SetNextWindowSize') then last = c[2]; end
        if (c[1] == 'Begin' and c[2] == WINDOW) then return last and last[1], last and last[2]; end
    end
end
MOCK.fire('command', { command = '/cadence' });
s.window.x, s.window.y, s.window.width, s.window.height = 1400, 900, 920, 680;
MOCK.fire('command', { command = '/cadence' });
frames(1);
x, y = placed();
local w, h = sized();
check('off the edge keeps its size', w == 920 and h == 680, tostring(w) .. 'x' .. tostring(h));
check('and is pulled back into view', x == 1600 - 920 and y == 1200 - 680, tostring(x) .. ',' .. tostring(y));

-- The window opens at the size you left it, whatever that is.
local function reopen()
    MOCK.fire('command', { command = '/cadence' });
    frames(1);
    MOCK.fire('command', { command = '/cadence' });
    frames(1);
end
MOCK.fire('command', { command = '/cadence' });
frames(1);
s.window.x, s.window.y, s.window.width, s.window.height = 120, 10, 920, 650;
MOCK.fire('command', { command = '/cadence' });
frames(1);
check('a size you picked is kept', s.window.width == 920 and s.window.height == 650, s.window.width .. 'x' .. s.window.height);
s.window.width, s.window.height = 840, 590;
reopen();
check('and so is another', s.window.width == 840 and s.window.height == 590, s.window.width .. 'x' .. s.window.height);
s.window.width, s.window.height = 700, 500;
reopen();
check('and a small one', s.window.width == 700 and s.window.height == 500);

-- Resizing the open window and letting go saves it once and keeps it, the next time it opens too.
MOCK.window_size = { 920, 680 };
reopen();
MOCK.mouse_down = true;
MOCK.window_size = { 920, 610 };
frames(5);
MOCK.mouse_down = false;
local before = MOCK.saved;
frames(60);
check('resizing saves once', MOCK.saved - before == 1, ('%d saves in 60 frames'):format(MOCK.saved - before));
check('and keeps the size you gave it', s.window.width == 920 and s.window.height == 610, s.window.width .. 'x' .. s.window.height);
MOCK.window_size = nil;
reopen();
check('opening it again keeps it too', s.window.width == 920 and s.window.height == 610, s.window.width .. 'x' .. s.window.height);

-- With one layout for all characters on, each save writes shared_layout.json. Letting go writes it once too.
local shared_layout = require('core.shared_layout');
local writes = 0;
local write_shared = shared_layout.save;
shared_layout.save = function () writes = writes + 1; write_shared(); end
MOCK.fire('command', { command = '/cadence onelayout on' });
MOCK.window_size = { 920, 680 };
reopen();
MOCK.mouse_down = true;
MOCK.window_size = { 840, 590 };
frames(5);
MOCK.mouse_down = false;
writes = 0;
frames(60);
check('with one layout on, the shared file is written once', writes == 1, ('%d writes in 60 frames'):format(writes));
MOCK.fire('command', { command = '/cadence onelayout off' });
shared_layout.save = write_shared;
MOCK.window_size = nil;

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
