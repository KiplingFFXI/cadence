-- Caching keeps periodic expiry and same-icon replacement semantics.
local out, failed = {}, 0;
local function check(name, value)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name;
    if (not value) then failed = failed + 1; end
end
local modifiers = require('core.modifiers');
local calculate, calculations = modifiers.calculate, 0;
modifiers.calculate = function (snapshot)
    calculations = calculations + 1;
    return calculate(snapshot);
end;
local observer = require('core.stat_state');
MOCK.player.equipment[4] = 15290;
local loadout = { main_job = 1, main_level = 75, sub_job = 13, sub_level = 37,
    buffs = {}, buffs_known = true, engaged = false, resting = false };
local function update(now)
    MOCK.now = now;
    return observer.update(now, loadout);
end
update(0);
observer.on_packet(MOCK.action_packet(1001, 5, 15290, 1001, { { message = 0 } }), 1, 1001);
loadout.buffs = { [33] = true };
local active = update(1.3);
check('setup observes the supported Haste enchantment', observer.snapshot().activated_items[15290] ~= nil);
loadout.buffs_known = false;
local unknown = update(2);
local count = calculations;
check('unavailable buffs preserve the timed identity before expiry', observer.snapshot().activated_items[15290] ~= nil);
update(2.3);
check('unchanged unavailable polls still reuse the model', calculations == count);
local expired = update(182);
check('expiry clears timed item even when buff memory is unavailable', observer.snapshot().activated_items[15290] == nil);
check('expiry rebuilds once and removes the old potency', calculations == count + 1 and expired ~= unknown
    and expired.haste_magic ~= unknown.haste_magic);
count = calculations;
update(182.3);
check('stable state after expiry reuses its model', calculations == count);
loadout.buffs_known = true;
local before = update(183);
count = calculations;
observer.on_packet(MOCK.action_packet(2001, 4, 57, 1001, { { message = 230, damage = 33 } }), 183.1, 1001);
local replaced = update(183.1);
check('same-icon landed replacement invalidates model once', calculations == count + 1 and replaced ~= before
    and replaced.delay_key ~= before.delay_key);
check('same-icon replacement keeps unrelated TP model identity', replaced.tp_key == before.tp_key);
count = calculations;
update(183.4);
check('settling replacement does not recalculate unchanged inputs', calculations == count and not observer.info().transition);
modifiers.calculate = calculate;
if (failed > 0) then out[#out + 1] = failed .. ' FAILED'; else out[#out + 1] = 'ALL PASSED'; end
return table.concat(out, '\n');
