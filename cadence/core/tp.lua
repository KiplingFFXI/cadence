--[[
    Your TP per hit, and how many rounds until 1000 TP.

    Phoenix gives TP the old way, from before Seekers of Adoulin (its soa_tp_gain era module). Every
    hit that lands in a round gives the same TP. Your weapon's base delay and your Store TP set it.
    A Samurai's Zanshin hit is the one exception. Ikishoten merits add to it. Misses, parries,
    shadows and hits that did no damage give none. Haste doesn't change it.
    Known gear, traits, merits and effects give the first guess. Anything the client cannot identify
    is left to your own TP. The change right after one of your rounds gets
    split across that round's hits. A monster hitting you, a weapon skill or Regain can move your TP
    around then too. When that happens the change doesn't count.

    Rounds to 1000 also counts TP that isn't from your own hits, like a monster hitting you or
    countering you, its TP moves and spells, or Regain. From one of your rounds to the next, whatever
    your TP went up by beyond what your hits gave is added up. Each of your rounds moves an average a
    third of the way toward that. A stretch doesn't count when another action of yours is in it, when
    your TP went down or reached 3000, for 24 seconds after Meditate, or when your next round came
    late. Each fight starts it over.
]]

local delay = require('core.delay');

local tp = {};

local TP_CAP = 3000;

-- Your round's TP update comes right behind it, in the same server tick.
local SAME_BATCH_SECONDS = 0.5;

-- After TP rises with nothing behind it, like Regain or Meditate, changes aren't used for this long.
local QUIET_SECONDS = 6;

-- A buff that adds TP on its own, and one that makes weapon skills free.
local REGAIN        = 170;
local MEIKYO_SHISUI = 54;

-- Ikishoten merits give a Samurai's Zanshin hits extra TP. Merits start at 75.
local JOB_SAM         = 12;
local IKISHOTEN_LEVEL = 75;

-- Recent rounds kept for the hits per round, and how many guessed rounds start it off.
local ROUNDS_KEPT    = 16;
local PRIOR_ROUNDS   = 2;
local PRIOR_HIT_RATE = 0.9;

-- TP from anything but your own hits. Each of your rounds moves the average a third of the way toward
-- what came in since the round before, so it catches up in a few rounds.
local OTHER_WEIGHT = 1 / 3;

-- A round more than this many times your delay after the last one, plus a server tick, had a pause in
-- it, like casting or walking back into reach. The auto attack timer uses the same rule.
local LONGEST_STRETCH_RATIO = 1.5;
local SERVER_TICK           = 0.4;

-- Meditate gives TP every 3 seconds with no buff the client can see. With Myochin Kabuto and Saotome
-- Kote it lasts 23 seconds, and one more covers its last tick.
local MEDITATE         = 63;
local MEDITATE_SECONDS = 24;

local state = {
    key         = nil,   -- The weapons, jobs and modifiers the numbers below go with.
    weapon_key  = nil,   -- A modifier-only change keeps the measured attacks per round.
    rounds_key  = nil,
    target      = nil,
    model_known = false,
    transition  = false,
    samples     = 0,
    rejected    = 0,
    last_reason = nil,
    learned_at  = nil,
    suppressed  = false, -- Meikyo Shisui stops normal-hit TP, without changing the saved amount.
    guess       = nil,   -- TP per hit worked out from your weapon.
    per_hit     = nil,   -- TP per hit, once it was learned from your own hits.
    last_sample = nil,
    hits        = {},    -- Hits that gave TP in your recent rounds.
    hit_times   = {},
    attacks     = 1,     -- How many attacks a round has. Two weapons and fists have 2.
    pending     = nil,   -- The hits in a round whose TP update hasn't come yet, and when the round came.
    pending_at  = nil,
    own_round   = false, -- One of your rounds came since the last update.
    stirred     = false, -- Something else that changes TP happened since the last update.
    quiet_until = 0,
    last_tp     = nil,   -- Your TP from the last update.
    own_hits    = 0,     -- Hits that gave TP in your last round, until its TP update comes.
    other       = nil,   -- TP from anything else since your last round, or nil when this stretch doesn't count.
    other_rate  = 0,     -- That TP in an average round lately.
    round_at    = nil,   -- When your last round came.
    other_from  = 0,     -- A stretch that starts before this doesn't count, since Meditate's TP is still coming.
};

-- TP per hit before Store TP, from the delay the server uses (LSB era module soa_tp_gain).
local function base_tp(d)
    if (d <= 180) then
        return math.floor(50 + (d - 180) * 15 / 180);
    elseif (d <= 450) then
        return math.floor(50 + (d - 180) * 65 / 270);
    elseif (d <= 480) then
        return math.floor(115 + (d - 450) * 15 / 30);
    elseif (d <= 530) then
        return math.floor(130 + (d - 480) * 15 / 50);
    end
    return math.floor(145 + (d - 530) * 35 / 470);
