--[[
    cadence's colors in the chat log. Each line cadence prints starts with the [cadence] tag, then its
    answer. You pick the color of the tag's brackets, of the word cadence inside them and of the answer,
    from the game's own chat colors. The defaults are the ones Ashita's chat.header and chat.message
    use.
]]

local chat_colors = {};

--[[
    The chat colors you can pick, from Ashita's color table 1, named as in libs\chat.lua. checkmate
    offers the same ones. Codes 0, 10 and 13 are left out. 0 ends the text and 10 and 13 break the
    line. chat.lua has no name for 102, 104 and 106. 104 is its warning color and 106 its message
    color. `swatch` is the color the settings window shows for it, the CSS color chat.lua names the
    code after. A light blue, a pale yellow and a cream stand in for those three. The game's own shades
    differ, and Print a sample shows the real ones.
]]
chat_colors.PALETTE = {
    { code = 106, name = 'Cream',             swatch = 'ffefc2' },
    { code = 1,   name = 'White',             swatch = 'ffffff' },
    { code = 2,   name = 'Lawn green',        swatch = '7cfc00' },
    { code = 3,   name = 'Slate blue',        swatch = '7b68ee' },
    { code = 5,   name = 'Magenta',           swatch = 'ff00ff' },
    { code = 6,   name = 'Cyan',              swatch = '00ffff' },
    { code = 7,   name = 'Moccasin',          swatch = 'ffe4b5' },
    { code = 8,   name = 'Coral',             swatch = 'ff7f50' },
    { code = 65,  name = 'Dim grey',          swatch = '696969' },
    { code = 67,  name = 'Grey',              swatch = '808080' },
    { code = 68,  name = 'Salmon',            swatch = 'fa8072' },
    { code = 69,  name = 'Yellow',            swatch = 'ffff00' },
    { code = 71,  name = 'Royal blue',        swatch = '4169e1' },
    { code = 72,  name = 'Dark magenta',      swatch = '8b008b' },
    { code = 73,  name = 'Violet',            swatch = 'ee82ee' },
    { code = 76,  name = 'Tomato',            swatch = 'ff6347' },
    { code = 77,  name = 'Misty rose',        swatch = 'ffe4e1' },
    { code = 78,  name = 'Pale goldenrod',    swatch = 'eee8aa' },
    { code = 79,  name = 'Lime',              swatch = '00ff00' },
    { code = 80,  name = 'Pale green',        swatch = '98fb98' },
    { code = 81,  name = 'Dark orchid',       swatch = '9932cc' },
    { code = 82,  name = 'Aqua',              swatch = '00ffff' },
    { code = 83,  name = 'Spring green',      swatch = '00ff7f' },
    { code = 85,  name = 'Dark salmon',       swatch = 'e9967a' },
    { code = 88,  name = 'Med. spring green', swatch = '00fa9a' },
    { code = 89,  name = 'Medium purple',     swatch = '9370db' },
    { code = 90,  name = 'Azure',             swatch = 'f0ffff' },
    { code = 92,  name = 'Light cyan',        swatch = 'e0ffff' },
    { code = 96,  name = 'Light goldenrod',   swatch = 'fafad2' },
    { code = 102, name = 'Light blue',        swatch = 'add8e6' },
    { code = 104, name = 'Warning yellow',    swatch = 'ffff80' },
    { code = 105, name = 'Plum',              swatch = 'dda0dd' },
};

-- The parts of a line you can color, in the order the Window tab shows them. `key` is the part's name
-- in your chat settings and the word /cadence chatcolor takes. `name` is what the Window tab calls it.
chat_colors.PARTS = {
    { key = 'tag_brackets', name = 'Tag brackets' },
    { key = 'tag_word',     name = 'Tag word' },
    { key = 'replies',      name = 'Replies' },
};

local BY_CODE = {};
for _, entry in ipairs(chat_colors.PALETTE) do
    BY_CODE[entry.code] = entry;
end

-- Anything outside the palette prints in cream.
local FALLBACK = BY_CODE[106];

-- Lowercase letters and digits only, so "Lawn green", "lawngreen" and "LAWN-GREEN" match.
local function squash(text)
    return (text:lower():gsub('[^%w]', ''));
end

function chat_colors.in_palette(code)
    return BY_CODE[code] ~= nil;
end

-- The palette entry for a code. A code outside the palette gets cream.
function chat_colors.entry(code)
    return BY_CODE[code] or FALLBACK;
end

-- The palette entry a word names, by its name with or without its spaces or by its number, or nil.
function chat_colors.find(word)
    local wanted = squash(word);
    for _, entry in ipairs(chat_colors.PALETTE) do
        if (wanted == tostring(entry.code) or wanted == squash(entry.name)) then
            return entry;
        end
    end
    return nil;
end

-- The part with this key, or nil. A command's words come in lowercase.
function chat_colors.part(key)
    for _, part in ipairs(chat_colors.PARTS) do
        if (part.key == key) then
            return part;
        end
    end
    return nil;
end

-- One chat line, "[word] text" in your chat colors. It's built the same way Ashita's chat.header and
-- chat.message build it, so at the defaults it's the very same line.
function chat_colors.line(colors, word, text)
    local brackets = chat_colors.entry(colors.tag_brackets).code;
    return ('\30%c[\30%c%s\30%c]\30\01 \30%c%s\30\01'):format(brackets, chat_colors.entry(colors.tag_word).code,
        word, brackets, chat_colors.entry(colors.replies).code, text);
end

return chat_colors;
