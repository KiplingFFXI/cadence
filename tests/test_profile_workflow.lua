-- Saved baselines and file recovery are independent from live settings Undo.
addon.name = 'cadence';
local defaults = require('ui.defaults');
local history = require('ui.history');
local layouts = require('ui.layouts');
local profiles = require('ui.profiles');
local json = require('json');
local FILE = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\profiles.json';
local out, failed = {}, 0;
local function check(name, yes)
    out[#out + 1] = (yes and 'ok   ' or 'FAIL ') .. name;
    if (not yes) then failed = failed + 1; end
end
local function read_file()
    local file = assert(io.open(FILE, 'r')); local data = file:read('*a'); file:close(); return data;
end
local function write_file(data)
    local file = assert(io.open(FILE, 'w')); file:write(json.encode(data)); file:close();
end
os.remove(FILE); profiles.refresh();
local s = defaults.make();
local tabs, links = s.window.tabs, s.job_links;
s.attack.width = 333;
check('saving records the active baseline', profiles.save(s, 'Baseline')
    and s.profile_source.kind == 'profile' and s.profile_source.name == 'Baseline');
check('a freshly saved profile is not modified', not profiles.status(s).modified and not profiles.status(s).missing);
local saved = json.decode(read_file()).Baseline;
check('profiles exclude navigation, geometry, job links and their source marker',
    saved.window == nil and saved.job_links == nil and saved.profile_source == nil);

local stable, opens, real_open = profiles.status(s), 0, io.open;
io.open = function(...) opens = opens + 1; return real_open(...); end;
local same = true;
for _ = 1, 100 do if (profiles.status(s) ~= stable) then same = false; end end
io.open = real_open;
check('quiet status reads reuse the result without disk access', same and opens == 0);
s.attack.width = 400; profiles.invalidate_status(s);
check('changed display settings mark the saved baseline modified', profiles.status(s).modified);
s.attack.width = 333; profiles.invalidate_status(s);
check('restoring the saved value clears the modified indicator', not profiles.status(s).modified);
s.window.x, s.window.width, s.window.tabs.Enemy, s.job_links.BLM = 91, 1100, false, 'Baseline';
profiles.invalidate_status(s);
check('window navigation and character job links do not dirty a profile', not profiles.status(s).modified);
s.attack.width = 411;
check('loading restores the saved value rather than a live alias', profiles.load(s, 'Baseline') and s.attack.width == 333);
check('loading preserves character tables and geometry', s.window.tabs == tabs and s.job_links == links
    and s.window.x == 91 and s.window.width == 1100 and s.window.tabs.Enemy == false and links.BLM == 'Baseline');
check('the loaded baseline is clean', not profiles.status(s).modified);

write_file({ Legacy = { attack = { width = 301 }, style = { font_size = 16 } } });
check('older partial profiles load default values as a clean baseline', profiles.load(s, 'Legacy')
    and s.attack.width == 301 and not profiles.status(s).modified and s.resting.show_gains);
local ok, relinked, renamed_source = profiles.rename(s, 'Legacy', 'Renamed');
check('renaming updates baseline identity even without a job link', ok and not relinked and renamed_source
    and s.profile_source.name == 'Renamed' and not profiles.status(s).modified);
local state = history.capture(s);
check('a failed rename leaves the source unchanged', not profiles.rename(s, 'Renamed', 'None') and history.equal(state, s));

local outside = json.decode(read_file()); outside.Renamed.attack.width = 320; write_file(outside);
profiles.refresh();
check('refresh exposes a baseline changed by another window', profiles.status(s).modified);
outside.Renamed = nil; write_file(outside); profiles.refresh();
check('a missing saved baseline remains explicit', profiles.status(s).missing and profiles.status(s).modified);

layouts.apply(s, 'melee'); profiles.mark_layout(s, 'melee');
check('starter layout status has its readable name', profiles.status(s).kind == 'layout'
    and profiles.status(s).label == 'Melee / TP' and not profiles.status(s).modified);
s.attack.x, s.attack.fill_start[1], s.style.font_size = 7, 0.1, 22;
profiles.invalidate_status(s);
check('personal styling does not dirty a starter readout layout', not profiles.status(s).modified);
s.attack.show_tp_hits = false; profiles.invalidate_status(s);
check('changing a starter-owned readout marks it modified', profiles.status(s).modified);
s.profile_source = T{ kind = '', name = '' }; profiles.invalidate_status(s);
check('settings without a known baseline are called custom settings', profiles.status(s).label == 'Custom settings');

os.remove(FILE); profiles.refresh();
s = defaults.make(); s.attack.width = 270;
check('the first save is not an overwrite', profiles.save(s, 'Recover') and not profiles.can_undo_overwrite());
check('an unchanged save does not invent an overwrite from JSON rounding', profiles.save(s, 'Recover')
    and not profiles.can_undo_overwrite());
s.attack.width = 370;
check('a changed overwrite offers its name for recovery', profiles.save(s, 'Recover')
    and profiles.overwritten_name() == 'Recover' and not profiles.status(s).modified);
local current = history.capture(s);
local other = defaults.make(); other.resting.sound = true;
profiles.save(other, 'Other');
ok, state = profiles.undo_overwrite();
local data = json.decode(read_file());
check('undo overwrite restores old disk contents and preserves another profile', ok and state == 'Recover'
    and data.Recover.attack.width == 270 and data.Other.resting.sound);
check('undo overwrite leaves live settings untouched and reports them modified',
    history.equal(current, s) and profiles.status(s).modified and not profiles.can_undo_overwrite());

s.attack.width = 470; profiles.save(s, 'Recover');
data = json.decode(read_file()); data.Recover.attack.width = 570; write_file(data);
ok, state = profiles.undo_overwrite();
check('a newer same-profile write blocks overwrite recovery', not ok and state == 'changed'
    and json.decode(read_file()).Recover.attack.width == 570 and profiles.can_undo_overwrite());
profiles.load(s, 'Recover'); s.attack.width = 580; profiles.save(s, 'Recover');
local bytes = read_file();
MOCK.file_replace_error = true;
ok, state = profiles.undo_overwrite();
MOCK.file_replace_error = nil;
check('a failed overwrite recovery preserves the file and retry entry', not ok and state == 'file'
    and read_file() == bytes and profiles.can_undo_overwrite());
ok, state = profiles.undo_overwrite();
check('overwrite recovery succeeds on retry', ok and state == 'Recover'
    and json.decode(read_file()).Recover.attack.width == 570);

s.job_links.BLM = 'Recover';
profiles.delete(s, 'Recover');
check('existing deletion recovery remains separate', profiles.can_undo_delete()
    and profiles.deleted_name() == 'Recover' and s.job_links.BLM == nil);
s.job_links.BLM = 'Other';
ok, state = profiles.undo_delete(s);
check('deletion recovery still preserves a newer job link', ok and state == 'Recover'
    and s.job_links.BLM == 'Other' and profiles.exists('Recover'));
s.attack.width = 601; profiles.save(s, 'Recover');
local bad = assert(io.open(FILE, 'w')); bad:write('{broken'); bad:close();
ok, state = profiles.undo_overwrite();
check('malformed profile data blocks overwrite recovery', not ok and state == 'file' and read_file() == '{broken');
os.remove(FILE); profiles.refresh();
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
