--[[
    Reads the few incoming packet fields cadence needs.

    Offsets come from the LandSandBoat server source in src/map/packets. Phoenix runs these packets
    unchanged.
]]

local packets = {};

packets.ID = {
    ZONE_IN = 0x00A,
    ACTION  = 0x028,
    MESSAGE = 0x029,
    ASSIST  = 0x058,
    VITALS  = 0x0DF,
};

-- Action categories (0x028). Only the ones cadence reacts to.
packets.CATEGORY = {
    MELEE           = 1,
    RANGED_FINISH   = 2,
    WEAPONSKILL     = 3,
    SPELL_FINISH    = 4,
    ITEM_FINISH     = 5,
    ABILITY         = 6,
    MOBSKILL_START  = 7,
    SPELL_START     = 8,
    ITEM_START      = 9,
    MOBSKILL_FINISH = 11,
    RANGED_START    = 12,
};

-- Start and interrupt packets for TP moves, spells, items and ranged attacks share a category.
-- The low 16 bits of the action id tell them apart. "ca" is a start and "sp" is an interrupt.
packets.CAST_BEGIN     = 0x6163;
packets.CAST_INTERRUPT = 0x7073;

-- Bit positions in the 0x028 header.
local ACTOR_BIT        = 40;
local TARGET_COUNT_BIT = 72;
local CATEGORY_BIT     = 82;
local PARAM_BIT        = 86;
local TARGET_BIT       = 150;
local RESULT_COUNT_BIT = 182;
local FIRST_RESULT_BIT = 186;

-- Each result is 85 bits. A 1-bit flag follows, then a 37-bit add-effect block when it is set.
-- Another 1-bit flag follows, then a 34-bit reaction block when it is set.
local RESULT_MESSAGE_OFFSET = 44;
local RESULT_BASE_BITS      = 85;
local ADD_EFFECT_BITS       = 37;
local REACTION_BITS         = 34;
local MAX_RESULTS           = 8;
local MAX_TARGETS           = 16;

-- A result starts with 3 bits for how the attack landed. Its damage is 17 bits, 27 bits in.
local RESULT_DAMAGE_OFFSET = 27;
local PLAIN_HIT = 0;
local LANDED = { [0] = true, [2] = true, [4] = true };   -- A hit, a guarded hit or a blocked hit.

-- Result messages for a melee hit and a critical hit.
local HIT_MESSAGES = { [1] = true, [67] = true };

-- The reaction block starts with 6 bits for its kind. 63 is a counter. Spikes are reactions too.
local REACTION_KIND_BITS = 6;
local COUNTER            = 63;

-- A target is its 32-bit id and a 4-bit result count, then its results.
local TARGET_BITS = 36;

local unpack_bits = ashita.bits.unpack_be;

--[[
    Steps past the result that starts at `offset`, along with its add-effect and reaction blocks.
    Returns where the next result starts and where this one's reaction block starts, if it has one.
    Returns nil when the packet ends before the reaction flag.
]]
local function next_result(data, offset, total_bits)
    offset = offset + RESULT_BASE_BITS;
    if (unpack_bits(data, 0, offset, 1) == 1) then
        offset = offset + ADD_EFFECT_BITS;
    end
    offset = offset + 1;

    if (offset + 1 > total_bits) then
        return nil;
    end
    if (unpack_bits(data, 0, offset, 1) == 1) then
        return offset + 1 + REACTION_BITS, offset + 1;
    end
    return offset + 1, nil;
end

-- Reads who acted and what kind of action it was.
function packets.action_header(e)
    local actor    = unpack_bits(e.data_raw, 0, ACTOR_BIT, 32);
    local category = unpack_bits(e.data_raw, 0, CATEGORY_BIT, 4);
    return actor, category;
end

-- The low 16 bits of the action id. That is the spell id on a spell finish, or CAST_BEGIN or
-- CAST_INTERRUPT on a start.
function packets.action_param(e)
    return unpack_bits(e.data_raw, 0, PARAM_BIT, 16);
end

-- The server id of the first target. On an attack round that's who got attacked.
function packets.action_target(e)
    return unpack_bits(e.data_raw, 0, TARGET_BIT, 32);
end

-- Fills `out` with the message id of every result on the first target and returns the count.
function packets.action_messages(e, out)
    local data = e.data_raw;
    local total_bits = e.size * 8;
    local count = math.min(unpack_bits(data, 0, RESULT_COUNT_BIT, 4), MAX_RESULTS);

    local offset = FIRST_RESULT_BIT;
    for i = 1, count do
        -- A short packet ends the loop before it reads past the end.
        if (offset + RESULT_BASE_BITS + 1 > total_bits) then
            return i - 1;
        end
        out[i] = unpack_bits(data, 0, offset + RESULT_MESSAGE_OFFSET, 10);
        offset = next_result(data, offset, total_bits);
        if (offset == nil) then
            return i;
        end
    end
    return count;
end

