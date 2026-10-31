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
local MENU_PREFIX     = 0x756E656D;   -- 'menu'.
local NAME_SPACES     = 0x20202020;

local interface_check = ashita.memory.find('FFXiMain.dll', 0, INTERFACE_CHECK, 0, 0);
local menu_check      = ashita.memory.find('FFXiMain.dll', 0, MENU_CHECK, 16, 0);
local interface  = (interface_check ~= 0) and ashita.memory.read_uint32(interface_check + 10) or 0;
local focus_slot = (menu_check ~= 0) and ashita.memory.read_uint32(menu_check) or 0;
if (focus_slot ~= 0 and focus_slot ~= interface + FOCUS_OFFSET) then
    interface, focus_slot = 0, 0;
end
local hidden_flag = (interface ~= 0) and (interface + HIDDEN_OFFSET) or 0;

-- Typing, the combat command panel and native macro palettes leave the timers visible.
-- Spell and ability lists are ordinary menus.
local INPUT_MENUS = { inline = true, chatctrl = true, playermo = true,
    mcr1pall = true, mcr2pall = true, mcr1long = true, mcr2long = true };
local last_name_low, last_name_high, last_chat, last_menu;

local function pointer(value, extra)
    return type(value) == 'number' and value >= 0x10000 and value <= 0xFFFFFFFF - (extra or 0)
        and value == math.floor(value);
end

-- The eight-byte name can end in spaces or zeroes. Decode it only when it changes.
local function classify_menu(low, high)
    if (low == last_name_low and high == last_name_high) then return last_chat, last_menu; end
    last_name_low, last_name_high, last_chat, last_menu = low, high, false, false;
    local name = '';
    for i = 0, 7 do
        local word = i < 4 and low or high;
        local byte = math.floor(word / 256 ^ (i % 4)) % 256;
        if (byte == 0) then break; end
        if (byte < 32 or byte > 126) then return false, false; end
        name = name .. string.char(byte);
    end
    name = name:gsub(' +$', '');
    last_chat = name == 'fulllog';
    last_menu = name ~= '' and not last_chat and not INPUT_MENUS[name];
    return last_chat, last_menu;
end

local function read_menu_visibility(want_chat, want_menus, want_map)
    local menu = ashita.memory.read_uint32(focus_slot);
    if (not pointer(menu, 4)) then return false, false, false; end
    local header = ashita.memory.read_uint32(menu + 4);
    if (not pointer(header, SHORT_NAME + 7)) then return false, false, false; end
    local low = ashita.memory.read_uint32(header + SHORT_NAME);
    if (type(low) ~= 'number' or low < 0 or low > 0xFFFFFFFF or low ~= math.floor(low)) then return false, false, false; end
    local map = bit.band(low, 0xFFFFFF) == MAP_NAME;
    if (map or not (want_chat or want_menus)) then return false, false, want_map and map; end
    if (ashita.memory.read_uint32(header + 0x46) ~= MENU_PREFIX
        or ashita.memory.read_uint32(header + 0x4A) ~= NAME_SPACES) then return false, false, false; end
    local high = ashita.memory.read_uint32(header + SHORT_NAME + 4);
    if (type(high) ~= 'number' or high < 0 or high > 0xFFFFFFFF or high ~= math.floor(high)) then return false, false, false; end
    local chat, other = classify_menu(low, high);
    return want_chat and chat, want_menus and other, false;
end

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
    local _, _, map = player.menu_visibility(false, false, true);
    return map;
end

-- One focus read separates the full-screen log, other menus and maps. Missing reads leave timers up.
-- The native full-screen log's short name is fulllog; opening the chat input is not the same thing.
function player.menu_visibility(want_chat, want_menus, want_map)
    want_chat, want_menus, want_map = want_chat ~= false, want_menus ~= false, want_map ~= false;
    if (focus_slot == 0 or not (want_chat or want_menus or want_map)) then return false, false, false; end
    local ok, chat, other, map = pcall(read_menu_visibility, want_chat, want_menus, want_map);
    if (not ok) then return false, false, false; end
    return chat, other, map;
end

-- Whether this game version lets cadence see the hidden interface and the map.
function player.can_check_interface()
    return hidden_flag ~= 0;
end

function player.can_check_map()
    return focus_slot ~= 0;
end

function player.can_check_chat()
    return focus_slot ~= 0;
end

function player.can_check_menus()
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

