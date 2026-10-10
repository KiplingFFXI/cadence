-- Modeled recovery supplies an initial estimate; clean gains replace it without changing tick time.
local resting = require('core.resting');
local out, fails = {}, 0;
local function check(name, condition, detail)
    if (condition) then table.insert(out, 'ok   ' .. name);
    else
        fails = fails + 1;
        table.insert(out, 'FAIL ' .. name .. (detail and (' -> ' .. tostring(detail)) or ''));
    end
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 0.001; end
local function model(key, hp_base, hp_step, mp_base, mp_step, known)
    return { resting_key = key, hp_base = hp_base, hp_step = hp_step,
        mp_base = mp_base, mp_step = mp_step, hp_known = known, mp_known = known,
        unknown = known and {} or { 'food or traits' } };
end
local function sit(m, hp, mp, hp_max, mp_max)
    resting.reset();
    resting.on_buffs(0, {});
    resting.on_vitals(-1, hp, mp, 100, hp_max, mp_max);
    resting.on_model(m);
    resting.start(0);
end
local function target(now)
    local _, left = resting.progress(now);
    return now + left;
end

resting.reset();
check('no next gain without active vitals', resting.next_gains() == nil);
sit(model('blm75', 31, 4, 27, 3, true), 900, 100, 900, 190);
local hp, mp, confidence = resting.next_gains();
check('BLM75 starts at 27 MP before a tick', hp == 0 and mp == 27 and confidence.mp == 'known');
check('first full ETA includes the initial wait and three recovery ticks', near(resting.until_full(0), 41.4));
resting.on_vitals(21, 900, 127, 100, 900, 190);
hp, mp, confidence = resting.next_gains();
check('the first observation predicts 30, without adding the model twice', mp == 30 and confidence.mp == 'observed', mp);
resting.on_vitals(30, 900, 157, 100, 900, 190);
check('the next MP gain is 33', select(2, resting.next_gains()) == 33);
check('progress still reports the last actual gain', select(5, resting.progress(30)) == 30);

sit(model('signet900', 31, 4, 12, 1, true), 500, 0, 900, 0);
check('Signet75 and maxHP900 starts at 31 HP', resting.next_gains() == 31);
resting.on_vitals(21, 531, 0, 100, 900, 0);
check('Signet second gain is 35 HP', resting.next_gains() == 35);
resting.on_vitals(30, 566, 0, 100, 900, 0);
check('Signet third gain is 39 HP', resting.next_gains() == 39);
local before_target = target(31);
resting.on_model(model('signet1200', 31, 5, 12, 1, true));
resting.on_vitals(31, 566, 0, 100, 1200, 0);
check('a maxHP boundary uses the new slope at the existing tick index', resting.next_gains() == 41);
check('maximum changes preserve tick count and phase', select(3, resting.progress(31)) == 2
    and near(target(31), before_target));

sit(model('old gear', 10, 1, 27, 3, true), 1000, 100, 1000, 1000);
resting.on_vitals(21, 1000, 127, 100, 1000, 1000);
resting.on_vitals(30, 1000, 157, 100, 1000, 1000);
before_target = target(31);
resting.on_model(model('new gear', 10, 1, 37, 3, true));
check('known hMP swap immediately changes next gain', select(2, resting.next_gains()) == 43);
check('hMP swap preserves the due tick', near(target(31), before_target));
-- This packet was produced before the gear snapshot changed. Keep its timing, not its old amount.
resting.on_vitals(42, 1000, 190, 100, 1000, 1000);
hp, mp, confidence = resting.next_gains();
check('a packet crossing the swap cannot recalibrate new gear', mp == 46 and confidence.mp == 'known', mp);
check('the crossing packet can still establish tick time', select(3, resting.progress(42)) == 3
    and resting.seen_at() == 42);
resting.on_vitals(51, 1000, 236, 100, 1000, 1000);
check('clean observations resume under the new gear', select(2, resting.next_gains()) == 49);
resting.on_model(model('weapon swap', 10, 1, 37, 3, true));
resting.on_vitals(59, 1000, 236, 0, 1000, 1000);
check('a crossing weapon TP loss is not a resting tick', select(3, resting.progress(59)) == 4);

