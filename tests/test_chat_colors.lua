-- cadence's chat colors. The palette, every line printed in your colors and the very same line as
-- Ashita's at the defaults, the colors each preset sets, Undo and Reset look, the settings check, the
-- CHAT controls under Window in Appearance with its lists and Print a sample, the chatcolor command and what it
-- says back, and /cadence help chatcolors.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
-- A shared layout left over from another test would turn One layout for all characters on.
local SHARED = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\shared_layout.json';
os.remove(SHARED);

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.watch_settings();
MOCK.fire('load');
local s = MOCK.settings.current;
local imgui = require('imgui');
local chat_colors = require('ui.chat_colors');
local defaults = require('ui.defaults');
local presets = require('ui.presets');
local theme = require('ui.theme');
local json = require('json');
MOCK.now = 100;

-- A chat line with its codes shown, so a FAIL line can be read.
local function shown(line)
    return (tostring(line):gsub('[\30\31]', '^'):gsub('[%c\128-\255]', function (c) return ('<%d>'):format(c:byte()); end));
end

-- Runs a command. Returns what it printed, without the [cadence] tag, and the same lines codes and all.
-- Each list is counted on its own.
local function said(command)
    local plain, raw = #MOCK.printed, #MOCK.printed_raw;
    MOCK.fire('command', { command = command });
    local lines, raws = {}, {};
    for i = plain + 1, #MOCK.printed do table.insert(lines, (MOCK.printed[i]:gsub('^%[cadence%] ', ''))); end
    for i = raw + 1, #MOCK.printed_raw do table.insert(raws, MOCK.printed_raw[i]); end
    return lines, raws;
end
local function answers(command, expected)
    local saves = MOCK.saved;
    local lines = said(command);
    return #lines == 1 and lines[1] == expected and MOCK.saved == saves + 1,
        table.concat(lines, ' / ') .. ' saves ' .. (MOCK.saved - saves);
end
local function refuses(command, expected)
    local saves, state = MOCK.saved, json.encode(s);
    local lines = said(command);
    return #lines == 1 and lines[1] == expected and MOCK.saved == saves and json.encode(s) == state,
        table.concat(lines, ' / ') .. ' saves ' .. (MOCK.saved - saves);
end

-- The line Ashita's chat.header and chat.message make, with the colors put in.
-- Source: Ashita's libs\chat.lua, chat.header is '\30\81[\30\06%s\30\81]\30\01 ' and chat.message
-- wraps the text in \30\106 and \30\01.
local function line(brackets, word, replies, text)
    return '\30' .. string.char(brackets) .. '[\30' .. string.char(word) .. 'cadence\30' .. string.char(brackets)
        .. ']\30\1 \30' .. string.char(replies) .. text .. '\30\1';
end

-- The palette ------------------------------------------------------------------------------------------------
-- Typed out, so a color moved, dropped, renamed or given the wrong swatch shows up.
local PALETTE = 'Cream 106 ffefc2, White 1 ffffff, Lawn green 2 7cfc00, Slate blue 3 7b68ee, Magenta 5 ff00ff, '
    .. 'Cyan 6 00ffff, Moccasin 7 ffe4b5, Coral 8 ff7f50, Dim grey 65 696969, Grey 67 808080, Salmon 68 fa8072, '
    .. 'Yellow 69 ffff00, Royal blue 71 4169e1, Dark magenta 72 8b008b, Violet 73 ee82ee, Tomato 76 ff6347, '
    .. 'Misty rose 77 ffe4e1, Pale goldenrod 78 eee8aa, Lime 79 00ff00, Pale green 80 98fb98, Dark orchid 81 9932cc, '
    .. 'Aqua 82 00ffff, Spring green 83 00ff7f, Dark salmon 85 e9967a, Med. spring green 88 00fa9a, '
    .. 'Medium purple 89 9370db, Azure 90 f0ffff, Light cyan 92 e0ffff, Light goldenrod 96 fafad2, '
    .. 'Light blue 102 add8e6, Warning yellow 104 ffff80, Plum 105 dda0dd';
local listed = {};
for _, entry in ipairs(chat_colors.PALETTE) do
    table.insert(listed, ('%s %d %s'):format(entry.name, entry.code, entry.swatch));
end
check('the palette is checkmate\'s chat colors in order, each with its swatch', table.concat(listed, ', ') == PALETTE,
    table.concat(listed, ', '));
