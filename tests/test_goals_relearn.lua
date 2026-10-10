local resting, tp = require('core.resting'), require('core.tp');
local attack, enemy = require('core.attack'), require('core.enemy');
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 0.0001; end
local function sit(hp, mp, maximum_hp, maximum_mp, extra)
    resting.reset(); resting.on_buffs(0, {});
    resting.on_vitals(-1, hp, mp, 0, maximum_hp, maximum_mp);
    local model = { resting_key = 'goals', hp_base = 10, hp_step = 1, mp_base = 12, mp_step = 1,
        hp_known = true, mp_known = true, regen_known = true, refresh_known = true };
    for key, value in pairs(extra or {}) do model[key] = value; end
    resting.on_model(model); resting.start(0);
end

sit(50, 0, 100, 50);
local full_before = resting.until_full(0);
local goal = resting.goal_progress(0, 'hp', 'percent', 80);
check('HP percentage goal uses three growing ticks', near(goal.seconds, 41.4) and goal.ticks == 3 and goal.target_hp == 80 and goal.target_mp == 0);
goal = resting.goal_progress(0, 'mp', 'percent', 50);
check('MP percentage goal is independent of HP', near(goal.seconds, 31.4) and goal.ticks == 2 and goal.target_mp == 25);
goal = resting.goal_progress(0, 'both', 'amount', 80);
check('absolute both goal clamps each maximum separately', goal.target_hp == 80 and goal.target_mp == 50 and near(goal.seconds, 51.4));
check('goal lookup leaves actual-full prediction and state unchanged', resting.until_full(0) == full_before and not resting.is_full() and select(3, resting.progress(0)) == 0);
goal = resting.goal_progress(0, 'hp', 'percent', 50);
check('reached goal reports zero without marking actual full', goal.reached and goal.seconds == 0 and goal.ticks == 0 and not resting.is_full());
goal = resting.goal_progress(0, 'both', 'percent', 200);
check('percent above100 clamps to actual maxima', goal.target_hp == 100 and goal.target_mp == 50 and goal.seconds == full_before);
check('negative goals clamp to zero and are reached', resting.goal_progress(0, 'both', 'amount', -5).reached);
check('invalid goal inputs are ignored', resting.goal_progress(0, 'tp', 'amount', 500) == nil and resting.goal_progress(0, 'hp', 'percent', 0/0) == nil);
sit(50, 0, 101, 0);
goal = resting.goal_progress(0, 'hp', 'percent', 50);
check('fractional percentage threshold rounds up to next whole HP', goal.target_hp == 51 and not goal.reached);
check('zero-max MP goal is already reached', resting.goal_progress(0, 'mp', 'percent', 100).reached);
resting.stop();
goal = resting.goal_progress(1, 'hp', 'amount', 80);
check('standing retains target but has no resting ETA', goal.target_hp == 80 and goal.seconds == nil and not goal.reached);
sit(100, 90, 100, 100, { refresh = 2 });
goal = resting.goal_progress(0, 'mp', 'amount', 95);
check('passive recovery can reach a goal before any resting tick', goal.seconds == 9 and goal.ticks == 0);
sit(70, 80, 100, 100, { refresh_down = 2 });
goal = resting.goal_progress(0, 'both', 'amount', 80);
check('joint goal rechecks MP that drains while HP catches up', near(goal.seconds, 31.4) and goal.ticks == 2);
check('HP-only goal ignores an unrelated MP deficit', near(resting.goal_progress(0, 'hp', 'amount', 80).seconds, 21.4));
resting.on_buffs(0, { [8] = true });
goal = resting.goal_progress(0, 'hp', 'amount', 80);
check('blocked recovery has no goal ETA', goal.seconds == nil and goal.confidence == 'blocked');
check('a reached goal remains reached while healing is blocked', resting.goal_progress(0, 'mp', 'amount', 80).reached);

local loadout = { main = { id = 1, delay = 240, skill = 3 }, main_job = 1, main_level = 75,
    sub_job = 0, sub_level = 0, buffs = {}, modifiers = { store_tp = 0, tp_known = true, tp_key = 'zero', rounds_key = 'plain' } };
tp.forget(); tp.on_zone(); tp.on_engage(loadout); tp.on_target(1); tp.on_vitals(0, 0);
local timing = { active = true, source = 'observed', next_in = 3, delay = 4 };
for i = 1, 3 do
    tp.on_round(i * 4, 1, false, true, loadout); tp.on_vitals(i * 4 + 0.1, i * 64);
    if (i == 2) then check('TP seconds wait for three recent rounds', tp.time_to(320, 128, 9, timing) == nil); end
