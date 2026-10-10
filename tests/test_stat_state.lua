-- Passive stat inputs, missing client data and changes between packets and the next memory read.
local out, fails = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then fails = fails + 1; end
end

local last, calculations, reads, commands = nil, 0, 0, 0;
local equipped, items, buffs = {}, {}, {};
local party_ids, party_jobs = { [0] = 1001, [1] = 1002 }, { [0] = 12, [1] = 3 };
local live, unloaded_slot = true, nil;
local cold_icons, cold_timers;
local zero = string.rep('\0', 24);
local inv = {
    GetEquippedItem = function (_, slot)
        reads = reads + 1;
        if (slot == unloaded_slot) then return nil; end
        return { Index = equipped[slot] or 0 };
    end,
    GetContainerItem = function (_, bag, index) return items[bag * 256 + index]; end,
};
local stats = {
    GetMainJob = function () return 12; end,
    GetMainJobLevel = function () return 75; end,
    GetSubJob = function () return 1; end,
    GetSubJobLevel = function () return 37; end,
    GetHPMax = function () return 1000; end,
    GetMPMax = function () return 100; end,
    GetNation = function () return 2; end,
    GetStatusIcons = function () return cold_icons; end,
    GetStatusTimers = function () return cold_timers; end,
    GetBuffs = function ()
        local r, i = {}, 0;
        for id, count in pairs(buffs) do
            for _ = 1, type(count) == 'number' and count or 1 do r[i], i = id, i + 1; end
        end
        return r;
    end,
};
local group = {
    GetMemberIsActive = function (_, i) return party_ids[i] ~= nil; end,
    GetMemberServerId = function (_, i) return party_ids[i] or 0; end,
    GetMemberMainJob = function (_, i) return party_jobs[i]; end,
    GetMemberHP = function () return 500; end,
    GetMemberMP = function () return 20; end,
    GetMemberTP = function () return 300; end,
    GetMemberHPPercent = function () return 50; end,
    GetMemberZone = function () return 100; end,
};
local managers = 0;
AshitaCore.GetMemoryManager = function ()
    managers = managers + 1;
    return {
        GetPlayer = function () return live and stats or nil; end,
        GetInventory = function () return live and inv or nil; end,
        GetParty = function () return live and group or nil; end,
    };
end;
AshitaCore.GetChatManager = function () commands = commands + 1; error('No commands belong here'); end;
AshitaCore.GetPacketManager = function () commands = commands + 1; error('No packet requests belong here'); end;
package.loaded['data.phoenix_modifiers'] = {
    zone_regions = { [100] = 4 },
    zone_assault = { [100] = false, [69] = true },
    valid_blue_spells = { [545] = true, [640] = true },
    foods = { [4510] = { mods = { [71] = 3 }, duration = 180 } },
    activated_items = {
        [15889] = { mods = { [72] = 2 }, duration = 1800, remove_on_unequip = true },
        [15290] = { mods = { [384] = 1000 }, duration = 180, effect = 33, remove_on_unequip = true },
    },
    relevant_effects = { [251] = true, [162] = true, [321] = true, [312] = true },
    relic_aftermath = { [18318] = { weaponskill = 153, slot = 0, store_tp = 7, duration_per_tp = 0.02 } },
};
package.loaded['core.modifiers'] = { calculate = function (snapshot)
    calculations = calculations + 1;
    last = snapshot;
    return { tp_key = 'same-stats', resting_key = 'same-stats', known = {} };
end };
local observer = require('core.stat_state');

local function bytes(size, fields)
    local b = MOCK.bytes(size);
    for offset, pair in pairs(fields or {}) do
        local value, length = pair[1], pair[2];
        for i = 0, length - 1 do b[offset + i] = math.floor(value / 256 ^ i) % 256; end
    end
    return MOCK.to_string(b);
