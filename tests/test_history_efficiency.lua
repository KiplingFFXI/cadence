-- Undo history records changed values without copying paths for every unchanged setting.
local defaults, history = require('ui.defaults'), require('ui.history');
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. detail) or '');
    if (not ok) then failed = failed + 1; end
end
local s = defaults.make();
local before = history.capture(s);
s.resting.height_scale = 0.75;
for _ = 1, 10 do history.record(s, before, 'Timer height'); end
if (jit) then jit.off(); end
collectgarbage('collect'); collectgarbage('stop');
local started = collectgarbage('count');
for _ = 1, 200 do history.record(s, before, 'Timer height'); end
local bytes = (collectgarbage('count') - started) * 1024 / 200;
collectgarbage('restart');
check('recording a one-field edit stays below4KiB', bytes < 4096, ('%.1f bytes per edit'):format(bytes));
check('height Undo restores the original setting', history.undo(s) and s.resting.height_scale == 1);

history.clear(s);
s.extra = { nested = { first = 3, deleted = { value = 7 } }, second = { keep = false } };
before = history.capture(s);
local nested, second, colors = s.extra.nested, s.extra.second, s.attack.fill_start;
s.extra.nested.first, s.extra.nested.deleted = 9, nil;
s.extra.second.keep, s.extra.second.added = true, { enabled = true };
s.attack.fill_start[2] = 0.123;
s.resting.height_scale = 0.8;
s.window.x = 400;
check('one grouped edit records multiple independent branches', history.record(s, before, 'Grouped edit'));
local ok, label = history.undo(s);
check('each changed branch is restored to its own path', ok and label == 'Grouped edit'
    and s.extra.nested.first == 3 and s.extra.nested.deleted.value == 7
    and not s.extra.second.keep and s.extra.second.added == nil
    and s.attack.fill_start[2] == before.attack.fill_start[2] and s.resting.height_scale == 1);
check('existing tables and current window geometry are preserved', s.extra.nested == nested
    and s.extra.second == second and s.attack.fill_start == colors and s.window.x == 400);
s.extra.nested.deleted.value = 99;
check('restored tables cannot modify the original snapshot', before.extra.nested.deleted.value == 7);

history.clear(s);
before = history.capture(s);
s.extra.nested = false;
s.extra.second = 'replacement';
s.added_section = { value = 1 };
history.record(s, before, 'Replace sections');
history.undo(s);
check('table replacements and new root sections undo independently',
    history.equal(s.extra, before.extra) and s.added_section == nil);
local patch = { attack = { height_scale = 1 }, resting = { width = 240 } };
s.attack.height_scale, s.resting.width, s.resting.show_ticks = 0.6, 300, true;
history.record_patch(s, patch, 'Layout');
history.undo(s);
check('partial snapshots leave unrelated new values alone', s.attack.height_scale == 1
    and s.resting.width == 240 and s.resting.show_ticks and s.extra ~= nil);
history.clear(s);
before = history.capture(s);
check('unchanged full snapshots still create no Undo entry', not history.record(s, before, 'No change')
    and history.status(s) == nil);
check('recording history never changes its input snapshot', history.equal(before, s));
out[#out + 1] = failed == 0 and 'ALL PASSED' or failed .. ' FAILED';
return table.concat(out, '\n');
