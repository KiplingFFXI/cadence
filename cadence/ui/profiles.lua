--[[
    Saved profiles. A profile is a named copy of your cadence settings, the timers' spots included.

    Every character shares the profiles in config\addons\cadence\profiles.json. The file is read
    again before each change and written only when a profile changes, so two game windows don't undo
    each other's work. A file that can't be read is never written over.

    Job links stay with each character, in its own settings. A link names the profile that loads
    when you change to that main job and zone.
]]

local json     = require('json');
local defaults = require('ui.defaults');
local presets  = require('ui.presets');
local history  = require('ui.history');
local layouts  = require('ui.layouts');

local store = require('core.file_store');
local profiles = {};
local deleted, overwritten;
local revision = 0;
local statuses = setmetatable({}, { __mode = 'k' });
local baselines = {};

-- The longest profile name, in characters.
profiles.NAME_MAX = 32;

-- Job links use these words to mean no link, so a new profile can't have one as its name, in any case.
local NO_LINK_WORDS = { ['none'] = true, ['(none)'] = true };

-- What the window and chat say when you try one.
profiles.NO_LINK_NAME = 'Job links use "%s" to mean no link, so a profile can\'t have that name.';

-- Settings a profile leaves alone. Where the settings window sits and its size belong to this screen,
-- and job links belong to each character.
local NOT_SAVED = { window = true, job_links = true, profile_source = true };

-- The settings sections a profile holds.
local SECTIONS, KEYS = {}, {};
for name, section in pairs(defaults.make()) do
    if (not NOT_SAVED[name]) then
        table.insert(SECTIONS, name);
        KEYS[name] = {};
        for key in pairs(section) do table.insert(KEYS[name], key); end
    end
end

local FOLDER = ('%s\\config\\addons\\%s\\'):format(AshitaCore:GetInstallPath(), addon.name);
local FILE   = FOLDER .. 'profiles.json';

local UNREADABLE = 'profiles.json can\'t be read, so profiles won\'t work until you fix or remove it. It\'s in '
    .. 'config\\addons\\cadence in your Ashita folder.';

local saved    = nil;     -- Every profile by name, as last read from the file.
local names    = {};      -- The profile names in alphabetical order.
local readable = true;    -- False when the file is there but isn't valid JSON.

-- Names go in alphabetical order in any case. Two that differ only in case keep a steady order.
local function before(a, b)
    local x, y = a:lower(), b:lower();
    if (x == y) then
        return a < b;
    end
    return x < y;
end

local function sort_names()
    names = {};
    for name in pairs(saved) do
        table.insert(names, name);
    end
    table.sort(names, before);
end

-- Reads the file. No file means no profiles.
local function read()
    revision = revision + 1;
    baselines = {};
    saved, readable = {}, true;
    local file = io.open(FILE, 'r');
    if (file ~= nil) then
        local text = file:read('*a');
        file:close();
        local ok, data = pcall(json.decode, text);
        if (ok and type(data) == 'table') then
            for name, profile in pairs(data) do
                if (type(name) == 'string' and type(profile) == 'table') then
                    saved[name] = profile;
                end
            end
        else
            readable = false;
        end
    elseif (ashita.fs.exists(FILE)) then
        readable = false;
    end
    sort_names();
    return saved;
end

-- Reads the file the first time anything asks about the profiles.
local function read_once()
    if (saved == nil) then
        read();
    end
end

local function write()
    if (not readable) then
        return false;
    end
    ashita.fs.create_dir(FOLDER);
    if (not store.write(FILE, saved)) then return false; end
    revision = revision + 1;
    baselines = {};
    sort_names();
    return true;
end

-- Your saved value, with anything missing or of the wrong type taken from the default.
local function fill(value, default)
    if (type(value) ~= type(default)) then
        return default;
    end
    if (type(default) == 'table') then
        for key, inner in pairs(default) do
            value[key] = fill(value[key], inner);
        end
    end
    return value;
end

-- Printable ASCII, no spaces at either end, and no longer than NAME_MAX. ## shrinks to one #, since
-- ImGui would hide everything after it in the list.
function profiles.clean_name(name)
    local text = tostring(name or ''):gsub('[^\32-\126]', ''):gsub('##+', '#'):match('^%s*(.-)%s*$');
    return (text:sub(1, profiles.NAME_MAX):gsub('%s+$', ''));
end

