-- Interrupted edits must reach the correct file and history before their owner changes.
local out, fails = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then fails = fails + 1; end
end
local root = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\';
local FILE = root .. 'shared_layout.json';
os.remove(FILE); os.remove(root .. 'profiles.json');
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.watch_settings(); MOCK.fire('load');
local window, history, defaults = require('ui.settings_window'), require('ui.history'), require('ui.defaults');
local json, imgui, settings = require('json'), require('imgui'), require('settings');
local own_written, real_save = {}, settings.save;
settings.save = function ()
    own_written[settings.current] = history.capture(settings.current);
    return real_save();
end;
local function command(words) MOCK.fire('command', { command = '/cadence' .. (words ~= '' and (' ' .. words) or '') }); end
local function disk()
    local file = io.open(FILE, 'r'); if (not file) then return nil; end
    local value = json.decode(file:read('*a')); file:close(); return value.settings;
end
local function held_scale(value)
    local draw = window.draw;
    window.set_open(true);
    window.draw = function (s) s.style.scale = value; return { changed = true, save = false, label = 'Scale' }; end;
    MOCK.frame();
    window.draw = draw;
end
local own = settings.current;
local saves = MOCK.saved;
held_scale(1.25);
check('a held edit has not saved or entered history yet', MOCK.saved == saves and history.status(own) == nil);
command('');
check('closing by command saves the pending own edit once', not window.is_open() and MOCK.saved == saves + 1
    and own_written[own] and own_written[own].style.scale == 1.25);
check('closing by command records the entire edit', history.status(own) == 'Scale');
command('undo');
check('one Undo restores the value before the held edit', own.style.scale == 1 and history.status(own) == nil);

command('onelayout on');
local shared = MOCK.in_use;
saves = MOCK.saved;
held_scale(1.5); command(''); MOCK.frame();
check('closing a shared edit persists it before the idle fast return', disk().style.scale == 1.5
    and shared.style.scale == 1.5 and history.status(shared) == 'Scale');
check('saving a shared edit does not overwrite this character layout', MOCK.saved == saves and own.style.scale == 1);
command('undo');
check('the interrupted shared edit can be undone once', disk().style.scale == 1 and history.status(shared) == nil);

held_scale(1.6);
rawset(imgui, 'Begin', function (name, opened)
    if (name == 'cadence##cadence_settings') then opened[1] = false; return false; end
    return true;
end);
MOCK.frame();
rawset(imgui, 'Begin', nil);
check('closing with the title-bar X also persists the pending edit', not window.is_open()
    and disk().style.scale == 1.6 and history.status(shared) == 'Scale');
command('undo');
check('title-bar close records just one edit', shared.style.scale == 1 and history.status(shared) == nil);

-- The shared save failed before the own visibility table could be written.
saves = MOCK.saved;
MOCK.file_replace_error = true;
command('tab details off');
MOCK.file_replace_error = nil;
check('a failed shared save leaves the old file and pending own choice', disk().window.tabs == nil
    and not own.window.tabs.Details and MOCK.saved == saves);
command('tab details off');
check('a same-value retry still persists the character-owned change', MOCK.saved == saves + 1
    and own_written[own] and not own_written[own].window.tabs.Details);
command('undo');
check('retrying creates no duplicate Undo entry and restores the own table', own.window.tabs.Details
    and own_written[own].window.tabs.Details and shared.window.tabs == own.window.tabs and history.status(shared) == nil);

-- A failed automatic flush remains retryable when the user closes again.
held_scale(1.7);
MOCK.file_replace_error = true; command(''); MOCK.file_replace_error = nil;
check('failed close keeps the previous shared file', disk().style.scale == 1);
command(''); command('');
check('a later close retries the unfinished save', disk().style.scale == 1.7);
command('undo');
check('failed-close retry remains one history entry', shared.style.scale == 1 and history.status(shared) == nil);

held_scale(1.8);
command('onelayout off');
check('turning sharing off flushes the pending edit before replacing its owner', MOCK.in_use == own
    and own.style.scale == 1.8 and own_written[own].style.scale == 1.8 and disk() == nil);
check('changing layout owner clears the old history', history.status(own) == nil);
held_scale(1.9);
command('onelayout on');
shared = MOCK.in_use;
check('turning sharing on saves the pending own edit before copying it', own_written[own].style.scale == 1.9
    and shared ~= own and disk().style.scale == 1.9 and history.status(shared) == nil);

