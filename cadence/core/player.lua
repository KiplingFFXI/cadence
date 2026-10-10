--[[
    Everything cadence reads from game memory, about you and the monsters around you.
]]

local player = {};

local SLOT_MAIN = 0;
local SLOT_SUB  = 1;
local ITEM_NONE = { [0] = true, [65535] = true };

-- The status the server gives you during a cutscene or NPC conversation.
local STATUS_EVENT = 4;

-- Spawn flag the client sets on monsters.
local SPAWN_FLAG_MONSTER = 0x10;

--[[
    How the client's positions turn into the server's. These come from Ashita's headers and other
    addons. If "too far" or "not facing" shows at the wrong times, these two are the first place to
    look. Ashita keeps height in Z, where the server keeps it in y. Headings are in radians. Ashita
    keeps a hitbox in yalms, the server's byte times 0.1.
]]
local HEADING_SIGN = 1;   -- -1 turns the heading the other way round.
local HITBOX_SCALE = 1;   -- 0.1 reads a hitbox kept as the server's byte.

local memory    = AshitaCore:GetMemoryManager();
local resources = AshitaCore:GetResourceManager();
local entities  = memory:GetEntity();
local targets   = memory:GetTarget();
local party     = memory:GetParty();
local stats     = memory:GetPlayer();
local inventory = memory:GetInventory();

--[[
    The game's own "event running" flag, the same one XIUI's "Hide During Events" reads. The game sets
    it the moment a cutscene or NPC conversation starts and clears it when the event ends. The pattern
    finds the game code that checks the flag. The flag's address is the four bytes after that code's
    first byte. It's looked up once since the flag never moves.
]]
local EVENT_CHECK = 'A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3';
local event_check = ashita.memory.find('FFXiMain.dll', 0, EVENT_CHECK, 0, 0);
local event_flag = (event_check ~= 0) and ashita.memory.read_uint32(event_check + 1) or 0;

--[[
    The game's interface object, found the same way XIUI finds it. The byte at +0xB4 is 1 while you
    hide the interface (Scroll Lock by default). The slot at +0x54 holds the menu that has focus.
    Each menu's name is "menu    " plus an eight letter short name. Every map view's short name starts
    with "map", like map0, mapv2 and mapframe. Both addresses are looked up once since the object
    never moves. The map check needs both patterns. If the focus slot isn't inside the interface
    object, a game update moved something and both checks stay off.
]]
local INTERFACE_CHECK = '8B4424046A016A0050B9????????E8????????F6D81BC040C3';
local MENU_CHECK      = '8B480C85C974??8B510885D274??3B05';
local HIDDEN_OFFSET   = 0xB4;
local FOCUS_OFFSET    = 0x54;
local SHORT_NAME      = 0x46 + 8;
local MAP_NAME        = 0x0070616D;   -- 'map' as the low three bytes of a little-endian word.

local interface_check = ashita.memory.find('FFXiMain.dll', 0, INTERFACE_CHECK, 0, 0);
local menu_check      = ashita.memory.find('FFXiMain.dll', 0, MENU_CHECK, 16, 0);
local interface  = (interface_check ~= 0) and ashita.memory.read_uint32(interface_check + 10) or 0;
local focus_slot = (menu_check ~= 0) and ashita.memory.read_uint32(menu_check) or 0;
if (focus_slot ~= 0 and focus_slot ~= interface + FOCUS_OFFSET) then
    interface, focus_slot = 0, 0;
end
local hidden_flag = (interface ~= 0) and (interface + HIDDEN_OFFSET) or 0;

-- Your entity, or nil while zoning.
function player.entity()
    return GetPlayerEntity();
end

-- True during a cutscene or NPC conversation. If a game update breaks the pattern, this falls back
-- to your event status. The server sends that a moment later.
function player.in_event(entity)
    if (event_flag ~= 0) then
        return ashita.memory.read_uint8(event_flag) == 1;
    end
    return entity.StatusServer == STATUS_EVENT;
end

-- True while you've hidden the game's interface. False when this game version can't be checked.
function player.interface_hidden()
    return hidden_flag ~= 0 and ashita.memory.read_uint8(hidden_flag) == 1;
end

-- True while a map view has focus. False when this game version can't be checked.
function player.map_open()
    if (focus_slot == 0) then
        return false;
    end
    local menu = ashita.memory.read_uint32(focus_slot);
    if (menu == 0) then
        return false;
    end
    local header = ashita.memory.read_uint32(menu + 4);
    if (header == 0) then
        return false;
    end
    return bit.band(ashita.memory.read_uint32(header + SHORT_NAME), 0xFFFFFF) == MAP_NAME;
