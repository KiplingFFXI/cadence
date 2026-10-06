--[[
    Draws the auto attack timer, the resting timer and the enemy attack timer.

    Each element is a small borderless ImGui window that clicks pass straight through. While you hold
    Shift the windows take the mouse. Drag one to move it, or drag an edge to resize it.
    Everything is drawn with the ImGui draw list. It costs next to nothing per frame.
]]

local imgui       = require('imgui');
local theme       = require('ui.theme');
local defaults    = require('ui.defaults');
local window_font = require('ui.window_font');

local hud = {};

local HUD_FLAGS = bit.bor(
    ImGuiWindowFlags_NoDecoration,
    ImGuiWindowFlags_NoBackground,
    ImGuiWindowFlags_NoSavedSettings,
    ImGuiWindowFlags_NoFocusOnAppearing,
    ImGuiWindowFlags_NoBringToFrontOnFocus,
    ImGuiWindowFlags_NoNav,
    ImGuiWindowFlags_NoDocking);
local CLICK_THROUGH_FLAGS = bit.bor(HUD_FLAGS, ImGuiWindowFlags_NoInputs, ImGuiWindowFlags_NoMove);

local WINDOW_NAMES = {
    attack  = '##cadence_attack',
    resting = '##cadence_resting',
    enemy   = '##cadence_enemy',
};

-- Fonts you can pick, by name and file in the Windows fonts folder. The first one found is the
-- default. Wine and Proton ship Tahoma but not Segoe UI.
local FONT_FILES = {
    { 'Segoe UI Semibold', 'seguisb.ttf' },
    { 'Tahoma Bold',       'tahomabd.ttf' },
    { 'Segoe UI Bold',     'segoeuib.ttf' },
    { 'Segoe UI',          'segoeui.ttf' },
    { 'Verdana Bold',      'verdanab.ttf' },
    { 'Arial Bold',        'arialbd.ttf' },
    { 'Calibri Bold',      'calibrib.ttf' },
    { 'Trebuchet MS Bold', 'trebucbd.ttf' },
    { 'Bahnschrift',       'bahnschrift.ttf' },
    { 'Consolas Bold',     'consolab.ttf' },
    { 'Georgia Bold',      'georgiab.ttf' },
};

-- Any .ttf or .otf in this folder, under config, shows up in the list too.
local FONT_FOLDER = '\\config\\addons\\cadence\\fonts\\';

-- Ashita's own pixel font, by its name in the Font list and for /cadence font.
hud.ASHITA_FONT = 'Ashita';

-- Widths are set for 14 px text and grow with the text size.
local BASE_TEXT_SIZE = 14;

-- The enemy strip attached under the auto attack timer has a thinner bar than its own setting.
local ATTACHED_BAR = 0.6;

-- The edges you grab to resize a timer, in pixels at scale 1.
local GRIP_SIZE = 6;

-- The text shadow sits this many pixels down and to the right.
local SHADOW_OFFSET = 1;

-- While an edge is being dragged it's the active item, and a plain IsWindowHovered() says no.
local HOVERED = ImGuiHoveredFlags_AllowWhenBlockedByActiveItem;

-- Button ids for each timer's right edge, bottom edge and corner, made once.
local GRIP_IDS = {};
for key in pairs(WINDOW_NAMES) do
    GRIP_IDS[key] = {
        width  = '##grip_width_' .. key,
        height = '##grip_height_' .. key,
        corner = '##grip_corner_' .. key,
    };
end

-- Reused point tables, so drawing doesn't create garbage every frame.
local A = { 0, 0 };
local B = { 0, 0 };
local SIZE = { 0, 0 };

local settings     = nil;
local colors       = {};
local size         = {};    -- Pixel sizes at the current scale, rebuilt by hud.refresh().
local fonts        = {};    -- Loaded fonts by name.
local font_names   = {};    -- Their names in list order, for the settings window.
local chosen_font  = nil;   -- The font picked in the settings, or nil for Ashita's own.
local face         = nil;   -- The font every element draws with this frame.
local place        = { attack = true, resting = true, enemy = true };
local layout_dirty = false;
local movable      = false;
local joined_below = false; -- True while the enemy strip hangs under the card at the auto attack spot.

-- Where a drag on a timer's edge started, and the width and bar height it had then.
local resize = { mouse_x = 0, mouse_y = 0, width = 0, bar_height = 0 };

-- The card drawn at the auto attack timer's spot this frame. The attached enemy strip hangs under it.
-- With "Share one spot" on, that's the resting timer while you're resting.
local host = { shown = false, x = 0, y = 0, width = 0, height = 0, reach = 0, hovered = false };

-- Where each timer's window was last frame. One that ImGui moved since then was dragged.
local seen = { attack = { x = 0, y = 0 }, resting = { x = 0, y = 0 }, enemy = { x = 0, y = 0 } };

-- The game window's size, read at the start of each frame.
local screen = { width = 0, height = 0 };

local function set_point(point, x, y)
    point[1] = x;
    point[2] = y;
    return point;
end

local function round(value)
    return math.floor(value + 0.5);
end

local function lerp(a, b, t)
    return a + (b - a) * t;
end

local function clamp(value, range)
    return math.max(range[1], math.min(range[2], value));
end

-- Packs a color partway between two settings colors.
local function blend(from, to, t)
    return imgui.col32(
        round(lerp(from[4], to[4], t) * 255),
        round(lerp(from[1], to[1], t) * 255),
        round(lerp(from[2], to[2], t) * 255),
        round(lerp(from[3], to[3], t) * 255));
end

-- Packs a settings color with its alpha scaled down by `strength` (0..1).
local function faded(color, strength)
    return imgui.col32(
        round(color[4] * strength * 255),
        round(color[1] * 255),
        round(color[2] * 255),
        round(color[3] * 255));
end

-- A packed color with its alpha scaled down by `strength` (0..1). Nil leaves it as it is.
local function dimmed(packed, strength)
    if (strength == nil) then
        return packed;
    end
    return bit.bor(bit.band(packed, 0xFFFFFF), bit.lshift(round(bit.rshift(packed, 24) * strength), 24));
end