--[[
    How many attacks in your round gave you TP. Hits, criticals, and guarded or blocked hits give it
    when they did damage. Misses, parries, shadows and hits that did nothing don't. The second value
    is true when the target countered inside the round. That gives you TP too. The third is true
    when the first attack was a plain hit.
]]
function packets.melee_hits(e)
    local data = e.data_raw;
    local total_bits = e.size * 8;
    local count = math.min(unpack_bits(data, 0, RESULT_COUNT_BIT, 4), MAX_RESULTS);
    local hits, hit_back = 0, false;
    local clean_start = count > 0 and unpack_bits(data, 0, FIRST_RESULT_BIT, 3) == PLAIN_HIT;

    local offset = FIRST_RESULT_BIT;
    for _ = 1, count do
        if (offset + RESULT_BASE_BITS + 1 > total_bits) then
            break;
        end
        local landed  = LANDED[unpack_bits(data, 0, offset, 3)];
        local damage  = unpack_bits(data, 0, offset + RESULT_DAMAGE_OFFSET, 17);
        local message = unpack_bits(data, 0, offset + RESULT_MESSAGE_OFFSET, 10);
        if (landed and damage > 0 and HIT_MESSAGES[message]) then
            hits = hits + 1;
        end

        local reaction;
        offset, reaction = next_result(data, offset, total_bits);
        if (reaction ~= nil and unpack_bits(data, 0, reaction, REACTION_KIND_BITS) == COUNTER) then
            hit_back = true;
        end
        if (offset == nil) then
            break;
        end
    end
    return hits, hit_back, clean_start;
end

--[[
    Fills `out` with every result on every target, as { target, message, param }, and returns how
    many. The rows are reused, so read them before the next packet. For a spell that lands, `param`
    is the effect it put on.
]]
function packets.action_results(e, out)
    local data = e.data_raw;
    local total_bits = e.size * 8;
    local targets = math.min(unpack_bits(data, 0, TARGET_COUNT_BIT, 6), MAX_TARGETS);
    local n = 0;

    local offset = TARGET_BIT;
    for _ = 1, targets do
        if (offset + TARGET_BITS > total_bits) then
            return n;
        end
        local target = unpack_bits(data, 0, offset, 32);
        local results = math.min(unpack_bits(data, 0, offset + 32, 4), MAX_RESULTS);
        offset = offset + TARGET_BITS;

        for _ = 1, results do
            if (offset + RESULT_BASE_BITS + 1 > total_bits) then
                return n;
            end
            n = n + 1;
            local row = out[n] or {};
            out[n] = row;
            row.target  = target;
            row.message = unpack_bits(data, 0, offset + RESULT_MESSAGE_OFFSET, 10);
            row.param   = unpack_bits(data, 0, offset + RESULT_DAMAGE_OFFSET, 17);
            offset = next_result(data, offset, total_bits);
            if (offset == nil) then
                return n;
            end
        end
    end
    return n;
end

-- True when `id` is one of the action's targets. Every target is checked, since a monster's area TP
-- move lists the whole party.
function packets.action_has_target(e, id)
    local data = e.data_raw;
    local total_bits = e.size * 8;
    local targets = math.min(unpack_bits(data, 0, TARGET_COUNT_BIT, 6), MAX_TARGETS);

    local offset = TARGET_BIT;
    for _ = 1, targets do
        if (offset + TARGET_BITS > total_bits) then
            return false;
        end
        if (unpack_bits(data, 0, offset, 32) == id) then
            return true;
        end
        local results = unpack_bits(data, 0, offset + 32, 4);
        offset = offset + TARGET_BITS;

        for _ = 1, results do
            if (offset + RESULT_BASE_BITS + 1 > total_bits) then
                return false;
            end
            offset = next_result(data, offset, total_bits);
            if (offset == nil) then
                return false;
            end
        end
    end
    return false;
end

-- 0x029 battle message. Returns who it's from, the message id, who it's about and its first number.
-- On a wear-off that number is the effect id.
function packets.message(e)
    local data = e.data;
    local actor   = struct.unpack('L', data, 0x04 + 1);
    local target  = struct.unpack('L', data, 0x08 + 1);
    local param   = struct.unpack('L', data, 0x0C + 1);
    local message = struct.unpack('H', data, 0x18 + 1);
    return actor, message, target, param;
end

-- 0x0DF party member vitals. The server sends one for each party member every time their HP, MP or TP
-- changes. This returns whose it is, so the other fields are only read when it's yours.
function packets.vitals_member(e)
    return struct.unpack('L', e.data, 0x04 + 1);
end

-- The HP, MP and TP in a 0x0DF.
function packets.vitals(e)
    local data = e.data;
    local hp = struct.unpack('L', data, 0x08 + 1);
    local mp = struct.unpack('L', data, 0x0C + 1);
    local tp = struct.unpack('L', data, 0x10 + 1);
    return hp, mp, tp;
end

-- 0x058 assist. Returns whose it is and the server id of the monster they're on. The server sends it
-- when your attacks move to another monster, and as the answer to /assist.
function packets.assist(e)
    return struct.unpack('L', e.data, 0x04 + 1), struct.unpack('L', e.data, 0x08 + 1);
end

-- 0x00A zone in. Returns your server id.
function packets.zone_in(e)
    return struct.unpack('L', e.data, 0x04 + 1);
end

return packets;