sit(model('capped', 10, 1, 27, 3, true), 1000, 100, 1000, 120);
resting.on_vitals(21, 1000, 120, 100, 1000, 120);
hp, mp, confidence = resting.next_gains();
check('a capped gain is not learned as full potency', mp == 0 and confidence.mp_uncapped == 30
    and confidence.mp == 'known', confidence.mp_uncapped);

sit(model('blocked', 31, 4, 27, 3, true), 500, 100, 900, 1000);
resting.on_buffs(0, { [8] = true });
resting.update(21.5);
resting.update(31);
hp, mp, confidence = resting.next_gains();
check('blocked next gains are zero and not a recovery ETA', hp == 0 and mp == 0
    and confidence.hp == 'blocked' and resting.until_full(31) == nil);
resting.on_buffs(33, {});
hp, mp = resting.next_gains();
check('blocked scheduled ticks keep the formula index advancing', hp == 39 and mp == 33);
resting.on_vitals(42, 539, 133, 100, 900, 1000);
check('recovery after a block advances once', select(3, resting.progress(42)) == 3
    and select(2, resting.next_gains()) == 36);

sit(model('unknown', 10, 1, 12, 1, false), 1000, 100, 1000, 1000);
hp, mp, confidence = resting.next_gains();
check('unknown sources retain an explicitly estimated prior', mp == 12 and confidence.mp == 'estimated'
    and confidence.unknown[1] == 'food or traits');
resting.on_vitals(21, 1000, 127, 100, 1000, 1000);
hp, mp, confidence = resting.next_gains();
check('one unknown Clear Mind tick calibrates the amount but still estimates its slope', mp == 28
    and confidence.mp == 'estimated' and confidence.mp_step == 1);
resting.on_vitals(30, 1000, 157, 100, 1000, 1000);
hp, mp, confidence = resting.next_gains();
check('27 then30 establish the unknown slope and predict33 observed', mp == 33
    and confidence.mp == 'observed' and confidence.mp_step == 3);
resting.on_model(model('unknown', 10, 1, 12, 1, false));
check('an unchanged snapshot keeps learned gains', select(2, resting.next_gains()) == 33);
local transitioning = model('unknown', 10, 1, 12, 1, false);
transitioning.transition = true;
resting.on_model(transitioning);
hp, mp, confidence = resting.next_gains();
check('an unrelated equipment notification keeps the observed prior', mp == 33
    and confidence.mp == 'observed' and confidence.transition);
resting.on_vitals(42, 1000, 257, 100, 1000, 1000);
resting.on_model(model('unknown', 10, 1, 12, 1, false));
hp, mp, confidence = resting.next_gains();
check('a transient crossing cannot replace that observation', mp == 36
    and confidence.mp == 'observed' and not confidence.transition, mp);
resting.on_model(model('different food', 10, 1, 22, 1, false));
check('source changes discard old hidden corrections', select(2, resting.next_gains()) == 25);

sit(model('refresh', 10, 1, 12, 1, true), 1000, 100, 1000, 1000);
resting.on_vitals(3, 1000, 103, 100, 1000, 1000);
resting.on_vitals(6, 1000, 106, 100, 1000, 1000);
resting.on_vitals(21, 1000, 121, 100, 1000, 1000);
hp, mp, confidence = resting.next_gains();
check('Refresh is removed before calibrating the resting part', mp == 13 and confidence.mp == 'observed', mp);
check('the last actual gain still includes the simultaneous Refresh', select(5, resting.progress(21)) == 15);

resting.stop();
check('standing has no next resting gain', resting.next_gains() == nil);
resting.reset();
resting.on_vitals(-1, 500, 100, 0, 1000, 400);
resting.start(0);
check('without a model the existing observation-only ETA waits', resting.until_full(0) == nil);
resting.on_vitals(21, 510, 112, 0, 1000, 400);
resting.on_vitals(30, 521, 126, 0, 1000, 400);
hp, mp, confidence = resting.next_gains();
check('without a model observed slopes still predict gains', hp == 12 and mp == 16
    and confidence.hp == 'observed');
check('the existing observation-only ETA still works', resting.until_full(30) ~= nil);