--[[
    Runs when the settings change. Rebuilds the packed colors and pixel sizes. Only the moving end of
    each bar's gradient and the fading tick flash get packed per frame.
]]
function hud.refresh(settings_table)
    settings = settings_table;
    local style = settings.style;

    -- A font that's no longer there, like one taken out of the fonts folder, falls back to the first.
    chosen_font = nil;
    if (style.system_font) then
        chosen_font = fonts[style.font_name] or fonts[font_names[1]];
    end
    local scale = style.scale;
    local P = theme.palette;

    colors.panel         = theme.u32(style.panel_color);
    colors.border        = theme.u32(style.border_color);
    colors.accent        = theme.u32(style.accent_color);
    colors.track         = theme.u32(style.track_color);
    colors.label         = theme.u32(style.label_color);
    colors.value         = theme.u32(style.value_color);
    colors.detail        = theme.u32(style.detail_color);
    colors.shadow        = theme.u32(P.shadow);
    colors.text_edge     = theme.u32(style.outline_color);
    colors.outline       = theme.u32(theme.with_alpha(P.ember, 0.85));
    colors.attack_start  = theme.u32(settings.attack.fill_start);
    colors.resting_start = theme.u32(settings.resting.fill_start);
    colors.enemy_start   = theme.u32(settings.enemy.fill_start);
    colors.ready         = theme.u32(settings.attack.ready_color);
    colors.almost        = theme.u32(settings.attack.almost_color);
    colors.tp            = theme.u32(settings.attack.tp_color);
    colors.enemy_ready   = theme.u32(settings.enemy.ready_color);
    colors.enemy_almost  = theme.u32(settings.enemy.almost_color);
    colors.on_you        = theme.u32(settings.enemy.on_you_color);
    colors.full          = theme.u32(settings.resting.full_color);

    size.value_px = round(style.font_size * scale);
    -- Labels are a little smaller than values, but never shrink below 11 px unless values do.
    size.label_px = math.max(round(size.value_px * 0.82), math.min(11, size.value_px));
    -- Timer names and the small text are that size too, unless Label size and Detail size set their own.
    size.name_px = size.label_px;
    if (style.label_size >= defaults.LABEL_SIZE[1]) then
        size.name_px = round(style.label_size * scale);
    end
    size.detail_px = size.label_px;
    if (style.detail_size >= defaults.DETAIL_SIZE[1]) then
        size.detail_px = round(style.detail_size * scale);
    end
    size.width_scale = scale * style.font_size / BASE_TEXT_SIZE;
    size.pad_x       = style.panel and round(10 * scale) or 0;
    size.pad_y       = style.panel and round(7 * scale) or 0;
    size.strip_pad_y = style.panel and round(4 * scale) or 0;
    -- With no card behind it, the strip still needs a gap between the bar above it and its own text.
    size.strip_top   = style.panel and size.strip_pad_y or round(5 * scale);
    size.accent      = style.accent and math.max(2, round(2 * scale)) or 0;
    size.gap         = round(5 * scale);
    size.strip_gap   = round(3 * scale);
    size.spacing     = round(7 * scale);
    size.rounding    = round(style.rounding * scale);
    -- With a border, the attached strip moves up 1 px so it shares the card's bottom border line.
    size.overlap     = style.border and 1 or 0;

    -- A reset, a character switch, the shared layout or the shared spot can all move the timers.
    hud.place_all();
end

-- The settings window can list the same file, so window_font loads each file once for both.
local function add_font(name, path)
    if (fonts[name] ~= nil) then
        return;
    end
    local loaded = window_font.load_file(path);
    if (loaded ~= nil) then
        fonts[name] = loaded;
        table.insert(font_names, name);
    end
end

--[[
    Loads every font you can pick, from the Windows fonts folder and cadence's own fonts folder. Only
    called from the load event, because adding a font in the middle of a frame can crash the game.
    XIUI loads its fonts the same way.
]]
function hud.load_fonts()
    local windows = ('%s\\Fonts\\'):format(os.getenv('WINDIR') or 'C:\\Windows');
    for _, entry in ipairs(FONT_FILES) do
        add_font(entry[1], windows .. entry[2]);
    end

    local folder = AshitaCore:GetInstallPath() .. FONT_FOLDER;
    if (not ashita.fs.exists(folder)) then
        return;
    end
    local files = ashita.fs.get_directory(folder, '.*\\.[tToO][tT][fF]$', false) or {};
    table.sort(files);
    for _, file in ipairs(files) do
        add_font(file:gsub('%.%a+$', ''), folder .. file);
    end
end

-- The fonts that loaded, in list order.
function hud.font_names()
    return font_names;
end

-- The name of the font the timers use, or nil for Ashita's own.
function hud.font_in_use()
    if (chosen_font == nil) then
        return nil;
    end
    return fonts[settings.style.font_name] and settings.style.font_name or font_names[1];
end

-- Puts every element back at its saved position on the next frame.
function hud.place_all()
    place.attack, place.resting, place.enemy = true, true, true;
end

-- Set each frame before drawing. True while you hold Shift, so the timers can take the mouse.
function hud.set_movable(value)
    movable = value;
end

-- Set each frame before drawing. When the enemy strip will hang under the card at the auto attack
-- spot, that card's bottom corners go square to meet it.
function hud.join_below(value)
    joined_below = value;
end

-- The settings that hold an element's position. With the shared spot on, the resting timer sits
-- wherever the auto attack timer is.
local function anchor(key)
    if (key == 'resting' and settings.style.shared_spot) then
        return settings.attack;
    end
    return settings[key];
end

-- True when a timer's name is drawn. Show labels and the timer's own switch both have to be on.
local function shows_name(key)
    return settings.style.show_labels and settings[key].show_label;
end

-- True when a timer shows small text next to its name.
local function has_detail(key)
    local element = settings[key];
    return element.show_delay or element.show_gains or element.show_until_full or element.show_name
        or element.show_effects;
end

-- True when a timer shows its row of text above the bar. A timer showing just its numbers always does.
local function has_header(key)
    local element = settings[key];
    return element.numbers_only or shows_name(key) or element.show_value or has_detail(key);
