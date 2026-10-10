--[[
    The enemy attack timer. It keeps a clock for each monster attacking near you. When you switch
    targets the bar is already in step.

    Monsters time their attacks with the same server code as players (LSB attack_state.cpp). Phoenix
    runs it unchanged. The first attack comes 2.8 s after a monster engages. Each attack adds its
    delay to a timer that drains in 0.4 s ticks. Leftover time carries over.
    A monster's delay can't be seen from the client. Most monsters use the default delay of 240, or
    4 s. That's the first guess until its own attacks show the real one. A monster with the same name
    as one learned earlier in that zone starts from that one's delay instead.
    TP moves and spells pause the timer while they run. It picks up about 2 s after they finish.
    Observed control effects stop learning. Their end waits for a new attack to set the clock.
    A monster chasing you still has no visible pause. A bar that runs out shows ready. It
    shows waiting once a whole delay goes by with no attack. The next attack puts it back in step.
    Slow, Elegy and Haste change a monster's delay. Its gaps with none of them on are kept apart from
    its gaps with them on. Going back and forth doesn't mix up what was learned.
]]

local monster_effects = require('core.monster_effects');

local enemy = {};

local SLOW, HASTE, HUNDRED_FISTS, ELEGY = monster_effects.SLOW, monster_effects.HASTE,
    monster_effects.HUNDRED_FISTS, monster_effects.ELEGY;

-- Haste can take at most 43.75% off a delay. Slow and Elegy can at most double it.
local MOST_HASTE = 0.4375;

-- Hundred Fists ignores Haste and Slow. The delay is kept between 1.6 and 8 s, then quartered.
local FISTS_SHARE, FISTS_FLOOR, FISTS_CEILING = 0.25, 1.6, 8.0;

-- Your own effects come off when their wear-off message arrives. If it's missed, they're dropped
-- this long past the longest they can last.
local WEAR_OFF_SLACK = 10;

local FIRST_ATTACK_SECONDS = 2.8;
local DEFAULT_DELAY        = 4.0;
local HOLD_TAIL_SECONDS    = 2.0;
local TICK_SECONDS         = 0.4;
local GAPS_TO_TRUST        = 3;
local GAPS_KEPT            = 6;

-- A gap further than this from the middle one had a pause in it that cadence couldn't see.
local NEAR_MIDDLE = 0.5;

-- A gap longer than this many times the learned delay had a pause in it. It isn't kept. Slow and
-- Elegy can at most double a delay. A slowed monster's gaps stay under it.
local LONGEST_GAP_RATIO = 2.5;

-- Until a delay is learned, a gap is a pause only when no monster attacks that slowly. The slowest
-- monsters are 500 delay. Slow and Elegy can double that.
local LONGEST_DELAY = 500 * 2 / 60;

-- How long a monster counts as active after its last round, TP move or spell. A long spell and the
-- 2 s after it can keep a monster from attacking for over 10 s. A monster that attacks slower than
-- that, like a slow one under Slow and Elegy, gets one and a half of its own delay instead.
local ACTIVE_SECONDS = 10;
local ACTIVE_DELAYS  = 1.5;

-- A monster with no packets for this long is dropped. The cap on clocks is only a backstop. Pets
-- and NPC fighters get clocks too.
local FORGET_SECONDS = 30;
local MOST_CLOCKS    = 64;
local CONTROL_ORDER = { 7, 28, 10, 2 };

-- How many monster names keep their delay. Past this the oldest one saved goes.
local MOST_SPEEDS = 64;

local clocks = {};   -- [monster server id] = its clock
local count  = 0;
local sorted = {};   -- Reused to find the middle gap without making garbage.

-- Delays learned with no effects on, kept until another character logs in. They're never saved
-- to a file. `saved` counts up with each save, so the oldest one can be found.
local speeds      = {};   -- ['zone name'] = { delay, saved }
local speed_count = 0;
local saves       = 0;

