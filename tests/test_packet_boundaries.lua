-- Malformed packets never reach missing fields or contribute partial observations.
local out, failed = {}, 0;
local function check(name, value)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name;
    if (not value) then failed = failed + 1; end
end
local read_bits = ashita.bits.unpack_be;
ashita.bits.unpack_be = function (data, start, offset, count)
    assert(data ~= nil and offset + count <= data.n * 8, 'read beyond action body');
    return read_bits(data, start, offset, count);
end;
local read_struct = struct.unpack;
struct.unpack = function (format, data, at)
    local size = format == 'L' and 4 or 2;
    assert(at + size - 1 <= #data, 'read beyond fixed packet body');
    return read_struct(format, data, at);
end;
local packets = require('core.packets');
local MOB = 0x01000200;
local normal = MOCK.action_packet(1001, 1, 0, MOB, { { message = 1, damage = 55, reaction = 63 } });
local readers = { 'action_header', 'action_param', 'action_target', 'action_messages',
    'melee_hits', 'action_results', 'action_has_target' };
for size = 0, 38 do
    local event = { id = 0x028, data = normal.data:sub(1, size), data_raw = normal.data_raw, size = size };
    local safe = not packets.valid(event);
    for _, name in ipairs(readers) do
        local argument = name == 'action_has_target' and MOB or {};
        safe = safe and pcall(packets[name], event, argument);
    end
    check('all action readers reject ' .. size .. ' bytes safely', safe);
end
check('complete counter action remains valid', packets.valid(normal));
local hits, counter, plain = packets.melee_hits(normal);
check('valid hit and counter retain their semantics', hits == 1 and counter and plain);
local rows = {};
packets.action_results(normal, rows);
check('counter reactions expose their own message and amount', rows[1].reaction == 33 and rows[1].reaction_param == 1234);
local both = MOCK.action_packet(1001, 1, 0, MOB, { { message = 1, damage = 55, add_effect = true, reaction = true } });
packets.action_results(both, rows);
check('additional and reaction results retain separate fields', rows[1].added == 163 and rows[1].added_param == 9999
    and rows[1].reaction == 44 and rows[1].reaction_param == 1234);
packets.action_results(MOCK.action_packet(1001, 1, 0, MOB, { { message = 1, damage = 55 } }), rows);
check('reused result rows clear absent secondary effects', rows[1].added == 0 and rows[1].added_param == 0
    and rows[1].reaction == 0 and rows[1].reaction_param == 0);
local partial = MOCK.action_packet_multi(1001, 4, 56, {
    { id = MOB, results = { { message = 236, damage = 13 } } },
    { id = MOB + 1, results = { { message = 236, damage = 13 } } },
});
partial.size = 35;
partial.data = partial.data:sub(1, 35);
check('later target truncation rejects earlier results', not packets.valid(partial) and packets.action_results(partial, rows) == 0);
check('partial action cannot match an earlier target', not packets.action_has_target(partial, MOB));
local absent = { id = 0x028, data = normal.data, size = normal.size };
check('missing native action pointer is rejected', not packets.valid(absent));
local false_size = { id = 0x028, data = '', data_raw = normal.data_raw, size = normal.size };
check('reported size cannot enlarge the received body', not packets.valid(false_size));
local excessive = MOCK.action_packet(1001, 4, 56, MOB, { { message = 236, damage = 13 } });
MOCK.pack_bits(excessive.data_raw, 72, 6, 17);
excessive.data = MOCK.to_string(excessive.data_raw);
check('excessive target count is rejected instead of clipped', not packets.valid(excessive));
for _, fixture in ipairs({
    { 'message', MOCK.message_packet(1001, MOB, 0, 0, 6, 0), 26 },
    { 'vitals', MOCK.vitals_packet(1001, 100, 100, 100), 20 },
    { 'assist', MOCK.assist_packet(1001, MOB), 12 },
    { 'zone_in', MOCK.zone_packet(1001), 8 },
}) do
    local event = fixture[2];
    event.data, event.size = event.data:sub(1, fixture[3] - 1), fixture[3] - 1;
    local ok, result = pcall(packets[fixture[1]], event);
    check('short ' .. fixture[1] .. ' is rejected safely', ok and result == nil and not packets.valid(event));
end
local leave = MOCK.message_packet(MOB, 0, 0, 0, 0, 0);
leave.id = 0x00E;
leave.data_raw[8], leave.data_raw[9], leave.data_raw[10] = 0, 2, 0x20;
leave.data = MOCK.to_string(leave.data_raw);
local id, index = packets.despawned(leave);
check('despawn decoder returns identity and index', id == MOB and index == 512);
for size = 0, 10 do
    local e = { data = leave.data:sub(1, size), size = size };
    check('short entity update is ignored at ' .. size, packets.despawned(e) == nil);
end
struct.unpack, ashita.bits.unpack_be = read_struct, read_bits;
if (failed > 0) then out[#out + 1] = failed .. ' FAILED'; else out[#out + 1] = 'ALL PASSED'; end
return table.concat(out, '\n');