check('it leaves out 0, which ends the text, and 10 and 13, which break the line', not chat_colors.in_palette(0)
    and not chat_colors.in_palette(10) and not chat_colors.in_palette(13) and chat_colors.in_palette(105));
local parts = {};
for _, part in ipairs(chat_colors.PARTS) do table.insert(parts, part.key .. ' ' .. part.name); end
check('the parts are the tag\'s brackets, its word and the replies', table.concat(parts, ', ')
    == 'tag_brackets Tag brackets, tag_word Tag word, replies Replies', table.concat(parts, ', '));

-- The defaults print the same line as Ashita -------------------------------------------------------------------
local fresh = defaults.make().chat;
check('the defaults are Ashita\'s 81, 6 and 106', fresh.tag_brackets == 81 and fresh.tag_word == 6
    and fresh.replies == 106);
local lines, raws = said('/cadence lock');
check('at the defaults a line is the very same as Ashita\'s chat.header and chat.message make',
    raws[1] == line(81, 6, 106, 'The timers are locked in place.'), shown(raws[1]));
check('and reads as plain words with the colors taken out', lines[1] == 'The timers are locked in place.', lines[1]);
check('a code outside the palette prints in cream', chat_colors.line({ tag_brackets = 0, tag_word = 13, replies = 10 },
    'cadence', 'x') == line(106, 106, 106, 'x') and chat_colors.entry(999).name == 'Cream');

-- Every line goes out in your colors, read when it's printed.
s.chat.tag_brackets, s.chat.tag_word, s.chat.replies = 85, 8, 7;
lines, raws = said('/cadence help');
local off = nil;
for i, raw in ipairs(raws) do
    if (raw ~= line(85, 8, 7, lines[i])) then off = shown(raw); end
