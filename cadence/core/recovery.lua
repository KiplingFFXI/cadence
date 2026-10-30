-- Recovery estimates use confirmed actions and the server's matching action data.
local recovery = {};
local source = require('data.phoenix_recovery');

local SPELL_SECONDS = 2.5;
local RANGED_SECONDS = 0.8;
local UNKNOWN_NOTICE_SECONDS = 5;
local EVENT_KEYS_KEPT = 8;
local CAST_BEGIN = 0x6163;
local START_KIND = { [8] = 'spell', [9] = 'item', [12] = 'ranged' };
local ABILITY_CATEGORY = { [6] = true, [14] = true, [15] = true };

local state = { started = nil, deadline = nil, duration = nil, kind = nil, known = nil, notice_until = nil };
local view = { estimated = true };
local event_keys = {};
local key_count, next_key = 0, 1;

local function finite(now)
    return type(now) == 'number' and now == now and now >= 0 and now < math.huge;
end

local function clear_timer()
    state.started, state.deadline, state.duration, state.kind = nil, nil, nil, nil;
    state.known, state.notice_until = nil, nil;
end

function recovery.reset()
    clear_timer();
    for i = 1, key_count do event_keys[i] = nil; end
    key_count, next_key = 0, 1;
end

local function repeated_event(event_key)
    if (type(event_key) ~= 'string' or event_key == '') then return false; end
    for i = 1, key_count do
        if (event_keys[i] == event_key) then return true; end
    end
    -- A late repeated packet must not restart or clear recovery.
    event_keys[next_key] = event_key;
    key_count = math.min(key_count + 1, EVENT_KEYS_KEPT);
    next_key = next_key % EVENT_KEYS_KEPT + 1;
    return false;
end

local function accept_event(now, event_key)
    if (not finite(now) or (state.started ~= nil and now < state.started)) then
        return false;
    end
    local expires = state.deadline or state.notice_until;
    if (expires ~= nil and now >= expires) then
        clear_timer();
    end
    return not repeated_event(event_key);
end

local function begin(now, seconds, kind, event_key)
    if (not accept_event(now, event_key)) then return false; end
    local deadline = now + seconds;
    if (state.deadline ~= nil and state.deadline >= deadline) then
        return true;
    end
    state.started, state.deadline, state.duration, state.kind = now, deadline, seconds, kind;
    state.known, state.notice_until = true, nil;
    return true;
end

local function unknown(now, kind, event_key)
    if (not accept_event(now, event_key)) then return false; end
    clear_timer();
    state.started, state.kind, state.known = now, kind, false;
    -- This only limits how long the notice stays visible. It is not a recovery duration.
    state.notice_until = now + UNKNOWN_NOTICE_SECONDS;
    return true;
end

-- Category 3 contains both weapon skills and job abilities, with overlapping ids.
function recovery.classify(category, param, animation, message)
    if (message == 84 or message == 106 or not finite(param) or param % 1 ~= 0) then
        return nil, nil, 'ignored';
    end
    if (START_KIND[category] ~= nil) then
        if (param == CAST_BEGIN) then return START_KIND[category], 0, 'accepted'; end
        return nil, nil, 'ignored';
    end
    if (category == 2) then return 'ranged', RANGED_SECONDS, 'timed'; end
    if (param == 0) then return nil, nil, 'ignored'; end
    if (category == 4) then
        local seconds = source.spell_attack_seconds[param];
        if (not finite(seconds)) then return 'spell', nil, 'unknown'; end
        return 'spell', math.max(SPELL_SECONDS, seconds), 'timed';
    end
    if (category == 5) then
        local seconds = source.items[param];
        if (seconds == nil) then return 'item', nil, 'unknown'; end
        return 'item', seconds, seconds > 0 and 'timed' or 'none';
    end
    if (category == 3 or ABILITY_CATEGORY[category]) then
        local ability = source.abilities[param];
        local is_ability = ability ~= nil and ability.category == category and ability.animations[animation] == true;
        local skill = category == 3 and source.weaponskills[param] or nil;
        local is_skill = skill ~= nil and skill[animation] == true;
        if (is_ability and is_skill) then return 'unknown', nil, 'unknown'; end
        if (is_skill) then
            local seconds = source.weaponskill_seconds and source.weaponskill_seconds[param];
            if (not finite(seconds)) then return 'weaponskill', nil, 'unknown'; end
            return 'weaponskill', seconds, seconds > 0 and 'timed' or 'none';
        end
        if (is_ability) then
            return ability.kind, ability.seconds, ability.seconds > 0 and 'timed' or 'none';
        end
        return category == 3 and 'unknown' or 'ability', nil, 'unknown';
    end
    return nil, nil, 'ignored';
end

function recovery.on_action(now, category, param, animation, event_key, message)
    local kind, seconds, status = recovery.classify(category, param, animation, message);
    local accepted = false;
    if (status == 'timed') then
        accepted = begin(now, seconds, kind, event_key);
    elseif (status == 'unknown') then
        accepted = unknown(now, kind, event_key);
    elseif (status == 'accepted' or status == 'none') then
        accepted = recovery.on_cast_begin(now, event_key);
    end
    if (not accepted) then return kind, seconds, 'ignored'; end
    return kind, seconds, status;
end

function recovery.on_spell(now, spell_id, event_key)
    return recovery.on_action(now, 4, spell_id, nil, event_key);
end

function recovery.on_weaponskill(now, skill_id, event_key)
    local seconds = source.weaponskill_seconds and source.weaponskill_seconds[skill_id];
    if (not finite(seconds)) then
        return unknown(now, 'weaponskill', event_key);
    elseif (seconds == 0) then
        return recovery.on_cast_begin(now, event_key);
    end
    return begin(now, seconds, 'weaponskill', event_key);
end

-- An accepted new action ends the previous recovery estimate or unknown notice.
function recovery.on_cast_begin(now, event_key)
    if (not accept_event(now, event_key)) then return false; end
    clear_timer();
    return true;
end

function recovery.progress(now)
    if (state.started == nil or not finite(now)) then
        return nil;
    end
    if (now < state.started) then
        recovery.reset();
        return nil;
    end
    if (now >= (state.deadline or state.notice_until)) then
        clear_timer();
        return nil;
    end
    view.left = state.known and state.deadline - now or nil;
    view.duration, view.kind = state.duration, state.kind;
    view.fill = state.known and 1 - view.left / state.duration or 0;
    view.estimated, view.known = true, state.known;
    return view;
end

return recovery;
