-- Holding Shift to see through the settings window, so a timer under it can be dragged. Shift while you
-- type in chat does nothing to the window or the timers.
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
local presets = require('ui.presets');
local theme = require('ui.theme');
local WINDOW = 'cadence##cadence_settings';

local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do MOCK.frame(1 / 60); end
    MOCK.record_imgui = false;
    return MOCK.imgui_calls;
end

--[[
    How the settings window was drawn on the last frame recorded. `flags` are its Begin flags, `alpha`
    is the Alpha pushed for the whole window (nil for none), `faded` lists the Alpha values pushed
    inside it below 1 and `balanced` is true when every style var pushed was popped.
]]
local function window_state(calls)
    local at = nil;
    for i, c in ipairs(calls) do
        if (c[1] == 'Begin' and c[2] == WINDOW) then at = i; end
    end
    if (at == nil) then return nil; end
    local state = { flags = calls[at][4], alpha = nil, faded = {}, balanced = true };
    for i = at - 1, 1, -1 do
        local c = calls[i];
        if (c[1] == 'End') then break; end
        if (c[1] == 'PushStyleVar' and c[2] == ImGuiStyleVar_Alpha) then state.alpha = c[3]; end
    end
    local depth = 0;
    for i = at + 1, #calls do
        local c = calls[i];
        if (c[1] == 'End' and depth == 0) then break; end
        if (c[1] == 'Begin') then depth = depth + 1; end
        if (c[1] == 'End') then depth = depth - 1; end
        if (c[1] == 'PushStyleVar' and c[2] == ImGuiStyleVar_Alpha and c[3] < 1) then
            table.insert(state.faded, c[3]);
        end
    end
    local pushed = 0;
    for _, c in ipairs(calls) do
        if (c[1] == 'PushStyleVar') then pushed = pushed + 1; end
        if (c[1] == 'PopStyleVar') then pushed = pushed - (c[2] or 1); end
    end
    state.balanced = pushed == 0;
    return state;
end

local function see_through(state)
    return state ~= nil and bit.band(state.flags or 0, ImGuiWindowFlags_NoInputs) ~= 0;
end

