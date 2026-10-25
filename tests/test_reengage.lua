-- The re-engage display keeps a fixed cooldown estimate after a confirmed departure.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) <= 1e-6; end

local attack = require('core.attack');
local function fresh(now, seconds, key, joined_late, initial)
    attack.reset();
    attack.forget_learned();
    attack.engage(now or 0, seconds or 8, key or 'reengage', joined_late, initial);
end

attack.reset();
attack.disengage(10, true);
check('loading idle cannot invent a cooldown', attack.reengage_progress(10) == nil);

fresh();
attack.disengage();
check('the legacy departure keeps the feature off', attack.reengage_progress(1) == nil and not attack.is_active());
for _, enabled in ipairs({ false, 0, 1, 'true', {} }) do
    fresh();
    attack.disengage(1, enabled);
    check('only a true toggle enables retention: ' .. tostring(enabled), attack.reengage_progress(1) == nil);
end

fresh(0, 4.5);
attack.disengage(1, true);
local progress = attack.reengage_progress(1);
check('the 1.5 second floor is not rounded to a server tick', progress and near(progress.duration, 1.5)
    and near(progress.left, 1.5) and progress.fill == 0 and not progress.unknown and not progress.elapsed);
check('retention does not keep the combat clock active', not attack.is_active() and attack.progress(1) == nil);
local same = attack.reengage_progress(1.75);
check('HUD frames reuse the same view table', same == progress and near(same.left, 0.75) and near(same.fill, 0.5));
progress = attack.reengage_progress(2.5);
check('the deadline shows elapsed with no extra combat cycle', progress and progress.elapsed
    and progress.left == 0 and progress.fill == 1 and attack.progress(2.5) == nil);
check('elapsed remains visible briefly', attack.reengage_progress(2.999) ~= nil);
check('the display expires at its visibility deadline', attack.reengage_progress(3) == nil);

fresh(0, 16);
attack.on_round(2.8, 16, 'reengage');
attack.disengage(3, true);
progress = attack.reengage_progress(3);
check('heavy Slow retains the full 13 second cooldown', progress and progress.duration == 13 and progress.left == 13);
check('automatic visibility never caps a longer cooldown', near(attack.reengage_progress(14).left, 2));
check('a long cooldown still shows elapsed', attack.reengage_progress(16).elapsed);
check('a long cooldown expires after its elapsed grace', attack.reengage_progress(16.5) == nil);

fresh();
attack.on_round(2.8, 8, 'reengage');
attack.disengage(10.7, true, { last_target = 123, cause = 'manual' });
local info = attack.info(10.7);
check('a manual hint cannot prove the shorter remaining-time path', info.reengage.duration == 5
    and info.reengage.conservative and near(info.reengage.remaining, 0.1));
check('departure diagnostics preserve the previous target', info.reengage.last_target == 123 and info.reengage.cause == 'manual');
local deadline, expires = info.reengage.deadline, info.reengage.expires;
attack.disengage(11, true, { cause = 'target died' });
info = attack.info(11);
check('repeated departures cannot restart or extend retention', info.reengage.deadline == deadline
    and info.reengage.expires == expires and info.reengage.cause == 'manual');
attack.on_round(11, 2, 'idle-changed');
attack.delay_in_use(2, 'idle-changed');
attack.relearn();
info = attack.info(12, 2, 'idle-changed');
check('idle rounds, gear previews and relearning cannot move the deadline', info.reengage.deadline == deadline
    and info.reengage.sampled_delay == 8 and info.reengage.sampled_at == 2.8 and info.samples == 0);

fresh();
attack.on_round(2.8, 8, 'reengage');
attack.on_cast_begin(4, 'spell');
attack.on_disabled(5, 10);
attack.on_out_of_reach('too far');
attack.disengage(10, true);
info = attack.info(10);
check('departure captures held timing before it clears combat state', near(info.reengage.remaining, 6.8)
    and info.reengage.holding == 'spell' and info.reengage.disabled == 10 and info.reengage.stalled);
check('retained holds do not freeze the cooldown', near(attack.reengage_progress(12).left, 3)
    and info.holding == nil and info.disabled == nil and info.reason == nil);

fresh(0, 8, 'unknown-initial', false, false);
attack.disengage(1, true);
progress = attack.reengage_progress(1);
check('an unknown initial sample remains unknown', progress and progress.unknown
    and progress.left == nil and progress.duration == nil and progress.fill == 0 and not progress.elapsed);
check('unknown timing remains readable for five seconds without a countdown', attack.reengage_progress(5.99).unknown
    and attack.reengage_progress(6) == nil);

fresh(0, 6, 'latent', false, 8);
attack.disengage(1, true);
check('the initial sample can differ from the drawn-weapon model', attack.info(1).reengage.sampled_delay == 8
    and attack.info(1).reengage.duration == 5);
fresh(0, 6, 'latent', false, 8);
attack.on_round(2.8, 6, 'latent');
attack.disengage(3, true);
check('a permitted round replaces the initial pre-latent sample', attack.info(3).reengage.sampled_delay == 6
    and attack.info(3).reengage.duration == 3);

fresh(0, 8, 'joined', true, 8);
attack.disengage(1, true);
check('joining an existing fight cannot recover its last sampled interval', attack.reengage_progress(1).unknown);
fresh(0, 8, 'joined', true, 8);
attack.on_paralyzed(3, 8, 'joined');
attack.disengage(3.1, true);
check('ambiguous paralysis cannot establish a joined fight sample', attack.reengage_progress(3.1).unknown);
fresh(0, 8, 'joined', true, false);
attack.on_round(2, 6, 'joined');
attack.disengage(3, true);
check('a real round establishes timing after joining late', attack.reengage_progress(3).duration == 3);