end
check('every line of the help is in your colors', #raws > 10 and off == nil, off);
lines, raws = said('/cadence unlock');
check('and so is an answer', raws[1] == line(85, 8, 7, 'Hold Shift and drag a timer to move it.'), shown(raws[1]));
s.chat.tag_brackets, s.chat.tag_word, s.chat.replies = 81, 6, 106;

-- The settings check -------------------------------------------------------------------------------------------
do
    local broken = defaults.make();
    local BAD = { 0, 10, 13, 4, 107, 999, 81.5, -6, '81', true, 0 / 0, 1 / 0 };
    local kept = nil;
    for _, value in ipairs(BAD) do
        for _, part in ipairs(chat_colors.PARTS) do broken.chat[part.key] = value; end
        defaults.tidy(broken);
        for _, part in ipairs(chat_colors.PARTS) do
            if (broken.chat[part.key] ~= fresh[part.key]) then kept = tostring(value) .. ' in ' .. part.key; end
        end
    end
    check('a code that isn\'t a chat color gets the default', kept == nil, kept);
    broken.chat.tag_brackets, broken.chat.tag_word, broken.chat.replies = 105, 1, 88;
    defaults.tidy(broken);
    check('a chat color stays', broken.chat.tag_brackets == 105 and broken.chat.tag_word == 1 and broken.chat.replies == 88);
    broken.chat.replies = nil;
    defaults.tidy(broken);
    check('a missing one gets the default', broken.chat.replies == 106 and broken.chat.tag_brackets == 105);
end

-- Presets --------------------------------------------------------------------------------------------------------
-- checkmate's skins, by the same names. Minimal is all cream and High contrast white with a yellow word.
local PRESET_CHAT = {
    ['Phoenix'] = { 81, 6, 106 }, ['Classic FFXI'] = { 81, 6, 106 }, ['Minimal'] = { 106, 106, 106 },
    ['High contrast'] = { 1, 69, 1 }, ['Ember'] = { 85, 8, 7 }, ['Mint'] = { 102, 88, 90 },
    ['Lavender'] = { 102, 105, 90 }, ['Colorblind safe'] = { 81, 6, 106 },
};
local function chat_is(want)
    return s.chat.tag_brackets == want[1] and s.chat.tag_word == want[2] and s.chat.replies == want[3];
end
local function chat_now() return ('%s %s %s'):format(s.chat.tag_brackets, s.chat.tag_word, s.chat.replies); end
presets.apply(s, 'Ember');
for _, name in ipairs(presets.NAMES) do
    presets.apply(s, name);
    check(name .. ' sets its chat colors', chat_is(PRESET_CHAT[name]), chat_now());
    check(name .. ' is still the look you have', presets.current(s) == name, presets.current(s));
end
s.style.window_matches_look = false;
presets.apply(s, 'High contrast');
check('a preset sets them with Window matches the look off too, since they aren\'t the window', chat_is({ 1, 69, 1 }),
    chat_now());
s.style.window_matches_look = true;

presets.apply(s, 'Phoenix');
presets.forget_undo();
check('a chat color you change makes the Preset list say Custom', answers('/cadence chatcolor replies white',
    'The replies chat color is set to White.') and presets.current(s) == nil, presets.current(s));
check('picking the preset again puts its chat colors back', answers('/cadence preset phoenix',
    'The Phoenix preset is on. /cadence undo takes it back.') and chat_is({ 81, 6, 106 }), chat_now());
MOCK.fire('command', { command = '/cadence undo' });
check('and Undo brings your color back', s.chat.replies == 1, chat_now());
s.chat.tag_word = 69;
presets.reset(s);
check('Reset look puts them back to default', chat_is({ 81, 6, 106 }), chat_now());
presets.undo(s);
check('and Undo takes that back too', s.chat.tag_word == 69 and s.chat.replies == 1, chat_now());
presets.apply(s, 'Phoenix');
presets.forget_undo();

-- The CHAT controls under Window in Appearance -----------------------------------------------------------------------
local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n or 1 do MOCK.frame(1 / 60); end
    MOCK.record_imgui = false;
end
local function find(name, label, from)
    for i = from or 1, #MOCK.imgui_calls do
        local c = MOCK.imgui_calls[i];
        if (c[1] == name and (label == nil or c[2] == label or c[3] == label)) then return i; end
    end
    return nil;
end
MOCK.fire('command', { command = '/cadence' });

-- The section from its heading to the next heading, as one line per call that places something.
local function chat_section()
    local calls = MOCK.imgui_calls;
    local at = find('TextColored', 'CHAT');
    local steps = {};
    for i = (at or #calls) + 1, #calls do
        local c = calls[i];
        if (c[1] == 'EndTabItem' or (c[1] == 'TextColored' and c[3] == 'TIMING DETAILS')) then break; end
        if (c[1] == 'ColorButton') then table.insert(steps, 'swatch ' .. c[2]);
        elseif (c[1] == 'SameLine') then table.insert(steps, 'same' .. (c[2] and (' ' .. c[2]) or '')
            .. (c[3] and (' ' .. c[3]) or ''));
        elseif (c[1] == 'SetNextItemWidth') then table.insert(steps, 'width ' .. c[2]);
        elseif (c[1] == 'BeginCombo') then table.insert(steps, c[2] .. '=' .. c[3]);
        elseif (c[1] == 'Button') then table.insert(steps, 'button ' .. c[2]);
        elseif (c[1] == 'TextDisabled') then table.insert(steps, c[2]);
        end
    end
    return at, table.concat(steps, ' | ');
end

frames(1);
local heading_at, steps = chat_section();
local spacing_at = find('SliderInt', 'Spacing##window');
local table_end = spacing_at and find('EndTable', nil, spacing_at);
check('CHAT comes on the Window section after the FONT and SHAPE columns', heading_at ~= nil and table_end ~= nil
    and table_end < heading_at, tostring(heading_at));
-- The mock's column is 792 wide, so the second column starts (792 + 24) / 2 in.
local TWO = 'swatch ##chat_tag_brackets | same 0 4 | width 190 | Tag brackets=Dark orchid | same | (?) | same 408 | '
    .. 'swatch ##chat_tag_word | same 0 4 | width 190 | Tag word=Cyan | same | (?) | '
    .. 'swatch ##chat_replies | same 0 4 | width 190 | Replies=Cream | same | (?) | same 408 | '
    .. 'button Print a sample | same | (?)';
check('each is a swatch, then its list as wide as the other controls with the color\'s name, then its (?), two to a '
    .. 'line with Print a sample last', steps == TWO, steps);
MOCK.window_size = { 600, 680 };
frames(1);
MOCK.window_size = nil;
_, steps = chat_section();
check('in one column each gets a line of its own', steps == TWO:gsub(' | same 408', ''), steps);
s.window_style.font_size = 24;
frames(1);
s.window_style.font_size = 18;
_, steps = chat_section();
check('at 24 px the lists grow with the other controls', select(2, steps:gsub('width 253', '')) == 3, steps);
-- A font that draws the names wider. Med. spring green is the longest at 170, so a list takes 212 with its
-- padding and its arrow. Two to a line, Tag brackets has only 192 left in its half next to its name and (?).
-- The narrow window above was saved as its size, so it goes back to two columns first.
s.window.width, s.window.height = 920, 680;
MOCK.measure = function (words) return #words * 10; end
frames(1);
_, steps = chat_section();
check('each list fits the longest color name, but no more than its half of the line has',
    steps:find('width 192 | Tag brackets=', 1, true) and steps:find('width 212 | Tag word=', 1, true)
    and steps:find('width 212 | Replies=', 1, true), steps);
MOCK.window_size = { 600, 680 };
frames(1);
MOCK.window_size = nil;
MOCK.measure = nil;
_, steps = chat_section();
check('in one column each has the whole line', select(2, steps:gsub('width 212', '')) == 3, steps);

-- Each swatch with the table, flags and size it was given.
local swatches = {};
rawset(imgui, 'ColorButton', function (id, color, flags, size)
    table.insert(swatches, { id = id, color = color, flags = flags, size = size });
end);
local open_list = nil;
local selectables = {};
rawset(imgui, 'BeginCombo', function (label) return label == open_list; end);
rawset(imgui, 'Selectable', function (label, picked)
    table.insert(selectables, { label = label, picked = picked });
    return false;
end);
-- The row each SetItemDefaultFocus came right after. ImGui scrolls an open list to that row.
local focused = {};
rawset(imgui, 'SetItemDefaultFocus', function ()
    table.insert(focused, selectables[#selectables] and selectables[#selectables].label or 'nothing');
end);
s.chat.tag_word = 88;
frames(1);
local FLAGS = bit.bor(ImGuiColorEditFlags_NoTooltip, ImGuiColorEditFlags_NoDragDrop);
local function same_color(c, hex)
    local want = theme.hex(hex);
    for i = 1, 4 do if (math.abs(c[i] - want[i]) > 1e-9) then return false; end end
    return true;
end
local front = {};
for _, sw in ipairs(swatches) do front[sw.id] = sw; end
local a, b, c = front['##chat_tag_brackets'], front['##chat_tag_word'], front['##chat_replies'];
check('the swatch in front shows the color you have', a and b and c and same_color(a.color, '9932cc')
    and same_color(b.color, '00fa9a') and same_color(c.color, 'ffefc2'));
check('it has no tip and can\'t be dragged', a.flags == FLAGS and b.flags == FLAGS and c.flags == FLAGS,
    tostring(a.flags));
check('and it\'s as tall as its list, which ImGui picks', a.size[1] == 0 and a.size[2] == 0 and rawequal(a.size, c.size));

-- The open list. Each name has its swatch in front, as tall as a line of text, and yours is marked.
swatches, selectables, focused, open_list = {}, {}, {}, 'Tag word';
frames(1);
local names, marked, odd = {}, {}, nil;
for _, row in ipairs(selectables) do
    table.insert(names, row.label);
    if (row.picked) then table.insert(marked, row.label); end
end
local in_list = {};
for _, sw in ipairs(swatches) do if (sw.id:find('^##chat%d')) then table.insert(in_list, sw); end end
for i, entry in ipairs(chat_colors.PALETTE) do
    local sw = in_list[i];
    if (sw == nil or sw.id ~= '##chat' .. entry.code or not same_color(sw.color, entry.swatch) or sw.flags ~= FLAGS
        or sw.size[1] ~= 18 or sw.size[2] ~= 18) then
        odd = odd or entry.name;
    end
end
local every = {};
for _, entry in ipairs(chat_colors.PALETTE) do table.insert(every, entry.name); end
check('the list has every chat color in order', table.concat(names, ', ') == table.concat(every, ', '),
    table.concat(names, ', '));
check('with yours marked', table.concat(marked, ',') == 'Med. spring green', table.concat(marked, ','));
check('and it opens scrolled to yours, 25th of the 32', table.concat(focused, ',') == 'Med. spring green',
    table.concat(focused, ','));
check('each with its own swatch, as tall as a line of text', odd == nil and #in_list == #chat_colors.PALETTE, odd);
s.window_style.font_size = 24;
swatches = {};
frames(1);
s.window_style.font_size = 18;
local tall = nil;
for _, sw in ipairs(swatches) do if (sw.id == '##chat2') then tall = sw.size[1] .. 'x' .. sw.size[2]; end end
check('which grows with the font', tall == '24x24', tall);

-- Picking one sets it and saves.
local saves = MOCK.saved;
rawset(imgui, 'Selectable', function (label) return label == 'Lime'; end);
frames(1);
check('picking a color sets it and saves', s.chat.tag_word == 79 and MOCK.saved == saves + 1,
    s.chat.tag_word .. ' ' .. (MOCK.saved - saves));
check('which makes the Preset list say Custom', presets.current(s) == nil);
rawset(imgui, 'Selectable', nil);
rawset(imgui, 'BeginCombo', nil);
rawset(imgui, 'ColorButton', nil);
rawset(imgui, 'SetItemDefaultFocus', nil);
presets.apply(s, 'Phoenix');

-- Print a sample prints one line in your colors and changes nothing.
s.chat.replies = 2;
saves = MOCK.saved;
local before, raw_before = #MOCK.printed, #MOCK.printed_raw;
rawset(imgui, 'Button', function (label) return label == 'Print a sample'; end);
frames(1);
rawset(imgui, 'Button', nil);
frames(2);
local printed = {};
for i = before + 1, #MOCK.printed do table.insert(printed, MOCK.printed[i]); end
check('Print a sample prints one line, once', #printed == 1
    and printed[1] == '[cadence] This is how cadence\'s answers look in your chat colors.', table.concat(printed, ' / '));
check('in your chat colors', MOCK.printed_raw[raw_before + 1]
    == line(81, 6, 2, 'This is how cadence\'s answers look in your chat colors.'), shown(MOCK.printed_raw[raw_before + 1]));
check('and saves nothing', MOCK.saved == saves, MOCK.saved - saves);
s.chat.replies = 106;

-- Each (?) says what it colors.
rawset(imgui, 'IsItemHovered', function () return true; end);
frames(1);
rawset(imgui, 'IsItemHovered', nil);
local tips, control, inside = {}, nil, false;
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'BeginCombo' or call[1] == 'Button' or call[1] == 'SmallButton') then control = call[2]; end
    if (call[1] == 'BeginTooltip') then inside = true; end
    if (call[1] == 'EndTooltip') then inside = false; end
    if (inside and call[1] == 'TextUnformatted' and control ~= nil and tips[control] == nil) then tips[control] = call[2]; end
end
local function tip_says(label, words)
    local tip = tips[label] or '';
    return tip:find(words, 1, true) ~= nil and #tip <= 200 and not tip:find(';', 1, true), tip;
end
check('Tag brackets names the tag and says a preset sets them', tip_says('Tag brackets', 'brackets of the [cadence] tag')
    and tip_says('Tag brackets', 'A preset sets all three chat colors'), tips['Tag brackets']);
check('Tag word names the word', tip_says('Tag word', 'The word cadence inside the tag'), tips['Tag word']);
check('Replies names the answers', tip_says('Replies', 'answers to your commands'), tips['Replies']);
check('Print a sample says the swatches only come close', tip_says('Print a sample', 'only come close'),
    tips['Print a sample']);
check('the Preset tip says a preset sets the chat colors', tip_says('Preset', 'Sets the timer and chat colors'),
    tips['Preset']);
check('and the Reset look tip that it puts them back', tip_says('Reset look', 'timer and chat colors'),
    tips['Reset look']);
MOCK.fire('command', { command = '/cadence' });

-- The command ------------------------------------------------------------------------------------------------
local CASES = {
    { 'tag_brackets lawn green',     'tag_brackets', 2,   'Lawn green' },
    { 'TAG_WORD Royal Blue',         'tag_word',     71,  'Royal blue' },
    { 'replies 105',                 'replies',      105, 'Plum' },
    { 'replies medspringgreen',      'replies',      88,  'Med. spring green' },
    { 'replies Med. Spring Green',   'replies',      88,  'Med. spring green' },
    { 'replies "Light cyan"',        'replies',      92,  'Light cyan' },
    { 'tag_word cyan',               'tag_word',     6,   'Cyan' },
};
for _, case in ipairs(CASES) do
    local ok, detail = answers('/cadence chatcolor ' .. case[1], ('The %s chat color is set to %s.'):format(case[2], case[4]));
    check('chatcolor ' .. case[1], ok and s.chat[case[2]] == case[3], detail);
end
lines, raws = said('/cadence chatcolor tag_brackets 1');
check('the answer is already in the new color', raws[1] == line(1, 6, 92, 'The tag_brackets chat color is set to White.'),
    shown(raws[1]));
local USAGE = 'Type /cadence chatcolor <what> <color>. /cadence help chatcolors lists the choices.';
for _, command in ipairs({ '/cadence chatcolor', '/cadence chatcolor replies' }) do
    local ok, detail = refuses(command, USAGE);
    check('"' .. command .. '" gets the usage line', ok, detail);
end
local ok, detail = refuses('/cadence chatcolor brackets cyan', 'There\'s no chat color called "brackets". The chat '
    .. 'colors are tag_brackets, tag_word and replies.');
check('a part that isn\'t there names the parts', ok, detail);
for _, word in ipairs({ 'puce', '0', '10', '13', '4', '107', 'lawn' }) do
    ok, detail = refuses('/cadence chatcolor replies ' .. word, ('"%s" isn\'t a chat color. /cadence help chatcolors '
        .. 'lists them.'):format(word));
    check('"' .. word .. '" isn\'t a chat color', ok, detail);
end
presets.apply(s, 'Phoenix');

-- With one layout for all characters on, the shared copy holds them, and lines go out in its colors.
local layout_ok, layout_err = pcall(function ()
    MOCK.fire('command', { command = '/cadence onelayout on' });
    lines, raws = said('/cadence chatcolor replies lime');
    check('with one layout on, the shared copy takes the color', MOCK.in_use.chat.replies == 79 and s.chat.replies == 106,
        MOCK.in_use.chat.replies .. ' ' .. s.chat.replies);
    check('and lines go out in it', raws[1] == line(81, 6, 79, 'The replies chat color is set to Lime.'), shown(raws[1]));
    MOCK.fire('command', { command = '/cadence onelayout off' });
end);
os.remove(SHARED);
check('the shared layout part ran', layout_ok, layout_err);
presets.apply(s, 'Phoenix');

-- Help -------------------------------------------------------------------------------------------------------
lines = said('/cadence help chatcolors');
local HELP = {
    '/cadence chatcolor <what> <color>  sets one of cadence\'s chat colors, the same as the CHAT controls under '
        .. 'Window in Appearance. <what> is tag_brackets, tag_word or replies.',
    '<color> is one of these names or its number. A name works with or without its spaces, like lawngreen.',
    'Cream 106, White 1, Lawn green 2, Slate blue 3, Magenta 5, Cyan 6, Moccasin 7, Coral 8',
    'Dim grey 65, Grey 67, Salmon 68, Yellow 69, Royal blue 71, Dark magenta 72, Violet 73, Tomato 76',
    'Misty rose 77, Pale goldenrod 78, Lime 79, Pale green 80, Dark orchid 81, Aqua 82, Spring green 83, Dark salmon 85',
    'Med. spring green 88, Medium purple 89, Azure 90, Light cyan 92, Light goldenrod 96, Light blue 102, '
        .. 'Warning yellow 104, Plum 105',
};
check('help chatcolors lists the parts and every color with its number', table.concat(lines, '\n')
    == table.concat(HELP, '\n'), table.concat(lines, ' / '));
-- A color past the last full line of 8 still gets a line.
table.insert(chat_colors.PALETTE, { code = 106, name = 'One more', swatch = 'ffefc2' });
lines = said('/cadence help chatcolors');
table.remove(chat_colors.PALETTE);
check('a short last line is listed too', #lines == 7 and lines[7] == 'One more 106', lines[7]);
lines = said('/cadence help reset');
check('help reset says Reset look puts the chat colors back', (lines[2] or ''):find('the chat colors', 1, true) ~= nil,
    lines[2]);

-- What chat says reads like everything else in cadence.
local odd_line = nil;
for _, said_line in ipairs(MOCK.printed) do
    if (said_line:find(';', 1, true) or said_line:find('[\128-\255]')) then odd_line = said_line; end
end
check('no semicolons or odd characters in anything said', odd_line == nil, odd_line);
local errors = nil;
for _, said_line in ipairs(MOCK.printed) do if (said_line:find('Drawing stopped', 1, true)) then errors = said_line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
