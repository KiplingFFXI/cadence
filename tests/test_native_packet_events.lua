-- Ashita's bound event structures are userdata, not the plain tables used by most fixtures.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local function native(fields)
    local value = newproxy(true);
    getmetatable(value).__index = fields;
    return value;
end
local packets = require('core.packets');
local event = native(MOCK.vitals_packet(1001, 526, 0, 137));
check('the event fixture is real Lua userdata', type(event) == 'userdata');
check('native vitals pass validation', packets.valid(event));
local hp, mp, tp = packets.vitals(event);
check('native vitals retain their character and amounts', packets.vitals_member(event) == 1001
    and hp == 526 and mp == 0 and tp == 137);

local action = native(MOCK.action_packet(1001, 1, 0, 0x01000200, { { message = 1, damage = 55 } }));
local actor, category = packets.action_header(action);
local rows = {};
check('native action headers retain actor and category', packets.valid(action) and actor == 1001 and category == 1);
check('native action results retain the complete hit', packets.action_results(action, rows) == 1
    and rows[1].target == 0x01000200 and rows[1].message == 1 and rows[1].param == 55);
local message = native(MOCK.message_packet(2001, 1001, 90, 0, 24, 0));
local who, id, target, amount = packets.message(message);
check('native battle messages retain their fields', packets.valid(message) and who == 2001
    and id == 24 and target == 1001 and amount == 90);
check('native zone identity is readable', packets.zone_in(native(MOCK.zone_packet(2002, 147))) == 2002);

check('nil remains safely rejected', not packets.valid(nil) and packets.vitals(nil) == nil);
for _, value in ipairs({ false, true, 1, 'packet', function () end }) do
    check(type(value) .. ' is not a packet event', not packets.valid(value) and packets.vitals(value) == nil);
end
for _, fields in ipairs({
    { id = 0x0DF, data = string.rep('\0', 19), size = 36 },
    { id = 0x0DF, data = string.rep('\0', 36), size = 19 },
    { id = 0x0DF, data = string.rep('\0', 36), size = -1 },
    { id = 0x0DF, data = string.rep('\0', 36), size = 0 / 0 },
    { id = 0x0DF, data = false, size = 36 },
    { id = 0x0DF },
}) do
    local malformed = native(fields);
    check('malformed native vitals remain rejected safely', not packets.valid(malformed) and packets.vitals(malformed) == nil);
end
local truncated = MOCK.action_packet(1001, 1, 0, 0x01000200, { { message = 1, add_effect = true } });
truncated.data = truncated.data:sub(1, 25);
check('native action truncation cannot use a longer raw buffer', not packets.valid(native(truncated))
    and packets.action_results(native(truncated), {}) == 0);

-- Exercise the actual registered main callback with the no-MP report's job and vitals.
local memory = AshitaCore.GetMemoryManager();
local party = memory:GetParty();
party.GetMemberIsActive = function (_, i) return i == 0; end;
party.GetMemberServerId = function (_, i) return i == 0 and MOCK.player.server_id or 0; end;
party.GetMemberMainJob = function () return MOCK.player.main_job; end;
party.GetMemberZone = function () return MOCK.player.zone; end;
party.GetMemberHP = function () return MOCK.player.hp; end;
party.GetMemberMP = function () return MOCK.player.mp; end;
party.GetMemberHPPercent = function () return math.floor(MOCK.player.hp * 100 / MOCK.player.hp_max); end;
memory.GetParty = function () return party; end;
AshitaCore.GetMemoryManager = function () return memory; end;
MOCK.player.main_job, MOCK.player.main_level, MOCK.player.sub_job, MOCK.player.sub_level = 1, 30, 6, 15;
MOCK.player.hp, MOCK.player.hp_max, MOCK.player.mp, MOCK.player.mp_max = 526, 562, 0, 0;
MOCK.player.tp, MOCK.player.status, MOCK.player.zone, MOCK.player.buffs = 137, 33, 147, { 253, 251 };
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local resting, observer = require('core.resting'), require('core.stat_state');
MOCK.frame(0);
local diagnostics = require('core.diagnostics');
diagnostics.enable(true);
MOCK.now = 0.1; MOCK.fire('packet_in', event);
check('registered callback initializes resting vitals from native events', resting.knows_vitals());
local saw_vitals = false;
for _, row in ipairs(diagnostics.report({}).events) do
    if (row.kind == 'vitals') then saw_vitals = true; end