end

-- True when the enemy timer is the smaller strip attached under the auto attack timer.
local function is_strip(key)
    return key == 'enemy' and settings.enemy.attached;
end

-- True when a timer shows a line of text under the bar. The auto attack timer does for your TP, and
-- the resting timer for when HP and MP will each be full.
local function has_footer(key)
    if (key == 'attack') then
        return settings.attack.show_tp;
    end
    return key == 'resting' and settings.resting.show_each_full;
end

-- How thick a timer's bar is in pixels, or 0 when it shows just its numbers.
local function bar_px(key)
    local element = settings[key];
    if (element.numbers_only) then
        return 0;
    end
    local thickness = element.bar_height * settings.style.scale;
    if (is_strip(key)) then
        thickness = thickness * ATTACHED_BAR;
    end
    return math.max(1, round(thickness));
end

-- How tall a timer's row of text is. A name or small text bigger than the numbers makes it taller.
local function header_px(key)
    local row = is_strip(key) and size.label_px or size.value_px;
    if (shows_name(key)) then
        row = math.max(row, size.name_px);
    end
    if (has_detail(key)) then
        row = math.max(row, size.detail_px);
    end
    return row;
end

-- Width and height of an element in pixels at the current settings. There's a gap between its text
-- row, its bar and the line under the bar.
function hud.element_size(key)
    local strip = is_strip(key);
    local header = has_header(key) and header_px(key) or 0;
    local bar = bar_px(key);
    local footer = (not strip and has_footer(key)) and size.detail_px or 0;
    local rows = ((header > 0) and 1 or 0) + ((bar > 0) and 1 or 0) + ((footer > 0) and 1 or 0);
    local gaps = math.max(rows - 1, 0) * (strip and size.strip_gap or size.gap);

    if (strip) then
        -- As wide as the card above it, with the smaller text size and a thinner bar.
        local width = host.shown and host.width or hud.element_size('attack');
        return width, size.strip_top + size.strip_pad_y + header + bar + gaps;
    end
    local width = size.accent + size.pad_x * 2 + round(settings[key].width * size.width_scale);
    return width, size.pad_y * 2 + header + bar + footer + gaps;
end

-- The game window's size in pixels.
function hud.screen_size()
    local display = imgui.GetIO().DisplaySize;
    return display.x, display.y;
end

-- Where a card this size is drawn from its saved spot. It's pulled in just enough that all of it is on
-- screen. The saved spot stays as it is, so a bigger screen shows it there again.
local function on_screen(x, y, width, height)
    return math.max(0, math.min(x, screen.width - width)), math.max(0, math.min(y, screen.height - height));
end

-- The element window already pushed the value size. Other sizes get measured at their own size,
-- since Ashita's pixel font doesn't scale evenly.
local function text_width(text, px)
    if (px == size.value_px) then
        local width = imgui.CalcTextSize(text);
        return width;
    end
    imgui.PushFont(face, px);
    local width = imgui.CalcTextSize(text);
    imgui.PopFont();
    return width;
end

-- The eight spots around the text an outline is drawn at.
local EDGE_SPOTS = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } };

-- Draws text with its shadow and outline, when those are on. The outline is 1 px around normal text
-- and thicker around big text.
local function draw_text(list, x, y, color, text, px)
    local style = settings.style;
    if (style.text_shadow) then
        list:AddText(face, px, set_point(A, x + SHADOW_OFFSET, y + SHADOW_OFFSET), colors.shadow, text);
    end
    if (style.text_outline) then
        local edge = math.max(1, round(px / 16));
        for _, spot in ipairs(EDGE_SPOTS) do
            list:AddText(face, px, set_point(A, x + spot[1] * edge, y + spot[2] * edge), colors.text_edge, text);
        end
    end
    list:AddText(face, px, set_point(A, x, y), color, text);
end

--[[
    Opens the element's window. Always pair with end_element(), even when this returns false.
    `fixed_x` and `fixed_y` pin it in place for this frame, for the attached enemy strip. The card
    above the strip reaches down over it. A drag on the strip lands on that card and moves both.

    Otherwise it goes to its saved spot every frame, pulled in to fit on screen. ImGui only gets to
    move it while Shift and the mouse button are down. Only a drag changes the saved spot.
    `fit_height` is the height it has to fit on screen, when that's taller than the window.
]]
local function begin_element(key, width, height, fixed_x, fixed_y, fit_height)
    local spot = anchor(key);
    local can_move = movable and not settings.style.locked;
    local flags = can_move and HUD_FLAGS or CLICK_THROUGH_FLAGS;
    local x, y = fixed_x, fixed_y;
    local dragging = false;
    if (fixed_x ~= nil) then
        flags = CLICK_THROUGH_FLAGS;
    else
        x, y = on_screen(spot.x, spot.y, width, fit_height or height);
        dragging = can_move and imgui.IsMouseDown(ImGuiMouseButton_Left);
    end
    -- A window that was hidden still comes back at its spot during a drag. A reset moves it right away.
    local condition = ImGuiCond_Always;
    if (dragging and not place[key]) then
        condition = ImGuiCond_Appearing;
    end
    imgui.SetNextWindowPos(set_point(A, x, y), condition);
    -- A pinned window goes back to its saved spot as soon as it isn't pinned anymore.
    place[key] = fixed_x ~= nil;
    imgui.SetNextWindowSize(set_point(SIZE, width, height), ImGuiCond_Always);

    if (not imgui.Begin(WINDOW_NAMES[key], true, flags)) then
        return false;
    end

    imgui.PushFont(face, size.value_px);

    local drawn_x, drawn_y = imgui.GetWindowPos();
    drawn_x, drawn_y = math.floor(drawn_x), math.floor(drawn_y);
    if (fixed_x ~= nil) then
        return true, drawn_x, drawn_y, imgui.GetWindowDrawList();
    end

    -- The saved spot follows the window while it's dragged. It was dragged when ImGui moved it since last
    -- frame, and not to where it was put this frame.
    local last = seen[key];
    if (dragging and (drawn_x ~= last.x or drawn_y ~= last.y) and (drawn_x ~= x or drawn_y ~= y)) then
        spot.x, spot.y = drawn_x, drawn_y;
        layout_dirty = true;
    end
    last.x, last.y = drawn_x, drawn_y;
    return true, drawn_x, drawn_y, imgui.GetWindowDrawList();
