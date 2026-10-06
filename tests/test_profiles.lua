-- Profiles. Saving, loading, renaming and deleting them, what profiles.json holds, a profile with settings
-- missing or wrong, a broken file and one that can't be written. Then the Profiles tab with its list, name
-- box, buttons and messages, and the profile commands with what each one says back, and /cadence help
-- profiles.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
MOCK.fs['C:\\Windows\\Fonts\\consola.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
-- Files left over from another test would change what loads.
local FOLDER = MOCK_INSTALL_PATH .. '\\config\\addons\\';
local FILE = FOLDER .. 'cadence\\profiles.json';
local SHARED = FOLDER .. 'cadence\\shared_layout.json';
os.remove(FILE);
os.remove(SHARED);

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.watch_settings();
MOCK.fire('load');
local s = MOCK.settings.current;
local profiles = require('ui.profiles');
local presets = require('ui.presets');
local defaults = require('ui.defaults');
local theme = require('ui.theme');
local json = require('json');
local DEFAULTS = defaults.make();
MOCK.now = 100;

local function read_file(path)
    local f = io.open(path or FILE, 'r');
    if (f == nil) then return nil; end
    local text = f:read('*a');
    f:close();
    return text;
end
local function write_file(text)
    local f = assert(io.open(FILE, 'w'));
    f:write(text);
    f:close();
end
local function same(a, b)
    if (type(a) ~= 'table' or type(b) ~= 'table') then return false; end
    for i = 1, 4 do if (math.abs(a[i] - b[i]) > 0.002) then return false; end end
    return true;
end
local function names() return table.concat(profiles.names(), ','); end

-- The profiles on their own ----------------------------------------------------------------------------------
check('no file is no profiles', profiles.file_ok() and #profiles.names() == 0);

s.attack.x, s.attack.y = 333, 444;
s.style.scale = 1.5;
s.enemy.which = 'attacker';
s.resting.label_text = 'RST';
s.window_style.font, s.window_style.font_size = 'consolas', 21;
s.window_style.buttons_pressed[1] = 0.25;
s.chat.replies = 8;
s.style.window_look = 'ember';
s.window.x, s.window.width = 222, 900;
check('save', profiles.save(s, 'Solo BLM'));
local text = read_file() or '';
check('the file is written in cadence\'s own folder', text ~= '' and read_file(FOLDER .. 'checkmate\\profiles.json') == nil);
check('the file is ASCII', not text:find('[^\32-\126]'));
local saved = json.decode(text)['Solo BLM'] or {};
check('where the settings window sits and its size aren\'t in it', saved.window == nil and not text:find('"window"', 1, true));
check('every other section is', saved.attack and saved.resting and saved.enemy and saved.style and saved.window_style
    and saved.chat);
check('the timers\' spots and every other setting', saved.attack.x == 333 and saved.attack.y == 444
    and saved.style.scale == 1.5 and saved.enemy.which == 'attacker' and saved.resting.label_text == 'RST'
    and saved.chat.replies == 8 and saved.style.window_look == 'ember');
local every = true;
for _, entry in ipairs(theme.WINDOW_COLORS) do every = every and type(saved.window_style[entry.key]) == 'table'; end
check('every window color, the window\'s font and its size', every and saved.window_style.font == 'consolas'
    and saved.window_style.font_size == 21 and saved.window_style.buttons_pressed[1] == 0.25);

s.attack.x, s.attack.y = 780, 664;
s.style.scale = 1.0;
s.enemy.which = 'target_first';
s.resting.label_text = '';
s.window_style.font, s.window_style.font_size = 'ashita', 18;
s.window_style.buttons_pressed[1] = 1;
s.chat.replies = 106;
s.window.x, s.window.width = 111, 920;
presets.apply(s, 'Minimal');
check('a preset leaves something to undo', presets.can_undo());
check('load', profiles.load(s, 'Solo BLM'));
check('it puts back the timers\' spots and everything else', s.attack.x == 333 and s.attack.y == 444
    and s.style.scale == 1.5 and s.enemy.which == 'attacker' and s.resting.label_text == 'RST' and s.chat.replies == 8);
check('and the window colors and font', s.window_style.buttons_pressed[1] == 0.25 and s.window_style.font == 'consolas'
    and s.window_style.font_size == 21);
check('but leaves where the settings window sits and its size', s.window.x == 111 and s.window.width == 920);
check('Undo is cleared, so it can\'t bring back the look from before', not presets.can_undo());
check('the Preset list names the preset the profile came from', presets.current(s) == nil
    and presets.custom_name(s.style.window_look) == 'Custom (from Ember)', s.style.window_look);
check('a profile that isn\'t there doesn\'t load', profiles.load(s, 'Nope') == false and s.attack.x == 333);

-- Names.
profiles.save(s, 'apple');
profiles.save(s, 'Zebra');
check('names sort in any case', names() == 'apple,Solo BLM,Zebra', names());
check('a name keeps printable ASCII, with no spaces at either end', profiles.clean_name('  a\195\169b\tc  ') == 'abc',
    profiles.clean_name('  a\195\169b\tc  '));
check('and is cut to 32 letters, with no spaces left at the end', #profiles.clean_name(string.rep('x', 50)) == 32
    and profiles.clean_name('x' .. string.rep(' ', 40) .. 'y') == 'x');
check('## shrinks to one #, since the list would hide what comes after it',
    profiles.clean_name('Party ###2') == 'Party #2' and profiles.clean_name('A#B') == 'A#B');
check('a name with nothing in it isn\'t saved', profiles.save(s, ' \1 ') == false and names() == 'apple,Solo BLM,Zebra');
check('saving over a name replaces it', profiles.save(s, 'apple') and #profiles.names() == 3);
check('a name is found in any case', profiles.find('SOLO blm') == 'Solo BLM' and profiles.find('Nope') == nil);
-- Job links use None and (none) to mean no link.
check('None and (none) in any case can\'t be new names', profiles.save(s, 'NONE') == false
    and profiles.save(s, ' (None) ') == false and profiles.rename(s, 'apple', 'none') == false
    and profiles.rename(s, 'apple', '(NONE)') == false and names() == 'apple,Solo BLM,Zebra', names());
check('but a name with more in it is fine', profiles.save(s, 'Nonesuch') and profiles.save(s, '(none) 2')
    and profiles.delete(s, 'Nonesuch') and profiles.delete(s, '(none) 2'));

-- Rename and delete.
check('rename', profiles.rename(s, 'Solo BLM', 'Nuker') and profiles.exists('Nuker') and not profiles.exists('Solo BLM'));
check('rename refuses a name another profile has in any case', profiles.rename(s, 'Nuker', 'APPLE') == false
    and profiles.exists('Nuker'));
check('rename refuses a profile that isn\'t there', profiles.rename(s, 'Nope', 'New') == false and not profiles.exists('New'));
check('rename refuses a blank name', profiles.rename(s, 'Nuker', ' ') == false and profiles.exists('Nuker'));
check('renaming to the same name does nothing', profiles.rename(s, 'Nuker', 'Nuker') == false and profiles.exists('Nuker'));
check('a change of case alone is fine', profiles.rename(s, 'Nuker', 'NUKER') and profiles.exists('NUKER')
    and not profiles.exists('Nuker'));
check('delete', profiles.delete(s, 'NUKER') and not profiles.exists('NUKER') and names() == 'apple,Zebra', names());
check('deleting a profile that isn\'t there fails', profiles.delete(s, 'NUKER') == false);

-- Another game window saves a profile. The file is read again before each change, so it stays.
local other = json.decode(read_file());
other['From the other window'] = { chat = { replies = 1 } };
write_file(json.encode(other));
profiles.save(s, 'Mine');
check('another window\'s profile survives a save', profiles.exists('From the other window') and profiles.exists('Mine'));

-- Two names that differ only in case, from a file someone edited.
write_file('{"solo":{},"Solo":{}}');
profiles.refresh();
check('two names that differ only in case keep a steady order', names() == 'Solo,solo', names());
check('and each finds itself first', profiles.find('solo') == 'solo' and profiles.find('Solo') == 'Solo');
write_file('{"none":{}}');
profiles.refresh();
check('a profile called none that someone put in the file can still be saved over', profiles.save(s, 'none')
    and json.decode(read_file()).none.chat ~= nil);
write_file('{"Good":{},"Junk":5,"More junk":"x"}');
profiles.refresh();
check('an entry that isn\'t a profile is skipped', names() == 'Good' and profiles.file_ok(), names());

-- A profile with only a few settings, and one with wrong ones.
write_file('{"Partial":{"attack":{"x":50,"width":300},"style":{"value_color":[0.5,0.25,0],'
    .. '"detail_color":[0.5,"x",0.25,1],"label_color":"red"}},'
    .. '"Bad":{"attack":"nope","style":{"scale":99,"window_look":"purple","panel":"yes"},'
    .. '"window_style":{"font":"comic","font_size":99,"text":[1,0,0,1]},"chat":{"replies":13},"window":{"x":5}}}');
s.window.x = 111;
check('load a profile with only a few settings', profiles.load(s, 'Partial'));
check('what it has is loaded', s.attack.x == 50 and s.attack.width == 300, s.attack.x);
check('anything it\'s missing comes from the defaults', s.attack.y == DEFAULTS.attack.y and s.style.scale == 1
    and s.enemy.which == 'target_first' and s.resting.label_text == '' and s.chat.replies == 106
    and s.window_style.font == 'ashita' and same(s.window_style.buttons_pressed, DEFAULTS.window_style.buttons_pressed));
check('a color missing a part keeps the parts it has', s.style.value_color[1] == 0.5 and s.style.value_color[2] == 0.25
    and s.style.value_color[3] == 0 and s.style.value_color[4] == DEFAULTS.style.value_color[4]);
check('and so does one with a part that isn\'t a number', s.style.detail_color[1] == 0.5
    and s.style.detail_color[2] == DEFAULTS.style.detail_color[2] and s.style.detail_color[3] == 0.25);
check('a color that isn\'t a list of numbers gets its default', same(s.style.label_color, DEFAULTS.style.label_color));
check('load a profile with wrong settings', profiles.load(s, 'Bad'));
check('a wrong type gets its default', s.attack.x == DEFAULTS.attack.x and s.attack.width == DEFAULTS.attack.width
    and s.style.panel == true);
check('then the settings check runs', s.style.scale == 2.5 and s.style.window_look == 'phoenix'
    and s.window_style.font == 'ashita' and s.window_style.font_size == 24 and s.chat.replies == 106,
    ('%s %s %s %s %s'):format(s.style.scale, s.style.window_look, s.window_style.font, s.window_style.font_size,
        s.chat.replies));
check('a good window color in it is kept', s.window_style.text[1] == 1 and s.window_style.text[2] == 0);
check('a window section in the file is never loaded', s.window.x == 111);

-- A broken file is never written over.
write_file('{broken');
profiles.refresh();
check('a broken file is noticed', profiles.file_ok() == false);
check('and the problem says where it is', profiles.problem() == 'profiles.json can\'t be read, so profiles won\'t work '
    .. 'until you fix or remove it. It\'s in config\\addons\\cadence in your Ashita folder.', profiles.problem());
check('nothing is saved over it', profiles.save(s, 'X') == false and not profiles.exists('X') and read_file() == '{broken');
check('nothing loads from it', profiles.load(s, 'Partial') == false);
check('and nothing is renamed or deleted', profiles.rename(s, 'Partial', 'Y') == false
    and profiles.delete(s, 'Partial') == false and read_file() == '{broken');
os.remove(FILE);
profiles.refresh();
check('no file again is no profiles', profiles.file_ok() and #profiles.names() == 0);

-- A file that can't be written leaves every profile as it was.
profiles.save(s, 'Keep');
local real_open = io.open;
io.open = function (path, mode)
    if (path == FILE and mode == 'w') then return nil; end
    return real_open(path, mode);
end
check('a save that can\'t be written fails', profiles.save(s, 'New') == false and not profiles.exists('New'));
check('and says so', profiles.problem() == 'Couldn\'t write profiles.json.', profiles.problem());
check('so does a rename, and the old name stays', profiles.rename(s, 'Keep', 'Moved') == false and profiles.exists('Keep')
    and not profiles.exists('Moved'));
check('and a delete', profiles.delete(s, 'Keep') == false and profiles.exists('Keep'));
io.open = real_open;
check('deleting the last one leaves a file with no profiles', profiles.delete(s, 'Keep') and #profiles.names() == 0
    and profiles.file_ok());
profiles.refresh();
check('which reads back fine', profiles.file_ok() and #profiles.names() == 0, read_file());

-- The Profiles tab -----------------------------------------------------------------------------------------------
-- The Bad profile left the window's font at 24 px.
s.window_style.font_size = 18;
local imgui = require('imgui');
MOCK.fire('command', { command = '/cadence' });
MOCK.imgui_calls = {};
MOCK.record_imgui = true;
MOCK.frame(1 / 60);
MOCK.record_imgui = false;
local tabs = {};
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'BeginTabItem') then table.insert(tabs, c[2]); end end
check('Profiles is the last tab', table.concat(tabs, ',') == 'Timers,Enemy,Look,Window,Window colors,Profiles',
    table.concat(tabs, ','));

-- What the tab draws, each as a short word, and every text with the color it's in.
local log, pick, press, typing, last_color = {}, nil, nil, nil, nil;
local function add(...) table.insert(log, { ... }); end
local FAKES = {
    BeginListBox = function (label, size) add('list', label .. ' ' .. size[1] .. 'x' .. size[2]); return true; end,
    EndListBox = function () add('end list'); end,
    Selectable = function (label, picked) add('row', label .. (picked and ' picked' or '')); return label == pick; end,
    Button = function (label) add('button', label); return label == press; end,
    BeginDisabled = function (off) add(off and 'grey' or 'live'); end,
    InputText = function (label, buffer, size)
        add('box', ('%s %d "%s"'):format(label, size, buffer[1]));
        if (typing ~= nil) then buffer[1] = typing; return true; end
        return false;
    end,
    SetNextItemWidth = function (width) add('width', width); end,
    SameLine = function () add('same'); end,
    TextDisabled = function () add('(?)'); end,
    TextColored = function (color, words) add('heading', words, color); end,
    PushStyleColor = function (_, color) last_color = color; end,
    TextUnformatted = function (words) add('text', words, last_color); end,
    EndTable = function () add('end table'); end,
};
for name, fn in pairs(FAKES) do rawset(imgui, name, fn); end
local function frame()
    log = {};
    MOCK.frame(1 / 60);
    pick, press, typing = nil, nil, nil;
end
-- The PROFILES section as one line, from its heading to the JOB LINKS heading. test_job_links.lua checks
-- that one.
local function tab()
    local words, inside = {}, false;
    for _, e in ipairs(log) do
        if (e[1] == 'heading' and e[2] == 'PROFILES') then inside = true; end
        if (inside and e[1] == 'heading' and e[2] == 'JOB LINKS') then break; end
        if (inside) then
            local word = e[1];
            if (e[2] ~= nil and e[1] ~= 'heading' and e[1] ~= 'text') then word = word .. ' ' .. e[2]; end
            if (e[1] == 'heading' or e[1] == 'text') then word = e[2]; end
            table.insert(words, word);
        end
    end
    return table.concat(words, ' | ');
end
-- The texts under the buttons, each as its words and the color it's in.
local function messages()
    local found, after = {}, false;
    for _, e in ipairs(log) do
        if (e[1] == 'button' and e[2] == 'Delete') then after = true; end
        if (after and e[1] == 'heading') then break; end
        if (after and e[1] == 'text') then table.insert(found, { words = e[2], color = e[3] }); end
    end
    return found;
end
-- Every message the tab showed, for the check on quotes at the end.
local shown_messages = {};
local function says(words, color)
    local found = messages();
    for _, message in ipairs(found) do table.insert(shown_messages, message.words); end
    return #found == 1 and found[1].words == words and same(found[1].color, color),
        (found[1] and found[1].words or 'nothing') .. ' / ' .. #found;
end
local W = s.window_style;

frame();
-- Each button for the picked profile is greyed out or not just before it.
local BUTTONS = 'button Save as new | same | (?) | same | %s | button Overwrite | same | (?) | %s | button Load | same '
    .. '| (?) | same | %s | button Rename | same | (?) | same | %s | button Delete | same | (?)';
local EMPTY = 'PROFILES | same | (?) | list ##profiles -1x130 | No profiles yet. | end list | width 190 | box Name 33 "" | '
    .. 'same | (?) | ' .. BUTTONS:gsub('%%s', 'grey');
check('PROFILES has a (?), then the list, the name box and the buttons, greyed out until you pick a profile',
    tab() == EMPTY, tab());
local empty_note = nil;
for _, e in ipairs(log) do if (e[1] == 'text' and e[2] == 'No profiles yet.') then empty_note = e[3]; end end
check('an empty list says so in the faded text color', same(empty_note, W.faded_text));
check('no message yet', #messages() == 0);
-- Verdana isn't in the mock's fonts folder, so the Window tab says so in the problem color too.
s.window_style.font = 'verdana';
frame();
s.window_style.font = 'ashita';
local font_note = nil;
for _, e in ipairs(log) do if (e[1] == 'text' and tostring(e[2]):find('^Verdana isn\'t in')) then font_note = e[3]; end end
check('the note about a font that won\'t load is in the problem color', same(font_note, W.problem_messages));
s.window_style.font_size = 24;
frame();
s.window_style.font_size = 18;
check('at 24 px the list is taller and the box wider', tab():find('list ##profiles -1x173 |', 1, true) ~= nil
    and tab():find('width 253 | box Name', 1, true) ~= nil, tab());

-- Save as new.
typing = '  ';
press = 'Save as new';
frame();
frame();
local ok, detail = says('Type a name for the new profile first.', W.problem_messages);
check('Save as new with no name says so in the problem color', ok and #profiles.names() == 0, detail);
local saves = MOCK.saved;
s.style.scale = 2.0;
typing = 'Solo BLM';
press = 'Save as new';
frame();
frame();
ok, detail = says('Saved "Solo BLM" as a new profile.', W.done_messages);
check('Save as new saves your settings in the done color', ok and profiles.exists('Solo BLM'), detail);
check('picks the new profile', tab():find('row Solo BLM picked', 1, true) ~= nil, tab());
check('and saves no settings, since none changed', MOCK.saved == saves);
check('a profile is picked, so its buttons work', tab():find(BUTTONS:gsub('%%s', 'live'), 1, true) ~= nil, tab());
typing = 'SOLO blm';
press = 'Save as new';
frame();
frame();
ok, detail = says('A profile called "Solo BLM" is already there. Pick it and use Overwrite.', W.problem_messages);
check('a name another profile has in any case is refused', ok and #profiles.names() == 1, detail);
typing = 'None';
press = 'Save as new';
frame();
frame();
ok, detail = says('Job links use "None" to mean no link, so a profile can\'t have that name.', W.problem_messages);
check('so is None, since job links use it', ok and #profiles.names() == 1, detail);

-- Picking in the list.
profiles.save(s, 'apple');
pick = 'apple';
frame();
frame();
check('the list shows every profile in order, with the one you picked', tab():find('row apple picked | row Solo BLM |', 1,
    true) ~= nil, tab());
check('and picking one puts its name in the box', tab():find('box Name 33 "apple"', 1, true) ~= nil, tab());

-- Overwrite and Load.
pick = 'Solo BLM';
frame();
s.style.scale = 1.75;
press = 'Overwrite';
frame();
frame();
ok, detail = says('The profile "Solo BLM" has your settings now.', W.done_messages);
check('Overwrite saves your settings over the profile you picked', ok
    and json.decode(read_file())['Solo BLM'].style.scale == 1.75, detail);
s.style.scale = 1;
s.attack.x = 5;
saves = MOCK.saved;
MOCK.in_use = nil;
press = 'Load';
frame();
frame();
ok, detail = says('The profile "Solo BLM" is loaded.', W.done_messages);
check('Load loads the profile you picked', ok and s.style.scale == 1.75 and s.attack.x == DEFAULTS.attack.x, detail);
check('saves your settings and redraws the timers', MOCK.saved == saves + 1 and MOCK.in_use == s);

-- Rename.
press = 'Rename';
frame();
frame();
ok, detail = says('The profile "Solo BLM" already has that name.', W.problem_messages);
check('Rename with the same name in the box says so', ok, detail);
typing = 'Apple';
frame();
press = 'Rename';
frame();
frame();
ok, detail = says('A profile called "apple" is already there.', W.problem_messages);
check('Rename to a name another profile has is refused', ok and profiles.exists('Solo BLM'), detail);
typing = '';
frame();
press = 'Rename';
frame();
frame();
ok, detail = says('Type the new name first.', W.problem_messages);
check('Rename with no name says so', ok, detail);
typing = '(none)';
frame();
press = 'Rename';
frame();
frame();
ok, detail = says('Job links use "(none)" to mean no link, so a profile can\'t have that name.', W.problem_messages);
check('Rename to (none) is refused, since job links use it', ok and profiles.exists('Solo BLM'), detail);
typing = 'Nuker';
frame();
press = 'Rename';
frame();
frame();
ok, detail = says('The profile "Solo BLM" is called "Nuker" now.', W.done_messages);
check('Rename gives the profile you picked the name in the box', ok and profiles.exists('Nuker')
    and not profiles.exists('Solo BLM'), detail);
check('and keeps it picked', tab():find('row Nuker picked', 1, true) ~= nil, tab());

-- Delete goes by the profile you picked, not the name in the box.
typing = 'apple';
frame();
press = 'Delete';
frame();
frame();
ok, detail = says('The profile "Nuker" is deleted.', W.done_messages);
check('Delete deletes the profile you picked', ok and not profiles.exists('Nuker') and profiles.exists('apple'), detail);
check('and nothing is picked after', tab():find(BUTTONS:gsub('%%s', 'grey'), 1, true) ~= nil, tab());

-- Another game window deletes the profile you picked.
pick = 'apple';
frame();
write_file('[]');
s.attack.x = 7;
press = 'Load';
frame();
frame();
ok, detail = says('The profile you picked isn\'t there anymore.', W.problem_messages);
check('a button for a profile another window deleted says so', ok and s.attack.x == 7, detail);
check('and nothing is picked after', tab():find(BUTTONS:gsub('%%s', 'grey'), 1, true) ~= nil, tab());
profiles.save(s, 'apple');
pick = 'apple';
frame();
profiles.delete(s, 'apple');
frame();
check('a picked profile that\'s gone stops being picked', tab():find(BUTTONS:gsub('%%s', 'grey'), 1, true) ~= nil, tab());

-- Opening the window reads profiles.json again and clears the message.
write_file('{"From outside":{}}');
frame();
check('the open window keeps the list it read', tab():find('row From outside', 1, true) == nil, tab());
MOCK.fire('command', { command = '/cadence' });
MOCK.fire('command', { command = '/cadence' });
frame();
check('opening it again reads the file', tab():find('row From outside', 1, true) ~= nil, tab());
check('and clears the last message', #messages() == 0, #messages());

-- A broken file.
write_file('{broken');
MOCK.fire('command', { command = '/cadence' });
MOCK.fire('command', { command = '/cadence' });
frame();
ok, detail = says(profiles.problem(), W.problem_messages);
check('a broken file gets a note under the buttons before you press anything', ok and not profiles.file_ok(), detail);
typing = 'X';
press = 'Save as new';
frame();
frame();
ok, detail = says(profiles.problem(), W.problem_messages);
check('a button says the same once, not twice', ok and read_file() == '{broken', detail);
-- ImGui can break a line right after a closing quote. A period or comma there would start a line by itself.
local stray = nil;
for _, words in ipairs(shown_messages) do
    if (words:find('"[%.,;:!?]')) then stray = stray or words; end
end
check('no message has a period or comma right after a quoted name', #shown_messages >= 10 and stray == nil,
    stray or #shown_messages);
os.remove(FILE);

-- One layout for all characters. Loading writes into the shared layout, never your own settings.
profiles.save(s, 'Shared');
MOCK.fire('command', { command = '/cadence onelayout on' });
local mine = s.style.scale;
local own_saves = MOCK.saved;
write_file('{"Shared":{"style":{"scale":0.75}}}');
pick = 'Shared';
frame();
press = 'Load';
frame();
local shared = json.decode(read_file(SHARED) or '{}');
check('with one layout on, Load goes into the shared layout', shared.settings and shared.settings.style.scale == 0.75
    and s.style.scale == mine and MOCK.saved == own_saves, s.style.scale);
MOCK.fire('command', { command = '/cadence onelayout off' });
for name in pairs(FAKES) do rawset(imgui, name, nil); end

-- Commands --------------------------------------------------------------------------------------------------
os.remove(FILE);
profiles.refresh();
s = MOCK.settings.current;
local function said(command)
    local before = #MOCK.printed;
    MOCK.fire('command', { command = command });
    local lines = {};
    for n = before + 1, #MOCK.printed do table.insert(lines, (MOCK.printed[n]:gsub('^%[cadence%] ', ''))); end
    return lines;
end
-- A command that answers with exactly `expected` and writes no settings.
local function replies(command, expected)
    local saves_now, state = MOCK.saved, json.encode(s);
    local lines = said(command);
    return #lines == 1 and lines[1] == expected and MOCK.saved == saves_now and json.encode(s) == state,
        table.concat(lines, ' / ') .. ' saves ' .. (MOCK.saved - saves_now);
end
local USAGE = 'Type /cadence profile save|overwrite|load|delete <name>, or /cadence profile rename <old> <new>. Put a '
    .. 'name with spaces in quotes.';
local function none(name) return ('There\'s no profile called "%s". /cadence help profiles lists yours.'):format(name); end

s.style.scale = 1.25;
ok, detail = replies('/cadence profile save Solo BLM', 'Your settings are saved as the profile "Solo BLM".');
check('profile save, with a space and no quotes', ok and profiles.exists('Solo BLM'), detail);
ok, detail = replies('/cadence PROFILE Save "solo blm"', 'There\'s already a profile called "Solo BLM". /cadence profile '
    .. 'overwrite saves over it.');
check('a name another profile has in any case is refused', ok and #profiles.names() == 1, detail);
local NO_LINK = 'Job links use "%s" to mean no link, so a profile can\'t have that name.';
ok, detail = replies('/cadence profile save none', NO_LINK:format('none'));
check('so is none', ok and #profiles.names() == 1, detail);
ok, detail = replies('/cadence profile save "(NONE)"', NO_LINK:format('(NONE)'));
check('and (none), in any case', ok and #profiles.names() == 1, detail);
s.style.scale = 1.5;
ok, detail = replies('/cadence profile overwrite SOLO BLM', 'Your settings are saved over the profile "Solo BLM".');
check('profile overwrite, in any case', ok and json.decode(read_file())['Solo BLM'].style.scale == 1.5, detail);
ok, detail = replies('/cadence profile overwrite Duo', none('Duo'));
check('overwrite needs a profile that\'s there', ok and not profiles.exists('Duo'), detail);

s.style.scale = 1;
local saves_now = MOCK.saved;
MOCK.in_use = nil;
local lines = said('/cadence profile load "solo blm"');
check('profile load, with quotes', #lines == 1 and lines[1] == 'Your settings now come from the profile "Solo BLM".'
    and s.style.scale == 1.5, lines[1]);
check('saves once and redraws the timers', MOCK.saved == saves_now + 1 and MOCK.in_use == s);
ok, detail = replies('/cadence profile load nope', none('nope'));
check('a profile that isn\'t there doesn\'t load', ok, detail);

profiles.save(s, 'apple');
ok, detail = replies('/cadence profile rename "Solo BLM" Nuker', 'The profile "Solo BLM" is now called "Nuker".');
check('profile rename', ok and profiles.exists('Nuker'), detail);
ok, detail = replies('/cadence profile rename nuker NUKER', 'The profile "Nuker" is now called "NUKER".');
check('a change of case alone', ok and profiles.exists('NUKER'), detail);
ok, detail = replies('/cadence profile rename NUKER NUKER', 'The profile is already called "NUKER".');
check('the same name', ok, detail);
ok, detail = replies('/cadence profile rename nuker Apple', 'There\'s already a profile called "apple".');
check('a name another profile has', ok and profiles.exists('NUKER'), detail);
ok, detail = replies('/cadence profile rename nuker None', NO_LINK:format('None'));
check('None', ok and profiles.exists('NUKER'), detail);
ok, detail = replies('/cadence profile rename nuker (none)', NO_LINK:format('(none)'));
check('and (none)', ok and profiles.exists('NUKER'), detail);
ok, detail = replies('/cadence profile rename nope x', none('nope'));
check('a profile that isn\'t there', ok, detail);
ok, detail = replies('/cadence profile rename Solo BLM Nuker', USAGE);
check('names with spaces and no quotes get the usage line', ok, detail);
ok, detail = replies('/cadence profile delete nuker', 'The profile "NUKER" is deleted.');
check('profile delete, in any case', ok and not profiles.exists('NUKER'), detail);
ok, detail = replies('/cadence profile delete nuker', none('nuker'));
check('deleting it again', ok, detail);

for _, command in ipairs({ '/cadence profile', '/cadence profile list', '/cadence profile save', '/cadence profile save ""',
        '/cadence profile load "Solo BLM', '/cadence profile rename apple' }) do
    ok, detail = replies(command, USAGE);
    check('"' .. command .. '" gets the usage line', ok, detail);
end
-- An auto-translate phrase can hold plain letters, like Hi here.
ok, detail = replies('/cadence profile save \253\2\2Hi\253Party\130\160', 'Your settings are saved as the profile "Party".');
check('auto-translate phrases and two-byte letters are dropped whole', ok, detail);
ok, detail = replies('/cadence profile save \130\160\131\65', 'That name has nothing cadence can use. Use plain English '
    .. 'letters, numbers or symbols.');
check('a name with nothing left is refused', ok and not profiles.exists('A'), detail);
ok, detail = replies('/cadence profile load \131\65', 'That name has nothing cadence can use. Use plain English letters, '
    .. 'numbers or symbols.');
check('the same for a name to find', ok, detail);

-- Help, with the names of your profiles.
local HELP = {
    '/cadence profile save <name>  saves your settings as a new profile. Every character shares your profiles.',
    '/cadence profile overwrite <name>  saves your settings over that profile.',
    '/cadence profile load <name>  loads a profile. It holds every setting but where the settings window sits, its size '
        .. 'and your job links.',
    '/cadence profile rename <old> <new>  gives a profile a new name. Your job links to it follow.',
    '/cadence profile delete <name>  deletes a profile and your job links to it.',
    '/cadence joblink <job> <profile>  loads that profile when you change to that main job and zone. Each character has '
        .. 'its own job links. The jobs are WAR, MNK, WHM, BLM, RDM, THF, PLD, DRK, BST, BRD, RNG, SAM, NIN, DRG, SMN, BLU, '
        .. 'COR and PUP.',
    '/cadence joblink <job> none  stops that job loading a profile.',
    'Capital letters don\'t matter in a name. Put a name with spaces in quotes, like /cadence profile load "Solo BLM".',
};
-- The last two lines are your profiles and your job links. test_job_links.lua checks the job links line.
lines = said('/cadence help profiles');
local links_line = table.remove(lines);
local last = table.remove(lines);
check('help profiles', table.concat(lines, '\n') == table.concat(HELP, '\n'), table.concat(lines, ' / '));
check('then your profiles', last == 'Your profiles are "apple" and "Party".', last);
check('then your job links', links_line == 'You have no job links.', links_line);
check('help profile is the same', table.concat(said('/cadence help profile'), '\n')
    == table.concat(HELP, '\n') .. '\n' .. last .. '\n' .. links_line);
profiles.delete(s, 'Party');
lines = said('/cadence help profiles');
check('with one profile', lines[#lines - 1] == 'Your profile is "apple".', lines[#lines - 1]);
profiles.delete(s, 'apple');
lines = said('/cadence help profiles');
check('with none', lines[#lines - 1] == 'You have no profiles yet.', lines[#lines - 1]);
write_file('{"From outside":{}}');
lines = said('/cadence help profiles');
check('help reads the file again, since another character can change it', lines[#lines - 1]
    == 'Your profile is "From outside".', lines[#lines - 1]);
os.remove(FILE);

-- A broken file.
write_file('{broken');
profiles.refresh();
ok, detail = replies('/cadence profile save X', profiles.problem());
check('a broken file stops every profile command and says why', ok and read_file() == '{broken', detail);
ok, detail = replies('/cadence profile load X', profiles.problem());
check('load too', ok, detail);
lines = said('/cadence help profiles');
check('and help says so in place of the names', lines[#lines - 1] == profiles.problem(), lines[#lines - 1]);
os.remove(FILE);

-- One layout for all characters.
profiles.refresh();
write_file('{"Wide":{"attack":{"width":500}}}');
MOCK.fire('command', { command = '/cadence onelayout on' });
own_saves = MOCK.saved;
local width = s.attack.width;
lines = said('/cadence profile load wide');
shared = json.decode(read_file(SHARED) or '{}');
check('with one layout on, profile load goes into the shared layout', lines[1] == 'Your settings now come from the '
    .. 'profile "Wide".' and shared.settings and shared.settings.attack.width == 500 and s.attack.width == width
    and MOCK.saved == own_saves, lines[1]);
MOCK.fire('command', { command = '/cadence onelayout off' });

-- Reset all leaves your profiles.
MOCK.now = MOCK.now + 30;
said('/cadence reset all');
said('/cadence reset all');
check('reset all leaves your profiles', read_file() == '{"Wide":{"attack":{"width":500}}}' and profiles.exists('Wide'));
os.remove(FILE);
os.remove(SHARED);

-- What chat says reads like everything else in cadence.
local odd = nil;
for _, line in ipairs(MOCK.printed) do
    if (line:find(';', 1, true) or line:find('[\128-\255]') or line:find(' - ', 1, true)) then odd = line; end
end
check('no semicolons, dashes or odd characters in anything said', odd == nil, odd);
local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped', 1, true)) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
