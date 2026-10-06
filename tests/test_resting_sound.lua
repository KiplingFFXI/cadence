-- The sound when resting fills your HP and MP. The two sounds that come with cadence and your sounds folder,
-- the list, picking a file, when the file opens and closes, when it plays and when it doesn't, the volume, a
-- file that won't open or play, a sound of cadence's that's gone, the commands, the Sound rows in the
-- settings window, the settings check, profiles and presets.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

local FOLDER = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\sounds\\';
local OURS = 'C:\\Ashita\\addons\\cadence\\sounds\\';
local ALIAS = 'cadence_resting_sound';
local PLAY = 'play ' .. ALIAS .. ' from 0';
local CLOSE = 'close ' .. ALIAS;
local function OPEN(name, folder) return ('open "%s%s" type mpegvideo alias %s'):format(folder or FOLDER, name, ALIAS); end
local function PROBLEM(name) return name .. ' won\'t play. Check that it\'s a working .mp3 or .wav file, or pick another one.'; end

-- cadence's own folder, the way addon.path gives it in game, with its two sounds and a file that isn't one.
addon.path = 'C:\\Ashita\\addons\\cadence\\';
MOCK.fs[OURS] = true;
MOCK.fs[OURS .. 'FF VII Save.mp3'] = true;
MOCK.fs[OURS .. 'FF IX Moogle.mp3'] = true;
-- Your folder starts missing. Its files, with two that aren't sounds and one with the same name as one of cadence's.
local MINE = { 'Chime.WAV', 'bell.mp3', 'notes.txt', 'alarm.Mp3', 'song.ogg', 'ff vii save.MP3' };
MOCK.dirs = { [FOLDER] = MINE, [OURS] = { 'FF VII Save.mp3', 'readme.txt', 'FF IX Moogle.mp3' } };
local made, looks = {}, 0;
ashita.fs.create_dir = function (path) table.insert(made, path); MOCK.fs[path] = true; return true; end
-- Reading a folder that isn't there fails, the worst the real one could do.
local get_directory = ashita.fs.get_directory;
ashita.fs.get_directory = function (path, ...)
    if (not MOCK.fs[path]) then error('no folder ' .. path); end
    if (path == FOLDER) then looks = looks + 1; end
    return get_directory(path, ...);
end