local function new_clock(now)
    return {
        last_attack   = nil,    -- When the last round arrived, or when it engaged.
        next_attack   = nil,    -- When the next round is expected.
        delay         = DEFAULT_DELAY,   -- The delay in use, with any effects on it.
        base_gaps     = {},     -- Recent clean gaps with no effects on.
        base_guess    = DEFAULT_DELAY,   -- Its delay with no effects, until base_gaps shows it.
        recalled      = false,
        effect_gaps   = {},     -- Recent clean gaps with the effects it has on now.
        effects       = {},     -- [effect id] = { power, exact, sure_until, ends_at }
        controls      = {},     -- Observed attack-preventing effects, with uncertain durations.
        control_since = nil,
        resync        = false,  -- A control ended; only another attack can set the next due time.
        changes       = 0,      -- Goes up each time an effect lands or comes off.
        round_changes = 0,      -- `changes` and whether it had any effects when it last attacked.
        round_plain   = true,
        tag           = nil,    -- Like "slow" or "slow+elegy", and the same with "?" for an unsure one.
        tag_unsure    = nil,
        clean         = false,  -- False when something held the timer since the last round.
        held_since    = nil,    -- Set while a TP move or spell runs.
        held_by       = nil,    -- 'tp_move' or 'spell', for the one running.
        target        = 0,      -- Who it attacked last.
        seen          = now,    -- Its last packet.
        last_action   = nil,    -- Its last round, TP move or spell starting or ending, or when it engaged.
    };
end

local function forget(id)
    if (clocks[id] ~= nil) then
        clocks[id] = nil;
        count = count - 1;
    end
end

local function forget_oldest()
    local oldest_id, oldest_seen = nil, math.huge;
    for id, clock in pairs(clocks) do
        if (clock.seen < oldest_seen) then
            oldest_id, oldest_seen = id, clock.seen;
        end
    end
    forget(oldest_id);
end

local function clock_for(now, id)
    local clock = clocks[id];
    if (clock == nil) then
        clock = new_clock(now);
        clocks[id] = clock;
        count = count + 1;
        if (count > MOST_CLOCKS) then
            forget_oldest();
        end
    end
    clock.seen = now;
    return clock;
end

