--[[
    The resting (/heal) tick timer.

    The server times resting ticks in LSB scripts/effects/healing.lua and zone_entities.cpp.
    Phoenix runs both unchanged.
    Resting ticks every 10 s from the moment you sit. The first tick restores nothing.
    Ticks only run on the zone's 3 s effect check. Each one lands up to 3.2 s after its 10 s mark.
    That makes the gaps between ticks run 9, 9, 12, 9, 9, 12. The short ones are 8.8 or 9.2 s.
    The first HP/MP tick lands 20 to 23 s after you sit down.

    cadence counts down to the first tick. After that it watches your HP, MP and TP for each real
    tick and predicts the next one from the 9, 9, 12 pattern.
    A flat 10 s countdown drifts up to 2 s off.

    Disease, plague and the curse that stops healing (Curse II on the server) make a tick restore
    nothing. The ticks still come on time and still count. Once the effect is gone, the next tick
    heals as much as it would have with no effect at all. cadence follows the pattern on its own
    while one of them is on.
]]

local resting = {};

local TICK_INTERVAL       = 10.0;
local FIRST_TICK_SECONDS  = 21.4;
local FIRST_TICK_EARLIEST = 19.3;
local FIRST_TICK_LATEST   = 23.8;
local SHORT_GAP           = 9.0;
local LONG_GAP            = 12.0;
local LOOSE_WINDOW        = 1.2;
local TIGHT_WINDOW        = 0.7;
local LATE_TICK           = 1.0;

-- How far the first tick can land from FIRST_TICK_SECONDS. Until a tick shows up, the ones after it
-- can be as far off.
local FIRST_TICK_SPREAD = FIRST_TICK_LATEST - FIRST_TICK_SECONDS;

-- Real ticks are never closer than 8.8 s. Anything sooner than this can't be one.
local MIN_TICK_GAP = SHORT_GAP - LOOSE_WINDOW;

-- Resting shows up on your character about this long after the server starts it.
local SIT_DELAY = 0.25;

-- The smallest amounts a resting tick restores. Nothing else restores 12 MP while you're resting.
local TICK_MP = 12;
local TICK_HP = 10;

-- Extra HP allowed on top of what a tick should add. Regen or a gear swap can push one tick higher.
local HP_STEP_SLACK = 2;

-- Regen and Refresh add HP and MP on the same 3 s effect pass that runs the ticks.
local EFFECT_PASS = 3.0;
local PASS_WINDOW = 0.6;
local ACTION_WINDOW = 0.5;

-- Disease (8), plague (31) and the curse that stops healing (20). The first one found is the one named.
local CANT_HEAL = { 8, 31, 20 };
local STATS = { 'hp', 'mp' };

-- A change made while one of them is on gets decided at the next buff read, about 0.2 s later. A slow
-- frame can make that read late. A change this old can still be the tick the effect wore off on.
local BUFF_LAG = 0.5;

local state = {
    active         = false,
    started_at     = nil,    -- When resting showed up on your character.
    last_tick      = nil,
    last_evidence  = nil,    -- How the last tick was found. It is 'sure', 'maybe' or 'assumed'.
    next_tick      = nil,
    next_gap       = nil,    -- The gap the current prediction assumed.
    gap_last       = nil,    -- The last two gaps, rounded to 9 or 12.
    gap_before     = nil,
    ticks          = 0,      -- HP/MP ticks so far, seen or assumed.
    gained_hp      = 0,      -- What the last seen tick restored, Regen and Refresh included.
    gained_mp      = 0,
    heal_hp        = 0,      -- The resting part of the last seen tick, without Regen or Refresh.
    heal_mp        = 0,
    heal_before_hp = 0,      -- The resting part of the seen tick before that.
    heal_before_mp = 0,
    regen_hp       = 0,      -- Regen and Refresh per 3 s pass, from the last full gap between ticks.
    regen_mp       = 0,
    pass_hp        = nil,    -- The last gain seen between ticks.
    pass_mp        = nil,
    pass_at_hp     = nil,
    pass_at_mp     = nil,
    pending_pass_hp = nil,
    pending_pass_mp = nil,
    pending_pass_at_hp = nil,
    pending_pass_at_mp = nil,
    direct_hp      = nil,
    direct_mp      = nil,
    direct_tp      = nil,
    gap_regen_hp   = 0,      -- Regen and Refresh seen so far in the current gap.
    gap_regen_mp   = 0,
    regen_at       = nil,
    regen_observed_hp = false,
    regen_observed_mp = false,
    gap_regen_known_hp = false,
    gap_regen_known_mp = false,
    seen_at        = nil,    -- When the last seen tick landed.
    hp             = nil,    -- Your last known HP, MP and TP, and your max HP and MP.
    mp             = nil,
    tp             = nil,
    hp_max         = nil,
    mp_max         = nil,
    full           = false,
    hidden         = false,  -- True once ticks stopped showing up at full HP and MP.
    lost           = false,  -- True when an expected tick never showed up.
    blocked        = nil,    -- The buff id of disease, plague or the curse while one is on you.
    skipped        = 0,      -- Ticks that healed nothing under one of them since the last tick you saw.
    -- A change in your HP, MP or TP under one of them, kept until the next buff check decides it.
    held_at        = nil,
    held_hp        = 0,
    held_mp        = 0,
    held_tp        = 0,
    held_missing   = 0,
    held_train_hp  = false,
    held_train_mp  = false,
    model          = nil,
    model_pending  = false, -- The next packet may cross a gear or effect change.
    recovery_changed = false,
    sample_hp      = nil,   -- Uncapped resting gains under the current model.
    sample_mp      = nil,
    accepted       = 0,
    rejected       = 0,
    last_decision  = nil,
};
local passive_rate;
local last_change = {};
local phase_before = {};
local PHASE_FIELDS = { 'last_tick', 'last_evidence', 'next_tick', 'next_gap', 'gap_last', 'gap_before',
    'ticks', 'seen_at', 'hidden', 'lost', 'skipped', 'gained_hp', 'gained_mp', 'accepted' };

