-- Settings history stays in memory and belongs to the active settings table.
local defaults = require('ui.defaults');
local theme = require('ui.theme');
local history = { LIMIT = 8 };
local owners = setmetatable({}, { __mode = 'k' });
local WINDOW_GEOMETRY = { x = true, y = true, width = true, height = true };

function history.copy(value)
    if (type(value) ~= 'table') then return value; end
    local out = T{};
    for key, inner in pairs(value) do out[key] = history.copy(inner); end
    return out;
end

function history.equal(a, b)
    if (type(a) ~= type(b)) then return false; end
    if (type(a) ~= 'table') then return a == b; end
    for key, value in pairs(a) do if (not history.equal(value, b[key])) then return false; end end
    for key in pairs(b) do if (a[key] == nil) then return false; end end
    return true;
end

function history.capture(settings)
    return history.copy(settings);
end

local function ignored(path, key)
    return (#path == 0 and key == 'profile_source')
        or (#path == 1 and path[1] == 'window' and WINDOW_GEOMETRY[key]);
end

local function remember_change(path, key, value, out)
    local saved_path = history.copy(path);
    saved_path[#saved_path + 1] = key;
    out[#out + 1] = { path = saved_path, before = history.copy(value) };
end

local function differences(before, after, path, out, partial)
    for key, a in pairs(before) do
        if (not ignored(path, key)) then
            local b = after[key];
            if (type(a) == 'table' and type(b) == 'table') then
                path[#path + 1] = key;
                differences(a, b, path, out, partial);
                path[#path] = nil;
            elseif (not history.equal(a, b)) then
                remember_change(path, key, a, out);
            end
        end
    end
    if (not partial) then
        for key in pairs(after) do
            if (before[key] == nil and not ignored(path, key)) then
                remember_change(path, key, nil, out);
            end
        end
    end
end

local function record(settings, before, label, partial)
    if (type(before) ~= 'table') then return false; end
    local changes = {};
    differences(before, settings, {}, changes, partial);
    if (#changes == 0) then return false; end
    local stack = owners[settings] or {};
    owners[settings] = stack;
    stack[#stack + 1] = { changes = changes, label = label or 'Settings change',
        source = history.copy(partial and settings.profile_source or before.profile_source) };
    if (#stack > history.LIMIT) then table.remove(stack, 1); end
    return true;
end

-- Call once when an edit finishes, using a full settings capture from before it.
function history.record(settings, before, label)
    return record(settings, before, label, false);
end

-- HUD gestures already return a smaller snapshot containing only their layout fields.
function history.record_patch(settings, before, label)
    return record(settings, before, label, true);
end

function history.status(settings)
    local stack = owners[settings];
    return stack and stack[#stack] and stack[#stack].label;
end

function history.undo(settings)
    local stack = owners[settings];
    if (stack == nil or #stack == 0) then return false, 'none'; end
    local entry = table.remove(stack);
    for _, change in ipairs(entry.changes) do
        local parent = settings;
        for i = 1, #change.path - 1 do
            local key = change.path[i];
            if (type(parent[key]) ~= 'table') then parent[key] = T{}; end
            parent = parent[key];
        end
        parent[change.path[#change.path]] = history.copy(change.before);
    end
    settings.profile_source = history.copy(entry.source) or T{ kind = '', name = '' };
    return true, entry.label;
end

function history.clear(settings)
    owners[settings] = nil;
end

local TIMER_KEEP = { x = true, y = true, label_text = true };
local STYLE_LOOK = { 'scale', 'font_size', 'detail_size', 'system_font', 'font_name', 'show_labels', 'label_size',
    'rounding', 'panel', 'panel_color', 'border', 'border_color', 'accent', 'accent_color', 'track_color',
    'label_color', 'value_color', 'detail_color', 'text_shadow', 'text_outline', 'outline_color', 'bar_drains',
    'window_look', 'window_matches_look' };
local TIMER_LOOK = {
    attack = { 'width', 'height_scale', 'bar_height', 'fill_start', 'fill_end', 'ready_color', 'almost_color', 'tp_color',
        'numbers_only', 'almost_mark', 'show_label' },
    resting = { 'width', 'height_scale', 'bar_height', 'fill_start', 'fill_end', 'full_color', 'flash_color', 'numbers_only', 'show_label' },
    enemy = { 'width', 'height_scale', 'bar_height', 'fill_start', 'fill_end', 'ready_color', 'almost_color', 'on_you_color',
        'numbers_only', 'almost_mark', 'show_label' },
};
local SECTIONS = {
    { id = 'timers', name = 'Timers' }, { id = 'attack', name = 'Auto attack' }, { id = 'resting', name = 'Resting' },
    { id = 'enemy', name = 'Enemy' }, { id = 'appearance', name = 'Appearance' }, { id = 'window', name = 'Window' },
    { id = 'windowcolors', name = 'Window colors' }, { id = 'preview', name = 'Preview' }, { id = 'profiles', name = 'Job links' },
};
local function find_section(id)
    local key = tostring(id or ''):lower():gsub('[%s_%-]+', '');
    if (key == 'look') then key = 'appearance'; end
    if (key == 'autoattack') then key = 'attack'; end
    for _, section in ipairs(SECTIONS) do if (section.id == key) then return section; end end
end

function history.sections()
    return history.copy(SECTIONS);
end

local function copy_keys(settings, base, section, keys)
    for _, key in ipairs(keys) do settings[section][key] = history.copy(base[section][key]); end
end

local function reset(settings, base, id)
    if (id == 'timers') then reset(settings, base, 'attack'); reset(settings, base, 'resting');
    elseif (TIMER_LOOK[id]) then
        for key, value in pairs(base[id]) do
            if (not TIMER_KEEP[key]) then settings[id][key] = history.copy(value); end
        end
    elseif (id == 'window') then
        copy_keys(settings, base, 'window_style', { 'font', 'font_size', 'rounding', 'spacing' });
        copy_keys(settings, base, 'style', { 'hover_tips', 'record_diagnostics' });
        copy_keys(settings, base, 'chat', { 'tag_brackets', 'tag_word', 'replies' });
    elseif (id == 'windowcolors') then
        for _, color in ipairs(theme.WINDOW_COLORS) do
            settings.window_style[color.key] = history.copy(base.window_style[color.key]);
        end
    elseif (id == 'appearance') then
        copy_keys(settings, base, 'style', STYLE_LOOK);
        for section, keys in pairs(TIMER_LOOK) do copy_keys(settings, base, section, keys); end
        reset(settings, base, 'window');
        reset(settings, base, 'windowcolors');
    elseif (id == 'preview') then
        copy_keys(settings, base, 'attack', { 'show_tp_time' });
        copy_keys(settings, base, 'resting', { 'show_goal', 'goal_stat', 'goal_mode', 'goal_value' });
        copy_keys(settings, base, 'style', { 'layout_guides' });
    elseif (id == 'profiles') then
        for key in pairs(settings.job_links) do settings.job_links[key] = nil; end
    end
end

function history.reset_section(settings, id, options)
    local section = find_section(id);
    if (section == nil) then return false, 'section'; end
    local before = history.capture(settings);
    reset(settings, defaults.make(), section.id);
    local changed = not history.equal(before, settings);
    local label = 'Reset ' .. section.name;
    if (changed and not (options and options.record == false)) then history.record(settings, before, label); end
    return changed, label;
end

return history;
