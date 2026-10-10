--[[
    Colors for cadence.

    The timer palette is the one phoenix-xi.com and the Phoenix launcher use. The site draws square
    corners, 1 px borders and thin accent stripes. The addon does the same.

    The settings window has a palette for each preset. Each one has the same eleven role colors as
    checkmate's skins, like its background and accent, plus a corner roundness and the space between
    rows. Phoenix, Classic FFXI, Minimal, High contrast, Ember, Mint and Lavender use checkmate's own, so the two
    addons match. High contrast's spacing is the one exception, 1 px less. A preset spreads its
    palette over every window color in WINDOW_COLORS and copies them into your settings, so each one
    can be changed on its own.
]]

local imgui = require('imgui');

local theme = {};

-- Turns 'c55151' into an ImGui color table.
local function hex(value, alpha)
    return {
        tonumber(value:sub(1, 2), 16) / 255,
        tonumber(value:sub(3, 4), 16) / 255,
        tonumber(value:sub(5, 6), 16) / 255,
        alpha or 1.0,
    };
end
theme.hex = hex;

-- The default timer colors.
theme.palette = {
    surface1  = hex('291c1c'),
    surface2  = hex('321f1f'),
    text      = hex('fff8f8'),
    peach     = hex('d2abab'),
    muted     = hex('8a6b6b'),
    soft      = hex('a88a8a'), -- Lighter than muted, so small text reads over the game.
    rose      = hex('b39393'), -- Darker than peach, so gold stands out on it for colorblind players.
    royal     = hex('c55151'),
    ember     = hex('ff8d79'),
    success   = hex('63ba8a'),
    mint      = hex('9fe0bc'), -- The site green made lighter, so colorblind players can tell it from ember.
    gold      = hex('f5c850'), -- The launcher gold made brighter, so colorblind players can tell it from ember.
    border    = hex('d2abab', 0.20),
    shadow    = hex('000000', 0.70),
};

-- Converts a { r, g, b, a } table of 0..1 floats to the packed color the draw list wants.
function theme.u32(color)
    return imgui.col32(
        math.floor(color[4] * 255 + 0.5),
        math.floor(color[1] * 255 + 0.5),
        math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5));
end

-- Same color with a different alpha.
function theme.with_alpha(color, alpha)
    return { color[1], color[2], color[3], alpha };
end

