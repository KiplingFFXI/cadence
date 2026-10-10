-- HP-only resting accepts real recovery, not duplicate vitals or a passive-only pass.
local resting = require('core.resting');
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local function sit(hp, regen, known)
    resting.reset(); resting.on_buffs(0, {});
    resting.on_vitals(-1, hp, 0, 0, 900, 0);
    resting.on_model({ resting_key = 'hp-only', hp_base = 31, hp_step = 4, mp_base = 12, mp_step = 1,
        hp_known = true, mp_known = true, regen = known and regen or 0,
        regen_known = known ~= false, refresh_known = true });
    resting.start(0);
end
local function vitals(now, hp)
    resting.on_vitals(now, hp, 0, 0, 900, 0);
end

sit(100, 0, true);
vitals(20, 100);
check('a duplicate near the first tick leaves its count at zero', resting.info(20).ticks == 0);
check('a duplicate near the first tick keeps the initial prediction', resting.info(20).next_tick == 21.4
    and resting.info(20).last_tick == nil);
vitals(22, 131);
check('the real first HP-only gain still establishes timing', resting.info(22).ticks == 1
    and resting.info(22).last_tick == 22 and resting.info(22).next_tick == 31);
check('the real first gain teaches HP potency with no MP', resting.next_gains() == 35
    and select(3, resting.next_gains()).hp == 'observed');
vitals(31, 131);
check('a duplicate at the next expected tick cannot advance the count', resting.info(31).ticks == 1
    and resting.info(31).last_tick == 22 and resting.info(31).next_tick == 31);
vitals(31.2, 166);
check('real recovery after a duplicate is retained exactly once', resting.info(31.2).ticks == 2
    and resting.info(31.2).last_tick == 31.2 and resting.next_gains() == 39);
check('ordinary HP-only recovery still has a full ETA', resting.until_full(31.2) ~= nil);

-- The three-second pass at19.5 is inside the first-tick window, before healing at22.5.
for _, known in ipairs({ true, false }) do
    sit(100, 1, known);
    local hp = 100;
    for i = 0, 6 do
        hp = hp + 1;
        vitals(1.5 + 3 * i, hp);
        resting.update(2.1 + 3 * i);
    end
    local source = known and 'known' or 'observed';
    check(source .. ' Regen near the first tick is not resting recovery', resting.info(20.1).ticks == 0
        and resting.info(20.1).last_tick == nil and resting.info(20.1).next_tick == 21.4);
    check(source .. ' Regen remains available as a separate passive rate', resting.info(20.1).regen_hp == 1);
    hp = hp + 32; vitals(22.5, hp);
    check(source .. ' Regen plus a real first gain establishes only one tick', resting.info(22.5).ticks == 1
        and resting.info(22.5).last_tick == 22.5 and resting.info(22.5).next_tick == 31.5);
    check(source .. ' Regen is excluded from the next healing amount', resting.next_gains() == 35);
    hp = hp + 1; vitals(25.5, hp);
    hp = hp + 1; vitals(28.5, hp);
    hp = hp + 36; vitals(31.5, hp);
    check(source .. ' Regen with a second real gain keeps the HP-only phase', resting.info(31.5).ticks == 2
        and resting.info(31.5).last_tick == 31.5 and resting.next_gains() == 39);
    local due = resting.info(31.5).next_tick;
    hp = hp + 1; vitals(due, hp);
    check(source .. ' passive-only gain at a later expected tick cannot restart the timer',
        resting.info(due).ticks == 2 and resting.info(due).last_tick == 31.5 and resting.info(due).next_tick == due);
    hp = hp + 40; vitals(due + 0.2, hp);
    check(source .. ' real HP gain remains visible after the passive-only update', resting.info(due + 0.2).ticks == 3
        and resting.info(due + 0.2).last_tick == due + 0.2 and resting.next_gains() == 43);
    check(source .. ' passive recovery does not remove the full ETA', resting.until_full(due + 0.2) ~= nil);
end

sit(900, 0, true);
vitals(21, 900);
check('full duplicate vitals are not a visible healing tick', resting.info(21).ticks == 0
    and resting.info(21).last_tick == nil);
resting.update(24);
check('an invisible first tick at full HP still advances on schedule', resting.info(24).ticks == 1
    and resting.info(24).last_tick == nil);
resting.update(35); resting.update(35.1);
check('later invisible full ticks still advance on schedule', resting.info(35.1).ticks == 2
    and resting.is_full());

sit(100, 0, true);
resting.on_buffs(0, { [8] = true });
vitals(21, 100); resting.update(21.5);
check('blocked ticks still advance without visible recovery', resting.info(21.5).ticks == 1
    and resting.info(21.5).last_tick == nil and resting.until_full(21.5) == nil);
resting.on_buffs(22, {});
vitals(30.4, 135);
check('HP-only recovery after a block retains the tick index', resting.info(30.4).ticks == 2
    and resting.info(30.4).last_tick == 30.4 and resting.next_gains() == 39);

out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