local function middle_gap(gaps)
    for i = 1, #gaps do
        sorted[i] = gaps[i];
    end
    for i = #gaps + 1, #sorted do
        sorted[i] = nil;
    end
    table.sort(sorted);
    return sorted[math.floor((#sorted + 1) / 2)];
end

-- The average of the gaps near the middle one. Monsters whose delay isn't a whole number of ticks
-- alternate between two gaps, like 4.4 and 4.8 s. The average lands on the real delay.
local function learned_delay(gaps)
    local middle = middle_gap(gaps);
    local total, used = 0, 0;
    for i = 1, #gaps do
        if (math.abs(gaps[i] - middle) <= NEAR_MIDDLE) then
            total = total + gaps[i];
            used = used + 1;
        end
    end
    return total / used;
end

local function remember_gap(gaps, gap)
    if (gap <= 0) then return; end
    local longest = LONGEST_DELAY;
    if (#gaps >= GAPS_TO_TRUST) then
        longest = learned_delay(gaps) * LONGEST_GAP_RATIO;
    end
    if (gap > longest) then
        return;
    end
    table.insert(gaps, gap);
    if (#gaps > GAPS_KEPT) then
        table.remove(gaps, 1);
    end
end

local function forget_gaps(gaps)
    for i = #gaps, 1, -1 do
        gaps[i] = nil;
    end
end

-- Its delay with no effects on.
local function base_delay(clock)
    if (#clock.base_gaps > 0) then
        return learned_delay(clock.base_gaps);
    end
    return clock.base_guess;
end

-- How much the effects on it stretch its delay, like 1.25 for a 25% Slow.
local function stretch(effects)
    local haste = 0;
    if (effects[HASTE] ~= nil) then
        haste = haste + effects[HASTE].power;
    end
    if (effects[SLOW] ~= nil) then
        haste = haste - effects[SLOW].power;
    end
    if (effects[ELEGY] ~= nil) then
        haste = haste - effects[ELEGY].power;
    end
    return 1 - math.max(-1, math.min(MOST_HASTE, haste / 10000));
end

-- Works out the delay in use from what was learned and the effects it has on.
local function update_delay(clock)
    local base = base_delay(clock);
    if (clock.effects[HUNDRED_FISTS] ~= nil) then
        clock.delay = math.max(FISTS_FLOOR, math.min(FISTS_CEILING, base)) * FISTS_SHARE;
    elseif (next(clock.effects) == nil) then
        clock.delay = base;
    elseif (#clock.effect_gaps > 0) then
        clock.delay = learned_delay(clock.effect_gaps);
    else
        clock.delay = base * stretch(clock.effects);
    end
end

-- True when its delay with the effects on is known without gaps of its own. Its plain delay has to
-- be learned. Every effect on it has to be one that's always the same strength.
local function sure_of_effects(clock)
    if (next(clock.effects) == nil or #clock.base_gaps < GAPS_TO_TRUST) then
        return false;
    end
    for _, on in pairs(clock.effects) do
        if (not on.exact) then
            return false;
        end
    end
    return true;
end

-- The gaps that go with the effects it has on now. Hundred Fists gaps aren't kept.
local function gaps_in_use(clock)
    if (next(clock.effects) == nil) then
        return clock.base_gaps;
    end
    return clock.effect_gaps;
end

-- "slow", "slow+elegy" and so on, made once each time the effects change.
local TAG_ORDER = { { SLOW, 'slow' }, { ELEGY, 'elegy' }, { HASTE, 'haste' }, { HUNDRED_FISTS, 'hundred fists' } };
local function update_tag(clock)
    local tag = nil;
    for _, entry in ipairs(TAG_ORDER) do
        if (clock.effects[entry[1]] ~= nil) then
            tag = tag and (tag .. '+' .. entry[2]) or entry[2];
        end
    end
    clock.tag = tag;
    clock.tag_unsure = tag and (tag .. '?') or nil;
end

--[[
    Call before an effect lands or comes off. A monster slowed from the pull has no gaps without the
    effect. Taking the effect's stretch back out of its gaps gives the best guess at its delay
    without it.
]]
local function before_change(clock)
    if (#clock.base_gaps == 0 and #clock.effect_gaps > 0 and clock.effects[HUNDRED_FISTS] == nil) then
        clock.base_guess = learned_delay(clock.effect_gaps) / stretch(clock.effects);
    end
end

local function after_change(clock)
    clock.changes = clock.changes + 1;
    forget_gaps(clock.effect_gaps);
    update_delay(clock);
    update_tag(clock);
end

-- Removing a control gives no exact next-attack time.
local function control_gone(clock, effect)
    if (effect == 19 or effect == 193) then effect = 2; end
    if (clock.controls[effect] == nil) then return false; end
    clock.controls[effect] = nil;
    clock.clean, clock.resync = false, true;
    if (next(clock.controls) == nil) then clock.control_since = nil; end
    return true;
end

-- Takes off effects that can't still be on. Control expiry remains an estimate.
local function expire(clock, now)
    for effect, on in pairs(clock.controls) do
        if (now >= on.ends_at) then control_gone(clock, effect); end
    end
    local gone = false;
    for _, on in pairs(clock.effects) do
        if (now > on.ends_at) then
            gone = true;
            break;
        end
    end
    if (not gone) then
        return;
    end
    before_change(clock);
    for effect, on in pairs(clock.effects) do
        if (now > on.ends_at) then
            clock.effects[effect] = nil;
        end
    end
    after_change(clock);
end

--[[
    The gap from its last attack to this one. The delay behind it was set when the last attack went
    off. It's kept with the effects it had then. A gap from before the latest change of effects
    matches neither list. It's dropped.
]]
local function file_gap(clock, gap)
    if (clock.round_plain) then
        remember_gap(clock.base_gaps, gap);
    elseif (clock.round_changes == clock.changes and clock.effects[HUNDRED_FISTS] == nil) then
        remember_gap(clock.effect_gaps, gap);
    end
    update_delay(clock);
end

-- A monster's attack round arrived. `target` is the server id of who it attacked.
function enemy.on_round(now, id, target)
    local clock = clock_for(now, id);
    expire(clock, now);
    if (clock.clean and not clock.resync and next(clock.controls) == nil) then
        file_gap(clock, now - clock.last_attack);
    end
    for effect in pairs(clock.controls) do clock.controls[effect] = nil; end
    clock.control_since, clock.resync = nil, false;
    clock.round_changes, clock.round_plain = clock.changes, next(clock.effects) == nil;
    clock.last_attack = now;
    clock.last_action = now;
    clock.next_attack = now + clock.delay;
    clock.held_since  = nil;
    clock.clean       = true;
    clock.target      = target;
end

--[[
    Slow, Elegy, Haste or Hundred Fists landed on a monster. `info` is its entry from
    monster_effects. `mine` is true when you cast it. Only then do you get a wear-off message. A new
    Slow or Elegy replaces the last one. Haste and Slow cancel each other out.
]]
function enemy.on_effect(now, id, info, mine)
    local clock = clock_for(now, id);
    if (info.control ~= nil) then
        clock.controls[info.effect] = { control = info.control, ends_at = now + info.lasts,
            duration_estimate = info.duration_estimate, duration_basis = info.duration_basis,
            inputs_known = info.inputs_known, cast_inputs = info.cast_inputs };
        clock.control_since = clock.control_since or now;
        clock.clean, clock.resync = false, true;
        clock.held_since, clock.held_by = nil, nil;
        return;
    end
    before_change(clock);
    local effects = clock.effects;
    if (info.effect == SLOW) then
        effects[HASTE] = nil;
    elseif (info.effect == HASTE) then
        effects[SLOW] = nil;
    end
    effects[info.effect] = {
        power      = info.power,
        exact      = info.exact,
        sure_until = mine and math.huge or (now + info.sure_for),
        ends_at    = now + info.lasts + (mine and WEAR_OFF_SLACK or 0),
        duration_estimate = info.duration_estimate, duration_basis = info.duration_basis,
        duration_uncertain = info.duration_uncertain,
        inputs_known = info.inputs_known, cast_inputs = info.cast_inputs,
    };
    after_change(clock);
end

-- An effect wore off the monster, or something took it off.
function enemy.on_effect_gone(now, id, effect)
    local clock = clocks[id];
    if (clock ~= nil and control_gone(clock, effect)) then clock.seen = now; return; end
    if (clock == nil or clock.effects[effect] == nil) then
        return;
    end
    clock.seen = now;
    before_change(clock);
    clock.effects[effect] = nil;
    after_change(clock);
end

-- Positive damage wakes an observed Sleep. Bind is not an attack-preventing effect.
function enemy.on_damage(now, id, damage)
    local clock = clocks[id];
    if (clock ~= nil and damage > 0 and control_gone(clock, 2)) then clock.seen = now; end
end

-- A paralyzed or intimidated round. It uses up the timer and shows who the monster was attacking.
-- Its gap isn't learned.
function enemy.on_paralyzed(now, id, target)
    local clock = clock_for(now, id);
    expire(clock, now);
    for effect in pairs(clock.controls) do clock.controls[effect] = nil; end
    clock.control_since, clock.resync = nil, false;
    clock.last_attack = now;
    clock.last_action = now;
    clock.next_attack = now + clock.delay;
    clock.held_since  = nil;
    clock.clean       = false;
    if (target ~= nil and target ~= 0) then
        clock.target = target;
    end
end

-- The monster readied a TP move or started a spell. Its timer stops until that finishes. `kind` is
-- 'tp_move' or 'spell'.
function enemy.on_hold_begin(now, id, kind)
    local clock = clocks[id];
    if (clock == nil or clock.next_attack == nil or clock.held_since ~= nil) then
        return;
    end
    clock.seen        = now;
    clock.last_action = now;
    clock.held_since  = now;
    clock.held_by     = kind;
    clock.clean       = false;
end

--[[
    The TP move or spell finished, or a TP move was cut off. A finish adds the 2 s the server waits
    after one. A TP move only gets cut off when the monster is stunned or put to sleep. Then `stunned`
    is true and adds no tail. The bar runs out, then waits for the next round. A TP move with no
    ready time finishes without starting.
]]
function enemy.on_hold_end(now, id, stunned)
    local clock = clocks[id];
    if (clock == nil or clock.next_attack == nil) then
        return;
    end
    expire(clock, now);
    if (clock.held_since == nil and clock.next_attack - now <= TICK_SECONDS) then
        -- Some monsters, like flying wyrms, attack with TP moves. The attack used up its delay.
        clock.last_attack = now;
        clock.next_attack = now + clock.delay + HOLD_TAIL_SECONDS;
    else
        local from = clock.held_since or now;
        local remaining = math.max(clock.next_attack - from, 0);
        clock.next_attack = now + remaining + (stunned and 0 or HOLD_TAIL_SECONDS);
    end
    clock.seen        = now;
    clock.last_action = now;
    clock.held_since  = nil;
    clock.clean       = false;
end

-- The TP move or spell was cut off. A spell still waits out its 2 s and ends like a finish. A
-- paralyzed spell sends its finish first. That already ended the hold.
function enemy.on_interrupt(now, id, spell)
    local clock = clocks[id];
    if (clock ~= nil and clock.held_since ~= nil) then
        enemy.on_hold_end(now, id, not spell);
    end
end

-- The monster engaged. Its first round comes 2.8 s later. One that's already fighting is left alone.
function enemy.on_engage(now, id)
    local clock = clocks[id];
    if (clock ~= nil and clock.next_attack ~= nil and now - clock.seen < clock.delay) then
        return;
    end
    clock = clock_for(now, id);
    clock.last_attack = now;
    clock.last_action = now;
    clock.next_attack = now + FIRST_ATTACK_SECONDS;
    clock.held_since  = nil;
    clock.clean       = false;
end

-- The monster stopped fighting, died or is gone.
enemy.forget = forget;
enemy.on_disappear = forget;

function enemy.has(id)
    return clocks[id] ~= nil;
end

-- True while the monster counts as active, set by ACTIVE_SECONDS and ACTIVE_DELAYS.
function enemy.active(now, id)
    local clock = clocks[id];
    if (clock == nil or clock.last_action == nil) then
        return false;
    end
    return next(clock.controls) ~= nil or clock.held_since ~= nil
        or now - clock.last_action < math.max(ACTIVE_SECONDS, clock.delay * ACTIVE_DELAYS);
end

-- The server id of who the monster attacked last, or nil before its first round.
function enemy.last_target(id)
    local clock = clocks[id];
    if (clock == nil or clock.target == 0) then
        return nil;
    end
    return clock.target;
end

--[[
    Returns how full the bar is (0..1), the seconds until the next round, the delay in use, whether
    that delay was learned, whether the monster is overdue by a whole delay, a tag for its effects,
    and 'tp_move' or 'spell' while one holds its timer. The tag is like "slow", or "slow?" once
    another player's Slow might have worn off. Returns nil when there's no clock for it yet.
]]
function enemy.progress(now, id)
    local clock = clocks[id];
    if (clock == nil or clock.next_attack == nil) then
        return nil;
    end
    expire(clock, now);

    if (clock.resync and next(clock.controls) == nil) then
        return 1, 0, clock.delay, false, true, clock.tag, 'observing';
    end
    local control;
    for _, effect in ipairs(CONTROL_ORDER) do
        if (clock.controls[effect] ~= nil) then control = clock.controls[effect].control; break; end
    end
    -- Both kinds of hold preserve the last phase without predicting when a control will end.
    local clock_now = clock.control_since or clock.held_since or now;
    local span = clock.next_attack - clock.last_attack;
    local left = clock.next_attack - clock_now;
    local waiting = left < -clock.delay;
    if (left < 0) then
        left = 0;
    end

    local fill = 1;
    if (span > 0) then
        fill = 1 - left / span;
    end
    local tag = clock.tag;
    for _, on in pairs(clock.effects) do
        if (now > on.sure_until) then
            tag = clock.tag_unsure;
            break;
        end
    end
    local learned = #gaps_in_use(clock) >= GAPS_TO_TRUST or sure_of_effects(clock);
    return fill, left, clock.delay, learned and not clock.resync, waiting, tag,
        control or (clock.held_since and clock.held_by);
end

--[[
    The monster attacking `me`, if one did within the last few seconds. It stays on `current` while
    that one keeps attacking you. Otherwise it's the one that attacked most recently. With two
    monsters on you, the bar doesn't flip to whichever one just attacked.
]]
function enemy.attacking(now, me, current)
    local followed = clocks[current];
    if (followed ~= nil and followed.target == me and followed.last_attack ~= nil
        and enemy.active(now, current)) then
        return current;
    end

    local found, latest = nil, -math.huge;
    for id, clock in pairs(clocks) do
        if (clock.target == me and clock.last_attack ~= nil and clock.last_attack > latest and enemy.active(now, id)) then
            found, latest = id, clock.last_attack;
        end
    end
    return found;
end

-- Drops monsters that went quiet. It keeps `keep`, the one the bar follows. That one can sleep for
-- a minute or more. It also keeps any that still have an effect on. Called every few seconds.
function enemy.sweep(now, keep)
    for id, clock in pairs(clocks) do
        expire(clock, now);
        if (id ~= keep and now - clock.seen > FORGET_SECONDS and next(clock.effects) == nil and next(clock.controls) == nil) then
            forget(id);
        end
    end
end

function enemy.reset()
    for id in pairs(clocks) do
        clocks[id] = nil;
    end
    count = 0;
end

local function forget_oldest_speed()
    local oldest_key, oldest_saved = nil, math.huge;
    for key, speed in pairs(speeds) do
        if (speed.saved < oldest_saved) then
            oldest_key, oldest_saved = key, speed.saved;
        end
    end
    speeds[oldest_key] = nil;
    speed_count = speed_count - 1;
end

--[[
    Keeps the monster's delay under its zone and name, once its gaps with no effects on show it. A
    clock doesn't know its monster's name, so cadence.lua passes it in. A monster that only attacked
    with Slow, Elegy, Haste or Hundred Fists on isn't kept.
]]
-- A monster's server id has its zone in bits 12 to 23, so the same name in two zones stays apart.
local function speed_key(id, name)
    return ('%d %s'):format(bit.band(bit.rshift(id, 12), 0xFFF), name);
end

function enemy.remember(id, name)
    local clock = clocks[id];
    if (clock == nil or #clock.base_gaps < GAPS_TO_TRUST) then
        return;
    end
    local key = speed_key(id, name);
    clock.speed_key = key;
    local speed = speeds[key];
    if (speed == nil) then
        speed = {};
        speeds[key] = speed;
        speed_count = speed_count + 1;
    end
    saves = saves + 1;
    speed.delay, speed.saved = learned_delay(clock.base_gaps), saves;
    if (speed_count > MOST_SPEEDS) then
        forget_oldest_speed();
    end
end

--[[
    Starts a monster's delay from the one kept for its name in this zone. It stays a guess, so it
    still says "est." until its own gaps show its delay. Its first gap takes over from the guess.
    When a round already came, its next one was set from the old guess. That one moves too.
]]
function enemy.recall(now, id, name)
    local speed = speeds[speed_key(id, name)];
    if (speed == nil) then
        return;
    end
    local clock = clocks[id] or clock_for(now, id);
    clock.speed_key = speed_key(id, name);
    -- Once it has a gap of its own with no effects on, the guess isn't used.
    if (#clock.base_gaps > 0) then
        return;
    end
    clock.base_guess = speed.delay;
    clock.recalled = true;
    update_delay(clock);
    -- A round with nothing on it set its next one from the plain speed, even when an effect landed after.
    if (clock.clean and clock.round_plain) then
        clock.next_attack = clock.last_attack + speed.delay;
    elseif (clock.clean and clock.round_changes == clock.changes) then
        clock.next_attack = clock.last_attack + clock.delay;
    end
end

-- Keep its current action and effects, but start its measured and remembered speeds again.
function enemy.relearn(id)
    local clock = clocks[id];
    if (clock == nil) then return false; end
    if (clock.speed_key ~= nil and speeds[clock.speed_key] ~= nil) then
        speeds[clock.speed_key] = nil;
        speed_count = speed_count - 1;
    end
    forget_gaps(clock.base_gaps);
    forget_gaps(clock.effect_gaps);
    clock.base_guess, clock.recalled, clock.clean = DEFAULT_DELAY, false, false;
    update_delay(clock);
    return true;
end

function enemy.info(now, id)
    local clock = clocks[id];
    if (clock == nil) then return nil; end
    local _, left, delay, learned, waiting, tag, holding = enemy.progress(now, id);
    local effects = {};
    for effect, on in pairs(clock.effects) do
        effects[#effects + 1] = { id = effect, power = on.power, exact = on.exact,
            uncertain = now > on.sure_until, ends_at = on.ends_at,
            duration_estimate = on.duration_estimate, duration_basis = on.duration_basis,
            duration_uncertain = on.duration_uncertain,
            inputs_known = on.inputs_known, cast_inputs = on.cast_inputs };
    end
    for effect, on in pairs(clock.controls) do
        effects[#effects + 1] = { id = effect, control = on.control, uncertain = true,
            ends_at = on.ends_at, duration_estimate = on.duration_estimate,
            duration_basis = on.duration_basis, inputs_known = on.inputs_known, cast_inputs = on.cast_inputs };
    end
    table.sort(effects, function (a, b) return a.id < b.id; end);
    return { delay = delay, left = left, learned = learned, waiting = waiting, holding = holding,
        source = (#gaps_in_use(clock) >= GAPS_TO_TRUST and 'observed')
            or (sure_of_effects(clock) and 'known effects') or (clock.recalled and 'same name') or 'estimated',
        samples = #gaps_in_use(clock), last_attack = clock.last_attack, last_seen = clock.seen,
        tag = tag, effects = effects, awaiting_attack = clock.resync };
end

-- Another character logged in.
function enemy.forget_speeds()
    for key in pairs(speeds) do
        speeds[key] = nil;
    end
    speed_count = 0;
end

return enemy;