local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge;
end

local function forget_recovery()
    last_change.at = nil;
    state.heal_hp, state.heal_mp = 0, 0;
    state.heal_before_hp, state.heal_before_mp = 0, 0;
    state.regen_hp, state.regen_mp = 0, 0;
    state.pass_hp, state.pass_mp = nil, nil;
    state.pass_at_hp, state.pass_at_mp = nil, nil;
    state.pending_pass_hp, state.pending_pass_mp = nil, nil;
    state.pending_pass_at_hp, state.pending_pass_at_mp = nil, nil;
    state.gap_regen_hp, state.gap_regen_mp = 0, 0;
    state.regen_at = nil;
    state.regen_observed_hp, state.regen_observed_mp = false, false;
    state.gap_regen_known_hp, state.gap_regen_known_mp = false, false;
    state.sample_hp, state.sample_mp = nil, nil;
    state.held_at = nil;
end

-- A changed amount starts fresh samples without moving the resting clock.
function resting.on_model(model)
    local next_model = nil;
    if (type(model) == 'table') then
        next_model = {
            resting_key = model.resting_key,
            hp_known = model.hp_known == true,
            mp_known = model.mp_known == true,
            unknown = model.unknown,
            transition = model.transition == true,
            regen = model.regen or 0, refresh = model.refresh or 0,
            regen_down = model.regen_down or 0, refresh_down = model.refresh_down or 0,
            regen_known = model.regen_known ~= false, refresh_known = model.refresh_known ~= false,
        };
        for _, stat in ipairs(STATS) do
            local base, step = model[stat .. '_base'], model[stat .. '_step'];
            if (finite(base) and base >= 0 and finite(step) and step >= 0) then
                next_model[stat .. '_base'], next_model[stat .. '_step'] = base, step;
            end
        end
    end
    local before = state.model;
    local changed = (before == nil) ~= (next_model == nil);
    if (before ~= nil and next_model ~= nil) then
        for _, key in ipairs({ 'resting_key', 'hp_base', 'hp_step', 'mp_base', 'mp_step',
            'regen', 'refresh', 'regen_down', 'refresh_down' }) do
            if (before[key] ~= next_model[key]) then changed = true; end
        end
    end
    state.model = next_model;
    if (changed) then
        forget_recovery();
        state.recovery_changed = true;
        state.model_pending = state.active and (before ~= nil or state.last_tick ~= nil);
    end
end

-- Observations replace the modeled amount. The model is never added to a gain we already saw.
local function modeled_gain(stat, tick)
    local model = state.model;
    if (model == nil or model[stat .. '_base'] == nil) then return nil; end
    local step = model[stat .. '_step'];
    local sample = state['sample_' .. stat];
    if (sample ~= nil) then
        step = sample.step or step;
        local confidence = (sample.step ~= nil or model[stat .. '_known']) and 'observed' or 'estimated';
        return math.max(0, sample.gain + (tick - sample.tick) * step), step, confidence;
    end
    return model[stat .. '_base'] + (tick - 1) * step, step,
        model[stat .. '_known'] and 'known' or 'estimated';
end

local function learn_gain(stat, gain)
    if (state.model == nil or state.model[stat .. '_base'] == nil or gain <= 0) then return; end
    local before = state['sample_' .. stat];
    local step = nil;
    if (before ~= nil and state.ticks > before.tick) then
        local increase = (gain - before.gain) / (state.ticks - before.tick);
        if (increase > 0) then step = increase; end
    end
    state['sample_' .. stat] = { gain = gain, tick = state.ticks, step = step };
end

-- True once the last two gaps are known, so the next one comes from the 9, 9, 12 pattern.
function resting.pattern_known()
    return state.gap_last ~= nil and state.gap_before ~= nil;
end

-- The gaps repeat 9, 9, 12. After two short gaps the next one is long.
local function predict_gap(tick_time)
    if (resting.pattern_known()) then
        if (state.gap_last == SHORT_GAP and state.gap_before == SHORT_GAP) then
            return LONG_GAP;
        end
        return SHORT_GAP;
    end
    if (state.gap_last == LONG_GAP) then
        return SHORT_GAP;
    end

    -- Too little history. A tick that landed well after its 10 s mark comes before a short gap.
    -- Ticks land 0 to 3.2 s after a mark. A value past 5 s means the next mark is under 5 s away.
    local late = (tick_time - (state.started_at - SIT_DELAY)) % TICK_INTERVAL;
    if (late > TICK_INTERVAL / 2) then
        late = late - TICK_INTERVAL;
    end
    if (late >= LATE_TICK) then
        return SHORT_GAP;
    end
    return LONG_GAP;
