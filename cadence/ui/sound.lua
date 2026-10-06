--[[
    The sound that plays once resting fills your HP and MP. Two sounds come with cadence, in the sounds
    folder next to cadence.lua. You can add your own .mp3 or .wav files to config\addons\cadence\sounds\.
    The two that come with cadence are from Final Fantasy VII and Final Fantasy IX. They belong to Square
    Enix, and the GPL doesn't cover them.

    Ashita's own play_sound only plays .wav files. Windows' MCI plays both, so cadence talks to it
    through winmm. The file opens only while the sound is on, or when you press Play, and stays open so
    each play starts right away. It closes when you pick another one, when you turn the sound off and
    when cadence unloads. A file that won't open or play never stops cadence. It just stays quiet, and
    the settings window says so.
]]

local ffi = require('ffi');

ffi.cdef[[
    unsigned long __stdcall mciSendStringA(const char *command, char *answer, unsigned int size, void *window);
]];

-- winmm comes with Windows. Without it no sound plays, and nothing else changes.
local loaded, winmm = pcall(ffi.load, 'winmm');

local sound = {};

-- The sounds that come with cadence, and the folder for your own. addon.path can end in a \ or not.
sound.BUILT_IN = addon.path:gsub('[\\/]+$', '') .. '\\sounds\\';
sound.FOLDER = AshitaCore:GetInstallPath() .. '\\config\\addons\\cadence\\sounds\\';

-- The name MCI knows the open file by. No other addon uses it.
local ALIAS  = 'cadence_resting_sound';
local OPEN   = 'open "%s" type mpegvideo alias ' .. ALIAS;
local VOLUME = 'setaudio ' .. ALIAS .. ' volume to %d';
local PLAY   = 'play ' .. ALIAS .. ' from 0';
local CLOSE  = 'close ' .. ALIAS;

local files   = {};    -- The .mp3 and .wav files in the folder, from the last look.
local opened  = nil;   -- The file that's open.
local level   = nil;   -- The volume the open file has, from 0 to 1000.
local failed  = nil;   -- The file that last wouldn't open or play.
local problem = nil;   -- What the settings window says about it, made when it failed.

-- Sends one MCI command. True when it worked.
local function mci(command)
    return loaded and winmm.mciSendStringA(command, nil, 0, nil) == 0;
end

-- Makes the folder when it isn't there, so you can find where your files go.
function sound.make_folder()
    if (not ashita.fs.exists(sound.FOLDER)) then
        ashita.fs.create_dir(sound.FOLDER);
    end
end

local function is_sound(name)
    local lower = name:lower();
    return lower:find('%.mp3$') ~= nil or lower:find('%.wav$') ~= nil;
end

local function before(a, b)
    return a:lower() < b:lower();
end

-- The .mp3 and .wav files in `folder` in alphabetical order in any case, leaving out the ones `taken`
-- names in lower case. A folder that isn't there has none.
local function sounds_in(folder, taken)
    local found = {};
    if (not ashita.fs.exists(folder)) then
        return found;
    end
    for _, name in ipairs(ashita.fs.get_directory(folder, '.*', false) or {}) do
        if (is_sound(name) and not taken[name:lower()]) then
            found[#found + 1] = name;
        end
    end
    table.sort(found, before);
    return found;
end

--[[
    Looks in both folders again. The settings window opening, its Refresh button and the soundfile
    command call this, never each frame. The sounds that come with cadence go first, then yours. One of
    yours with the same name as one of cadence's is left out, since cadence's plays.
]]
function sound.refresh()
    sound.make_folder();
    local taken = {};
    files = sounds_in(sound.BUILT_IN, taken);
    for _, name in ipairs(files) do
        taken[name:lower()] = true;
    end
    for _, name in ipairs(sounds_in(sound.FOLDER, taken)) do
        files[#files + 1] = name;
    end
end

-- The sounds from the last look. cadence's come first, then yours.
function sound.files()
    return files;
end

-- The file from the last look that `word` names, in any case, with or without .mp3 or .wav. Nil if none.
function sound.find(word)
    local wanted = word:lower();
    for _, name in ipairs(files) do
        local lower = name:lower();
        if (lower == wanted or lower:gsub('%.%w+$', '') == wanted) then
            return name;
        end
    end
    return nil;
end

-- `name` won't open or play. Whatever is open closes, and the words for the settings window are made now.
local function give_up(name)
    sound.close();
    failed = name;
    problem = ('%s won\'t play. Try another file.'):format(name);
    return false;
end

-- Where `name` is. One that comes with cadence wins over one of yours with the same name. A name in
-- neither folder gets your folder, so the open fails.
local function path_of(name)
    if (ashita.fs.exists(sound.BUILT_IN .. name)) then
        return sound.BUILT_IN .. name;
    end
    return sound.FOLDER .. name;
end

local function open(name)
    -- Closing first also clears a file cadence left open before a reload, like after an error. With
    -- nothing open it fails, and that's fine.
    mci(CLOSE);
    opened, level = nil, nil;
    if (not mci(OPEN:format(path_of(name)))) then
        return give_up(name);
    end
    opened, failed, problem = name, nil, nil;
    return true;
end

--[[
    Opens `name`, unless it's open already. A file that wouldn't open is only tried again with `again`,
    for when you pick it, turn the sound on or press Play. No name closes the open file. True when
    `name` is open or there's no name.
]]
function sound.use(name, again)
    if (name == '') then
        sound.close();
        failed, problem = nil, nil;
        return true;
    end
    if (name == opened) then
        return true;
    end
    if (name == failed and not again) then
        return false;
    end
    return open(name);
end

-- Sets the volume, from 0 to 1000, and plays from the start. The volume is only sent when it changes.
local function start(wanted)
    if (wanted ~= level) then
        if (not mci(VOLUME:format(wanted))) then
            return false;
        end
        level = wanted;
    end
    return mci(PLAY);
end

--[[
    Plays the open file from the start, at `volume` from 0 to 100. True when it played. MCI only lets
    the thread that opened a file use it, and a change of sound device can lose it too. So when a play
    fails, the file opens again and gets one more try before cadence gives up on it.
]]
function sound.play(volume)
    if (opened == nil) then
        return false;
    end
    local name = opened;
    local wanted = math.floor(volume * 10 + 0.5);
    if (start(wanted)) then
        return true;
    end
    return open(name) and (start(wanted) or give_up(name));
end

-- Closes the open file. If the close fails, the next open clears it first anyway.
function sound.close()
    if (opened ~= nil) then
        mci(CLOSE);
        opened, level = nil, nil;
    end
end

-- True when `name` is the open file.
function sound.is_open(name)
    return opened == name;
end

-- What the settings window says about `name` when it won't play, or nil.
function sound.problem(name)
    if (name == failed) then
        return problem;
    end
    return nil;
end

return sound;
