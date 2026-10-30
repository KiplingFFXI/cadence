-- A competing save must retry against the latest file, without replacing another window's work.
addon.name = 'cadence';
local defaults = require('ui.defaults');
local profiles = require('ui.profiles');
local store = require('core.file_store');
local json = require('json');
local file = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\profiles.json';
local out, failed = {}, 0;
local function check(name, yes)
    out[#out + 1] = (yes and 'ok   ' or 'FAIL ') .. name;
    if (not yes) then failed = failed + 1; end
end
local function contents()
    local input = assert(io.open(file, 'r')); local text = input:read('*a'); input:close();
    return json.decode(text);
end
os.remove(file); profiles.refresh();
local first, second = defaults.make(), defaults.make();
first.attack.width, second.attack.width = 311, 411;
local write, attempted, competing, reason = store.write, false;
store.write = function (...)
    if (not attempted) then
        attempted = true;
        competing, reason = profiles.save(second, 'Second', true);
    end
    return write(...);
end;
check('first transaction saves while holding the lock', profiles.save(first, 'First', true));
store.write = write;
check('overlapping transaction returns busy without waiting', competing == false and reason == 'busy');
check('retry preserves both distinct profiles', profiles.save(second, 'Second', true)
    and contents().First.attack.width == 311 and contents().Second.attack.width == 411);
second.attack.width = 511;
local ok, problem = profiles.save(second, 'fIrSt', true);
check('save as new rechecks case-insensitive collisions inside the lock', not ok and problem == 'exists'
    and contents().First.attack.width == 311 and profiles.problem():find('already exists', 1, true));
check('explicit overwrite remains available', profiles.save(second, 'First') and contents().First.attack.width == 511);
first.job_links.BLM = 'First';
MOCK.file_lock_error = true;
ok, problem = profiles.rename(first, 'First', 'Renamed');
check('busy rename preserves the file and job links', not ok and problem == 'busy'
    and first.job_links.BLM == 'First' and contents().First ~= nil and contents().Renamed == nil);
ok, problem = profiles.delete(first, 'First');
check('busy delete preserves the profile', not ok and problem == 'busy' and contents().First ~= nil);
ok, problem = profiles.undo_overwrite();
check('busy undo retains its recovery entry', not ok and problem == 'busy' and profiles.can_undo_overwrite());
MOCK.file_lock_error = nil;
check('retrying undo restores only the overwritten profile', profiles.undo_overwrite()
    and contents().First.attack.width == 311 and contents().Second.attack.width == 411);
ok, problem = store.with_lock(file, function () error('simulated transaction error'); end);
check('transaction exception releases the lock', not ok and problem == 'file'
    and store.with_lock(file, function () return true; end));

-- Use real Windows handles too: the in-memory mock alone cannot validate OS exclusion.
package.loaded.ffi, package.loaded['core.file_store'] = nil, nil;
local ffi = require('ffi');
if (ffi.os == 'Windows') then
    local native = require('core.file_store');
    local lock_path = file .. '.native-test';
    local blocked, why;
    check('native Windows handle opens successfully', native.with_lock(lock_path, function ()
        blocked, why = native.with_lock(lock_path, function () error('must not run'); end);
        return true;
    end));
    check('native handle denies a competing transaction', blocked == false and why == 'busy');
    check('native lock can be acquired after release', native.with_lock(lock_path, function () return true; end));
    ok, problem = native.with_lock(lock_path, function () error('native callback failure'); end);
    check('native callback error closes the handle', not ok and problem == 'file'
        and native.with_lock(lock_path, function () return true; end));
    os.remove(lock_path .. '.lock');
end
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
