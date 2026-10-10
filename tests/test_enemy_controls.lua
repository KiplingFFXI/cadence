-- Observed control effects protect measured intervals without inventing a resume time.
local out, failed = {}, 0;
local function check(name, value)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name;
    if (not value) then failed = failed + 1; end
end
local enemy = require('core.enemy');
local effects = require('core.monster_effects');
local MOB = 0x01000200;
local function holding(now) return select(7, enemy.progress(now, MOB)); end
for i = 0, 4 do enemy.on_round(i * 4, MOB, 1001); end
local original = enemy.info(16, MOB);
check('baseline is observed', original.learned and original.delay == 4);
local sleep = effects.landed(4, 253, 236, 2);
check('Sleep is observed with uncertain source duration', sleep.control == 'sleep' and not sleep.inputs_known);
check('Bind alone is not an attack hold', effects.landed(4, 258, 236, 11) == nil);
check('a resisted Sleep is not a hold', effects.landed(4, 253, 85, 2) == nil);
enemy.on_effect(17, MOB, sleep, false);
local _, left = enemy.progress(18, MOB);
check('Sleep freezes the old phase', holding(19) == 'sleep' and select(2, enemy.progress(19, MOB)) == left);
enemy.on_damage(20, MOB, 0);
check('zero damage does not wake Sleep', holding(20) == 'sleep');
enemy.on_damage(21, MOB, 1);
check('damage waits for the next observed attack', holding(21) == 'observing');
check('wake does not invent a next interval', enemy.info(21, MOB).awaiting_attack and not enemy.info(21, MOB).learned);
enemy.on_round(24, MOB, 1001);
check('the waking gap was not learned', enemy.info(24, MOB).samples == original.samples and enemy.info(24, MOB).delay == 4);
check('actual round restores the timer', holding(24) == nil and select(2, enemy.progress(24, MOB)) == 4);
enemy.on_effect(25, MOB, effects.landed(4, 252, 236, 10), false);
check('Stun is labeled', holding(26) == 'stun');
check('estimated Stun expiry only changes to observation', holding(34) == 'observing');
enemy.on_round(40, MOB, 1001);
enemy.on_effect(41, MOB, effects.landed(11, 9999, 242, 7), false);
enemy.on_effect(42, MOB, effects.landed(11, 9999, 242, 28), false);
check('Petrification and Terror coexist', #enemy.info(42, MOB).effects == 2 and holding(42) == 'petrification');
enemy.on_effect_gone(43, MOB, 7);
check('removing one control preserves another', holding(43) == 'terror');
enemy.on_round(44, MOB, 1001);
check('a real attack overrides stale control observations', holding(44) == nil and #enemy.info(44, MOB).effects == 0);
enemy.remember(MOB, 'Remembered monster');
enemy.on_effect(45, MOB, effects.landed(4, 56, 236, 13), false);
enemy.on_disappear(MOB);
check('disappearance removes the clock and effects', not enemy.has(MOB));
enemy.on_engage(46, MOB);
enemy.recall(46, MOB, 'Remembered monster');
local recalled = enemy.info(46, MOB);
check('clean name and zone baseline survives disappearance', recalled.delay == 4 and recalled.source == 'same name' and #recalled.effects == 0);
enemy.on_effect(47, MOB, effects.landed(4, 253, 236, 2), false);
enemy.on_paralyzed(48, MOB, 1001);
check('a confirmed attempted round clears contradicted control', holding(48) == nil);
-- The same cases through the real addon controller, with only client memory mocked.
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
MOCK.settings.current.enemy.enabled = true;
MOCK.fire('packet_in', MOCK.zone_packet(1001));
MOCK.now = 100;
MOCK.fire('packet_in', MOCK.action_packet(MOB, 1, 0, 1001, { { message = 1, damage = 10 } }));
MOCK.fire('packet_in', MOCK.action_packet(2001, 4, 253, MOB, { { message = 236, damage = 2 } }));
check('controller tracks observed Sleep', holding(100) == 'sleep');
local injected = MOCK.action_packet(2001, 1, 0, MOB, { { message = 1, damage = 10 } });
injected.injected = true;
MOCK.fire('packet_in', injected);
check('injected damage cannot wake the observation', holding(100) == 'sleep');
MOCK.fire('packet_in', MOCK.action_packet(2001, 1, 0, MOB, { { message = 1, damage = 10 } }));
check('controller damage wakes Sleep conservatively', holding(100) == 'observing');
local partial = MOCK.action_packet_multi(2001, 4, 56, {
    { id = MOB, results = { { message = 236, damage = 13 } } },
    { id = MOB + 1, results = { { message = 236, damage = 13 } } },
});
partial.size, partial.data = 35, partial.data:sub(1, 35);
MOCK.fire('packet_in', partial);
check('controller rejects the entire partial action', #enemy.info(100, MOB).effects == 0);
MOCK.fire('packet_in', MOCK.action_packet(2001, 4, 56, MOB, { { message = 236, damage = 13 } }));
local leave = MOCK.message_packet(MOB, 0, 0, 0, 0, 0);
leave.id = 0x00E;
leave.data_raw[8], leave.data_raw[9], leave.data_raw[10] = 0, 2, 0x20;
leave.data = MOCK.to_string(leave.data_raw);
MOCK.fire('packet_in', leave);
check('controller clears the vanished enemy immediately', not enemy.has(MOB));
MOCK.now = 102;
MOCK.fire('packet_in', MOCK.action_packet(MOB, 1, 0, 1001, { { message = 1, damage = 10 } }));
check('reused entity ID does not inherit the old Slow', #enemy.info(102, MOB).effects == 0);
check('a zero-byte controller action is ignored', pcall(MOCK.fire, 'packet_in', { id = 0x028, data = '', size = 0, data_raw = { n = 0 } }));
if (failed > 0) then out[#out + 1] = failed .. ' FAILED'; else out[#out + 1] = 'ALL PASSED'; end
return table.concat(out, '\n');
