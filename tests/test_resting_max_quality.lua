-- A percentage-derived lower bound is not an exact cap for goals or next-gain labels.
local resting = require('core.resting');
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 0.0001; end
local function sit(hp, mp, maximum_hp, maximum_mp, hp_quality, mp_quality)
    resting.reset();
    resting.on_vitals(-1, hp, mp, 0, maximum_hp, maximum_mp, hp_quality, mp_quality);
    resting.on_model({ resting_key = 'cap-quality', hp_base = 10, hp_step = 1,
        mp_base = 12, mp_step = 1, hp_known = true, mp_known = true,
        regen_known = true, refresh_known = true });
    resting.start(0);
end

sit(1, 20, 51, 100, 'unknown', false);
local goal = resting.goal_progress(0, 'hp', 'percent', 1);
check('an unknown cap cannot turn a one-percent goal into reached', not goal.reached
    and goal.seconds == nil and goal.ticks == nil and goal.confidence == 'unknown');
goal = resting.goal_progress(0, 'both', 'percent', 1);
check('a joint percentage goal waits for each selected cap', not goal.reached and goal.seconds == nil);
goal = resting.goal_progress(0, 'hp', 'percent', 0);
check('zero percent remains reached without a known cap', goal.reached and goal.seconds == 0);
goal = resting.goal_progress(0, 'hp', 'amount', 100);
check('an amount goal is not clamped to an unknown lower bound', goal.target_hp == 100
    and not goal.reached and goal.seconds == nil and goal.confidence == 'unknown');
goal = resting.goal_progress(0, 'hp', 'amount', 1);
check('observed current HP can confirm an absolute goal', goal.reached and goal.seconds == 0);
goal = resting.goal_progress(0, 'hp', 'amount', 30);
check('an absolute goal within the lower bound can retain its forecast', goal.target_hp == 30
    and not goal.reached and near(goal.seconds, 41.4) and goal.ticks == 3);
goal = resting.goal_progress(0, 'mp', 'percent', 50);
check('unknown HP does not suppress a known MP goal forecast', goal.target_hp == 0
    and goal.target_mp == 50 and near(goal.seconds, 41.4) and goal.ticks == 3);
local hp, mp, confidence = resting.next_gains();
check('unknown HP next gain does not erase the known MP gain', hp == nil and mp == 12
    and confidence.hp == 'unknown' and confidence.mp == 'known');
local hp_full, mp_full = resting.until_each_full(0);
check('goal lookups do not invent a full estimate for the unknown stat', hp_full == nil
    and mp_full ~= nil and not resting.is_full());
resting.stop();
goal = resting.goal_progress(1, 'hp', 'amount', 100);
check('standing keeps the requested amount without an invented forecast', goal.target_hp == 100
    and not goal.reached and goal.seconds == nil);

sit(20, 1, 100, 51, false, 'unknown');
goal = resting.goal_progress(0, 'mp', 'percent', 1);
check('unknown MP gets the same percentage guard as HP', not goal.reached and goal.seconds == nil);
goal = resting.goal_progress(0, 'hp', 'percent', 50);
check('unknown MP leaves the known HP goal independent', near(goal.seconds, 41.4) and goal.target_mp == 0);
sit(1, 0, 51, 0, 'unknown', false);
goal = resting.goal_progress(0, 'mp', 'percent', 100);
check('a known zero MP pool remains reached', goal.reached and goal.seconds == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