end

local function remember_gap(gap)
    state.gap_before = state.gap_last;
    state.gap_last   = gap;
end

local function forget_gaps()
    state.gap_before = nil;
    state.gap_last   = nil;
end

-- `evidence` is 'sure' or 'maybe' for a tick that showed up, 'assumed' when nothing visible arrived.
local function record_tick(when, evidence)
    if (state.last_tick ~= nil) then
        local gap = when - state.last_tick;
        if (gap < MIN_TICK_GAP) then
            -- Too soon after the last one. That one was a cure or a guess. This tick replaces it.
            state.ticks = state.ticks - 1;
            forget_gaps();
        elseif (evidence == 'assumed') then
            -- An assumed tick keeps the pattern going with the gap it was predicted with.
            remember_gap(state.next_gap);
        elseif (state.last_evidence ~= 'assumed' and gap <= LONG_GAP + LOOSE_WINDOW) then
            remember_gap((gap > (SHORT_GAP + LONG_GAP) / 2) and LONG_GAP or SHORT_GAP);
        else
            -- A tick went missing or the last one was only assumed. The pattern starts over from here.
            forget_gaps();
        end
    end

    state.ticks         = state.ticks + 1;
    state.last_tick     = when;
    state.last_evidence = evidence;
    state.next_gap      = predict_gap(when);
    state.next_tick     = when + state.next_gap;
end

--[[
    Decides what a change in your HP, MP or TP says about a resting tick.
    'sure' means only a tick could cause it. 'maybe' means a cure or a buff wearing off could look the
    same. A 'maybe' only counts near the predicted time.
]]
local function tick_evidence(hp_gain, mp_gain, tp_gain, mp_missing, hp_max)
    if ((mp_gain ~= nil and mp_gain >= TICK_MP) or (tp_gain ~= nil and tp_gain < 0)) then
        return 'sure';
    end
    -- With 12 or more MP missing, a real tick would have restored at least 12 MP.
    if (mp_gain ~= nil and mp_missing >= TICK_MP) then
        return nil;
    end
    -- Each tick restores a little more HP than the one before. The step is 1 HP, or 1 + max HP / 300
    -- under Signet. A tick that healed nothing still counts a step. A much bigger jump is a cure.
    local steps = (1 + math.floor(hp_max / 300)) * (1 + state.skipped);
    local hp_limit = state.gained_hp + steps + HP_STEP_SLACK;
    local predicted = modeled_gain('hp', state.ticks + 1);
    if (predicted ~= nil) then hp_limit = math.max(hp_limit, predicted + state.regen_hp + HP_STEP_SLACK); end
    if (hp_gain ~= nil and not state.recovery_changed and state.gained_hp > 0 and hp_gain > hp_limit) then
        return nil;
    end
    -- Duplicate vitals and passive-only gains do not show a resting tick.
    if (hp_gain ~= nil and hp_gain >= TICK_HP) then
        return 'maybe';
    end
    return nil;
end

local function is_tick(now, evidence)
    if (evidence == nil) then
        return false;
    end

    if (state.ticks == 0) then
        local since_sit = now - state.started_at;
        return since_sit >= FIRST_TICK_EARLIEST and since_sit <= FIRST_TICK_LATEST;
    end

    -- After losing track, the next tick that shows up puts the timer back on track.
    if (state.lost) then
        return true;
    end

    if (evidence == 'sure') then
        -- A sure tick too soon after the last one means the last one was a wrong guess.
        return state.last_evidence ~= 'sure' or now - state.last_tick >= MIN_TICK_GAP;
    end

    -- Once the pattern is known the prediction is good to a few tenths. A looser match is a cure.
    local window = resting.pattern_known() and TIGHT_WINDOW or LOOSE_WINDOW;
    if (state.skipped > 0) then
        -- Ticks that healed nothing were only taken to land on time, so the last one can still come a
        -- moment late. With no tick seen since you sat down, the timer is on its first guess.
        window = (state.seen_at == nil) and FIRST_TICK_SPREAD or LOOSE_WINDOW;
        if (math.abs(now - state.last_tick) <= window) then
            return true;
        end
    end
    return math.abs(now - state.next_tick) <= window;
end

function resting.start(now)
    state.active        = true;
    state.started_at    = now;
    state.last_tick     = nil;
    state.last_evidence = nil;
    state.next_tick     = now + FIRST_TICK_SECONDS;
    state.next_gap      = nil;
    state.ticks         = 0;
    state.accepted, state.rejected, state.last_decision = 0, 0, nil;
    state.gained_hp, state.gained_mp = 0, 0;
    forget_recovery();
    state.direct_hp, state.direct_mp, state.direct_tp = nil, nil, nil;
    last_change.at = nil;
    state.model_pending = false;
    state.recovery_changed = false;
    state.seen_at       = nil;
    state.hidden        = false;
    state.lost          = false;
    state.skipped       = 0;
    state.held_at       = nil;
    forget_gaps();
