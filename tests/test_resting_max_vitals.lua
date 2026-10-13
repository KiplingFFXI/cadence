-- Maximum HP and MP can change while resting without another vitals packet.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local function positive(value) return value ~= nil and value > 0; end

dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local resting, hud, sound = require('core.resting'), require('ui.hud'), require('ui.sound');
local s = MOCK.settings.current;
s.attack.enabled, s.enemy.enabled = false, false;
s.resting.enabled, s.resting.hide_when_full = true, true;
s.resting.show_until_full, s.resting.show_each_full, s.resting.show_ticks = true, true, true;
s.resting.show_next_gains, s.resting.show_goal = true, true;
s.resting.goal_stat, s.resting.goal_mode, s.resting.goal_value = 'both', 'percent', 100;
s.resting.sound = true;
local view, plays = nil, 0;
hud.draw_resting = function (value) view = value; end;
sound.play = function () plays = plays + 1; return true; end;
local function frame(seconds)
    view = nil;
    MOCK.frame(seconds or 0.25);
end
local function vitals(hp, mp)
    MOCK.fire('packet_in', MOCK.vitals_packet(MOCK.player.server_id, hp, mp, 0));
end

for _, case in ipairs({
    { name = 'HP and MP', hp = 300, mp = 100, hp_max = 900, mp_max = 300 },
    { name = 'HP only', hp = 300, mp = 100, hp_max = 900, mp_max = 100 },
    { name = 'MP only', hp = 300, mp = 100, hp_max = 300, mp_max = 300 },
    { name = 'job without MP', hp = 300, mp = 0, hp_max = 900, mp_max = 0 },
    { name = 'MP becomes available', hp = 300, mp = 0, hp_max = 300, mp_max = 300 },
}) do
    MOCK.player.status = 0; frame();
    resting.reset();
    MOCK.player.hp_max, MOCK.player.mp_max = case.hp, case.mp;
    MOCK.player.buffs = { 1 };
    vitals(case.hp, case.mp);
    MOCK.player.status = 33; frame();
    frame(24);
    local before, sounds = resting.info(MOCK.now), plays;
    check(case.name .. ': full weakened vitals hide the timer', resting.is_full() and view == nil);

    -- The maximums arrive after Weakness ends. No 0x0DF carries another current HP or MP value.
    MOCK.player.buffs = {};
    MOCK.player.hp_max, MOCK.player.mp_max = case.hp_max, case.mp_max;
    frame();
    local after = resting.info(MOCK.now);
    local hp, mp, has_mp = resting.until_each_full(MOCK.now);
    local _, _, _, gained_hp, gained_mp = resting.progress(MOCK.now);
    check(case.name .. ': maximum changes clear full and reveal the timer', not resting.is_full()
        and view ~= nil and not view.full);
    check(case.name .. ': HP time follows the new maximum', case.hp_max > case.hp and positive(hp)
        or case.hp_max == case.hp and hp == 0);
    check(case.name .. ': MP time follows the new maximum', case.mp_max > case.mp and positive(mp)
        or case.mp_max == case.mp and mp == 0);
    check(case.name .. ': MP presence follows its maximum', has_mp == (case.mp_max > 0));
    check(case.name .. ': combined recovery and goal resume', view ~= nil and positive(view.until_full)
        and view.goal ~= nil and not view.goal.reached and positive(view.goal.seconds));
    check(case.name .. ': maximum changes preserve tick count and schedule', after.ticks == before.ticks
        and after.next_tick == before.next_tick and after.last_tick == before.last_tick);
    check(case.name .. ': maximum changes do not invent a healing observation', after.accepted == before.accepted
        and gained_hp == 0 and gained_mp == 0);
    check(case.name .. ': missing vitals do not play the completion sound', plays == sounds);

    if (case.hp_max > case.hp and case.mp_max > case.mp) then
        vitals(case.hp_max, case.mp); frame();
        check(case.name .. ': HP filling leaves MP recovery visible', view ~= nil and not view.full
            and view.hp_full_in == 0 and positive(view.mp_full_in) and plays == sounds);
    end
    vitals(case.hp_max, case.mp_max); frame();
    check(case.name .. ': filling the new maximums hides the timer', resting.is_full() and view == nil);
    check(case.name .. ': filling the new maximums plays once', plays == sounds + 1);
    frame();
    check(case.name .. ': staying full does not repeat the sound', plays == sounds + 1);
end

resting.reset();
resting.on_max_vitals(MOCK.now, 900, 300);
check('maximums alone do not establish current vitals', not resting.knows_vitals());
resting.on_buffs(0, {});
resting.on_vitals(-1, 100, 0, 0, 900, 300);
resting.on_model({ resting_key = 'before maximum change', hp_base = 31, hp_step = 4,
    mp_base = 12, mp_step = 1, hp_known = true, mp_known = true });
resting.start(0);
resting.on_vitals(21, 141, 12, 0, 900, 300);
resting.on_vitals(30, 187, 25, 0, 900, 300);
resting.on_vitals(42, 238, 39, 0, 900, 300);
local before = resting.info(43);
check('three recovery observations establish phase and a learned amount', before.pattern_known
    and before.ticks == 3 and before.next_tick == 51 and before.next_hp == 56
    and before.gain_confidence.hp == 'observed');
for _, caps in ipairs({ { 900, 300 }, { 0, 300 }, { 900, -1 }, { 0 / 0, 300 },
    { 900, math.huge }, { false, 300 } }) do
    resting.on_max_vitals(43, caps[1], caps[2]);
end
resting.on_max_vitals(43, nil, nil);
local kept = resting.info(43);
check('unchanged and unavailable maximums preserve the learned amount', kept.next_hp == before.next_hp
    and kept.next_mp == before.next_mp and kept.gain_confidence.hp == 'observed');
check('unchanged and unavailable maximums preserve phase and evidence', kept.pattern_known
    and kept.ticks == before.ticks and kept.next_tick == before.next_tick and kept.accepted == before.accepted);
resting.on_max_vitals(43, 1200, 400);
local changed = resting.info(43);
check('changed maximums discard only old recovery samples', changed.next_hp == 43
    and changed.gain_confidence.hp == 'known' and changed.pattern_known
    and changed.ticks == before.ticks and changed.next_tick == before.next_tick
    and changed.last_tick == before.last_tick and changed.accepted == before.accepted);
resting.on_model({ resting_key = 'after maximum change', hp_base = 31, hp_step = 5,
    mp_base = 12, mp_step = 1, hp_known = true, mp_known = true });
check('the new recovery slope uses the existing tick index', resting.next_gains() == 46);
resting.on_vitals(51, 284, 54, 0, 1200, 400);
check('the next recovery continues on the established schedule', resting.info(51).ticks == 4
    and resting.info(51).next_tick == 60 and resting.info(51).last_tick == 51);

out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
