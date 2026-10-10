-- The settings window's look. Each preset's palette spread over every window color in your settings,
-- the window drawing from those settings, its edges in the look's own colors and Phoenix keeping its own
-- window colors. Then Undo and Reset look, Window matches the look and its command, the settings check,
-- no Phoenix color left in another look, and every palette's text easy to read, on slider handles,
-- dropdown rows and pressed buttons too.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

-- Every ImGui color and corner size gets a number of its own, so each push can be told apart. They're
-- set before cadence loads, since theme.lua reads them then.
local COLOR_NAMES = {
    'Text', 'TextDisabled', 'WindowBg', 'ChildBg', 'PopupBg', 'Border', 'BorderShadow', 'FrameBg', 'FrameBgHovered',
    'FrameBgActive', 'TitleBg', 'TitleBgActive', 'TitleBgCollapsed', 'MenuBarBg', 'ScrollbarBg', 'ScrollbarGrab',
    'ScrollbarGrabHovered', 'ScrollbarGrabActive', 'CheckMark', 'SliderGrab', 'SliderGrabActive', 'Button',
    'ButtonHovered', 'ButtonActive', 'Header', 'HeaderHovered', 'HeaderActive', 'Separator', 'SeparatorHovered',
    'SeparatorActive', 'ResizeGrip', 'ResizeGripHovered', 'ResizeGripActive', 'InputTextCursor', 'TabHovered', 'Tab',
    'TabSelected', 'TabSelectedOverline', 'TabDimmed', 'TabDimmedSelected', 'TabDimmedSelectedOverline',
    'TableHeaderBg', 'TextLink', 'TextSelectedBg', 'DragDropTarget', 'NavCursor', 'ModalWindowDimBg',
};
local SLOT_NAME = {};
for i, name in ipairs(COLOR_NAMES) do
    _G['ImGuiCol_' .. name] = 1000 + i;
    SLOT_NAME[1000 + i] = name;
end
local ROUNDED = { 'WindowRounding', 'ChildRounding', 'FrameRounding', 'PopupRounding', 'GrabRounding', 'TabRounding',
    'ScrollbarRounding' };
local ROUNDED_NAME = {};
for i, name in ipairs(ROUNDED) do
    _G['ImGuiStyleVar_' .. name] = 2000 + i;
    ROUNDED_NAME[2000 + i] = name;
