--[[
    One-click looks for the timers, and "Reset look". A preset only sets colors, the card, the text
    shadow, corner roundness and cadence's chat colors. With Window matches the look on, it sets the
    settings window's colors, corners and spacing too. Sizes, positions and which parts are shown stay
    as they are. Every color can still be changed after.
]]

local theme    = require('ui.theme');
local defaults = require('ui.defaults');

local hex = theme.hex;

local presets = {};

presets.NAMES = { 'Phoenix', 'Classic FFXI', 'Minimal', 'High contrast', 'Ember', 'Mint', 'Lavender', 'Colorblind safe' };

-- The short name /cadence preset takes for each one, in the same order.
presets.IDS = { 'phoenix', 'classic', 'minimal', 'contrast', 'ember', 'mint', 'lavender', 'colorblind' };

-- What the Preset list says once you change a preset's look, like "Custom (from Phoenix)", by the
-- preset's short name. Made once, so the settings window builds no text each frame.
local CUSTOM_NAMES = {};
for i, id in ipairs(presets.IDS) do
    CUSTOM_NAMES[id] = ('Custom (from %s)'):format(presets.NAMES[i]);
end

-- The settings a preset controls, by section.
local PRESET_KEYS = {
    style = { 'panel', 'panel_color', 'border', 'border_color', 'accent', 'accent_color', 'track_color',
        'label_color', 'value_color', 'detail_color', 'text_shadow', 'rounding', 'window_look' },
    attack  = { 'fill_start', 'fill_end', 'ready_color', 'almost_color', 'tp_color' },
    resting = { 'fill_start', 'fill_end', 'full_color', 'flash_color' },
    enemy   = { 'fill_start', 'fill_end', 'ready_color', 'almost_color', 'on_you_color' },
    chat    = { 'tag_brackets', 'tag_word', 'replies' },
};

-- The sizes, fonts, labels and bar options that "Reset look" puts back on top of those. A preset never
-- changes the settings window's font or font size.
local LOOK_KEYS = {
    style = { 'scale', 'font_size', 'detail_size', 'system_font', 'font_name', 'show_labels', 'label_size',
        'bar_drains', 'text_outline', 'outline_color' },
    attack  = { 'width', 'height_scale', 'bar_height', 'numbers_only', 'almost_mark', 'label_text', 'show_label' },
    resting = { 'width', 'height_scale', 'bar_height', 'numbers_only', 'label_text', 'show_label' },
    enemy   = { 'width', 'height_scale', 'bar_height', 'numbers_only', 'almost_mark', 'label_text', 'show_label' },
    window_style = { 'font', 'font_size' },
};

-- The settings window's colors, corner roundness and spacing. A preset sets them while Window matches
-- the look is on, and "Reset look" always does.
local WINDOW_KEYS = { window_style = { 'rounding', 'spacing' } };
for _, entry in ipairs(theme.WINDOW_COLORS) do
    table.insert(WINDOW_KEYS.window_style, entry.key);
end

