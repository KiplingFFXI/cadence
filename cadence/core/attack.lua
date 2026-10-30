--[[
    The auto attack timer.

    The server times your attacks in LSB attack_state.cpp. Phoenix runs it unchanged.
    The timer starts at 3 s when you engage, and the first server tick takes a full 0.4 s off it. So the
    first attack comes 2.8 to 3.2 s after the server sees you engage. The bar uses the soonest, 2.8 s.
    Each attack adds your weapon delay to a timer that drains in 0.4 s server ticks. Leftover time
    carries over. A single gap can be up to 0.4 s off. The gaps average out to your exact delay.
    Job abilities and weapon skills hold it for their validated animation time.
    Spells, items and ranged attacks hold it while they run. Their validated animation time follows,
    usually 2 s after a spell and 0.8 s after a ranged attack. A zero-tail item waits one server tick.
    Unknown action timing stays unknown until another accepted action or attack supplies new evidence.
    Sleep, stun, petrification, terror, Lullaby and a penalty stop it. It picks up where it left off
    once they wear off.
    Switching targets keeps it running while you stay engaged. Disengaging ends that timer.
    Phoenix then applies a separate re-engage cooldown based on the last sampled attack delay.

    cadence starts from a delay worked out from your gear, job and buffs. Then it learns the real
    one from your own attacks. That also catches bonuses whose strength is still unknown.
]]

local delay = require('core.delay');

local attack = {};

local FIRST_ATTACK_SECONDS = 2.8;
local ABILITY_HOLD_SECONDS = 2.0;
local CAST_HOLD_SECONDS    = { spell = 2.0, ranged = 0.8, item = 0.4 };
local INTERVALS_TO_TRUST   = 3;
local INTERVALS_KEPT       = 6;
local KEYS_KEPT            = 16;
local SNAP_TO_ESTIMATE     = 0.04;
local DUE_SOON             = 0.5;
local REENGAGE_MIN_SECONDS = 1.5;
local REENGAGE_GATE_SECONDS = 3.0;
local REENGAGE_ELAPSED_SECONDS = 0.5;
local REENGAGE_UNKNOWN_SECONDS = 5.0;

-- A gap longer than this many times the estimate had a pause cadence didn't see.
local LONGEST_CLEAN_RATIO = 1.5;

-- A paralyzed ranged attack sends its interrupt, then the paralysis packet in the same server tick.
local SAME_TICK = 0.2;

local state = {
    active         = false,
    last_attack    = nil,   -- When the last round arrived, or the engage time before the first one.
    next_attack    = nil,   -- When the next round is expected.
    delay          = nil,   -- Seconds between attacks in use right now.
    estimate       = nil,   -- The delay worked out from gear, job and buffs.
    loadout_key    = nil,   -- Names the gear, job and buffs the intervals were learned with.
    guessed        = false, -- True when that key has March, Slow or Elegy in it.
    intervals      = {},    -- Recent clean gaps between rounds with that key.
    clean          = false, -- False when something held the timer since the last round.
    stalled        = false, -- True after an out of range message, until the next round.
    reason         = nil,   -- What that message said, like 'too far' or 'not facing'.
    held_since     = nil,   -- Set while a spell, item or ranged attack holds the timer.
    held_by        = nil,   -- 'spell', 'ranged' or 'item'.
    unknown_action_hold = false,
    unknown_remaining = nil,
    hold_ended     = nil,   -- When the last spell, item or ranged attack ended.
    disabled_since = nil,   -- Set while sleep, stun or the like stops the timer.
    disabled_by    = nil,   -- The buff id of what stops it.
    accepted       = 0,
    rejected       = 0,
    last_rejection = nil,
    sample_at      = nil,
    reused         = false,
    joined_late    = false, -- True when the fight started before cadence saw it, until your first round.
    sampled_delay  = nil,   -- The interval sampled at engagement or the last permitted round.
    sampled_at     = nil,
};

local retained = { active = false };
local retained_view = {};

local function action_seconds(seconds, fallback)
    if (seconds == false) then return false; end
    if (type(seconds) == 'number' and seconds == seconds and seconds >= 0 and seconds < math.huge) then return seconds; end
    return fallback;
end

local function clear_unknown_hold()
    state.unknown_action_hold, state.unknown_remaining = false, nil;
end

-- The gaps learned with the last few keys. Zoning keeps them, and so does a buff that wears off and
-- lands again. Another character logging in clears them.
local gaps_by_key = {};
local keys_by_use = {};   -- Oldest first.

