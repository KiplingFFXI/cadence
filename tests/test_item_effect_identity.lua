-- Shared icons keep each observed item's own expiration.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local state = require('core.stat_state');
MOCK.player.equipment[10] = 15290;
local load = { main_job = 1, main_level = 75, sub_job = 0, sub_level = 0,
    buffs = {}, buff_counts = {}, buffs_known = true, engaged = false, resting = false };
local function update(now)
    MOCK.now = now;
    return state.update(now, load, true);
end
local function icons(now, stamps)
    local bytes = MOCK.bytes(200);
    local function put(at, value, size)
        for i = 0, size - 1 do bytes[at + i] = math.floor(value / 256 ^ i) % 256; end
    end
    put(4, 9, 2);
    for i, stamp in ipairs(stamps) do put(8 + (i - 1) * 2, 33, 2); put(72 + (i - 1) * 4, stamp, 4); end
    load.buffs, load.buff_counts = #stamps > 0 and { [33] = true } or {}, { [33] = #stamps };
    state.on_packet({ id = 0x063, size = 200, data = MOCK.to_string(bytes) }, now, 1001);
end
local function action(now, item)
    state.on_packet(MOCK.action_packet(item and 1001 or 2001, item and 5 or 4, item and 15290 or 57,
        1001, { { message = item and 0 or 230, damage = item and 0 or 33 } }), now, 1001);
end
local function start(status_first, stamp)
    state.reset(); load.buffs, load.buff_counts = {}, {}; update(0);
    stamp = stamp or 100000;
    if (status_first) then icons(1, { stamp }); action(1.1, true);
    else action(1, true); icons(1.1, { stamp }); end
    return update(1.3);
end
local function item()
    return state.snapshot().activated_items[15290];
end
check('the observed belt starts at its known 1000 magic haste', start().haste_magic == 1000 and item().timer_stamp == 100000);
action(10, false); icons(10.1, { 100000, 130000 });
local model = update(10.3);
check('adding normal Haste retains the belt and adds only one spell estimate', item() ~= nil and model.haste_magic == 2465);
icons(12, { 130000, 100000 });
check('reordered icons keep both contributions', update(12.1).haste_magic == 2465 and item().timer_stamp == 100000);
action(20, false); icons(20.1, { 160000, 100000 });
check('recasting the other Haste leaves the belt expiration intact', update(20.3).haste_magic == 2465 and item().timer_stamp == 100000);
icons(25, { 100000 }); model = update(25.1);
check('removing the spell preserves the known belt', model.haste_magic == 1000 and model.delay_known and item() ~= nil);
action(30, true); icons(30.1, { 180000 }); model = update(30.3);
check('reusing the belt replaces only its own expiration', item().timer_stamp == 180000 and item().expires_at == 210 and model.haste_magic == 1000);
action(35, false); icons(35.1, { 180000, 190000 }); update(35.3);
icons(40, { 190000 }); model = update(40.1);
check('losing the belt timer removes its potency while Haste remains', item() == nil and model.haste_magic == 1465 and not model.delay_known);
start(); icons(1.5, {}); model = update(1.6);
check('confirmed removal clears a bound item even inside the initial two seconds', item() == nil and model.haste_magic == 0);
start(true); action(10, false); icons(10.1, { 130000, 100000 }); model = update(10.3);
check('status arriving before item completion binds the retained original timer', item().timer_stamp == 100000 and model.haste_magic == 2465);
local previous = start(); icons(5, { 100060 }); model = update(5.1);
check('expiration rounding reuses the modifier model', model == previous);
icons(6, { 100120 }); update(6.1);
action(10, false); icons(10.1, { 130000, 100180 }); model = update(10.3);
check('timer rounding follows the same instance without losing its identity', item().timer_stamp == 100180 and model.haste_magic == 2465);
previous = start(false, 4294967280); icons(5, { 44 }); model = update(5.1);
check('expiration rounding survives the packet timestamp wrap', item().timer_stamp == 44 and model == previous);
start(); action(10, false); icons(10.1, { 100000, 100000 }); update(10.3);
icons(12, { 100000 }); model = update(12.1);
check('ambiguous removal from identical expirations stays unknown', item() == nil and not model.delay_known and model.haste_magic == 1465);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