-- Every look but Phoenix. Each one is built fresh, so a color picker never edits the preset itself.
-- The chat colors are the ones checkmate's skin of the same name uses.
local LOOKS = {
    ['Classic FFXI'] = function ()
        return {
            style = {
                panel = true, panel_color = hex('0b1a3d', 0.82),
                border = true, border_color = hex('8ea3d6', 0.55),
                accent = false, accent_color = hex('e8c86a'),
                track_color = hex('09122b'),
                label_color = hex('b7c4e6'), value_color = hex('ffffff'), detail_color = hex('9fb0d8'),
                text_shadow = true, rounding = 4, window_look = 'classic',
            },
            -- Almost ready is darker than the gold on your bar and lighter than the red on the enemy's. Full
            -- leans lime. That way colorblind players see every change.
            attack  = { fill_start = hex('3a6fd8'), fill_end = hex('8fd0ff'), ready_color = hex('ffd966'), almost_color = hex('d78b2a'), tp_color = hex('7ee08a') },
            resting = { fill_start = hex('3a6fd8'), fill_end = hex('8fd0ff'), full_color = hex('b4de7d'), flash_color = hex('ffffff', 0.35) },
            enemy   = { fill_start = hex('7a2f2f'), fill_end = hex('e07b7b'), ready_color = hex('fa333a'), almost_color = hex('feba5b'), on_you_color = hex('ffb347') },
            chat    = { tag_brackets = 81, tag_word = 6, replies = 106 },
        };
    end,
    ['Minimal'] = function ()
        return {
            style = {
                panel = false, panel_color = hex('000000', 0.5),
                border = false, border_color = hex('ffffff', 0.3),
                accent = false, accent_color = hex('ffffff'),
                track_color = hex('000000', 0.45),
                label_color = hex('ffffff', 0.8), value_color = hex('ffffff'), detail_color = hex('e0e0e0', 0.85),
                text_shadow = true, rounding = 3, window_look = 'minimal',
            },
            -- The bars are white, so ready and full step down to a darker seafoam instead. That way colorblind
            -- players can still tell them from the bar and from almost ready.
            attack  = { fill_start = hex('f2f2f2'), fill_end = hex('ffffff'), ready_color = hex('72b99c'), almost_color = hex('ffd27a'), tp_color = hex('8fd0ff') },
            resting = { fill_start = hex('f2f2f2'), fill_end = hex('ffffff'), full_color = hex('72b99c'), flash_color = hex('ffffff', 0.3) },
            enemy   = { fill_start = hex('9a9a9a'), fill_end = hex('cfcfcf'), ready_color = hex('e58181'), almost_color = hex('ffd27a'), on_you_color = hex('ff9b6b') },
            -- The whole line in cream.
            chat    = { tag_brackets = 106, tag_word = 106, replies = 106 },
        };
    end,
    ['High contrast'] = function ()
        return {
            style = {
                panel = true, panel_color = hex('000000', 0.92),
                border = true, border_color = hex('ffffff', 0.7),
                accent = true, accent_color = hex('ffd000'),
                track_color = hex('333333'),
                label_color = hex('ffe066'), value_color = hex('ffffff'), detail_color = hex('e6e6e6'),
                text_shadow = true, rounding = 0, window_look = 'contrast',
            },
            -- Ready and full are white and almost ready is blue, so colorblind players can tell them from the
            -- filling bars too.
            attack  = { fill_start = hex('ffd000'), fill_end = hex('ff7a00'), ready_color = hex('ffffff'), almost_color = hex('00a8ff'), tp_color = hex('ff66ff') },
            resting = { fill_start = hex('ffd000'), fill_end = hex('ff7a00'), full_color = hex('ffffff'), flash_color = hex('ffffff', 0.5) },
            enemy   = { fill_start = hex('ff00aa'), fill_end = hex('ff5500'), ready_color = hex('ffffff'), almost_color = hex('00a8ff'), on_you_color = hex('ff6a00') },
            -- White, with the word cadence in yellow.
            chat    = { tag_brackets = 1, tag_word = 69, replies = 1 },
        };
    end,
    -- The warm browns and orange of checkmate's Ember skin. Your bars glow from deep to light orange.
    -- Almost ready is gold, ready is warm white and full is pale green. The enemy bar is ash grey and
    -- turns red once the monster can attack. The enemy timer's name and stripe go white while the
    -- monster's last attack was on you. Each change differs in brightness too, so colorblind players
    -- see it.
    ['Ember'] = function ()
        return {
            style = {
                panel = true, panel_color = hex('2a1d12', 0.88),
                border = true, border_color = hex('ffb070', 0.25),
                accent = true, accent_color = hex('e8742a'),
                track_color = hex('3a2716'),
                label_color = hex('ffc38a'), value_color = hex('fff4e8'), detail_color = hex('c4a07e'),
                text_shadow = true, rounding = 2, window_look = 'ember',
            },
            attack  = { fill_start = hex('b4471c'), fill_end = hex('f08a3c'), ready_color = hex('fff4e8'), almost_color = hex('ffd23f'), tp_color = hex('8fcf6a') },
            resting = { fill_start = hex('b4471c'), fill_end = hex('f08a3c'), full_color = hex('b4f0b4'), flash_color = hex('ffa04d', 0.45) },
            enemy   = { fill_start = hex('6b6058'), fill_end = hex('b2a798'), ready_color = hex('f2402a'), almost_color = hex('ffd23f'), on_you_color = hex('ffffff') },
            -- Dark salmon brackets, the word cadence in coral and moccasin answers.
            chat    = { tag_brackets = 85, tag_word = 8, replies = 7 },
        };
    end,
    ['Mint'] = function ()
        return {
            style = {
                panel = true, panel_color = hex('192f29', 0.88),
                border = true, border_color = hex('8fe3ba', 0.35),
                accent = true, accent_color = hex('74d9ad'),
                track_color = hex('233d34'),
                label_color = hex('b1ebd0'), value_color = hex('edf9f1'), detail_color = hex('9bbbad'),
                text_shadow = true, rounding = 4, window_look = 'mint',
            },
            attack  = { fill_start = hex('32866c'), fill_end = hex('74d9ad'), ready_color = hex('edf9f1'), almost_color = hex('f5c850'), tp_color = hex('9fcfff') },
            resting = { fill_start = hex('32866c'), fill_end = hex('74d9ad'), full_color = hex('edf9f1'), flash_color = hex('a4edcc', 0.40) },
            enemy   = { fill_start = hex('626c68'), fill_end = hex('a4b4ad'), ready_color = hex('f07868'), almost_color = hex('f5c850'), on_you_color = hex('ff865e') },
            chat    = { tag_brackets = 102, tag_word = 88, replies = 90 },
        };
    end,
    ['Lavender'] = function ()
        return {
            style = {
                panel = true, panel_color = hex('262033', 0.88),
                border = true, border_color = hex('cdb1f4', 0.35),
                accent = true, accent_color = hex('c3a0ed'),
                track_color = hex('342b45'),
                label_color = hex('deccf7'), value_color = hex('f3ecff'), detail_color = hex('b5a5c9'),
                text_shadow = true, rounding = 4, window_look = 'lavender',
            },
            attack  = { fill_start = hex('77629e'), fill_end = hex('c3a0ed'), ready_color = hex('f3ecff'), almost_color = hex('f5c850'), tp_color = hex('a8d9c0') },
            resting = { fill_start = hex('77629e'), fill_end = hex('c3a0ed'), full_color = hex('f3ecff'), flash_color = hex('e4ccff', 0.40) },
            enemy   = { fill_start = hex('696271'), fill_end = hex('b3aaba'), ready_color = hex('f07868'), almost_color = hex('f5c850'), on_you_color = hex('ffad70') },
            chat    = { tag_brackets = 102, tag_word = 105, replies = 90 },
        };
    end,
    --[[
        Okabe and Ito's colorblind palette. Filling bars are blue, almost ready is vermillion and ready
        or full is yellow. Each step differs in brightness too, not just in hue. The enemy bar is
        grey so its warnings stand out. Every pair that has to look different stays clearly apart under
        red-green and blue-yellow colorblindness.
    ]]
    ['Colorblind safe'] = function ()
        return {
            style = {
                panel = true, panel_color = hex('101418', 0.88),
                border = true, border_color = hex('ffffff', 0.35),
                accent = true, accent_color = hex('56b4e9'),
                track_color = hex('2b3038'),
                label_color = hex('e6e6e6'), value_color = hex('ffffff'), detail_color = hex('bdbdbd'),
                text_shadow = true, rounding = 2, window_look = 'colorblind',
            },
            attack  = { fill_start = hex('0072b2'), fill_end = hex('56b4e9'), ready_color = hex('f0e442'), almost_color = hex('d55e00'), tp_color = hex('56b4e9') },
            resting = { fill_start = hex('0072b2'), fill_end = hex('56b4e9'), full_color = hex('f0e442'), flash_color = hex('ffffff', 0.35) },
            enemy   = { fill_start = hex('6e6e6e'), fill_end = hex('bdbdbd'), ready_color = hex('f0e442'), almost_color = hex('d55e00'), on_you_color = hex('e69f00') },
            chat    = { tag_brackets = 81, tag_word = 6, replies = 106 },
        };
    end,
};