--[[
    The settings window's palette for each preset, by the preset's id. `rounding` is how round its
    corners are and `spacing` is the space between its rows, both in pixels. Success colors what the
    Profiles tab says after something works. Problem colors what it says when something doesn't, and
    it's the accent unless a palette sets its own.

    Phoenix's heading lines are fainter, its scrollbar track is solid, a held slider handle is a
    lighter red, the rows in an open dropdown are a stronger red and a pressed button is solid red.
    Its red is dark, so the text still reads on all of them. The other palettes work these out from
    their own colors, below.
]]
theme.window_palettes = {
    phoenix = {
        background   = hex('180e0e', 0.96),
        card         = hex('291c1c'),
        control      = hex('321f1f'),
        hover        = hex('3a2525'),
        border       = hex('d2abab', 0.20),
        text         = hex('fff8f8'),
        heading      = hex('d2abab'),
        muted        = hex('8a6b6b'),
        accent       = hex('c55151'),
        accent_hover = hex('ff8d79'),
        success      = hex('63ba8a'),
        rounding     = 0,
        spacing      = 7,
        divider      = hex('d2abab', 0.12),
        track        = hex('180e0e'),
        grab_held    = hex('d45e5e'),
        row_picked   = hex('c55151', 0.45),
        row_hovered  = hex('c55151', 0.70),
        pressed      = hex('c55151'),
    },
    classic = {
        background   = hex('0b1a3d', 0.94),
        card         = hex('13275a'),
        control      = hex('1b3470'),
        hover        = hex('27468c'),
        border       = hex('8ea3d6', 0.55),
        text         = hex('ffffff'),
        heading      = hex('f2e6c4'),
        muted        = hex('9fb0d8'),
        accent       = hex('e8c86a'),
        accent_hover = hex('ffe08a'),
        success      = hex('7ee08a'),
        rounding     = 4,
        spacing      = 7,
    },
    minimal = {
        background   = hex('1e1e1e', 0.96),
        card         = hex('2a2a2a'),
        control      = hex('333333'),
        hover        = hex('404040'),
        border       = hex('ffffff', 0.15),
        text         = hex('f2f2f2'),
        heading      = hex('cfcfcf'),
        muted        = hex('8c8c8c'),
        accent       = hex('d0d0d0'),
        accent_hover = hex('ffffff'),
        success      = hex('9be3b5'),
        rounding     = 3,
        spacing      = 6,
    },
    contrast = {
        background   = hex('000000'),
        card         = hex('141414'),
        control      = hex('262626'),
        hover        = hex('3d3d3d'),
        border       = hex('ffffff', 0.70),
        text         = hex('ffffff'),
        heading      = hex('ffe066'),
        muted        = hex('c8c8c8'),
        accent       = hex('ffd000'),
        accent_hover = hex('ffe866'),
        success      = hex('39ff14'),
        rounding     = 0,
        -- checkmate's is 8. At 8 the Timers tab scrolls with a timer off and the timers hidden, and 1 px
        -- less looks the same.
        spacing      = 7,
    },
    ember = {
        background   = hex('1a120c', 0.96),
        card         = hex('2a1d12'),
        control      = hex('3a2716'),
        hover        = hex('4a321c'),
        border       = hex('ffb070', 0.25),
        text         = hex('fff4e8'),
        heading      = hex('ffc38a'),
        muted        = hex('a07c5c'),
        accent       = hex('e8742a'),
        accent_hover = hex('ffa04d'),
        success      = hex('8fcf6a'),
        rounding     = 2,
        spacing      = 7,
    },
    mint = {
        background   = hex('101f1b', 0.96),
        card         = hex('192f29'),
        control      = hex('233d34'),
        hover        = hex('2e5446'),
        border       = hex('8fe3ba', 0.35),
        text         = hex('edf9f1'),
        heading      = hex('b1ebd0'),
        muted        = hex('9bbbad'),
        accent       = hex('74d9ad'),
        accent_hover = hex('a4edcc'),
        success      = hex('8fe3b7'),
        problem      = hex('ff8d79'),
        rounding     = 4,
        spacing      = 7,
    },
    lavender = {
        background   = hex('191523', 0.96),
        card         = hex('262033'),
        control      = hex('342b45'),
        hover        = hex('463858'),
        border       = hex('cdb1f4', 0.35),
        text         = hex('f3ecff'),
        heading      = hex('deccf7'),
        muted        = hex('b5a5c9'),
        accent       = hex('c3a0ed'),
        accent_hover = hex('e4ccff'),
        success      = hex('a8d9c0'),
        problem      = hex('ff8d79'),
        rounding     = 4,
        spacing      = 7,
    },
    -- The dark panel and the Okabe and Ito sky blue of the Colorblind safe timers. The greys and the
    -- light blue headings are checkmate's. Its accent and success are the same blue, so problems take
    -- Okabe and Ito's orange instead and stay apart from what worked.
    colorblind = {
        background   = hex('101418', 0.96),
        card         = hex('1b2129'),
        control      = hex('252d37'),
        hover        = hex('313b47'),
        border       = hex('56b4e9', 0.30),
        text         = hex('f2f2f2'),
        heading      = hex('9fd3f5'),
        muted        = hex('8f9aa6'),
        accent       = hex('56b4e9'),
        accent_hover = hex('9fd3f5'),
        success      = hex('56b4e9'),
        rounding     = 2,
        spacing      = 7,
        problem      = hex('e69f00'),
    },
};

