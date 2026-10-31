-- Drawing faults keep bounded source locations without recording private error text.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local diagnostics = require('core.diagnostics');
local hud = require('ui.hud');
local player = require('core.player');
local json = require('json');
MOCK.now, MOCK.player.status = 100, 1;
MOCK.player.equipment[0], MOCK.items[16535] = 16535, { Delay = 240, Skill = 3 };
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local getinfo, stack_reads = debug.getinfo, 0;
debug.getinfo = function(level, fields)
    stack_reads = stack_reads + 1;
    return getinfo(level + 1, fields);
end;
for _ = 1, 120 do MOCK.frame(1 / 60); end
check('successful frames never inspect the stack', stack_reads == 0);

local draw_attack = hud.draw_attack;
local fault = assert(loadstring([[
return function()
    error('Private Player Z:\\Private Folder\\secret.txt', 0);
end
]], [[@Z:\Users\Private Person\addons\cadence\ui\hud.lua]]))();
local attempts = 0;
hud.draw_attack = function(...)
    attempts = attempts + 1;
    fault(...);
end;
MOCK.frame(1 / 60);
local first = diagnostics.report({});
check('drawing faults are retained with recording off', not first.recording and first.recorded_events == 0
    and first.drawing_error ~= nil and first.drawing_error.value_type == 'string');
local found = false;
for _, frame in ipairs(first.drawing_error.frames) do
    found = found or (frame.source == 'cadence/ui/hud.lua' and frame.line == 2);
end
check('the failing call site is captured before its stack unwinds', found);
local encoded = json.encode(first);
check('saved evidence excludes names absolute paths and raw error text',
    not encoded:find('Private', 1, true) and not encoded:find('secret.txt', 1, true)
    and not encoded:find('Z:', 1, true) and not encoded:find('Users', 1, true));
local messages = #MOCK.printed;
local reads_after_error = stack_reads;
for _ = 1, 10 do MOCK.frame(1 / 60); end
check('drawing stays paused and reports the error once', attempts == 1 and #MOCK.printed == messages
    and stack_reads == reads_after_error);
check('the one-line error gives report and retry commands', MOCK.printed[messages]:find('Private Player', 1, true)
    and MOCK.printed[messages]:find('/cadence report', 1, true) and MOCK.printed[messages]:find('/cadence to try again', 1, true));

local open, saved = io.open, nil;
io.open = function(path, mode)
    if (mode == 'rb') then return nil; end
    return { write = function(self, value) saved = value; return self; end, close = function() return true; end };
end;
MOCK.fire('command', { command = '/cadence report' });
local report = saved and json.decode(saved);
check('the report command saves crash evidence while drawing is paused', report ~= nil
    and report.drawing_error ~= nil and not report.recording and report.snapshot.addon.name == 'cadence');
MOCK.frame(1 / 60);
check('saving a report does not retry drawing', attempts == 1);
MOCK.fire('command', { command = '/cadence record on' });
check('starting timing recording preserves the last drawing fault', diagnostics.report({}).drawing_error ~= nil);

local read_loadout = player.read_loadout;
player.read_loadout = function() error('Private Player snapshot failure'); end;
saved = nil;
MOCK.fire('command', { command = '/cadence report' });
report = saved and json.decode(saved);
check('a broken snapshot dependency cannot prevent saving the fault', report ~= nil
    and report.snapshot.snapshot_unavailable == true and report.drawing_error ~= nil
    and not saved:find('Private', 1, true));
player.read_loadout, io.open = read_loadout, open;

MOCK.fire('command', { command = '/cadence' });
MOCK.frame(1 / 60);
check('an explicit retry captures a fresh fault and pauses again', attempts == 2
    and diagnostics.report({}).drawing_error.at > first.drawing_error.at);
MOCK.frame(1 / 60);
check('a repeated fault still waits for another explicit retry', attempts == 2);
hud.draw_attack = draw_attack;
MOCK.fire('command', { command = '/cadence' });
reads_after_error = stack_reads;
MOCK.frame(1 / 60);
check('a successful retry keeps the evidence without more stack reads', stack_reads == reads_after_error
    and diagnostics.report({}).drawing_error ~= nil);
debug.getinfo = getinfo;

local dynamic = assert(loadstring("return function() error('Private Player') end", 'Private Player dynamic source'))();
xpcall(dynamic, diagnostics.capture_drawing_error);
encoded = json.encode(diagnostics.report({}));
check('dynamic chunk text and names never enter the saved stack', not encoded:find('Private', 1, true)
    and encoded:find('[string]', 1, true));
local external = assert(loadstring("return function() error('private error') end", '@Z:/Private Folder/Private Player.lua'))();
xpcall(external, diagnostics.capture_drawing_error);
encoded = json.encode(diagnostics.report({}));
check('unfamiliar filenames are replaced instead of exposing private paths', not encoded:find('Private', 1, true)
    and encoded:find('[external]', 1, true));
-- Deliberately force the reported Sugar error to verify its library frame survives capture.
local ok = xpcall(function() return math[4.4931404467467e-157]; end, diagnostics.capture_drawing_error);
found = false;
for _, frame in ipairs(diagnostics.report({}).drawing_error.frames) do
    found = found or (frame.source == 'libs/sugar/math.lua' and frame.line > 0);
end
check('a forced native Sugar error retains the library call site', not ok and found);
local deep;
deep = function(n)
    if (n == 0) then error('deep fault'); end
    local result = deep(n - 1);
    return result;
end;
xpcall(function() deep(100); end, diagnostics.capture_drawing_error);
check('a deep failing stack is bounded to 32 frames', #diagnostics.report({}).drawing_error.frames == 32);
diagnostics.reset();
check('character reset clears drawing evidence', diagnostics.report({}).drawing_error == nil);
check('drawing diagnostics send no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