end

local function end_element(opened)
    if (opened) then
        imgui.PopFont();
    end
    imgui.End();
end

--[[
    The card behind an element. It has a background, the Phoenix accent stripe and a hairline border.
    `corners` picks which corners are rounded. The auto attack timer and the strip under it meet
    square, so they look like one card.
]]
local function draw_panel(list, x, y, width, height, corners, accent)
    local style = settings.style;
    local corner = size.rounding;
    corners = corners or 0;   -- No flags means every corner.
    if (style.panel) then
        list:AddRectFilled(set_point(A, x, y), set_point(B, x + width, y + height), colors.panel, corner, corners);
    end
    if (style.accent) then
        -- The stripe is the card's own shape cut down to its left edge, so it follows rounded corners.
        list:PushClipRect(set_point(A, x, y), set_point(B, x + size.accent, y + height), true);
        list:AddRectFilled(set_point(A, x, y), set_point(B, x + width, y + height), accent or colors.accent, corner,
            corners);
        list:PopClipRect();
    end
    if (style.border) then
        list:AddRect(set_point(A, x, y), set_point(B, x + width, y + height), colors.border, corner, corners, 1);
    end
end

-- A thin bar. The fill reveals a gradient that runs from `from` to `to` across the full width. `dim`
-- scales the fill's alpha (0..1), or nil draws it as it is.
local function draw_bar(list, x, y, width, height, fill, from_packed, from, to, solid, dim)
    local corner = math.min(size.rounding, height / 2);
    list:AddRectFilled(set_point(A, x, y), set_point(B, x + width, y + height), colors.track, corner);
    if (fill <= 0) then
        return;
    end

    -- Whole pixels, so the gradient and its rounded ends meet without a seam.
    local right = x + math.max(1, round(width * math.min(fill, 1)));
    if (solid ~= nil) then
        list:AddRectFilled(set_point(A, x, y), set_point(B, right, y + height), dimmed(solid, dim), corner);
        return;
    end

    -- A gradient can't round its own corners, so rounded ends are drawn on in the end colors. They sit
    -- beside the gradient, not over it, so a dimmed fill shows no brighter seams. A fill too short for
    -- both ends is drawn in one color.
    from_packed = dimmed(from_packed, dim);
    local right_color = dimmed(blend(from, to, fill), dim);
    local cap = math.floor(corner);
    if (right - x < cap * 4) then
        list:AddRectFilled(set_point(A, x, y), set_point(B, right, y + height), right_color, corner);
        return;
    end
    list:AddRectFilledMultiColor(set_point(A, x + cap * 2, y), set_point(B, right - cap * 2, y + height),
        from_packed, right_color, right_color, from_packed);
    if (cap >= 1) then
        list:AddRectFilled(set_point(A, x, y), set_point(B, x + cap * 2, y + height), from_packed, cap,
            ImDrawFlags_RoundCornersLeft);
        list:AddRectFilled(set_point(A, right - cap * 2, y), set_point(B, right, y + height), right_color, cap,
            ImDrawFlags_RoundCornersRight);
    end
end

-- One edge you can drag to resize a timer. It's an invisible button, so grabbing it doesn't move the
-- window. `sideways` drags change the width and `down` drags change the bar height.
local function grip(key, id, x, y, width, height, sideways, down, cursor)
    imgui.SetCursorScreenPos(set_point(A, x, y));
    imgui.InvisibleButton(id, set_point(B, width, height));
    local element = settings[key];
    if (imgui.IsItemActivated()) then
        resize.mouse_x, resize.mouse_y = imgui.GetMousePos();
        resize.width, resize.bar_height = element.width, element.bar_height;
    end
    if (imgui.IsItemActive()) then
        local mouse_x, mouse_y = imgui.GetMousePos();
        if (sideways) then
            element.width = clamp(round(resize.width + (mouse_x - resize.mouse_x) / size.width_scale), defaults.WIDTH);
        end
        if (down) then
            -- The attached strip draws its bar thinner, so its drag is scaled the same way to keep the
            -- edge under the mouse.
            local bar_scale = settings.style.scale * (is_strip(key) and ATTACHED_BAR or 1);
            element.bar_height = clamp(round(resize.bar_height + (mouse_y - resize.mouse_y) / bar_scale),
                defaults.BAR_HEIGHT);
        end
        layout_dirty = true;
    end
    if (imgui.IsItemHovered() or imgui.IsItemActive()) then
        imgui.SetMouseCursor(cursor);
    end
end

-- The right edge sets the width, the bottom edge the bar height and the corner both. A timer showing
-- just its numbers has no bar, so only its width can change.
local function resize_grips(key, x, y, width, height)
    local edge = math.max(4, round(GRIP_SIZE * settings.style.scale));
    local ids = GRIP_IDS[key];
    local has_bar = not settings[key].numbers_only;
    -- The attached strip takes the auto attack timer's width, so it only gets its bottom edge.
    if (is_strip(key)) then
        if (has_bar) then
            grip(key, ids.height, x, y + height - edge, width, edge, false, true, ImGuiMouseCursor_ResizeNS);
        end
        return;
    end
    grip(key, ids.width, x + width - edge, y, edge, height - edge, true, false, ImGuiMouseCursor_ResizeEW);
    if (has_bar) then
        grip(key, ids.height, x, y + height - edge, width - edge, edge, false, true, ImGuiMouseCursor_ResizeNS);
    end
    grip(key, ids.corner, x + width - edge, y + height - edge, edge, edge, true, has_bar,
        has_bar and ImGuiMouseCursor_ResizeNWSE or ImGuiMouseCursor_ResizeEW);
end

-- Two short lines in the bottom right corner, so you can see where to grab.
local function draw_corner_grip(list, x, y, width, height)
    local right, bottom = x + width - 2, y + height - 2;
    local long, short = math.max(6, round(8 * settings.style.scale)), math.max(3, round(4 * settings.style.scale));
    list:AddLine(set_point(A, right - long, bottom), set_point(B, right, bottom - long), colors.outline, 1);
    list:AddLine(set_point(A, right - short, bottom), set_point(B, right, bottom - short), colors.outline, 1);
