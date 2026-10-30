-- The settings window's greyed out sliders, the Fill label, a timer that's off drawn faint, Show
-- them, Undo and Reset look on the PRESET heading, Drain instead of fill on the Appearance tab, the footer,
-- a color dropped on a swatch saving, and what chat says.
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
check('action recovery starts off', not s.recovery.enabled);
check('enemy casting starts off independently', not s.enemycast.enabled);
-- Keep the new card on while isolating each existing timer's off state below.
s.recovery.enabled = true;
s.enemycast.enabled = true;
local imgui = require('imgui');

local OFF_NOTE = 'This timer is off, so it isn\'t on screen.';

local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do MOCK.frame(1 / 60); end
    MOCK.record_imgui = false;
    return MOCK.imgui_calls;
end

-- Walks the recorded calls, following BeginDisabled and the pushed Alpha. Returns every other call in
-- order, with its label, the alpha it was drawn at and whether it was greyed out.
local function walk(calls)
    local seen, disabled, styles = {}, {}, {};
    for _, c in ipairs(calls) do
        local name = c[1];
        if (name == 'BeginDisabled') then
            table.insert(disabled, c[2] == true);
        elseif (name == 'EndDisabled') then
            table.remove(disabled);
        elseif (name == 'PushStyleVar') then
            table.insert(styles, { c[2], c[3] });
        elseif (name == 'PopStyleVar') then
            for _ = 1, (c[2] or 1) do table.remove(styles); end
        else
            local alpha, off = 1, false;
            for _, style in ipairs(styles) do
                if (style[1] == ImGuiStyleVar_Alpha) then alpha = style[2]; end
            end
            for _, d in ipairs(disabled) do off = off or d; end
            local label = (name == 'TextColored') and c[3] or c[2];
            table.insert(seen, { name = name, label = label, alpha = alpha, disabled = off });
        end
    end
    return seen;
end

-- The first call with this name and label, and where it is.
local function find(seen, name, label)
    for i, e in ipairs(seen) do
        if (e.name == name and e.label == label) then return e, i; end
    end
    return nil, nil;
end

