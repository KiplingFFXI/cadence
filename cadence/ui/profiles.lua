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

local profiles = {};

-- The longest profile name, in characters.
profiles.NAME_MAX = 32;

-- Job links use these words to mean no link, so a new profile can't have one as its name, in any case.
local NO_LINK_WORDS = { ['none'] = true, ['(none)'] = true };

-- What the window and chat say when you try one.
profiles.NO_LINK_NAME = 'Job links use "%s" to mean no link, so a profile can\'t have that name.';

-- Settings a profile leaves alone. Where the settings window sits and its size belong to this screen,
-- and job links belong to each character.
local NOT_SAVED = { window = true, job_links = true };

-- The settings sections a profile holds.
local SECTIONS = {};
for name in pairs(defaults.make()) do
    if (not NOT_SAVED[name]) then
        table.insert(SECTIONS, name);
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
    local ok, text = pcall(json.encode, saved);
    if (not ok) then
        return false;
    end
    ashita.fs.create_dir(FOLDER);
    local file = io.open(FILE, 'w');
    if (file == nil) then
        return false;
    end
    file:write(text);
    file:close();
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
    -- The file gets a copy when it's written. Anything that looks inside a profile reads the file again first.
    local profile = {};
    for _, section in ipairs(SECTIONS) do
        profile[section] = settings[section];
    end
    saved[name] = profile;
    if (not write()) then
        saved[name] = old;
        return false;
    end
    return true;
end

--[[
    Loads the named profile into `settings`. Anything it's missing or holds wrong comes from the
    defaults, then the settings check runs. Undo is cleared, since the look it keeps is from before
    the load.
]]
function profiles.load(settings, name)
    local profile = read()[name];
    if (profile == nil) then
        return false;
    end
    local fresh = defaults.make();
    for _, section in ipairs(SECTIONS) do
        local mine, theirs = settings[section], profile[section];
        if (type(theirs) ~= 'table') then
            theirs = {};
        end
        for key, default in pairs(fresh[section]) do
            mine[key] = fill(theirs[key], default);
        end
    end
    defaults.tidy(settings);
    presets.forget_undo();
    return true;
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
    return true, relink(settings, old, new);
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
    return true, relink(settings, name, nil);
end

return profiles;
