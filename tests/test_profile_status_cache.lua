-- Saved baselines are reused while editing and refreshed when another window changes the file.
addon.name = 'cadence';
local defaults, history, profiles = require('ui.defaults'), require('ui.history'), require('ui.profiles');
local json = require('json');
local FILE = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\profiles.json';
local out, fails = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then fails = fails + 1; end
end
local function read_file()
    local f = assert(io.open(FILE, 'r')); local data = json.decode(f:read('*a')); f:close(); return data;
end
local function write_file(data)
    local f = assert(io.open(FILE, 'w')); f:write(json.encode(data)); f:close();
end
os.remove(FILE); profiles.refresh();
local s = defaults.make();
s.attack.width = 260;
s.attack.future_choice = 'left alone';
check('saving starts with a clean baseline', profiles.save(s, 'Cache') and not profiles.status(s).modified);
s.attack.future_choice = 'still left alone'; profiles.invalidate_status(s);
check('unknown section keys retain the same comparison scope as profile loading', not profiles.status(s).modified);
local original = history.capture(s);
local opened, real_open = 0, io.open;
io.open = function (...) opened = opened + 1; return real_open(...); end;
collectgarbage('collect'); collectgarbage('stop');
local before, every_modified = collectgarbage('count'), true;
for i = 1, 100 do
    s.attack.width = 300 + i;
    profiles.invalidate_status(s);
    if (not profiles.status(s).modified) then every_modified = false; end
end
local allocated = collectgarbage('count') - before;
collectgarbage('restart');
io.open = real_open;
check('changed settings are compared without reading the file again', every_modified and opened == 0);
check('editing a saved profile keeps allocation below 40 KiB per update', allocated < 4000, ('%.1f KiB/update'):format(allocated / 100));
s.attack.width = 260; profiles.invalidate_status(s);
check('restoring the saved setting clears Modified without disturbing other values',
    not profiles.status(s).modified and history.equal(s, original));
local other = defaults.make();
other.profile_source = T{ kind = 'profile', name = 'Cache' }; other.attack.width = 260;
check('another owner can share the saved baseline without sharing current settings', not profiles.status(other).modified);
other.attack.width = 280; profiles.invalidate_status(other);
check('one owner changing does not dirty another owner', profiles.status(other).modified and not profiles.status(s).modified);
local external = read_file(); external.Cache.attack.width = 420; write_file(external); profiles.refresh();
check('a fresh disk read invalidates both owners baseline views', profiles.status(s).modified and profiles.status(other).modified);
check('loading the external edit is clean and leaves unknown section keys alone', profiles.load(s, 'Cache')
    and s.attack.width == 420 and s.attack.future_choice == 'still left alone' and not profiles.status(s).modified);
s.attack.width = 430; check('a local overwrite replaces the cached baseline', profiles.save(s, 'Cache') and not profiles.status(s).modified);
check('undo overwrite restores the disk baseline without restoring live settings', profiles.undo_overwrite()
    and s.attack.width == 430 and profiles.status(s).modified);
MOCK.file_replace_error = true;
local failed_save = not profiles.save(s, 'Cache');
MOCK.file_replace_error = nil;
check('failed overwrite keeps the restored disk baseline', failed_save and read_file().Cache.attack.width == 420
    and profiles.status(s).modified);
profiles.delete(s, 'Cache');
check('deletion cannot leave a cached profile looking present', profiles.status(s).missing and profiles.status(s).modified);
profiles.undo_delete(s);
check('deletion recovery rebuilds the restored baseline', not profiles.status(s).missing and profiles.status(s).modified);
s.attack.width = 420; profiles.invalidate_status(s);
check('restoring its value makes the recovered baseline clean', not profiles.status(s).modified);
local f = assert(io.open(FILE, 'w')); f:write('{broken'); f:close(); profiles.refresh();
check('unreadable storage cannot reuse a clean cached baseline', profiles.status(s).missing and profiles.status(s).modified);
os.remove(FILE); profiles.refresh();
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