-- The (?) right after the call at `i`, and where it is.
local function help_after(seen, i)
    for j = (i or #seen) + 1, #seen do
        if (seen[j].name == 'TextDisabled' and seen[j].label == '(?)') then return seen[j], j; end
    end
    return nil, nil;
end

local function balanced(calls)
    local push, pop, begin, finish = 0, 0, 0, 0;
    for _, c in ipairs(calls) do
        if (c[1] == 'PushStyleVar') then push = push + 1; end
        if (c[1] == 'PopStyleVar') then pop = pop + (c[2] or 1); end
        if (c[1] == 'BeginDisabled') then begin = begin + 1; end
        if (c[1] == 'EndDisabled') then finish = finish + 1; end
    end
    return push == pop and begin == finish, push .. '/' .. pop .. ' ' .. begin .. '/' .. finish;
end

MOCK.now = 100;
MOCK.fire('command', { command = '/cadence' });

-- Greyed out sliders -----------------------------------------------------------------------------
local seen = walk(frames(1));
local function greyed(name, label)
    local e, i = find(seen, name, label);
    if (e == nil) then return 'missing'; end
    local tip = help_after(seen, i);
    return e.disabled, tip and tip.disabled;
end
check('Almost ready at is live with almost ready on', greyed('SliderFloat', 'Almost ready at##attack') == false);
check('the enemy one too', greyed('SliderFloat', 'Almost ready at##enemy') == false);
check('Flash length is live with the flash on', greyed('SliderFloat', 'Flash length') == false);

s.attack.almost_ready, s.enemy.almost_ready, s.resting.flash_on_tick = false, false, false;
seen = walk(frames(1));
local off, tip_off = greyed('SliderFloat', 'Almost ready at##attack');
check('Almost ready at greys out with almost ready off', off == true, tostring(off));
check('its (?) still works', tip_off == false, tostring(tip_off));
off, tip_off = greyed('SliderFloat', 'Almost ready at##enemy');
check('the enemy one greys out too', off == true and tip_off == false, tostring(off) .. ' ' .. tostring(tip_off));
off, tip_off = greyed('SliderFloat', 'Flash length');
check('Flash length greys out with the flash off', off == true and tip_off == false,
    tostring(off) .. ' ' .. tostring(tip_off));
check('the other sliders stay live', greyed('SliderFloat', 'Scale') == false);
s.attack.almost_ready, s.enemy.almost_ready, s.resting.flash_on_tick = true, true, true;

-- The other sliders that grey out work the same way, with their (?) outside.
s.attack.numbers_only, s.enemy.attached, s.style.show_labels = true, true, false;
seen = walk(frames(1));
for _, slider in ipairs({ 'Bar height##attack', 'Width##enemy', 'Label size' }) do
    off, tip_off = greyed('SliderInt', slider);
    check(slider .. ' greys out, its (?) doesn\'t', off == true and tip_off == false,
        tostring(off) .. ' ' .. tostring(tip_off));
end
check('Bar height##resting stays live', greyed('SliderInt', 'Bar height##resting') == false);
check('Height stays live for a text-only timer', greyed('SliderFloat', 'Height##attack') == false);
check('Height stays live for the attached enemy timer', greyed('SliderFloat', 'Height##enemy') == false);
s.attack.numbers_only, s.enemy.attached, s.style.show_labels = false, false, true;
seen = walk(frames(1));
for _, slider in ipairs({ 'Bar height##attack', 'Width##enemy', 'Label size' }) do
    check(slider .. ' is live again', greyed('SliderInt', slider) == false);
end

-- Fill ------------------------------------------------------------------------------------------
local plain, muted = 0, 0;
for _, e in ipairs(seen) do
    if (e.label == 'Fill' and e.name == 'TextUnformatted') then plain = plain + 1; end
    if (e.label == 'Fill' and e.name == 'TextColored') then muted = muted + 1; end
end
check('Fill is plain text on all five bars', plain == 5 and muted == 0, plain .. ' plain, ' .. muted .. ' colored');

-- A timer that's off --------------------------------------------------------------------------------
-- The enemy timer is off by default. Both of its sections are faint, with one line under its heading.
local function notes(list)
    local n = 0;
    for _, e in ipairs(list) do if (e.name == 'TextUnformatted' and e.label == OFF_NOTE) then n = n + 1; end end
    return n;
end
check('the enemy timer is off by default', s.enemy.enabled == false);
check('its settings are faint', find(seen, 'BeginCombo', 'Follows##enemy').alpha < 1
    and find(seen, 'Checkbox', 'On you').alpha < 1, find(seen, 'BeginCombo', 'Follows##enemy').alpha);
check('its bar settings too', find(seen, 'Checkbox', 'Text only##enemy').alpha < 1
    and find(seen, 'SliderFloat', 'Almost ready at##enemy').alpha < 1);
check('faint isn\'t greyed out, so they still work', not find(seen, 'BeginCombo', 'Follows##enemy').disabled
    and not find(seen, 'Checkbox', 'Keep the last monster').disabled
    and not find(seen, 'Checkbox', 'Text only##enemy').disabled);
local _, chip = find(seen, 'Button', 'OFF##enemy');
local note, at = find(seen, 'TextUnformatted', OFF_NOTE);
local _, follows = find(seen, 'BeginCombo', 'Follows##enemy');
check('a line under its heading says it isn\'t on screen', note ~= nil and chip < at and at < follows);
check('the heading, its chip and that line are at full strength', note ~= nil and note.alpha == 1
    and seen[chip].alpha == 1 and find(seen, 'TextColored', 'ENEMY ATTACK TIMER').alpha == 1);
check('only one line for it', notes(seen) == 1, notes(seen));
check('the timers that are on aren\'t faint', find(seen, 'Checkbox', 'Seconds left##attack').alpha == 1
    and find(seen, 'Checkbox', 'Seconds left##resting').alpha == 1);
check('the Appearance tab isn\'t faint', find(seen, 'SliderFloat', 'Scale').alpha == 1);

s.enemy.enabled = true;
seen = walk(frames(1));
check('turned on, the enemy settings are full strength', find(seen, 'BeginCombo', 'Follows##enemy').alpha == 1
    and find(seen, 'SliderFloat', 'Almost ready at##enemy').alpha == 1 and notes(seen) == 0);
s.enemycast.enabled = false;
seen = walk(frames(1));
check('casting off has its own faint controls and one independent note', find(seen, 'Checkbox', 'Spell name##enemycast').alpha < 1
    and find(seen, 'Checkbox', 'Seconds left##enemycast').alpha < 1 and notes(seen) == 1
    and find(seen, 'BeginCombo', 'Follows##enemy').alpha == 1);
s.enemycast.enabled = true;

s.attack.enabled = false;
local calls = frames(1);
seen = walk(calls);
check('auto attack off, its settings are faint', find(seen, 'Checkbox', 'Seconds left##attack').alpha < 1
    and find(seen, 'Checkbox', 'Why it stopped').alpha < 1);
check('and still work', not find(seen, 'Checkbox', 'Seconds left##attack').disabled);
check('the resting timer next to it isn\'t', find(seen, 'Checkbox', 'Seconds left##resting').alpha == 1
    and find(seen, 'Checkbox', 'Hide during events').alpha == 1);
check('one line says so', notes(seen) == 1, notes(seen));
check('pushes and pops match', balanced(calls));
s.attack.enabled = true;

s.resting.enabled = false;
calls = frames(1);
seen = walk(calls);
check('resting off, its settings are faint', find(seen, 'Checkbox', 'Seconds left##resting').alpha < 1
    and find(seen, 'SliderFloat', 'Flash length').alpha < 1);
check('the settings for all timers aren\'t', find(seen, 'Checkbox', 'Hide during events').alpha == 1
    and find(seen, 'Checkbox', 'Hide with the game UI').alpha == 1);
check('pushes and pops match here too', balanced(calls));

-- A color picker or dropdown opened from a faint section is drawn at full strength.
rawset(imgui, 'IsPopupOpen', function (_, flags) return flags == ImGuiPopupFlags_AnyPopupId; end);
seen = walk(frames(1));
rawset(imgui, 'IsPopupOpen', nil);
check('with a picker open, the section is full strength', find(seen, 'Checkbox', 'Seconds left##resting').alpha == 1
    and find(seen, 'SliderFloat', 'Flash length').alpha == 1);
check('and still says the timer is off', notes(seen) == 1, notes(seen));

-- A (?) in a faint section shows its tip at full strength.
s.enemy.enabled, s.resting.numbers_only = false, true;
rawset(imgui, 'IsItemHovered', function () return true; end);
calls = frames(1);
rawset(imgui, 'IsItemHovered', nil);
seen = walk(calls);
local tips, faint_tips, dim_tips = 0, 0, 0;
for i, e in ipairs(seen) do
    if (e.name == 'BeginTooltip') then
        tips = tips + 1;
        if (e.alpha ~= 1) then dim_tips = dim_tips + 1; end
        -- The (?) it belongs to.
        for j = i - 1, 1, -1 do
            if (seen[j].name == 'TextDisabled') then
                if (seen[j].alpha < 1) then faint_tips = faint_tips + 1; end
                break;
            end
        end
    end
end
check('tips over faint settings are full strength', tips > 0 and faint_tips > 10 and dim_tips == 0,
    tips .. ' tips, ' .. faint_tips .. ' over faint settings, ' .. dim_tips .. ' dim');
check('hovering keeps pushes and pops matched', balanced(calls));
s.enemy.enabled, s.resting.enabled, s.resting.numbers_only = false, true, false;

-- Show them ---------------------------------------------------------------------------------------
local function windows_named(list, name)
    local n = 0;
    for _, c in ipairs(list) do if (c[1] == 'Begin' and c[2] == name) then n = n + 1; end end
    return n;
end
seen = walk(frames(1));
check('no Show them while the timers show', find(seen, 'Button', 'Show them') == nil);
MOCK.fire('command', { command = '/cadence hide' });
calls = frames(1);
seen = walk(calls);
local show, show_at = find(seen, 'Button', 'Show them');
local hidden_note, hidden_at = find(seen, 'TextUnformatted', 'The timers are hidden.');
check('the hidden note has a Show them button', show ~= nil and hidden_note ~= nil and hidden_at < show_at);
local _, show_help = help_after(seen, show_at);
local _, tabs_at = find(seen, 'BeginTabBar', '##cadence_tabs');
check('with a (?)', show_help ~= nil and show_help < tabs_at, tostring(show_help) .. ' ' .. tostring(tabs_at));
check('the timers are hidden', windows_named(calls, '##cadence_attack') == 0);

rawset(imgui, 'IsItemHovered', function () return true; end);
calls = frames(1);
rawset(imgui, 'IsItemHovered', nil);
local tip, after = nil, false;
for _, c in ipairs(calls) do
    if (c[1] == 'Button') then after = c[2] == 'Show them'; end
    if (after and tip == nil and c[1] == 'TextUnformatted') then tip = tostring(c[2]); end
end
check('its tip says the commands do the same', tip ~= nil and tip:find('/cadence show', 1, true) ~= nil
    and tip:find(';', 1, true) == nil and #tip <= 200, tip);

local saves = MOCK.saved;
rawset(imgui, 'Button', function (label) return label == 'Show them'; end);
frames(1);
rawset(imgui, 'Button', nil);
calls = frames(1);
check('Show them brings the timers back', windows_named(calls, '##cadence_attack') == 1
    and find(walk(calls), 'Button', 'Show them') == nil, windows_named(calls, '##cadence_attack'));
check('and isn\'t saved, like /cadence show', MOCK.saved == saves, MOCK.saved - saves);
-- Pressing it once doesn't keep bringing them back.
MOCK.fire('command', { command = '/cadence hide' });
calls = frames(2);
check('/cadence hide hides them again after', windows_named(calls, '##cadence_attack') == 0,
    windows_named(calls, '##cadence_attack'));
MOCK.fire('command', { command = '/cadence show' });

-- Undo and Reset look ------------------------------------------------------------------------------
calls = frames(1);
seen = walk(calls);
local _, heading_at = find(seen, 'TextColored', 'PRESET');
local _, undo_at = find(seen, 'SmallButton', 'Undo');
local _, reset_at = find(seen, 'SmallButton', 'Reset look');
local _, combo_at = find(seen, 'BeginCombo', 'Preset');
check('Undo and Reset look sit on the PRESET heading, above the dropdown', heading_at and undo_at and reset_at
    and combo_at and heading_at < undo_at and undo_at < reset_at and reset_at < combo_at,
    tostring(heading_at) .. ' ' .. tostring(undo_at) .. ' ' .. tostring(reset_at) .. ' ' .. tostring(combo_at));
local _, undo_help = help_after(seen, undo_at);
local _, reset_help = help_after(seen, reset_at);
check('each with a (?)', undo_help and reset_help and undo_help < reset_at and reset_help < combo_at);
check('Reset look isn\'t under POSITION', find(seen, 'Button', 'Reset look') == nil
    and find(seen, 'Button', 'Reset positions') ~= nil);

-- They end at the right edge of the column, like a timer's ON/OFF chip. The mock measures 7 px a
-- letter, with a column 792 wide starting at 0.
local line = nil;
for i, c in ipairs(calls) do
    if (c[1] == 'SmallButton' and c[2] == 'Undo') then
        for j = i - 1, 1, -1 do
            if (calls[j][1] == 'SameLine') then line = calls[j][2]; break; end
        end
        break;
    end
end
local function letters(text) return #text * 7; end
local right_end = line and (line + letters('Undo') + 16 + 8 + letters('(?)') + 8 + letters('Reset look') + 16 + 8
    + letters('(?)'));
check('they end at the column\'s right edge', right_end == 792, tostring(line) .. ' -> ' .. tostring(right_end));

s.style.scale, s.attack.width = 2.0, 400;
rawset(imgui, 'SmallButton', function (label) return label == 'Reset look'; end);
frames(1);
rawset(imgui, 'SmallButton', nil);
check('Reset look still resets the look', s.style.scale == 1.0 and s.attack.width == 240,
    s.style.scale .. ' ' .. s.attack.width);

-- Drain instead of fill ----------------------------------------------------------------------------
local _, look_at = find(seen, 'BeginTabItem', 'Appearance');
local _, drain_at = find(seen, 'Checkbox', 'Drain instead of fill');
local _, font_at = find(seen, 'BeginCombo', 'Font');
local _, lock_at = find(seen, 'Checkbox', 'Lock in place');
check('Drain instead of fill is on the Appearance tab, under Font', look_at and drain_at and drain_at > look_at
    and drain_at > font_at and drain_at < lock_at, tostring(look_at) .. ' ' .. tostring(drain_at));
local _, drain_help = help_after(seen, drain_at);
check('with a (?)', drain_help ~= nil and drain_help < lock_at);
local drains = 0;
for _, e in ipairs(seen) do
    if (e.name == 'Checkbox' and e.label == 'Drain instead of fill') then drains = drains + 1; end
end
check('and nowhere else', drains == 1, drains);
saves = MOCK.saved;
rawset(imgui, 'Checkbox', function (label, value)
    if (label ~= 'Drain instead of fill') then return false; end
    value[1] = not value[1];
    return true;
end);
frames(1);
rawset(imgui, 'Checkbox', nil);
check('it still turns on and saves', s.style.bar_drains == true and MOCK.saved == saves + 1);
s.style.bar_drains = false;

-- The footer ---------------------------------------------------------------------------------------
local footer = nil;
for _, e in ipairs(seen) do
    if (e.name == 'TextUnformatted' and tostring(e.label):find('Ctrl+click a slider to type a value', 1, true)) then
        footer = e.label;
    end
end
check('the footer says Ctrl+click types a value', footer ~= nil and footer:find('Hold Shift', 1, true) ~= nil);

-- A color dropped on a swatch ------------------------------------------------------------------------
-- A drop changes the color without the swatch ever being held, so it saves right away. Dragging in the
-- picker holds it, so that saves once when it's let go.
local dropped, holding, let_go = nil, false, false;
rawset(imgui, 'ColorEdit4', function (label, value)
    if (label == dropped) then
        value[1] = 0.25;
        dropped = holding and dropped or nil;
        return true;
    end
    return false;
end);
rawset(imgui, 'IsItemActive', function () return holding; end);
rawset(imgui, 'IsItemDeactivatedAfterEdit', function () return let_go; end);
saves = MOCK.saved;
dropped = '##attack_start';
frames(1);
check('a color dropped on a swatch saves right away', MOCK.saved == saves + 1 and s.attack.fill_start[1] == 0.25,
    MOCK.saved - saves);
saves = MOCK.saved;
frames(3);
check('once', MOCK.saved == saves, MOCK.saved - saves);
dropped = 'Values##text';
frames(1);
check('a swatch with a name too', MOCK.saved == saves + 1 and s.style.value_color[1] == 0.25, MOCK.saved - saves);
saves = MOCK.saved;
holding, dropped = true, '##resting_end';
frames(5);
check('dragging in the picker doesn\'t save each frame', MOCK.saved == saves and s.resting.fill_end[1] == 0.25,
    MOCK.saved - saves);
holding, dropped, let_go = false, nil, true;
frames(1);
let_go = false;
check('it saves once you let go', MOCK.saved == saves + 1, MOCK.saved - saves);
for _, name in ipairs({ 'ColorEdit4', 'IsItemActive', 'IsItemDeactivatedAfterEdit' }) do rawset(imgui, name, nil); end
MOCK.fire('command', { command = '/cadence' });

-- Chat ------------------------------------------------------------------------------------------------
local function said(command)
    local before = #MOCK.printed;
    MOCK.fire('command', { command = command });
    local lines = {};
    for i = before + 1, #MOCK.printed do table.insert(lines, MOCK.printed[i]); end
    return lines;
end
local lines = said('/cadence lock');
check('lock says timers', (lines[1] or ''):find('The timers are locked in place.', 1, true) ~= nil, lines[1]);
lines = said('/cadence unlock');
check('unlock says timers', (lines[1] or ''):find('Hold Shift and drag a timer to move it.', 1, true) ~= nil, lines[1]);
lines = said('/cadence reset');
check('reset says timers', (lines[1] or ''):find('The timers are back at their default positions.', 1, true) ~= nil,
    lines[1]);
lines = said('/cadence Swing');
check('an unknown word says so in one line', #lines == 1
    and (lines[1] or ''):find('Didn\'t recognize "Swing". Type /cadence help to see the commands.', 1, true) ~= nil,
    lines[1]);
lines = said('/cadence help');
local reset_line = nil;
for _, line in ipairs(lines) do if (line:find('/cadence reset ', 1, true)) then reset_line = line; end end
check('help is just the help', (lines[1] or ''):find('opens or closes', 1, true) ~= nil, lines[1]);
check('the help says timers', (reset_line or ''):find('puts every timer back', 1, true) ~= nil, reset_line);
local element = nil;
for _, printed in ipairs(MOCK.printed) do if (printed:lower():find('element', 1, true)) then element = printed; end end
check('chat never says element', element == nil, element);

local errors = nil;
for _, printed in ipairs(MOCK.printed) do if (printed:find('Drawing stopped')) then errors = printed; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
