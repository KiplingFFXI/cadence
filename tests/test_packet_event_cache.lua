-- Readers share validation only within one incoming event, even if Ashita reuses its event object.
local count, unpack_bits = 0, ashita.bits.unpack_be;
ashita.bits.unpack_be = function (...)
    count = count + 1;
    return unpack_bits(...);
end;
local packets = require('core.packets');
local out, failed = {}, 0;
local function check(name, yes)
    out[#out + 1] = (yes and 'ok   ' or 'FAIL ') .. name;
    if (not yes) then failed = failed + 1; end
end
local MOB = 0x01000200;
local hits = {};
for i = 1, 8 do hits[i] = { message = 1, damage = 25 }; end
local event = MOCK.action_packet(1001, 1, 0, MOB, hits);
check('complete action starts an event', packets.begin_event(event));
local rows, other, messages = {}, {}, {};
check('all eight results decode', packets.action_results(event, rows) == 8);
local reads = count;
check('readers retain their results', packets.valid(event) and packets.action_header(event) == 1001
    and packets.action_param(event) == 0 and packets.action_target(event) == MOB
    and packets.action_messages(event, messages) == 8 and packets.melee_hits(event) == 8
    and packets.action_has_target(event, MOB) and packets.action_results(event, other) == 8);
check('subsequent readers perform no further bit reads', count == reads);
check('eight-hit decode stays below the former 274 reads', reads <= 70);
rows[1].message = 999;
check('consumer result buffers are independent', other[1].message == 1);
packets.end_event();
local replacement = MOCK.action_packet(2002, 4, 144, MOB, { { message = 2, damage = 51 } });
event.data, event.data_raw, event.size = replacement.data, replacement.data_raw, replacement.size;
check('reused event object gets a fresh header', packets.begin_event(event) and packets.action_header(event) == 2002
    and packets.action_param(event) == 144);
check('reused result rows get fresh data and counts', packets.action_results(event, rows) == 1
    and rows[1].message == 2 and rows[1].param == 51);
packets.end_event();
replacement = MOCK.action_packet(3003, 1, 0, MOB, hits);
event.data, event.data_raw, event.size = replacement.data, replacement.data_raw, replacement.size;
check('readers outside the callback never use a stale view', packets.action_header(event) == 3003);
local empty = MOCK.action_packet(1001, 1, 0, nil, {});
check('zero-target action is rejected', not packets.begin_event(empty) and not packets.valid(empty));
empty = MOCK.action_packet(1001, 1, 0, MOB, {});
check('zero-result action is rejected', not packets.begin_event(empty) and not packets.valid(empty));
local partial = MOCK.action_packet_multi(1001, 1, 0, {
    { id = MOB, results = hits }, { id = MOB + 1, results = hits },
});
partial.data, partial.size = partial.data:sub(1, #partial.data - 4), #partial.data - 4;
check('truncated later target rejects the whole cached event', not packets.begin_event(partial)
    and packets.action_results(partial, rows) == 0);
packets.end_event();

dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
MOCK.player.status = 1; MOCK.frame(0.1);
local attack = require('core.attack');
local before = attack.info(MOCK.now);
MOCK.fire('packet_in', empty);
local after = attack.info(MOCK.now);
check('empty melee event cannot move the attack timer', before.next_in == after.next_in
    and before.observations == after.observations);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