fresh(0, 8, 'learned');
attack.on_round(2.8, 8, 'learned');
for _, at in ipairs({ 12.8, 22.8, 32.8 }) do attack.on_round(at, 8, 'learned'); end
check('the fixture learns a ten second interval', near(attack.info(33).delay, 10) and near(attack.info(33).sampled_delay, 10));
attack.relearn();
info = attack.info(33);
check('relearning changes the model but preserves the sampled interval', info.delay == 8 and near(info.sampled_delay, 10));
attack.disengage(33, true);
check('the cooldown uses the last sample after relearning', near(attack.reengage_progress(33).duration, 7));

fresh(0, 8, 'uncertain', false, false);
attack.on_round(2.8, 8, 'uncertain', false);
attack.disengage(3, true);
check('an uncalibrated unknown modifier keeps timing unknown', attack.reengage_progress(3).unknown);
fresh(0, 8, 'uncertain', false, false);
attack.on_round(2.8, 8, 'uncertain', false);
for _, at in ipairs({ 12.8, 22.8, 32.8 }) do attack.on_round(at, 8, 'uncertain', false); end
attack.disengage(33, true);
check('clean measured intervals can calibrate an unknown modifier', near(attack.reengage_progress(33).duration, 7));

fresh(0, 8, 'uncertain', false, false);
attack.on_round(2.8, 8, 'uncertain', false);
attack.on_paralyzed(10.7, 8, 'uncertain', false);
attack.disengage(11, true);
check('an uncalibrated failed round does not make an unknown modifier known', attack.reengage_progress(11).unknown);
local march_key = '1:0:1/75:0/0:214';
fresh(0, 8, march_key, false, false);
attack.on_round(2.8, 8, march_key, false);
for _, at in ipairs({ 12.8, 22.8, 32.8 }) do attack.on_round(at, 8, march_key, false); end
attack.on_paralyzed(42.7, 8, march_key, false);
attack.disengage(43, true);
check('a failed round retains the same March key and calibrated interval', near(attack.reengage_progress(43).duration, 7));

for _, method in ipairs({ 'on_round', 'on_paralyzed' }) do
    for _, known in ipairs({ true, false }) do
        fresh(0, 8, march_key, false, false);
        attack.on_round(2.8, 8, march_key, known);
        for _, at in ipairs({ 12.8, 22.8, 32.8 }) do attack.on_round(at, 8, march_key, known); end
        attack[method](42.8, 8, march_key, known, true);
        attack.disengage(43, true);
        check(method .. ' keeps a pending change unknown despite calibration and known=' .. tostring(known),
            attack.reengage_progress(43).unknown and attack.info(43).sampled_delay == nil);
    end
end

fresh(0, 8, 'slow');
attack.on_round(2.8, 8, 'slow');
attack.on_paralyzed(10.7, 16, 'slower');
info = attack.info(10.7);
check('a due failed round resamples newly changed attack speed', info.delay == 16 and info.sampled_delay == 16
    and info.sampled_at == 10.7 and info.samples == 0 and info.next_in == 16);
attack.disengage(11, true);
check('the failed round sample reaches the cooldown', attack.reengage_progress(11).duration == 13);

fresh(0, 8, 'slow');
attack.on_round(2.8, 8, 'slow');
attack.on_paralyzed(4, 16, 'slower');
info = attack.info(4);
check('an early failed ability keeps the preceding round sample', info.sampled_delay == 8 and info.sampled_at == 2.8);
attack.disengage(5, true);
check('a failed ability does not use the newly changed speed', attack.reengage_progress(5).duration == 5);

fresh(0, 8, 'slow');
attack.on_round(2.8, 8, 'slow');
attack.on_paralyzed(10.7);
attack.disengage(11, true);
check('a failed round without a current model cannot reuse stale speed', attack.reengage_progress(11).unknown);

fresh(0, 8, 'held');
attack.on_round(2.8, 8, 'held');
attack.on_cast_begin(4, 'ranged');
attack.on_cast_end(5);
attack.on_paralyzed(5.1, 16, 'slower');
check('a failure following a ranged interrupt cannot resample melee speed', attack.info(5.1).sampled_delay == 8);
attack.disengage(5.11, true);
attack.engage(5.12, 4, 'next', false, 4);
attack.on_paralyzed(7.8, 6, 'next-slow');
check('the next engagement does not inherit old hold state', attack.info(7.8).sampled_delay == 6);

fresh();
attack.disengage(1, true);
attack.engage(2, 4, 'new', false, false);
local _, first = attack.progress(2);
check('successful engage clears retention and starts a fresh first attack', attack.reengage_progress(2) == nil
    and attack.is_active() and near(first, 2.8));
attack.on_round(4.8, 4, 'new');
check('the idle interval is never learned', attack.info(4.8).samples == 0);

for _, method in ipairs({ 'cancel_reengage', 'reset', 'forget_learned', 'disengage' }) do
    fresh();
    attack.disengage(1, true);
    attack[method]();
    check(method .. ' clears retained timing', attack.reengage_progress(1) == nil);
end

for _, sample in ipairs({ -1, 0, math.huge, -math.huge, 0 / 0 }) do
    fresh(0, 8, 'invalid', false, sample);
    attack.disengage(1, true);
    check('an invalid initial interval stays unknown: ' .. tostring(sample), attack.reengage_progress(1).unknown);
end

table.insert(out, fails == 0 and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