-- Exact status packets are not sent for every cap change. Current HP/MP and their server percentages
-- can disprove an old cap, including after Weakness ends while native memory still has the old value.
local hp_cap, mp_cap = {}, {};
local function valid_cap(value, zero)
    return type(value) == 'number' and value == math.floor(value) and value >= (zero and 0 or 1) and value <= 0x7FFFFFFF;
end

local function coherent_cap(record, cap)
    local value, percent = record.current, record.percent;
    if (record.last_current ~= nil and cap < record.last_current) then return false; end
    if (value == nil or percent == nil or percent == 0) then return true; end
    if (cap < value or cap <= 0) then return false; end
    if (cap == value) then return percent == 100; end
    if (percent == 100) then return cap == value; end
    local ratio = value * 100 / cap;
    -- The server calculates this percentage with float precision. Allow rounding at an integer edge.
    return percent == math.max(1, math.floor(ratio + 0.00001))
        or percent == math.max(1, math.floor(ratio - 0.00001));
end

local function observe_vital(record, value, percent)
    if (not valid_cap(value, true)) then return; end
    record.last_current = value;
    if (record.value ~= nil and record.value < value) then record.value = nil; end
    if (record.native ~= nil and record.native < value) then record.rejected_native = record.native; end
    if (not valid_cap(percent, true) or percent > 100
        or (percent == 0 and value > 0) or (percent > 0 and value == 0)) then return; end
    record.current, record.percent, record.pinned = value, percent, false;
    if (record.native ~= nil and not coherent_cap(record, record.native)) then record.rejected_native = record.native; end
    if (record.value ~= nil and not coherent_cap(record, record.value)) then record.value = nil; end
    if (percent == 100) then
        record.value, record.quality = value, false;
    elseif (record.value == nil and percent > 0) then
        if (percent == 1) then
            -- One percent also represents values below one percent, so it supplies no upper bound.
            record.value, record.quality = math.floor(value * 100 / 2) + 1, 'unknown';
        else
            record.value, record.quality = math.floor(value * 100 / percent), true;
        end
    elseif (record.quality == 'unknown' and percent > 1) then
        record.quality = true;
    end
end

local function read_cap(record, native, zero)
    local previous = record.native;
    local changed = native ~= previous;
    record.native = native;
    if (not record.pinned and changed and valid_cap(previous, zero) and valid_cap(native, zero)
        and (record.percent == nil or record.percent == 0)) then
        -- A new native cap can clamp current vitals before their next packet. Without a percentage
        -- snapshot to contradict it, old current values cannot keep that new cap from taking effect.
        record.current, record.percent, record.last_current, record.rejected_native = nil, nil, nil, nil;
        record.value, record.quality = native, false;
    elseif (not record.pinned and (changed or record.value == nil) and valid_cap(native, zero)
        and native ~= record.rejected_native and coherent_cap(record, native)) then
        record.value, record.quality = native, false;
    end
    if (record.value == nil) then return math.max(1, (record.last_current or 0) + 1), 'unknown'; end
    return record.value, record.quality;
end

-- Quality is false for a current exact source, true for an estimate, or 'unknown' for an open bound.
-- Keep a still-consistent estimate stable so ordinary recovery ticks do not restart potency learning.
function player.max_vitals()
    local hp, hp_quality = read_cap(hp_cap, stats:GetHPMax(), false);
    local mp, mp_quality = read_cap(mp_cap, stats:GetMPMax(), true);
    return hp, mp, hp_quality, mp_quality;
end

function player.on_vitals(hp, mp, hp_percent, mp_percent)
    observe_vital(hp_cap, hp, hp_percent);
    observe_vital(mp_cap, mp, mp_percent);
end

function player.on_max_vitals(hp, mp)
    if (not valid_cap(hp, false) or not valid_cap(mp, true)) then return; end
    hp_cap.current, hp_cap.percent, hp_cap.rejected_native, hp_cap.last_current = nil, nil, nil, nil;
    mp_cap.current, mp_cap.percent, mp_cap.rejected_native, mp_cap.last_current = nil, nil, nil, nil;
    hp_cap.value, hp_cap.quality, hp_cap.pinned, hp_cap.native = hp, false, true, stats:GetHPMax();
    mp_cap.value, mp_cap.quality, mp_cap.pinned, mp_cap.native = mp, false, true, stats:GetMPMax();
end

function player.reset_vitals()
    for key in pairs(hp_cap) do hp_cap[key] = nil; end
    for key in pairs(mp_cap) do mp_cap[key] = nil; end
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