--[[
    Every color of the settings window, kept in your settings under window_style. They're grouped the
    way the Window colors section shows them, under headings, in rows with a swatch for each color. `key`
    is the color's name in your settings and the word /cadence windowcolor takes. `name` is what its
    swatch says when you point at it. `role` is the palette color it starts from and `paints` is the
    ImGui color it sets. `also` is a second ImGui color that takes the same color. Headings, notes,
    messages and the ON chips paint no ImGui color, since cadence draws them itself.
]]
theme.WINDOW_COLOR_GROUPS = {
    {
        name = 'TEXT',
        rows = {
            { name = 'Text', colors = {
                { key = 'text',          name = 'Text',           role = 'text',      paints = ImGuiCol_Text },
                { key = 'faded_text',    name = 'Faded text',     role = 'muted',     paints = ImGuiCol_TextDisabled },
            } },
            { name = 'Headings', colors = {
                { key = 'headings',      name = 'Headings',       role = 'heading' },
                { key = 'heading_lines', name = 'Heading lines',  role = 'divider',   paints = ImGuiCol_Separator },
            } },
            { name = 'Notes', colors = {
                { key = 'notes',         name = 'Notes',          role = 'heading' },
            } },
            -- What the Profiles tab says after you press one of its buttons.
            { name = 'Messages', colors = {
                { key = 'done_messages',    name = 'Done messages',    role = 'success' },
                { key = 'problem_messages', name = 'Problem messages', role = 'problem' },
            } },
            { name = 'Text boxes', colors = {
                { key = 'selected_text', name = 'Text highlight', role = 'selection',
                    paints = ImGuiCol_TextSelectedBg },
                { key = 'text_cursor',   name = 'Text cursor',    role = 'text',
                    paints = ImGuiCol_InputTextCursor },
            } },
        },
    },
    {
        name = 'WINDOW',
        rows = {
            { name = 'Window', colors = {
                { key = 'background',            name = 'Background',             role = 'background',
                    paints = ImGuiCol_WindowBg },
                { key = 'border',                name = 'Border',                 role = 'border',
                    paints = ImGuiCol_Border },
            } },
            { name = 'Title bar', colors = {
                { key = 'title_bar',             name = 'Title bar',              role = 'card',
                    paints = ImGuiCol_TitleBgActive },
                { key = 'title_bar_unfocused',   name = 'Title bar, unfocused',   role = 'card',
                    paints = ImGuiCol_TitleBg, also = ImGuiCol_TitleBgCollapsed },
            } },
            { name = 'Resize corner', colors = {
                { key = 'resize_corner',         name = 'Resize corner',          role = 'hover',
                    paints = ImGuiCol_ResizeGrip },
                { key = 'resize_corner_hovered', name = 'Resize corner, hovered', role = 'tint',
                    paints = ImGuiCol_ResizeGripHovered },
                { key = 'resize_corner_held',    name = 'Resize corner, held',    role = 'accent',
                    paints = ImGuiCol_ResizeGripActive },
            } },
            -- The window's edges while you point at one or drag it. Without these, ImGui draws its own blue.
            { name = 'Resize edges', colors = {
                { key = 'resize_edges_hovered',  name = 'Resize edges, hovered',  role = 'accent_hover',
                    paints = ImGuiCol_SeparatorHovered },
                { key = 'resize_edges_held',     name = 'Resize edges, held',     role = 'accent',
                    paints = ImGuiCol_SeparatorActive },
            } },
            { name = 'Scrollbar', colors = {
                { key = 'scrollbar_track',       name = 'Scrollbar track',        role = 'track',
                    paints = ImGuiCol_ScrollbarBg },
                { key = 'scrollbar',             name = 'Scrollbar',              role = 'control',
                    paints = ImGuiCol_ScrollbarGrab },
                { key = 'scrollbar_hovered',     name = 'Scrollbar, hovered',     role = 'hover',
                    paints = ImGuiCol_ScrollbarGrabHovered },
                { key = 'scrollbar_held',        name = 'Scrollbar, held',        role = 'accent',
                    paints = ImGuiCol_ScrollbarGrabActive },
            } },
        },
    },
    {
        name = 'BOXES AND BUTTONS',
        rows = {
            { name = 'Boxes', colors = {
                { key = 'boxes',               name = 'Boxes',                role = 'control',
                    paints = ImGuiCol_FrameBg },
                { key = 'boxes_hovered',       name = 'Boxes, hovered',       role = 'hover',
                    paints = ImGuiCol_FrameBgHovered },
                { key = 'boxes_clicked',       name = 'Boxes, clicked',       role = 'tint',
                    paints = ImGuiCol_FrameBgActive },
            } },
            { name = 'Check marks', colors = {
                { key = 'check_marks',         name = 'Check marks',          role = 'accent',
                    paints = ImGuiCol_CheckMark, also = ImGuiCol_DragDropTarget },
            } },
            { name = 'Slider handles', colors = {
                { key = 'slider_handles',      name = 'Slider handles',       role = 'grab',
                    paints = ImGuiCol_SliderGrab },
                { key = 'slider_handles_held', name = 'Slider handles, held', role = 'grab_held',
                    paints = ImGuiCol_SliderGrabActive },
            } },
            { name = 'Buttons', colors = {
                { key = 'buttons',             name = 'Buttons',              role = 'control',
                    paints = ImGuiCol_Button },
                { key = 'buttons_hovered',     name = 'Buttons, hovered',     role = 'hover',
                    paints = ImGuiCol_ButtonHovered },
                { key = 'buttons_pressed',     name = 'Buttons, pressed',     role = 'pressed',
                    paints = ImGuiCol_ButtonActive },
            } },
            { name = 'ON chips', colors = {
                { key = 'on_chips',            name = 'ON chips',             role = 'accent' },
                { key = 'on_chip_text',        name = 'ON chip words',        role = 'on_accent' },
            } },
            -- An open dropdown, then its rows. The one you have, the one under the mouse and the one you click.
            { name = 'Dropdowns', colors = {
                { key = 'dropdowns',           name = 'Open dropdowns',       role = 'card',
                    paints = ImGuiCol_PopupBg },
                { key = 'row_picked',          name = 'Picked row',           role = 'row_picked',
                    paints = ImGuiCol_Header },
                { key = 'row_hovered',         name = 'Row, hovered',         role = 'row_hovered',
                    paints = ImGuiCol_HeaderHovered },
                { key = 'row_clicked',         name = 'Row, clicked',         role = 'pressed',
                    paints = ImGuiCol_HeaderActive },
            } },
        },
    },
    {
        name = 'TABS',
        rows = {
            { name = 'Tabs', colors = {
                { key = 'tabs',                    name = 'Tabs',                     role = 'card',
                    paints = ImGuiCol_Tab },
                { key = 'tabs_hovered',            name = 'Tabs, hovered',            role = 'hover',
                    paints = ImGuiCol_TabHovered },
                { key = 'open_tab',                name = 'Open tab',                 role = 'control',
                    paints = ImGuiCol_TabSelected },
                { key = 'open_tab_line',           name = 'Open tab line',            role = 'accent',
                    paints = ImGuiCol_TabSelectedOverline },
            } },
            { name = 'Unfocused tabs', colors = {
                { key = 'tabs_unfocused',          name = 'Tabs, unfocused',          role = 'card',
                    paints = ImGuiCol_TabDimmed },
                { key = 'open_tab_unfocused',      name = 'Open tab, unfocused',      role = 'control',
                    paints = ImGuiCol_TabDimmedSelected },
                { key = 'open_tab_line_unfocused', name = 'Open tab line, unfocused', role = 'accent',
                    paints = ImGuiCol_TabDimmedSelectedOverline },
            } },
        },
    },
};