end

function resting.stop()
    state.active = false;
end

local function clear_pass(stat)
    state['pass_' .. stat], state['pass_at_' .. stat] = nil, nil;
    state['pending_pass_' .. stat], state['pending_pass_at_' .. stat] = nil, nil;
end

-- Wait for the action packet too, since it may follow the vitals it changed.
local function settle_pass(when, stat)
    local at = state['pending_pass_at_' .. stat];
    if (at == nil or when - at <= ACTION_WINDOW) then return; end
    state['gap_regen_' .. stat] = state['pending_pass_' .. stat];
    state['gap_regen_known_' .. stat] = true;
    state.regen_at = at;
    state['pending_pass_' .. stat], state['pending_pass_at_' .. stat] = nil, nil;
end

local function note_stat_pass(when, stat, gain, allowed)
    if (not allowed) then clear_pass(stat); return; end
    if (gain == 0) then return; end
    local at = state['pass_at_' .. stat];
    if (gain == state['pass_' .. stat] and at ~= nil and math.abs(when - at - EFFECT_PASS) <= PASS_WINDOW) then
        state['pending_pass_' .. stat], state['pending_pass_at_' .. stat] = gain, when;
    end
    state['pass_' .. stat], state['pass_at_' .. stat] = gain, when;
end

-- Only uncapped, consecutive three-second changes can teach a passive rate.
local function note_pass(when, hp_gain, mp_gain, hp_allowed, mp_allowed)
    note_stat_pass(when, 'hp', hp_gain, hp_allowed);
    note_stat_pass(when, 'mp', mp_gain, mp_allowed);
end

-- A direct cure, drain or transfer cannot teach Regen, Refresh or resting potency.
function resting.on_direct_change(now, hp, mp, tp)
    if (not state.active or not finite(now) or not (hp or mp or tp)) then return; end
    if (hp) then state.direct_hp = now; clear_pass('hp'); end
    if (mp) then state.direct_mp = now; clear_pass('mp'); end
    if (tp) then state.direct_tp = now; end
    if (state.held_at ~= nil and now >= state.held_at and now - state.held_at <= ACTION_WINDOW) then
        state.held_direct_hp = state.held_direct_hp or hp;
        state.held_direct_mp = state.held_direct_mp or mp;
        state.held_direct_tp = state.held_direct_tp or tp;
    end
    if (last_change.at ~= nil and now >= last_change.at and now - last_change.at <= ACTION_WINDOW) then
        last_change.direct_hp = last_change.direct_hp or hp;
        last_change.direct_mp = last_change.direct_mp or mp;
        last_change.direct_tp = last_change.direct_tp or tp;
        if (hp and last_change.hp ~= 0) then
            state.sample_hp = last_change.sample_hp;
            state.heal_hp, state.heal_before_hp, state.gained_hp = 0, 0, 0;
        end
        if (mp and last_change.mp ~= 0) then
            state.sample_mp = last_change.sample_mp;
            state.heal_mp, state.heal_before_mp, state.gained_mp = 0, 0, 0;
        end
        local changed = (hp and last_change.hp ~= 0) or (mp and last_change.mp ~= 0)
            or (tp and last_change.tp ~= 0);
        if (last_change.accepted and changed) then
            local independent = (not last_change.direct_mp and last_change.mp_evidence >= TICK_MP)
                or (not last_change.direct_tp and last_change.tp < 0)
                or (not last_change.direct_hp and last_change.hp_tick);
            if (not independent) then
                -- The only evidence was the direct action. Keep the countdown that preceded it.
                for _, key in ipairs(PHASE_FIELDS) do state[key] = phase_before[key]; end
                state.sample_hp, state.sample_mp = last_change.sample_hp, last_change.sample_mp;
                state.heal_hp, state.heal_mp = 0, 0;
                state.heal_before_hp, state.heal_before_mp = 0, 0;
                state.rejected = state.rejected + 1;
                last_change.accepted = false;
            end
            state.last_decision = 'direct action';
        end
    end
end

passive_rate = function (stat)
    if (state['gap_regen_known_' .. stat]) then return state['gap_regen_' .. stat], true; end
    if (state['regen_observed_' .. stat]) then return state['regen_' .. stat], true; end
    local model = state.model;
    if (model == nil) then return 0, false; end
    local name = stat == 'hp' and 'regen' or 'refresh';
    return math.max(model[name], 0) - model[name .. '_down'], false;
end

-- A tick landed. Its packet also carries one pass of Regen or Refresh. Taking that off leaves the
-- resting part.
local function remember_heal(when, hp_gain, mp_gain)
    state.regen_hp, state.regen_observed_hp = passive_rate('hp');
    state.regen_mp, state.regen_observed_mp = passive_rate('mp');
    state.gap_regen_hp, state.gap_regen_mp = 0, 0;
    state.gap_regen_known_hp, state.gap_regen_known_mp = false, false;
    clear_pass('hp'); clear_pass('mp');
    if (state.regen_hp ~= 0 or state.regen_mp ~= 0) then state.regen_at = when; end

    state.heal_before_hp, state.heal_before_mp = state.heal_hp, state.heal_mp;
    state.heal_hp = hp_gain ~= nil and math.max(hp_gain - state.regen_hp, 0) or 0;
    state.heal_mp = mp_gain ~= nil and math.max(mp_gain - state.regen_mp, 0) or 0;
    if (hp_gain == nil) then state.heal_before_hp = 0; end
    if (mp_gain == nil) then state.heal_before_mp = 0; end
