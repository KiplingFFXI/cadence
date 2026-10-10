-- Job links. The setting and its check, profiles leaving the links out, Rename and Delete taking them
-- along, your job read after zoning loading the linked profile, each character's own links, One layout for
-- all characters, the JOB LINKS section of the Profiles tab, /cadence joblink, /cadence help profiles and
-- /cadence reset all.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
-- Files left over from another test would change what loads.
local FOLDER = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\';
local FILE = FOLDER .. 'profiles.json';
local SHARED = FOLDER .. 'shared_layout.json';
os.remove(FILE);
os.remove(SHARED);

--[[
    Ashita's settings library the way test_one_layout.lua has it. Each character has a file. Ashita
    writes the table it handed out to that file on every save and before every character switch.
]]
local lib = MOCK.settings;
local files, playing = {}, 'Alice';
local function copy(t)
    local result = {};
    for k, v in pairs(t) do result[k] = (type(v) == 'table') and copy(v) or v; end
    return result;
end
local function merge(into, from)
    for k, v in pairs(from) do
        if (rawget(into, k) == nil) then into[k] = v;
        elseif (type(v) == 'table') then merge(into[k], v); end
    end
    return into;
end
local function load_file()
    local loaded = merge(copy(files[playing] or lib.defaults), lib.defaults);
    files[playing] = copy(loaded);
    return loaded;
end
function lib.load(defaults)
    lib.defaults = defaults;
    lib.current = load_file();
    return lib.current;
end
function lib.save()
    MOCK.saved = MOCK.saved + 1;
    files[playing] = copy(lib.current);
    return true;
end
-- Another character logs in. In game the 0x00A that brings them in reaches cadence too.
local function log_in(name)
    files[playing] = copy(lib.current);
    playing = name;
    lib.current = load_file();
    for _, fn in pairs(lib.callbacks) do fn(lib.current); end
    MOCK.fire('packet_in', MOCK.zone_packet(MOCK.player.server_id));
end

-- Your main job. Each read of it is counted.
local job, job_reads = 1, 0;
MOCK.player.main_job = nil;
setmetatable(MOCK.player, {
    __index = function (_, key)
        if (key == 'main_job') then job_reads = job_reads + 1; return job; end
    end,
    __newindex = function (t, key, value)
        if (key == 'main_job') then job = value; else rawset(t, key, value); end
    end,
});

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.watch_settings();
MOCK.fire('load');
local defaults = require('ui.defaults');
local profiles = require('ui.profiles');
local presets = require('ui.presets');
local shared_layout = require('core.shared_layout');
local json = require('json');
local imgui = require('imgui');
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
local function frames(n) for _ = 1, n or 1 do MOCK.frame(1 / 60); end end
-- What cadence printed since line `from`, without the [cadence] tag.
local function printed_since(from)
    local lines = {};
    for i = from + 1, #MOCK.printed do table.insert(lines, (MOCK.printed[i]:gsub('^%[cadence%] ', ''))); end
    return lines;
end
-- Runs a command. Returns what it printed and whether it was blocked from the game.
local function said(command)
    local before = #MOCK.printed;
    local e = { command = command };
    MOCK.fire('command', e);
    return printed_since(before), e.blocked;
end
-- Changes your main job to `id`, zones and draws a frame. Returns what cadence printed.
local function change_job(id)
    local before = #MOCK.printed;
    MOCK.player.main_job = id;
    MOCK.fire('packet_in', MOCK.zone_packet(MOCK.player.server_id));
    frames(1);
    return printed_since(before);
end
-- This character's links as text, in job order, like BLM=Mage,WAR=Melee.
local function links_of(t)
    local parts = {};
    for _, name in ipairs(defaults.JOBS) do
        if (t.job_links and t.job_links[name] ~= nil) then table.insert(parts, name .. '=' .. tostring(t.job_links[name])); end
    end
    return table.concat(parts, ',');
end

-- The setting and its check ----------------------------------------------------------------------------------
local fresh = defaults.make();
check('job links start empty', type(fresh.job_links) == 'table' and next(fresh.job_links) == nil);
check('every set of defaults has its own', defaults.make().job_links ~= defaults.make().job_links);
check('a link can name any of the 18 main jobs, in job id order', table.concat(defaults.JOBS, ',')
    == 'WAR,MNK,WHM,BLM,RDM,THF,PLD,DRK,BST,BRD,RNG,SAM,NIN,DRG,SMN,BLU,COR,PUP', table.concat(defaults.JOBS, ','));