-- True for None and (none) in any case.
function profiles.no_link_word(name)
    return NO_LINK_WORDS[name:lower()] == true;
end

-- Reads the file again, since another character can change it.
function profiles.refresh()
    read();
end

-- The profile names in alphabetical order. Don't change the list.
function profiles.names()
    read_once();
    return names;
end

function profiles.exists(name)
    read_once();
    return saved[name] ~= nil;
end

-- The name of the saved profile `name` stands for in any case, or nil. The same case comes first.
function profiles.find(name)
    read_once();
    if (saved[name] ~= nil) then
        return name;
    end
    local wanted = name:lower();
    for _, saved_name in ipairs(names) do
        if (saved_name:lower() == wanted) then
            return saved_name;
        end
    end
    return nil;
end

-- False when profiles.json is there but can't be read. Nothing is saved until it's fixed or removed.
function profiles.file_ok()
    read_once();
    return readable;
end

-- What went wrong with profiles.json when a save, rename or delete didn't work.
function profiles.problem()
    if (not profiles.file_ok()) then
        return UNREADABLE;
    end
    return 'Couldn\'t write profiles.json.';
end

-- Saves `settings` as the named profile, new or over an old one. A new one can't be called None or (none).
function profiles.save(settings, name)
    name = profiles.clean_name(name);
    if (name == '') then
        return false;
    end
    read();
    local old = saved[name];
    if (old == nil and profiles.no_link_word(name)) then
        return false;
    end
    -- The saved baseline must not follow later edits to the live settings.
    local profile = {};
    for _, section in ipairs(SECTIONS) do
        profile[section] = history.copy(settings[section]);
    end
    saved[name] = profile;
    if (not write()) then
        saved[name] = old;
        return false;
    end
    -- Compare the same decoded numbers the file reader will see.
    local written = json.decode(json.encode(profile));
    if (old ~= nil and not history.equal(old, written)) then
        overwritten = { name = name, before = history.copy(old), after = written };
    end
    settings.profile_source = T{ kind = 'profile', name = name };
    profiles.changed(settings);
    return true;
end

--[[
    Loads the named profile into `settings`. Anything it's missing or holds wrong comes from the
    defaults, then the settings check runs. Undo keeps the settings from before the load.
]]
local function apply_profile(settings, profile)
    local fresh = defaults.make();
    for _, section in ipairs(SECTIONS) do
        local mine, theirs = settings[section], profile[section];
        if (type(mine) ~= 'table') then mine = T{}; settings[section] = mine; end
        if (type(theirs) ~= 'table') then theirs = {}; end
        for key, default in pairs(fresh[section]) do
            mine[key] = fill(history.copy(theirs[key]), default);
        end
    end
    defaults.tidy(settings);
end

function profiles.load(settings, name)
    local profile = read()[name];
    if (profile == nil) then return false; end
    local before = presets.capture(settings, SECTIONS);
    apply_profile(settings, profile);
    settings.profile_source = T{ kind = 'profile', name = name };
    profiles.changed(settings);
    presets.remember_snapshot(before);
    return true;
end

local function same_profile(a, b)
    if (type(a) ~= type(b)) then return false; end
    if (type(a) == 'number') then return a == b or math.abs(a - b) <= 1e-9 * math.max(1, math.abs(a), math.abs(b)); end
    if (type(a) ~= 'table') then return a == b; end
    for key, value in pairs(a) do if (not same_profile(value, b[key])) then return false; end end
    for key in pairs(b) do if (a[key] == nil) then return false; end end
    return true;
end

-- Changes clear the cached result. A status read compares again only when needed.
function profiles.invalidate_status(settings)
    statuses[settings] = nil;
end

function profiles.changed(settings)
    read_once();
    local source = settings.profile_source or {};
    local status = { kind = source.kind or '', name = source.name or '', modified = false, missing = false };
    if (status.kind == 'layout') then
        local layout = layouts.find(status.name);
        status.modified = not layouts.matches(settings, status.name);
        status.missing = layout == nil;
        status.label = layout and layout.name or status.name;
    elseif (status.kind == 'profile') then
        local profile = saved[status.name];
        status.missing = profile == nil or not readable;
        if (not status.missing) then
            -- A slider changes the current copy often, but the saved copy only changes on a file read or write.
            local expected = baselines[status.name];
            if (expected == nil) then
                expected = defaults.make();
                apply_profile(expected, profile);
                baselines[status.name] = expected;
            end
            local current = history.copy(settings);
            defaults.tidy(current);
            for _, section in ipairs(SECTIONS) do
                for _, key in ipairs(KEYS[section]) do
                    if (not same_profile(current[section][key], expected[section][key])) then status.modified = true; break; end
                end
                if (status.modified) then break; end
            end
        else status.modified = true; end
        status.label = status.name;
    else
        status.kind, status.name, status.label = '', '', 'Custom settings';
    end
    statuses[settings] = { revision = revision, status = status };
    return status;