-- Every window color in the Window colors section's order.
theme.WINDOW_COLORS = {};
for _, group in ipairs(theme.WINDOW_COLOR_GROUPS) do
    for _, row in ipairs(group.rows) do
        for _, entry in ipairs(row.colors) do
            table.insert(theme.WINDOW_COLORS, entry);
        end
    end
end

-- Style sizes that take the window's corner roundness.
local ROUNDED = {
    ImGuiStyleVar_WindowRounding, ImGuiStyleVar_ChildRounding, ImGuiStyleVar_FrameRounding,
    ImGuiStyleVar_PopupRounding, ImGuiStyleVar_GrabRounding, ImGuiStyleVar_TabRounding,
    ImGuiStyleVar_ScrollbarRounding,
};

-- The space inside boxes and buttons. The settings window puts it back inside each tab after giving
-- the tabs less.
theme.FRAME_PADDING = { 8, 4 };

-- Style sizes every look shares.
local WINDOW_VARS = {
    { ImGuiStyleVar_WindowBorderSize, 1 },
    { ImGuiStyleVar_WindowPadding,    { 14, 12 } },
    { ImGuiStyleVar_FramePadding,     theme.FRAME_PADDING },
    { ImGuiStyleVar_GrabMinSize,      10 },
    { ImGuiStyleVar_TabBarOverlineSize, 2 },
    { ImGuiStyleVar_CellPadding,      { 12, 0 } },
};

-- The space between things on a line, then between rows. The rows take your spacing setting.
local item_spacing = { 8, 7 };

-- How bright a color looks, the way the WCAG contrast check counts it. Black is 0 and white is 1.
local LIGHT_WEIGHTS = { 0.2126, 0.7152, 0.0722 };
local function brightness(color)
    local sum = 0;
    for i = 1, 3 do
        local part = color[i];
        if (part <= 0.04045) then
            part = part / 12.92;
        else
            part = ((part + 0.055) / 1.055) ^ 2.4;
        end
        sum = sum + LIGHT_WEIGHTS[i] * part;
    end
    return sum;
end

-- How well one color stands out on another, from 1 for the same brightness to 21 for black on white.
local function contrast(a, b)
    local x, y = brightness(a) + 0.05, brightness(b) + 0.05;
    return math.max(x, y) / math.min(x, y);