end
check('native vitals appear in opt-in timing details', saw_vitals);
local gain, _, confidence = resting.next_gains();
check('native vitals unlock the HP-only model despite unknown food', gain == 19
    and confidence and confidence.hp == 'estimated');
local hp_full, mp_full, has_mp = resting.until_each_full(0.1);
check('native vitals restore HP full-in before the first tick', hp_full ~= nil and hp_full > 0
    and mp_full == 0 and not has_mp and resting.until_full(0.1) ~= nil);
MOCK.now = 21; MOCK.player.hp = 545;
MOCK.fire('packet_in', native(MOCK.vitals_packet(1001, 545, 0, 137)));
check('native HP-only healing records its real tick and next gain', resting.info(21).accepted == 1
    and resting.info(21).last_tick == 21 and resting.next_gains() == 17);
check('HP full-in follows the next due native recovery', select(1, resting.until_each_full(21)) == 9);

local original_direct, direct_calls = resting.on_direct_change, 0;
resting.on_direct_change = function (at, h, m, t)
    if (h and not m and not t) then direct_calls = direct_calls + 1; end
    return original_direct(at, h, m, t);
end;
MOCK.now = 24;
MOCK.fire('packet_in', native(MOCK.action_packet(2001, 4, 1, 1001, { { message = 7, damage = 90 } })));
MOCK.now = 25; MOCK.fire('packet_in', message);
check('registered native action and message paths still exclude direct HP recovery', direct_calls == 2);
resting.on_direct_change = original_direct;

for _, flag in ipairs({ 'blocked', 'injected', 'is_injected', 'blocked_original' }) do
    local fields = MOCK.vitals_packet(1001, 1, 0, 0); fields[flag] = true;
    MOCK.fire('packet_in', native(fields));
end
MOCK.fire('packet_in', native(MOCK.vitals_packet(2001, 1, 0, 0)));
check('blocked injected and other-character native vitals remain ignored',
    resting.next_gains() == 17 and observer.snapshot().hp == 545);

MOCK.now = 30; MOCK.player.hp = 562;
MOCK.fire('packet_in', native(MOCK.vitals_packet(1001, 562, 0, 137)));
check('native capped recovery reaches full without overstating its potency', resting.info(30).accepted == 2
    and resting.is_full() and select(1, resting.until_each_full(30)) == 0);

local old_packet, saw_equipment = observer.on_packet, false;
observer.on_packet = function (e, at, server_id)
    if (type(e) == 'userdata' and e.id == 0x050) then saw_equipment = true; end
    return old_packet(e, at, server_id);
end;
MOCK.fire('packet_in', native({ id = 0x050, size = 8, data = string.rep('\0', 8) }));
observer.on_packet = old_packet;
check('native observer-only packet types also reach the normal callback', saw_equipment);

MOCK.player.status = 1;
MOCK.now = 32; MOCK.frame(0);
local attack = require('core.attack');
MOCK.now = 33; MOCK.fire('packet_in', action);
local first_round = attack.info(33);
MOCK.now = 37; MOCK.fire('packet_in', action);
local second_round = attack.info(37);
check('registered native melee actions schedule the next attack and learn its interval',
    first_round.active and first_round.next_in and first_round.next_in > 0
    and second_round.next_in and second_round.next_in > 0
    and second_round.accepted == first_round.accepted + 1 and second_round.samples == 1);

MOCK.player.status = 33;
MOCK.player.server_id, MOCK.player.hp = 2002, 500;
MOCK.now = 40; MOCK.fire('packet_in', native(MOCK.zone_packet(2002, 147)));
check('native zone events clear previous resting observations', not resting.knows_vitals() and not resting.is_active());
MOCK.fire('packet_in', native(MOCK.vitals_packet(2002, 500, 0, 137)));
check('native zone identity accepts the new character vitals', resting.knows_vitals()
    and observer.snapshot().hp == 500);
check('the native callback path sends no game commands', #MOCK.commands == 0);

out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
