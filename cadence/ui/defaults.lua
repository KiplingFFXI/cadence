--[[
    Default settings. Ashita saves your copy per character under config\addons\cadence\.

    make() builds a fresh table every call, so editing your settings can never change the defaults.
]]

local theme       = require('ui.theme');
local window_font = require('ui.window_font');
local chat_colors = require('ui.chat_colors');
local navigation = require('ui.navigation');

local P = theme.palette;

-- Every color gets its own table. A shared one would let a color picker edit the palette itself.
local function color(base, alpha)
    return { base[1], base[2], base[3], alpha or base[4] };
end

local defaults = {};

-- The smallest and largest a timer can be, from the settings window or a drag on its edge.
defaults.WIDTH      = { 120, 640 };
defaults.BAR_HEIGHT = { 2, 32 };
defaults.HEIGHT_SCALE = { 0.5, 2.5 };

-- The size of the timer names, like AUTO ATTACK, and of the small text next to them and under the
-- bars. Below the smallest it's auto, which follows the text size.
defaults.LABEL_SIZE  = { 8, 32 };
defaults.DETAIL_SIZE = { 8, 32 };

-- How far each slider goes, by section. The settings window and the settings check both read this.
-- Label size and Detail size start one below their smallest, at auto.
local ALMOST_SECONDS = { 0.1, 2.0 };
defaults.RANGES = {
    attack  = { width = defaults.WIDTH, height_scale = defaults.HEIGHT_SCALE, bar_height = defaults.BAR_HEIGHT, almost_seconds = ALMOST_SECONDS },
    resting = { width = defaults.WIDTH, height_scale = defaults.HEIGHT_SCALE, bar_height = defaults.BAR_HEIGHT, flash_seconds = { 0.2, 1.5 },
        sound_volume = { 0, 100 } },
    enemy   = { width = defaults.WIDTH, height_scale = defaults.HEIGHT_SCALE, bar_height = defaults.BAR_HEIGHT, almost_seconds = ALMOST_SECONDS },
    style   = {
        scale       = { 0.5, 2.5 },
        font_size   = { 10, 28 },
        detail_size = { defaults.DETAIL_SIZE[1] - 1, defaults.DETAIL_SIZE[2] },
        label_size  = { defaults.LABEL_SIZE[1] - 1, defaults.LABEL_SIZE[2] },
        rounding    = { 0, 12 },
    },
    window_style = {
        rounding  = { 0, 12 },
        spacing   = { 2, 14 },
        font_size = { window_font.SIZE_MIN, window_font.SIZE_MAX },
    },
};

-- The longest label you can type for a timer.
defaults.LABEL_LENGTH = 23;
defaults.TP_GOALS = { 1000, 2000, 3000 };
defaults.GOAL_PERCENT = { 1, 100 };
defaults.GOAL_AMOUNT = { 1, 99999 };

-- What Follows can be, as its settings value, its name in the settings window and its word for
-- /cadence enemy follow.
defaults.FOLLOWS = {
    { 'target_first', 'My target first', 'first' },
    { 'target',       'My target only',  'target' },
    { 'attacker',     'Whoever hits me', 'hits' },
};

-- Main jobs 1 to 18 in job id order, the ones a job link can name. Dancer and Scholar came after the era.
defaults.JOBS = {
    'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST',
    'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP',
};
local IS_JOB = {};
for _, job in ipairs(defaults.JOBS) do
    IS_JOB[job] = true;
end

-- The settings window's look in Phoenix's palette, in Ashita's font at its own size.
local function window_style()
    local style = theme.window_style('phoenix');
    style.font, style.font_size = window_font.LIST[1].id, window_font.SIZE_DEFAULT;
    return style;
end

