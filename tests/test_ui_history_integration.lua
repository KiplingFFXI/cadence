-- Settings actions keep one history across commands, completed edits and shared layouts.
local out, fails = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then fails = fails + 1; end
end
local root = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\';
os.remove(root .. 'shared_layout.json');
os.remove(root .. 'profiles.json');
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.watch_settings();
MOCK.fire('load');
local history, profiles = require('ui.history'), require('ui.profiles');
local window, defaults = require('ui.settings_window'), require('ui.defaults');
local json = require('json');
local function command(words) MOCK.fire('command', { command = '/cadence ' .. words }); end
local function current() return MOCK.in_use; end
local s = current();
local initial = s.attack.show_tp;
command('attack tp off');
command('attack delay off');
command('undo');
check('ordinary command Undo keeps the earlier edit', not s.attack.show_tp and s.attack.show_delay);
command('undo');
check('a second Undo restores the first edit', s.attack.show_tp == initial and history.status(s) == nil);
command('attack tp on');
check('repeating the current value creates no history entry', history.status(s) == nil);

-- A slider applies every frame but saves and enters history only when released.
window.set_open(true);
local real_draw, step = window.draw, 0;
local scale, saves = s.style.scale, MOCK.saved;
window.draw = function (settings)
    step = step + 1;
    if (step <= 4) then
        settings.style.scale = scale + step / 10;
        return { changed = true, save = false, label = 'Scale' };
    end
    return { save = step == 5, label = 'Scale' };
end;
for _ = 1, 4 do MOCK.frame(); end
check('held edits apply without repeated saves or history copies', MOCK.saved == saves and history.status(s) == nil);
MOCK.frame();
check('release saves once and records the edit', MOCK.saved == saves + 1 and history.status(s) == 'Scale');
command('undo');
check('Undo restores the value before the entire drag', s.style.scale == scale and history.status(s) == nil);
window.draw = real_draw;
window.set_open(false);

command('skin mint');
command('attack width 320');
command('attack labeltext Swing');
s.attack.x, s.attack.y = 91, 92;
command('shadow on');
local look = history.copy(s.style);
local before = history.capture(s);
local count = MOCK.saved;
command('layout preview resting');
check('starter preview does not change or save settings', history.equal(s, before) and MOCK.saved == count);
command('layout resting');
check('applying a starter layout keeps the look and timer geometry', history.equal(s.style, look)
    and s.attack.x == 91 and s.attack.y == 92 and s.attack.width == 320 and s.attack.label_text == 'Swing');
check('starter layout reports its active source', profiles.status(s).kind == 'layout' and not profiles.status(s).modified);
command('resting gains off');
check('changing a starter readout reports Modified', profiles.status(s).modified);
command('undo');
check('Undo restores the starter indicator', not profiles.status(s).modified);
command('undo');
check('Undo restores the display choices before applying a layout', s.attack.enabled == before.attack.enabled
    and s.resting.show_gains == before.resting.show_gains and s.profile_source.kind == before.profile_source.kind);
window.set_open(false);
command('resetsection attack');
check('scoped reset preserves the timer name, position and other sections', s.attack.label_text == 'Swing'
    and s.attack.x == 91 and s.attack.y == 92 and s.attack.width == defaults.make().attack.width
    and history.equal(s.resting, before.resting));
command('undo');
check('scoped reset can be undone', s.attack.width == 320);

command('profile save Integration');
check('profile save persists its baseline', s.profile_source.name == 'Integration' and not profiles.status(s).modified);
command('attack width 340');
command('profile overwrite Integration');
local state = history.capture(s);
command('profile undooverwrite');
check('Undo overwrite changes the saved profile without changing current settings', history.equal(s, state)
    and profiles.status(s).modified and profiles.overwritten_name() == nil);
command('profile load Integration');
check('loading the restored profile uses the previous saved width', s.attack.width == 320);
command('profile rename Integration Renamed');
check('renaming the active profile updates its indicator', s.profile_source.name == 'Renamed'
    and profiles.status(s).label == 'Renamed' and not profiles.status(s).missing);

command('tab enemy off');
command('joblink WAR Renamed');
command('onelayout on');
s = current();
local own = MOCK.settings.current;
check('shared layouts keep character-owned tabs and job links by reference', s ~= own
    and s.window.tabs == own.window.tabs and s.job_links == own.job_links);
check('switching settings owners clears old Undo', history.status(s) == nil);
local own_look = history.copy(own.style);
local own_saves = MOCK.saved;
command('tab details off');
check('hiding a tab while shared persists the character choice', not own.window.tabs.Details and MOCK.saved == own_saves + 1);
command('undo');
check('Undo preserves tab-table ownership and persists the restored choice', own.window.tabs.Details
    and s.window.tabs == own.window.tabs and MOCK.saved == own_saves + 2 and history.equal(own.style, own_look));
local file = assert(io.open(root .. 'shared_layout.json', 'r'));
local shared = json.decode(file:read('*a')); file:close();
check('shared storage excludes tab choices and job links', shared.settings.window.tabs == nil and shared.settings.job_links == nil);
command('profile load Renamed');
check('profiles preserve hidden tabs and job-link ownership', not s.window.tabs.Enemy
    and s.window.tabs == own.window.tabs and s.job_links == own.job_links and own.job_links.WAR == 'Renamed');
command('tab appearance off');
check('Appearance cannot be hidden', s.window.tabs.Appearance);
command('tabs all');
check('Restore all tabs leaves job links in place', s.window.tabs.Enemy and s.job_links.WAR == 'Renamed');
command('resetsection profiles');
check('resetting job links while shared persists an empty character map', next(own.job_links) == nil);
command('undo');
check('Undo restores job links in the same owned table', s.job_links == own.job_links and own.job_links.WAR == 'Renamed');
local next_character = defaults.make();
next_character.window.tabs.Preview = false;
MOCK.settings.switch_character(next_character);
s = current();
check('a new character keeps their own visibility while sharing', not s.window.tabs.Preview and s.window.tabs.Enemy);
check('character switches clear settings history', history.status(s) == nil);
command('onelayout off');
command('attack width 330');
command('reset all'); command('reset all');
check('Reset all clears the history and restores tab visibility', history.status(current()) == nil and current().window.tabs.Preview);
check('UI changes issue no game commands', #MOCK.commands == 0);
os.remove(root .. 'profiles.json');
os.remove(root .. 'shared_layout.json');
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
