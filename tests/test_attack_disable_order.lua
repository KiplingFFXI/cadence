-- An accepted action can precede the periodic buff read that notices a disable ended.
local out, failures = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failures = failures + 1; end
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 0.001; end
local attack = require('core.attack');
local function left(now) return select(2, attack.progress(now)); end
local function paused()
    attack.reset();
    attack.engage(0, 4, 'disable-order');
    attack.on_round(1, 4, 'disable-order', true, false);
    attack.on_disabled(2, 10);
end

paused();
attack.on_ability(11, 2, true);
check('an accepted ability carries the paused three seconds into its tail', near(left(11), 5)
    and attack.info(11).disabled == nil);
attack.on_enabled(11.1); attack.on_enabled(11.2);
check('later buff polls cannot apply the same pause again', near(left(11.2), 4.8));

paused();
attack.on_disabled(6, 2);
attack.on_ability(11, 0, true);
check('changing disabling effects preserves the original pause boundary', near(left(11), 3)
    and attack.info(11).disabled == nil);

paused();
attack.on_ability(11, false, true);
check('an accepted action with unknown timing ends the disable but stays unknown', left(11) == nil
    and attack.info(11).disabled == nil and attack.info(11).holding == 'recovery');
attack.on_enabled(12);
attack.on_ability(13, 0, true);
check('a later accepted action preserves the unknown hold remaining phase', near(left(13), 3));

paused();
attack.on_ability(3, 2);
check('an ambiguous failed action cannot clear a disabling effect', attack.info(3).disabled == 10
    and near(left(3), 5) and near(left(10), 5));
attack.on_enabled(11);
check('a failed action tail remains anchored to the pause until it ends', near(left(11), 5));

paused();
attack.on_paralyzed(3, 4, 'disable-order', true, false);
check('a paralyzed action is not proof that the disable ended', attack.info(3).disabled == 10);

-- A new disable while an action is already holding the timer must not count their overlap twice.
for _, tail in ipairs({ 0, 0.8, 2, 5 }) do
    attack.reset(); attack.engage(0, 4, 'disable-overlap');
    attack.on_round(1, 4, 'disable-overlap', true, false);
    attack.on_cast_begin(2, 'spell');
    attack.on_disabled(3, 10);
    attack.on_cast_end(4, tail);
    attack.on_enabled(6);
    check('a disable continuing beyond a cast preserves phase with tail ' .. tail, near(left(6), 3 + tail));
end
attack.reset(); attack.engage(0, 4, 'disable-overlap');
attack.on_round(1, 4, 'disable-overlap', true, false);
attack.on_cast_begin(2, 'spell');
attack.on_disabled(3, 10);
attack.on_enabled(4);
attack.on_cast_end(5, 2);
check('a disable entirely inside a cast adds no second pause', near(left(5), 5));

attack.reset(); attack.engage(0, 4, 'disable-interrupt');
attack.on_round(1, 4, 'disable-interrupt', true, false);
attack.on_cast_begin(2, 'spell');
attack.on_disabled(3, 10);
attack.on_cast_end(4, false);
attack.on_enabled(6);
check('an interrupted spell stays unknown after its disable ends', left(6) == nil);
attack.on_ability(7, 2, true);
check('accepted action after interruption keeps the frozen swing remainder', near(left(7), 5));

-- Exercise the actual controller. Continuous frames keep the buff polling path active during Stun.
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local sequence, origin = 0, 100;
local function frame(at) MOCK.now = at; MOCK.frame(0); end
local function incoming(at, event) MOCK.now = at; MOCK.fire('packet_in', event); end
local function action(category, param, message, animation, result)
    local event = MOCK.action_packet(1001, category, param, 0x01000200,
        { { message = message, animation = animation or 0, damage = result or 0 } });
    sequence = sequence + 1;
    event.data_raw[2], event.data_raw[3] = sequence % 256, math.floor(sequence / 256);
    event.data = MOCK.to_string(event.data_raw);
    return event;
end
local function prepare()
    origin = origin + 30;
    MOCK.player.buffs = {};
    incoming(origin, MOCK.zone_packet(1001));
    MOCK.player.status = 0; frame(origin);
    MOCK.player.status = 1;
    incoming(origin + 0.1, MOCK.status_packet(1001, 1)); frame(origin + 0.1);
    incoming(origin + 1, action(1, 0, 1, 0, 10));
    MOCK.player.buffs = { 10 }; frame(origin + 2);
    for tick = 201, 1099 do frame(origin + tick / 100); end
    check('continuous polling keeps exactly three seconds frozen', near(left(origin + 10.99), 3));
    MOCK.player.buffs = {};
end
local scenarios = {
    { name = 'Provoke', category = 6, param = 35, animation = 3, expected = 5 },
    { name = 'Super Jump', category = 3, param = 68, animation = 214, expected = 8 },
    { name = 'spell', start = 8, category = 4, param = 57, expected = 5 },
    { name = 'ranged attack', start = 12, category = 2, param = 0, expected = 3.8 },
    { name = 'scroll', start = 9, category = 5, param = 4606, expected = 8 },
};
for _, scenario in ipairs(scenarios) do
    for _, packet_first in ipairs({ false, true }) do
        prepare();
        local now = origin + 11.2;
        local event = scenario.start and action(scenario.start, 0x6163, 327, 0, scenario.param)
            or action(scenario.category, scenario.param, 100, scenario.animation);
        if (not packet_first) then frame(now); end
        incoming(now, event);
        if (packet_first) then frame(now); end
        if (scenario.start) then
            now = origin + 13.2;
            incoming(now, action(scenario.category, scenario.param, 230));
        end
        check(scenario.name .. (packet_first and ' packet before buff poll' or ' buff poll before packet'),
            near(left(now), scenario.expected) and attack.info(now).disabled == nil, left(now));
    end
end

for _, message in ipairs({ 84, 106 }) do
    prepare();
    incoming(origin + 11.2, action(6, 35, message, 3));
    check('failed ability message does not prove enable ' .. message,
        attack.info(origin + 11.2).disabled == 10 and near(left(origin + 11.2), 3));
    incoming(origin + 11.2, action(8, 0x6163, message, 0, 57));
    check('failed cast start does not prove enable ' .. message,
        attack.info(origin + 11.2).disabled == 10 and attack.info(origin + 11.2).holding == nil);
end
prepare();
incoming(origin + 11.2, action(8, 0x6163, 327, 0, 57)); frame(origin + 11.2);
incoming(origin + 12.2, action(8, 0x7073, 16, 0, 57));
check('controller interruption remains unknown after packet-first start', left(origin + 12.2) == nil);
incoming(origin + 13.2, action(6, 35, 100, 3));
check('controller recovery from interruption preserves the paused remainder', near(left(origin + 13.2), 5));
for _, message in ipairs(MOCK.printed) do
    check('the controller never stops drawing', not message:find('Drawing stopped', 1, true), message);
end
out[#out + 1] = failures == 0 and 'ALL PASSED' or (failures .. ' FAILED');
return table.concat(out, '\n');