end

-- What a change in your HP, MP or TP at `when` was. It's a resting tick, or something between ticks.
local function take_change(when, hp_gain, mp_gain, tp_gain, mp_missing, train_hp, train_mp,
    direct_hp, direct_mp, direct_tp, pass_hp, pass_mp)
    last_change.at, last_change.hp, last_change.mp, last_change.tp = when, hp_gain, mp_gain, tp_gain;
    last_change.mp_evidence = mp_gain - passive_rate('mp');
    last_change.hp_tick = is_tick(when, tick_evidence(hp_gain - passive_rate('hp'), nil, nil, 0, state.hp_max));
    last_change.direct_hp, last_change.direct_mp, last_change.direct_tp = direct_hp, direct_mp, direct_tp;
    last_change.accepted = false;
    last_change.sample_hp, last_change.sample_mp = state.sample_hp, state.sample_mp;
    local crossing = state.model_pending or (state.model ~= nil and state.model.transition);
    state.model_pending = false;
    local evidence = tick_evidence(not direct_hp and hp_gain - passive_rate('hp') or nil,
        not direct_mp and mp_gain - passive_rate('mp') or nil,
        not direct_tp and tp_gain or nil, mp_missing, state.hp_max);
    if (crossing) then
        -- A weapon swap can remove TP. Only a positive gain near the expected tick keeps its time.
        if (hp_gain <= 0 and mp_gain <= 0) then
            state.rejected, state.last_decision = state.rejected + 1, 'loadout changed';
            return;
        end
        evidence = evidence ~= nil and 'maybe' or nil;
    end
    if (is_tick(when, evidence)) then
        for _, key in ipairs(PHASE_FIELDS) do phase_before[key] = state[key]; end
        last_change.accepted = true;
        local was_lost = state.lost;
        state.gained_hp = not direct_hp and math.max(hp_gain, 0) or 0;
        state.gained_mp = not direct_mp and math.max(mp_gain, 0) or 0;
        state.seen_at   = when;
        remember_heal(when, not direct_hp and hp_gain or nil, not direct_mp and mp_gain or nil);
        state.hidden    = false;
        state.lost      = false;
        state.skipped   = 0;
        record_tick(when, evidence);
        state.recovery_changed = false;
        state.accepted = state.accepted + 1;
        state.last_decision = crossing and 'tick timing only during loadout change' or 'recovery tick';
        if (not crossing and not was_lost) then
            if (train_hp and not direct_hp) then learn_gain('hp', state.heal_hp); end
            if (train_mp and not direct_mp) then learn_gain('mp', state.heal_mp); end
        end
    else
        if (hp_gain ~= 0 or mp_gain ~= 0 or tp_gain ~= 0) then
            state.rejected = state.rejected + 1;
            state.last_decision = crossing and 'loadout changed'
                or ((direct_hp or direct_mp or direct_tp) and 'direct action' or 'between recovery ticks');
        end
        if (not crossing) then note_pass(when, hp_gain, mp_gain, pass_hp and not direct_hp, pass_mp and not direct_mp); end
    end
end

--[[
    A change under disease, plague or the curse came between ticks, since ticks heal nothing then. But
    the effect can wear off on the very tick that heals you, a moment before cadence reads your buffs.
    A change that came just before cadence saw the effect go can still be that tick.
]]
local function settle_held(now)
    local at = state.held_at;
    state.held_at = nil;
    if (at == nil or not state.active) then
        return;
    end
    -- The effect going away sends your HP and MP with nothing changed, and plague's drain only takes.
    -- Neither one is a tick. A tick that heals always gains HP or MP.
    if (state.blocked == nil and now - at <= BUFF_LAG and (state.held_hp > 0 or state.held_mp > 0)) then
        take_change(at, state.held_hp, state.held_mp, state.held_tp, state.held_missing,
            state.held_train_hp, state.held_train_mp, state.held_direct_hp, state.held_direct_mp,
            state.held_direct_tp, state.held_pass_hp, state.held_pass_mp);
    else
        note_pass(at, state.held_hp, state.held_mp, state.held_pass_hp and not state.held_direct_hp,
            state.held_pass_mp and not state.held_direct_mp);
    end
end

