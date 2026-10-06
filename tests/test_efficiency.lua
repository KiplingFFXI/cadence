-- Work cadence shouldn't redo. Ashita's party, player and inventory objects are fetched once, a party
-- member's 0x0DF is read only as far as whose it is, and the settings window makes no garbage.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

-- Counts each time cadence asks Ashita for these objects.
local asked = { GetParty = 0, GetPlayer = 0, GetInventory = 0 };
local real_manager = AshitaCore.GetMemoryManager;
AshitaCore.GetMemoryManager = function (self)
    local manager = real_manager(self);
    for name in pairs(asked) do
        local get = manager[name];
        manager[name] = function (...) asked[name] = asked[name] + 1; return get(...); end
    end
    return manager;
end
local function asked_total() return asked.GetParty + asked.GetPlayer + asked.GetInventory; end

-- Counts the fields read out of packets.
local unpacks = 0;
local real_unpack = struct.unpack;
struct.unpack = function (...) unpacks = unpacks + 1; return real_unpack(...); end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
MOCK.player.equipment[1] = 16535;
MOCK.player.main_job = 13;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local player = require('core.player');

local ME, MOB, FRIEND = 1001, 0x01000200, 1002;
MOCK.entities[0x200] = { ServerId = MOB, Name = 'Goblin Thug', Status = 1, SpawnFlags = 0x10, X = 1, Z = 0 };
MOCK.player.target_index = 0x200;

-- Ashita's party, player and inventory objects ------------------------------------------------------
local at_load = asked_total();
check('they are fetched when cadence loads', asked.GetParty >= 1 and asked.GetPlayer >= 1 and asked.GetInventory >= 1,
    ('%d %d %d'):format(asked.GetParty, asked.GetPlayer, asked.GetInventory));

MOCK.now = 100;
MOCK.player.status = 1;
for _ = 1, 30 do MOCK.frame(1 / 60); end
for i = 1, 5 do
    MOCK.now = MOCK.now + 3;
    MOCK.fire('packet_in', MOCK.action_packet(ME, 1, 0, MOB, { { message = 1 } }));
    MOCK.fire('packet_in', MOCK.vitals_packet(ME, 1000, 0, 64 * i));
    for _ = 1, 12 do MOCK.frame(1 / 60); end
end
MOCK.fire('command', { command = '/cadence info' });
MOCK.player.status = 33;
for _ = 1, 30 do MOCK.frame(1 / 60); end
MOCK.player.status = 0;
MOCK.frame(1 / 60);
check('a fight, rounds, resting and /cadence info never fetch them again', asked_total() == at_load,
    ('%d more'):format(asked_total() - at_load));

-- The kept objects still read what's in memory now.
MOCK.player.tp = 1234;
MOCK.player.hp_max = 1500;
local hp_max = player.max_vitals();
check('your TP and max HP are read fresh', player.tp() == 1234 and hp_max == 1500, player.tp() .. ' ' .. hp_max);
MOCK.player.buffs = { 33 };
check('and so are your buffs', player.read_buffs({})[33] == true);
MOCK.player.buffs = {};
MOCK.player.equipment[1] = nil;
check('and your weapons', player.read_loadout().sub == nil and player.read_loadout().main.delay == 240);

-- 0x0DF -----------------------------------------------------------------------------------------
unpacks = 0;
MOCK.fire('packet_in', MOCK.vitals_packet(FRIEND, 900, 100, 300));
check('a party member\'s is read only as far as whose it is', unpacks == 1, unpacks);
unpacks = 0;
MOCK.fire('packet_in', MOCK.vitals_packet(ME, 1000, 0, 400));
check('yours is read in full', unpacks == 4, unpacks);

-- The settings window ---------------------------------------------------------------------------
local imgui = require('imgui');
local settings_window = require('ui.settings_window');
local s = MOCK.settings.current;
settings_window.set_open(true);

