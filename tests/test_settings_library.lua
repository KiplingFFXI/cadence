-- Exercise the installed settings and Sugar libraries against files in the runner's temporary install.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local mock_ffi = package.loaded.ffi;
package.loaded.ffi = nil;
local native_ffi = require('ffi');
package.loaded.ffi = mock_ffi;
if (native_ffi.os ~= 'Windows') then return 'Skipped: the installed settings library uses Windows paths.'; end
native_ffi.cdef('int __stdcall CreateDirectoryA(const char*, void*);');
local root = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\';
for _, directory in ipairs({ 'defaults', 'Alice_1001', 'Bob_1002' }) do
    native_ffi.C.CreateDirectoryA(root .. directory, nil);
    os.remove(root .. directory .. '\\settings.lua');
end
os.remove(root .. 'shared_layout.json');
local function write(directory, values)
    local file = assert(io.open(root .. directory .. '\\settings.lua', 'w'));
    file:write("require('common');\nreturn T", values, ';\n'); file:close();
end

package.loaded.common, package.preload.common = nil, nil;
package.loaded.settings, package.preload.settings = nil, nil;
require('common');
local get_memory = AshitaCore.GetMemoryManager;
AshitaCore.GetMemoryManager = function (...)
    local memory = get_memory(...);
    local get_player = memory.GetPlayer;
    memory.GetPlayer = function (...)
        local player = get_player(...);
        player.GetLoginStatus = function () return 0; end;
        return player;
    end;
    return memory;
end;
ashita.fs.exists = function (path)
    local file = io.open(path, 'rb');
    if (file) then file:close(); return true; end
    return false;
end;
local unpack = struct.unpack;
struct.unpack = function (format, data, offset)
    if (format == 'c16') then return data:sub(offset, offset + 15); end
    return unpack(format, data, offset);
end;
local function native(fields)
    local event = newproxy(true);
    getmetatable(event).__index = function (_, key) return fields[key]; end;
    getmetatable(event).__newindex = function (_, key, value) fields[key] = value; end;
    return event;
end
local function login(name, id)
    local packet = MOCK.zone_packet(id);
    packet.data = packet.data:sub(1, 132) .. name .. string.rep('\0', 16 - #name) .. packet.data:sub(149);
    MOCK.fire('packet_in', native(packet));
end

write('defaults', "{attack=42,style=T{panel_color=false,scale=1.75,detail_color=T{0.2,0.3,0.4}},window=T{tabs='wrong'},own_extra='keep'}");
local loaded, err = pcall(dofile, ADDON_DIR .. '/cadence.lua');
check('serializable wrong section, color and tab types do not abort loading', loaded);
if (not loaded) then out[#out + 1] = tostring(err); out[#out + 1] = failed .. ' FAILED'; return table.concat(out, '\n'); end
MOCK.fire('load');
local settings, defaults = require('settings'), require('ui.defaults');
local own = settings.get();
check('startup validation repairs only invalid fields', type(own.attack) == 'table'
    and type(own.style.panel_color) == 'table' and type(own.window.tabs) == 'table'
    and own.style.scale == 1.75 and own.own_extra == 'keep');
check('filling a missing alpha preserves valid saved RGB values', own.style.detail_color[1] == 0.2
    and own.style.detail_color[2] == 0.3 and own.style.detail_color[3] == 0.4
    and own.style.detail_color[4] == defaults.make().style.detail_color[4]);
MOCK.fire('command', native({command='/cadence attack off'}));
check('commands keep the exact table cached by the real settings library', settings.get() == own and not own.attack.enabled);
local persisted = assert(loadfile(root .. 'defaults\\settings.lua'))();
check('the actual settings writer saves repaired fields and valid values', type(persisted.attack) == 'table'
    and not persisted.attack.enabled and persisted.style.scale == 1.75 and persisted.own_extra == 'keep');

write('Alice_1001', "{resting='wrong',attack=T{width=333},style=T{scale=1.6},own_extra='Alice value'}");
login('Alice', 1001);
local alice = settings.get();
check('a real settings login callback repairs a malformed section and fills a partial file', alice ~= own
    and type(alice.resting) == 'table' and alice.attack.width == 333 and alice.style.scale == 1.6
    and alice.own_extra == 'Alice value');
alice.attack.fill_start[1] = 0.123;
settings.save();
-- The settings library changes owners only after a logout or a new logged-in session.
settings.logged_in = false;
login('Bob', 1002);
local bob, fresh = settings.get(), defaults.make();
check('a new character receives fresh defaults without references to the previous character', bob ~= alice
    and bob.style.scale == fresh.style.scale and bob.attack.width == fresh.attack.width
    and bob.attack.fill_start ~= alice.attack.fill_start and bob.attack.fill_start[1] == fresh.attack.fill_start[1]);
check('retained library defaults contain no mutable cadence tables', next(settings.cache.settings.defaults) == nil);

write('Bob_1002', "{enemy=7,style=T{detail_color='wrong',scale=1.25},own_extra=T{value='keep'}}");
check('real settings reload completes', settings.reload());
bob = settings.get();
check('reload validates replacement settings and preserves unrelated values', type(bob.enemy) == 'table'
    and type(bob.style.detail_color) == 'table' and bob.style.scale == 1.25 and bob.own_extra.value == 'keep');
MOCK.fire('command', native({command='/cadence'})); MOCK.frame();
local drawing_error = false;
for _, line in ipairs(MOCK.printed) do drawing_error = drawing_error or line:find('Drawing stopped', 1, true) ~= nil; end
check('repaired settings reach the rendered settings window', not drawing_error);
check('real library reset restores cadence defaults through its callback', settings.reset()
    and settings.get().style.scale == fresh.style.scale and settings.get().own_extra == nil);
check('settings loading and validation issue no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