-- Your HP, MP or TP changed. The server sends this for you every time one of them moves.
function resting.on_vitals(now, hp, mp, tp, hp_max, mp_max)
    settle_pass(now, 'hp'); settle_pass(now, 'mp');
    local known = state.hp ~= nil;
    local hp_gain = known and (hp - state.hp) or 0;
    local mp_gain = known and (mp - state.mp) or 0;
    local tp_gain = known and (tp - state.tp) or 0;
    local mp_missing = known and math.max(mp_max - state.mp, 0) or 0;
    local maxima_changed = known and (hp_max ~= state.hp_max or mp_max ~= state.mp_max);

    state.hp, state.mp, state.tp = hp, mp, tp;
    state.hp_max, state.mp_max = hp_max, mp_max;
    state.full = hp >= hp_max and mp >= mp_max;

    if (not state.active or not known) then
        return;
    end
    if (maxima_changed) then
        -- Recalculating maximum vitals may also clamp HP or MP. That packet cannot train a gain.
        forget_recovery();
        state.recovery_changed = true;
        state.model_pending = false;
        return;
    end
    -- A duplicate vitals packet must not hide the gain whose action is still arriving.
    if (hp_gain == 0 and mp_gain == 0 and tp_gain == 0 and last_change.at ~= nil
        and now >= last_change.at and now - last_change.at <= ACTION_WINDOW) then return; end

    local train_hp, train_mp = hp < hp_max, mp < mp_max;
    local direct_hp = state.direct_hp ~= nil and now >= state.direct_hp and now - state.direct_hp <= ACTION_WINDOW;
    local direct_mp = state.direct_mp ~= nil and now >= state.direct_mp and now - state.direct_mp <= ACTION_WINDOW;
    local direct_tp = state.direct_tp ~= nil and now >= state.direct_tp and now - state.direct_tp <= ACTION_WINDOW;
    local pass_hp = hp_gain == 0 or (hp_gain > 0 and hp < hp_max) or (hp_gain < 0 and hp > 0);
    local pass_mp = mp_gain == 0 or (mp_gain > 0 and mp < mp_max) or (mp_gain < 0 and mp > 0);

    -- Ticks heal nothing now, but plague drains TP and MP like a tick. The next buff check decides.
    if (state.blocked ~= nil) then
        settle_held(now);
        state.held_at = now;
        state.held_hp, state.held_mp, state.held_tp, state.held_missing = hp_gain, mp_gain, tp_gain, mp_missing;
        state.held_train_hp, state.held_train_mp = train_hp, train_mp;
        state.held_direct_hp, state.held_direct_mp, state.held_direct_tp = direct_hp, direct_mp, direct_tp;
        state.held_pass_hp, state.held_pass_mp = pass_hp, pass_mp;
        return;
    end
    take_change(now, hp_gain, mp_gain, tp_gain, mp_missing, train_hp, train_mp,
        direct_hp, direct_mp, direct_tp, pass_hp, pass_mp);
end

-- Maximum HP or MP can change without another vitals packet. Keep the last packet's current values.
function resting.on_max_vitals(now, hp_max, mp_max)
    if (state.hp == nil or not finite(hp_max) or hp_max <= 0 or not finite(mp_max) or mp_max < 0
        or (hp_max == state.hp_max and mp_max == state.mp_max)) then return; end
    resting.on_vitals(now, state.hp, state.mp, state.tp, hp_max, mp_max);
end

-- Your buffs, read five times a second. Notes whether disease, plague or the curse is on you.
function resting.on_buffs(now, buffs)
    local found = nil;
    for _, id in ipairs(CANT_HEAL) do
        if (buffs[id]) then
            found = id;
            break;
        end
    end
    state.blocked = found;
    settle_held(now);
end

-- The buff id of disease, plague or the curse while one keeps your ticks from healing you, or nil.
function resting.blocked_by()
    return state.blocked;
end

-- Moves the prediction along when an expected tick doesn't show up.
function resting.update(now)
    if (not state.active) then
        return;
    end
    settle_pass(now, 'hp'); settle_pass(now, 'mp');

    -- Under disease, plague or the curse no tick can show up, so each one is taken to land on time. It
    -- healed nothing, so the step between the ticks before it says nothing about the next one.
    if (state.blocked ~= nil) then
        if (now > state.next_tick) then
            state.heal_hp, state.heal_mp = 0, 0;
            state.skipped = state.skipped + 1;
            record_tick(state.next_tick, 'assumed');
        end
        return;
    end

    if (state.ticks == 0) then
        if (now > state.started_at + FIRST_TICK_LATEST) then
            -- Nothing showed up, so HP and MP were already full. Assume the tick landed on time.
            record_tick(state.next_tick, 'assumed');
        end
        return;
    end

    if (now <= state.next_tick + LOOSE_WINDOW) then
        return;
    end

    if (state.next_gap == SHORT_GAP and not state.hidden) then
        -- No tick yet, so this is one of the long gaps.
        state.next_gap  = LONG_GAP;
        state.next_tick = state.last_tick + LONG_GAP;
        return;
    end

    -- Under Signet a tick at full HP and MP changes nothing. Nothing shows up. Once a long gap passes
    -- with nothing, the timer follows the pattern without waiting for ticks. Below full a tick always
    -- shows. A missing one means the timer lost track.
    if (state.full) then
        state.hidden = true;
    else
        state.lost = true;
    end
    record_tick(state.next_tick, 'assumed');
end

-- True while you are resting.
function resting.is_active()
    return state.active;
end

