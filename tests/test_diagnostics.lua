-- Recording is opt-in, bounded and detached from game commands and unrelated packets.
local out, fails = {}, 0;
local function check(name, value)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name;
    if (not value) then fails = fails + 1; end
end
local report = require('core.diagnostics');
report.record('ignored', 0, { hp = 1 });
check('recording starts off and keeps nothing', not report.is_enabled() and report.report({}).recorded_events == 0);
report.enable(true);
local source = { hp = 42, nested = { amount = 3 } };
report.record('vitals', 1, source); source.nested.amount = 99;
check('an event is a snapshot, not a mutable reference', report.report({}).events[1].values.nested.amount == 3);
for i = 2, 300 do report.record('vitals', i, { hp = i }); end
local result = report.report({ version = 'one', delay_key = 'raw-identity', extra = 'raw-extra',
    unknown_sources = { { field = 'store_tp', key = 'raw-identity' } } });
check('internal keys and raw item bytes are excluded', result.snapshot.delay_key == nil and result.snapshot.extra == nil
    and result.snapshot.unknown_sources[1].key == nil and result.snapshot.unknown_sources[1].field == 'store_tp');
check('only the latest256 events remain in order', result.recorded_events == 256 and result.events[1].at == 45 and result.events[256].at == 300);
result.events[1].values.hp = 0;
check('reading a report does not change saved evidence', report.report({}).events[1].values.hp == 45);
report.enable(false); report.record('ignored', 400, {});
check('turning it off keeps the last report without recording more', report.report({}).recorded_events == 256);
report.enable(true);
check('new recording starts a fresh session', report.report({}).recorded_events == 0);
local open, remove = io.open, os.remove;
local written = {};
io.open = function(path, mode)
    if (mode == 'rb') then return written[path] and { close = function() return true; end } or nil; end
    return { write = function(self, value) written[path] = value; return self; end, close = function() return true; end };
end;
local first = report.save({ model = { store_tp = 46 } });
local second = report.save({ model = { store_tp = 45 } });
check('same-second exports keep separate files', first ~= nil and second ~= nil and first ~= second);
check('report is valid JSON with the supplied model', require('json').decode(written[first]).snapshot.model.store_tp == 46);
local source_maps = {
    buffs = { [253] = true, [251] = true }, equipment = { [0] = { id = 17559 }, [13] = { id = 15543 } },
    merits = { [1092] = 5 }, sparse = { [1] = 'first', [3] = 'third' },
    mixed = { [1] = 'numeric', ['1'] = 'string', ['[1]'] = 'bracketed', label = 'mixed' },
    rows = { { amount = 31 }, { amount = 35 } }, filtered = { 1, math.huge, 3 },
};
report.record('maps', 1, source_maps);
local maps_path = report.save(source_maps);
local maps = maps_path and require('json').decode(written[maps_path]);
check('real JSON accepts sparse buff equipment and merit maps', maps ~= nil
    and maps.snapshot.buffs['253'] == true and maps.snapshot.equipment['0'].id == 17559
    and maps.snapshot.equipment['13'].id == 15543 and maps.snapshot.merits['1092'] == 5);
check('dense arrays keep their order and sparse arrays keep their ids', maps ~= nil
    and #maps.snapshot.rows == 2 and maps.snapshot.rows[2].amount == 35
    and maps.snapshot.sparse['1'] == 'first' and maps.snapshot.sparse['3'] == 'third'
    and maps.snapshot.filtered['1'] == 1 and maps.snapshot.filtered['3'] == 3);
check('numeric and string key collisions preserve all values', maps ~= nil
    and maps.snapshot.mixed['1'] == 'string' and maps.snapshot.mixed['[1]'] == 'bracketed'
    and maps.snapshot.mixed['[[1]]'] == 'numeric' and maps.snapshot.mixed.label == 'mixed');
check('recorded maps round trip without changing source keys', maps ~= nil and maps.recorded_events == 1
    and maps.events[1].values.equipment['0'].id == 17559 and source_maps.equipment[0].id == 17559
    and source_maps.equipment['0'] == nil);
local create_dir, exists = ashita.fs.create_dir, ashita.fs.exists;
ashita.fs.create_dir = function() return false; end;
ashita.fs.exists = function() return false; end;
local path, problem = report.save({});
check('directory creation failure reports the folder problem', path == nil
    and problem == 'The reports folder could not be opened.');
ashita.fs.exists = function() return true; end;
check('an existing reports folder accepts a false create result', report.save({}) ~= nil);
ashita.fs.create_dir = function() error('denied'); end;
check('a directory error is contained', report.save({}) == nil);
ashita.fs.create_dir, ashita.fs.exists = create_dir, exists;
io.open = function() return nil; end;
check('unwritable reports fail without throwing', report.save({}) == nil);
io.open, os.remove = open, remove;
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
MOCK.fire('command', { command = '/cadence record on' });
MOCK.fire('packet_in', { id = 0x017, data = 'unrelated chat secret', size = 30 });
check('unrelated chat is never recorded', not require('json').encode(report.report({})):find('unrelated chat secret', 1, true));
check('record command enables the saved setting', MOCK.settings.current.style.record_diagnostics == true);
check('recording sends no game commands', #MOCK.commands == 0);
MOCK.player.status, MOCK.player.buffs = 33, { 253, 251 };
MOCK.player.equipment[0], MOCK.player.equipment[13] = 17559, 15543;
MOCK.items[17559] = { Delay = 366, Skill = 12 };
MOCK.frame(0.3);
local command_json;
io.open = function(path, mode)
    if (mode == 'rb') then return nil; end;
    return { write = function(self, value) command_json = value; return self; end,
        close = function() return true; end };
end;
MOCK.fire('command', { command = '/cadence report' });
io.open = open;
local command_report = command_json and require('json').decode(command_json);
check('the actual report command saves live-shaped character inputs', command_report ~= nil
    and command_report.snapshot.loadout.buffs['253'] == true
    and command_report.snapshot.loadout.equipment[1].slot == 0
    and command_report.snapshot.loadout.equipment[1].id == 17559
    and command_report.snapshot.loadout.equipment[2].slot == 13
    and command_report.snapshot.loadout.equipment[2].id == 15543
    and MOCK.printed[#MOCK.printed]:find('Timing report saved to ', 1, true));
report.reset();
check('character reset clears prior evidence', report.report({}).recorded_events == 0);
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