-- The ON/OFF chips reuse one size table.
local chip_sizes = {};
rawset(imgui, 'Button', function (label, size)
    if (tostring(label):find('##attack$')) then table.insert(chip_sizes, size); end
    return false;
end);
settings_window.draw(s, addon.version, false, false);
settings_window.draw(s, addon.version, false, false);
check('the chip is drawn each frame', #chip_sizes == 2, #chip_sizes);
check('with the same size table', rawequal(chip_sizes[1], chip_sizes[2]) and chip_sizes[1][1] == 52);
rawset(imgui, 'Button', nil);

--[[
    No garbage from drawing the window. The mock makes some of its own, so every imgui function the
    window calls is looked up once and kept first, and the window and screen sizes come from tables
    kept here. The JIT is off so the count is only what the code makes.
]]
if (jit) then jit.off(); end
MOCK.record_imgui = true;
MOCK.imgui_calls = {};
settings_window.draw(s, addon.version, false, false);
MOCK.record_imgui = false;
for _, c in ipairs(MOCK.imgui_calls) do
    if (rawget(imgui, c[1]) == nil) then rawset(imgui, c[1], imgui[c[1]]); end
end
local io_table = { DisplaySize = { x = 1600, y = 1200 } };
local next_pos, next_size = { 0, 0 }, { 0, 0 };
rawset(imgui, 'GetIO', function () return io_table; end);
rawset(imgui, 'SetNextWindowPos', function (pos) next_pos[1], next_pos[2] = pos[1], pos[2]; end);
rawset(imgui, 'SetNextWindowSize', function (size) next_size[1], next_size[2] = size[1], size[2]; end);
rawset(imgui, 'GetWindowPos', function () return next_pos[1], next_pos[2]; end);
rawset(imgui, 'GetWindowSize', function () return next_size[1], next_size[2]; end);

local function bytes_per_draw()
    for _ = 1, 10 do settings_window.draw(s, addon.version, false, false); end
    collectgarbage('collect');
    collectgarbage('stop');
    local before = collectgarbage('count');
    for _ = 1, 100 do settings_window.draw(s, addon.version, false, false); end
    local made = (collectgarbage('count') - before) * 1024 / 100;
    collectgarbage('restart');
    return made;
end
local two_columns = bytes_per_draw();
check('the window makes no garbage each frame', two_columns < 8, ('%.1f bytes a frame'):format(two_columns));
rawset(imgui, 'GetWindowSize', function () return 600, 650; end);
local one_column = bytes_per_draw();
check('nor in one column', one_column < 8, ('%.1f bytes a frame'):format(one_column));
require('ui.presets').apply(s, 'Classic FFXI');
local other_look = bytes_per_draw();
check('nor in another preset\'s colors', other_look < 8, ('%.1f bytes a frame'):format(other_look));
-- A changed look makes the Preset list say Custom and the preset it came from.
s.style.rounding = s.style.rounding + 1;
local custom_look = bytes_per_draw();
check('nor with Custom from that preset in the Preset list', custom_look < 8,
    ('%.1f bytes a frame'):format(custom_look));
-- An open chat color list draws a swatch and a name for each chat color, and scrolls to yours.
for _, name in ipairs({ 'Selectable', 'EndCombo', 'SetItemDefaultFocus' }) do rawset(imgui, name, imgui[name]); end
local begin_combo = rawget(imgui, 'BeginCombo');
rawset(imgui, 'BeginCombo', function (label) return label == 'Replies'; end);
local open_list = bytes_per_draw();
rawset(imgui, 'BeginCombo', begin_combo);
check('nor with a chat color list open', open_list < 8, ('%.1f bytes a frame'):format(open_list));
-- The Profiles tab with three profiles in its list, one picked, and a message under its buttons. The
-- message is made once, when its button is pressed.
local profiles = require('ui.profiles');
local PROFILES_FILE = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\profiles.json';
os.remove(PROFILES_FILE);
for _, name in ipairs({ 'apple', 'Solo BLM', 'Zebra' }) do profiles.save(s, name); end
for _, name in ipairs({ 'EndListBox', 'Button' }) do rawset(imgui, name, imgui[name]); end
local begin_list, select_row, button = rawget(imgui, 'BeginListBox'), rawget(imgui, 'Selectable'), rawget(imgui, 'Button');
rawset(imgui, 'BeginListBox', function () return true; end);
rawset(imgui, 'Selectable', function (label) return label == 'Solo BLM'; end);
rawset(imgui, 'Button', function (label) return label == 'Rename'; end);
settings_window.draw(s, addon.version, false, false);
rawset(imgui, 'Selectable', select_row);
rawset(imgui, 'Button', button);
local profile_list = bytes_per_draw();
local rows = 0;
MOCK.record_imgui = true;
MOCK.imgui_calls = {};
settings_window.draw(s, addon.version, false, false);
MOCK.record_imgui = false;
local message = nil;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'Selectable') then rows = rows + 1; end
    if (c[1] == 'TextUnformatted' and tostring(c[2]):find('already has that name', 1, true)) then message = c[2]; end
end
rawset(imgui, 'BeginListBox', begin_list);
check('nor with profiles in the list and a message under the buttons', profile_list < 8 and rows == 3
    and message ~= nil, ('%.1f bytes a frame, %d rows, %s'):format(profile_list, rows, tostring(message)));