end
ImGuiStyleVar_ItemSpacing = 2100;

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
-- A shared layout left over from another test would turn One layout for all characters on.
os.remove(MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\shared_layout.json');

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local theme = require('ui.theme');
local presets = require('ui.presets');
local defaults = require('ui.defaults');
local settings_window = require('ui.settings_window');
local imgui = require('imgui');
MOCK.now = 100;

local function hex(value, alpha)
    return { tonumber(value:sub(1, 2), 16) / 255, tonumber(value:sub(3, 4), 16) / 255,
        tonumber(value:sub(5, 6), 16) / 255, alpha or 1 };
end
local function with_alpha(c, a) return { c[1], c[2], c[3], a }; end
local function same(a, b, slack)
    if (type(a) ~= 'table' or type(b) ~= 'table') then return false; end
    for i = 1, 4 do if (math.abs(a[i] - b[i]) > (slack or 0.002)) then return false; end end
    return true;
end
local function show(c)
    if (type(c) ~= 'table') then return tostring(c); end
    return ('%02x%02x%02x@%.2f'):format(c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5, c[4]);
end
local function mix(a, b, amount)
    return { a[1] + (b[1] - a[1]) * amount, a[2] + (b[2] - a[2]) * amount, a[3] + (b[3] - a[3]) * amount, a[4] };
end

--[[
    Each palette typed out again, so a slip in theme.lua shows up. All but Colorblind safe are
    checkmate's skins. After the eleven roles come the corners, the spacing, the ON chip's words, then
    the slider handle, the held handle, a pressed button, the picked and hovered dropdown rows, the
    heading lines and the scrollbar track. Phoenix picks those itself. In the others the text can't
    stand out on the accent, so they get a half solid handle and a faint pressed button. High
    contrast's spacing is 7, not checkmate's 8, so the Timers tab still fits with a timer off and the
    timers hidden.
]]
local ROLES = { 'background', 'card', 'control', 'hover', 'border', 'text', 'heading', 'muted', 'accent',
    'accent_hover', 'success' };
local function palette(list, rounding, spacing, on_accent, made)
    local p = { rounding = rounding, spacing = spacing, on_accent = hex(on_accent) };
    for i, role in ipairs(ROLES) do p[role] = hex(list[i][1], list[i][2]); end
    p.tint, p.selection = with_alpha(p.accent, 0.30), with_alpha(p.accent, 0.35);
    p.grab, p.grab_held, p.pressed = made[1], made[2], made[3];
    p.row_picked, p.row_hovered, p.divider, p.track = made[4], made[5], made[6], made[7];
    return p;
end
local function light(accent, border, background)
    return { hex(accent, 0.5), hex(accent, 0.5), hex(accent, 0.40), hex(accent, 0.15), hex(accent, 0.40),
        hex(border[1], border[2]), hex(background[1], background[2]) };
end
local EXPECTED = {
    phoenix = palette({ { '180e0e', 0.96 }, { '291c1c' }, { '321f1f' }, { '3a2525' }, { 'd2abab', 0.20 }, { 'fff8f8' },
        { 'd2abab' }, { '8a6b6b' }, { 'c55151' }, { 'ff8d79' }, { '63ba8a' } }, 0, 7, 'fff8f8',
        { hex('c55151'), hex('d45e5e'), hex('c55151'), hex('c55151', 0.45), hex('c55151', 0.70), hex('d2abab', 0.12),
            hex('180e0e') }),
    classic = palette({ { '0b1a3d', 0.94 }, { '13275a' }, { '1b3470' }, { '27468c' }, { '8ea3d6', 0.55 }, { 'ffffff' },
        { 'f2e6c4' }, { '9fb0d8' }, { 'e8c86a' }, { 'ffe08a' }, { '7ee08a' } }, 4, 7, '0b1a3d',
        light('e8c86a', { '8ea3d6', 0.55 }, { '0b1a3d', 0.94 })),
    minimal = palette({ { '1e1e1e', 0.96 }, { '2a2a2a' }, { '333333' }, { '404040' }, { 'ffffff', 0.15 }, { 'f2f2f2' },
        { 'cfcfcf' }, { '8c8c8c' }, { 'd0d0d0' }, { 'ffffff' }, { '9be3b5' } }, 3, 6, '1e1e1e',
        light('d0d0d0', { 'ffffff', 0.15 }, { '1e1e1e', 0.96 })),
    contrast = palette({ { '000000' }, { '141414' }, { '262626' }, { '3d3d3d' }, { 'ffffff', 0.70 }, { 'ffffff' },
        { 'ffe066' }, { 'c8c8c8' }, { 'ffd000' }, { 'ffe866' }, { '39ff14' } }, 0, 7, '000000',
        light('ffd000', { 'ffffff', 0.70 }, { '000000' })),
    ember = palette({ { '1a120c', 0.96 }, { '2a1d12' }, { '3a2716' }, { '4a321c' }, { 'ffb070', 0.25 }, { 'fff4e8' },
        { 'ffc38a' }, { 'a07c5c' }, { 'e8742a' }, { 'ffa04d' }, { '8fcf6a' } }, 2, 7, '1a120c',
        light('e8742a', { 'ffb070', 0.25 }, { '1a120c', 0.96 })),
    mint = palette({ { '101f1b', 0.96 }, { '192f29' }, { '233d34' }, { '2e5446' }, { '8fe3ba', 0.35 }, { 'edf9f1' },
        { 'b1ebd0' }, { '9bbbad' }, { '74d9ad' }, { 'a4edcc' }, { '8fe3b7' } }, 4, 7, '101f1b',
        light('74d9ad', { '8fe3ba', 0.35 }, { '101f1b', 0.96 })),
    lavender = palette({ { '191523', 0.96 }, { '262033' }, { '342b45' }, { '463858' }, { 'cdb1f4', 0.35 }, { 'f3ecff' },
        { 'deccf7' }, { 'b5a5c9' }, { 'c3a0ed' }, { 'e4ccff' }, { 'a8d9c0' } }, 4, 7, '191523',
        light('c3a0ed', { 'cdb1f4', 0.35 }, { '191523', 0.96 })),
    colorblind = palette({ { '101418', 0.96 }, { '1b2129' }, { '252d37' }, { '313b47' }, { '56b4e9', 0.30 },
        { 'f2f2f2' }, { '9fd3f5' }, { '8f9aa6' }, { '56b4e9' }, { '9fd3f5' }, { '56b4e9' } }, 2, 7, '101418',
        light('56b4e9', { '56b4e9', 0.30 }, { '101418', 0.96 })),
};
-- Problem messages take the accent. Colorblind safe's accent is the same blue as its success, so its
-- problems take Okabe and Ito's orange.
for _, p in pairs(EXPECTED) do p.problem = p.accent; end
EXPECTED.colorblind.problem = hex('e69f00');
EXPECTED.mint.problem, EXPECTED.lavender.problem = hex('ff8d79'), hex('ff8d79');
local NAME_OF = {};
for i, id in ipairs(presets.IDS) do NAME_OF[id] = presets.NAMES[i]; end

-- The window colors, and the palette role each one takes.
local SLOTS = {
    WindowBg = 'background', PopupBg = 'card', Border = 'border', Separator = 'divider', Text = 'text',
    TextDisabled = 'muted', TextSelectedBg = 'selection', InputTextCursor = 'text', DragDropTarget = 'accent',
    TitleBg = 'card', TitleBgActive = 'card', TitleBgCollapsed = 'card', FrameBg = 'control', FrameBgHovered = 'hover',
    FrameBgActive = 'tint', Button = 'control', ButtonHovered = 'hover', ButtonActive = 'pressed', CheckMark = 'accent',
    SliderGrab = 'grab', SliderGrabActive = 'grab_held', Header = 'row_picked', HeaderHovered = 'row_hovered',
    HeaderActive = 'pressed', Tab = 'card', TabHovered = 'hover', TabSelected = 'control',
    TabSelectedOverline = 'accent', TabDimmed = 'card', TabDimmedSelected = 'control',
    TabDimmedSelectedOverline = 'accent', ScrollbarBg = 'track', ScrollbarGrab = 'control',
    ScrollbarGrabHovered = 'hover', ScrollbarGrabActive = 'accent', ResizeGrip = 'hover', ResizeGripHovered = 'tint',
    ResizeGripActive = 'accent', SeparatorHovered = 'accent_hover', SeparatorActive = 'accent',
};

-- Records what the window pushes and writes, in order.
local events, rounding, spacing = {}, {}, nil;
local function record(kind, a, b)
    table.insert(events, { kind = kind, a = a, b = b });
end
local function copy_color(c) return { c[1], c[2], c[3], c[4] }; end
local function listen()
    rawset(imgui, 'PushStyleColor', function (slot, color) record('color', SLOT_NAME[slot], copy_color(color)); end);
    rawset(imgui, 'TextColored', function (color, words) record('text', words, copy_color(color)); end);
    rawset(imgui, 'CollapsingHeader', function (label)
        local last = events[#events];
        if (last and last.kind == 'color' and last.a == 'Text') then record('text', label:gsub('##.*$', ''), last.b); end
        return true;
    end);
    rawset(imgui, 'Button', function (label) record('button', label); return false; end);
    rawset(imgui, 'PushStyleVar', function (slot, value)
        if (ROUNDED_NAME[slot] ~= nil) then rounding[ROUNDED_NAME[slot]] = value; end
        if (slot == ImGuiStyleVar_ItemSpacing) then spacing = value[2]; end
    end);
end
local function stop_listening()
    for _, name in ipairs({ 'PushStyleColor', 'TextColored', 'CollapsingHeader', 'Button', 'PushStyleVar' }) do rawset(imgui, name, nil); end
end

settings_window.set_open(true);
local function draw(hidden)
    events, rounding, spacing = {}, {}, nil;
    listen();
    settings_window.draw(s, addon.version, hidden == true, false);
    stop_listening();
end

-- The first color pushed for each window color, which is the window's own.
local function window_colors()
    local first = {};
    for _, e in ipairs(events) do
        if (e.kind == 'color' and e.a ~= nil and first[e.a] == nil) then first[e.a] = e.b; end
    end
    return first;
end

-- What's wrong when the window doesn't wear `id`'s palette, or nil.
local function wears(id)
    local want, got = EXPECTED[id], window_colors();
    for slot, role in pairs(SLOTS) do
        if (not same(got[slot], want[role])) then return slot .. ' is ' .. show(got[slot]); end
    end
    if (not same(got.ChildBg, { 0, 0, 0, 0 })) then return 'ChildBg is ' .. show(got.ChildBg); end
    for _, name in ipairs(ROUNDED) do
        if (rounding[name] ~= want.rounding) then return name .. ' is ' .. tostring(rounding[name]); end
    end
    if (spacing ~= want.spacing) then return 'the spacing is ' .. tostring(spacing); end
    return nil;
end

-- The five pushes before a button, by window color.
local function chip(label)
    for i, e in ipairs(events) do
        if (e.kind == 'button' and e.a == label) then
            local found = {};
            for j = i - 5, i - 1 do found[events[j].a] = events[j].b; end
            return found;
        end
    end
    return {};
end

-- The colors of the headings, and of the notes and subtitle pushed after the window's own colors.
local function heading_colors()
    local found = {};
    for _, e in ipairs(events) do
        if (e.kind == 'text' and e.a:find('%a') and e.a == e.a:upper()) then found[e.a] = e.b; end
    end
    return found;
end
local function pushed_text_colors()
    local found, base = {}, true;
    for _, e in ipairs(events) do
        if (e.kind == 'color' and e.a == 'Text') then
            if (base) then base = false; else table.insert(found, e.b); end
        end
    end
    return found;
end
local function has(list, color)
    for _, c in ipairs(list) do if (same(c, color)) then return true; end end
    return false;
end

-- The palettes ----------------------------------------------------------------------------------------
local count = 0;
for id, p in pairs(theme.window_palettes) do
    count = count + 1;
    local want, wrong = EXPECTED[id], nil;
    if (want == nil) then
        wrong = 'not a preset';
    else
        for role, color in pairs(want) do
            if (type(color) == 'table' and not same(p[role], color)) then wrong = wrong or (role .. ' is ' .. show(p[role])); end
        end
        if (p.rounding ~= want.rounding or p.spacing ~= want.spacing) then
            wrong = wrong or ('rounding and spacing are ' .. tostring(p.rounding) .. ' ' .. tostring(p.spacing));
        end
    end
    check(id .. ' has its colors, roundness and spacing', wrong == nil, wrong);
end
check('one palette for each preset', count == #presets.IDS, count);

-- The window look in your settings ----------------------------------------------------------------------
do
    local keys, wrong, seen = 0, nil, {};
    for _, entry in ipairs(theme.WINDOW_COLORS) do
        keys = keys + 1;
        if (seen[entry.key]) then wrong = wrong or (entry.key .. ' twice'); end
        seen[entry.key] = true;
        if (not entry.key:match('^[a-z_]+$')) then wrong = wrong or (entry.key .. ' is not a plain word'); end
    end
    check('every window color has a key of its own', wrong == nil and keys == 44, wrong or keys);

    local fresh = defaults.make().window_style;
    local first, second = theme.window_style('classic'), theme.window_style('classic');
    wrong = nil;
    for _, entry in ipairs(theme.WINDOW_COLORS) do
        local want = theme.window_palettes.phoenix[entry.role];
        if (not same(fresh[entry.key], want)) then wrong = wrong or (entry.key .. ' is ' .. show(fresh[entry.key])); end
        if (rawequal(first[entry.key], second[entry.key]) or rawequal(first[entry.key], theme.window_palettes.classic[entry.role])) then
            wrong = wrong or (entry.key .. ' shares a table');
        end
    end
    check('the defaults are Phoenix spread over every key, each color in a table of its own', wrong == nil
        and fresh.rounding == 0 and fresh.spacing == 7 and first.rounding == 4, wrong);
    -- The window's font and font size live there too. A preset never sets them.
    local OWN = { rounding = true, spacing = true, font = true, font_size = true };
    local extra = nil;
    for key in pairs(fresh) do
        if (not OWN[key] and not seen[key]) then extra = key; end
    end
    check('and nothing else is in there but the font and its size', extra == nil, extra);
    check('a loaded character has it', type(s.window_style) == 'table' and same(s.window_style.text, fresh.text));
    local ranges = defaults.RANGES.window_style or { rounding = {}, spacing = {} };
    check('its corners go 0 to 12 and its spacing 2 to 14', ranges.rounding[1] == 0 and ranges.rounding[2] == 12
        and ranges.spacing[1] == 2 and ranges.spacing[2] == 14);
end

-- Each preset's palette on the window -------------------------------------------------------------------
presets.reset(s);
presets.forget_undo();
check('the ON and OFF chips both show', s.attack.enabled and not s.enemy.enabled);
for _, id in ipairs(presets.IDS) do
    presets.apply(s, NAME_OF[id]);
    draw(true);
    local want = EXPECTED[id];
    local wrong = wears(id);
    check(NAME_OF[id] .. ': the window takes its colors, roundness and spacing', wrong == nil, wrong);

    local headings = heading_colors();
    local wrong_heading = nil;
    for words, color in pairs(headings) do
        if (not same(color, want.heading)) then wrong_heading = words .. ' ' .. show(color); end
    end
    check(NAME_OF[id] .. ': headings', headings['PRESET'] ~= nil and headings['AUTO ATTACK TIMER'] ~= nil
        and headings['LABELS'] ~= nil and wrong_heading == nil, wrong_heading);
    local notes = pushed_text_colors();
    check(NAME_OF[id] .. ': the subtitle is faded and the notes are in the heading color',
        has(notes, want.muted) and has(notes, want.heading));

    local on, off = chip('ON##attack'), chip('OFF##enemy');
    local lit = mix(want.accent, want.accent_hover, 0.25);
    check(NAME_OF[id] .. ': the ON chip is filled with the accent and stays solid while pressed',
        same(on.Button, want.accent) and same(on.ButtonHovered, lit) and same(on.ButtonActive, want.accent)
        and same(on.Border, want.accent) and same(on.Text, want.on_accent),
        show(on.Button) .. ' ' .. show(on.ButtonHovered) .. ' ' .. show(on.ButtonActive) .. ' ' .. show(on.Text));
    check(NAME_OF[id] .. ': the OFF chip is outlined, and pressed like any button', same(off.Button, { 0, 0, 0, 0 })
        and same(off.ButtonHovered, with_alpha(want.accent, 0.30)) and same(off.ButtonActive, want.pressed)
        and same(off.Border, want.border) and same(off.Text, want.heading),
        show(off.ButtonActive) .. ' ' .. show(off.Border) .. ' ' .. show(off.Text));
end

-- Phoenix's own window colors ----------------------------------------------------------------------------
-- Typed out, the colors ImGui shows and both chips. The ON chip under the mouse is a hair off d45e5e.
do
    local WANT = {
        WindowBg = hex('180e0e', 0.96), ChildBg = { 0, 0, 0, 0 }, PopupBg = hex('291c1c'), Border = hex('d2abab', 0.20),
        Separator = hex('d2abab', 0.12), Text = hex('fff8f8'), TextDisabled = hex('8a6b6b'), TitleBg = hex('291c1c'),
        TitleBgActive = hex('291c1c'), TitleBgCollapsed = hex('291c1c'), FrameBg = hex('321f1f'),
        FrameBgHovered = hex('3a2525'), FrameBgActive = hex('c55151', 0.30), Button = hex('321f1f'),
        ButtonHovered = hex('3a2525'), ButtonActive = hex('c55151'), CheckMark = hex('c55151'),
        SliderGrab = hex('c55151'), SliderGrabActive = hex('d45e5e'), Header = hex('c55151', 0.45),
        HeaderHovered = hex('c55151', 0.70), HeaderActive = hex('c55151'), Tab = hex('291c1c'),
        TabHovered = hex('3a2525'), TabSelected = hex('321f1f'), TabSelectedOverline = hex('c55151'),
        TabDimmed = hex('291c1c'), TabDimmedSelected = hex('321f1f'), TabDimmedSelectedOverline = hex('c55151'),
        ScrollbarBg = hex('180e0e'), ScrollbarGrab = hex('321f1f'), ScrollbarGrabHovered = hex('3a2525'),
        ResizeGrip = hex('3a2525'), ResizeGripHovered = hex('c55151', 0.30), ResizeGripActive = hex('c55151'),
    };
    presets.reset(s);
    presets.forget_undo();
    draw();
    local got, wrong = window_colors(), nil;
    for slot, color in pairs(WANT) do
        if (not same(got[slot], color)) then wrong = wrong or (slot .. ' is ' .. show(got[slot])); end
    end
    check('Phoenix: every window color matches the list', wrong == nil, wrong);
    local on, off = chip('ON##attack'), chip('OFF##enemy');
    check('Phoenix: both chips match too', same(on.Button, hex('c55151')) and same(on.ButtonActive, hex('c55151'))
        and same(on.Text, hex('fff8f8')) and same(on.Border, hex('c55151')) and same(on.ButtonHovered, hex('d45e5e'), 0.015)
        and same(off.Button, { 0, 0, 0, 0 }) and same(off.ButtonHovered, hex('c55151', 0.30))
        and same(off.ButtonActive, hex('c55151')) and same(off.Text, hex('d2abab')) and same(off.Border, hex('d2abab', 0.20)),
        show(on.ButtonHovered));
    check('Phoenix: the rows between headings are 7 apart', spacing == 7, spacing);
end

-- No Phoenix color in another look -------------------------------------------------------------------------
-- The timer palette, the Phoenix window palette, and the other colors only Phoenix's window uses.
local PHOENIX = {};
for _, color in pairs(theme.palette) do table.insert(PHOENIX, color); end
for _, role in ipairs(ROLES) do table.insert(PHOENIX, EXPECTED.phoenix[role]); end
for _, color in ipairs({ hex('180e0e'), hex('d45e5e'), hex('c55151', 0.30), hex('c55151', 0.45), hex('c55151', 0.70),
        hex('d2abab', 0.12), hex('3a2525') }) do
    table.insert(PHOENIX, color);
end
rawset(imgui, 'IsItemHovered', function () return true; end);
for i = 2, #presets.IDS do
    presets.apply(s, presets.NAMES[i]);
    draw(true);
    local found = nil;
    for _, e in ipairs(events) do
        if (e.kind ~= 'button' and has(PHOENIX, e.b)) then found = tostring(e.a) .. ' ' .. show(e.b); end
    end
    check(presets.NAMES[i] .. ': no Phoenix color anywhere in the window, tips and both chips included',
        found == nil and #events > 60, found or #events);
end
rawset(imgui, 'IsItemHovered', nil);

-- The window draws from your settings -------------------------------------------------------------------
do
    presets.apply(s, 'Classic FFXI');
    local look = s.window_style;
    look.boxes = hex('123456');
    look.check_marks = hex('abcdef');
    look.title_bar_unfocused = hex('fedcba');
    look.on_chips = hex('00ff00');
    look.resize_edges_hovered = hex('0000ff');
    look.headings = hex('ff00ff');
    look.notes = hex('00ffff');
    look.rounding, look.spacing = 9, 11;
    draw();
    local got = window_colors();
    check('each window color comes from its key', same(got.FrameBg, hex('123456'))
        and same(got.SeparatorHovered, hex('0000ff')), show(got.FrameBg));
    check('a color with a second ImGui color sets both', same(got.CheckMark, hex('abcdef'))
        and same(got.DragDropTarget, hex('abcdef')) and same(got.TitleBg, hex('fedcba'))
        and same(got.TitleBgCollapsed, hex('fedcba')), show(got.DragDropTarget) .. ' ' .. show(got.TitleBgCollapsed));
    check('the corners and spacing come from it too', rounding.FrameRounding == 9 and spacing == 11,
        tostring(rounding.FrameRounding) .. ' ' .. tostring(spacing));
    local headings, notes = heading_colors(), pushed_text_colors();
    check('so do the headings and notes', same(headings['SIZE'], hex('ff00ff')) and has(notes, hex('00ffff')),
        show(headings['SIZE']));
    local on, off = chip('ON##attack'), chip('OFF##enemy');
    check('the chips under the mouse follow the ON chip color', same(on.Button, hex('00ff00'))
        and same(on.ButtonHovered, mix(hex('00ff00'), hex('0000ff'), 0.25))
        and same(off.ButtonHovered, hex('00ff00', 0.30)), show(on.ButtonHovered) .. ' ' .. show(off.ButtonHovered));
    check('a color you change makes the Preset list Custom', presets.current(s) == nil, presets.current(s));
    check('without touching the palette', same(theme.window_palettes.classic.control, hex('1b3470'))
        and same(theme.window_style('classic').boxes, hex('1b3470')));
    presets.apply(s, 'Classic FFXI');
    draw();
    check('picking the preset again puts the window back', wears('classic') == nil and presets.current(s) == 'Classic FFXI',
        wears('classic'));

    -- Garbage the mock makes isn't counted here. test_efficiency checks the window as a whole.
    local before = { s.window_style.on_chips[1], s.window_style.resize_edges_hovered[1] };
    draw();
    check('working out the chip colors changes no setting', s.window_style.on_chips[1] == before[1]
        and s.window_style.resize_edges_hovered[1] == before[2]);
end

-- Undo and Reset look -------------------------------------------------------------------------------------
presets.reset(s);
presets.forget_undo();
presets.apply(s, 'Classic FFXI');
draw();
check('picking a preset changes the window', wears('classic') == nil, wears('classic'));
presets.undo(s);
draw();
check('Undo brings the window back', wears('phoenix') == nil, wears('phoenix'));
MOCK.fire('command', { command = '/cadence preset minimal' });
rawset(imgui, 'SmallButton', function (label) return label == 'Reset look'; end);
MOCK.frame(1 / 60);
rawset(imgui, 'SmallButton', nil);
draw();
check('Reset look in the window brings back Phoenix', wears('phoenix') == nil, wears('phoenix'));
rawset(imgui, 'SmallButton', function (label) return label == 'Undo'; end);
MOCK.frame(1 / 60);
rawset(imgui, 'SmallButton', nil);
draw();
check('and Undo in the window takes that back', wears('minimal') == nil, wears('minimal'));

MOCK.fire('command', { command = '/cadence preset contrast' });
draw();
check('/cadence preset changes the window', wears('contrast') == nil, wears('contrast'));
MOCK.fire('command', { command = '/cadence undo' });
draw();
check('/cadence undo brings it back', wears('minimal') == nil, wears('minimal'));
MOCK.fire('command', { command = '/cadence reset look' });
draw();
check('/cadence reset look', wears('phoenix') == nil, wears('phoenix'));
MOCK.fire('command', { command = '/cadence undo' });

-- The Preset list in the window.
rawset(imgui, 'BeginCombo', function (label) return label == 'Preset'; end);
rawset(imgui, 'Selectable', function (label) return label == 'Colorblind safe'; end);
draw();
rawset(imgui, 'BeginCombo', nil);
rawset(imgui, 'Selectable', nil);
draw();
check('the Preset list changes the window on the next frame', wears('colorblind') == nil, wears('colorblind'));

-- A timer color you change keeps the window --------------------------------------------------------------
presets.apply(s, 'High contrast');
s.style.accent_color[1] = 0.5;
draw();
check('a timer color you change makes it Custom', presets.current(s) == nil);
check('and the window keeps its look', wears('contrast') == nil, wears('contrast'));
presets.apply(s, 'Colorblind safe');
s.style.rounding = 9;
draw();
check('the timers\' corner roundness isn\'t the window\'s', presets.current(s) == nil and wears('colorblind') == nil,
    wears('colorblind'));

-- Window matches the look ---------------------------------------------------------------------------------
presets.apply(s, 'Colorblind safe');
presets.forget_undo();
check('on by default', defaults.make().style.window_matches_look == true and s.style.window_matches_look == true);
s.style.window_matches_look = false;
draw();
check('turning it off leaves the window as it is', wears('colorblind') == nil, wears('colorblind'));
presets.apply(s, 'Classic FFXI');
draw();
check('off, a preset leaves the window alone', wears('colorblind') == nil, wears('colorblind'));
check('and the Preset list still shows the preset you picked', presets.current(s) == 'Classic FFXI', presets.current(s));
check('which is kept as the last preset picked', s.style.window_look == 'classic', s.style.window_look);
s.window_style.text[1] = 0.25;
check('a window color you change doesn\'t make it Custom', presets.current(s) == 'Classic FFXI', presets.current(s));
presets.undo(s);
check('Undo puts back the timers and leaves your window color', presets.current(s) == 'Colorblind safe'
    and s.window_style.text[1] == 0.25, presets.current(s));
presets.reset(s);
draw();
check('Reset look puts the window back to Phoenix even with it off', wears('phoenix') == nil
    and s.style.window_matches_look == false, wears('phoenix'));
presets.undo(s);
check('and Undo takes that back too', s.window_style.text[1] == 0.25 and s.window_style.boxes[1] == hex('252d37')[1],
    s.window_style.text[1]);
s.style.window_matches_look = true;
draw();
check('turning it on leaves the window as it is too', window_colors().Text[1] == 0.25
    and same(window_colors().FrameBg, EXPECTED.colorblind.control), show(window_colors().Text));
check('but your window color now counts, so the Preset list says Custom', presets.current(s) == nil, presets.current(s));
rawset(imgui, 'BeginCombo', function (label) return label == 'Preset'; end);
rawset(imgui, 'Selectable', function (label) return label == 'Colorblind safe'; end);
draw();
rawset(imgui, 'BeginCombo', nil);
rawset(imgui, 'Selectable', nil);
check('and picking it in the Preset list sets the window too', presets.current(s) == 'Colorblind safe', presets.current(s));
presets.apply(s, 'Classic FFXI');
draw();
check('on again, a preset sets the window', wears('classic') == nil, wears('classic'));

-- The command.
local function said(command)
    local before = #MOCK.printed;
    MOCK.fire('command', { command = command });
    local lines = {};
    for i = before + 1, #MOCK.printed do table.insert(lines, (MOCK.printed[i]:gsub('^%[cadence%] ', ''))); end
    return lines;
end
local saves = MOCK.saved;
local lines = said('/cadence windowlook off');
draw();
check('/cadence windowlook off', #lines == 1 and lines[1] == 'Window matches the look is off.'
    and s.style.window_matches_look == false and MOCK.saved == saves + 1 and wears('classic') == nil, lines[1]);
MOCK.fire('command', { command = '/cadence preset minimal' });
draw();
check('and a preset after it leaves the window', wears('classic') == nil, wears('classic'));
lines = said('/cadence windowlook');
draw();
check('/cadence windowlook flips it back on', lines[1] == 'Window matches the look is on.'
    and s.style.window_matches_look == true and wears('classic') == nil, lines[1]);
MOCK.fire('command', { command = '/cadence undo' });
check('unified Undo also restores the last checkbox change', s.style.window_matches_look == false);
MOCK.fire('command', { command = '/cadence windowlook on' });
MOCK.fire('command', { command = '/cadence preset classic' });

-- The box, right under the Preset list, with its (?).
rawset(imgui, 'IsItemHovered', function () return true; end);
MOCK.imgui_calls = {};
MOCK.record_imgui = true;
settings_window.draw(s, addon.version, false, false);
MOCK.record_imgui = false;
rawset(imgui, 'IsItemHovered', nil);
local combo_at, box_at, size_at, tip = nil, nil, nil, nil;
for i, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'BeginCombo' and c[2] == 'Preset') then combo_at = i; end
    if (c[1] == 'Checkbox' and c[2] == 'Window matches the look') then box_at = i; end
    if (c[1] == 'CollapsingHeader' and c[2] == 'SIZE##section') then size_at = i; end
    if (box_at ~= nil and tip == nil and i > box_at and c[1] == 'TextUnformatted') then tip = tostring(c[2]); end
end
check('the box sits under the Preset list, above SIZE', combo_at and box_at and size_at and combo_at < box_at
    and box_at < size_at, tostring(combo_at) .. ' ' .. tostring(box_at) .. ' ' .. tostring(size_at));
check('its tip is short and plain, and says what off does', tip ~= nil and #tip <= 200 and tip:find(';', 1, true) == nil
    and tip:find('spacing', 1, true) ~= nil and tip:find('Off, presets leave this window', 1, true) ~= nil, tip);
saves = MOCK.saved;
rawset(imgui, 'Checkbox', function (label, value)
    if (label ~= 'Window matches the look') then return false; end
    value[1] = not value[1];
    return true;
end);
MOCK.frame(1 / 60);
rawset(imgui, 'Checkbox', nil);
draw();
check('clicking it turns it off and saves', s.style.window_matches_look == false and MOCK.saved == saves + 1
    and wears('classic') == nil, MOCK.saved - saves);
s.style.window_matches_look = true;

-- The settings check ----------------------------------------------------------------------------------------
for _, bad in ipairs({ 'purple', 'Classic', 'classic ', '', 7, true, {} }) do
    local t = defaults.make();
    t.style.window_look = bad;
    defaults.tidy(t);
    local named = (type(bad) == 'string') and ('"' .. bad .. '"') or ('a ' .. type(bad));
    check('the settings check turns ' .. named .. ' into Phoenix', t.style.window_look == 'phoenix', t.style.window_look);
end
for _, id in ipairs(presets.IDS) do
    local t = defaults.make();
    t.style.window_look = id;
    defaults.tidy(t);
    check('and keeps ' .. id, t.style.window_look == id, t.style.window_look);
end
do
    local t = defaults.make();
    t.style.window_matches_look = 'yes';
    defaults.tidy(t);
    check('a box that isn\'t on or off gets its default', t.style.window_matches_look == true);

    t = defaults.make();
    local kept = t.window_style.text;
    kept[1] = 2;
    t.window_style.border = { 'red', 0, 0, 1 };
    t.window_style.headings = nil;
    t.window_style.spacing, t.window_style.rounding = 99, -4;
    defaults.tidy(t);
    local fresh = defaults.make().window_style;
    check('a window color is pulled into 0 to 1 in its own table', t.window_style.text[1] == 1
        and rawequal(t.window_style.text, kept));
    check('a broken or missing one gets the Phoenix color', same(t.window_style.border, fresh.border)
        and same(t.window_style.headings, fresh.headings));
    check('the window\'s spacing and corners are pulled into their range', t.window_style.spacing == 14
        and t.window_style.rounding == 0, t.window_style.spacing .. ' ' .. t.window_style.rounding);
end

-- Easy to read ----------------------------------------------------------------------------------------------
local function linear(part)
    if (part <= 0.04045) then return part / 12.92; end
    return ((part + 0.055) / 1.055) ^ 2.4;
end
local function luminance(c) return 0.2126 * linear(c[1]) + 0.7152 * linear(c[2]) + 0.0722 * linear(c[3]); end
local function ratio(a, b)
    local x, y = luminance(a) + 0.05, luminance(b) + 0.05;
    return math.max(x, y) / math.min(x, y);
end
-- A see-through color over a solid one.
local function over(top, under)
    local a = top[4];
    return { top[1] * a + under[1] * (1 - a), top[2] * a + under[2] * (1 - a), top[3] * a + under[3] * (1 - a), 1 };
end
for _, id in ipairs(presets.IDS) do
    local p, look = theme.window_palettes[id], theme.window_style(id);
    local grounds = {
        { 'background over black', over(p.background, { 0, 0, 0, 1 }) },
        { 'background over white', over(p.background, { 1, 1, 1, 1 }) },
        { 'card', p.card }, { 'control', p.control },
    };
    local worst = nil;
    for _, ground in ipairs(grounds) do
        for _, need in ipairs({ { 'text', 4.5 }, { 'heading', 3 }, { 'muted', 3 } }) do
            local r = ratio(p[need[1]], ground[2]);
            if (r < need[2]) then worst = ('%s on %s is %.2f'):format(need[1], ground[1], r); end
        end
    end
    check(id .. ': text, headings and faded text read on its background, card and controls', worst == nil, worst);

    -- The value on a slider sits on the handle, and the handle sits on the box.
    local solid = ratio(p.text, p.accent) >= 3;
    check(id .. ': the slider handle is the accent, or half solid when text can\'t read on the accent',
        same(look.slider_handles, solid and p.accent or with_alpha(p.accent, 0.5)), show(look.slider_handles));
    local still = ratio(look.text, over(look.slider_handles, look.boxes));
    local pointed = ratio(look.text, over(look.slider_handles, look.boxes_hovered));
    check(id .. ': text on the slider handle reads', still >= 3 and pointed >= 3, ('%.2f %.2f'):format(still, pointed));

    -- An open dropdown's rows sit on the dropdown's own color.
    local picked = over(look.row_picked, look.dropdowns);
    local hovered = over(look.row_hovered, look.dropdowns);
    local row = math.min(ratio(look.text, picked), ratio(look.text, hovered));
    check(id .. ': text reads on the picked and the hovered dropdown row', row >= 4.5, ('%.2f'):format(row));
    local step = ratio(picked, hovered);
    check(id .. ': the hovered row stands out from the picked one', step >= 1.3, ('%.2f'):format(step));

    local pressed = ratio(look.text, over(look.buttons_pressed, with_alpha(look.background, 1)));
    local clicked = ratio(look.text, over(look.row_clicked, look.dropdowns));
    check(id .. ': text reads on a pressed button and a clicked row', pressed >= 3 and clicked >= 3,
        ('%.2f %.2f'):format(pressed, clicked));
    local chip_words = ratio(look.on_chip_text, look.on_chips);
    check(id .. ': the ON chip\'s words read on it', chip_words >= 4, ('%.2f'):format(chip_words));

    -- What the Profiles tab says sits on the window's background, over a dark or a bright game.
    local dimmest = 99;
    for _, under in ipairs({ { 0, 0, 0, 1 }, { 1, 1, 1, 1 } }) do
        local ground = over(look.background, under);
        dimmest = math.min(dimmest, ratio(look.done_messages, ground), ratio(look.problem_messages, ground));
    end
    check(id .. ': done and problem messages read on the background', dimmest >= 3.5, ('%.2f'):format(dimmest));
    local apart = 0;
    for i = 1, 3 do apart = math.max(apart, math.abs(look.done_messages[i] - look.problem_messages[i])); end
    check(id .. ': and they look different', apart >= 0.2, ('%.2f'):format(apart));
end

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
