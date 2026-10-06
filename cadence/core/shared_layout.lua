--[[
    One layout for all characters.

    Ashita keeps settings per character and writes them to that character's own file. While this is
    on, cadence uses a copy instead and writes it to config\addons\cadence\shared_layout.json. Every
    character that logs in loads the copy from there. Their own settings stay as they were. Turning
    it off deletes that file. This character keeps the shared layout as its own. Every other
    character goes back to its own.

    Job links stay with each character. The shared copy uses this character's own links, so a link
    set while sharing goes into this character's file, and the shared file never holds any.
]]

local json = require('json');

local shared_layout = {};

local FOLDER = ('%s\\config\\addons\\%s\\'):format(AshitaCore:GetInstallPath(), addon.name);
local FILE   = FOLDER .. 'shared_layout.json';

-- The sections that stay with each character.
local OWN = { job_links = true };

-- The shared copy while this is on, or nil.
local shared = nil;

local function read_file()
    local file = io.open(FILE, 'r');
    if (file == nil) then
        return nil;
    end
    local text = file:read('*a');
    file:close();

    local ok, data = pcall(json.decode, text);
    if (not ok or type(data) ~= 'table') then
        return nil;
    end
    return data;
end

local function write_file(data)
    ashita.fs.create_dir(FOLDER);
    local file = io.open(FILE, 'w');
    if (file == nil) then
        return;
    end
    file:write(json.encode(data));
    file:close();
end

-- A copy of `source` with tables of its own.
local function copy(source)
    local result = {};
    for key, value in pairs(source) do
        result[key] = (type(value) == 'table') and copy(value) or value;
    end
    return result;
end

-- A copy of `own` to share. The sections that stay with each character are `own`'s very tables.
local function share_copy(own)
    local result = copy(own);
    for name in pairs(OWN) do
        result[name] = own[name];
    end
    return result;
end

-- Copies values from `source` into `target` for every key `target` already has, keeping its tables.
local function copy_into(target, source)
    for key, value in pairs(source) do
        local current = target[key];
        if (type(current) == 'table' and type(value) == 'table') then
            copy_into(current, value);
        elseif (current ~= nil and type(current) == type(value)) then
            target[key] = value;
        end
    end
end

function shared_layout.is_on()
    return shared ~= nil;
end

-- The settings to use after a load or a login. While this is on, that's a copy of `own` with the
-- shared layout on top. Otherwise it's `own`. Job links in a hand-edited shared file are left out.
function shared_layout.apply(own)
    local data = read_file();
    shared = nil;
    if (data ~= nil and data.enabled == true and type(data.settings) == 'table') then
        for name in pairs(OWN) do
            data.settings[name] = nil;
        end
        shared = share_copy(own);
        copy_into(shared, data.settings);
    end
    return shared or own;
end

-- Starts sharing with a copy of `own`. Already on, it keeps the copy it has. Returns the copy to use.
function shared_layout.turn_on(own)
    shared = shared or share_copy(own);
    return shared;
end

-- Writes the shared copy for every character to load, without the sections that stay with each one.
function shared_layout.save()
    local out = {};
    for name, section in pairs(shared) do
        if (not OWN[name]) then
            out[name] = section;
        end
    end
    write_file({ enabled = true, settings = out });
end

-- Stops sharing and deletes the shared file. `own` takes the shared layout, so nothing on screen
-- changes. Returns `own`.
function shared_layout.turn_off(own)
    if (shared ~= nil) then
        copy_into(own, shared);
        shared = nil;
    end
    os.remove(FILE);
    return own;
end

return shared_layout;