end

local function weapon_key(loadout)
    return ('%d:%d:%s:%d/%d:%d/%d'):format(
        loadout.main and loadout.main.id or 0,
        loadout.sub and loadout.sub.id or 0,
        loadout.sub_used and 'sub' or '',
        loadout.main_job, loadout.main_level,
        loadout.sub_job, loadout.sub_level);
end

local function loadout_key(loadout)
    local model = loadout.modifiers;
    return weapon_key(loadout) .. ':' .. (model and model.tp_key or '');
end

-- TP per hit worked out from your weapon and Store TP.
local function guess_for(loadout)
    local value = math.floor(base_tp(delay.tp_delay(loadout)) * (1 + delay.store_tp(loadout) / 100));
    local model = loadout.modifiers;
    if (model ~= nil and model.inhibit_tp ~= nil) then
        value = math.floor(value * (1 - model.inhibit_tp / 100));
    end
    return math.max(0, value);
end

local function forget_hits()
    for i = #state.hits, 1, -1 do
        state.hits[i] = nil;
        state.hit_times[i] = nil;
    end
end

-- A relevant loadout change means a new TP per hit. What was learned gets dropped.
local function use_loadout(loadout)
    local model = loadout.modifiers;
    state.suppressed = loadout.buffs[MEIKYO_SHISUI] == true;
    state.model_known = model ~= nil and model.tp_known == true;
    state.transition = model ~= nil and model.transition == true;
    local weapons = weapon_key(loadout);
    local rounds = weapons .. ':' .. (model and model.rounds_key or '');
    if (rounds ~= state.rounds_key) then
        state.rounds_key = rounds;
        forget_hits();
        state.other, state.other_rate = nil, 0;
    end
    state.weapon_key = weapons;
    local key = loadout_key(loadout);
    if (key == state.key) then return; end
    local changed = state.key ~= nil;
    state.key = key;
    state.guess = guess_for(loadout);
    state.attacks = delay.attacks_twice(loadout) and 2 or 1;
    state.per_hit, state.last_sample, state.learned_at = nil, nil, nil;
    state.samples, state.rejected, state.last_reason = 0, 0, nil;
    if (changed and (state.pending ~= nil or state.own_round)) then state.stirred = true; end
    state.pending, state.pending_at, state.other, state.other_rate = nil, nil, nil, 0;
end

local function rejected(reason)
    state.rejected = state.rejected + 1;
    state.last_reason = reason;
end