end

-- How well the text has to stand out on a solid slider handle. A handle that can't is drawn half
-- solid instead, so the box under it darkens the color behind the value.
local GRAB_CONTRAST = 3;
local HALF = 0.5;

local CLEAR = { 0, 0, 0, 0 };

--[[
    The roles each palette builds from its own colors, made once here. A number after the accent is
    how solid it is, from 0 for clear to 1 for solid. `tint` is the accent at 0.30, for a box you
    click, and `selection` is the accent at 0.35, behind text you select. The slider handle is the
    accent when the text reads on it, or the accent half solid when it doesn't. A pressed button or
    a clicked dropdown row is the accent at 0.40. The picked dropdown row is the accent at 0.15 and
    the row under the mouse at 0.40, so you can tell them apart. The ON chip's words are the text or
    background color, whichever stands out more on the accent. A problem message is the accent. A
    role a palette sets itself above is kept.
]]
for _, palette in pairs(theme.window_palettes) do
    local accent = palette.accent;
    local dark = theme.with_alpha(palette.background, 1);
    palette.problem = palette.problem or accent;
    palette.tint = theme.with_alpha(accent, 0.30);
    palette.selection = theme.with_alpha(accent, 0.35);
    palette.grab = (contrast(palette.text, accent) >= GRAB_CONTRAST) and accent or theme.with_alpha(accent, HALF);
    palette.grab_held = palette.grab_held or palette.grab;
    palette.pressed = palette.pressed or theme.with_alpha(accent, 0.40);
    palette.row_picked = palette.row_picked or theme.with_alpha(accent, 0.15);
    palette.row_hovered = palette.row_hovered or theme.with_alpha(accent, 0.40);
    palette.divider = palette.divider or palette.border;
    palette.track = palette.track or palette.background;
    palette.on_accent = (contrast(palette.text, accent) >= contrast(dark, accent)) and palette.text or dark;
end

-- A fresh window look from the palette with this id, for your settings. It has a color for every key
-- in WINDOW_COLORS, each in a table of its own, and the palette's corner roundness and spacing.
function theme.window_style(id)
    local palette = theme.window_palettes[id];
    local style = { rounding = palette.rounding, spacing = palette.spacing };
    for _, entry in ipairs(theme.WINDOW_COLORS) do
        local color = palette[entry.role];
        style[entry.key] = { color[1], color[2], color[3], color[4] };
    end
    return style;
end

-- Pushes the settings window's colors, corners and spacing from your window_style settings. Returns
-- the counts to pop.
function theme.push_window_style(style)
    imgui.PushStyleColor(ImGuiCol_ChildBg, CLEAR);
    local colors = 1;
    for _, entry in ipairs(theme.WINDOW_COLORS) do
        if (entry.paints ~= nil) then
            imgui.PushStyleColor(entry.paints, style[entry.key]);
            colors = colors + 1;
        end
        if (entry.also ~= nil) then
            imgui.PushStyleColor(entry.also, style[entry.key]);
            colors = colors + 1;
        end
    end
    for _, id in ipairs(ROUNDED) do
        imgui.PushStyleVar(id, style.rounding);
    end
    for _, entry in ipairs(WINDOW_VARS) do
        imgui.PushStyleVar(entry[1], entry[2]);
    end
    item_spacing[2] = style.spacing;
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, item_spacing);
    return colors, #ROUNDED + #WINDOW_VARS + 1;
end

function theme.pop_window_style(color_count, var_count)
    imgui.PopStyleVar(var_count);
    imgui.PopStyleColor(color_count);
end

-- How far the ON chip goes toward the edge color under the mouse, and how solid the OFF chip is there.
local CHIP_LIT   = 0.25;
local CHIP_FAINT = 0.30;

--[[
    The ON and OFF chips under the mouse, written into `lit` and `faint` so nothing new is made each
    frame. The ON chip goes a quarter of the way to the color the window's edges take under the
    mouse, so it lights up a little like the site's filter chips. The OFF chip shows the ON chip's
    color, faint.
]]
function theme.chip_hover(style, lit, faint)
    local on, toward = style.on_chips, style.resize_edges_hovered;
    for i = 1, 3 do
        lit[i] = on[i] + (toward[i] - on[i]) * CHIP_LIT;
        faint[i] = on[i];
    end
    lit[4], faint[4] = on[4], CHIP_FAINT;
end

return theme;
