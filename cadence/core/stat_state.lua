--[[
    Keeps the parts of your stats the client can see. Gear is read five times a second. Packets fill
    in merits, set blue spells and items used while cadence was running. Missing power stays unknown.
    This never asks the server for data or changes anything in the client.
]]

local modifiers = require('core.modifiers');
local data = require('data.phoenix_modifiers');
local packets = require('core.packets');
local state = {};
local PERIOD = 0.2;
local FOOD = data.effect_ids and data.effect_ids.food or 251;
local ENCHANTMENT = data.effect_ids and data.effect_ids.enchantment or 162;
local VARIABLE_SPEED = { [13] = true, [194] = true, [214] = true };
local EVENT_LIMIT = 128;

local function member(object, name)
    return object[name];
end

local function call(object, name, ...)
    if (object == nil) then return nil; end
    local ok, method = pcall(member, object, name);
    if (not ok or type(method) ~= 'function') then return nil; end
    local success, value = pcall(method, object, ...);
    if (success) then return value; end
    return nil;
end

local memory = call(AshitaCore, 'GetMemoryManager');
local player = call(memory, 'GetPlayer');
local inventory = call(memory, 'GetInventory');
local party = call(memory, 'GetParty');

local snapshot, model, model_inputs, sampled_at, gear_due, effect_due, changed;
local merit_batches, pending_food, pending_items, pending_effects, rows;
local equipment_cache, equipped_locations, status_timers = {}, {}, {};
local unknown_enchantment, vitals_until, character_id, blue_role;
local evidence, events, cold_status_read, cold_status_retry_at, blue_reader, blue_candidate, blue_retry_at;
local unknown_item_effects;
local zone_packet, game_clock;

local function relevant(effect)
    return VARIABLE_SPEED[effect] or (data.relevant_effects or {})[effect]
        or ((unknown_item_effects or {})[effect] ~= nil);
end