end

-- The line under the bar. Nothing is cut mid-word. A narrow card gets the short forms, and then
-- nothing on the right.
local function draw_footer(list, timer, left, top, bar_width)
    local footer, right = timer.footer, timer.footer_right;
    local room = bar_width - text_width(footer, size.detail_px) - size.spacing;
    local right_width = right and text_width(right, size.detail_px) or 0;
    if (right ~= nil and right_width > room) then
        footer = timer.footer_left_short or footer;
        room = bar_width - text_width(footer, size.detail_px) - size.spacing;
        right = timer.footer_short;
        right_width = text_width(right, size.detail_px);
    end
    draw_text(list, left, top, timer.footer_color, footer, size.detail_px);
    if (right ~= nil and right_width <= room) then
        draw_text(list, left + bar_width - right_width, top, colors.detail, right, size.detail_px);
    end
end

--[[
    While Shift is held, the element under the mouse gets an outline, to show what a drag will move.
    Both parts of a joined card outline all of it, since either can be drawn on top. A timer at its
    own spot can be resized from its edges, and shows a grip in its corner.
]]
local function draw_move_hints(list, timer, x, y, width, height, hosting, strip)
    local hovered = imgui.IsWindowHovered(HOVERED);
    if (hosting) then
        -- The strip under this card is drawn next and uses this too.
        host.hovered = hovered;
    end
    if (hosting or (strip and timer.x ~= nil)) then
        if (host.hovered) then
            list:AddRect(set_point(A, x, host.y), set_point(B, x + width, host.y + host.height + host.reach),
                colors.outline, size.rounding, 0, 1);
        end
    elseif (hovered) then
        list:AddRect(set_point(A, x, y), set_point(B, x + width, y + height), colors.outline, size.rounding, 0, 1);
    end
    if (timer.x == nil) then
        if (hovered and not strip) then
            draw_corner_grip(list, x, y, width, height);
        end
        resize_grips(timer.key, x, y, width, height);
    end
end

--[[
    Draws one timer element.

    timer = {
        key = 'attack', 'resting' or 'enemy', label = 'AUTO ATTACK', detail = small text or nil,
        value = right-hand text or nil, value_color = packed color or nil,
        fill = 0..1, solid = packed color to draw the bar in one color, or nil for the gradient,
        dim = how much of the fill's alpha to keep (0..1), or nil for all of it,
        start_color = the packed start of the gradient,
        flash = packed color laid over the whole card, or nil,
        mark_as = packed color for the label and the accent stripe, or nil for their usual colors,
        mark = where on the bar (0..1) to draw a small mark, mark_color = its packed color,
        corners = which corners are rounded, or nil for all of them,
        x, y = where to pin it this frame, or nil to use its saved spot,
        footer = small text under the bar, footer_color = its packed color,
        footer_right, footer_short = text for the right of that line, and a shorter one for narrow cards,
        footer_left_short = a shorter footer for narrow cards, or nil to keep the footer as it is,
    }
]]
local function draw_timer(timer)
    local key = timer.key;
    local width, height = hud.element_size(key);

    -- The attached strip uses the smaller text for its value too, and less padding.
    local strip = is_strip(key);
    local value_px = strip and size.label_px or size.value_px;
    local gap = strip and size.strip_gap or size.gap;

    -- The attached strip hangs under the card at the auto attack spot. That card's bottom corners go
    -- square to meet it. Its window reaches down over the strip, so a drag anywhere on the joined card
    -- moves both. Near the screen's edge, that card always leaves room for the strip, so it doesn't
    -- jump when the strip comes and goes.
    local at_attack_spot = not strip and anchor(key) == settings.attack;
    local hosting = joined_below and at_attack_spot;
    local strip_room = 0;
    if (hosting or (at_attack_spot and settings.attack.enabled and settings.enemy.enabled
        and settings.enemy.attached)) then
        local _, strip_height = hud.element_size('enemy');
        strip_room = strip_height - size.overlap;
    end
    local reach = hosting and strip_room or 0;
    local corners = hosting and ImDrawFlags_RoundCornersTop or timer.corners;

    local opened, x, y, list = begin_element(key, width, height + reach, timer.x, timer.y, height + strip_room);
    if (opened) then
        draw_panel(list, x, y, width, height, corners, timer.mark_as);
        if (hosting) then
            host.shown, host.x, host.y, host.width, host.height, host.reach = true, x, y, width, height, reach;
        end

        local left = x + size.accent + size.pad_x;
        local top  = y + (strip and size.strip_top or size.pad_y);
        local bar_width = width - size.accent - size.pad_x * 2;
        if (has_header(key)) then
            -- Smaller text sits lower in the row by this much, so everything shares a baseline.
            local row_px = header_px(key);
            local value_top  = top + (row_px - value_px) * 0.75;
            local name_top   = top + (row_px - size.name_px) * 0.75;
            local detail_top = top + (row_px - size.detail_px) * 0.75;
            local value_x = left + bar_width;
            if (timer.value ~= nil) then
                value_x = value_x - text_width(timer.value, value_px);
                draw_text(list, value_x, value_top, timer.value_color or colors.value, timer.value, value_px);
            end

            local label = shows_name(key) and timer.label or nil;
            local detail_x, text_end = left, left;
            if (label ~= nil) then
                text_end = left + text_width(label, size.name_px);
                detail_x = text_end + size.spacing;
            end
            if (timer.detail ~= nil) then
                text_end = detail_x + text_width(timer.detail, size.detail_px);
            end

            -- On a narrow timer the label and detail are cut off before they run into the value.
            local room = value_x - size.spacing;
            local cut = text_end > room;
            if (cut) then
                list:PushClipRect(set_point(A, left, y), set_point(B, room, y + height), true);
            end
            if (label ~= nil) then
                draw_text(list, left, name_top, timer.mark_as or colors.label, label, size.name_px);
            end
            if (timer.detail ~= nil) then
                draw_text(list, detail_x, detail_top, colors.detail, timer.detail, size.detail_px);
            end
            if (cut) then
                list:PopClipRect();
            end
            top = top + row_px + gap;
        end

        local bar_height = bar_px(key);
        if (bar_height > 0) then
            -- A draining bar shows the time left. Once it's empty, a bar with a ready color fills
            -- back up in it, so ready still shows.
            local fill = timer.fill;
            if (settings.style.bar_drains) then
                fill = 1 - fill;
                if (fill <= 0 and timer.solid ~= nil) then
                    fill = 1;
                end
            end
            local element = settings[key];
            draw_bar(list, left, top, bar_width, bar_height, fill, timer.start_color,
                element.fill_start, element.fill_end, timer.solid, timer.dim);

            -- The mark pokes out a little above and below the bar, so it shows on a thin one.
            if (timer.mark ~= nil) then
                local scale = settings.style.scale;
                local mark_x = left + round(bar_width * timer.mark);
                local mark_width = math.max(1, round(scale));
                local poke = math.max(1, round(2 * scale));
                list:AddRectFilled(set_point(A, mark_x, top - poke),
                    set_point(B, mark_x + mark_width, top + bar_height + poke), timer.mark_color);
            end
            top = top + bar_height + gap;
        end

        if (timer.footer ~= nil) then
            draw_footer(list, timer, left, top, bar_width);
        end

        if (timer.flash ~= nil) then
            list:AddRectFilled(set_point(A, x, y), set_point(B, x + width, y + height), timer.flash, size.rounding,
                corners or 0);
        end

        if (movable and not settings.style.locked) then
            draw_move_hints(list, timer, x, y, width, height, hosting, strip);
        end
    end
    end_element(opened);