end

-- Whether this game version lets cadence see the hidden interface and the map.
function player.can_check_interface()
    return hidden_flag ~= 0;
end

function player.can_check_map()
    return focus_slot ~= 0;
end

function player.server_id()
    return party:GetMemberServerId(0);
end

-- Your own entity index.
function player.my_index()
    return party:GetMemberTargetIndex(0);
end

-- Your TP, 0 to 3000.
function player.tp()
    return party:GetMemberTP(0);
end

-- The entity index of your target, or nil. While you pick a target for a spell or ability, it's
-- still the target you had before you started picking.
function player.target_index()
    local index = targets:GetTargetIndex(0);
    if (targets:GetIsSubTargetActive() == 1) then
        local held = targets:GetTargetIndex(1);
        if (held ~= 0) then
            index = held;
        end
    end
    return (index ~= 0) and index or nil;
end

-- The server id of the monster at entity `index`, or nil when there's no monster there.
function player.monster_id(index)
    if (bit.band(entities:GetSpawnFlags(index), SPAWN_FLAG_MONSTER) == 0) then
        return nil;
    end
    local id = entities:GetServerId(index);
    return (id ~= 0) and id or nil;
end

-- The status of the entity at `index`, like 1 for engaged.
function player.entity_status(index)
    return entities:GetStatus(index);
end

function player.entity_name(index)
    return entities:GetName(index);
end

--[[
    Fills `out` with where the entity at `index` stands, on the server's axes, and returns it. x and z
    run across the ground and y is height. `heading` is the way it faces, 0 east and turning clockwise
    like the server's rotation. `hitbox` is its size in yalms.
]]
function player.body(index, out)
    out.x = entities:GetLocalPositionX(index);
    out.y = entities:GetLocalPositionZ(index);
    out.z = entities:GetLocalPositionY(index);
    out.heading = entities:GetLocalPositionYaw(index) * HEADING_SIGN;
    out.hitbox = entities:GetModelHitboxSize(index) * HITBOX_SCALE;
    return out;
end

-- Your main job's id, like 4 for BLM, or 0 while the game doesn't know it yet.
function player.main_job()
    return stats:GetMainJob();
end

-- Your max HP and MP.
function player.max_vitals()
    return stats:GetHPMax(), stats:GetMPMax();
end

--[[
    Fills `out` with your buffs as { [buff id] = true } and returns it. Old entries are cleared first,
    so one table can be reused. The second return value says whether the client had a buff list.
]]
function player.read_buffs(out)
    local buffs = stats:GetBuffs();
    if (buffs == nil) then
        return out, false, nil;
    end
    for id in pairs(out) do
        out[id] = nil;
    end

    local counts = {};
    -- Slots 0 to 32 cover the buff list whether it starts at 0 or at 1.
    for i = 0, 32 do
        local id = buffs[i];
        if (id ~= nil and id > 0 and id ~= 255) then
            out[id] = true;
            counts[id] = (counts[id] or 0) + 1;
        end
    end
    return out, true, counts;
end

-- Weapon info for the delay estimate, and whether the slot is occupied. A shield has no delay.
local function weapon_in(slot)
    local equipped = inventory:GetEquippedItem(slot);
    if (equipped == nil or equipped.Index == 0) then
        return nil, false;
    end

    local item = inventory:GetContainerItem(bit.rshift(equipped.Index, 8), bit.band(equipped.Index, 0xFF));
    if (item == nil or ITEM_NONE[item.Id]) then
        return nil, true;
    end

    local info = resources:GetItemById(item.Id);
    if (info == nil or info.Delay == nil or info.Delay == 0) then
        return nil, true;
    end
    return { id = item.Id, delay = info.Delay, skill = info.Skill }, true;
end

-- Reads what decides your attack delay. See delay.estimate() for the shape.
function player.read_loadout()
    local buffs, known, counts = player.read_buffs({});
    local main = weapon_in(SLOT_MAIN);
    local sub, sub_used = weapon_in(SLOT_SUB);
    return {
        main       = main,
        sub        = sub,
        sub_used   = sub_used,
        main_job   = stats:GetMainJob(),
        main_level = stats:GetMainJobLevel(),
        sub_job    = stats:GetSubJob(),
        sub_level  = stats:GetSubJobLevel(),
        buffs      = buffs,
        buffs_known = known,
        buff_counts = counts,
    };
end

return player;