os.remove(MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\shared_layout.json');
os.remove(MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\profiles.json');
MOCK.player.hp_max, MOCK.player.mp_max = 1000, 400;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local imgui = require('imgui');
local sound = require('ui.sound');
local defaults = require('ui.defaults');
local presets = require('ui.presets');
local json = require('json');
local ME = 1001;
MOCK.now = 100;

-- Runs a command. Returns what it printed, without the [cadence] header.
local function said(command)
    local before = #MOCK.printed;
    MOCK.fire('command', { command = command });
    local lines = {};
    for i = before + 1, #MOCK.printed do table.insert(lines, (MOCK.printed[i]:gsub('^%[cadence%] ', ''))); end
    return lines;
end
-- Runs a command that should answer with exactly `expected`, and save once or not at all.
local function answers(command, expected, saves)
    local before = MOCK.saved;
    local lines = said(command);
    return #lines == 1 and lines[1] == expected and MOCK.saved == before + (saves or 1),
        table.concat(lines, ' / ') .. ' saves ' .. (MOCK.saved - before);
end
local function frames(n) for _ = 1, n or 1 do MOCK.frame(1 / 60); end end
-- How many MCI commands since `from` are `command`, or start with it.
local function sent(command, from)
    local n = 0;
    for i = (from or 0) + 1, #MOCK.mci do
        if (MOCK.mci[i] == command or MOCK.mci[i]:sub(1, #command) == command) then n = n + 1; end
    end
    return n;
end
local function since(from) return table.concat(MOCK.mci, ' | ', from + 1); end
local function vitals(hp, mp) MOCK.fire('packet_in', MOCK.vitals_packet(ME, hp, mp, 0)); frames(1); end
local function sit() MOCK.player.status = 33; frames(2); end
local function stand() MOCK.player.status = 0; frames(2); end
-- Sits down below full and keeps resting until full. Returns how many times the sound played.
local function resting_until_full()
    local from = #MOCK.mci;
    stand();
    vitals(600, 200);
    sit();
    vitals(800, 300);
    vitals(1000, 400);
    frames(30);
    vitals(1000, 400);
    return sent(PLAY, from);
end
local function listed() return table.concat(sound.files(), ','); end

-- What the window draws in one frame, with Button, Selectable and BeginCombo answering for one label.
local function window_frame(pressed, list_open, picked, hovered)
    -- Each stand-in records its call the way the mock does, then says yes only for its label.
    local function answering(name, yes)
        rawset(imgui, name, function (label, ...)
            local args = { name, label };
            for _, v in ipairs({ ... }) do table.insert(args, v); end
            table.insert(MOCK.imgui_calls, args);
            return label == yes;
        end);
    end
    answering('Button', pressed);
    answering('BeginCombo', list_open);
    answering('Selectable', picked);
    if (hovered) then rawset(imgui, 'IsItemHovered', function () return true; end); end
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    rawset(imgui, 'Button', nil);
    rawset(imgui, 'BeginCombo', nil);
    rawset(imgui, 'Selectable', nil);
    rawset(imgui, 'IsItemHovered', nil);
    return MOCK.imgui_calls;
end
local function find_call(calls, name, label)
    for i, c in ipairs(calls) do if (c[1] == name and c[2] == label) then return c, i; end end
    return nil;
end
-- Where the window wrote `words`, or nil, and the color it pushed for them.
local function noted(calls, words)
    for i, c in ipairs(calls) do
        if (c[1] == 'TextUnformatted' and tostring(c[2]) == words) then
            local color = calls[i - 2][1] == 'PushStyleColor' and calls[i - 2][3] or nil;
            return i, color;
        end
    end
    return nil;
end

-- The folders and the list -----------------------------------------------------------------------------
check('cadence makes your sounds folder when it loads', made[1] == FOLDER and #made == 1, table.concat(made, ', '));
check('the sound is off by default, with FF VII Save.mp3 picked at full volume', s.resting.sound == false
    and s.resting.sound_file == 'FF VII Save.mp3' and s.resting.sound_volume == 100, s.resting.sound_file);
check('so loading sends nothing to MCI', #MOCK.mci == 0, since(0));
local function size_of(path)
    local file = io.open(path, 'rb');
    if (file == nil) then return nil; end
    local size = file:seek('end');
    file:close();
    return size;
end
local save_size, moogle_size = size_of(ADDON_DIR .. '/sounds/FF VII Save.mp3'), size_of(ADDON_DIR .. '/sounds/FF IX Moogle.mp3');
check('cadence comes with its two sounds, as they were made', save_size == 27931 and moogle_size == 34618,
    tostring(save_size) .. ' ' .. tostring(moogle_size));
check('the folder isn\'t read on load', looks == 0, looks);
frames(100);
check('or each frame', looks == 0, looks);
MOCK.fire('command', { command = '/cadence' });
check('opening the settings window reads it once', looks == 1, looks);
check('the list has cadence\'s sounds first, then your .mp3 and .wav files, each part in alphabetical order in any case',
    listed() == 'FF IX Moogle.mp3,FF VII Save.mp3,alarm.Mp3,bell.mp3,Chime.WAV', listed());
check('your file with the same name as one of cadence\'s is left out', not listed():find('ff vii save.MP3', 1, true));
frames(100);
check('the open window doesn\'t read it again', looks == 1, looks);
MOCK.fire('command', { command = '/cadence' });

-- Picking a file with the command, with the sound off ----------------------------------------------------
local LIST = 'The sounds you can pick are FF IX Moogle.mp3, FF VII Save.mp3, alarm.Mp3, bell.mp3 and Chime.WAV.';
local ok, detail = answers('/cadence resting soundfile', 'Type /cadence resting soundfile <name>. ' .. LIST, 0);
check('soundfile with no name lists the sounds', ok and s.resting.sound_file == 'FF VII Save.mp3', detail);
check('after reading the folder again', looks == 2, looks);
ok, detail = answers('/cadence resting soundfile nope', 'There\'s no sound called "nope". ' .. LIST, 0);
check('a name that isn\'t there gets the list', ok and s.resting.sound_file == 'FF VII Save.mp3', detail);
MOCK.fs[OURS] = nil;
MOCK.dirs[FOLDER] = { 'readme.txt' };
ok, detail = answers('/cadence resting soundfile bell', 'There\'s no sound called "bell". There are no .mp3 or .wav '
    .. 'files in config\\addons\\cadence\\sounds yet.', 0);
check('with cadence\'s folder gone and no sounds in yours, it says so', ok, detail);
MOCK.dirs[FOLDER] = { 'bell.mp3' };
ok, detail = answers('/cadence resting soundfile', 'Type /cadence resting soundfile <name>. The sound you can pick is '
    .. 'bell.mp3.', 0);
check('one sound', ok, detail);
MOCK.fs[OURS] = true;
MOCK.dirs[FOLDER] = MINE;
check('nothing was opened yet', #MOCK.mci == 0, since(0));
ok, detail = answers('/cadence resting soundfile BELL', 'bell.mp3 is the resting sound now. It plays once you turn it '
    .. 'on with /cadence resting sound on.');
check('soundfile takes a name with no .mp3, in any case', ok and s.resting.sound_file == 'bell.mp3', detail);
check('with the sound off, picking it opens nothing', #MOCK.mci == 0, since(0));

-- The window, with the sound off.
MOCK.fire('command', { command = '/cadence' });
window_frame(nil, 'Sound##resting', 'Chime.WAV');
check('picking a file in the list with the sound off opens nothing', s.resting.sound_file == 'Chime.WAV'
    and #MOCK.mci == 0, since(0));
window_frame('Refresh##sound');
said('/cadence resting soundvolume 40');
said('/cadence resting soundvolume 100');
check('and neither do Refresh and the volume, so you never touch MCI until you turn it on or press Play',
    #MOCK.mci == 0, since(0));
MOCK.fire('command', { command = '/cadence' });

-- When the file opens and closes -----------------------------------------------------------------------
said('/cadence resting soundfile bell');
local from = #MOCK.mci;
ok, detail = answers('/cadence resting playsound', 'Playing bell.mp3 at 100% volume.', 0);
check('Play opens the file with the sound off, then plays it', ok and MOCK.mci[from + 1] == CLOSE
    and MOCK.mci[from + 2] == OPEN('bell.mp3') and sent(PLAY, from) == 1, detail .. ' ' .. since(from));
from = #MOCK.mci;
said('/cadence resting width 300');
said('/cadence resting playsound');
check('it stays open through other changes, so the next Play opens nothing', sent('open "', from) == 0
    and sent(CLOSE, from) == 0 and sent(PLAY, from) == 1, since(from));
from = #MOCK.mci;
said('/cadence resting soundfile chime');
check('picking another file with the sound off closes it and opens nothing', MOCK.mci[from + 1] == CLOSE
    and #MOCK.mci == from + 1, since(from));
said('/cadence resting playsound');
from = #MOCK.mci;
ok, detail = answers('/cadence resting sound on', 'Sound is on for the resting timer.');
check('turning the sound on keeps the file Play opened', ok and #MOCK.mci == from, detail .. ' ' .. since(from));
from = #MOCK.mci;
ok, detail = answers('/cadence resting sound off', 'Sound is off for the resting timer.');
check('turning the sound off closes it', ok and MOCK.mci[from + 1] == CLOSE and #MOCK.mci == from + 1,
    detail .. ' ' .. since(from));
from = #MOCK.mci;
said('/cadence resting sound on');
check('turning it on opens it', MOCK.mci[from + 1] == CLOSE and MOCK.mci[from + 2] == OPEN('Chime.WAV')
    and #MOCK.mci == from + 2, since(from));

-- Picking a file with the sound on.
from = #MOCK.mci;
said('/cadence resting soundfile chime.wav');
check('picking the file that\'s open opens nothing', #MOCK.mci == from, since(from));
ok, detail = answers('/cadence resting soundfile "Bell.MP3"', 'bell.mp3 is the resting sound now.');
check('a full name in quotes, and with the sound on the answer says no more', ok and s.resting.sound_file == 'bell.mp3',
    detail);
check('picking another file closes the first, then opens it', MOCK.mci[from + 1] == CLOSE
    and MOCK.mci[from + 2] == OPEN('bell.mp3') and #MOCK.mci == from + 2, since(from));
from = #MOCK.mci;
ok, detail = answers('/cadence resting soundfile ff vii save', 'FF VII Save.mp3 is the resting sound now.');
check('one of cadence\'s sounds opens from its own folder, not your file with the same name', ok
    and MOCK.mci[from + 2] == OPEN('FF VII Save.mp3', OURS) and #MOCK.mci == from + 2, detail .. ' ' .. since(from));
said('/cadence resting soundfile bell');

-- When it plays ----------------------------------------------------------------------------------------
local opens = sent('open "');
from = #MOCK.mci;
stand();
vitals(600, 200);
sit();
vitals(800, 300);
frames(30);
check('nothing plays while you fill up', sent(PLAY, from) == 0, since(from));
vitals(1000, 400);
check('it plays once your HP and MP are full', sent(PLAY, from) == 1, since(from));
check('at full volume, set just before it plays', MOCK.mci[#MOCK.mci - 1] == 'setaudio ' .. ALIAS .. ' volume to 1000'
    and MOCK.mci[#MOCK.mci] == PLAY, since(from));
frames(120);
vitals(1000, 400);
frames(60);
check('and not again while you\'re resting at full', sent(PLAY, from) == 1);
vitals(1000, 380);
frames(10);
vitals(1000, 400);
check('MP dropping and filling again while you\'re resting plays it again', sent(PLAY, from) == 2);
check('with no volume sent again', sent('setaudio', from) == 1);
vitals(950, 400);
vitals(1000, 400);
check('so does HP', sent(PLAY, from) == 3);
from = #MOCK.mci;
stand();
vitals(600, 200);
vitals(1000, 400);
frames(10);
check('getting full while standing plays nothing', sent(PLAY, from) == 0);
sit();
frames(60);
vitals(1000, 400);
check('nor does sitting down already full', sent(PLAY, from) == 0);
check('resting again below full plays it again', resting_until_full() == 1);
check('every play used the file opened once', sent('open "') == opens and #MOCK.mci > 0, sent('open "') - opens);

MOCK.fire('command', { command = '/cadence resting off' });
check('not with the resting timer off', resting_until_full() == 0);
MOCK.fire('command', { command = '/cadence resting on' });
MOCK.fire('command', { command = '/cadence resting sound off' });
check('not with the sound off', resting_until_full() == 0);
MOCK.fire('command', { command = '/cadence resting sound on' });

-- It plays while the timer isn't drawn.
MOCK.fire('command', { command = '/cadence hide' });
check('it plays with the timers hidden', resting_until_full() == 1);
MOCK.fire('command', { command = '/cadence hide' });
MOCK.fire('command', { command = '/cadence resting hidefull on' });
check('and with Hide once full', resting_until_full() == 1);
MOCK.fire('command', { command = '/cadence resting hidefull off' });
MOCK.in_event = true;
check('and during an event', resting_until_full() == 1);
MOCK.in_event = false;
MOCK.menu_name = 'map0    ';
check('and on the map', resting_until_full() == 1);
MOCK.menu_name = nil;
check('the settings window open doesn\'t change it', (function ()
    MOCK.fire('command', { command = '/cadence' });
    local played = resting_until_full();
    MOCK.fire('command', { command = '/cadence' });
    return played == 1;
end)());

-- The volume -------------------------------------------------------------------------------------------
ok, detail = answers('/cadence resting soundvolume 55', 'The resting sound\'s volume is set to 55%.');
check('/cadence resting soundvolume 55', ok and s.resting.sound_volume == 55, detail);
from = #MOCK.mci;
resting_until_full();
check('MCI gets it as 550 of 1000 before the next play', MOCK.mci[#MOCK.mci - 1] == 'setaudio ' .. ALIAS
    .. ' volume to 550' and MOCK.mci[#MOCK.mci] == PLAY, since(from));
from = #MOCK.mci;
resting_until_full();
check('and only once', sent('setaudio', from) == 0 and sent(PLAY, from) == 1);
MOCK.fire('command', { command = '/cadence resting soundvolume 0' });
from = #MOCK.mci;
resting_until_full();
check('0 is silent', sent('setaudio ' .. ALIAS .. ' volume to 0', from) == 1);
MOCK.fire('command', { command = '/cadence resting soundvolume 7' });
from = #MOCK.mci;
resting_until_full();
check('7 is 70', sent('setaudio ' .. ALIAS .. ' volume to 70', from) == 1);
for _, word in ipairs({ '101', '-1', '50.5', 'loud' }) do
    ok, detail = answers('/cadence resting soundvolume ' .. word, 'Type /cadence resting soundvolume <0-100>.', 0);
    check('soundvolume refuses ' .. word, ok and s.resting.sound_volume == 7, detail);
end
MOCK.fire('command', { command = '/cadence resting soundvolume 100' });

-- Play -------------------------------------------------------------------------------------------------
from = #MOCK.mci;
ok, detail = answers('/cadence resting playsound', 'Playing bell.mp3 at 100% volume.', 0);
check('/cadence resting playsound plays it now', ok and sent(PLAY, from) == 1 and sent('open "', from) == 0, detail);

-- The settings window ----------------------------------------------------------------------------------
MOCK.fire('command', { command = '/cadence' });
local calls = window_frame();
local combo = find_call(calls, 'BeginCombo', 'Sound##resting');
check('the Sound list shows your file', combo ~= nil and combo[3] == 'bell.mp3', combo and combo[3]);
local box, box_at = find_call(calls, 'Checkbox', '##sound');
local _, combo_at = find_call(calls, 'BeginCombo', 'Sound##resting');
local drawn = {};
for i = (box_at or 0) + 1, (combo_at or 0) - 1 do
    if (calls[i][1]:find('^Text') or calls[i][1] == 'Button' or calls[i][1] == 'Checkbox') then
        table.insert(drawn, calls[i][1]);
    end
end
check('with the box that turns it on in front', box ~= nil and box[3][1] == true and calls[box_at + 1][1] == 'SameLine'
    and combo_at > box_at and #drawn == 0, tostring(box_at) .. ' ' .. tostring(combo_at) .. ' ' .. table.concat(drawn, ','));
local slider = find_call(calls, 'SliderInt', 'Volume##sound');
check('the Volume slider goes from 0 to 100 in percent', slider ~= nil and slider[4] == 0 and slider[5] == 100
    and slider[6] == '%d%%' and slider[3][1] == 100, slider and table.concat({ slider[4], slider[5], slider[6] }, ' '));
local _, play_at = find_call(calls, 'Button', 'Play##sound');
check('Play works with a file picked', play_at ~= nil and calls[play_at - 1][1] == 'BeginDisabled'
    and calls[play_at - 1][2] == false);
local told = false;
for _, c in ipairs(window_frame(nil, nil, nil, true)) do
    if (c[1] == 'TextUnformatted' and tostring(c[2]):find('^Plays a sound once resting fills your HP and MP%. Tick '
        .. 'the box to turn it on%. Two sounds come with cadence%. To add your own, put %.mp3 or %.wav files in '
        .. 'config\\addons\\cadence\\sounds%.$')) then
        told = true;
    end
end
check('its tip says two sounds come with cadence and where yours go', told);
calls = window_frame(nil, 'Sound##resting');
local rows = {};
for _, c in ipairs(calls) do if (c[1] == 'Selectable') then table.insert(rows, c[2]); end end
check('the open list has the sounds from the last look', table.concat(rows, ',')
    == 'FF IX Moogle.mp3,FF VII Save.mp3,alarm.Mp3,bell.mp3,Chime.WAV', table.concat(rows, ','));
-- The list grows to fit its longest name, in the room left of Refresh. The mock draws 7 px a letter, and
-- here the box in front of the list takes 30 px.
local function list_width()
    local moved = false;
    rawset(imgui, 'Checkbox', function (label)
        table.insert(MOCK.imgui_calls, { 'Checkbox', label });
        moved = moved or label == '##sound';
        return false;
    end);
    rawset(imgui, 'GetCursorPosX', function () return moved and 30 or 0; end);
    local now = window_frame();
    rawset(imgui, 'Checkbox', nil);
    rawset(imgui, 'GetCursorPosX', nil);
    local _, at = find_call(now, 'BeginCombo', 'Sound##resting');
    return now[at - 1][1] == 'SetNextItemWidth' and now[at - 1][2] or nil;
end
check('with short names the box and the list are as wide as the other controls', list_width() == 190 - 30, list_width());
MOCK.dirs[FOLDER] = { 'A long name for when resting is done.mp3' };
window_frame('Refresh##sound');
check('the list grows to fit a longer name, even one that isn\'t picked', list_width() == 40 * 7 + 16 + 26,
    list_width());
MOCK.content_width = 400;
check('but only into the room left of its name, Refresh and their (?)', list_width() == 400 - 102 - 68, list_width());
MOCK.content_width = nil;
MOCK.dirs[FOLDER] = { 'chime.wav', 'zap.mp3' };
local saves = MOCK.saved;
window_frame('Refresh##sound');
check('Refresh reads the folder again', listed() == 'FF IX Moogle.mp3,FF VII Save.mp3,chime.wav,zap.mp3'
    and MOCK.saved == saves, listed());
from = #MOCK.mci;
window_frame(nil, 'Sound##resting', 'zap.mp3');
check('with the sound on, picking a file in the list closes the old one and opens it once',
    s.resting.sound_file == 'zap.mp3' and MOCK.mci[from + 1] == CLOSE and MOCK.mci[from + 2] == OPEN('zap.mp3')
    and #MOCK.mci == from + 2 and MOCK.saved > saves, since(from));
from = #MOCK.mci;
local printed = #MOCK.printed;
window_frame('Play##sound');
check('Play plays it, with nothing in chat', sent(PLAY, from) == 1 and sent('open "', from) == 0
    and #MOCK.printed == printed, since(from));
MOCK.dirs[FOLDER] = {};
MOCK.fs[OURS] = nil;
window_frame('Refresh##sound');
calls = window_frame(nil, 'Sound##resting');
check('with no sounds anywhere, the open list says so', noted(calls, 'No .mp3 or .wav files in the sounds folder yet.'));
MOCK.fs[OURS] = true;
MOCK.dirs[FOLDER] = MINE;
window_frame('Refresh##sound');

-- A file that won't open ------------------------------------------------------------------------------
local NOTE = 'Chime.WAV won\'t play. Try another file.';
MOCK.mci_code = function (command) return command:find('^open') and 263 or 0; end
from = #MOCK.mci;
ok, detail = answers('/cadence resting soundfile chime', PROBLEM('Chime.WAV'));
check('a file that won\'t open is still picked, and chat says so once', ok and s.resting.sound_file == 'Chime.WAV',
    detail);
check('it was tried once', sent('open "', from) == 1, since(from));
printed = #MOCK.printed;
calls = window_frame();
local note_at, note_color = noted(calls, NOTE);
local _, play_button = find_call(calls, 'Button', 'Play##sound');
local problem_color = s.window_style.problem_messages;
check('the window says so under Play, in the problem color', note_at ~= nil and note_at > play_button
    and note_color ~= nil and note_color[1] == problem_color[1] and note_color[2] == problem_color[2],
    tostring(note_at) .. ' ' .. tostring(play_button));
from = #MOCK.mci;
frames(60);
MOCK.fire('command', { command = '/cadence resting width 300' });
MOCK.fire('command', { command = '/cadence resting soundvolume 80' });
window_frame();
check('frames and other changes don\'t try it again or say it again', sent('open "', from) == 0
    and #MOCK.printed == printed + 2, since(from));
check('getting full plays nothing and nothing breaks', resting_until_full() == 0 and sent('open "', from) == 0);
local broke = false;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped', 1, true)) then broke = true; end end
check('the addon keeps drawing', not broke);
from = #MOCK.mci;
printed = #MOCK.printed;
window_frame('Play##sound');
check('Play tries it again and says so once', sent('open "', from) == 1 and #MOCK.printed == printed + 1
    and MOCK.printed[#MOCK.printed]:find(PROBLEM('Chime.WAV'), 1, true) ~= nil, MOCK.printed[#MOCK.printed]);
from = #MOCK.mci;
ok, detail = answers('/cadence resting playsound', PROBLEM('Chime.WAV'), 0);
check('so does /cadence resting playsound', ok and sent('open "', from) == 1, detail);
for _, name in ipairs({ 'bell.mp3', 'Chime.WAV' }) do
    from = #MOCK.mci;
    printed = #MOCK.printed;
    window_frame(nil, 'Sound##resting', name);
    check('picking ' .. name .. ' in the list when it won\'t open tries it once and says so once',
        s.resting.sound_file == name and sent('open "', from) == 1 and #MOCK.printed == printed + 1
        and MOCK.printed[#MOCK.printed]:find(name .. ' won\'t play', 1, true) ~= nil,
        sent('open "', from) .. ' opens, ' .. (#MOCK.printed - printed) .. ' lines');
end
said('/cadence resting sound off');
from = #MOCK.mci;
local lines = said('/cadence resting sound on');
check('turning the sound on tries it again, and chat says so once, last', #lines == 2
    and lines[1] == 'Sound is on for the resting timer.' and lines[2] == PROBLEM('Chime.WAV') and sent('open "', from) == 1,
    table.concat(lines, ' / ') .. ' ' .. since(from));
said('/cadence resting sound off');
from = #MOCK.mci;
window_frame(nil, 'Sound##resting', 'bell.mp3');
check('with the sound off, picking another file takes the note away', not noted(window_frame(), NOTE)
    and sent('open "', from) == 0, since(from));
window_frame(nil, 'Sound##resting', 'Chime.WAV');
check('and picking the one that won\'t play brings it back', noted(window_frame(), NOTE) ~= nil);
said('/cadence resting sound on');
MOCK.mci_code = nil;
from = #MOCK.mci;
printed = #MOCK.printed;
window_frame('Play##sound');
check('once the file is fixed, Play opens and plays it', sent('open "', from) == 1 and sent(PLAY, from) == 1
    and #MOCK.printed == printed, since(from));
check('and the note goes', not noted(window_frame(), NOTE));

-- A file that opens but won't play.
MOCK.mci_code = function (command) return command:find('^play') and 277 or 0; end
ok, detail = answers('/cadence resting playsound', PROBLEM('Chime.WAV'), 0);
check('a play that fails says so', ok, detail);
check('and closes the file', MOCK.mci[#MOCK.mci] == CLOSE, MOCK.mci[#MOCK.mci]);
check('with the note in the window', noted(window_frame(), NOTE));
MOCK.mci_code = function (command) return command:find('^setaudio') and 277 or 0; end
MOCK.fire('command', { command = '/cadence resting soundvolume 60' });
from = #MOCK.mci;
said('/cadence resting playsound');
check('a volume MCI won\'t take doesn\'t play at the wrong volume, even after opening it again', sent(PLAY, from) == 0
    and sent('setaudio', from) == 2 and sent('open "', from) == 2, since(from));
MOCK.mci_code = nil;
said('/cadence resting playsound');

-- A play that fails once, like after a change of sound device, opens the file again and plays.
local tries = 0;
MOCK.mci_code = function (command)
    if (command:find('^play')) then tries = tries + 1; return (tries == 1) and 263 or 0; end
    return 0;
end
from = #MOCK.mci;
printed = #MOCK.printed;
check('a play that fails once opens the file again and plays', sound.play(60) and tries == 2
    and sent('open "', from) == 1 and sent('setaudio', from) == 1 and MOCK.mci[#MOCK.mci] == PLAY, since(from));
check('and says nothing, with no note', #MOCK.printed == printed and not noted(window_frame(), NOTE));
MOCK.mci_code = function (command) return command:find('^open') and 275 or (command:find('^play') and 263 or 0); end
from = #MOCK.mci;
check('when it won\'t open again either, cadence gives up', not sound.play(60) and sent(PLAY, from) == 1
    and sent('open "', from) == 1 and noted(window_frame(), NOTE), since(from));
MOCK.mci_code = nil;
said('/cadence resting playsound');

-- A sound of cadence's that's gone ---------------------------------------------------------------------
-- MCI can't open a file that isn't there.
MOCK.mci_code = function (command)
    local path = command:match('^open "(.-)"');
    return (path ~= nil and not MOCK.fs[path]) and 275 or 0;
end
MOCK.dirs[OURS] = { 'FF IX Moogle.mp3' };
MOCK.fs[OURS .. 'FF VII Save.mp3'] = nil;
MOCK.dirs[FOLDER] = { 'bell.mp3' };
window_frame('Refresh##sound');
check('a sound of cadence\'s that\'s gone isn\'t listed', listed() == 'FF IX Moogle.mp3,bell.mp3', listed());
s.resting.sound_file = 'FF VII Save.mp3';
from = #MOCK.mci;
ok, detail = answers('/cadence resting playsound', PROBLEM('FF VII Save.mp3'), 0);
check('picked anyway, it\'s looked for in your folder, and chat says it won\'t play', ok
    and MOCK.mci[from + 2] == OPEN('FF VII Save.mp3'), detail .. ' ' .. since(from));
check('the window says so too', noted(window_frame(), 'FF VII Save.mp3 won\'t play. Try another file.'));
check('getting full plays nothing', resting_until_full() == 0);
MOCK.fs[OURS] = nil;
MOCK.fs[OURS .. 'FF IX Moogle.mp3'] = nil;
window_frame('Refresh##sound');
check('with cadence\'s whole folder gone, the list has only yours', listed() == 'bell.mp3', listed());
broke = false;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped', 1, true)) then broke = true; end end
check('and nothing breaks', not broke);
MOCK.mci_code = nil;
MOCK.fs[OURS], MOCK.fs[OURS .. 'FF VII Save.mp3'], MOCK.fs[OURS .. 'FF IX Moogle.mp3'] = true, true, true;
MOCK.dirs[OURS] = { 'FF VII Save.mp3', 'FF IX Moogle.mp3' };
MOCK.dirs[FOLDER] = MINE;
said('/cadence resting soundfile bell');

-- Closing it --------------------------------------------------------------------------------------------
from = #MOCK.mci;
MOCK.fire('unload');
check('unloading closes it', MOCK.mci[from + 1] == CLOSE and #MOCK.mci == from + 1, since(from));
MOCK.fire('command', { command = '/cadence resting playsound' });
from = #MOCK.mci;
MOCK.now = MOCK.now + 20;
MOCK.fire('command', { command = '/cadence reset all' });
MOCK.fire('command', { command = '/cadence reset all' });
check('reset all turns the sound off with FF VII Save.mp3 picked, and closes the file',
    s.resting.sound_file == 'FF VII Save.mp3' and s.resting.sound == false and s.resting.sound_volume == 100
    and sent(CLOSE, from) == 1 and sent('open "', from) == 0, since(from));
calls = window_frame();
local _, play_on = find_call(calls, 'Button', 'Play##sound');
combo = find_call(calls, 'BeginCombo', 'Sound##resting');
check('so the list shows it and Play works', combo[3] == 'FF VII Save.mp3' and calls[play_on - 1][2] == false, combo[3]);
s.resting.sound_file = '';
calls = window_frame();
local _, play_off = find_call(calls, 'Button', 'Play##sound');
check('with no file, Play is greyed out', calls[play_off - 1][1] == 'BeginDisabled' and calls[play_off - 1][2] == true);
combo = find_call(calls, 'BeginCombo', 'Sound##resting');
check('and the list shows (none)', combo[3] == '(none)', combo[3]);
s.resting.sound_file = 'FF VII Save.mp3';
MOCK.fire('command', { command = '/cadence' });
from = #MOCK.mci;
ok, detail = answers('/cadence resting sound on', 'Sound is on for the resting timer.');
check('so turning the sound on just works, with FF VII Save.mp3 from cadence\'s folder', ok
    and MOCK.mci[from + 2] == OPEN('FF VII Save.mp3', OURS) and #MOCK.mci == from + 2, detail .. ' ' .. since(from));
said('/cadence resting sound off');

-- Profiles, presets, another character -----------------------------------------------------------------
said('/cadence resting soundfile alarm');
said('/cadence resting sound on');
said('/cadence resting soundvolume 35');
local function sound_settings() return json.encode({ s.resting.sound, s.resting.sound_file, s.resting.sound_volume }); end
local before = sound_settings();
local changed = {};
for _, name in ipairs(presets.NAMES) do
    presets.apply(s, name);
    if (sound_settings() ~= before) then table.insert(changed, name); end
end
check('no preset changes the sound', #changed == 0, table.concat(changed, ', '));
presets.reset(s);
check('nor does Reset look', sound_settings() == before, sound_settings());
presets.undo(s);
check('nor Undo', sound_settings() == before, sound_settings());
presets.reset(s);
presets.forget_undo();
said('/cadence profile save Loud');
said('/cadence resting soundfile bell');
said('/cadence resting sound off');
said('/cadence resting soundvolume 90');
local file = io.open(MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\profiles.json');
local saved = json.decode(file:read('*a'));
file:close();
local kept = saved.Loud and saved.Loud.resting;
check('a profile holds the sound', kept and kept.sound == true and kept.sound_file == 'alarm.Mp3'
    and kept.sound_volume == 35);
from = #MOCK.mci;
said('/cadence profile load Loud');
check('and loading it puts the sound back and opens its file', s.resting.sound == true
    and s.resting.sound_file == 'alarm.Mp3' and s.resting.sound_volume == 35
    and MOCK.mci[from + 1] == CLOSE and MOCK.mci[from + 2] == OPEN('alarm.Mp3'), since(from));
from = #MOCK.mci;
MOCK.settings.switch_character({ resting = { sound = true, sound_file = 'bell.mp3' } });
s = MOCK.settings.current;
check('another character logging in opens their own file', MOCK.mci[from + 1] == CLOSE
    and MOCK.mci[from + 2] == OPEN('bell.mp3') and #MOCK.mci == from + 2, since(from));
from = #MOCK.mci;
MOCK.settings.switch_character(nil);
s = MOCK.settings.current;
check('and one with the sound off closes it', s.resting.sound_file == 'FF VII Save.mp3'
    and MOCK.mci[from + 1] == CLOSE and #MOCK.mci == from + 1, since(from));

-- The settings check ------------------------------------------------------------------------------------
local CASES = {
    { 'bell.mp3', 'bell.mp3' },
    { 'FF IX Moogle.mp3', 'FF IX Moogle.mp3' },
    { 'My Full Chime.wav', 'My Full Chime.wav' },
    { 'C:\\Games\\PhoenixXI\\sounds\\ding.mp3', 'ding.mp3' },
    { '..\\..\\up.wav', 'up.wav' },
    { 'folder/inside.mp3', 'inside.mp3' },
    { 'D:ding.mp3', 'ding.mp3' },
    { 'say "hi".mp3', 'say hi.mp3' },
    { 'tab\there.mp3', 'tabhere.mp3' },
    { '..', '' },
    { '.', '' },
    { 'sounds\\', '' },
    { '', '' },
    { 42, 'FF VII Save.mp3' },
    { true, 'FF VII Save.mp3' },
};
local tidied = {};
for _, case in ipairs(CASES) do
    s.resting.sound_file = case[1];
    defaults.tidy(s);
    if (s.resting.sound_file ~= case[2]) then
        table.insert(tidied, ('%s gave %s'):format(tostring(case[1]), s.resting.sound_file));
    end
end
check('the file name keeps no folder, no quotes and no control characters, and one that isn\'t text gets FF VII '
    .. 'Save.mp3', #tidied == 0, table.concat(tidied, ' | '));
for _, case in ipairs({ { 150, 100 }, { -3, 0 }, { 'loud', 100 }, { 0 / 0, 100 }, { 40, 40 } }) do
    s.resting.sound_volume = case[1];
    defaults.tidy(s);
    check('a volume of ' .. tostring(case[1]) .. ' becomes ' .. case[2], s.resting.sound_volume == case[2],
        s.resting.sound_volume);
end
s.resting.sound = 'yes';
defaults.tidy(s);
check('the switch has to be true or false', s.resting.sound == false);

-- cadence's sounds folder comes from addon.path, with or without a \ at the end.
local found = {};
for _, path in ipairs({ 'D:\\Ashita\\addons\\cadence\\', 'D:\\Ashita\\addons\\cadence' }) do
    package.loaded['ui.sound'] = nil;
    addon.path = path;
    table.insert(found, require('ui.sound').BUILT_IN);
end
check('cadence\'s sounds folder is found from addon.path', found[1] == 'D:\\Ashita\\addons\\cadence\\sounds\\'
    and found[2] == found[1], table.concat(found, ' '));

-- Without winmm nothing plays, and nothing breaks.
package.loaded['ui.sound'] = nil;
MOCK.no_winmm = true;
local loaded, bare = pcall(require, 'ui.sound');
MOCK.no_winmm = nil;
from = #MOCK.mci;
check('without winmm a file just won\'t play', loaded and bare.use('bell.mp3', true) == false
    and bare.play(100) == false and bare.problem('bell.mp3') == 'bell.mp3 won\'t play. Try another file.'
    and #MOCK.mci == from, tostring(bare));

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