function defaults.make()
    return T{
        attack = T{
            enabled        = true,
            x              = 780,
            y              = 664,
            width          = 240,
            height_scale   = 1.0,
            bar_height     = 5,
            show_value     = true,
            show_delay     = true,
            -- The bar, then almost ready, then ready, each brighter than the last, so colorblind players
            -- see every change.
            fill_start     = color(P.royal),
            fill_end       = color(P.ember),
            ready_color    = color(P.text),
            almost_ready   = true,
            almost_seconds = 0.5,
            almost_color   = color(P.gold),
            show_tp        = true,
            show_tp_rounds = true,
            show_tp_hits   = false,
            show_tp_time   = false,
            tp_goal        = 1000,
            tp_color       = color(P.success),
            numbers_only   = false,
            almost_mark    = false,
            label_text     = '',
            show_label     = true,
            show_reason    = true,
            show_why       = true,
        },
        resting = T{
            enabled         = true,
            x               = 780,
            y               = 620,
            width           = 240,
            height_scale    = 1.0,
            bar_height      = 5,
            show_value      = true,
            show_gains      = true,
            show_next_gains = false,
            show_ticks      = false,
            show_until_full = true,
            show_goal       = false,
            goal_stat       = 'mp',
            goal_mode       = 'percent',
            goal_value      = 100,
            fill_start      = color(P.royal),
            fill_end        = color(P.ember),
            full_color      = color(P.mint),
            flash_on_tick   = true,
            flash_seconds   = 0.5,
            flash_color     = color(P.ember, 0.45),
            numbers_only    = false,
            show_each_full  = false,
            hide_when_full  = false,
            label_text      = '',
            show_label      = true,
            show_why        = true,
            -- A sound that comes with cadence, or one of yours from config\addons\cadence\sounds, that plays
            -- once your HP and MP are full, and how loud.
            sound           = false,
            sound_file      = 'FF VII Save.mp3',
            sound_volume    = 100,
        },
        enemy = T{
            enabled        = false,
            which          = 'target_first',
            keep_last      = true,
            attached       = false,
            x              = 780,
            y              = 724,
            width          = 240,
            height_scale   = 1.0,
            bar_height     = 5,
            show_value     = true,
            show_name      = true,
            show_delay     = true,
            show_effects   = true,
            show_holds     = true,
            show_on_you    = true,
            fill_start     = color(P.muted),
            fill_end       = color(P.rose),
            ready_color    = color(P.royal),
            almost_ready   = true,
            almost_seconds = 0.5,
            almost_color   = color(P.gold),
            on_you_color   = color(P.ember),
            numbers_only   = false,
            almost_mark    = false,
            label_text     = '',
            -- The timer's own name, like ENEMY ATTACK. show_name is the monster's name in the small text.
            show_label     = true,
        },
        window = T{
            x      = 120,
            y      = 10,
            width  = 920,
            height = 680,
            tabs   = navigation.normalize({}),
        },
        style = T{
            hover_tips         = true,
            record_diagnostics = false,
            layout_guides      = false,
            scale              = 1.0,
            font_size          = 14,
            detail_size        = 0,
            system_font        = true,
            font_name          = 'Segoe UI Semibold',
            show_labels        = true,
            label_size         = 0,
            rounding           = 0,
            panel              = true,
            panel_color        = color(P.surface1, 0.88),
            border             = true,
            border_color       = color(P.border),
            accent             = true,
            accent_color       = color(P.royal),
            track_color        = color(P.surface2),
            label_color        = color(P.peach),
            value_color        = color(P.text),
            detail_color       = color(P.soft),
            text_shadow        = true,
            text_outline       = false,
            outline_color      = color(P.shadow),
            shared_spot        = false,
            locked             = false,
            see_through        = true,
            hide_during_events = true,
            hide_with_game_ui  = true,
            hide_on_map        = true,
            bar_drains         = false,
            -- The id of the last preset you picked, and whether picking one sets the settings
            -- window's look too.
            window_look         = 'phoenix',
            window_matches_look = true,
        },
        -- The settings window's own look. A color for each key in theme.WINDOW_COLORS, its corner
        -- roundness, the space between its rows, and its font and font size. It starts as the Phoenix
        -- palette in Ashita's font at 18 px.
        window_style = T(window_style()),
        -- The chat color codes of the tag's brackets, the word cadence in it and the answer after it.
        -- They're the ones Ashita's chat.header and chat.message use.
        chat = T{
            tag_brackets = 81,
            tag_word     = 6,
            replies      = 106,
        },
        -- The profile each main job loads, by the job's short name, like BLM = 'Nuker'. They stay with
        -- each character. Profiles and the shared layout leave them out.
        job_links = T{},
        profile_source = T{ kind = '', name = '' },
    };
end

local TIMERS = { 'attack', 'resting', 'enemy' };

-- Like type(), but 0/0 gets its own name. Lua counts it as a number. It's no use as a setting, and
-- Ashita's settings file can hold one.
local function kind(value)
    if (value ~= value) then
        return 'nan';
    end
    return type(value);
end

-- A color is four numbers, each pulled into 0 to 1. Anything else gets the default.
local function tidy_color(value, default)
    for i = 1, 4 do
        if (kind(value[i]) ~= 'number') then
            return default;
        end
    end
    for i = 1, 4 do
        value[i] = math.max(0, math.min(1, value[i]));
    end
    return value;
end

local function is_follows(word)
    for _, choice in ipairs(defaults.FOLLOWS) do
        if (choice[1] == word) then
            return true;
        end
    end
    return false;