local function remember_hits(hits, now)
    table.insert(state.hits, hits);
    table.insert(state.hit_times, now);
    if (#state.hits > ROUNDS_KEPT) then
        table.remove(state.hits, 1);
        table.remove(state.hit_times, 1);
    end
end

-- Two samples in a row that agree lock it in. So does a first one that matches the guess.
-- A stray sample, like one a monster's hit slipped into, breaks the run but changes nothing.
local function learn(sample, now)
    if (sample == state.last_sample or (state.per_hit == nil and sample == state.guess)) then
        state.per_hit = sample;
    end
    state.last_sample, state.learned_at = sample, now;
    state.samples = state.samples + 1;
    state.last_reason = nil;
end

-- A relevant gear or effect change updates the first guess without touching the attack timer.
-- A packet received during an equipment swap cannot be used to learn either loadout.
function tp.on_loadout(loadout)
    use_loadout(loadout);
    if (loadout.modifiers ~= nil and loadout.modifiers.transition) then
        state.pending, state.pending_at, state.other = nil, nil, nil;
        state.stirred = true;
    end
end

-- A different target changes your hit rate and TP from being hit, not TP per normal hit.
function tp.on_target(target)
    if (target == nil or target == state.target) then return; end
    state.target = target;
    forget_hits();
    state.other, state.other_rate = nil, 0;
end

-- Hits that give TP in an average round. It starts with two guessed rounds counted in. That keeps it
-- steady from the first real one.
local function hits_per_round()
    local total = PRIOR_ROUNDS * state.attacks * PRIOR_HIT_RATE;
    for i = 1, #state.hits do
        total = total + state.hits[i];
    end
    return total / (#state.hits + PRIOR_ROUNDS);
end

-- You engaged. Works out the first guess before any round lands. TP from anything else starts over
-- each fight.
function tp.on_engage(loadout)
    use_loadout(loadout);
    state.other, state.other_rate = nil, 0;
end

--[[
    One of your melee rounds. `hits` is how many of its attacks gave TP. `hit_back` is true when the
    target countered inside it. A counter gives you TP too. `clean_start` is true when its first
    attack was a plain hit.
]]
function tp.on_round(now, hits, hit_back, clean_start, loadout)
    tp.on_loadout(loadout);
    remember_hits(hits, now);
    state.own_round = true;
    state.pending, state.pending_at = nil, nil;
    local buffs = loadout.buffs;

    -- The stretch since your last round ends here. One that ran long had a pause in it.
    if (state.other ~= nil
        and now - state.round_at <= delay.estimate(loadout) * LONGEST_STRETCH_RATIO + SERVER_TICK) then
        state.other_rate = state.other_rate + (state.other - state.other_rate) * OTHER_WEIGHT;
    end
    -- The next one only counts from below 3000, and not while Meditate's TP comes in.
    local counts = state.last_tp ~= nil and state.last_tp < TP_CAP and now >= state.other_from;
    state.other = counts and 0 or nil;
    state.round_at = now;
    -- Under Meikyo Shisui your hits give no TP, so all of the next change is from something else.
    state.own_hits = buffs[MEIKYO_SHISUI] and 0 or hits;

    -- Zanshin only attacks again in a one-attack round whose first attack wasn't a plain hit.
    local zanshin = not clean_start and state.attacks == 1
        and loadout.main_job == JOB_SAM and loadout.main_level >= IKISHOTEN_LEVEL;

    if (hits > 0 and not hit_back and not zanshin
        and not state.stirred and now >= state.quiet_until and not buffs[REGAIN] and not buffs[MEIKYO_SHISUI]
        and state.last_tp ~= nil and state.last_tp < TP_CAP) then
        state.pending, state.pending_at = hits, now;
    else
        local reason = hits <= 0 and 'no successful hits' or (hit_back and 'counter in round')
            or (zanshin and 'possible Zanshin bonus') or (state.transition and 'equipment or effect changing')
            or (buffs[MEIKYO_SHISUI] and 'Meikyo Shisui') or (buffs[REGAIN] and 'Regain')
            or (state.stirred and 'another action changed TP') or (now < state.quiet_until and 'unexplained TP gain')
            or (state.last_tp == nil and 'waiting for vitals') or 'TP cap';
        rejected(reason);
    end
end

-- Something besides your rounds that can change your TP, like a monster's action on you.
function tp.on_stir()
    state.stirred = true;
    state.pending = nil;
end

-- Another action of yours, like a weapon skill, a spell or a job ability. `ability` is the job ability's
-- id, or nil. The TP it moves isn't from being hit, so the stretch it's in doesn't count.
function tp.on_own_action(now, ability)
    tp.on_stir();
    state.other = nil;
    if (ability == MEDITATE) then
        state.other_from = now + MEDITATE_SECONDS;
    end
end

-- Your TP update arrived.
function tp.on_vitals(now, value)
    local last, own = state.last_tp, state.own_hits;
    state.last_tp, state.own_hits = value, 0;
    if (last == nil) then
        state.pending, state.stirred, state.own_round = nil, false, false;
        return;
    end

    local gain = value - last;
    if (state.pending ~= nil and now - state.pending_at <= SAME_BATCH_SECONDS) then
        if (gain > 0 and value < TP_CAP and gain % state.pending == 0) then
            learn(gain / state.pending, now);
        else
            rejected(value >= TP_CAP and 'TP cap' or 'TP gain does not match the round');
        end
    elseif (gain > 0 and not state.stirred and not state.own_round) then
        -- TP rose with nothing behind it, like Regain. Changes wait until that stops.
        state.quiet_until = now + QUIET_SECONDS;
    end

    -- What your own hits don't explain. TP going down or reaching 3000 means this stretch can't be
    -- measured. Until TP per hit is locked in, a change with your hits in it is left out.
    if (state.other ~= nil) then
        local unexplained = gain - own * (state.per_hit or 0);
        if (unexplained < 0 or value >= TP_CAP) then
            state.other = nil;
        elseif (own == 0 or state.per_hit ~= nil) then
            state.other = state.other + unexplained;
        end
    end
    state.pending, state.stirred, state.own_round = nil, false, false;
end

-- Rounds until `goal` TP from `value`, or nil once you're there or before anything is known.
function tp.rounds_to(goal, value)
    if (state.suppressed) then
        return value < goal and state.other_rate > 0 and math.max(1, math.ceil((goal - value) / state.other_rate)) or nil;
    end
    local per_hit = state.per_hit or state.guess;
    if (value >= goal or per_hit == nil or per_hit <= 0) then
        return nil;
    end
    local hits_needed = math.ceil((goal - value) / per_hit);
    -- TP from anything else each round counts as hits too, at your TP per hit.
    return math.max(1, math.floor(hits_needed / (hits_per_round() + state.other_rate / per_hit) + 0.5));
end

-- Successful normal hits needed from your own attacks. Future outside TP is not included.
function tp.hits_to(goal, value)
    if (value >= goal) then return 0; end
    local per_hit = state.per_hit or state.guess;
    if (state.suppressed or per_hit == nil or per_hit <= 0) then return nil; end
    return math.ceil((goal - value) / per_hit);
end

local function finite(number)
    return type(number) == 'number' and number == number and math.abs(number) < math.huge;
end

-- The current round's due time stays separate from the interval measured between later rounds.
function tp.time_to(goal, value, now, timing)
    if (not finite(goal) or not finite(value) or not finite(now) or goal < 0 or goal > TP_CAP) then return nil; end
    if (value >= goal) then return 0; end
    if (type(timing) ~= 'table' or not timing.active or timing.source ~= 'observed'
        or timing.holding or timing.disabled or timing.reason or timing.blocked or timing.stalled
        or timing.overdue or timing.late or timing.joined_late or timing.next_interval_changed or timing.transition
        or state.transition or state.suppressed or state.pending ~= nil or state.own_round
        or not finite(timing.delay) or timing.delay <= 0 or not finite(timing.next_in) or timing.next_in < 0
        or (state.per_hit == nil and not state.model_known)) then return nil; end
    local recent = 0;
    for _, at in ipairs(state.hit_times) do
        if (at <= now and now - at <= timing.delay * 4 + SERVER_TICK) then recent = recent + 1; end
    end
    if (recent < 3 or state.round_at == nil or now - state.round_at > timing.delay * LONGEST_STRETCH_RATIO + SERVER_TICK) then return nil; end
    local rounds = tp.rounds_to(goal, value);
    if (rounds == nil) then return nil; end
    return timing.next_in + (rounds - 1) * timing.delay;
end

-- Keep the current model and vitals, but discard measured amounts and any unfinished packet pair.
function tp.relearn()
    if (state.key == nil) then return false; end
    state.per_hit, state.last_sample, state.learned_at = nil, nil, nil;
    state.samples, state.rejected, state.last_reason = 0, 0, nil;
    state.pending, state.pending_at, state.own_round, state.own_hits = nil, nil, false, 0;
    state.other, state.other_rate, state.round_at = nil, 0, nil;
    state.stirred = true;
    forget_hits();
    return true;
end

function tp.hits_estimated()
    return state.transition or (state.per_hit == nil and not state.model_known);
end

function tp.is_estimated()
    return tp.hits_estimated() or #state.hits < 3;
end

-- A report can explain the estimate without exposing unrelated packets or chat.
function tp.info(now)
    return {
        per_hit = state.suppressed and 0 or (state.per_hit or state.guess), modeled_per_hit = state.guess,
        source = state.per_hit ~= nil and 'observed' or (state.model_known and 'known' or 'estimated'),
        samples = state.samples, rejected = state.rejected, last_rejection = state.last_reason,
        sample_age = state.learned_at and math.max(0, now - state.learned_at) or nil,
        recent_rounds = #state.hits, hits_per_round = hits_per_round(), other_tp_per_round = state.other_rate,
        transition = state.transition, suppressed = state.suppressed,
    };
end

-- About how much TP a round of yours has lately been getting from anything but your own hits.
function tp.other_per_round()
    return state.other_rate;
end

-- TP per hit in use, whether it was learned from your own hits, and the first guess it started from.
function tp.per_hit()
    if (state.suppressed) then
        return 0, false, state.guess;
    end
    return state.per_hit or state.guess, state.per_hit ~= nil, state.guess;
end

-- The same for the next fight with `loadout`. Other weapons, jobs or levels start from a new guess.
-- Nothing changes from looking.
function tp.per_hit_for(loadout)
    if (loadout.buffs[MEIKYO_SHISUI]) then
        return 0, false, 0;
    end
    if (loadout_key(loadout) == state.key) then
        return state.per_hit or state.guess, state.per_hit ~= nil, state.guess;
    end
    local guess = guess_for(loadout);
    return guess, false, guess;
end

-- Another character logged in. Nothing learned carries over.
function tp.forget()
    tp.on_zone();
    state.model_known, state.transition, state.suppressed = false, false, false;
    state.attacks, state.quiet_until, state.other_from = 1, 0, 0;
    state.rounds_key, state.target = nil, nil;
    state.samples, state.rejected, state.last_reason, state.learned_at = 0, 0, nil, nil;
    state.key, state.weapon_key, state.guess, state.per_hit, state.last_sample = nil, nil, nil, nil, nil;
    state.other, state.other_rate = nil, 0;
    forget_hits();
end

-- Zoning keeps TP per hit. The next fight needs its own hit rate and outside TP.
function tp.on_zone()
    state.last_tp, state.pending, state.pending_at = nil, nil, nil;
    state.stirred, state.own_round, state.own_hits = false, false, 0;
    state.target, state.round_at, state.other, state.other_rate = nil, nil, nil, 0;
    forget_hits();
end

return tp;
