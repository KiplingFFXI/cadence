--[[
    The settings window's font. Ashita's own font is always there. Every other one is a file in the
    Windows fonts folder. This is checkmate's list, so the two addons offer the same fonts.

    Adding a font in the middle of a frame can crash the game. So every font in the list loads once,
    on the load event, and stays loaded until the game closes. Picking a font only switches between
    the ones that loaded. A font whose file is missing or won't load leaves the window in Ashita's font.

    The timers have a font list of their own, in hud.lua. Both lists load their files through
    load_file, so a file in both, like segoeui.ttf, loads once and they share it. The chat log's font
    belongs to the game, and no addon can change it.
]]

local imgui = require('imgui');

local window_font = {};

-- The fonts you can pick, Ashita's own first. The others come with every Windows install.
window_font.LIST = {
    { id = 'ashita',   name = 'Ashita' },
    { id = 'segoeui',  name = 'Segoe UI', file = 'segoeui.ttf' },
    { id = 'arial',    name = 'Arial',    file = 'arial.ttf' },
    { id = 'tahoma',   name = 'Tahoma',   file = 'tahoma.ttf' },
    { id = 'verdana',  name = 'Verdana',  file = 'verdana.ttf' },
    { id = 'calibri',  name = 'Calibri',  file = 'calibri.ttf' },
    { id = 'consolas', name = 'Consolas', file = 'consola.ttf' },
};

-- Font sizes in whole pixels. Ashita draws its own font at 18.
window_font.SIZE_MIN     = 12;
window_font.SIZE_MAX     = 24;
window_font.SIZE_DEFAULT = 18;

-- The Windows fonts folder.
window_font.FOLDER = ('%s\\Fonts\\'):format(os.getenv('WINDIR') or 'C:\\Windows');

-- The size a font loads at. ImGui draws it at any size from there.
local LOAD_SIZE = 18;

local BY_ID = {};
for _, entry in ipairs(window_font.LIST) do
    BY_ID[entry.id] = entry;
end

-- The ImFont for each Windows font that loaded.
local loaded = {};

-- The ImFont for each font file that loaded, by its path.
local files = {};

-- Lowercase letters and digits only, so "Segoe UI", "segoeui" and "SEGOE-UI" match.
local function squash(text)
    return (tostring(text or ''):lower():gsub('[^%w]', ''));
end

-- The font with this id or name, in any case and with or without spaces, or nil. Each id is its name
-- in lowercase with the spaces taken out.
function window_font.find(word)
    return BY_ID[squash(word)];
end

-- A known font id, or Ashita's.
function window_font.clean_id(id)
    return BY_ID[id] ~= nil and id or window_font.LIST[1].id;
end

-- Where the font's file is, or nil for Ashita's own.
function window_font.path(id)
    local entry = BY_ID[id];
    return (entry ~= nil and entry.file ~= nil) and (window_font.FOLDER .. entry.file) or nil;
end

--[[
    Adds a font file to ImGui's fonts the first time it's asked for, and hands back the same ImFont
    after that. Nil when the file is missing or won't load. Only the load event calls this.
]]
function window_font.load_file(path)
    if (files[path] == nil and ashita.fs.exists(path)) then
        local ok, face = pcall(imgui.AddFontFromFileTTF, path, LOAD_SIZE);
        files[path] = ok and face or nil;
    end
    return files[path];
end

-- Loads every Windows font in the list. Only the load event calls this.
function window_font.load_all()
    for _, entry in ipairs(window_font.LIST) do
        local path = window_font.path(entry.id);
        if (path ~= nil) then
            loaded[entry.id] = window_font.load_file(path);
        end
    end
end

-- The ImFont to draw with, or nil to draw in Ashita's own.
function window_font.face(id)
    return loaded[id];
end

-- True when a Windows font's file is missing or wouldn't load. It builds no text, so the settings
-- window can ask every frame.
function window_font.failed(id)
    local entry = BY_ID[id];
    return entry ~= nil and entry.file ~= nil and loaded[id] == nil;
end

return window_font;