-- A fresh copy of the named look, with its settings window look. Phoenix is the default look, so it
-- comes straight from the defaults.
local function build_look(name)
    local look = LOOKS[name];
    if (look == nil) then
        return defaults.make();
    end
    local built = look();
    built.window_style = theme.window_style(built.style.window_look);
    return built;
end

-- The settings from before the last reversible layout change, for Undo. It's dropped when the addon reloads or
-- another character logs in.
local undo = nil;

-- Color tables get a copy, since a color picker edits them in place.
local function copy_value(value)
    if (type(value) ~= 'table') then
        return value;
    end
    local copy = {};
    for key, part in pairs(value) do
        copy[key] = copy_value(part);
    end
    return copy;
end

-- Keeps what the settings in each list of keys hold right now, for Undo.
local function remember(settings, ...)
    undo = {};
    for _, keys in ipairs({ ... }) do
        for section, names in pairs(keys) do
            undo[section] = undo[section] or {};
            for _, key in ipairs(names) do
                undo[section][key] = copy_value(settings[section][key]);
            end
        end
    end
end

-- Keep the latest direct snapshot. Settings actions use ui.history for their eight Undo steps.
function presets.remember_snapshot(snapshot)
    undo = copy_value(snapshot);
end

function presets.capture(settings, sections)
    local snapshot = {};
    for _, section in ipairs(sections) do snapshot[section] = copy_value(settings[section]); end
    return snapshot;
