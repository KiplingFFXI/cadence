-- Every preset sets every color and card setting a preset is meant to, so none of them leaves a hole
-- that a color picker would trip over.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local presets = require('ui.presets');

local COLORS = {
    style   = { 'panel_color', 'border_color', 'accent_color', 'track_color', 'label_color', 'value_color', 'detail_color' },
    attack  = { 'fill_start', 'fill_end', 'ready_color', 'almost_color', 'tp_color' },
    resting = { 'fill_start', 'fill_end', 'full_color', 'flash_color' },
    enemy   = { 'fill_start', 'fill_end', 'ready_color', 'almost_color', 'on_you_color' },
};
check('Colorblind safe is on the list', presets.NAMES[#presets.NAMES] == 'Colorblind safe');
for _, name in ipairs(presets.NAMES) do
    presets.apply(s, name);
    local missing = {};
    for section, keys in pairs(COLORS) do
        for _, key in ipairs(keys) do
            local c = s[section][key];
            if (type(c) ~= 'table' or #c ~= 4) then table.insert(missing, section .. '.' .. key); end
        end
    end
    for _, key in ipairs({ 'panel', 'border', 'accent', 'text_shadow' }) do
        if (type(s.style[key]) ~= 'boolean') then table.insert(missing, 'style.' .. key); end
    end
    if (type(s.style.rounding) ~= 'number') then table.insert(missing, 'style.rounding'); end
    check(name .. ' sets everything', #missing == 0, table.concat(missing, ', '));
end

-- Colorblind safe, as picked.
presets.apply(s, 'Colorblind safe');
local function same(c, r, g, b) return math.abs(c[1] - r / 255) < 0.002 and math.abs(c[2] - g / 255) < 0.002 and math.abs(c[3] - b / 255) < 0.002; end
check('blue bars', same(s.attack.fill_start, 0x00, 0x72, 0xb2) and same(s.attack.fill_end, 0x56, 0xb4, 0xe9));
check('vermillion for almost ready, yellow for ready', same(s.attack.almost_color, 0xd5, 0x5e, 0x00)
    and same(s.attack.ready_color, 0xf0, 0xe4, 0x42));
check('yellow once full', same(s.resting.full_color, 0xf0, 0xe4, 0x42));
check('a grey enemy bar', same(s.enemy.fill_end, 0xbd, 0xbd, 0xbd));

-- Ember, as picked, with every color typed out so a slip shows up. It comes right before Colorblind safe.
check('Ember is on the list', presets.NAMES[#presets.NAMES - 1] == 'Ember'
    and presets.IDS[#presets.IDS - 1] == 'ember');
presets.apply(s, 'Ember');
local EMBER = {
    style   = { panel_color = { '2a1d12', 0.88 }, border_color = { 'ffb070', 0.25 }, accent_color = { 'e8742a' },
        track_color = { '3a2716' }, label_color = { 'ffc38a' }, value_color = { 'fff4e8' }, detail_color = { 'c4a07e' } },
    attack  = { fill_start = { 'b4471c' }, fill_end = { 'f08a3c' }, ready_color = { 'fff4e8' },
        almost_color = { 'ffd23f' }, tp_color = { '8fcf6a' } },
    resting = { fill_start = { 'b4471c' }, fill_end = { 'f08a3c' }, full_color = { 'b4f0b4' },
        flash_color = { 'ffa04d', 0.45 } },
    enemy   = { fill_start = { '6b6058' }, fill_end = { 'b2a798' }, ready_color = { 'f2402a' },
        almost_color = { 'ffd23f' }, on_you_color = { 'ffffff' } },
};
local wrong = nil;
for section, colors in pairs(EMBER) do
    for key, want in pairs(colors) do
        local c, v = s[section][key], tonumber(want[1], 16);
        if (not same(c, math.floor(v / 65536), math.floor(v / 256) % 256, v % 256)
            or math.abs(c[4] - (want[2] or 1)) > 0.002) then
            wrong = wrong or (section .. '.' .. key);
        end
    end
end
check('Ember sets each of its colors', wrong == nil, wrong);
check('Ember has a card with a border and stripe, a text shadow, 2 px corners and its own window look',
    s.style.panel and s.style.border and s.style.accent and s.style.text_shadow and s.style.rounding == 2
    and s.style.window_look == 'ember', s.style.window_look);

-- The look you have -------------------------------------------------------------------------------------
presets.reset(s);
check('the default look is Phoenix', presets.current(s) == 'Phoenix', presets.current(s));
for _, name in ipairs(presets.NAMES) do
    presets.apply(s, name);
    check('picking ' .. name .. ' shows it', presets.current(s) == name, presets.current(s));
end
presets.apply(s, 'Minimal');
s.style.accent_color[1] = s.style.accent_color[1] + 0.001;
check('a color a hair off after saving still counts', presets.current(s) == 'Minimal');
s.style.accent_color[1] = s.style.accent_color[1] + 0.1;
check('a color you changed makes it Custom', presets.current(s) == nil);
presets.apply(s, 'Minimal');
s.style.text_shadow = not s.style.text_shadow;
check('the shadow counts too', presets.current(s) == nil);
presets.apply(s, 'Minimal');
s.attack.width = 400;
check('the width isn\'t part of a look', presets.current(s) == 'Minimal');
presets.reset(s);
check('Reset look is Phoenix again', presets.current(s) == 'Phoenix');

-- The dropdown shows it, and marks it in the list.
local imgui = require('imgui');
local function dropdown()
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    local shown, marked = nil, {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'BeginCombo' and c[2] == 'Preset') then shown = c[3]; end
        if (c[1] == 'Selectable' and c[3] == true) then table.insert(marked, c[2]); end
    end
    return shown, table.concat(marked, ',');
end
MOCK.fire('command', { command = '/cadence' });
-- Opens only the Preset dropdown, and still records the call.
rawset(imgui, 'BeginCombo', function (label, preview)
    if (MOCK.record_imgui) then table.insert(MOCK.imgui_calls, { 'BeginCombo', label, preview }); end
    return label == 'Preset';
end);
presets.apply(s, 'Classic FFXI');
local shown, marked = dropdown();
check('the dropdown shows the look you have', shown == 'Classic FFXI' and marked == 'Classic FFXI', shown .. ' ' .. marked);
s.style.rounding = s.style.rounding + 1;
shown, marked = dropdown();
check('and Custom from it once you change it', shown == 'Custom (from Classic FFXI)' and marked == '',
    shown .. ' ' .. marked);

-- Custom names the last preset you picked, typed out so a slip shows up. No row is marked, since your
-- look isn't any of them.
local FROM = { 'Custom (from Phoenix)', 'Custom (from Classic FFXI)', 'Custom (from Minimal)',
    'Custom (from High contrast)', 'Custom (from Ember)', 'Custom (from Colorblind safe)' };
for i, name in ipairs(presets.NAMES) do
    presets.apply(s, name);
    s.style.rounding = s.style.rounding + 1;
    shown, marked = dropdown();
    check(name .. ' changed says ' .. FROM[i], shown == FROM[i] and marked == '', shown .. ' ' .. marked);
end
presets.reset(s);
s.style.rounding = s.style.rounding + 1;
shown = dropdown();
check('a change after Reset look is Custom from Phoenix', shown == 'Custom (from Phoenix)', shown);

-- Clicks a preset in the list for one frame.
local function click(name)
    rawset(imgui, 'Selectable', function (label) return label == name; end);
    MOCK.frame(1 / 60);
    rawset(imgui, 'Selectable', nil);
end

-- Picking the preset your look came from puts its look back, and Undo brings back your change.
presets.apply(s, 'Minimal');
presets.forget_undo();
s.style.rounding = 9;
local saves = MOCK.saved;
click('Minimal');
shown, marked = dropdown();
check('picking the preset it came from puts its look back', shown == 'Minimal' and marked == 'Minimal'
    and s.style.rounding == 3 and MOCK.saved > saves, shown .. ' ' .. marked .. ' ' .. s.style.rounding);
presets.undo(s);
shown = dropdown();
check('and Undo brings back your change', s.style.rounding == 9 and shown == 'Custom (from Minimal)', shown);

-- Picking another preset, then Undo, brings back your look and the preset it came from.
click('Ember');
shown = dropdown();
check('another preset shows that one', shown == 'Ember', shown);
presets.undo(s);
shown = dropdown();
check('and Undo makes it Custom from the first one again', s.style.rounding == 9
    and shown == 'Custom (from Minimal)', shown);

-- A preset id that isn't on the list gets plain Custom.
s.style.window_look = 'gone';
shown = dropdown();
check('an id it doesn\'t know is plain Custom', shown == 'Custom' and presets.custom_name('gone') == 'Custom'
    and presets.custom_name(nil) == 'Custom', shown);
presets.reset(s);
presets.forget_undo();

-- The list is wide enough for its longest name, with 8 of padding on each side and the arrow, as wide as
-- the frame is tall. The mock measures 7 px a letter, in a column 792 wide.
local function list_width()
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    local width = nil;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'SetNextItemWidth') then width = c[2]; end
        if (c[1] == 'BeginCombo' and c[2] == 'Preset') then return width; end
    end
    return nil;
end
local function letters(text) return #text * 7; end
local fits = letters('Custom (from Colorblind safe)') + 16 + 18 + 8;
check('the list fits Custom from Colorblind safe', list_width() == fits, list_width());
-- Whichever name is longest in this font, even one in the middle of the list.
MOCK.measure = function (text) return text:find('Minimal', 1, true) and 300 or #text * 7; end
check('or whichever name is longest', list_width() == 300 + 16 + 26, list_width());
MOCK.measure = nil;
-- A narrow column cuts it down so its (?) still ends at the column's edge.
MOCK.content_width = 300;
local room = 300 - 4 - letters('Preset') - 8 - letters('(?)');
check('a narrow column cuts it down to the room next to its name and (?)', list_width() == room, list_width());
MOCK.content_width = 200;
check('but never under the other controls', list_width() == 190, list_width());
MOCK.content_width = nil;
-- At 24 px it measures in that font, and the arrow and the other controls grow with it.
s.window_style.font_size = 24;
MOCK.measure = function (text, px) return #text * px / 2; end
check('at 24 px it fits the name in that font', list_width() == 29 * 12 + 16 + 24 + 8, list_width());
MOCK.measure = function (text) return #text; end
check('and never goes under the other controls at that size', list_width() == math.floor(190 * 24 / 18 + 0.5),
    list_width());
MOCK.measure = nil;
s.window_style.font_size = 18;
-- Clicking the look you already have leaves it, and leaves Undo able to bring back yours.
presets.reset(s);
presets.forget_undo();
s.style.rounding = 9;
presets.apply(s, 'Minimal');
local pick = 'Minimal';
rawset(imgui, 'Selectable', function (label) return label == pick; end);
MOCK.frame(1 / 60);
rawset(imgui, 'Selectable', nil);
presets.undo(s);
check('clicking the look you have keeps Undo', s.style.rounding == 9, s.style.rounding);
rawset(imgui, 'BeginCombo', nil);
MOCK.fire('command', { command = '/cadence' });
presets.reset(s);
presets.forget_undo();

-- Undo -----------------------------------------------------------------------------------------------
presets.reset(s);
presets.undo(s);
check('nothing to undo after an undo', not presets.can_undo() and presets.undo(s) == false);

-- A look of your own, then a preset, then Undo puts your look back.
s.style.accent_color[1], s.style.panel, s.style.rounding = 0.3, false, 9;
s.attack.width = 300;
presets.apply(s, 'Minimal');
check('a preset can be undone', presets.can_undo());
check('the preset changed the look', s.style.accent_color[1] ~= 0.3 and s.style.rounding == 3);
presets.undo(s);
check('undo puts your colors back', math.abs(s.style.accent_color[1] - 0.3) < 1e-9 and s.style.panel == false
    and s.style.rounding == 9);
check('a preset never touched the width, so undo leaves it', s.attack.width == 300);
check('one step only', not presets.can_undo() and presets.undo(s) == false);

-- The color put back is its own table, so editing it can't change what Undo kept.
presets.apply(s, 'High contrast');
presets.undo(s);
local restored = s.style.accent_color;
restored[1] = 0.9;
presets.apply(s, 'Minimal');
presets.undo(s);
check('undo keeps its own copy', math.abs(s.style.accent_color[1] - 0.9) < 1e-9 and s.style.accent_color ~= restored);

-- Two presets in a row, then Undo, goes back to the first.
presets.apply(s, 'Classic FFXI');
local classic_track = s.style.track_color[3];
presets.apply(s, 'Colorblind safe');
presets.undo(s);
check('undo goes back one preset', math.abs(s.style.track_color[3] - classic_track) < 1e-9);

-- Reset look can be undone too, sizes and labels included.
s.attack.width, s.attack.label_text, s.style.font_name, s.style.label_size = 333, 'AA', 'Verdana Bold', 20;
presets.reset(s);
check('reset look changed them', s.attack.width == 240 and s.attack.label_text == '');
presets.undo(s);
check('undo puts back what Reset look changed', s.attack.width == 333 and s.attack.label_text == 'AA'
    and s.style.font_name == 'Verdana Bold' and s.style.label_size == 20);

-- Another character logging in drops the undo, so this one's look can't land on theirs.
presets.apply(s, 'Minimal');
MOCK.settings.switch_character(nil);
check('a character switch drops it', not presets.can_undo());
s = MOCK.settings.current;

-- The Undo button on the PRESET heading, greyed out with nothing to undo.
local imgui = require('imgui');
local function undo_greyed()
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    for i, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'SmallButton' and c[2] == 'Undo') then
            local before = MOCK.imgui_calls[i - 1];
            return before and before[1] == 'BeginDisabled' and before[2] == true;
        end
    end
end
MOCK.fire('command', { command = '/cadence' });
check('greyed out with nothing to undo', undo_greyed() == true);
presets.apply(s, 'Minimal');
check('live after a preset', undo_greyed() == false);
rawset(imgui, 'SmallButton', function (label) return label == 'Undo'; end);
MOCK.frame(1 / 60);
rawset(imgui, 'SmallButton', nil);
check('pressing it undoes the preset', not presets.can_undo() and s.style.rounding ~= 3);
MOCK.fire('command', { command = '/cadence' });

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