-- Returns how full the bar is (0..1), seconds to the next tick, the tick count, what the last tick
-- restored and whether HP and MP are full. Returns nil when you are not resting.
function resting.progress(now)
    if (not state.active) then
        return nil;
    end

    local from = state.last_tick or state.started_at;
    local span = state.next_tick - from;
    local left = state.next_tick - now;
    if (left < 0) then
        left = 0;
    end

    local fill = 1;
    if (span > 0) then
        fill = 1 - left / span;
    end
    -- A tick that healed nothing came after the last one you saw, so the last tick restored nothing.
    if (state.skipped > 0) then
        return fill, left, state.ticks, 0, 0, state.full;
    end
    return fill, left, state.ticks, state.gained_hp, state.gained_mp, state.full;
end

-- When the last tick you could see landed, or nil before the first one.
function resting.seen_at()
    return state.seen_at;
end

-- Each tick's resting part restores a set amount more than the one before. Two ticks in a row show
-- how much. Returns nil until then.
local function step_between(last, before)
    if (before > 0 and last > before) then
        return last - before;
    end
    return nil;
end

local function next_gain(stat)
    local gain, step, confidence = modeled_gain(stat, state.ticks + 1);
    if (gain ~= nil) then return gain, step, confidence; end
    local last = state['heal_' .. stat];
    step = step_between(last, state['heal_before_' .. stat]);
    if (last > 0 and step ~= nil) then return last + step, step, 'observed'; end
    return nil, nil, 'unknown';
end

-- The next resting gain, capped by missing vitals. Regen and Refresh stay separate.
function resting.next_gains()
    if (not state.active or state.hp == nil) then return nil; end
    local hp, hp_step, hp_confidence = next_gain('hp');
    local mp, mp_step, mp_confidence = next_gain('mp');
    local confidence = {
        hp = hp_confidence,
        mp = mp_confidence,
        hp_uncapped = hp,
        mp_uncapped = mp,
        hp_step = hp_step,
        mp_step = mp_step,
        tick = state.ticks + 1,
        unknown = state.model and state.model.unknown or nil,
        transition = state.model ~= nil and state.model.transition,
    };
    if (state.blocked ~= nil) then
        confidence.hp, confidence.mp = 'blocked', 'blocked';
        return 0, 0, confidence;
    end
    local hp_missing = math.max(0, state.hp_max - state.hp);
    local mp_missing = math.max(0, state.mp_max - state.mp);
    if (hp_missing == 0) then hp = 0;
    elseif (hp ~= nil) then hp = math.min(hp, hp_missing); end
    if (mp_missing == 0) then mp = 0;
    elseif (mp ~= nil) then mp = math.min(mp, mp_missing); end
    return hp, mp, confidence;
end

-- Recovery and Regen/Refresh run on separate schedules. Simulate them together so a full stat
-- that drains cannot be treated as still full when the other one catches up.
local recovery_stats = { hp = {}, mp = {} };
local function full_estimate(now, targets)
    if (not state.active or state.hp == nil) then return nil; end
    local meta, stats = {}, recovery_stats;
    local phase_known = resting.pattern_known() and not state.lost;
    local model = state.model;
    local stopped = state.blocked ~= nil or (model and model.regen_down > 0);
    local blocked_confidence = state.blocked and 'blocked' or 'unknown';
    local rates = false;
    for _, stat in ipairs(STATS) do
        local gain, step, confidence = next_gain(stat);
        local rate, observed = passive_rate(stat);
        local name = stat == 'hp' and 'regen' or 'refresh';
        if (not phase_known or (model and model.transition)
            or (model and not model[name .. '_known'] and not observed)) then confidence = 'estimated'; end
        if (rate ~= 0 and state.regen_at == nil and state.seen_at == nil) then confidence = 'estimated'; end
        local current, maximum = state[stat], state[stat .. '_max'];
        local target = targets and targets[stat] or maximum;
        local full = current >= target;
        if (target == 0) then gain, step, rate, confidence = 0, 0, 0, 'known'; end
        if (full and rate >= 0) then
            gain, step, confidence = gain or 0, step or 0, 'known';
        end
        local predictable = gain ~= nil and step ~= nil;
        if (not predictable and rate > 0) then
            -- A known passive gain can fill this stat even before resting potency is known.
            gain, step, confidence, predictable = 0, 0, 'estimated', true;
        end
        if (not predictable) then confidence = 'unknown'; end
        local record = stats[stat];
        record.value, record.maximum, record.target = current, maximum, target;
        record.gain, record.step, record.rate = gain, step, rate;
        record.confidence, record.full_at, record.predictable = confidence, full and 0 or nil, predictable;
        meta[stat .. '_ticks'] = full and 0 or nil;
        meta[stat .. '_confidence'] = full and 'known' or (stopped and blocked_confidence or confidence);
        rates = rates or rate ~= 0;
    end
    local hp, mp = stats.hp, stats.mp;
    if (hp.value >= hp.target and mp.value >= mp.target) then
        meta.full_in, meta.ticks, meta.confidence = 0, 0, 'known';
        return 0, 0, meta;
    end
    if (stopped) then
        meta.confidence = blocked_confidence;
        return hp.full_at, mp.full_at, meta;
    end
    local unknown = not hp.predictable or not mp.predictable;
    if (unknown and (not hp.predictable or hp.full_at ~= nil) and (not mp.predictable or mp.full_at ~= nil)) then
        meta.confidence = 'unknown';
        return hp.full_at, mp.full_at, meta;
    end
    local confidence = (hp.confidence == 'estimated' or mp.confidence == 'estimated') and 'estimated'
        or ((hp.confidence == 'observed' or mp.confidence == 'observed') and 'observed' or 'known');
    local rest_at = now + math.max(state.next_tick - now, 0.1);
    local last_gap, before_gap = state.next_gap, state.gap_last;
    local anchor = state.regen_at or state.seen_at or state.started_at or now;
    local pass_at = rates and (anchor + (math.floor(math.max(now - anchor, 0) / EFFECT_PASS) + 1) * EFFECT_PASS)
        or math.huge;
    local ticks = 0;
    for _ = 1, 500 do
        local at = math.min(rest_at, pass_at);
        if (math.abs(at - pass_at) < 0.01) then
            for _, stat in pairs(stats) do
                if (stat.predictable) then
                    stat.value = math.max(0, math.min(stat.maximum, stat.value + stat.rate));
                end
            end
            pass_at = pass_at + EFFECT_PASS;
        end
        if (math.abs(at - rest_at) < 0.01) then
            for _, stat in pairs(stats) do
                if (stat.predictable) then
                    stat.value = math.min(stat.maximum, stat.value + stat.gain);
                    stat.gain = stat.gain + stat.step;
                end
            end
            ticks = ticks + 1;
            local gap = TICK_INTERVAL;
            if (phase_known) then gap = (last_gap == SHORT_GAP and before_gap == SHORT_GAP) and LONG_GAP or SHORT_GAP; end
            before_gap, last_gap = last_gap, gap;
            rest_at = rest_at + gap;
        end
        for name, stat in pairs(stats) do
            if (stat.full_at == nil and stat.value >= stat.target) then
                stat.full_at = at - now;
                meta[name .. '_ticks'] = ticks;
            end
        end
        if (not unknown and hp.value >= hp.target and mp.value >= mp.target) then
            meta.full_in, meta.ticks, meta.confidence = at - now, ticks, confidence;
            return hp.full_at, mp.full_at, meta;
        end
        if (unknown and (not hp.predictable or hp.full_at ~= nil) and (not mp.predictable or mp.full_at ~= nil)) then
            break;
        end
        if (ticks >= 99) then break; end
    end
    meta.confidence = 'unknown';
    return hp.full_at, mp.full_at, meta;