end

-- A job link has to be a main job's short name with a profile name after it. A link to a profile that
-- isn't there anymore stays, so the Profiles tab can show it. The table itself stays too, since the
-- shared layout uses this character's own.
local function tidy_job_links(settings)
    local links = settings.job_links;
    if (type(links) ~= 'table') then
        settings.job_links = T{};
        return;
    end
    for job, name in pairs(links) do
        if (not IS_JOB[job] or type(name) ~= 'string' or name == '') then
            links[job] = nil;
        end
    end
end

-- The sound is a file in a sounds folder, so its name keeps only the part after the last \, / or :.
-- A double quote would break the command that opens it. A name of only dots is a folder, not a file.
local function tidy_sound_file(name)
    local plain = name:match('[^\\/:]*$'):gsub('[%c"]', '');
    if (plain:find('^%.*$')) then
        return '';
    end
    return plain;
end

--[[
    Fixes what a hand-edited settings file or shared layout can get wrong. A number outside its
    slider's range is pulled back in. A value of the wrong type gets its default. A label keeps only
    plain printable characters, Follows has to be one of its words, and the last preset picked, the
    settings window's font and the chat colors have to be ones there are. The sound's file name has no
    folder in it. A job link has to name a main job and a profile. A normal settings file comes through
    as it is. cadence runs it on load, on login and before each save.
]]
function defaults.tidy(settings)
    local fresh = defaults.make();
    for name, section in pairs(fresh) do
        local mine = settings[name];
        if (type(mine) ~= 'table') then mine = section; settings[name] = mine; end
        local ranges = defaults.RANGES[name];
        for key, default in pairs(section) do
            local value = mine[key];
            local range = ranges and ranges[key];
            if (name == 'window' and key == 'tabs') then
                local clean = navigation.normalize(value);
                if (type(value) ~= 'table') then value = {}; mine[key] = value; end
                for tab in pairs(value) do value[tab] = nil; end
                for tab, shown in pairs(clean) do value[tab] = shown; end
            elseif (kind(value) ~= type(default)) then
                mine[key] = default;
            elseif (type(value) == 'table') then
                mine[key] = tidy_color(value, default);
            elseif (range ~= nil) then
                -- Label size and Detail size are 0 by default, below their slider. Anything down there is auto.
                mine[key] = math.max(math.min(range[1], default), math.min(range[2], value));
            elseif (value == math.huge or value == -math.huge) then
                -- A spot or size with no range still can't be endless. The shared layout can't save it.
                mine[key] = default;
            end
        end
    end

    for _, name in ipairs(TIMERS) do
        local element = settings[name];
        element.label_text = element.label_text:gsub('[^\32-\126]', ''):sub(1, defaults.LABEL_LENGTH);
    end
    settings.resting.sound_file = tidy_sound_file(settings.resting.sound_file);
    if (settings.resting.goal_stat ~= 'hp' and settings.resting.goal_stat ~= 'mp' and settings.resting.goal_stat ~= 'both') then
        settings.resting.goal_stat = fresh.resting.goal_stat;
    end
    if (settings.resting.goal_mode ~= 'percent' and settings.resting.goal_mode ~= 'amount') then
        settings.resting.goal_mode = fresh.resting.goal_mode;
    end
    local goal_range = settings.resting.goal_mode == 'amount' and defaults.GOAL_AMOUNT or defaults.GOAL_PERCENT;
    settings.resting.goal_value = math.floor(math.max(goal_range[1], math.min(goal_range[2], settings.resting.goal_value)));
    if (settings.attack.tp_goal ~= 1000 and settings.attack.tp_goal ~= 2000 and settings.attack.tp_goal ~= 3000) then
        settings.attack.tp_goal = fresh.attack.tp_goal;
    end
    if (not is_follows(settings.enemy.which)) then
        settings.enemy.which = fresh.enemy.which;
    end
    if (theme.window_palettes[settings.style.window_look] == nil) then
        settings.style.window_look = fresh.style.window_look;
    end
    settings.window_style.font = window_font.clean_id(settings.window_style.font);
    for _, part in ipairs(chat_colors.PARTS) do
        if (not chat_colors.in_palette(settings.chat[part.key])) then
            settings.chat[part.key] = fresh.chat[part.key];
        end
    end
    tidy_job_links(settings);
    local source = settings.profile_source;
    if (source.kind ~= 'profile' and source.kind ~= 'layout') then source.kind, source.name = '', ''; end
    source.name = source.name:gsub('[^\32-\126]', ''):sub(1, 32);
end

return defaults;