end

-- Formats seconds as "2.4", reusing the last string until the tenths digit changes.
local function seconds_text(cache, seconds)
    local tenths = math.floor(seconds * 10 + 0.5);
    if (tenths ~= cache.tenths) then
        cache.tenths = tenths;
        cache.text = ('%.1f'):format(tenths / 10);
    end
    return cache.text;
end

-- The label a timer shows. Your own text from the settings, or the default.
local function label_for(element, default)
    local text = element.label_text;
    if (text == nil or text == '') then
        return default;
    end
    return text;
end

--[[
    Where the almost ready part of the bar starts, from 0 to 1, or nil for no mark. The bar's whole
    length comes from how far it has filled and the seconds left, so it's right for a first attack
    too.
]]
local function almost_mark(element, fill, left)
    if (not (element.almost_ready and element.almost_mark) or fill >= 1 or left <= 0) then
        return nil;
    end
    local total = left / (1 - fill);
    if (total <= element.almost_seconds) then
        return nil;
    end
    local at = 1 - element.almost_seconds / total;
    return settings.style.bar_drains and (1 - at) or at;
end

-- A delay like "3.78s". It's "3.78s est." while it's still a guess, before it's learned from real rounds.
local function delay_text(delay, learned)
    return ('%.2fs%s'):format(delay, learned and '' or ' est.');
end

local attack_text = { tenths = -1, text = '' };
local attack_detail = { delay = -1, learned = false, text = '' };
local attack_timer = { key = 'attack' };
local tp_text = { tp = -1, text = '' };
local rounds_text = { rounds = -1, goal = -1, long = '', short = '' };

-- What the auto attack timer says instead of the seconds while something stops it. A spell, ranged
-- attack or item goes by its kind. Sleep, petrification, stun, Sleep II, terror, penalty and Lullaby
-- go by their buff id.
local STOPPED_WORDS = { spell = 'casting', ranged = 'ranged', item = 'item', [2] = 'asleep', [7] = 'petrified',
    [10] = 'stunned', [19] = 'asleep', [28] = 'terrified', [159] = 'penalty', [193] = 'asleep' };

-- A stopped bar, one you can't attack from or a resting bar whose ticks can't heal you keeps this much of
-- its fill's alpha.
local STOPPED_DIM = 0.35;

-- Fills the TP line under the auto attack bar, like "TP 640" and "1000 TP in ~3 rounds".
local function fill_tp_line(timer, view)
    timer.footer, timer.footer_right, timer.footer_short, timer.footer_left_short = nil, nil, nil, nil;
    if (view == nil) then
        return;
    end

    if (view.tp ~= tp_text.tp) then
        tp_text.tp = view.tp;
        tp_text.text = ('TP %d'):format(view.tp);
    end
    timer.footer = tp_text.text;
    timer.footer_color = (view.tp >= view.goal) and colors.tp or colors.value;

    if (view.rounds ~= nil) then
        if (view.rounds ~= rounds_text.rounds or view.goal ~= rounds_text.goal) then
            rounds_text.rounds, rounds_text.goal = view.rounds, view.goal;
            local unit = (view.rounds == 1) and 'round' or 'rounds';
            rounds_text.long = ('%d TP in ~%d %s'):format(view.goal, view.rounds, unit);
            rounds_text.short = ('~%d %s'):format(view.rounds, unit);
        end
        timer.footer_right, timer.footer_short = rounds_text.long, rounds_text.short;
    end
end

