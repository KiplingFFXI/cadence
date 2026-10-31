-- Lower maximums clamp cached current vitals; raising them later cannot restore the removed HP/MP.
local resting = require('core.resting');
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local function positive(value) return value ~= nil and value > 0; end
local function sit(hp, mp, hp_max, mp_max)
    resting.reset();
    resting.on_vitals(-1, hp, mp, 0, hp_max, mp_max);
    resting.on_model({ resting_key = 'maximum transition', hp_base = 10, hp_step = 1,
        mp_base = 12, mp_step = 1, hp_known = true, mp_known = true });
    resting.start(0);
end
for _, case in ipairs({
    { name = 'HP and MP', low_hp = 300, low_mp = 100 },
    { name = 'HP only', low_hp = 300, low_mp = 300 },
    { name = 'MP only', low_hp = 900, low_mp = 100 },
    { name = 'MP drops to zero', low_hp = 900, low_mp = 0 },
}) do
    sit(900, 300, 900, 300);
    local before = resting.info(1);
    resting.on_max_vitals(1, case.low_hp, case.low_mp);
    check(case.name .. ': the lower maximums remain full', resting.is_full());
    resting.on_max_vitals(2, 900, 300);
    local after = resting.info(2);
    local hp, mp = resting.until_each_full(2);
    local _, _, _, gained_hp, gained_mp = resting.progress(2);
    check(case.name .. ': raising maximums cannot restore the lost current vitals', not resting.is_full()
        and (case.low_hp < 900 and positive(hp) or case.low_hp == 900 and hp == 0)
        and (case.low_mp < 300 and positive(mp) or case.low_mp == 300 and mp == 0));
    check(case.name .. ': maximum changes preserve the resting schedule and invent no tick',
        after.ticks == before.ticks and after.next_tick == before.next_tick and after.accepted == before.accepted
        and after.last_tick == before.last_tick and gained_hp == 0 and gained_mp == 0);
end
sit(900, 300, 900, 300);
resting.on_vitals(0, 900, 300, 500, 900, 300);
resting.on_vitals(21, 900, 300, 400, 900, 300);
resting.on_vitals(30, 900, 300, 300, 900, 300);
resting.on_vitals(42, 900, 300, 200, 900, 300);
local phase_before = resting.info(42);
resting.on_max_vitals(43, 300, 100); resting.on_max_vitals(44, 900, 300);
local phase_after = resting.info(44);
check('lowering and restoring caps keep an already observed tick pattern', phase_before.pattern_known
    and phase_after.pattern_known and phase_after.ticks == 3 and phase_after.next_tick == 51
    and phase_after.last_tick == 42 and phase_after.accepted == phase_before.accepted);
sit(200, 25, 900, 300);
resting.on_max_vitals(1, 300, 100);
resting.on_max_vitals(2, 900, 300);
check('values already below a lower maximum remain unchanged', resting.goal_progress(2, 'hp', 'amount', 200).reached
    and not resting.goal_progress(2, 'hp', 'amount', 201).reached
    and resting.goal_progress(2, 'mp', 'amount', 25).reached
    and not resting.goal_progress(2, 'mp', 'amount', 26).reached);

sit(900, 300, 900, 300);
resting.on_max_vitals(1, 300, 100); resting.on_max_vitals(2, 900, 300);
resting.on_vitals(21, 310, 112, 0, 900, 300);
local observed = resting.info(21);
check('the next real gain is measured from the clamped current vitals', observed.accepted == 1
    and observed.next_hp == 11 and observed.next_mp == 13 and observed.next_tick == 30);

-- A current-vitals packet may arrive before its increased maximums; do not clamp that packet itself.
sit(300, 100, 300, 100);
resting.on_vitals(1, 600, 200, 0, 300, 100);
resting.on_max_vitals(2, 900, 300);
check('a current packet preceding the maximum increase retains its actual values',
    resting.goal_progress(2, 'hp', 'amount', 600).reached and not resting.goal_progress(2, 'hp', 'amount', 601).reached
    and resting.goal_progress(2, 'mp', 'amount', 200).reached and not resting.goal_progress(2, 'mp', 'amount', 201).reached);

-- Include the live controller's hidden-card and completion-sound decisions with mocked client state.
resting.reset();
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local s, hud, sound = MOCK.settings.current, require('ui.hud'), require('ui.sound');
s.resting.hide_when_full, s.resting.show_each_full, s.resting.show_until_full, s.resting.sound = true, true, true, true;
MOCK.player.hp_max, MOCK.player.mp_max, MOCK.player.status = 900, 300, 0;
local shown, plays = nil, 0;
hud.draw_resting = function(view) shown = { full = view.full, hp = view.hp_full_in, mp = view.mp_full_in }; end;
sound.play = function() plays = plays + 1; return true; end;
MOCK.fire('packet_in', MOCK.vitals_packet(MOCK.player.server_id, 900, 300, 0));
MOCK.frame(0.25); MOCK.player.status = 33; MOCK.frame(0.25);
MOCK.player.hp_max, MOCK.player.mp_max = 300, 100; MOCK.frame(0.25);
check('a lower full cap keeps the resting card hidden without a completion sound', resting.is_full() and shown == nil and plays == 0);
MOCK.player.hp_max, MOCK.player.mp_max = 900, 300; MOCK.frame(0.25);
check('restoring maximums reveals both recovery forecasts without another current packet', shown ~= nil
    and not shown.full and positive(shown.hp) and positive(shown.mp) and plays == 0);
MOCK.fire('packet_in', MOCK.vitals_packet(MOCK.player.server_id, 900, 300, 0)); MOCK.frame(0.25);
check('only subsequent real fullness plays the completion sound', resting.is_full() and plays == 1);
MOCK.frame(0.25);
check('remaining full does not repeat the sound', plays == 1);
check('maximum transitions send no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or failed .. ' FAILED';
return table.concat(out, '\n');
