-- Spell starts name the cast, but do not contain its modified server duration.
local enemy_cast = {};
local MAX_CASTS, MAX_KEYS = 64, 64;
local casts, event_keys, view = {}, {}, {};
local count, key_count, next_key = 0, 0, 1;

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge;
end

function enemy_cast.forget(actor)
    if (casts[actor] ~= nil) then casts[actor], count = nil, count - 1; end
end

function enemy_cast.reset()
    for actor in pairs(casts) do casts[actor] = nil; end
    for i = 1, key_count do event_keys[i] = nil; end
    count, key_count, next_key = 0, 0, 1;
end

local function repeated(key)
    if (type(key) ~= 'string' or key == '') then return false; end
    for i = 1, key_count do if (event_keys[i] == key) then return true; end end
    event_keys[next_key] = key;
    key_count, next_key = math.min(key_count + 1, MAX_KEYS), next_key % MAX_KEYS + 1;
    return false;
end

function enemy_cast.on_start(now, actor, spell_id, name, duration, event_key)
    if (not finite(now) or not finite(actor) or actor <= 0 or actor % 1 ~= 0
        or not finite(spell_id) or spell_id < 1 or spell_id > 65535 or spell_id % 1 ~= 0) then return false; end
    local cast = casts[actor];
    if ((cast and now < cast.started) or repeated(event_key)) then return false; end
    if (not finite(duration) or duration <= 0 or duration > 120) then duration = nil; end
    if (type(name) ~= 'string' or name == '') then name = 'Spell ' .. spell_id; end
    name = name:gsub('[%c]', ' '):sub(1, 80);
    if (cast == nil) then
        if (count >= MAX_CASTS) then
            local oldest, started = nil, math.huge;
            for id, entry in pairs(casts) do
                if (entry.started < started) then oldest, started = id, entry.started; end
            end
            enemy_cast.forget(oldest);
        end
        cast = {};
        casts[actor], count = cast, count + 1;
    end
    cast.started, cast.spell_id, cast.spell, cast.duration = now, spell_id, name, duration;
    -- A missed finish cannot leave an old incarnation casting indefinitely.
    cast.stale_at = now + math.min(120, math.max(30, (duration or 0) + 15));
    return true;
end

-- An identified finish cannot end a newer, different spell. Interrupts can omit the spell id.
function enemy_cast.on_end(actor, spell_id, event_key)
    if (repeated(event_key)) then return false; end
    local cast = casts[actor];
    if (cast == nil or (spell_id ~= nil and spell_id ~= cast.spell_id)) then return false; end
    enemy_cast.forget(actor);
    return true;
end

function enemy_cast.progress(now, actor, out)
    local cast = casts[actor];
    if (cast == nil or not finite(now)) then return false; end
    if (now < cast.started or now >= cast.stale_at) then enemy_cast.forget(actor); return false; end
    out = out or view;
    local elapsed = now - cast.started;
    local left = cast.duration and math.max(0, cast.duration - elapsed) or nil;
    out.spell_id, out.spell, out.duration = cast.spell_id, cast.spell, cast.duration;
    out.elapsed, out.left, out.estimated = elapsed, left, true;
    out.waiting = left == nil or left <= 0;
    out.fill = cast.duration and math.min(1, elapsed / cast.duration) or 0;
    out.preview = false;
    return true;
end

function enemy_cast.sweep(now)
    if (not finite(now)) then return; end
    for actor, cast in pairs(casts) do
        if (now < cast.started or now >= cast.stale_at) then enemy_cast.forget(actor); end
    end
end

return enemy_cast;