end

-- Existing seconds stay first. The extra metadata explains confidence and remaining resting ticks.
function resting.until_full(now)
    if (not state.active or state.hp == nil) then return nil; end
    local hp, mp, meta = full_estimate(now);
    if (state.full or hp == nil or mp == nil) then return nil, meta; end
    return meta.full_in, meta;
end

function resting.until_each_full(now)
    if (not state.active or state.hp == nil) then return nil; end
    local hp, mp, meta = full_estimate(now);
    return hp, mp, state.mp_max > 0, meta;
end

-- Goals share the full-recovery simulation without changing the full-HP/MP state.
function resting.goal_progress(now, stat, mode, value)
    if (not finite(now) or not finite(value) or state.hp == nil
        or (stat ~= 'hp' and stat ~= 'mp' and stat ~= 'both')
        or (mode ~= 'percent' and mode ~= 'amount')) then return nil; end
    local targets = {};
    for _, name in ipairs(STATS) do
        local maximum = state[name .. '_max'];
        local amount = mode == 'percent' and maximum * math.max(0, math.min(100, value)) / 100 or value;
        targets[name] = (stat == name or stat == 'both') and math.max(0, math.min(maximum, math.ceil(amount))) or 0;
    end
    local reached = state.hp >= targets.hp and state.mp >= targets.mp;
    local result = { reached = reached, target_hp = targets.hp, target_mp = targets.mp,
        confidence = reached and 'known' or 'unknown' };
    if (reached) then result.seconds, result.ticks = 0, 0; return result; end
    if (not state.active) then return result; end
    local _, _, meta = full_estimate(now, targets);
    result.seconds, result.ticks, result.confidence = meta.full_in, meta.ticks, meta.confidence;
    return result;
end

function resting.info(now)
    local seconds, meta = resting.until_full(now);
    local hp, mp, confidence = resting.next_gains();
    return { active = state.active, ticks = state.ticks, pattern_known = resting.pattern_known(),
        last_tick = state.seen_at, next_tick = state.next_tick, blocked = state.blocked,
        accepted = state.accepted, rejected = state.rejected, last_decision = state.last_decision,
        next_hp = hp, next_mp = mp, gain_confidence = confidence, full_in = seconds, full = meta,
        regen_hp = passive_rate('hp'), regen_mp = passive_rate('mp') };
end

-- True at full HP and MP.
function resting.is_full()
    return state.full;
end

-- True once cadence has seen your HP and MP since it loaded or you last zoned.
function resting.knows_vitals()
    return state.hp ~= nil;
end

-- Forgets your last vitals, for example after a zone change.
function resting.reset()
    state.active = false;
    state.hp, state.mp, state.tp = nil, nil, nil;
    state.model = nil;
    state.model_pending = false;
    state.direct_hp, state.direct_mp, state.direct_tp = nil, nil, nil;
    last_change.at = nil;
    state.recovery_changed = false;
    forget_recovery();
end

return resting;