end
check('TP seconds use next due time plus remaining measured intervals', near(tp.time_to(320, 192, 13, timing), 7));
check('one remaining round uses only current next due time', tp.time_to(256, 192, 13, timing) == 3);
check('already reached TP goal takes zero seconds', tp.time_to(192, 192, 13, timing) == 0);
for _, flag in ipairs({ 'holding', 'disabled', 'reason', 'blocked', 'stalled', 'overdue', 'joined_late', 'next_interval_changed', 'transition' }) do
    timing[flag] = true;
    check('TP seconds hide during ' .. flag, tp.time_to(320, 192, 13, timing) == nil);
    timing[flag] = nil;
end
timing.source = 'estimated';
check('TP seconds reject a guessed attack interval', tp.time_to(320, 192, 13, timing) == nil);
timing.source = 'observed';
check('old round history cannot produce a current TP ETA', tp.time_to(320, 192, 40, timing) == nil);
tp.on_round(16, 1, false, true, loadout);
check('unfinished action and TP packet pair has no TP ETA', tp.time_to(320, 192, 16, timing) == nil);
check('TP relearn accepts a current model', tp.relearn());
local info = tp.info(16);
check('TP relearn preserves modeled potency and clears observations', info.per_hit == 64 and info.source == 'known' and info.samples == 0 and info.recent_rounds == 0);
tp.on_vitals(16.1, 256);
check('a pending old TP packet cannot restore discarded learning', tp.info(16.1).samples == 0 and not select(2, tp.per_hit()));
tp.on_round(20, 1, false, true, loadout); tp.on_vitals(20.1, 320);
check('clean TP learning resumes after selective relearn', tp.info(20.1).samples == 1 and select(2, tp.per_hit()));
tp.forget();
check('TP relearn reports no context before a model', not tp.relearn());

attack.reset(); attack.forget_learned();
local function train(key, start, estimate, interval)
    attack.engage(start, estimate, key);
    for i = 0, 3 do attack.on_round(start + 2.8 + i * interval, estimate, key); end
end
train('a', 0, 5, 4);
train('b', 30, 6, 5);
check('two independently learned timing buckets exist', attack.kept_count() == 2);
attack.on_ability(48); attack.on_cast_begin(49, 'spell');
local _, held_before = attack.progress(50);
check('attack relearn accepts the current bucket', attack.relearn());
local _, held_after, interval = attack.progress(50);
info = attack.info(50, 6, 'b');
check('attack relearn keeps scheduled attack and hold', near(held_before, held_after) and info.holding == 'spell' and interval == 6);
check('attack relearn clears only its current bucket', info.samples == 0 and info.source == 'estimated' and attack.kept_count() == 1);
attack.on_cast_end(55); attack.on_round(62.8, 6, 'b');
check('the gap crossing attack relearn is not learned', attack.info(62.8, 6, 'b').samples == 0);
attack.disengage();
check('another bucket retains its measured interval', near(attack.delay_in_use(5, 'a'), 4));
attack.reset();
check('attack relearn reports no context after reset', not attack.relearn());
attack.engage(0, 4, 'c'); attack.on_round(2.8, 4, 'c');
check('attack diagnostics expose a passed due time despite clamped next_in', attack.info(7, 4, 'c').overdue and attack.info(7, 4, 'c').next_in == 0);

enemy.reset(); enemy.forget_speeds();
local mob, other, copy = 0x01000200, 0x01000201, 0x01000202;
for i = 0, 3 do enemy.on_round(i * 6, mob, 1001); enemy.on_round(i * 4, other, 1001); end
enemy.remember(mob, 'Target'); enemy.remember(other, 'Other');
enemy.on_effect(19, mob, { effect = 13, power = 2500, exact = true, sure_for = 120, lasts = 120 }, true);
enemy.on_hold_begin(20, mob, 'spell');
local before = enemy.info(21, mob);
check('enemy relearn accepts current target', enemy.relearn(mob));
local after = enemy.info(21, mob);
check('enemy relearn preserves action hold, next attack and effects', before.left == after.left and after.holding == 'spell' and #after.effects == 1);
check('enemy relearn clears current samples and returns to modified base guess', after.samples == 0 and not after.learned and after.delay == 5);
check('enemy relearn leaves another monster learned', enemy.info(21, other).learned);
enemy.recall(21, copy, 'Target');
check('enemy relearn removes its remembered name speed', not enemy.has(copy));
enemy.on_hold_end(22, mob, false); enemy.on_round(28, mob, 1001);
check('enemy gap crossing relearn is not learned', enemy.info(28, mob).samples == 0);
check('enemy relearn reports missing target', not enemy.relearn(999));

if (failed > 0) then out[#out + 1] = tostring(failed) .. ' FAILED'; end
return table.concat(out, '\n');