local function all_equal(list, value)
    if (#list == 0) then return false; end
    for _, v in ipairs(list) do
        if (math.abs(v - value) > 1e-6) then return false; end
    end
    return true;
end

local function describe(state)
    if (state == nil) then return 'no window'; end
    return ('flags %s alpha %s faded %s'):format(tostring(state.flags), tostring(state.alpha),
        table.concat(state.faded, ','));
end

MOCK.now = 100;
MOCK.fire('command', { command = '/cadence' });

-- On by default.
check('on by default', require('ui.defaults').make().style.see_through == true and s.style.see_through == true);

-- Without Shift the window is solid and takes the mouse. The enemy timer is off, so its settings are faint.
local state = window_state(frames(1));
check('solid without Shift', state ~= nil and not see_through(state) and state.alpha == nil, describe(state));
check('an off timer\'s settings are faint at half', state ~= nil and all_equal(state.faded, 0.5), describe(state));

-- Holding Shift makes it see-through and lets the mouse through.
MOCK.key_shift = true;
state = window_state(frames(1));
check('Shift lets the mouse through', see_through(state), describe(state));
check('Shift makes it see-through', state ~= nil and state.alpha == 0.25, describe(state));
check('faint settings stay fainter than the others', state ~= nil and all_equal(state.faded, 0.125), describe(state));
check('every style var is popped', state ~= nil and state.balanced);

-- Shift while you type in the game's chat line is just typing. The window stays solid. The timers stay
-- click-through with no outline, so a capital letter can't grab one.
local OUTLINE = theme.u32(theme.with_alpha(theme.palette.ember, 0.85));
local function attack_timer(calls)
    local flags, outlined = nil, false;
    for _, c in ipairs(calls) do
        if (c[1] == 'Begin' and c[2] == '##cadence_attack') then flags = c[4]; end
        if (c[1] == 'dl:AddRect' and c[4] == OUTLINE) then outlined = true; end
    end
    return flags, outlined;
end
rawset(imgui, 'IsWindowHovered', function () return true; end);
MOCK.key_shift = false;
local still = attack_timer(frames(1));
MOCK.key_shift = true;
local movable, outlined = attack_timer(frames(1));
check('Shift on its own makes the timer movable and outlines it', movable ~= nil and movable ~= still and outlined);
MOCK.chat_input = 0x11;
local typing_calls = frames(1);
state = window_state(typing_calls);
check('solid while the game\'s chat line is open', state ~= nil and not see_through(state) and state.alpha == nil,
    describe(state));
local typing, typing_outlined = attack_timer(typing_calls);
check('the timers stay click-through while you type', typing == still, tostring(typing) .. ' vs ' .. tostring(still));
check('with no outline', not typing_outlined);
rawset(imgui, 'IsWindowHovered', nil);
MOCK.chat_input = 0;
state = window_state(frames(1));
check('see-through again once it closes', see_through(state), describe(state));

-- Letting go of Shift brings it back.
MOCK.key_shift = false;
state = window_state(frames(1));
check('solid again once you let go', state ~= nil and not see_through(state) and state.alpha == nil, describe(state));
check('faint settings go back to half', state ~= nil and all_equal(state.faded, 0.5), describe(state));

-- The chat line is only read while you hold Shift.
local chat_reads, get_chat = 0, AshitaCore.GetChatManager;
AshitaCore.GetChatManager = function (...) chat_reads = chat_reads + 1; return get_chat(...); end
frames(5);
check('without Shift the chat line isn\'t read', chat_reads == 0, chat_reads);
AshitaCore.GetChatManager = get_chat;

-- With Peek with Shift off, Shift does nothing to the window.
s.style.see_through = false;
MOCK.key_shift = true;
state = window_state(frames(1));
check('turned off, Shift leaves it solid', state ~= nil and not see_through(state) and state.alpha == nil,
    describe(state));
s.style.see_through = true;

-- A dropdown or color picker open keeps it solid.
rawset(imgui, 'IsPopupOpen', function () return true; end);
state = window_state(frames(2));
check('solid while a popup is open', state ~= nil and not see_through(state) and state.alpha == nil, describe(state));
rawset(imgui, 'IsPopupOpen', nil);
state = window_state(frames(1));
check('see-through once the popup closes', see_through(state), describe(state));

-- Typing in a box or dragging a slider keeps it solid, so a capital letter in a label box still works.
MOCK.key_shift = false;
rawset(imgui, 'IsAnyItemActive', function () return true; end);
rawset(imgui, 'IsWindowFocused', function () return true; end);
frames(1);
MOCK.key_shift = true;
state = window_state(frames(2));
check('solid while you use something in it', state ~= nil and not see_through(state) and state.alpha == nil,
    describe(state));
rawset(imgui, 'IsAnyItemActive', nil);
state = window_state(frames(1));
check('still solid on the frame you let go', not see_through(state), describe(state));
state = window_state(frames(1));
check('see-through on the next one', see_through(state) and state.alpha == 0.25, describe(state));

-- A timer you're dragging is active in its own window. That keeps the window see-through.
rawset(imgui, 'IsAnyItemActive', function () return true; end);
rawset(imgui, 'IsWindowFocused', function () return false; end);
state = window_state(frames(3));
check('stays see-through while you drag a timer under it', see_through(state) and state.alpha == 0.25,
    describe(state));
rawset(imgui, 'IsAnyItemActive', nil);
rawset(imgui, 'IsWindowFocused', nil);
MOCK.key_shift = false;

-- The box sits on the Look tab next to Reset positions, with its (?).
local calls = frames(1);
local order = {};
for _, c in ipairs(calls) do
    if ((c[1] == 'Button' and c[2] == 'Reset positions') or c[1] == 'SameLine' or c[1] == 'TextDisabled'
        or (c[1] == 'Checkbox' and c[2] == 'Peek with Shift')) then
        table.insert(order, c[1] .. ':' .. tostring(c[2]));
    end
end
local line = table.concat(order, ' ');
check('Peek with Shift sits beside Reset positions',
    line:find('Button:Reset positions SameLine:nil TextDisabled:(?) SameLine:228 Checkbox:Peek with Shift '
        .. 'SameLine:nil TextDisabled:(?)', 1, true) ~= nil, line:match('Button:Reset.*') or line);

-- Clearing it saves.
local saves = MOCK.saved;
rawset(imgui, 'Checkbox', function (label, flag)
    if (label == 'Peek with Shift') then flag[1] = false; return true; end
    return false;
end);
frames(1);
rawset(imgui, 'Checkbox', nil);
check('clearing the box turns it off', s.style.see_through == false);
check('and saves', MOCK.saved > saves, MOCK.saved - saves);

-- Its tip says what it does, and that the window doesn't move then.
rawset(imgui, 'IsItemHovered', function () return true; end);
calls = frames(1);
rawset(imgui, 'IsItemHovered', nil);
local tip, after_box = nil, false;
for _, c in ipairs(calls) do
    if (c[1] == 'Checkbox' and c[2] == 'Peek with Shift') then after_box = true; end
    if (after_box and c[1] == 'TextUnformatted' and tip == nil) then tip = tostring(c[2]); end
end
check('its tip names Shift and see-through', tip ~= nil and tip:find('Shift', 1, true) ~= nil
    and tip:find('see-through', 1, true) ~= nil, tip);
check('its tip says the window doesn\'t move then', tip ~= nil and tip:find('doesn\'t move the window', 1, true) ~= nil,
    tip);
check('its tip is short', tip ~= nil and #tip <= 200, tip and #tip);

-- It's how the window behaves, not a look, so presets, Reset look and Undo leave it alone.
s.style.see_through = false;
presets.apply(s, 'Minimal');
check('a preset leaves it', s.style.see_through == false);
presets.reset(s);
check('Reset look leaves it', s.style.see_through == false);
s.style.see_through = true;
presets.undo(s);
check('Undo leaves it', s.style.see_through == true);

-- With the window closed, Shift draws no window and breaks nothing.
MOCK.fire('command', { command = '/cadence' });
MOCK.key_shift = true;
state = window_state(frames(2));
check('no window while it\'s closed', state == nil);
MOCK.key_shift = false;

local errors = nil;
for _, l in ipairs(MOCK.printed) do if (l:find('Drawing stopped')) then errors = l; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