local t = defaults.make();
local mine = { BLM = 'Gone long ago', WAR = 'Melee party', blm = 'x', DNC = 'x', [4] = 'x', THF = 5, RDM = '',
    NIN = { 'x' }, SAM = true };
t.job_links = mine;
defaults.tidy(t);
check('the settings check keeps a main job with a profile name, even one that isn\'t there',
    mine.BLM == 'Gone long ago' and mine.WAR == 'Melee party');
check('and drops a word that isn\'t a main job in capitals', mine.blm == nil and mine.DNC == nil and mine[4] == nil);
check('and a name that isn\'t text or is empty', mine.THF == nil and mine.RDM == nil and mine.NIN == nil
    and mine.SAM == nil);
check('in the same table, since a shared layout uses this character\'s own', t.job_links == mine
    and links_of(t) == 'WAR=Melee party,BLM=Gone long ago', links_of(t));
for _, wrong in ipairs({ 'BLM', 5, false }) do
    t.job_links = wrong;
    defaults.tidy(t);
    check('job links that aren\'t a table start over empty: ' .. tostring(wrong), type(t.job_links) == 'table'
        and next(t.job_links) == nil);
end
t.job_links = nil;
defaults.tidy(t);
check('and so do missing ones', type(t.job_links) == 'table' and next(t.job_links) == nil);

-- Profiles leave them out, and Rename and Delete take them along ----------------------------------------------
local s = lib.current;
s.job_links.BLM = 'Keep me';
profiles.save(s, 'Solo');
local text = read_file() or '';
check('a profile leaves the job links out', text ~= '' and not text:find('job_links', 1, true)
    and json.decode(text).Solo.job_links == nil);
write_file('{"Solo":{"job_links":{"WAR":"From the file"},"style":{"scale":1.5}}}');
check('loading one leaves your job links, even with links in the file', profiles.load(s, 'Solo')
    and s.style.scale == 1.5 and links_of(s) == 'BLM=Keep me', links_of(s));
s.style.scale = 1;

local links = s.job_links;
links.BLM, links.WAR, links.THF = 'Solo', 'Solo', 'Other';
profiles.save(s, 'Other');
profiles.save(s, 'Lonely');
local ok, moved = profiles.rename(s, 'Solo', 'Nuker');
local detail;
check('Rename moves every job link to it', ok and moved and links_of(s) == 'WAR=Nuker,BLM=Nuker,THF=Other', links_of(s));
ok, moved = profiles.rename(s, 'Nuker', 'NUKER');
check('a change of case alone moves them too', ok and moved and links_of(s) == 'WAR=NUKER,BLM=NUKER,THF=Other',
    links_of(s));
ok, moved = profiles.rename(s, 'Lonely', 'Alone');
check('a rename with no link to it says no link changed', ok and moved == false and links_of(s)
    == 'WAR=NUKER,BLM=NUKER,THF=Other', links_of(s));