local function note(kind, now, fields)
    local entry = fields or {};
    entry.kind, entry.at = kind, now or snapshot.now or 0;
    if (#events >= EVENT_LIMIT) then table.remove(events, 1); end
    events[#events + 1] = entry;
end

local function copy(value)
    if (type(value) ~= 'table') then return value; end
    local result = {};
    for key, item in pairs(value) do result[key] = copy(item); end
    return result;
end

-- Evidence timestamps do not change the arithmetic. Every observed input still does.
local function same(a, b)
    if (type(a) ~= type(b)) then return false; end
    if (type(a) ~= 'table') then return a == b; end
    for key, value in pairs(a) do if (key ~= 'timer_stamp' and not same(value, b[key])) then return false; end end
    for key in pairs(b) do if (key ~= 'timer_stamp' and a[key] == nil) then return false; end end
    return true;
end

local function same_inputs()
    if (model_inputs == nil) then return false; end
    for key, value in pairs(snapshot) do
        if (key ~= 'now' and not same(value, model_inputs[key])) then return false; end
    end
    for key in pairs(model_inputs) do if (snapshot[key] == nil) then return false; end end
    return true;
end

local function byte(blob, offset)
    if (type(blob) ~= 'string' or offset < 0 or offset >= #blob) then return nil; end
    return blob:byte(offset + 1);
end

local function word(blob, offset)
    local a, b = byte(blob, offset), byte(blob, offset + 1);
    if (a == nil or b == nil) then return nil; end
    return a + b * 256;
end

local function dword(blob, offset)
    local a, b = word(blob, offset), word(blob, offset + 2);
    if (a == nil or b == nil) then return nil; end
    return a + b * 65536;
end

-- The official BluSets reader locates this offset in the running client. Only the read path is
-- used here. ReadProcessMemory fails safely for an unavailable page; no client function is called.
local function make_blue_reader()
    if (ashita == nil or ashita.memory == nil or type(ashita.memory.find) ~= 'function') then
        return nil, 'BLU signature reader unavailable';
    end
    local ok, ffi = pcall(require, 'ffi');
    if (not ok or ffi.os ~= 'Windows') then return nil, 'client memory unavailable'; end
    ok = pcall(ffi.cdef, [[int __stdcall ReadProcessMemory(void*, const void*, void*, size_t, size_t*);]]);
    if (not ok) then return nil, 'safe memory reader unavailable'; end
    local function read(address, size)
        if (type(address) ~= 'number' or address < 0x10000 or address + size > 0xFFFFFFFF or size > 32) then return nil; end
        local success, result = pcall(function ()
            local buffer, got = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]');
            if (ffi.C.ReadProcessMemory(ffi.cast('void*', -1), ffi.cast('const void*', address), buffer, size, got) == 0
                or tonumber(got[0]) ~= size) then return nil; end
            return ffi.string(buffer, size);
        end);
        return success and result or nil;
    end
    local pattern = 'C1E1032BC8B0018D????????????B9????????F3A55F5E5B';
    local found, address = pcall(ashita.memory.find, ':ffximain', 0, pattern, 10, 0);
    if (not found or type(address) ~= 'number' or address == 0) then return nil, 'BLU signature unavailable'; end
    local checked, second = pcall(ashita.memory.find, ':ffximain', 0, pattern, 10, 1);
    if (not checked or (second ~= nil and second ~= 0)) then return nil, 'BLU signature ambiguous'; end
    local offset = dword(read(address, 4), 0);
    if (offset == nil or offset < 0x100 or offset > 0x100000) then return nil, 'BLU offset unavailable'; end
    local pointers = call(AshitaCore, 'GetPointerManager');
    return function (role)
        local pointer = call(pointers, 'Get', 'inventory');
        local first = dword(read(pointer, 4), 0);
        local base = first and dword(read(first, 4), 0);
        if (base == nil or base == 0) then return nil; end
        return read(base + offset + (role == 1 and 0x9C or 0), 24);
    end;
end

local function read_blue(now)
    if (snapshot.blue_spells_known or now < blue_retry_at) then return; end
    local role = snapshot.main_job == 16 and 0 or (snapshot.sub_job == 16 and 1 or nil);
    if (role == nil) then return; end
    blue_retry_at = now + 1;
    if (call(player, 'GetIsZoning') ~= 0 or character_id == nil) then
        evidence.blue_status = 'waiting for character';
        return;
    end
    if (blue_reader == nil) then
        local reason;
        blue_reader, reason = make_blue_reader();
        if (blue_reader == nil) then blue_reader = false; evidence.blue_status = reason; end
    end
    if (blue_reader == false) then return; end
    local blob = blue_reader(role);
    if (blob == nil or byte(blob, 0) ~= 16 or byte(blob, 1) ~= role or word(blob, 2) ~= 0) then
        blue_candidate = nil;
        evidence.blue_status = 'BLU buffer not ready';
        return;
    end
    local spells, seen = {}, {};
    for offset = 4, 23 do
        local value = byte(blob, offset);
        if (value ~= 0) then
            local id = value + 512;
            if (not (data.valid_blue_spells or {})[id] or seen[id] or call(player, 'HasSpell', id) == false) then
                blue_candidate = nil;
                evidence.blue_status = 'BLU buffer not valid';
                return;
            end
            spells[#spells + 1], seen[id] = id, true;
        end
    end
    if (blue_candidate == nil or blue_candidate.blob ~= blob or blue_candidate.role ~= role) then
        blue_candidate = { blob = blob, role = role };
        evidence.blue_status = 'confirming BLU buffer';
        return;
    end
    -- A valid private-server buffer can still be stale. Only a normal job packet confirms it.
    snapshot.blue_spells, snapshot.blue_spells_known, blue_role = spells, false, role;
    evidence.blue_spells_seen_at, evidence.blue_source, evidence.blue_status = now, 'memory', 'provisional';
    if (not blue_candidate.reported) then
        note('blue_spells', now, { source = 'memory', count = #spells, role = role, provisional = true });
        blue_candidate.reported = true;
        changed = true;
    end
end

-- These are the standard and trial augments used by Phoenix. Other formats stay unknown. Reading
-- the bytes avoids calling a client function through a signature that may have changed.
local function augments(extra)
    if (type(extra) ~= 'string' or #extra < 12) then return nil, false; end
    local kind, flags = extra:byte(1, 2);
    if (kind == 0 or kind == 1) then return {}, true; end
    if (kind ~= 2 or bit.band(flags, 0xB8) ~= 0) then return nil, false; end
    local result = {};
    local count = bit.band(flags, 0x40) ~= 0 and 4 or 5;
    for i = 0, count - 1 do
        local packed = word(extra, 2 + i * 2);
        local id = bit.band(packed, 0x7FF);
        if (id ~= 0) then
            result[#result + 1] = { id = id, value = bit.rshift(packed, 11) };
        end
    end
    return result, true;
end

local function read_equipment(now)
    local equipped, present = {}, {};
    equipped_locations = {};
    local known = inventory ~= nil;
    for slot = 0, 15 do
        local location = call(inventory, 'GetEquippedItem', slot);
        if (location == nil) then known = false; end
        local index = location and tonumber(location.Index) or 0;
        if (index ~= 0) then
            equipped_locations[index] = true;
            local item = call(inventory, 'GetContainerItem', bit.rshift(index, 8), bit.band(index, 255));
            local id = item and tonumber(item.Id);
            if (id ~= nil and id > 0 and id < 65535) then
                local extra = type(item.Extra) == 'string' and item.Extra or nil;
                local cached = equipment_cache[slot];
                if (cached == nil or cached.id ~= id or cached.extra ~= extra) then
                    local decoded, understood = augments(extra);
                    cached = { id = id, extra = extra, augments = decoded, augments_known = understood };
                    equipment_cache[slot] = cached;
                    note('equipment', now, { slot = slot, item = id, augments_known = understood });
                end
                equipped[slot], present[id] = cached, true;
            else
                known = false;
            end
        else
            if (equipment_cache[slot] ~= nil) then note('equipment', now, { slot = slot, item = 0 }); end
            equipment_cache[slot] = nil;
        end
    end
    snapshot.equipment, snapshot.equipment_known = equipped, known;
    for id in pairs(snapshot.activated_items) do
        local rule = (data.activated_items or {})[id];
        if (known and rule and rule.remove_on_unequip and not present[id]) then
            snapshot.activated_items[id] = nil;
        end
    end
    for id, effect in pairs(snapshot.effects) do
        if (effect.weapon_id and (equipped[effect.slot] == nil or equipped[effect.slot].id ~= effect.weapon_id)) then
            snapshot.effects[id] = nil;
        end
    end
end

local function read_party()
    local jobs, other_jobs, seen = {}, {}, {};
    local count, known, size_known = 0, party ~= nil, party ~= nil;
    local in_zone, zone_known = 0, party ~= nil and snapshot.zone ~= nil;
    for i = 0, 5 do
        local active = call(party, 'GetMemberIsActive', i);
        local id = call(party, 'GetMemberServerId', i);
        if (active == nil or ((active ~= false and active ~= 0) and (id == nil or id == 0))) then
            known, size_known = false, false;
        end
        if (active ~= false and active ~= 0 and id ~= nil and id ~= 0 and not seen[id]) then
            seen[id], count = true, count + 1;
            local zone = call(party, 'GetMemberZone', i);
            if (zone == nil or zone == 0) then zone_known = false;
            elseif (zone == snapshot.zone) then in_zone = in_zone + 1; end
            local job = call(party, 'GetMemberMainJob', i);
            if (i == 0) then job = snapshot.main_job; end
            if (job ~= nil and job > 0) then
                jobs[job] = (jobs[job] or 0) + 1;
                if (i ~= 0) then other_jobs[job] = (other_jobs[job] or 0) + 1; end
            else
                known = false;
            end
        end
    end
    snapshot.party_size = count > 0 and count or nil;
    snapshot.party_jobs, snapshot.another_party_jobs = jobs, other_jobs;
    snapshot.party_known = known;
    snapshot.party_size_known = size_known and count > 0;
    snapshot.party_in_zone, snapshot.party_in_zone_known = in_zone, zone_known and size_known and count > 0;
end

local function bump(id)
    snapshot.effect_epochs[id] = (snapshot.effect_epochs[id] or 0) + 1;
    changed = true;
end

local function stamp_matches(a, b)
    local distance = math.abs(a - b);
    return distance <= 60 or distance >= 4294967296 - 60;
end

-- One icon can belong to several spells or items. Keep an item's own expiration when another joins it.
local function reconcile_items(effect, before, stamps, now)
    local claimed, old_used, added = {}, {}, {};
    local removed = false;
    for i, stamp in ipairs(stamps) do
        local found;
        for j, old in ipairs(before or {}) do
            if (not old_used[j] and stamp_matches(stamp, old)) then found = j; break; end
        end
        if (found) then old_used[found] = true; else added[#added + 1] = i; end
    end
    for i in ipairs(before or {}) do if (not old_used[i]) then removed = true; break; end end
    local matched = 0;
    for pass = 1, 2 do
        local entries = pass == 1 and snapshot.activated_items or pending_items;
        for item_id, entry in pairs(entries) do
            if ((entry.effect or ENCHANTMENT) == effect and (pass == 2 or pending_items[item_id] == nil)) then
                local found;
                if (entry.timer_stamp ~= nil) then
                    local old_count, new_count = 0, 0;
                    for _, stamp in ipairs(before or {}) do
                        if (stamp_matches(entry.timer_stamp, stamp)) then old_count = old_count + 1; end
                    end
                    for i, stamp in ipairs(stamps) do
                        if (stamp_matches(entry.timer_stamp, stamp)) then
                            new_count = new_count + 1;
                            if (not claimed[i]) then found = i; end
                        end
                    end
                    -- Losing one of two identical timestamps cannot identify which effect remains.
                    if (old_count > 1 and new_count < old_count) then found = nil; end
                elseif (now <= entry.seen_at + 2 and #added == 1 and not claimed[added[1]]) then
                    found = added[1];
                elseif (before ~= nil and #before == 1) then
                    for i, stamp in ipairs(stamps) do
                        if (not claimed[i] and stamp_matches(stamp, before[1])) then found = i; break; end
                    end
                elseif (not removed and #stamps == 1 and not claimed[1]) then
                    found = 1;
                end
                if (found) then
                    entry.timer_stamp, claimed[found] = stamps[found], true;
                    matched = matched + 1;
                elseif (entry.timer_stamp ~= nil or (now > entry.seen_at + 2 and removed)) then
                    entries[item_id] = nil;
                end
            end
        end
    end
    local unknown = matched < #stamps;
    unknown_item_effects[effect] = unknown;
    if (effect == ENCHANTMENT) then
        unknown_enchantment, snapshot.activated_items_known = unknown, not unknown;
    end
end

local function observe_timers(timers, now, source)
    for effect, stamps in pairs(timers) do
        table.sort(stamps);
        local before = status_timers[effect];
        local same = before ~= nil and #before == #stamps;
        if (same) then
            for i = 1, #stamps do
                if (not stamp_matches(before[i], stamps[i])) then same = false; break; end
            end
        end
        if (not same) then
            bump(effect);
            if (source == 'packet') then effect_due = now + PERIOD; end
            note('effect_timer', now, { effect = effect, count = #stamps, source = source, refresh = before ~= nil });
            if (before ~= nil and effect == FOOD and snapshot.food
                and now > snapshot.food.seen_at + 2 and pending_food == nil) then
                snapshot.food, snapshot.food_known = nil, false;
            elseif (unknown_item_effects[effect] == nil and before ~= nil and snapshot.effects[effect]
                and now > snapshot.effects[effect].seen_at + 2 and pending_effects[effect] == nil) then
                snapshot.effects[effect] = nil;
            end
        end
        if (unknown_item_effects[effect] ~= nil) then reconcile_items(effect, before, stamps, now); end
    end
    for effect, before in pairs(status_timers) do
        if (timers[effect] == nil and unknown_item_effects[effect] ~= nil) then
            reconcile_items(effect, before, {}, now);
        end
    end
    status_timers = timers;
    evidence.status_seen_at, evidence.status_source = now, source;
end

local function read_cold_status(now)
    if (cold_status_read or now < cold_status_retry_at) then return; end
    cold_status_retry_at = now + 1;
    local icons, expires = call(player, 'GetStatusIcons'), call(player, 'GetStatusTimers');
    if (icons == nil or expires == nil) then return; end
    cold_status_read = true;
    local timers = {};
    for i = 0, 31 do
        local id, stamp = icons[i], expires[i];
        if (relevant(id) and type(stamp) == 'number') then
            timers[id] = timers[id] or {};
            timers[id][#timers[id] + 1] = stamp;
        end
    end
    observe_timers(timers, now, 'memory');
end

local function read_buffs(loadout, now)
    -- Observed deadlines still expire while client status memory is unavailable.
    for id, entry in pairs(snapshot.activated_items) do
        if (entry.expires_at and now >= entry.expires_at) then
            snapshot.activated_items[id] = nil;
            bump(entry.effect or ENCHANTMENT);
        end
    end
    for id, effect in pairs(snapshot.effects) do
        if (effect.expires_at and now >= effect.expires_at) then snapshot.effects[id] = nil; end
    end
    if (loadout and loadout.buffs_known == false) then
        snapshot.buffs_known = false;
        return;
    end
    local buffs = loadout and loadout.buffs;
    local counts = loadout and loadout.buff_counts;
    if (type(buffs) ~= 'table') then
        local raw = call(player, 'GetBuffs');
        if (raw ~= nil) then
            buffs, counts = {}, {};
            for i = 0, 31 do
                local id = raw[i];
                if (id ~= nil and id > 0 and id ~= 255) then
                    buffs[id], counts[id] = true, (counts[id] or 0) + 1;
                end
            end
        end
    end
    if (buffs == nil) then snapshot.buffs_known = false; return; end
    local old, old_counts, fresh, fresh_counts = snapshot.buffs, snapshot.buff_counts, {}, {};
    for id, value in pairs(buffs) do
        if (value) then
            fresh[id] = true;
            fresh_counts[id] = counts and counts[id] or (status_timers[id] and #status_timers[id]) or 1;
        end
    end
    buffs = fresh;
    for id, count in pairs(fresh_counts) do
        if (relevant(id) and (snapshot.buff_counts[id] or 0) ~= count) then
            bump(id);
            note('buff', now, { effect = id, count = count });
        end
    end
    for id in pairs(snapshot.buff_counts) do
        if (relevant(id) and fresh_counts[id] == nil) then bump(id); note('buff', now, { effect = id, count = 0 }); end
    end
    snapshot.buffs, snapshot.buff_counts, snapshot.buffs_known = buffs, fresh_counts, true;
    evidence.buffs_seen_at = now;
    if (not buffs[ENCHANTMENT]) then
        unknown_enchantment = false;
    elseif (not old[ENCHANTMENT] and next(pending_items) == nil) then
        unknown_enchantment = true;
    end
    if (pending_food and buffs[FOOD]) then
        snapshot.food = pending_food;
        pending_food = nil;
        bump(FOOD);
    elseif (pending_food and now > pending_food.seen_at + 2) then
        pending_food = nil;
    end
    if (not buffs[FOOD]) then snapshot.food = nil; end
    snapshot.food_known = not buffs[FOOD] or snapshot.food ~= nil;
    for id, entry in pairs(pending_items) do
        if (buffs[entry.effect or ENCHANTMENT]) then
            snapshot.activated_items[id] = entry;
            pending_items[id] = nil;
            bump(entry.effect or ENCHANTMENT);
        elseif (now > entry.seen_at + 2) then
            pending_items[id] = nil;
        end
    end
    for id, entry in pairs(snapshot.activated_items) do
        if (not buffs[entry.effect or ENCHANTMENT] or now >= entry.expires_at) then
            snapshot.activated_items[id] = nil;
            bump(entry.effect or ENCHANTMENT);
        end
    end
    snapshot.activated_items_known = not unknown_enchantment;
    for effect in pairs(unknown_item_effects) do
        if (not buffs[effect]) then
            unknown_item_effects[effect] = false;
        elseif (not old[effect] or (fresh_counts[effect] or 0) > (old_counts[effect] or 0)) then
            local observed = 0;
            for _, entry in pairs(snapshot.activated_items) do
                if ((entry.effect or ENCHANTMENT) == effect) then observed = observed + 1; end
            end
            if (observed < (fresh_counts[effect] or 1)) then unknown_item_effects[effect] = true; end
        end
        snapshot.activated_item_effects_known[effect] = not unknown_item_effects[effect];
    end
    for id, effect in pairs(pending_effects) do
        if (buffs[id]) then
            snapshot.effects[id], pending_effects[id] = effect, nil;
        elseif (now > effect.seen_at + 2) then
            pending_effects[id] = nil;
        end
    end
    for id, effect in pairs(snapshot.effects) do
        if (not buffs[id] or (effect.expires_at and now >= effect.expires_at)) then snapshot.effects[id] = nil; end
    end
end

local function read_character(loadout, now)
    loadout = loadout or {};
    local id = call(party, 'GetMemberServerId', 0);
    if (character_id == nil and id ~= nil and id ~= 0) then character_id = id; end
    local old_main, old_sub = snapshot.main_job, snapshot.sub_job;
    snapshot.main_job = loadout.main_job or call(player, 'GetMainJob');
    snapshot.main_level = loadout.main_level or call(player, 'GetMainJobLevel');
    if (snapshot.main_job == 0) then snapshot.main_job = nil; end
    if (snapshot.main_level == 0) then snapshot.main_level = nil; end
    snapshot.sub_job = loadout.sub_job or call(player, 'GetSubJob');
    snapshot.sub_level = loadout.sub_level or call(player, 'GetSubJobLevel');
    if (vitals_until == nil or now >= vitals_until) then
        snapshot.max_hp = loadout.max_hp or call(player, 'GetHPMax');
        snapshot.max_mp = loadout.max_mp or call(player, 'GetMPMax');
        snapshot.hp = loadout.hp or call(party, 'GetMemberHP', 0);
        snapshot.mp = loadout.mp or call(party, 'GetMemberMP', 0);
        snapshot.tp = loadout.tp or call(party, 'GetMemberTP', 0);
        snapshot.hp_percent = loadout.hp_percent or call(party, 'GetMemberHPPercent', 0);
    end
    snapshot.nation = call(player, 'GetNation');
    snapshot.zone = call(party, 'GetMemberZone', 0) or snapshot.zone;
    snapshot.region = (data.zone_regions or {})[snapshot.zone];
    snapshot.engaged = loadout.engaged;
    snapshot.resting = loadout.resting;
    snapshot.pet_present = loadout.pet_present;
    snapshot.flags = copy(loadout.flags or {});
    if (snapshot.flags.assault == nil) then snapshot.flags.assault = (data.zone_assault or {})[snapshot.zone]; end
    if (snapshot.flags.dynamis == nil) then snapshot.flags.dynamis = (data.zone_dynamis or {})[snapshot.zone]; end
    if (game_clock) then
        local time = game_clock.seconds + math.max(0, now - game_clock.at);
        snapshot.day, snapshot.hour = math.floor(time / 3456) % 8, math.floor(time / 144) % 24;
    end
    local matching_blue = (snapshot.main_job == 16 and blue_role == 0) or (snapshot.sub_job == 16 and blue_role == 1);
    if ((old_main ~= nil and (old_main ~= snapshot.main_job or old_sub ~= snapshot.sub_job))
        or (snapshot.blue_spells_known and (snapshot.main_job == 16 or snapshot.sub_job == 16) and not matching_blue)) then
        if (not matching_blue) then
            snapshot.blue_spells, snapshot.blue_spells_known, blue_role = {}, false, nil;
        end
    end
end

function state.reset()
    snapshot = {
        equipment = {}, buffs = {}, buff_counts = {}, merits = {}, blue_spells = {}, effects = {},
        activated_items = {}, effect_epochs = {}, unknown = {}, flags = {},
        activated_item_effects_known = {},
        merits_known = false, blue_spells_known = false, food_known = false,
        activated_items_known = false,
    };
    model, model_inputs, sampled_at, gear_due, effect_due, changed = nil, nil, -math.huge, nil, nil, true;
    merit_batches, pending_food, pending_items, pending_effects, rows = 0, nil, {}, {}, {};
    equipment_cache, equipped_locations, status_timers = {}, {}, {};
    unknown_enchantment, vitals_until, character_id, blue_role = true, nil, nil, nil;
    evidence, events, cold_status_read, blue_reader, blue_candidate, blue_retry_at = {}, {}, false, nil, nil, -math.huge;
    cold_status_retry_at = -math.huge;
    unknown_item_effects = { [ENCHANTMENT] = true };
    for _, rule in pairs(data.activated_items or {}) do unknown_item_effects[rule.effect or ENCHANTMENT] = true; end
    zone_packet, game_clock = nil, nil;
end

function state.on_zone(my_id)
    local previous, timers, unknown, batches, role = snapshot, status_timers, unknown_enchantment, merit_batches, blue_role;
    local previous_evidence, previous_unknown = evidence, unknown_item_effects;
    local incoming_zone = zone_packet;
    local same_character = my_id ~= nil and my_id ~= 0 and my_id == character_id;
    state.reset();
    character_id = my_id;
    if (same_character) then
        -- Session evidence still belongs to you. Buffs, expiry and gear reconcile it after zoning.
        for _, key in ipairs({ 'merits', 'merits_known', 'blue_spells', 'blue_spells_known', 'food',
            'food_known', 'activated_items', 'activated_items_known', 'effects', 'effect_epochs',
            'activated_item_effects_known', 'buffs', 'buff_counts', 'main_job', 'sub_job' }) do
            snapshot[key] = previous[key];
        end
        status_timers, unknown_enchantment, merit_batches = timers, unknown, batches;
        blue_role = role;
        evidence, unknown_item_effects = previous_evidence, previous_unknown;
    end
    if (incoming_zone and incoming_zone.id == my_id) then
        snapshot.zone, snapshot.weather = incoming_zone.zone, incoming_zone.weather;
        if (incoming_zone.seconds > 0) then
            game_clock = { seconds = incoming_zone.seconds, at = incoming_zone.at };
            evidence.time_seen_at = incoming_zone.at;
        end
        evidence.weather_seen_at = incoming_zone.at;
    end
    note('zone', os.clock(), { same_character = same_character });
end

function state.update(now, loadout, force)
    snapshot.now = now;
    local sample = force or now - sampled_at >= PERIOD;
    local context_changed = false;
    if (loadout and model ~= nil) then
        for _, key in ipairs({ 'main_job', 'main_level', 'sub_job', 'sub_level', 'engaged', 'resting', 'pet_present' }) do
            if (loadout[key] ~= nil and loadout[key] ~= snapshot[key]) then context_changed = true; break; end
        end
    end
    if (context_changed and not sample) then
        read_character(loadout, now);
        changed = true;
    end
    if (sample) then
        sampled_at = now;
        read_character(loadout, now);
        read_cold_status(now);
        read_buffs(loadout, now);
        read_party();
        read_blue(now);
        if (gear_due == nil or now >= gear_due) then
            read_equipment(now);
            gear_due = nil;
        end
        changed = true;
        evidence.sampled_at = now;
        if (effect_due and now >= effect_due) then effect_due = nil; end
    end
    if (changed or model == nil) then
        if (model == nil or not same_inputs()) then
            model = modifiers.calculate(snapshot);
            model_inputs = copy(snapshot);
            model_inputs.now = nil;
        end
        changed = false;
    end
    model.transition = gear_due ~= nil or effect_due ~= nil;
    model.evidence = model.evidence or {};
    for key in pairs(model.evidence) do model.evidence[key] = nil; end
    for key, value in pairs(evidence) do model.evidence[key] = value; end
    model.evidence.age = evidence.sampled_at and math.max(0, now - evidence.sampled_at) or nil;
    return model;
end

-- Own casts can use current client inputs. A pending gear packet still makes gear uncertain.
function state.effect_context(now, loadout)
    state.update(now, loadout, true);
    local result = { equipment = {}, equipment_known = snapshot.equipment_known and gear_due == nil,
        buffs = copy(snapshot.buffs), buffs_known = snapshot.buffs_known,
        merits = copy(snapshot.merits), merits_known = snapshot.merits_known,
        main_job = snapshot.main_job, main_level = snapshot.main_level };
    for slot = 0, 15 do
        local item = snapshot.equipment[slot];
        if (item) then
            result.equipment[#result.equipment + 1] = { slot = slot, id = item.id,
                augments = copy(item.augments), augments_known = item.augments_known };
        end
    end
    return result;
end

-- The main packet handler already decoded these values. Use them before client memory catches up.
function state.on_vitals(now, hp, mp, tp, max_hp, max_mp)
    snapshot.hp, snapshot.mp, snapshot.tp = hp, mp, tp;
    if (max_hp ~= nil) then snapshot.max_hp = max_hp; end
    if (max_mp ~= nil) then snapshot.max_mp = max_mp; end
    snapshot.hp_percent = snapshot.max_hp and snapshot.max_hp > 0 and math.floor(hp * 100 / snapshot.max_hp) or nil;
    vitals_until = now + PERIOD;
    evidence.vitals_seen_at = now;
    changed = true;
end

local function item_finished(item_id, now)
    if ((data.foods or {})[item_id]) then
        read_party();
        pending_food = { id = item_id, party_size = snapshot.party_size_known and snapshot.party_size or nil, seen_at = now };
        effect_due = now + PERIOD;
        evidence.food_seen_at = now;
        note('food', now, { item = item_id, party_size = pending_food.party_size });
    end
    local activated = (data.activated_items or {})[item_id];
    local wearing = false;
    for _, item in pairs(snapshot.equipment) do
        if (item.id == item_id) then wearing = true; break; end
    end
    if (activated and wearing and gear_due == nil and type(activated.duration) == 'number') then
        pending_items[item_id] = { seen_at = now, expires_at = now + activated.duration, effect = activated.effect or ENCHANTMENT };
        effect_due = now + PERIOD;
        note('activated_item', now, { item = item_id, effect = activated.effect or ENCHANTMENT, duration = activated.duration });
    end
    changed = true;
end

local function action(e, now, my_id)
    if (e.size == nil or e.size < 24 or e.data_raw == nil or my_id == nil) then return; end
    local actor, category = packets.action_header(e);
    if (category ~= 3 and category ~= 4 and category ~= 5 and category ~= 6) then return; end
    local id = packets.action_param(e);
    local count = packets.action_results(e, rows);
    for i = 1, count do
        local row = rows[i];
        if (row.target == my_id) then
            -- Food and the supported enchanted items leave the normal result message at zero.
            local rule = (data.activated_items or {})[id];
            local item_success = row.message == 0 or (rule and row.param == (rule.effect or ENCHANTMENT)
                and (row.message == 230 or row.message == 236 or row.message == 237));
            if (category == 5 and item_success) then item_finished(id, now); end
            if ((row.message == 230 or row.message == 236 or row.message == 237)
                and relevant(row.param)) then
                bump(row.param);
                effect_due = now + PERIOD;
                note('effect_refresh', now, { effect = row.param, action = id, category = category });
            end
            if (category == 6 and (id == 100 or id == 109 or id == 123)) then
                -- The roll result is a dice total. It cannot tell us the caster's hidden bonuses.
                bump(312);
                bump(321);
                effect_due = now + PERIOD;
            end
        end
    end
    if (actor == my_id and category == 3) then
        if (gear_due == nil) then
            for slot, item in pairs(snapshot.equipment) do
                local rule = (data.relic_aftermath or {})[item.id];
                if (rule and rule.slot == slot and rule.weaponskill == id) then
                    pending_effects[273] = {
                        store_tp = rule.store_tp, weapon_id = item.id, slot = slot, seen_at = now,
                        expires_at = now + rule.duration_per_tp * 3000,
                        mods = copy(rule.mods),
                    };
                    effect_due = now + PERIOD;
                    changed = true;
                    break;
                end
            end
        end
        -- An aftermath refresh with the same icon still changes an uncertain TP estimate.
        for _, effect in ipairs({ 270, 271, 272, 273 }) do
            if (snapshot.buffs[effect]) then bump(effect); end
        end
    end
end

function state.on_packet(e, now, my_id)
    if (e == nil or e.blocked or e.injected) then return; end
    local id, blob = e.id, e.data;
    if (id == 0x00A and type(blob) == 'string' and #blob >= 0x70) then
        local weather = word(blob, 0x68);
        zone_packet = { id = dword(blob, 4), zone = word(blob, 0x30), seconds = dword(blob, 0x3C),
            weather = weather <= 19 and weather or nil, at = now };
        return;
    end
    if (id == 0x020 and model ~= nil) then
        local bag, index = byte(blob, 14), byte(blob, 15);
        if (bag == nil or index == nil or not equipped_locations[bag * 256 + index]) then return; end
    end
    if (id == 0x050 or id == 0x020 or id == 0x01D) then
        gear_due = now + PERIOD;
        if (model) then model.transition = true; end
        note('equipment_pending', now, { packet = id });
        evidence.last_packet_at = now;
        return;
    elseif (id == 0x0DF) then
        return;
    elseif (id == 0x061 or id == 0x01B or id == 0x0AC) then
        effect_due = now + PERIOD;
        return;
    elseif (id == 0x028) then
        action(e, now, my_id);
        return;
    end
    if (type(blob) ~= 'string') then return; end
    if (id == 0x08C) then
        local count = word(blob, 4);
        if (count == nil or count > 61 or #blob < 8 + count * 4) then return; end
        for i = 0, count - 1 do
            local offset = 8 + i * 4;
            snapshot.merits[word(blob, offset)] = byte(blob, offset + 3);
        end
        if (count == 61) then merit_batches = merit_batches + 1; end
        snapshot.merits_known = merit_batches >= 5;
        evidence.merits_seen_at, evidence.last_packet_at = now, now;
        note('merits', now, { count = count });
        changed = true;
    elseif (id == 0x044 and byte(blob, 4) == 16 and #blob >= 28) then
        local spells = {};
        for offset = 8, 27 do
            local spell = byte(blob, offset);
            if (spell ~= 0) then spells[#spells + 1] = spell + 512; end
        end
        snapshot.blue_spells, snapshot.blue_spells_known = spells, true;
        blue_role = byte(blob, 5);
        evidence.blue_spells_seen_at, evidence.blue_source, evidence.blue_status, evidence.last_packet_at = now, 'packet', 'known', now;
        note('blue_spells', now, { source = 'packet', count = #spells, role = blue_role });
        changed = true;
    elseif (id == 0x057 and #blob >= 10) then
        snapshot.weather = byte(blob, 8);
        evidence.weather_seen_at, evidence.last_packet_at = now, now;
        note('weather', now, { weather = snapshot.weather });
        changed = true;
    elseif (id == 0x063 and word(blob, 4) == 9 and #blob >= 200) then
        local timers = {};
        for i = 0, 31 do
            local effect = word(blob, 8 + i * 2);
            local stamp = dword(blob, 72 + i * 4);
            if (relevant(effect)) then
                timers[effect] = timers[effect] or {};
                timers[effect][#timers[effect] + 1] = stamp;
            end
        end
        observe_timers(timers, now, 'packet');
        evidence.last_packet_at = now;
    end
end

function state.info()
    return model;
end

-- The first attack interval is sampled before drawn-weapon latents turn on.
function state.before_engage()
    if (model == nil or model.transition) then return nil; end
    local before = {};
    for key, value in pairs(snapshot) do before[key] = value; end
    before.engaged, before.resting = false, false;
    return modifiers.calculate(before);
end

-- Reports are requested by you. They omit raw extra data, packet bytes, names and server IDs.
function state.snapshot()
    local result = {};
    for _, key in ipairs({ 'main_job', 'main_level', 'sub_job', 'sub_level', 'zone', 'region', 'nation',
        'weather', 'day', 'hour', 'engaged', 'resting', 'pet_present', 'hp', 'mp', 'tp', 'max_hp', 'max_mp', 'hp_percent',
        'buffs', 'buff_counts', 'buffs_known', 'equipment_known', 'merits', 'merits_known',
        'blue_spells', 'blue_spells_known', 'food', 'food_known', 'activated_items',
        'activated_items_known', 'activated_item_effects_known', 'effects', 'effect_epochs',
        'party_size', 'party_size_known', 'party_in_zone', 'party_in_zone_known', 'party_known', 'party_jobs', 'another_party_jobs', 'flags' }) do
        result[key] = copy(snapshot[key]);
    end
    result.equipment = {};
    for slot = 0, 15 do
        local item = snapshot.equipment[slot];
        if (item) then
            result.equipment[#result.equipment + 1] = { slot = slot, id = item.id,
                augments = copy(item.augments), augments_known = item.augments_known };
        end
    end
    result.evidence = copy(evidence);
    result.evidence.age = evidence.sampled_at and math.max(0, os.clock() - evidence.sampled_at) or nil;
    result.status_timers = copy(status_timers);
    return result;
end

local NO_EVENTS = {};
function state.drain_events()
    if (#events == 0) then return NO_EVENTS; end
    local result = events;
    events = {};
    return result;
end

state.reset();
return state;