end
local function packet(id, blob)
    return { id = id, data = blob, size = #blob };
end
local function update(now) return observer.update(now, { main_job = 12, main_level = 75, sub_job = 1, sub_level = 37 }); end

-- A real 24-byte standard augment payload: id44 with encoded value4 means Store TP+5.
local extra = bytes(24, { [0] = { 2, 1 }, [1] = { 3, 1 }, [2] = { 44 + 4 * 2048, 2 } });
equipped[0], equipped[4] = 0x0307, 0x0408;
items[0x0307], items[0x0408] = { Id = 17809, Extra = zero }, { Id = 15889, Extra = extra };
update(0);
check('reads the sixteen equipped slots', reads == 16);
check('reads the right inventory and wardrobe locations', last.equipment[0].id == 17809 and last.equipment[4].id == 15889);
check('zone maps to the generated server region', last.region == 4);
check('standard augments keep raw id and encoded value', last.equipment[4].augments[1].id == 44 and last.equipment[4].augments[1].value == 4);
check('zero extra data is known unaugmented', last.equipment[0].augments_known and #last.equipment[0].augments == 0);
check('cold merits and blue spells stay unknown', not last.merits_known and not last.blue_spells_known);
check('party input separates another member from yourself', last.party_size == 2 and last.party_jobs[12] == 1 and last.another_party_jobs[12] == nil and last.another_party_jobs[3] == 1);
check('party members in the zone are counted separately', last.party_in_zone == 2 and last.party_in_zone_known);
update(0.1);
check('nearby frames reuse the snapshot and model', reads == 16 and calculations == 1 and managers == 1);
observer.on_vitals(0.101, 750, 60, 800, 1200, 300);
update(0.102);
check('decoded packet vitals update without another memory scan', last.hp == 750 and last.mp == 60 and last.hp_percent == 62 and last.max_hp == 1200 and reads == 16);
observer.update(0.103, { main_job = 1, main_level = 75, sub_job = 12, sub_level = 37, engaged = true });
check('a rapid job or engagement change updates its model immediately', last.main_job == 1 and last.sub_job == 12 and last.engaged and last.hp == 750 and reads == 16);
update(0.104);

local gear = packet(0x050, bytes(8));
observer.on_packet(gear, 0.11, 1001);
local pending = update(0.12);
check('gear packets pause sampling before memory settles', pending.transition and reads == 16);
check('pending irrelevant gear does not change stat keys', pending.tp_key == 'same-stats' and pending.resting_key == 'same-stats');
items[0x0408] = { Id = 15889, Extra = bytes(24, { [0] = { 2, 1 }, [1] = { 3, 1 }, [2] = { 44 + 9 * 2048, 2 } }) };
check('settled gear ends the transition', not update(0.4).transition);
check('the same item id with new augments is reread', last.equipment[4].augments[1].value == 9);
items[0x0408].Extra = bytes(24, { [0] = { 3, 1 }, [1] = { 0x83, 1 } });
update(0.7);
check('an unsupported augment format stays unknown', last.equipment[4].augments_known == false);

local merit = packet(0x08C, bytes(12, { [4] = { 1, 2 }, [8] = { 2374, 2 }, [11] = { 5, 1 } }));
merit.injected = true;
observer.on_packet(merit, 0.71, 1001);
update(0.72);
check('injected packets do not set merits', last.merits[2374] == nil);
merit.injected, merit.blocked = false, true;
observer.on_packet(merit, 0.73, 1001);
check('blocked packets do not set merits', last.merits[2374] == nil);
merit.blocked = false;
observer.on_packet(merit, 0.74, 1001);
update(0.75);
check('normal allocated merits are cached by id', last.merits[2374] == 5 and not last.merits_known);
observer.on_packet(packet(0x08C, bytes(10, { [4] = { 61, 2 } })), 0.76, 1001);
check('a short merit packet leaves known data alone', last.merits[2374] == 5);
observer.on_packet(packet(0x044, bytes(28, { [4] = { 16, 1 }, [8] = { 11, 1 }, [9] = { 44, 1 } })), 0.77, 1001);
update(0.78);
check('blue set packets become actual spell ids', last.blue_spells_known and last.blue_spells[1] == 523 and last.blue_spells[2] == 556);

-- An item starting, failing or affecting another player must not become your food.
observer.on_packet(MOCK.action_packet(1001, 9, 4510, 1001, { { message = 0 } }), 0.8, 1001);
buffs[251] = true;
update(1.0);
check('a pre-existing food buff has no invented item', last.food == nil and not last.food_known);
observer.on_packet(MOCK.action_packet(1001, 5, 4510, 1001, { { message = 75 } }), 1.01, 1001);
observer.on_packet(MOCK.action_packet(1002, 5, 4510, 1002, { { message = 0 } }), 1.02, 1001);
update(1.3);
check('failed or other-target items are ignored', last.food == nil);
observer.on_packet(MOCK.action_packet(1001, 5, 4510, 1001, { { message = 0 } }), 1.31, 1001);
update(1.6);
check('successful food remembers party size at consumption', last.food and last.food.id == 4510 and last.food.party_size == 2);
observer.update(1.81, { main_job = 12, main_level = 75, sub_job = 1, sub_level = 37, buffs = {}, buffs_known = false });
check('unavailable loadout buffs retain observed food as uncertain', last.buffs_known == false and last.food and last.food.id == 4510 and last.buffs[251]);
party_ids[1] = nil;
update(2.02);
check('later party changes do not rewrite food strength', last.food.party_size == 2 and last.party_size == 1);
buffs[251] = nil;
update(2.23);
check('food wearoff removes its identity', last.food == nil and last.food_known);

observer.on_packet(MOCK.action_packet(1001, 5, 15889, 1001, { { message = 0 } }), 2.24, 1001);
buffs[162] = true;
update(2.5);
check('an activated item gets its actual duration', last.activated_items[15889] and last.activated_items[15889].expires_at == 1802.24);
equipped[4] = nil;
observer.on_packet(gear, 2.51, 1001);
update(2.8);
check('unequipping clears an effect with that rule', last.activated_items[15889] == nil);
observer.on_packet(packet(0x057, bytes(12, { [8] = { 5, 1 } })), 2.81, 1001);
update(2.82);
check('weather changes come from normal packets', last.weather == 5);
local epochs = last.effect_epochs[321] or 0;
observer.on_packet(MOCK.action_packet(1002, 6, 109, 1001, { { message = 420, damage = 11 } }), 2.83, 1001);
update(2.84);
check('a roll refresh is tracked without inventing potency', last.effect_epochs[321] > epochs and last.effects[321] == nil);

local before = calculations;
observer.on_packet(MOCK.vitals_packet(1001, 800, 50, 500), 2.85, 1001);
update(2.86);
check('vitals packets do not cause a second stat parse', calculations == before);
observer.on_zone();
update(3.2);
check('zoning drops stale food merits spells and item power', next(last.merits) == nil and not last.blue_spells_known and last.food == nil and next(last.activated_items) == nil and last.weather == nil);
unloaded_slot = 3;
update(3.5);
check('partly loaded equipment is not an empty complete set', last.equipment_known == false);
unloaded_slot = nil;
party_ids[1], party_jobs[1] = 1002, nil;
update(3.8);
check('an unknown party job cannot prove a job absent', not last.party_known and last.party_size_known and last.party_size == 2);
party_jobs[1] = 3;
local unrelated = packet(0x020, bytes(40, { [14] = { 1, 1 }, [15] = { 99, 1 } }));
observer.on_packet(unrelated, 3.81, 1001);
check('unrelated inventory updates do not pause sampling', not update(3.82).transition);

equipped[4] = 0x0408;
items[0x0408].Extra = bytes(24, {
    [0] = { 2, 1 }, [1] = { 0x43, 1 }, [2] = { 44 + 4 * 2048, 2 }, [10] = { 142 + 9 * 2048, 2 },
});
update(4.1);
check('trial augments stop before the trial number field', last.equipment[4].augments_known and #last.equipment[4].augments == 1);
items[0x0408].Extra = '\2\3';
update(4.4);
check('short extra data is unknown and safe', last.equipment[4].augments_known == false);

local function icons(stamps)
    local fields = { [4] = { 9, 2 } };
    for i, pair in ipairs(stamps) do
        fields[8 + (i - 1) * 2] = { pair[1], 2 };
        fields[72 + (i - 1) * 4] = { pair[2], 4 };
    end
    return packet(0x063, bytes(200, fields));
end
observer.reset();
buffs = { [162] = true };
update(10);
check('a cold enchantment stays unidentified', not last.activated_items_known);
observer.on_packet(MOCK.action_packet(1001, 5, 15889, 1001, { { message = 0 } }), 10.1, 1001);
update(10.4);
check('observing one item does not identify an older enchantment', last.activated_items[15889] ~= nil and not last.activated_items_known);
observer.on_packet(icons({ { 162, 100000 }, { 162, 200000 } }), 10.5, 1001);
local old_epoch = last.effect_epochs[162];
observer.on_packet(icons({ { 162, 200000 }, { 162, 100000 } }), 13, 1001);
update(13.1);
check('duplicate enchantment icons are stable in any slot order', last.effect_epochs[162] == old_epoch and last.activated_items[15889] ~= nil);
observer.on_packet(icons({ { 162, 200060 }, { 162, 100060 } }), 13.2, 1001);
check('one second of timer rounding is not a new effect', last.effect_epochs[162] == old_epoch);
buffs = {};
update(13.5);
check('proven enchantment absence clears uncertainty', last.activated_items_known and next(last.activated_items) == nil);

observer.on_packet(MOCK.action_packet(1001, 5, 4510, 1001, { { message = 0 } }), 13.6, 1001);
buffs[251] = true;
update(13.9);
observer.on_packet(icons({ { 251, 300000 } }), 14, 1001);
observer.on_packet(merit, 14.01, 1001);
observer.on_zone(1001);
update(14.4);
check('ordinary zoning preserves matching character merits and food', last.merits[2374] == 5 and last.food and last.food.id == 4510);
observer.on_packet(icons({ { 251, 360000 } }), 16.1, 1001);
update(16.2);
check('an unexplained food timer replacement drops the old identity', last.food == nil and not last.food_known);
local sam_epoch = last.effect_epochs[321] or 0;
observer.on_packet(MOCK.action_packet(1002, 6, 123, 1001, { { message = 420, damage = 11 } }), 16.3, 1001);
check('Double-Up uses its ability id to refresh unknown rolls', last.effect_epochs[321] > sam_epoch);
observer.on_zone(2002);
update(16.6);
check('a different character cannot inherit session knowledge', next(last.merits) == nil and last.food == nil and not last.blue_spells_known);

observer.reset();
buffs = {};
items[0x0307] = { Id = 18318, Extra = zero };
update(17);
observer.on_packet(MOCK.action_packet(1001, 3, 153, 9001, { { message = 15 } }), 17.1, 1001);
update(17.4);
check('an observed relic WS waits for the actual aftermath buff', last.effects[273] == nil);
buffs[273] = true;
update(17.7);
check('observed Kaiten establishes its source-backed Store TP even on a miss', last.effects[273] and last.effects[273].store_tp == 7);
items[0x0307].Id = 17809;
update(18);
check('a weapon swap drops unsupported aftermath identity', last.effects[273] == nil);
observer.reset();
update(18.3);
check('cold aftermath cannot be inferred from its icon alone', last.effects[273] == nil);
observer.on_packet(packet(0x044, bytes(28, { [4] = { 16, 1 }, [8] = { 33, 1 }, [9] = { 128, 1 } })), 18.4, 1001);
observer.update(18.5, { main_job = 16, main_level = 75, sub_job = 1, sub_level = 37 });
check('a BLU packet arriving before job memory is not discarded', last.blue_spells_known and last.blue_spells[2] == 640);
observer.update(18.51, { main_job = 1, main_level = 75, sub_job = 16, sub_level = 37 });
check('switching BLU between main and sub needs that role spell set', not last.blue_spells_known);
observer.update(18.52, { main_job = 0, main_level = 0, sub_job = 0, sub_level = 0 });
check('unloaded job zero is missing data rather than a real job', last.main_job == nil and last.main_level == nil);

-- Duplicate effects and refreshes change speed evidence without invented spell potency.
observer.reset();
cold_icons, cold_timers = nil, nil;
update(29);
check('unloaded status memory remains unavailable', observer.info().evidence.status_source == nil);
cold_icons, cold_timers = { [0] = 214, [1] = 214 }, { [0] = 100000, [1] = 200000 };
buffs = { [214] = 2 };
update(30);
check('supported cold status memory preserves duplicate March count', last.buff_counts[214] == 2 and observer.info().evidence.status_source == 'memory');
check('generated zone rules supply a known non-Assault state', last.flags.assault == false);
local march_epoch = last.effect_epochs[214];
observer.on_packet(MOCK.action_packet(1002, 4, 386, 1001, { { message = 230, damage = 214 } }), 30.1, 1001);
update(30.4);
check('same-icon March refresh gets new evidence without guessing power', last.effect_epochs[214] > march_epoch and last.effects[214] == nil);
local slow_before = last.effect_epochs[13] or 0;
observer.on_packet(MOCK.action_packet(1002, 4, 56, 1001, { { message = 236, damage = 13 } }), 30.5, 1001);
check('a landed Slow refresh is observed', last.effect_epochs[13] > slow_before);
march_epoch = last.effect_epochs[214];
observer.on_packet(icons({ { 214, 220000 }, { 214, 100000 } }), 30.6, 1001);
check('same-count new March expiration invalidates its old evidence', last.effect_epochs[214] > march_epoch);
observer.update(30.7, { main_job = 12, main_level = 75, sub_job = 1, sub_level = 37, buffs = { [214] = true }, buff_counts = { [214] = 1 }, resting = true });
check('loadout counts and resting state reach the model', last.buff_counts[214] == 1 and last.resting);

-- Activated haste uses its displayed Haste icon, not the server-only Enchantment type.
buffs = {};
equipped[10] = 0x0510;
items[0x0510] = { Id = 15290, Extra = zero };
update(31);
observer.on_packet(MOCK.action_packet(1001, 5, 15290, 1001, { { message = 230, damage = 33 } }), 31.1, 1001);
buffs[33] = true;
update(31.4);
check('activated Haste waits for and accepts its own visible effect', last.activated_items[15290] and last.activated_items[15290].effect == 33 and last.activated_items[15290].expires_at == 211.1);
check('observed clean activated Haste is distinguished from a cold icon', last.activated_item_effects_known[33] == true);
observer.on_zone(1001);
update(31.7);
check('same-character zone keeps activated effect identity', last.activated_items[15290] ~= nil);
observer.reset();
update(32);
check('cold Haste does not prove its activated source', last.activated_item_effects_known[33] == false);

local report = observer.snapshot();
check('report excludes raw bytes and identity but keeps useful inputs', report.equipment[1].id and report.equipment[1].extra == nil and report.server_id == nil and report.name == nil and report.evidence.sampled_at == 32);
report.equipment[1].id = 0;
check('a diagnostic snapshot cannot mutate live state', observer.snapshot().equipment[1].id ~= 0);
observer.drain_events();
for n = 1, 160 do observer.on_packet(gear, 32 + n / 1000, 1001); end
local captured = observer.drain_events();
check('observation events are bounded and drained once', #captured == 128 and #observer.drain_events() == 0 and captured[1].data == nil);

-- A safe local-memory stand-in exercises the exact official pointer chain without game functions.
local ffi_before, find_before = package.loaded['ffi'], ashita.memory.find;
local memory_bytes = {};
local function put_memory(address, blob)
    for i = 1, #blob do memory_bytes[address + i - 1] = blob:byte(i); end
end
package.loaded['ffi'] = {
    os = 'Windows', cdef = function () end, new = function () return {}; end,
    cast = function (_, value) return value; end,
    string = function (buffer, size)
        local chars = {};
        for i = 0, size - 1 do chars[#chars + 1] = string.char(buffer[i]); end
        return table.concat(chars);
    end,
    C = { ReadProcessMemory = function (_, address, buffer, size, got)
        for i = 0, size - 1 do
            if (memory_bytes[address + i] == nil) then return 0; end
            buffer[i] = memory_bytes[address + i];
        end
        got[0] = size;
        return 1;
    end },
};
ashita.memory.find = function (_, _, _, _, occurrence) return occurrence == 0 and 0x11000 or 0; end;
AshitaCore.GetPointerManager = function () return { Get = function () return 0x12000; end }; end;
stats.GetIsZoning = function () return 0; end;
stats.HasSpell = function () return true; end;
put_memory(0x11000, bytes(4, { [0] = { 0x20000, 4 } }));
put_memory(0x12000, bytes(4, { [0] = { 0x13000, 4 } }));
put_memory(0x13000, bytes(4, { [0] = { 0x200000, 4 } }));
put_memory(0x220000, bytes(24, { [0] = { 16, 1 }, [4] = { 33, 1 }, [5] = { 128, 1 } }));
observer.reset();
local blu = { main_job = 16, main_level = 75, sub_job = 1, sub_level = 37, buffs = {} };
observer.update(40, blu);
check('a cold BLU buffer needs stable validation', not last.blue_spells_known and observer.info().evidence.blue_status == 'confirming BLU buffer');
observer.update(41.1, blu);
check('a validated read-only BLU buffer stays provisional', not last.blue_spells_known and last.blue_spells[1] == 545 and last.blue_spells[2] == 640 and observer.info().evidence.blue_source == 'memory' and observer.info().evidence.blue_status == 'provisional');
observer.drain_events();
observer.update(42.2, blu);
check('the same provisional BLU candidate does not repeat events', #observer.drain_events() == 0);
observer.reset();
put_memory(0x220000, bytes(24, { [0] = { 18, 1 }, [4] = { 33, 1 } }));
observer.update(42, blu);
observer.update(43.1, blu);
check('a stale job header cannot become a BLU allocation', not last.blue_spells_known);
observer.reset();
put_memory(0x220000, bytes(24, { [0] = { 16, 1 }, [4] = { 33, 1 }, [5] = { 33, 1 } }));
observer.update(44, blu);
check('invalid duplicate spells leave cold BLU unknown', not last.blue_spells_known);
observer.reset();
memory_bytes[0x13000] = nil;
observer.update(45, blu);
check('unreadable client pages safely leave cold BLU unknown', not last.blue_spells_known);
observer.reset();
ashita.memory.find = nil;
observer.update(45.3, blu);
check('a missing signature API safely leaves cold BLU unknown', not last.blue_spells_known and observer.info().evidence.blue_status == 'BLU signature reader unavailable');
package.loaded['ffi'], ashita.memory.find = ffi_before, find_before;
observer.on_packet(packet(0x00A, bytes(0x70, { [4] = { 1001, 4 }, [0x30] = { 69, 2 }, [0x3C] = { 3455, 4 }, [0x68] = { 5, 2 } })), 46, 1001);
observer.on_zone(1001);
group.GetMemberZone = function () return 69; end;
update(46.2);
check('normal zone packet bootstraps day weather and Assault', last.day == 0 and last.hour == 23 and last.weather == 5 and last.flags.assault == true);
update(47.2);
check('Vana day boundaries advance without a request or native time function', last.day == 1 and last.hour == 0);

-- Polls still observe every input, but unchanged observations reuse the arithmetic.
observer.reset(); buffs={}; cold_icons,cold_timers=nil,nil;
update(50);
local cached, count_before, reads_before = observer.info(), calculations, reads;
for _, now in ipairs({50.3,50.6,50.9,51.2,51.5}) do update(now); end
check('unchanged polls reuse the full modifier model', observer.info()==cached and calculations==count_before);
check('unchanged caching does not skip gear polls or evidence refresh', reads==reads_before+80 and cached.evidence.sampled_at==51.5);
observer.on_vitals(51.51,499,19,301,1000,100); update(51.52);
check('vital-dependent latents rebuild immediately',calculations==count_before+1);
count_before=calculations;
observer.on_packet(packet(0x057,bytes(10,{[8]={6,1}})),51.53,1001);update(51.54);
check('weather packets invalidate without waiting for the next poll',calculations==count_before+1);
count_before=calculations;
buffs[13]=true;
local context=observer.effect_context(51.55,{main_job=12,main_level=75,sub_job=1,sub_level=37});
check('own cast context refreshes current buffs between polls',context.buffs[13] and calculations==count_before+1 and context.equipment_known);
context.buffs[13]=nil; context.equipment[1].id=1;
check('own cast context is detached from the model inputs',last.buffs[13] and last.equipment[0].id~=1);
observer.on_packet(packet(0x050,bytes(8)),51.56,1001);
context=observer.effect_context(51.57,{main_job=12,main_level=75,sub_job=1,sub_level=37});
check('forced cast reads respect pending equipment',not context.equipment_known and observer.info().transition);
count_before=calculations;
items[0x0408]={Id=15889,Extra=extra};
update(51.9);
check('a settled equipment change rebuilds the model',calculations==count_before+1 and not observer.info().transition);
count_before=calculations;party_jobs[1]=4;update(52.2);
check('party composition invalidates cached conditions',calculations==count_before+1);

live = false;
package.loaded['core.stat_state'] = nil;
observer = require('core.stat_state');
check('missing client memory is safe', pcall(observer.update, 20, {}) and last.equipment_known == false);
check('nothing queues commands or packets', commands == 0);

out[#out + 1] = fails == 0 and 'ALL OK' or (fails .. ' FAILED');
return table.concat(out, '\n');
