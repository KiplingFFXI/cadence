--[[
    Works out whether you can attack your target from where you stand. It checks the same way the
    server does before each attack, in LSB CCharEntity::CanAttack. Facing comes first, then range.

    You face your target while it's less than 45 degrees to either side of the way you face. That's 32
    of the server's 256 rotation steps. Only the ground counts for facing. Standing right on top of it
    counts as facing it. Your reach is 2 yalms plus both hitboxes. It's measured straight through,
    height included.

    Positions are on the server's axes, x and z across the ground and y for height. Headings are in
    radians, 0 east and turning clockwise like the server's rotation.

    The client sees positions a moment before or after the server does. Each check turns on past the
    server's edge. It only turns off once you're back inside it by a margin. Standing on the edge
    doesn't flicker.
]]

local reach = {};

-- The server's rules.
local MELEE_REACH  = 2.0;           -- Yalms on top of both hitboxes.
local FACING_LIMIT = math.pi / 4;   -- To either side of the way you face.
local ON_TOP       = 0.1;           -- Yalms across the ground.

-- How far back inside an edge you need to be before its word goes away.
local RANGE_MARGIN  = 0.2;          -- Yalms.
local FACING_MARGIN = math.rad(5);

-- The 0x029 messages the server sends for each.
local NOT_FACING = 5;
local TOO_FAR    = 4;

local state = {
    target     = nil,     -- The server id of the target being checked.
    too_far    = false,
    not_facing = false,
};

-- How far your target sits to one side of the way you face, from 0 to pi.
local function angle_off(me, target)
    local dx, dz = target.x - me.x, target.z - me.z;
    if (dx * dx + dz * dz <= ON_TOP * ON_TOP) then
        return 0;
    end
    local off = (-math.atan2(dz, dx) - me.heading) % (2 * math.pi);
    return math.min(off, 2 * math.pi - off);
end

local function distance(me, target)
    local dx, dy, dz = target.x - me.x, target.y - me.y, target.z - me.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
end

-- True past `edge`. Once it's past, it stays true until `value` is back inside by `margin`.
local function past(was_past, value, edge, margin)
    if (was_past) then
        return value > edge - margin;
    end
    return value > edge;
end

--[[
    Returns the message the server would send if your attack were due now. That's 5 when you aren't
    facing your target, 4 when it's too far away, or nil when you can attack. `target_id` is its server
    id. A new one starts the checks over. `me` and `target` are { x, y, z, heading, hitbox } from
    player.body().
]]
function reach.check(target_id, me, target)
    if (target_id ~= state.target) then
        reach.forget();
        state.target = target_id;
    end
    state.not_facing = past(state.not_facing, angle_off(me, target), FACING_LIMIT, FACING_MARGIN);
    state.too_far = past(state.too_far, distance(me, target), me.hitbox + MELEE_REACH + target.hitbox,
        RANGE_MARGIN);

    if (state.not_facing) then
        return NOT_FACING;
    end
    return state.too_far and TOO_FAR or nil;
end

-- Starts the checks over, for a new fight or while nothing is checked.
function reach.forget()
    state.target, state.too_far, state.not_facing = nil, false, false;
end

return reach;
