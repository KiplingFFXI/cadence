-- Action ids overlap between job abilities and weapon skills. Recovery needs the packet signature.
local out, failed = {}, 0;
local function check(name, yes, detail)
    out[#out + 1] = (yes and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not yes) then failed = failed + 1; end
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-6; end
local recovery = require('core.recovery');
local packets = require('core.packets');
local source = require('data.phoenix_recovery');

local signatures = {
    { 'Spinning Axe', 3, 68, 50, 'weaponskill', 2.833, 'timed' },
    { 'Super Jump', 3, 68, 214, 'superjump', 5, 'timed' },
    { 'Gale Axe', 3, 66, 48, 'weaponskill', 1.833, 'timed' },
    { 'Combo', 3, 1, 16, 'weaponskill', 1.916, 'timed' },
    { 'Fast Blade', 3, 32, 1, 'weaponskill', 1.5, 'timed' },
    { 'Jump', 3, 66, 204, 'ability', 0, 'none' },
    { 'Eagle Eye Shot with a bow', 3, 26, 186, 'ability', 0, 'none' },
    { 'Eagle Eye Shot with a gun', 3, 26, 187, 'ability', 0, 'none' },
    { 'Shadowbind with a crossbow', 3, 57, 189, 'ability', 0, 'none' },
    { 'Weapon Bash with a polearm', 3, 77, 203, 'ability', 0, 'none' },
    { 'Blade Bash with a great katana', 3, 168, 201, 'ability', 0, 'none' },
    { 'Provoke', 6, 35, 3, 'ability', 0, 'none' },
    { 'Quick Draw', 6, 125, 125, 'ability', 0, 'none' },
    { 'Curing Waltz', 14, 190, 6, 'ability', 0, 'none' },
    { 'spell completion', 4, 57, 0, 'spell', 2.5, 'timed' },
    { 'spell with a longer animation', 4, 830, 0, 'spell', 4, 'timed' },
    { 'spell with unknown animation timing', 4, 65535, 0, 'spell', nil, 'unknown' },
    { 'ranged completion with zero parameter', 2, 0, 0, 'ranged', 0.8, 'timed' },
    { 'a learned spell scroll', 5, 4606, 11, 'item', 5, 'timed' },
    { 'a zero-tail potion', 5, 4112, 30, 'item', 0, 'none' },
    { 'quarantined item duration', 5, 4352, 0, 'item', nil, 'unknown' },
    { 'unrecognized item', 5, 65535, 0, 'item', nil, 'unknown' },
    { 'unrecognized shared-category signature', 3, 68, 4095, 'unknown', nil, 'unknown' },
    { 'unrecognized job ability', 6, 65535, 4095, 'ability', nil, 'unknown' },
};
for _, row in ipairs(signatures) do
    local kind, seconds, status = recovery.classify(row[2], row[3], row[4]);
    check(row[1] .. ' uses its own source rule', kind == row[5] and seconds == row[6] and status == row[7],
        tostring(kind) .. '/' .. tostring(seconds) .. '/' .. tostring(status));
end

-- A future data overlap must remain unknown instead of choosing one action family.
local prior = source.weaponskills[68][214];
source.weaponskills[68][214] = true;
local kind, seconds, status = recovery.classify(3, 68, 214);
check('an ambiguous data signature cannot pretend to be a weapon skill', kind == 'unknown' and seconds == nil and status == 'unknown');
source.weaponskills[68][214] = prior;

local duration = source.weaponskill_seconds[68];
source.weaponskill_seconds[68] = nil;
kind, seconds, status = recovery.classify(3, 68, 50);
check('missing weapon skill timing cannot fall back to a generic delay', kind == 'weaponskill'
    and seconds == nil and status == 'unknown');
recovery.on_weaponskill(1, 68);
check('the direct weapon skill reader also keeps missing timing unknown', recovery.progress(1).known == false);
source.weaponskill_seconds[68] = 0;
kind, seconds, status = recovery.classify(3, 68, 50);
check('a validated zero animation stays zero', kind == 'weaponskill' and seconds == 0 and status == 'none');
source.weaponskill_seconds[68] = duration;
recovery.reset();
recovery.on_spell(2, 830);
check('the direct spell reader includes longer animation locks', near(recovery.progress(2).left, 4));
recovery.reset();

local rows = {};
local event = MOCK.action_packet_multi(1001, 3, 68, {
    { id = 1002, results = {
        { animation = 0xABC, message = 185, add_effect = true, reaction = true },
        { animation = 0x345, message = 110 },
    } },
    { id = 1003, results = { { animation = 0xFFF, message = 100 } } },
});
local count = packets.action_results(event, rows);
check('result parsing preserves all 12 animation bits through optional blocks and targets', count == 3
    and rows[1].animation == 0xABC and rows[2].animation == 0x345 and rows[3].animation == 0xFFF
    and rows[1].message == 185 and rows[3].target == 1003);
local kept = rows[1];
count = packets.action_results(MOCK.action_packet(1001, 3, 68, 1002, { { animation = 0, message = 110 } }), rows);
check('animation fields reuse their result row and clear an older value', count == 1 and rows[1] == kept and rows[1].animation == 0);
event.size, event.data = event.size - 8, event.data:sub(1, -9);
check('a truncated later target rejects every result before classification', packets.action_results(event, rows) == 0);

recovery.reset();
recovery.on_action(10, 3, 68, 214, 'super jump');
local view = recovery.progress(10);
check('Super Jump begins a five-second estimate', view and view.kind == 'superjump' and view.known
    and view.estimated and near(view.left, 5));
recovery.on_action(10.1, 2, 0, 0, 'ranged after jump');
check('a shorter overlapping action cannot shorten a longer estimate', near(recovery.progress(11).left, 4));
recovery.on_action(11, 3, 68, 214, 'super jump');
check('a replayed Super Jump cannot extend its estimate', near(recovery.progress(12).left, 3));
check('Super Jump expiry hides without claiming readiness', recovery.progress(15) == nil);

recovery.on_action(20, 2, 0, 0, 'ranged shot');
view = recovery.progress(20.2);
check('ranged recovery uses the completed shot and its 0.8-second tail', view and view.kind == 'ranged'
    and view.known and near(view.left, 0.6));
check('ranged recovery hides at its deadline', recovery.progress(20.8) == nil);
recovery.on_action(21, 5, 4606, 11, 'spell scroll');
check('a validated item uses its source duration', near(recovery.progress(22).left, 4)
    and recovery.progress(22).kind == 'item');
recovery.on_action(22.1, 5, 4112, 30, 'potion');
check('an accepted zero-tail item clears stale recovery without inventing a timer', recovery.progress(22.1) == nil);
recovery.on_spell(23, 57, 'prior spell');
recovery.on_action(23.1, 6, 35, 3, 'provoke');
check('an accepted ordinary ability clears stale recovery without a generic JA timer', recovery.progress(23.1) == nil);
recovery.on_action(23.2, 3, 68, 50, 'spinning axe');
recovery.on_action(23.3, 6, 35, 3, 'provoke');
check('a late duplicate ordinary ability cannot clear a newer weapon skill', near(recovery.progress(23.3).left, 2.733));

recovery.on_action(30, 5, 4352, 0, 'uncertain food');
view = recovery.progress(30);
check('quarantined data shows an explicit unknown without numeric timing', view and view.kind == 'item'
    and view.known == false and view.estimated and view.left == nil and view.duration == nil and view.fill == 0);
check('unknown notices reuse the same view while visible', recovery.progress(34.9) == view);
check('the notice timeout hides without claiming recovery completed', recovery.progress(35) == nil);
recovery.on_action(35.1, 5, 4352, 0, 'uncertain food');
check('a replay cannot bring an expired unknown notice back', recovery.progress(35.1) == nil);

for _, category in ipairs({ 8, 9, 12 }) do
    recovery.reset();
    recovery.on_action(40, 5, 4352, 0, 'unknown');
    recovery.on_action(40.1, category, packets.CAST_BEGIN, 0, 'accepted start');
    check('accepted start category ' .. category .. ' clears an unknown notice', recovery.progress(40.1) == nil);
    recovery.on_action(40.2, 2, 0, 0, 'later ranged');
    recovery.on_action(40.3, category, packets.CAST_BEGIN, 0, 'accepted start');
    check('duplicate start category ' .. category .. ' cannot clear later recovery', near(recovery.progress(40.3).left, 0.7));
end

recovery.reset();
recovery.on_spell(50, 57);
for _, category in ipairs({ 2, 3, 4, 5, 6, 14, 15 }) do
    for _, message in ipairs({ 84, 106 }) do
        kind, seconds, status = recovery.on_action(50.1, category, 65535, 4095, nil, message);
        check('failed category ' .. category .. ' message ' .. message .. ' adds no timer or notice', status == 'ignored'
            and recovery.progress(50.1).kind == 'spell' and near(recovery.progress(50.1).left, 2.4));
    end
end
for _, category in ipairs({ 1, 7, 10, 11, 13 }) do
    local _, _, ignored = recovery.classify(category, 68, 214);
    check('irrelevant category ' .. category .. ' cannot invent player recovery', ignored == 'ignored');
end
for _, category in ipairs({ 3, 4, 5, 6, 14, 15 }) do
    local _, _, ignored = recovery.classify(category, 0, 0);
    check('empty completion category ' .. category .. ' is ignored', ignored == 'ignored');
end
recovery.on_action(50.2, 9, packets.CAST_INTERRUPT, 0, 'interrupt');
check('an interrupt cannot clear active recovery', near(recovery.progress(50.2).left, 2.3));
recovery.on_action(math.huge, 5, 4352, 0, 'bad time');
check('invalid event time cannot replace recovery with an unknown notice', recovery.progress(50.2).kind == 'spell');

recovery.reset();
recovery.on_action(60, 5, 4352, 0, 'unknown before reset');
check('a backward clock clears an unknown notice', recovery.progress(59) == nil and recovery.progress(60) == nil);
recovery.on_action(61, 5, 4352, 0, 'unknown before reset');
check('a backward-clock reset also clears replay history', recovery.progress(61) ~= nil);
recovery.reset();
check('explicit reset clears the unknown notice', recovery.progress(62) == nil);

if (jit) then jit.off(); end
local function actions()
    recovery.reset();
    recovery.on_action(70, 3, 68, 214, 'jump');
    recovery.on_action(70.1, 5, 4352, 0, 'unknown item');
    recovery.progress(70.2);
    recovery.on_action(70.3, 6, 35, 3, 'accepted ability');
end
for _ = 1, 20 do actions(); end
collectgarbage('collect'); collectgarbage('stop');
local before = collectgarbage('count');
for _ = 1, 1000 do actions(); end
local bytes = (collectgarbage('count') - before) * 1024 / 1000;
collectgarbage('restart');
check('classification and unknown notices reuse bounded state', bytes < 8, ('%.2f bytes/action group'):format(bytes));

out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