end

local function copy_keys(settings, source, keys)
    for section, names in pairs(keys) do
        for _, key in ipairs(names) do
            settings[section][key] = source[section][key];
        end
    end
end

-- Puts the named preset's colors, card, text shadow, corner roundness and chat colors into `settings`.
-- With Window matches the look on, the settings window's colors, corners and spacing go in too. Off,
-- the window stays as it is and Undo leaves it alone.
function presets.apply(settings, name)
    local look = build_look(name);
    if (settings.style.window_matches_look) then
        remember(settings, PRESET_KEYS, WINDOW_KEYS);
        copy_keys(settings, look, WINDOW_KEYS);
    else
        remember(settings, PRESET_KEYS);
    end
    copy_keys(settings, look, PRESET_KEYS);
end

-- Puts what a preset sets back to default, along with sizes, labels, font, text outline, Numbers only,
-- Ready mark, Drain instead of fill and the settings window's look, font and font size. Positions, the
-- lock and the other timer options stay as they are.
function presets.reset(settings)
    remember(settings, PRESET_KEYS, LOOK_KEYS, WINDOW_KEYS);
    local fresh = defaults.make();
    copy_keys(settings, fresh, PRESET_KEYS);
    copy_keys(settings, fresh, LOOK_KEYS);
    copy_keys(settings, fresh, WINDOW_KEYS);
end

-- Each look built once, only for telling which one you have. Nothing hands these out, so nothing edits them.
local built_looks = nil;

-- Saved colors can come back a hair off after a trip through the settings file.
local COLOR_SLACK = 0.002;

local function same_value(a, b)
    if (type(a) == 'table' and type(b) == 'table') then
        for i = 1, 4 do
            if (math.abs((a[i] or 1) - (b[i] or 1)) > COLOR_SLACK) then
                return false;
            end
        end
        return true;
    end
    return a == b;
end

local function matches(settings, look, keys)
    for section, names in pairs(keys) do
        for _, key in ipairs(names) do
            if (not same_value(settings[section][key], look[section][key])) then
                return false;
            end
        end
    end
    return true;
end

-- The name of the preset your look matches, or nil once you've changed any of what a preset sets.
-- With Window matches the look off, presets leave the settings window alone, so its look doesn't count.
function presets.current(settings)
    if (built_looks == nil) then
        built_looks = {};
        for _, name in ipairs(presets.NAMES) do
            built_looks[name] = build_look(name);
        end
    end
    local window = settings.style.window_matches_look;
    for _, name in ipairs(presets.NAMES) do
        local look = built_looks[name];
        if (matches(settings, look, PRESET_KEYS) and (not window or matches(settings, look, WINDOW_KEYS))) then
            return name;
        end
    end
    return nil;
end

-- What the Preset list says once your look matches no preset. `id` is the last preset you picked, which
-- style.window_look keeps, so you can see which one to pick to get its look back. An id it doesn't
-- know gets plain Custom.
function presets.custom_name(id)
    return CUSTOM_NAMES[id] or 'Custom';
end

-- Puts back the settings from before the last saved change. Returns false when there's nothing to
-- undo. It's one step, so a second Undo does nothing. What was kept goes back as is, since it's dropped
-- right after.
function presets.undo(settings)
    if (undo == nil) then
        return false;
    end
    for section, values in pairs(undo) do
        for key, value in pairs(values) do
            settings[section][key] = value;
        end
    end
    undo = nil;
    return true;
end

function presets.can_undo()
    return undo ~= nil;
end

-- Another character's settings came in, so this one's look isn't theirs to go back to.
function presets.forget_undo()
    undo = nil;
end

return presets;