end

-- The returned status is read-only and reused on quiet frames.
function profiles.status(settings)
    local cached = statuses[settings];
    if (cached == nil or cached.revision ~= revision) then return profiles.changed(settings); end
    return cached.status;
end

function profiles.mark_layout(settings, id)
    local layout = layouts.find(id);
    if (layout == nil) then return false; end
    settings.profile_source = T{ kind = 'layout', name = layout.id };
    profiles.changed(settings);
    return true;
end

function profiles.overwritten_name()
    return overwritten and overwritten.name;
end

function profiles.can_undo_overwrite()
    return overwritten ~= nil;
end

-- A newer version from any character wins over the copy kept for recovery.
function profiles.undo_overwrite()
    if (overwritten == nil) then return false, 'none'; end
    read();
    if (not readable) then return false, 'file'; end
    if (not history.equal(saved[overwritten.name], overwritten.after)) then return false, 'changed'; end
    saved[overwritten.name] = history.copy(overwritten.before);
    if (not write()) then saved[overwritten.name] = history.copy(overwritten.after); return false, 'file'; end
    local name = overwritten.name;
    overwritten = nil;
    return true, name;
end

-- Points this character's job links to `old` at `new`, or clears them when `new` is nil. True when a
-- link changed, so the settings need saving.
local function relink(settings, old, new)
    local changed = false;
    for job, linked in pairs(settings.job_links) do
        if (linked == old) then
            settings.job_links[job] = new;
            changed = true;
        end
    end
    return changed;
end

--[[
    Gives a profile a new name, and this character's job links to it follow. False when `old` isn't
    there, `new` is blank, the same, None or (none), another profile has `new` in any case, or the file
    can't be written. A change of case alone is fine. After true comes whether a job link changed.
]]
function profiles.rename(settings, old, new)
    new = profiles.clean_name(new);
    read();
    local taken = profiles.find(new);
    if (saved[old] == nil or new == '' or new == old or profiles.no_link_word(new)
        or (taken ~= nil and taken ~= old)) then
        return false;
    end
    saved[new] = saved[old];
    saved[old] = nil;
    if (not write()) then
        saved[old] = saved[new];
        saved[new] = nil;
        return false;
    end
    local source = settings.profile_source;
    local renamed_source = source and source.kind == 'profile' and source.name == old;
    if (renamed_source) then source.name = new; end
    profiles.changed(settings);
    return true, relink(settings, old, new), renamed_source == true;
end

-- Deletes a profile, and this character's job links to it go too. After true comes whether a job link
-- changed.
function profiles.delete(settings, name)
    read();
    local old = saved[name];
    if (old == nil) then
        return false;
    end
    saved[name] = nil;
    if (not write()) then
        saved[name] = old;
        return false;
    end
    deleted = { name = name, profile = old, owner = settings.job_links, links = {} };
    for job, linked in pairs(settings.job_links) do
        if (linked == name) then deleted.links[job] = linked; end
    end
    return true, relink(settings, name, nil);
end

function profiles.can_undo_delete()
    return deleted ~= nil;
end

function profiles.deleted_name()
    return deleted and deleted.name;
end

-- New profiles and job links win over anything kept for deletion recovery.
function profiles.undo_delete(settings)
    if (deleted == nil) then return false, 'none'; end
    read();
    if (not readable) then return false, 'file'; end
    if (profiles.find(deleted.name) ~= nil) then return false, 'exists'; end
    saved[deleted.name] = deleted.profile;
    if (not write()) then saved[deleted.name] = nil; return false, 'file'; end
    local linked = false;
    if (settings.job_links == deleted.owner) then
        for job, name in pairs(deleted.links) do
            if (settings.job_links[job] == nil) then settings.job_links[job], linked = name, true; end
        end
    end
    local name = deleted.name;
    deleted = nil;
    return true, name, linked;
end

return profiles;