-- The gaps learned with a key. It becomes the newest, and the oldest past KEYS_KEPT is dropped.
local function gaps_for(loadout_key)
    for i, key in ipairs(keys_by_use) do
        if (key == loadout_key) then
            table.remove(keys_by_use, i);
            break;
        end
    end
    table.insert(keys_by_use, loadout_key);
    if (#keys_by_use > KEYS_KEPT) then
        gaps_by_key[table.remove(keys_by_use, 1)] = nil;
    end

    local gaps = gaps_by_key[loadout_key];
    if (gaps == nil) then
        gaps = {};
        gaps_by_key[loadout_key] = gaps;
    end
    return gaps;
end

-- The key includes the known gear and effects that change attack speed. Other gear keeps its gaps.
-- A key with March, Slow or Elegy starts over each time. The new one can be a different strength.
local function use_loadout(loadout_key)
    if (loadout_key == state.loadout_key) then
        return;
    end
    state.accepted, state.rejected, state.last_rejection, state.sample_at = 0, 0, nil, nil;
    state.loadout_key = loadout_key;
    state.intervals   = gaps_for(loadout_key);
    state.guessed     = not delay.exact(loadout_key);
    if (state.guessed) then
        state.intervals = {};
        gaps_by_key[loadout_key] = state.intervals;
    end
    state.reused = #state.intervals >= INTERVALS_TO_TRUST;
end

local function learned_delay(gaps)
    local count = #gaps;
    if (count < INTERVALS_TO_TRUST) then
        return nil;
    end

    local total = 0;
    for i = 1, count do
        total = total + gaps[i];
    end
    return total / count;
end

local function remember_interval(interval, now)
    if (interval <= 0) then
        state.rejected = state.rejected + 1;
        state.last_rejection = 'rounds arrived together';
        return;
    end
    if (interval > state.estimate * LONGEST_CLEAN_RATIO) then
        state.rejected = state.rejected + 1;
        state.last_rejection = 'gap too long for an uninterrupted round';
        return;
    end

    state.accepted, state.sample_at, state.last_rejection, state.reused = state.accepted + 1, now, nil, false;
    table.insert(state.intervals, interval);
    if (#state.intervals > INTERVALS_KEPT) then
        table.remove(state.intervals, 1);
    end
end

local function choose_delay(gaps, estimate)
    local learned = learned_delay(gaps);
    if (learned == nil) then
        return estimate;
    end

    -- The estimate is exact to the millisecond when nothing hidden changes it.
    if (math.abs(learned - estimate) <= SNAP_TO_ESTIMATE) then
        return estimate;
    end
    return learned;
end

-- You engaged a target. `estimate` is the delay in seconds and `loadout_key` names the gear behind it.
-- `joined_late` is true when the fight started before cadence saw it. Then the first attack's time
-- isn't known until it lands.
-- `initial_delay` is the model before drawn-weapon latents apply, or false when it isn't known.
function attack.engage(now, estimate, loadout_key, joined_late, initial_delay)
    attack.cancel_reengage();
    clear_unknown_hold();
    use_loadout(loadout_key);
    state.reused         = learned_delay(state.intervals) ~= nil;
    state.active         = true;
    state.joined_late    = joined_late == true;
    state.last_attack    = now;
    state.next_attack    = now + FIRST_ATTACK_SECONDS;
    state.estimate       = estimate;
    state.delay          = choose_delay(state.intervals, estimate);
    if (initial_delay == nil) then initial_delay = estimate; end
    state.sampled_delay  = not state.joined_late and type(initial_delay) == 'number'
        and initial_delay > 0 and initial_delay < math.huge and initial_delay or nil;
    state.sampled_at     = state.sampled_delay and now or nil;
    state.held_since     = nil;
    state.held_by        = nil;
    state.hold_ended     = nil;
    state.disabled_since = nil;
    state.disabled_by    = nil;
    state.clean          = false;
    state.stalled        = false;
    state.reason         = nil;
end

-- Only a confirmed server departure passes a timestamp and enables retention here.
function attack.disengage(now, enabled, context)
    if (type(now) ~= 'number' or now ~= now or math.abs(now) == math.huge
        or enabled ~= true) then
        attack.cancel_reengage();
    elseif (state.active) then
        local duration = not (context and context.unknown) and state.sampled_delay and math.max(REENGAGE_MIN_SECONDS,
            state.sampled_delay - REENGAGE_GATE_SECONDS) or nil;
        retained.active = true;
        retained.started = now;
        retained.duration = duration;
        retained.deadline = duration and now + duration or nil;
        retained.expires = now + (duration and duration + REENGAGE_ELAPSED_SECONDS or REENGAGE_UNKNOWN_SECONDS);
        retained.sampled_delay = state.sampled_delay;
        retained.sampled_at = state.sampled_at;
        retained.remaining = not state.unknown_action_hold and not state.joined_late and state.next_attack
            and math.max(0, state.next_attack - (state.held_since or state.disabled_since or now)) or nil;
        retained.held_by = state.held_since and state.held_by or nil;
        retained.disabled_by = state.disabled_since and state.disabled_by or nil;
        retained.stalled = state.stalled;
        retained.last_target = context and context.last_target or nil;
        retained.cause = context and context.cause or nil;
    end
    state.active         = false;
    clear_unknown_hold();
    state.held_since     = nil;
    state.held_by        = nil;
    state.hold_ended     = nil;
    state.disabled_since = nil;
    state.disabled_by    = nil;
    state.reason         = nil;
    state.clean          = false;
end

function attack.cancel_reengage()
    retained.active = false;
end

-- Departure cause and packet transit time aren't known. Use the longest lockout for the saved delay.
-- This table is reused by the HUD. It never advances the attack clock or learns an idle gap.
function attack.reengage_progress(now)
    if (not retained.active) then return nil; end
    if (now >= retained.expires) then
        retained.active = false;
        return nil;
    end

    local left = retained.deadline and math.max(0, retained.deadline - now) or nil;
    retained_view.fill = left and math.max(0, math.min(1, 1 - left / retained.duration)) or 0;
    retained_view.left = left;
    retained_view.duration = retained.duration;
    retained_view.unknown = left == nil;
    retained_view.elapsed = left == 0;
    retained_view.conservative = true;
    return retained_view;
end

-- One of your melee rounds arrived. The server reads your delay at attack time. The gear and buffs
-- you have right now decide the next gap.
function attack.on_round(now, estimate, loadout_key, sampled_known, transition)
    if (not state.active) then
        return;
    end

    if (loadout_key ~= state.loadout_key) then
        use_loadout(loadout_key);
    elseif (state.clean) then
        remember_interval(now - state.last_attack, now);
    else
        state.rejected = state.rejected + 1;
        state.last_rejection = 'first round or interrupted timing';
    end

    state.estimate       = estimate;
    state.delay          = choose_delay(state.intervals, estimate);
    -- A pending gear or effect change makes the previous calibration stale for this sample.
    state.sampled_delay  = not transition and (sampled_known ~= false or learned_delay(state.intervals) ~= nil)
        and state.delay or nil;
    state.sampled_at     = state.sampled_delay and now or nil;
    state.last_attack    = now;
    state.next_attack    = now + state.delay;
    clear_unknown_hold();
    state.joined_late    = false;
    state.held_since     = nil;
    state.held_by        = nil;
    state.hold_ended     = nil;
    state.disabled_since = nil;
    state.disabled_by    = nil;

    -- The first attack after a stall carries a short timer into the next gap. That gap isn't learned.
    state.clean   = not state.stalled;
    state.stalled = false;
    state.reason  = nil;
end

-- A job ability or weapon skill went off. False means its attack hold is unknown.
function attack.on_ability(now, seconds)
    if (not state.active) then
        return;
    end

    local remaining = state.unknown_action_hold and state.unknown_remaining or math.max(state.next_attack - now, 0);
    seconds = action_seconds(seconds, ABILITY_HOLD_SECONDS);
    if (seconds == false) then
        state.unknown_action_hold, state.unknown_remaining = true, remaining;
    else
        clear_unknown_hold();
        state.next_attack = now + remaining + seconds;
    end
    state.clean       = false;
    state.reason      = nil;
end

--[[
    A paralyzed or intimidated auto attack and a paralyzed job ability send the same packet. An auto
    attack only happens when one is due. The same packet well before that is a job ability. Items
    and ranged attacks send it too. Those already hold the timer.
]]
function attack.on_paralyzed(now, estimate, loadout_key, sampled_known, transition)
    if (not state.active or state.held_since ~= nil or state.unknown_action_hold) then
        return;
    end
    if (state.hold_ended ~= nil and now - state.hold_ended < SAME_TICK) then
        return;
    end

    if (now < state.next_attack - DUE_SOON) then
        attack.on_ability(now);
        return;
    end

    -- The paralyzed attack still used up the timer.
    if (estimate ~= nil and loadout_key ~= nil) then
        use_loadout(loadout_key);
        state.estimate = estimate;
        state.delay = choose_delay(state.intervals, estimate);
    end
    state.sampled_delay = not transition and not state.joined_late and estimate ~= nil and loadout_key ~= nil
        and (sampled_known ~= false or learned_delay(state.intervals) ~= nil) and state.delay or nil;
    state.sampled_at = state.sampled_delay and now or nil;
    state.last_attack = now;
    state.next_attack = now + state.delay;
    state.clean       = false;
    state.reason      = nil;
end

-- A spell, item or ranged attack started. `kind` is 'spell', 'item' or 'ranged'.
-- The bar stops filling until it ends.
function attack.on_cast_begin(now, kind)
    if (not state.active or state.held_since ~= nil) then
        return;
    end

    if (state.unknown_action_hold) then
        state.next_attack = now + state.unknown_remaining;
        clear_unknown_hold();
    end
    state.held_since = now;
    state.held_by    = kind;
    state.clean      = false;
end

-- The spell, item or ranged attack finished or was interrupted. False keeps its hold unknown.
function attack.on_cast_end(now, seconds)
    if (not state.active or state.held_since == nil) then
        return;
    end

    local remaining   = math.max(state.next_attack - state.held_since, 0);
    seconds = action_seconds(seconds, CAST_HOLD_SECONDS[state.held_by]);
    if (seconds == false) then
        state.unknown_action_hold, state.unknown_remaining = true, remaining;
    else
        clear_unknown_hold();
        state.next_attack = now + remaining + seconds;
    end
    state.held_since  = nil;
    state.hold_ended  = now;
    state.reason      = nil;

    -- Sleep or stun cuts a spell off. The hold covered the time up to now. The pause starts here.
    if (state.disabled_since ~= nil) then
        state.disabled_since = now;
    end
end

-- The server said you can't attack. The timer waits at zero until you can. `reason` is what to show
-- instead of "ready", like 'too far' or 'not facing', or nil.
function attack.on_out_of_reach(reason)
    clear_unknown_hold();
    state.clean   = false;
    state.stalled = true;
    state.reason  = reason;
end

--[[
    Sleep, Lullaby, stun, petrification, terror or a penalty is on you. The server stops your attack
    timer until it wears off. The bar stops where it is. The gap it lands in isn't learned.
    `effect` is its buff id.
]]
function attack.on_disabled(now, effect)
    state.clean = false;
    state.disabled_by = effect;
    if (state.active and state.disabled_since == nil) then
        state.disabled_since = now;
    end
end

-- None of those are on you anymore. The time that was left carries on from here.
function attack.on_enabled(now)
    if (state.disabled_since == nil) then
        return;
    end
    if (state.active and state.held_since == nil) then
        state.next_attack = now + math.max(state.next_attack - state.disabled_since, 0);
    end
    state.disabled_since = nil;
end

--[[
    Returns how full the bar is (0..1), the seconds until the next attack, the delay in use, why you
    aren't attacking when the server said so, and what stopped the timer. That's 'spell', 'ranged' or
    'item' while one holds it, 'recovery' for an unknown action hold, or the buff id of sleep and the
    like. The seconds are nil while recovery or a joined-late fight's phase is unknown.
    Returns nil when you are not engaged.
]]
function attack.progress(now)
    if (not state.active) then
        return nil;
    end

    -- Sleep and the like come first. They cut a spell off.
    local why = (state.disabled_since and state.disabled_by) or (state.held_since and state.held_by)
        or (state.unknown_action_hold and 'recovery') or nil;
    if (state.unknown_action_hold) then return 0, nil, state.delay, state.reason, why; end
    if (state.joined_late) then
        return 0, nil, state.delay, state.reason, why;
    end

    -- The bar doesn't move while an action or sleep and the like hold the timer.
    local clock = state.held_since or state.disabled_since or now;
    local span  = state.next_attack - state.last_attack;
    local left  = state.next_attack - clock;
    if (left < 0) then
        left = 0;
    end

    local fill = 1;
    if (span > 0) then
        fill = 1 - left / span;
    end
    return fill, left, state.delay, state.reason, why;
end

-- True while you are engaged.
function attack.is_active()
    return state.active;
end

-- True while the key last used has March, Slow or Elegy in it. Your buffs are watched for it to wear off.
function attack.watching_buffs()
    return state.loadout_key ~= nil and state.guessed;
end

-- Once the March, Slow or Elegy in the key wears off, the next one is measured again. While it stays
-- on, the next fight starts on what was learned with it.
function attack.on_buffs(buffs)
    if (attack.watching_buffs() and delay.guess_worn_off(state.loadout_key, buffs)) then
        state.loadout_key = nil;
    end
end

-- True when enough of your attacks have been seen to trust the learned delay.
function attack.is_learned()
    return learned_delay(state.intervals) ~= nil;
end

--[[
    Returns the delay in use, whether it was learned and the estimate it goes with. Out of a fight
    it's the delay you'd start on if you engaged now with `estimate` and `loadout_key`. Nothing
    learned changes.
]]
function attack.delay_in_use(estimate, loadout_key)
    if (state.active) then
        return state.delay, attack.is_learned(), state.estimate;
    end
    local gaps = gaps_by_key[loadout_key] or {};
    -- Like use_loadout, a new key with March, Slow or Elegy starts over.
    if (loadout_key ~= state.loadout_key and not delay.exact(loadout_key)) then
        gaps = {};
    end
    return choose_delay(gaps, estimate), learned_delay(gaps) ~= nil, estimate;
end

-- How many keys come back learned the next time they're used. An old key with March, Slow or Elegy
-- doesn't.
function attack.kept_count()
    local count = 0;
    for key, gaps in pairs(gaps_by_key) do
        if (#gaps >= INTERVALS_TO_TRUST and (key == state.loadout_key or delay.exact(key))) then
            count = count + 1;
        end
    end
    return count;
end

-- Zoning. What was learned stays. Your gear came with you.
function attack.reset()
    attack.cancel_reengage();
    clear_unknown_hold();
    state.active         = false;
    state.last_attack    = nil;
    state.next_attack    = nil;
    state.held_since     = nil;
    state.held_by        = nil;
    state.hold_ended     = nil;
    state.disabled_since = nil;
    state.disabled_by    = nil;
    state.reason         = nil;
    state.loadout_key    = nil;
    state.intervals      = {};
    state.sampled_delay  = nil;
    state.sampled_at     = nil;
    state.joined_late    = false;
    state.clean          = false;
    state.stalled        = false;
end

-- Another character logged in. Nothing learned carries over to them.
function attack.forget_learned()
    attack.cancel_reengage();
    gaps_by_key, keys_by_use = {}, {};
    state.loadout_key = nil;
    state.intervals   = {};
end

-- Start this loadout's measurements again without moving an attack already scheduled.
function attack.relearn()
    if (state.loadout_key == nil) then return false; end
    for i = #state.intervals, 1, -1 do state.intervals[i] = nil; end
    gaps_by_key[state.loadout_key] = state.intervals;
    state.accepted, state.rejected, state.last_rejection, state.sample_at = 0, 0, nil, nil;
    state.reused, state.clean = false, false;
    state.delay = state.estimate;
    return true;
end

function attack.info(now, next_estimate, next_key)
    local minimum, maximum = nil, nil;
    for _, gap in ipairs(state.intervals) do
        minimum = minimum and math.min(minimum, gap) or gap;
        maximum = maximum and math.max(maximum, gap) or gap;
    end
    local reengage = attack.reengage_progress(now);
    return {
        active = state.active, delay = state.delay, modeled_delay = state.estimate,
        next_interval_model = next_estimate, next_interval_changed = next_key ~= nil and next_key ~= state.loadout_key,
        source = attack.is_learned() and (state.reused and 'remembered' or 'observed') or 'estimated',
        samples = #state.intervals, accepted = state.accepted, rejected = state.rejected,
        sample_age = state.sample_at and math.max(0, now - state.sample_at) or nil,
        sample_min = minimum, sample_max = maximum, last_rejection = state.last_rejection,
        holding = state.unknown_action_hold and 'recovery' or (state.held_since and state.held_by or nil),
        disabled = state.disabled_since and state.disabled_by or nil, reason = state.reason,
        stalled = state.stalled, joined_late = state.joined_late,
        sampled_delay = state.sampled_delay, sampled_at = state.sampled_at,
        reengage = reengage and {
            left = reengage.left, duration = reengage.duration, unknown = reengage.unknown,
            elapsed = reengage.elapsed, conservative = reengage.conservative,
            started = retained.started, deadline = retained.deadline, expires = retained.expires,
            sampled_delay = retained.sampled_delay, sampled_at = retained.sampled_at,
            remaining = retained.remaining, holding = retained.held_by, disabled = retained.disabled_by,
            stalled = retained.stalled, last_target = retained.last_target, cause = retained.cause,
        } or nil,
        overdue = state.active and not state.unknown_action_hold and state.next_attack ~= nil and now > state.next_attack,
        next_in = not state.unknown_action_hold and state.next_attack and math.max(0, state.next_attack - now) or nil,
    };
end

return attack;