--[[
    Draws the auto attack timer from how full the bar is (0..1), the seconds left, the delay in use
    and whether that delay was learned from your attacks. `tp_view` is { tp, goal, rounds } for the TP
    line under the bar. `rounds` is nil once you're at the goal. A nil tp_view leaves the line off.
    `reason` is why you aren't attacking from the server's message, like "too far", or nil. It only
    shows once the attack is due. `reach` is "too far" or "not facing" from where you stand, or nil,
    and shows any time. `why` is what stopped the timer, a key in STOPPED_WORDS, or nil. `left` is nil
    while the next attack's time isn't known, and shows "--".
]]
function hud.draw_attack(fill, left, delay, learned, tp_view, reason, why, reach)
    local element = settings.attack;
    local stopped = element.show_why and STOPPED_WORDS[why] or nil;
    local ready = left ~= nil and left <= 0;
    local almost = left ~= nil and not ready and element.almost_ready and left <= element.almost_seconds;
    local state_color = (ready and colors.ready) or (almost and colors.almost) or nil;

    -- The server's message only shows once the attack is due, and then it wins.
    local cant = nil;
    if (element.show_reason) then
        cant = ((left == nil or ready) and reason) or reach;
    end

    attack_timer.label = label_for(element, 'AUTO ATTACK');
    attack_timer.fill = fill;
    attack_timer.dim = (stopped or cant) and STOPPED_DIM or nil;
    attack_timer.mark, attack_timer.mark_color = left and almost_mark(element, fill, left), colors.almost;
    attack_timer.start_color = colors.attack_start;
    attack_timer.solid = state_color;
    attack_timer.value_color = state_color;
    attack_timer.value = nil;
    if (element.show_value) then
        -- What stopped the timer comes first, then why you can't attack, then the seconds. Before the
        -- attack is due, why you can't attack is in the detail color, since nothing is about to happen.
        if (stopped ~= nil) then
            attack_timer.value, attack_timer.value_color = stopped, colors.detail;
        elseif (left == nil) then
            -- The server only sends its message once an attack is due, so it's in the ready color.
            local from_server = element.show_reason and reason ~= nil;
            attack_timer.value = cant or '--';
            attack_timer.value_color = from_server and colors.ready or colors.detail;
        elseif (ready) then
            attack_timer.value = cant or 'ready';
        elseif (cant ~= nil) then
            attack_timer.value, attack_timer.value_color = cant, colors.detail;
        else
            attack_timer.value = seconds_text(attack_text, left);
        end
    end

    attack_timer.detail = nil;
    if (element.show_delay and delay ~= nil) then
        if (delay ~= attack_detail.delay or learned ~= attack_detail.learned) then
            attack_detail.delay, attack_detail.learned = delay, learned;
            attack_detail.text = delay_text(delay, learned);
        end
        attack_timer.detail = attack_detail.text;
    end
    fill_tp_line(attack_timer, tp_view);

    draw_timer(attack_timer);
end

local resting_text = { tenths = -1, text = '' };
local resting_detail = { hp = -1, mp = -1, until_full = -1, text = '' };
local resting_timer = { key = 'resting' };

-- What the resting timer says instead of the seconds while disease, plague or the curse that stops
-- healing is on you, by buff id. They're the game's own words for each one.
local CANT_HEAL_WORDS = { [8] = 'diseased', [31] = 'plagued', [20] = 'cursed' };
local each_full = { hp = -2, mp = -2, has_mp = nil, hp_text = '', hp_short = '', mp_text = '', mp_short = '' };

-- Seconds as "20s", or "1:10" from a minute up.
local function duration_text(seconds)
    if (seconds >= 60) then
        return ('%d:%02d'):format(math.floor(seconds / 60), seconds % 60);
    end
    return ('%ds'):format(seconds);
end

-- "HP full in 20s", "HP full" once it is, or "HP full in --" before it can be worked out. The short
-- form is "HP 20s".
local function full_text(stat, seconds)
    if (seconds == 0) then
        return stat .. ' full', stat .. ' full';
    end
    local time = (seconds < 0) and '--' or duration_text(seconds);
    return ('%s full in %s'):format(stat, time), ('%s %s'):format(stat, time);
end

-- Fills the line under the resting bar with when HP and MP will each be full. Rebuilt only when a
-- number changes.
local function fill_full_line(timer, view)
    timer.footer, timer.footer_right, timer.footer_short, timer.footer_left_short = nil, nil, nil, nil;
    if (not settings.resting.show_each_full) then
        return;
    end

    local hp = view.hp_full_in and math.ceil(view.hp_full_in) or -1;
    local mp = view.mp_full_in and math.ceil(view.mp_full_in) or -1;
    local last = each_full;
    if (hp ~= last.hp or mp ~= last.mp or view.has_mp ~= last.has_mp) then
        last.hp, last.mp, last.has_mp = hp, mp, view.has_mp;
        last.hp_text, last.hp_short = full_text('HP', hp);
        last.mp_text, last.mp_short = full_text('MP', mp);
    end
    timer.footer, timer.footer_left_short = last.hp_text, last.hp_short;
    timer.footer_color = (hp == 0) and colors.full or colors.value;
    if (view.has_mp) then
        timer.footer_right, timer.footer_short = last.mp_text, last.mp_short;
    end
end