-- The settings library already changed its current owner before the login callback.
held_scale(2.0);
local next_character = defaults.make();
next_character.window.tabs.Enemy = false;
local saves_before_login = MOCK.saved;
settings.switch_character(next_character);
check('a login preserves the previous pending shared edit', disk().style.scale == 2.0 and MOCK.in_use.style.scale == 2.0);
check('login does not save old settings into the new character', MOCK.saved == saves_before_login
    and own_written[next_character] == nil and next_character.style.scale == 1 and not next_character.window.tabs.Enemy);
check('login rebinds owned tables and drops the previous edit history', MOCK.in_use.window.tabs == next_character.window.tabs
    and MOCK.in_use.job_links == next_character.job_links and history.status(MOCK.in_use) == nil);

-- A failed shared write must survive another login without carrying character-owned choices.
shared = MOCK.in_use;
command('attack width 310');
check('there is an earlier edit to clear before a failed login save', history.status(shared) ~= nil);
next_character.job_links['WAR'] = 'Previous';
next_character.window.tabs.Profiles = false;
held_scale(2.2);
local third_character = defaults.make();
third_character.window.tabs.Details = false;
third_character.job_links['MNK'] = 'Third';
saves_before_login = MOCK.saved;
MOCK.file_replace_error = true;
settings.switch_character(third_character);
check('a failed login save keeps the pending shared display and previous disk copy', MOCK.in_use == shared
    and MOCK.in_use.style.scale == 2.2 and disk().style.scale == 2.0);
check('a failed login save rebinds only the new character choices', MOCK.in_use.window.tabs == third_character.window.tabs
    and MOCK.in_use.job_links == third_character.job_links and MOCK.in_use.window.tabs.Profiles
    and not MOCK.in_use.window.tabs.Details and MOCK.in_use.job_links['WAR'] == nil);
check('a failed login save clears old history without writing the new character file', history.status(MOCK.in_use) == nil
    and MOCK.saved == saves_before_login and own_written[third_character] == nil and third_character.style.scale == 1);

local fourth_character = defaults.make();
fourth_character.window.tabs.Preview = false;
fourth_character.job_links['WHM'] = 'Fourth';
settings.switch_character(fourth_character);
check('another failed switch still keeps the pending display', MOCK.in_use == shared
    and MOCK.in_use.style.scale == 2.2 and disk().style.scale == 2.0);
check('every failed switch uses its own character tables and drops old history', MOCK.in_use.window.tabs == fourth_character.window.tabs
    and MOCK.in_use.job_links == fourth_character.job_links and MOCK.in_use.window.tabs.Details
    and not MOCK.in_use.window.tabs.Preview and MOCK.in_use.job_links['MNK'] == nil and history.status(MOCK.in_use) == nil);
MOCK.file_replace_error = nil;
command('');
check('closing retries the shared write after failed switches', disk().style.scale == 2.2
    and MOCK.in_use.style.scale == 2.2 and history.status(MOCK.in_use) == nil);
check('retrying the retained shared edit never writes another character layout', MOCK.saved == saves_before_login
    and own_written[third_character] == nil and own_written[fourth_character] == nil and fourth_character.style.scale == 1);
command('tab enemy off');
check('the next owned edit saves only the current character choices', own_written[fourth_character]
    and not own_written[fourth_character].window.tabs.Enemy and own_written[fourth_character].job_links['WHM'] == 'Fourth'
    and own_written[fourth_character].job_links['WAR'] == nil and own_written[fourth_character].job_links['MNK'] == nil
    and own_written[third_character] == nil and not next_character.window.tabs.Profiles
    and third_character.window.tabs.Enemy);
next_character = fourth_character;

held_scale(2.1);
MOCK.fire('unload');
check('unload flushes a pending shared edit', disk().style.scale == 2.1);
check('unload saves only the current character own layout', own_written[next_character]
    and own_written[next_character].style.scale == 1 and not own_written[next_character].window.tabs.Enemy);
check('pending-save handling issues no game commands', #MOCK.commands == 0);
settings.save = real_save;
os.remove(FILE); os.remove(root .. 'profiles.json');
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