-- Once the phase is established, the full ETA follows actual 9/9/12 passes.
sit(model('phase', 10, 1, 27, 3, true), 900, 100, 900, 300);
local initial_seconds, initial_meta = resting.until_full(0);
check('before phase observations the full ETA is marked estimated', initial_seconds ~= nil
    and initial_meta.confidence == 'estimated');
resting.on_vitals(21, 900, 127, 100, 900, 300);
resting.on_vitals(30, 900, 157, 100, 900, 300);
resting.on_vitals(42, 900, 190, 100, 900, 300);
local seconds, meta = resting.until_full(42);
check('known phase fills on51,60,72 rather than a flat10s series', near(seconds, 30)
    and meta.ticks == 3 and meta.mp_ticks == 3 and meta.confidence == 'observed', seconds);
check('bounded timing diagnostics count accepted observations', resting.info(42).accepted == 3
    and resting.info(42).last_decision == 'recovery tick');

local passive = model('gear refresh', 10, 1, 27, 3, true);
passive.refresh, passive.refresh_known = 3, true;
sit(passive, 900, 100, 900, 211);
resting.on_vitals(3, 900, 103, 100, 900, 211);
resting.on_vitals(6, 900, 106, 100, 900, 211);
resting.on_vitals(21, 900, 136, 100, 900, 211);
resting.on_vitals(30, 900, 169, 100, 900, 211);
resting.on_vitals(42, 900, 205, 100, 900, 211);
seconds, meta = resting.until_full(42);
check('Refresh can fill between resting ticks with zero resting ticks remaining', seconds == 6
    and meta.ticks == 0 and meta.mp_confidence == 'observed', seconds);
check('the next healing amount excludes gear Refresh', select(3, resting.next_gains()).mp_uncapped == 36);

sit(passive, 900, 100, 900, 1000);
resting.on_vitals(3, 900, 105, 100, 900, 1000);
resting.on_vitals(6, 900, 110, 100, 900, 1000);
resting.on_vitals(21, 900, 142, 100, 900, 1000);
check('observed net Refresh replaces gear plus unknown spell instead of adding twice',
    resting.info(21).regen_mp == 5 and select(2, resting.next_gains()) == 30);

local drain = model('refresh drain', 10, 1, 27, 3, true);
drain.refresh_down = 2;
sit(drain, 900, 100, 900, 1000);
resting.on_vitals(3, 900, 98, 100, 900, 1000);
resting.on_vitals(6, 900, 96, 100, 900, 1000);
resting.on_vitals(21, 900, 121, 100, 900, 1000);
check('signed MP drain is removed from the observed net resting gain',
    select(2, resting.next_gains()) == 30 and resting.info(21).regen_mp == -2);
local drain_eta = resting.until_full(21);
local clean = model('clean', 10, 1, 27, 3, true);
resting.on_model(clean);
check('MP drain lengthens full ETA without lowering next healing potency',
    resting.until_full(21) < drain_eta and select(2, resting.next_gains()) == 30);

local negative = model('negative raw regen', 10, 1, 27, 3, true);
negative.regen, negative.refresh = -5, -3;
sit(negative, 500, 100, 900, 300);
check('negative raw Regen and Refresh clamp to zero rather than draining',
    resting.info(0).regen_hp == 0 and resting.info(0).regen_mp == 0);
negative.regen_down = 1;
resting.on_model(negative);
check('HP drain that breaks healing has no uninterrupted full ETA', resting.until_full(0) == nil);


local full_then_drain = model('full MP can drain', 10, 1, 12, 1, true);
full_then_drain.refresh_down = 2;
sit(full_then_drain, 90, 100, 100, 100);
local hp_first, mp_first = resting.until_each_full(0);
seconds, meta = resting.until_full(0);
check('MP full now is not assumed to remain full while HP recovers', near(hp_first,21.4)
    and mp_first == 0 and near(seconds,31.4) and meta.ticks == 2,seconds);
resting.on_vitals(1,100,100,100,100,100);
local _, _, _, all_full = resting.until_each_full(1);
check('already full vitals need zero more recovery ticks', all_full.ticks == 0);

table.insert(out, fails == 0 and 'ALL OK' or (fails .. ' FAILED'));
return table.concat(out, '\n');