ok, moved = profiles.rename(s, 'NUKER', 'other');
check('a rename that\'s refused leaves the links', not ok and links_of(s) == 'WAR=NUKER,BLM=NUKER,THF=Other');
ok, moved = profiles.delete(s, 'NUKER');
check('Delete clears every job link to it', ok and moved and links_of(s) == 'THF=Other', links_of(s));
ok, moved = profiles.delete(s, 'Alone');
check('a delete with no link to it says no link changed', ok and moved == false and links_of(s) == 'THF=Other');
local real_open = io.open;
io.open = function (path, mode)
    if (path:sub(1, #FILE + 1) == FILE .. '.' and mode == 'w') then return nil; end
    return real_open(path, mode);
end
check('a rename that can\'t be written leaves the links', profiles.rename(s, 'Other', 'Moved') == false
    and links_of(s) == 'THF=Other');
check('and so does a delete', profiles.delete(s, 'Other') == false and links_of(s) == 'THF=Other');
io.open = real_open;
links.THF = nil;
os.remove(FILE);

-- Your job, read after zoning -----------------------------------------------------------------------------------
write_file('{"Thief":{"style":{"scale":1.25}},"Mage":{"style":{"scale":0.75}}}');
links.THF, links.BLM, links.WHM, links.RDM = 'Thief', 'Mage', 'Gone', 'Mage';
frames(2);
check('cadence loading reads your job and loads nothing', s.style.scale == 1 and job_reads > 0);
job_reads = 0;
MOCK.player.main_job = 6;
frames(30);
check('a job change without zoning loads nothing yet, and your job isn\'t read every frame', s.style.scale == 1
    and job_reads == 0, job_reads);

presets.apply(s, 'Minimal');
local saves = MOCK.saved;
MOCK.in_use = nil;
job_reads = 0;
local lines = change_job(6);
check('zoning as a new job loads its profile and says so', s.style.scale == 1.25 and #lines == 1
    and lines[1] == 'Your settings now come from the profile "Thief", since it\'s linked to THF.', lines[1]);
check('it saves once and redraws the timers', MOCK.saved == saves + 1 and MOCK.in_use == s, MOCK.saved - saves);
check('a linked profile load can be undone', presets.can_undo());
check('the job links stay', links_of(s) == 'WHM=Gone,BLM=Mage,RDM=Mage,THF=Thief', links_of(s));
frames(30);
check('your job is read once after zoning', job_reads == 1, job_reads);

s.style.scale = 2;
lines = change_job(6);
check('zoning as the same job loads nothing', s.style.scale == 2 and #lines == 0);
lines = change_job(2);
check('an unlinked job loads nothing', s.style.scale == 2 and #lines == 0);

-- While zoning there's no you to read, and the game can hold 0 for your job for a moment.
MOCK.zoning = true;
MOCK.player.main_job = 4;
MOCK.fire('packet_in', MOCK.zone_packet(MOCK.player.server_id));
frames(5);
check('nothing loads while you\'re still zoning', s.style.scale == 2);
MOCK.zoning = false;
MOCK.player.main_job = 0;
frames(5);
check('nor while the game doesn\'t know your job yet', s.style.scale == 2);
MOCK.player.main_job = 4;
frames(1);
check('then it loads once your job is there', s.style.scale == 0.75);

lines = change_job(3);
check('a link to a profile that isn\'t there anymore says so', #lines == 1
    and lines[1] == 'WHM is linked to the profile "Gone", but it isn\'t there anymore.' and s.style.scale == 0.75,
    lines[1]);
change_job(4);
write_file('{broken');
s.style.scale = 2;
lines = change_job(5);
check('a profiles.json that can\'t be read says so', #lines == 1 and lines[1] == profiles.problem()
    and s.style.scale == 2, lines[1]);
write_file('{"Thief":{"style":{"scale":1.25}},"Mage":{"style":{"scale":0.75}}}');
lines = change_job(19);
check('a job past the era loads nothing', #lines == 0 and s.style.scale == 2);

-- Your job is read even with nothing to draw, the settings window closed and a cutscene on.
s.attack.enabled, s.resting.enabled, s.enemy.enabled = false, false, false;
MOCK.in_event = true;
lines = change_job(6);
check('with nothing on screen and a cutscene on, the profile still loads', s.style.scale == 1.25 and #lines == 1,
    lines[1]);
said('/cadence');
lines = change_job(4);
check('and with the settings window open but hidden by the cutscene', s.style.scale == 0.75 and #lines == 1, lines[1]);
said('/cadence');
MOCK.in_event = false;
s.attack.enabled, s.resting.enabled = true, true;

-- Each character has their own --------------------------------------------------------------------------------
files.Bob = { job_links = { WHM = 'Thief' }, style = { scale = 1.5 } };
local before = #MOCK.printed;
MOCK.player.main_job = 3;
log_in('Bob');
frames(2);
s = lib.current;
check('the next character has their own links', links_of(s) == 'WHM=Thief', links_of(s));
check('and their first job read loads nothing, though it isn\'t the last character\'s job', s.style.scale == 1.5
    and #printed_since(before) == 0, s.style.scale);
lines = change_job(6);
check('a job only the last character linked loads nothing', s.style.scale == 1.5 and #lines == 0);
change_job(3);
check('their own link loads', s.style.scale == 1.25);
log_in('Alice');
frames(1);
s = lib.current;
check('Alice\'s links are still theirs', links_of(s) == 'WHM=Gone,BLM=Mage,RDM=Mage,THF=Thief', links_of(s));

-- The JOB LINKS section of the Profiles tab -------------------------------------------------------------------
os.remove(FILE);
profiles.save(s, 'Solo');
profiles.save(s, 'apple');
links = s.job_links;
for _, name in ipairs(defaults.JOBS) do links[name] = nil; end
links.BLM, links.THF = 'Solo', 'Old thief';
s.window_style.font_size = 18;

local log, open_list, pick, press, typing = {}, nil, nil, nil, nil;
local cursor_x, room = 472, 434;
local function add(...) table.insert(log, table.concat({ ... }, ' ')); end
local FAKES = {
    TextColored = function (_, words) add(words); end,
    TextDisabled = function () add('(?)'); end,
    AlignTextToFramePadding = function () add('align'); end,
    TextUnformatted = function (words) add('text', words); end,
    SameLine = function () add('same'); end,
    SetCursorPosX = function (x) add('x', x); end,
    SetNextItemWidth = function (width) add('width', width); end,
    BeginCombo = function (id, shown) add('list', id, shown); return id == open_list; end,
    Selectable = function (label, on) add('row', label .. (on and ' picked' or '')); return label == pick; end,
    EndCombo = function () add('end list'); end,
    SetItemDefaultFocus = function () add('focus'); end,
    TableNextColumn = function () add('next column'); end,
    Spacing = function () add('spacing'); end,
    EndTable = function () add('end table'); end,
    GetCursorPosX = function () return cursor_x; end,
    GetContentRegionAvail = function () return room, 400; end,
    Button = function (label) return label == press; end,
    BeginListBox = function () return true; end,
    InputText = function (label, buffer)
        if (label == 'Name' and typing ~= nil) then buffer[1] = typing; return true; end
        return false;
    end,
};
for name, fn in pairs(FAKES) do rawset(imgui, name, fn); end
local function frame()
    log = {};
    frames(1);
    open_list, pick, press, typing = nil, nil, nil, nil;
end
-- The steps of the JOB LINKS section, from three before its heading to the end of the tab's sections.
local function steps()
    local found, inside = {}, false;
    for i, e in ipairs(log) do
        if (e == 'JOB LINKS') then
            inside = true;
            for k = i - 3, i - 1 do table.insert(found, log[k]); end
        end
        if (inside and e == 'end table') then break; end
        if (inside) then table.insert(found, e); end
    end
    return found;
end
local function section() return table.concat(steps(), ' | '); end
-- The rows of the open list `id` that ImGui scrolls to as it opens, the ones SetItemDefaultFocus follows.
local function focus_of(id)
    local found, inside, last = {}, false, nil;
    for _, e in ipairs(log) do
        if (e:find('list ' .. id .. ' ', 1, true) == 1) then inside = true;
        elseif (inside and e == 'end list') then break;
        elseif (inside and e:find('^row ')) then last = e:sub(5);
        elseif (inside and e == 'focus') then table.insert(found, last); end
    end
    return table.concat(found, ',');
end
-- What follows `word` in each of the section's steps that starts with it, like each spot SetCursorPosX set.
local function each(word)
    local found = {};
    for _, e in ipairs(steps()) do
        local first, tail = e:match('^(%S+) (.*)$');
        if (first == word) then table.insert(found, tail); end
    end
    return table.concat(found, ',');
end
-- The rows of the open list `id`.
local function rows_of(id)
    local found, inside = {}, false;
    for _, e in ipairs(log) do
        if (e:find('list ' .. id .. ' ', 1, true) == 1) then inside = true;
        elseif (inside and e == 'end list') then break;
        elseif (inside and e:find('^row ')) then table.insert(found, e:sub(5)); end
    end
    return table.concat(found, ',');
end

said('/cadence');
frame();
local all = section();
local FIRST_TWO = '(?) | next column | spacing | JOB LINKS | same | (?) | align | text WAR | same | x 520 | width 157 '
    .. '| list ##WAR (none) | same | x 701 | align | text MNK | same | x 749 | width 157 | list ##MNK (none) | align '
    .. '| text WHM';
check('JOB LINKS is the second section, with a (?), then two jobs to a line, each name and then its list',
    all:find(FIRST_TWO, 1, true) == 1, all);
local wanted_ids, wanted_spots, wanted_widths = {}, {}, {};
for i, name in ipairs(defaults.JOBS) do
    table.insert(wanted_ids, '##' .. name .. ' ' .. ((name == 'BLM' and 'Solo') or (name == 'THF' and '(gone) Old thief')
        or '(none)'));
    if (i % 2 == 1) then table.insert(wanted_spots, '520');
    else table.insert(wanted_spots, '701'); table.insert(wanted_spots, '749'); end
    table.insert(wanted_widths, '157');
end
check('a list for every main job, in job order', each('list') == table.concat(wanted_ids, ','), each('list'));
check('the left jobs\' lists start 48 in, the right jobs halfway across past the gap', each('x')
    == table.concat(wanted_spots, ','), each('x'));
check('every list reaches the gap or the edge', each('width') == table.concat(wanted_widths, ','), each('width'));
check('a linked job shows its profile', all:find('list ##BLM Solo |', 1, true) ~= nil);
check('a link to a profile that\'s gone says so', all:find('list ##THF (gone) Old thief |', 1, true) ~= nil);
check('an unlinked job shows (none)', all:find('list ##PUP (none)', 1, true) ~= nil);
check('a job list has no (?) of its own', not all:find('list ##WAR (none) | same | (?)', 1, true));

-- A bigger font moves the lists out with it. A narrow window stacks the sections.
s.window_style.font_size = 24;
frame();
all = section();
check('at 24 px each list starts 64 in and is narrower by as much', all:find('text WAR | same | x 536 | width 141 |',
    1, true) ~= nil and all:find('text MNK | same | x 765 | width 141 |', 1, true) ~= nil, all);
s.window_style.font_size = 18;
MOCK.window_size = { 600, 650 };
frame();
MOCK.window_size = nil;
check('stacked, JOB LINKS comes under PROFILES with a gap', section():find('next column | spacing | spacing | JOB LINKS',
    1, true) == 1, section());
-- The narrow window was saved as its size. Back to two columns.
s.window.width, s.window.height = 920, 680;

-- Picking in a job's list.
saves = MOCK.saved;
frame();
check('drawing the section saves nothing', MOCK.saved == saves);
open_list = '##BLM';
frame();
check('an open list has (none), then every profile, with the linked one marked', rows_of('##BLM')
    == '(none),apple,Solo picked', rows_of('##BLM'));
check('and it opens scrolled to that one', focus_of('##BLM') == 'Solo picked', focus_of('##BLM'));
open_list = '##THF';
frame();
check('a link to a profile that\'s gone has no row to scroll to', rows_of('##THF') == '(none),apple,Solo'
    and focus_of('##THF') == '', focus_of('##THF'));
open_list, pick = '##WAR', 'apple';
frame();
check('picking a profile links it and saves this character\'s file', links.WAR == 'apple' and MOCK.saved == saves + 1
    and files.Alice.job_links.WAR == 'apple', MOCK.saved - saves);
open_list, pick = '##BLM', '(none)';
frame();
check('picking (none) clears the link and saves', links.BLM == nil and files.Alice.job_links.BLM == nil
    and MOCK.saved == saves + 2);
open_list = '##BLM';
frame();
check('then (none) is the one marked', rows_of('##BLM') == '(none) picked,apple,Solo', rows_of('##BLM'));
check('and the list opens scrolled to it', focus_of('##BLM') == '(none) picked', focus_of('##BLM'));

-- Rename and Delete on the tab.
pick = 'apple';
frame();
typing = 'Pear';
press = 'Rename';
frame();
frame();
check('Rename moves the link and saves this character\'s file', links.WAR == 'Pear' and files.Alice.job_links.WAR == 'Pear'
    and MOCK.saved == saves + 3, MOCK.saved - saves);
check('and the list shows the new name', section():find('list ##WAR Pear |', 1, true) ~= nil);
pick = 'Solo';
frame();
typing = 'Duo';
press = 'Rename';
frame();
frame();
check('a rename with no link to it saves nothing', profiles.exists('Duo') and MOCK.saved == saves + 3,
    MOCK.saved - saves);
pick = 'Pear';
frame();
press = 'Delete';
frame();
frame();
check('Delete clears the link and saves', links.WAR == nil and files.Alice.job_links.WAR == nil
    and MOCK.saved == saves + 4 and not profiles.exists('Pear'), MOCK.saved - saves);

-- A profiles.json that can't be read shows each link's plain name, since its profile can still be in it.
links.BLM = 'Duo';
write_file('{broken');
said('/cadence');
said('/cadence');
frame();
all = section();
check('a profiles.json that can\'t be read shows each link\'s plain name, with no (gone)', all:find('list ##BLM Duo |',
    1, true) ~= nil and all:find('list ##THF Old thief |', 1, true) ~= nil and not all:find('(gone)', 1, true), all);
links.BLM = nil;
for name in pairs(FAKES) do rawset(imgui, name, nil); end
said('/cadence');

-- /cadence joblink --------------------------------------------------------------------------------------------
os.remove(FILE);
profiles.refresh();
links.THF = nil;
profiles.save(s, 'Solo BLM');
profiles.save(s, 'Melee');
-- A command that answers with exactly `expected`, is kept from the game and saves once.
local function answers(command, expected)
    local saves_now = MOCK.saved;
    local got, blocked = said(command);
    return #got == 1 and got[1] == expected and MOCK.saved == saves_now + 1 and blocked == true,
        table.concat(got, ' / ') .. ' saves ' .. (MOCK.saved - saves_now);
end
-- A command that answers with exactly `expected` and changes and saves nothing.
local function refuses(command, expected)
    local saves_now, state = MOCK.saved, links_of(s);
    local got = said(command);
    return #got == 1 and got[1] == expected and MOCK.saved == saves_now and links_of(s) == state,
        table.concat(got, ' / ') .. ' saves ' .. (MOCK.saved - saves_now);
end
local JOB_LIST = 'WAR, MNK, WHM, BLM, RDM, THF, PLD, DRK, BST, BRD, RNG, SAM, NIN, DRG, SMN, BLU, COR and PUP';
local USAGE = 'Type /cadence joblink <job> <profile>, or /cadence joblink <job> none to stop that job loading one.';

ok, detail = answers('/cadence joblink blm solo blm', 'The profile "Solo BLM" now loads when you change to BLM and zone.');
check('joblink, with the job in any case and a name with spaces in any case', ok and links.BLM == 'Solo BLM'
    and files.Alice.job_links.BLM == 'Solo BLM', detail);
ok, detail = answers('/cadence JOBLINK War "Melee"', 'The profile "Melee" now loads when you change to WAR and zone.');
check('a name in quotes', ok and links.WAR == 'Melee', detail);
-- Another character saved a profile since this one last read the file.
write_file('{"Solo BLM":{},"Melee":{},"Fresh":{}}');
ok, detail = answers('/cadence joblink smn fresh', 'The profile "Fresh" now loads when you change to SMN and zone.');
check('joblink reads profiles.json again first', ok and links.SMN == 'Fresh', detail);
links.SMN = nil;
ok, detail = answers('/cadence joblink war none', 'Changing to WAR no longer loads a profile.');
check('none clears a link', ok and links.WAR == nil and files.Alice.job_links.WAR == nil, detail);
ok, detail = answers('/cadence joblink BLM NONE', 'Changing to BLM no longer loads a profile.');
check('in any case', ok and links.BLM == nil, detail);
links.WAR = 'Melee';
ok, detail = answers('/cadence joblink war (none)', 'Changing to WAR no longer loads a profile.');
check('(none), the way the list shows it, clears a link too', ok and links.WAR == nil, detail);
ok, detail = refuses('/cadence joblink thf nope', 'There\'s no profile called "nope". /cadence help profiles lists yours.');
check('only a profile that\'s there can be linked', ok and links.THF == nil, detail);
ok, detail = refuses('/cadence joblink dnc Melee', ('There\'s no job called "dnc". The jobs are %s.'):format(JOB_LIST));
check('a job past the era or a wrong word says which jobs there are', ok, detail);
for _, command in ipairs({ '/cadence joblink', '/cadence joblink blm', '/cadence joblink blm ""' }) do
    ok, detail = refuses(command, USAGE);
    check('"' .. command .. '" gets the usage line', ok, detail);
end
ok, detail = refuses('/cadence joblink blm \130\160', 'That name has nothing cadence can use. Use plain English '
    .. 'letters, numbers or symbols.');
check('a name with nothing cadence can use', ok, detail);
links.RDM = 'Melee';
write_file('{broken');
profiles.refresh();
ok, detail = refuses('/cadence joblink blm Melee', profiles.problem());
check('a profiles.json that can\'t be read stops a link', ok, detail);
ok, detail = answers('/cadence joblink rdm none', 'Changing to RDM no longer loads a profile.');
check('none still works then', ok and links.RDM == nil, detail);
os.remove(FILE);
profiles.save(s, 'Solo BLM');
profiles.save(s, 'Melee');

-- Profile commands persist changed links and a renamed active baseline.
links.BLM, links.SAM = 'Solo BLM', 'Melee';
ok, detail = answers('/cadence profile rename "solo blm" Nuker', 'The profile "Solo BLM" is now called "Nuker".');
check('profile rename moves the links to it and saves', ok and links.BLM == 'Nuker'
    and files.Alice.job_links.BLM == 'Nuker', detail);
ok, detail = answers('/cadence profile delete melee', 'The profile "Melee" is deleted.');
check('profile delete clears the links to it and saves', ok and links.SAM == nil and files.Alice.job_links.SAM == nil,
    detail);
profiles.save(s, 'Spare');
ok, detail = answers('/cadence profile rename spare Extra', 'The profile "Spare" is now called "Extra".');
check('renaming the active baseline saves its new name without changing links',
    ok and s.profile_source.name == 'Extra' and files.Alice.profile_source.name == 'Extra', detail);
ok, detail = refuses('/cadence profile delete extra', 'The profile "Extra" is deleted.');
check('and neither does delete', ok, detail);

-- /cadence help profiles ends with your job links ----------------------------------------------------------------
local function links_line()
    local got = said('/cadence help profiles');
    return got[#got];
end
for _, name in ipairs(defaults.JOBS) do links[name] = nil; end
check('help with no job links', links_line() == 'You have no job links.', links_line());
links.BLM = 'Nuker';
check('help with one job link', links_line() == 'Your job link is BLM to "Nuker".', links_line());
links.WAR, links.PUP = 'Gone', 'Nuker';
check('help with more, in job order, and a profile that isn\'t there marked', links_line()
    == 'Your job links are WAR to "Gone" (gone), BLM to "Nuker" and PUP to "Nuker".', links_line());
write_file('{broken');
check('help with a file that can\'t be read, none is marked', links_line()
    == 'Your job links are WAR to "Gone", BLM to "Nuker" and PUP to "Nuker".', links_line());
os.remove(FILE);
profiles.refresh();

-- One layout for all characters --------------------------------------------------------------------------------
local function shared_file()
    local data = read_file(SHARED);
    return data and json.decode(data).settings;
end
local layout_ok, layout_err = pcall(function ()
    profiles.save(s, 'Wide');
    write_file('{"Wide":{"attack":{"width":500}}}');
    for _, name in ipairs(defaults.JOBS) do links[name] = nil; end
    said('/cadence onelayout on');
    local copy_in_use = MOCK.in_use;
    check('the shared copy uses this character\'s own links', copy_in_use ~= s and copy_in_use.job_links == s.job_links);
    saves = MOCK.saved;
    ok, detail = answers('/cadence joblink drk wide', 'The profile "Wide" now loads when you change to DRK and zone.');
    check('a link set while sharing goes into this character\'s own file', ok and files.Alice.job_links.DRK == 'Wide',
        detail);
    -- The same for a profile picked in a job's list.
    rawset(imgui, 'BeginCombo', function (id) return id == '##MNK'; end);
    rawset(imgui, 'Selectable', function (label) return label == 'Wide'; end);
    said('/cadence');
    saves = MOCK.saved;
    frames(1);
    rawset(imgui, 'BeginCombo', nil);
    rawset(imgui, 'Selectable', nil);
    said('/cadence');
    check('and so does a link picked in the window', s.job_links.MNK == 'Wide' and files.Alice.job_links.MNK == 'Wide'
        and MOCK.saved == saves + 1, MOCK.saved - saves);
    s.job_links.MNK = nil;
    said('/cadence attack tp off');
    local shared = shared_file();
    check('the shared file never holds job links', shared ~= nil and shared.job_links == nil
        and not read_file(SHARED):find('job_links', 1, true));
    local own_width = s.attack.width;
    local lines_now = change_job(8);
    shared = shared_file();
    check('the job\'s profile loads into the shared layout', lines_now[1] == 'Your settings now come from the profile '
        .. '"Wide", since it\'s linked to DRK.' and shared.attack.width == 500 and s.attack.width == own_width,
        lines_now[1]);

    -- A hand-edited shared file with links in it, then another character logging in.
    local data = json.decode(read_file(SHARED));
    data.settings.job_links = { DRK = 'Hacked', NIN = 'Hacked' };
    local f = assert(io.open(SHARED, 'w'));
    f:write(json.encode(data));
    f:close();
    files.Bob.job_links = { NIN = 'Ninja' };
    log_in('Bob');
    check('another character logs in to the shared layout with their own links', MOCK.in_use ~= lib.current
        and MOCK.in_use.job_links == lib.current.job_links and links_of(lib.current) == 'NIN=Ninja'
        and MOCK.in_use.attack.width == 500, links_of(lib.current));
    log_in('Alice');
    s = lib.current;
    check('and Alice keeps theirs', links_of(s) == 'DRK=Wide' and links_of(MOCK.in_use) == 'DRK=Wide', links_of(MOCK.in_use));

    -- Reset all clears the links in this character's file too.
    MOCK.now = MOCK.now + 30;
    said('/cadence reset all');
    saves = MOCK.saved;
    said('/cadence reset all');
    check('reset all clears the links while sharing, in this character\'s file', links_of(s) == ''
        and links_of(MOCK.in_use) == '' and files.Alice.job_links.DRK == nil and MOCK.saved == saves + 1,
        MOCK.saved - saves);
    check('and the shared layout stays on', shared_layout.is_on() and shared_file() ~= nil
        and shared_file().job_links == nil);
    s.job_links.MNK = 'Wide';
    said('/cadence onelayout off');
    check('turning it off keeps the links', links_of(lib.current) == 'MNK=Wide' and MOCK.in_use == lib.current);
end);
os.remove(SHARED);
check('the one layout part ran to the end', layout_ok, layout_err);

-- Reset all clears the links -----------------------------------------------------------------------------------
s = lib.current;
s.job_links.BLM = 'Wide';
MOCK.now = MOCK.now + 30;
lines = said('/cadence reset all');
check('reset all says the links go too', lines[1] == 'This puts every setting back to its default, including where '
    .. 'the timers sit and which ones are on, and clears your job links. Your saved profiles stay. Type /cadence reset '
    .. 'all again within 10 seconds to go ahead.' and links_of(s) == 'MNK=Wide,BLM=Wide', lines[1]);
ok, detail = answers('/cadence reset all', 'Every setting is back to its default and your job links are cleared. Your '
    .. 'saved profiles are still there.');
check('and clears them, saving once', ok and links_of(s) == '' and files.Alice.job_links.BLM == nil
    and profiles.exists('Wide'), detail);
os.remove(FILE);

-- profiles.json is read at each time the guide's "What cadence reads" table names, and only then ----------------
local guide_file = assert(io.open(ADDON_DIR .. '/../docs/GUIDE.md'));
local row = guide_file:read('*a'):match('\n| `config\\addons\\cadence\\profiles%.json`, read ([^|]*)|') or '';
guide_file:close();
local real_open, reads = io.open, 0;
io.open = function (path, mode)
    if (path == FILE and (mode == nil or mode == 'r')) then reads = reads + 1; end
    return real_open(path, mode);
end
-- Whether `action` read the file.
local function reads_file(action)
    reads = 0;
    action();
    return reads > 0;
end
-- A button on the Profiles tab. Wide gets picked in the list and Overwrite pressed in the same frame.
local function press_overwrite()
    rawset(imgui, 'BeginListBox', function () return true; end);
    rawset(imgui, 'Selectable', function (label) return label == 'Wide'; end);
    rawset(imgui, 'Button', function (label) return label == 'Overwrite'; end);
    frames(1);
    for _, name in ipairs({ 'BeginListBox', 'Selectable', 'Button' }) do rawset(imgui, name, nil); end
end
write_file('{"Wide":{}}');
s.job_links.BLM = 'Wide';
local TIMES = {
    { 'when the settings window opens', reads_file(function () said('/cadence'); end) },
    { 'before each profile command or button', reads_file(press_overwrite)
        and reads_file(function () said('/cadence profile overwrite wide'); end) },
    { 'for `/cadence joblink <job> <profile>` and `/cadence help profiles`',
        reads_file(function () said('/cadence joblink war wide'); end)
        and reads_file(function () said('/cadence help profiles'); end) },
    { 'after a zone when your main job changed and has a link', reads_file(function () change_job(4); end) },
};
for _, time in ipairs(TIMES) do
    check(('profiles.json is read %s, as the guide says'):format(time[1]), time[2] and row:find(time[1], 1, true) ~= nil,
        row);
end
check('and not when the window closes, after a zone with the same job or one with no link, or for joblink none',
    not reads_file(function () said('/cadence'); end) and not reads_file(function () change_job(4); end)
    and not reads_file(function () change_job(5); end)
    and not reads_file(function () said('/cadence joblink war none'); end));
io.open = real_open;
os.remove(FILE);

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
