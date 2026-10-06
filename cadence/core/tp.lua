--[[
    Your TP per hit, and how many rounds until 1000 TP.

    Phoenix gives TP the old way, from before Seekers of Adoulin (its soa_tp_gain era module). Every
    hit that lands in a round gives the same TP. Your weapon's base delay and your Store TP set it.
    A Samurai's Zanshin hit is the one exception. Ikishoten merits add to it. Misses, parries,
    shadows and hits that did no damage give none. Haste doesn't change it.
    The client can't see Store TP gear. The TP per hit worked out from your weapon is only a first
    guess. The real number comes from your own TP. The change right after one of your rounds gets
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
    key         = nil,   -- The weapons, jobs and levels the numbers below go with.
    guess       = nil,   -- TP per hit worked out from your weapon.
    per_hit     = nil,   -- TP per hit, once it was learned from your own hits.
    last_sample = nil,
    hits        = {},    -- Hits that gave TP in your recent rounds.
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

local function loadout_key(loadout)
    return ('%d:%d:%s:%d/%d:%d/%d'):format(
        loadout.main and loadout.main.id or 0,
        loadout.sub and loadout.sub.id or 0,
        loadout.sub_used and 'sub' or '',
        loadout.main_job, loadout.main_level,
        loadout.sub_job, loadout.sub_level);
end

-- TP per hit worked out from your weapon and Store TP.
local function guess_for(loadout)
    return math.floor(base_tp(delay.tp_delay(loadout)) * (1 + delay.store_tp(loadout) / 100));
end

local function forget_hits()
    for i = #state.hits, 1, -1 do
        state.hits[i] = nil;
    end
end

-- New weapons, jobs or levels mean a new TP per hit. What was learned gets dropped.
local function use_loadout(loadout)
    local key = loadout_key(loadout);
    if (key == state.key) then
        return;
    end
    state.key = key;
    state.guess = guess_for(loadout);
    state.attacks = delay.attacks_twice(loadout) and 2 or 1;
    state.per_hit, state.last_sample = nil, nil;
    forget_hits();
end

local function remember_hits(hits)
    table.insert(state.hits, hits);
    if (#state.hits > ROUNDS_KEPT) then
        table.remove(state.hits, 1);
    end
end

-- Two samples in a row that agree lock it in. So does a first one that matches the guess.
-- A stray sample, like one a monster's hit slipped into, breaks the run but changes nothing.
local function learn(sample)
    if (sample == state.last_sample or (state.per_hit == nil and sample == state.guess)) then
        state.per_hit = sample;
    end
    state.last_sample = sample;
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
    use_loadout(loadout);
    remember_hits(hits);
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
        return;
    end

    local gain = value - last;
    if (state.pending ~= nil and now - state.pending_at <= SAME_BATCH_SECONDS) then
        if (gain > 0 and value < TP_CAP and gain % state.pending == 0) then
            learn(gain / state.pending);
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
    local per_hit = state.per_hit or state.guess;
    if (value >= goal or per_hit == nil or per_hit <= 0) then
        return nil;
    end
    local hits_needed = math.ceil((goal - value) / per_hit);
    -- TP from anything else each round counts as hits too, at your TP per hit.
    return math.max(1, math.floor(hits_needed / (hits_per_round() + state.other_rate / per_hit) + 0.5));
end

-- About how much TP a round of yours has lately been getting from anything but your own hits.
function tp.other_per_round()
    return state.other_rate;
end

-- TP per hit in use, whether it was learned from your own hits, and the first guess it started from.
function tp.per_hit()
    return state.per_hit or state.guess, state.per_hit ~= nil, state.guess;
end

-- The same for the next fight with `loadout`. Other weapons, jobs or levels start from a new guess.
-- Nothing changes from looking.
function tp.per_hit_for(loadout)
    if (loadout_key(loadout) == state.key) then
        return tp.per_hit();
    end
    local guess = guess_for(loadout);
    return guess, false, guess;
end

-- Another character logged in. Nothing learned carries over.
function tp.forget()
    state.key, state.guess, state.per_hit, state.last_sample = nil, nil, nil, nil;
    state.other, state.other_rate = nil, 0;
    forget_hits();
end

-- Zoning. What was learned stays. Your gear came with you.
function tp.on_zone()
    state.last_tp, state.pending, state.stirred, state.own_round = nil, nil, false, false;
end

return tp;