-- One job linked to a profile, and one to a profile that's gone. What the gone one shows is made once.
s.job_links.BLM, s.job_links.THF = 'Solo BLM', 'Old thief';
local job_links = bytes_per_draw();
local shown = {};
MOCK.record_imgui = true;
MOCK.imgui_calls = {};
settings_window.draw(s, addon.version, false, false);
MOCK.record_imgui = false;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'BeginCombo' and (c[2] == '##BLM' or c[2] == '##THF')) then table.insert(shown, c[3]); end
end
check('nor with job links, one of them to a profile that\'s gone', job_links < 8
    and table.concat(shown, ',') == 'Solo BLM,(gone) Old thief', ('%.1f bytes a frame, %s'):format(job_links,
    table.concat(shown, ',')));
local format, gone_made = string.format, 0;
string.format = function (pattern, ...)
    if (pattern == '(gone) %s') then gone_made = gone_made + 1; end
    return format(pattern, ...);
end
for _ = 1, 10 do settings_window.draw(s, addon.version, false, false); end
string.format = format;
check('and what the gone one shows is made once, not every frame', gone_made == 0,
    ('made %d times in 10 frames'):format(gone_made));
s.job_links.BLM, s.job_links.THF = nil, nil;
os.remove(PROFILES_FILE);
-- Verdana isn't in the mock's fonts folder, so the Window tab says so under Font size.
s.window_style.font, s.window_style.font_size = 'verdana', 24;
local big_font = bytes_per_draw();
check('nor at 24 px with a note about a font that didn\'t load', big_font < 8, ('%.1f bytes a frame'):format(big_font));
local noted = false;
MOCK.record_imgui = true;
MOCK.imgui_calls = {};
settings_window.draw(s, addon.version, false, false);
MOCK.record_imgui = false;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'TextUnformatted' and tostring(c[2]):find('^Verdana isn\'t in')) then noted = true; end
end
check('and the note was there', noted);
-- The note's words are made the first time, then kept. Making them looks up the font's name.
local window_font = require('ui.window_font');
local find, finds = window_font.find, 0;
window_font.find = function (word) finds = finds + 1; return find(word); end
for _ = 1, 10 do settings_window.draw(s, addon.version, false, false); end
window_font.find = find;
check('and its words are made once, not every frame', finds == 0, ('%d look-ups in 10 frames'):format(finds));
s.window_style.font, s.window_style.font_size = 'ashita', 18;

-- The Sound rows with a file picked, with the list of sounds open, and with the note about a file that
-- won't play. The note's words are made when the file fails, and the folder is never read by a frame.
local sound = require('ui.sound');
local SOUNDS = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\sounds\\';
MOCK.dirs = { [SOUNDS] = { 'bell.mp3', 'chime.wav', 'zap.mp3' } };
MOCK.fs[SOUNDS] = true;
local looks = 0;
local get_directory = ashita.fs.get_directory;
ashita.fs.get_directory = function (...) looks = looks + 1; return get_directory(...); end
sound.refresh();
s.resting.sound_file = 'chime.wav';
sound.use('chime.wav');
looks = 0;
local picked_sound = bytes_per_draw();
check('nor with a sound picked', picked_sound < 8, ('%.1f bytes a frame'):format(picked_sound));
rawset(imgui, 'BeginCombo', function (label) return label == 'Sound##resting'; end);
local sound_list = bytes_per_draw();
rawset(imgui, 'BeginCombo', begin_combo);
check('nor with the list of sounds open', sound_list < 8 and #sound.files() == 3,
    ('%.1f bytes a frame, %d sounds'):format(sound_list, #sound.files()));
MOCK.mci_code = function (command) return command:find('^open') and 263 or 0; end
s.resting.sound_file = 'zap.mp3';
sound.use('zap.mp3', true);
MOCK.mci_code = nil;
local note_made = 0;
string.format = function (pattern, ...)
    if (pattern:find('won\'t play', 1, true)) then note_made = note_made + 1; end
    return format(pattern, ...);
end
local failed_sound = bytes_per_draw();
string.format = format;
check('nor with the note about a file that won\'t play, made once', failed_sound < 8 and sound.problem('zap.mp3') ~= nil
    and note_made == 0, ('%.1f bytes a frame, made %d times'):format(failed_sound, note_made));
check('and no frame read the sounds folder', looks == 0, looks);
ashita.fs.get_directory = get_directory;
s.resting.sound_file = '';
sound.use('');

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