-- The small text after RESTING, like "+24 HP  +31 MP  full in 28s". Rebuilt only when a number changes.
local function resting_detail_text(element, view)
    local hp = element.show_gains and view.gained_hp or 0;
    local mp = element.show_gains and view.gained_mp or 0;
    local until_full = (element.show_until_full and view.until_full) and math.ceil(view.until_full) or -1;
    if (hp == resting_detail.hp and mp == resting_detail.mp and until_full == resting_detail.until_full) then
        return resting_detail.text;
    end
    resting_detail.hp, resting_detail.mp, resting_detail.until_full = hp, mp, until_full;

    local parts = {};
    if (hp > 0) then
        table.insert(parts, ('+%d HP'):format(hp));
    end
    if (mp > 0) then
        table.insert(parts, ('+%d MP'):format(mp));
    end
    if (until_full >= 0) then
        table.insert(parts, 'full in ' .. duration_text(until_full));
    end
    resting_detail.text = (#parts > 0) and table.concat(parts, '  ') or nil;
    return resting_detail.text;
end

--[[
    Draws the resting timer.

    view = {
        fill = 0..1, left = seconds to the next tick, gained_hp, gained_mp = what the last tick
        restored, full = true at full HP and MP, until_full = seconds until full or nil,
        hp_full_in, mp_full_in = seconds until each is full, 0 once it is, or nil,
        has_mp = false for a job with no MP, flash = 0..1 strength of the tick flash,
        why = the buff id of what keeps ticks from healing you, a key in CANT_HEAL_WORDS, or nil,
    }
]]
function hud.draw_resting(view)
    local element = settings.resting;
    -- Full needs no healing, so it wins.
    local cant = (element.show_why and not view.full) and CANT_HEAL_WORDS[view.why] or nil;

    resting_timer.label = label_for(element, 'RESTING');
    resting_timer.fill = view.fill;
    resting_timer.dim = cant and STOPPED_DIM or nil;
    resting_timer.start_color = colors.resting_start;
    resting_timer.solid = view.full and colors.full or nil;
    resting_timer.value_color = view.full and colors.full or nil;
    resting_timer.value = nil;
    if (element.show_value) then
        resting_timer.value = view.full and 'full' or seconds_text(resting_text, view.left);
        if (cant ~= nil) then
            resting_timer.value, resting_timer.value_color = cant, colors.detail;
        end
    end
    -- The gains and the full times aren't true while ticks heal nothing. Their rows stay, so the card
    -- keeps its size.
    resting_timer.detail = (cant == nil) and resting_detail_text(element, view) or nil;
    fill_full_line(resting_timer, view);
    if (cant ~= nil) then
        resting_timer.footer = nil;
    end

    resting_timer.flash = nil;
    if (element.flash_on_tick and view.flash > 0) then
        resting_timer.flash = faded(element.flash_color, view.flash);
    end

    draw_timer(resting_timer);
end

local enemy_text = { tenths = -1, text = '' };

-- What the enemy timer says instead of the seconds while the monster readies a TP move or casts.
local HOLD_WORDS = { tp_move = 'TP move', spell = 'casting' };
local enemy_detail = { name = nil, delay = -1, learned = false, tag = nil, show_name = false, show_delay = false,
    show_effects = false, text = nil };
local enemy_timer = { key = 'enemy' };

-- The small text after the label, like "Young Quadav  4.42s  slow". Rebuilt only when something in it
-- changes.
local function enemy_detail_text(element, view)
    local last = enemy_detail;
    if (view.name == last.name and view.delay == last.delay and view.learned == last.learned and view.tag == last.tag
        and element.show_name == last.show_name and element.show_delay == last.show_delay
        and element.show_effects == last.show_effects) then
        return last.text;
    end
    last.name, last.delay, last.learned, last.tag = view.name, view.delay, view.learned, view.tag;
    last.show_name, last.show_delay, last.show_effects = element.show_name, element.show_delay, element.show_effects;

    local parts = {};
    if (element.show_name and view.name ~= nil) then
        table.insert(parts, view.name);
    end
    if (element.show_delay) then
        table.insert(parts, delay_text(view.delay, view.learned));
    end
    if (element.show_effects and view.tag ~= nil) then
        table.insert(parts, view.tag);
    end
    last.text = (#parts > 0) and table.concat(parts, '  ') or nil;
    return last.text;
end

--[[
    Draws the enemy attack timer.

    view = {
        fill = 0..1, left = seconds to the monster's next round, delay = the delay in use,
        learned = true once it was learned from the monster's own rounds, name = the monster's name,
        waiting = true once it's overdue by a whole delay, like while it's asleep or chasing you,
        tag = the effects on it, like "slow", or nil,
        holding = 'tp_move' or 'spell' while one holds its timer, or nil,
        on_you = true when its last attack was on you,
    }
]]
function hud.draw_enemy(view)
    local element = settings.enemy;
    local ready = view.left <= 0 and not view.waiting;
    local almost = not ready and not view.waiting and element.almost_ready and view.left <= element.almost_seconds;
    local state_color = (ready and colors.enemy_ready) or (almost and colors.enemy_almost) or nil;

    enemy_timer.fill = view.waiting and 0 or view.fill;
    enemy_timer.mark = (not view.waiting) and almost_mark(element, view.fill, view.left) or nil;
    enemy_timer.mark_color = colors.enemy_almost;
    enemy_timer.start_color = colors.enemy_start;
    enemy_timer.solid = state_color;
    enemy_timer.value_color = view.waiting and colors.detail or state_color;
    enemy_timer.value = nil;
    if (element.show_value) then
        enemy_timer.value = (view.waiting and '--') or (ready and 'ready') or seconds_text(enemy_text, view.left);
    end
    if (element.show_holds and view.holding ~= nil) then
        enemy_timer.value, enemy_timer.value_color = HOLD_WORDS[view.holding], colors.enemy_almost;
    end
    enemy_timer.detail = enemy_detail_text(element, view);

    -- Following whoever hits you, it's always on you, so there's nothing to mark.
    local marked = element.show_on_you and view.on_you and element.which ~= 'attacker';
    enemy_timer.mark_as = marked and colors.on_you or nil;

    enemy_timer.label = label_for(element, element.attached and 'ENEMY' or 'ENEMY ATTACK');
    enemy_timer.corners, enemy_timer.x, enemy_timer.y = nil, nil, nil;
    if (element.attached and settings.attack.enabled) then
        -- Under the card at the auto attack spot, sharing its bottom border line. Between fights that
        -- card is hidden, and the strip stays where it will be, so it doesn't jump when you engage.
        -- With the auto attack timer turned off, it sits at its own spot, where Shift can drag it.
        if (host.shown) then
            enemy_timer.x = host.x;
            enemy_timer.y = host.y + host.height - size.overlap;
            enemy_timer.corners = ImDrawFlags_RoundCornersBottom;
        else
            -- Where that card and the strip under it would be drawn, pulled in together.
            local width, attack_height = hud.element_size('attack');
            local _, strip_height = hud.element_size('enemy');
            local x, y = on_screen(settings.attack.x, settings.attack.y, width,
                attack_height + strip_height - size.overlap);
            enemy_timer.x = x;
            enemy_timer.y = y + attack_height - size.overlap;
        end
    end

    draw_timer(enemy_timer);
end

-- Everything the HUD draws in a frame goes between begin_frame() and end_frame().
function hud.begin_frame()
    host.shown, host.hovered = false, false;
    face = chosen_font or imgui.GetFont();
    screen.width, screen.height = hud.screen_size();
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, set_point(A, 0, 0));
    imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, set_point(B, 1, 1));
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 0);
end

-- Returns true once a drag has finished and the new positions should be saved.
function hud.end_frame()
    imgui.PopStyleVar(4);
    if (layout_dirty and not imgui.IsMouseDown(ImGuiMouseButton_Left)) then
        layout_dirty = false;
        return true;
    end
    return false;
end

return hud;
