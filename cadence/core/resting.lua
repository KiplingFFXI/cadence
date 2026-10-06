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

-- Disease (8), plague (31) and the curse that stops healing (20). The first one found is the one named.
local CANT_HEAL = { 8, 31, 20 };

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
    gap_regen_hp   = 0,      -- Regen and Refresh seen so far in the current gap.
    gap_regen_mp   = 0,
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
};

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
    if (mp_gain >= TICK_MP or tp_gain < 0) then
        return 'sure';
    end
    -- With 12 or more MP missing, a real tick would have restored at least 12 MP.
    if (mp_missing >= TICK_MP) then
        return nil;
    end
    -- Each tick restores a little more HP than the one before. The step is 1 HP, or 1 + max HP / 300
    -- under Signet. A tick that healed nothing still counts a step. A much bigger jump is a cure.
    local steps = (1 + math.floor(hp_max / 300)) * (1 + state.skipped);
    if (state.gained_hp > 0 and hp_gain > state.gained_hp + steps + HP_STEP_SLACK) then
        return nil;
    end
    if (hp_gain >= TICK_HP or (hp_gain == 0 and mp_gain == 0 and tp_gain == 0)) then
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
    state.gained_hp, state.gained_mp = 0, 0;
    state.heal_hp, state.heal_mp = 0, 0;
    state.heal_before_hp, state.heal_before_mp = 0, 0;
    state.regen_hp, state.regen_mp = 0, 0;
    state.pass_hp, state.pass_mp = nil, nil;
    state.gap_regen_hp, state.gap_regen_mp = 0, 0;
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

--[[
    Regen and Refresh add the same amount on every 3 s pass. A cure lands once. A gain between ticks
    that matches the one before it is Regen or Refresh.
]]
local function note_pass(hp_gain, mp_gain)
    if (hp_gain > 0) then
        if (hp_gain == state.pass_hp) then
            state.gap_regen_hp = hp_gain;
        end
        state.pass_hp = hp_gain;
    end
    if (mp_gain > 0) then
        if (mp_gain == state.pass_mp) then
            state.gap_regen_mp = mp_gain;
        end
        state.pass_mp = mp_gain;
    end
end

-- A tick landed. Its packet also carries one pass of Regen or Refresh. Taking that off leaves the
-- resting part.
local function remember_heal(hp_gain, mp_gain)
    state.regen_hp, state.regen_mp = state.gap_regen_hp, state.gap_regen_mp;
    state.gap_regen_hp, state.gap_regen_mp = 0, 0;
    state.pass_hp, state.pass_mp = nil, nil;

    state.heal_before_hp, state.heal_before_mp = state.heal_hp, state.heal_mp;
    state.heal_hp = math.max(hp_gain - state.regen_hp, 0);
    state.heal_mp = math.max(mp_gain - state.regen_mp, 0);
end

-- What a change in your HP, MP or TP at `when` was. It's a resting tick, or something between ticks.
local function take_change(when, hp_gain, mp_gain, tp_gain, mp_missing)
    local evidence = tick_evidence(hp_gain, mp_gain, tp_gain, mp_missing, state.hp_max);
    if (is_tick(when, evidence)) then
        state.gained_hp = math.max(hp_gain, 0);
        state.gained_mp = math.max(mp_gain, 0);
        state.seen_at   = when;
        remember_heal(state.gained_hp, state.gained_mp);
        state.hidden    = false;
        state.lost      = false;
        state.skipped   = 0;
        record_tick(when, evidence);
    else
        note_pass(hp_gain, mp_gain);
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
        take_change(at, state.held_hp, state.held_mp, state.held_tp, state.held_missing);
    else
        note_pass(state.held_hp, state.held_mp);
    end
end

-- Your HP, MP or TP changed. The server sends this for you every time one of them moves.
function resting.on_vitals(now, hp, mp, tp, hp_max, mp_max)
    local known = state.hp ~= nil;
    local hp_gain = known and (hp - state.hp) or 0;
    local mp_gain = known and (mp - state.mp) or 0;
    local tp_gain = known and (tp - state.tp) or 0;
    local mp_missing = known and math.max(mp_max - state.mp, 0) or 0;

    state.hp, state.mp, state.tp = hp, mp, tp;
    state.hp_max, state.mp_max = hp_max, mp_max;
    state.full = hp >= hp_max and mp >= mp_max;

    if (not state.active or not known) then
        return;
    end

    -- Ticks heal nothing now, but plague drains TP and MP like a tick. The next buff check decides.
    if (state.blocked ~= nil) then
        settle_held(now);
        state.held_at = now;
        state.held_hp, state.held_mp, state.held_tp, state.held_missing = hp_gain, mp_gain, tp_gain, mp_missing;
        return;
    end
    take_change(now, hp_gain, mp_gain, tp_gain, mp_missing);
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

--[[
    Ticks needed to restore `missing`. The last tick's resting part was `last`. Each tick adds `step`
    more. Regen or Refresh adds `regen` on top every 3 s pass.
]]
local function ticks_to_restore(missing, last, step, regen)
    if (missing <= 0) then
        return 0;
    end
    if (last <= 0 or step == nil) then
        return nil;
    end

    local regen_per_tick = regen * TICK_INTERVAL / EFFECT_PASS;
    local ticks, restored, gain = 0, 0, last;
    while (restored < missing and ticks < 99) do
        gain = gain + step;
        restored = restored + gain + regen_per_tick;
        ticks = ticks + 1;
    end
    return ticks;
end

-- Ticks until HP and until MP are full. Either is nil when it can't be worked out yet.
local function ticks_until_full()
    local hp_ticks = ticks_to_restore(state.hp_max - state.hp, state.heal_hp,
        step_between(state.heal_hp, state.heal_before_hp), state.regen_hp);
    local mp_ticks = ticks_to_restore(state.mp_max - state.mp, state.heal_mp,
        step_between(state.heal_mp, state.heal_before_mp), state.regen_mp);
    return hp_ticks, mp_ticks;
end

-- Seconds for that many ticks. The first is the one already counting down. The others average 10 s
-- apart. A tick running late is still owed. This is only 0 when nothing is left.
local function seconds_for(ticks, now)
    if (ticks == nil) then
        return nil;
    end
    if (ticks == 0) then
        return 0;
    end
    return math.max(state.next_tick - now, 0.1) + (ticks - 1) * TICK_INTERVAL;
end

-- Seconds until HP and MP are both full, or nil when it can't be worked out yet.
function resting.until_full(now)
    if (not state.active or state.full or state.hp == nil) then
        return nil;
    end

    local hp_ticks, mp_ticks = ticks_until_full();
    if (hp_ticks == nil or mp_ticks == nil) then
        return nil;
    end

    local ticks = math.max(hp_ticks, mp_ticks);
    if (ticks == 0) then
        return nil;
    end
    return seconds_for(ticks, now);
end

--[[
    Seconds until HP is full and until MP is full. Each is 0 once it's full, or nil when it can't be
    worked out yet. The third value is false for a job with no MP. Returns nothing when you are not
    resting.
]]
function resting.until_each_full(now)
    if (not state.active or state.hp == nil) then
        return nil;
    end
    local hp_ticks, mp_ticks = ticks_until_full();
    return seconds_for(hp_ticks, now), seconds_for(mp_ticks, now), state.mp_max > 0;
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
end

return resting;
