-- Known TP and resting modifiers. Unknown inputs stay unknown until packets or real gains fill them in.
local data = require('data.phoenix_modifiers');
local modifiers = {};
local effects = data.effect_ids;

local fields = {};
for field, mod in pairs(data.mod_ids) do fields[mod] = field; end
local domains = {
    [71] = { 'mp' }, [72] = { 'hp' }, [73] = { 'tp' }, [173] = { 'tp', 'delay' },
    [259] = { 'tp', 'delay' }, [295] = { 'mp' }, [380] = { 'tp', 'delay' }, [488] = { 'tp' },
    [167] = { 'delay' }, [171] = { 'delay' }, [217] = { 'delay' }, [383] = { 'delay' }, [384] = { 'delay' }, [906] = { 'delay' },
    [369] = { 'refresh' }, [370] = { 'regen' }, [404] = { 'regen' }, [405] = { 'refresh' },
};
for mod in pairs(fields) do
    if (domains[mod] == nil) then domains[mod] = { 'rounds' }; end
end

local effect_specs = {
    { 'samurai_roll', 73, 1 }, { 'store_tp', 73, 1 }, { 'healers_roll', 71, 1 },
    { 'aftermath', 73, nil }, { 'bust', 73, nil }, { 'inhibit_tp', 488, 1 },
    { 'arcane_crest', 73, -1 }, { 'dragon_breaker', 73, -1 }, { 'sepulcher', 73, -1 },
};
local speed_effects = {
    { 'haste', 167, 1465 }, { 'march', 167, 600 }, { 'slow', 167, -1800 }, { 'elegy', 167, -2500 },
    { 'weakness', 167, -10000, true }, { 'hasso', 217, 1000, true }, { 'spirit_surge', 167, 2500, true },
};

-- These effect routes do not change between stat snapshots.
local handled = {};
for _, list in ipairs({ effect_specs, speed_effects,
    { { 'spirit_surge', 383 }, { 'last_resort', 217 }, { 'regen', 370 }, { 'refresh', 369 } } }) do
    for _, spec in ipairs(list) do
        local id = effects[spec[1]];
        if (id ~= nil) then
            handled[id] = handled[id] or {};
            handled[id][spec[2]] = true;
        end
    end
end

local function sorted_values(values)
    local result = {};
    for value in pairs(values) do
        result[#result + 1] = value;
    end
    table.sort(result);
    return result;
end

local function identity(value)
    if (type(value) == 'string') then
        local hash = 0;
        for index = 1, #value do hash = (hash * 131 + value:byte(index)) % 2147483647; end
        return ('bytes%d-%d'):format(#value, hash);
    end
    if (type(value) ~= 'table') then
        return tostring(value or '?');
    end
    local result = {};
    for key, part in pairs(value) do
        result[#result + 1] = tostring(key) .. '=' .. identity(part);
    end
    table.sort(result);
    return table.concat(result, ',');
end

local function has(buffset, id)
    return id ~= nil and buffset[id] == true;
end

local function effective_weather(snapshot, buffs)
    local flags = snapshot.flags or {};
    if (flags.weather ~= nil) then return flags.weather; end
    local storm;
    for _, entry in ipairs({ { 'firestorm', 4 }, { 'rainstorm', 6 }, { 'sandstorm', 8 }, { 'windstorm', 10 },
        { 'hailstorm', 12 }, { 'thunderstorm', 14 }, { 'aurorastorm', 16 }, { 'voidstorm', 18 } }) do
        if (has(buffs, effects[entry[1]])) then storm = entry[2]; end
    end
    if (storm == nil) then return snapshot.weather; end
    if (snapshot.weather == nil) then return nil; end
    if (snapshot.weather == storm or snapshot.weather == storm + 1) then return storm + 1; end
    return storm;
end

local function weather_element(snapshot, buffs)
    if ((snapshot.flags or {}).weather_element ~= nil) then return snapshot.flags.weather_element; end
    local weather = effective_weather(snapshot, buffs);
    if (weather == nil) then return nil; end
    return data.weather_elements[weather] or 0;
end

local function latent_active(latent, snapshot, buffs, sub_job, slot)
    local condition, param = latent.condition, latent.param;
    local flags = snapshot.flags or {};
    if (condition >= 0 and condition <= 3) then
        local percent = snapshot.hp_percent;
        if (snapshot.hp ~= nil and snapshot.max_hp ~= nil and snapshot.max_hp > 0) then
            percent = snapshot.hp * 100 / snapshot.max_hp;
        end
        if (percent == nil) then return nil; end
        if (condition >= 2 and snapshot.tp == nil) then return nil; end
        if (condition >= 2 and snapshot.tp >= 1000) then return false; end
        return (condition % 2 == 0 and percent <= param) or (condition % 2 == 1 and percent >= param);
    elseif (condition == 4) then
        if (snapshot.mp == nil or snapshot.max_mp == nil) then return nil; end
        return snapshot.max_mp > 0 and snapshot.mp * 100 / snapshot.max_mp <= param;
    elseif (condition == 5) then
        if (snapshot.mp == nil) then return nil; end
        return snapshot.mp <= param;
    elseif (condition == 6 or condition == 7) then
        if (snapshot.tp == nil) then return nil; end
        return condition == 6 and snapshot.tp < param or condition == 7 and snapshot.tp > param;
    elseif (condition == 8) then
        return sub_job == param;
    elseif (condition == 9) then
        if (snapshot.pet_present == false) then return false; end
        if (snapshot.pet_id == nil) then return nil; end
        return snapshot.pet_id == param;
    elseif (condition == 10 or condition == 11) then
        if (snapshot.engaged == nil) then return nil; end
        return snapshot.engaged == (condition == 10);
    elseif (condition == 13) then
        return has(buffs, param);
    elseif (condition == 14) then
        return not has(buffs, effects.food);
    elseif (condition == 15 or condition == 16) then
        local size = condition == 15 and snapshot.party_size or snapshot.party_in_zone;
        local known = condition == 15 and snapshot.party_size_known or snapshot.party_in_zone_known;
        if (size == nil or known == false) then return nil; end
        -- Party updates use equality; equipment updates use >= in this source revision.
        if (condition == 16 and size > param) then return nil; end
        return size >= param;
    elseif (condition == 25) then
        if (snapshot.buffs_known == false) then return nil; end
        for id in pairs(data.song_roll_effects or {}) do if (has(buffs, id)) then return true; end end
        return false;
    elseif (condition == 26 or condition == 27 or condition == 39) then
        local hour = snapshot.vana_hour or snapshot.hour;
        if (hour == nil) then return nil; end
        if (condition == 39) then
            if (hour < 20 or hour >= 24) then return false; end
            return param == 0 and (snapshot.main_level or 0) % 2 == 1 or param > 0 and (snapshot.main_level or 0) % param == 0;
        elseif (condition == 26) then
            if (param == 0) then return hour >= 6 and hour < 18; end
            if (param == 1) then return hour >= 18 or hour < 6; end
            if (param == 2) then return hour >= 17 or hour < 7; end
        else
            if (param == 1) then return hour == 4; end
            if (param == 2) then return hour >= 6 and hour < 7; end
            if (param == 3) then return hour >= 7 and hour < 17; end
            if (param == 4) then return hour >= 16 and hour < 18; end
            if (param == 5) then return hour >= 18 and hour < 20; end
            if (param == 6) then return hour >= 20 or hour < 4; end
        end
    elseif (condition >= 28 and condition <= 36 and condition ~= 33) then
        local day = snapshot.vana_day or snapshot.day;
        if (day == nil) then return nil; end
        return day == ({ [28] = 0, [29] = 1, [30] = 2, [31] = 3, [32] = 7, [34] = 4, [35] = 5, [36] = 6 })[condition];
    elseif (condition == 37) then
        local phase, direction = snapshot.moon_phase, snapshot.moon_direction;
        if (phase == nil or direction == nil) then return nil; end
        if (param == 0) then return phase <= 5 or (phase <= 10 and direction == 1); end
        if (param == 1) then return phase >= 7 and phase <= 38 and direction == 2; end
        if (param == 2) then return phase >= 40 and phase <= 55 and direction == 2; end
        if (param == 3) then return phase >= 57 and phase <= 88 and direction == 2; end
        if (param == 4) then return phase >= 95 or (phase >= 90 and direction == 2); end
        if (param == 5) then return phase >= 62 and phase <= 93 and direction == 1; end
        if (param == 6) then return phase >= 45 and phase <= 60 and direction == 1; end
        if (param == 7) then return phase >= 12 and phase <= 43 and direction == 1; end
    elseif (condition == 38) then
        return param == 0 and (snapshot.main_level or 0) % 2 == 1 or param > 0 and (snapshot.main_level or 0) % param == 0;
    elseif (condition == 22) then
        -- The server checks other party members, excluding the wearer.
        local jobs = snapshot.another_party_jobs;
        if (jobs == nil) then return nil; end
        if (jobs[param] == true or (type(jobs[param]) == 'number' and jobs[param] > 0)) then return true; end
        if (snapshot.party_known == false) then return nil; end
        return false;
    elseif (condition == 23) then
        if (snapshot.zone == nil) then return nil; end
        return snapshot.zone == param;
    elseif (condition == 40) then
        return slot == param;
    elseif (condition == 41) then
        return false;
    elseif (condition == 42) then
        local weather = effective_weather(snapshot, buffs);
        if (weather == nil) then return nil; end
        return weather == param;
    elseif (condition == 48) then
        if (flags.dynamis ~= nil) then return flags.dynamis; end
        return (data.zone_dynamis or {})[snapshot.zone];
    elseif (condition == 44) then
        if (snapshot.nation == nil) then return nil; end
        return snapshot.nation == param;
    elseif (condition == 49) then
        if (not has(buffs, effects.food)) then return false; end
        if (snapshot.food == nil) then return nil; end
        return snapshot.food.id == param;
    elseif (condition == 50) then
        return (snapshot.main_level or 0) < param;
    elseif (condition == 51) then
        return (snapshot.main_level or 0) >= param;
    elseif (condition == 52) then
        local element = weather_element(snapshot, buffs);
        if (element == nil) then return nil; end
        return element == param;
    elseif (condition == 55 or condition == 56) then
        if (condition == 56 and snapshot.engaged == false) then return false; end
        if (snapshot.mp == nil or (condition == 56 and snapshot.engaged == nil)) then return nil; end
        return condition == 55 and snapshot.mp >= param or condition == 56 and snapshot.mp > param;
    elseif (condition == 58) then
        if (flags.assault ~= nil) then return flags.assault; end
        return (data.zone_assault or {})[snapshot.zone];
    elseif (condition == 62) then
        if (snapshot.main_job == nil) then return nil; end
        return snapshot.main_job == param;
    elseif (condition == 64) then
        if ((snapshot.main_level or 0) < param) then return false; end
        return flags.garrison;
    end
    return nil;
end

-- equipment uses slots 0..15; mods use Phoenix numeric IDs; raw augments are { id, value } records.
function modifiers.calculate(snapshot)
    snapshot = snapshot or {};
    local buffs = snapshot.buffs or {};
    local totals = {};
    local unknown = {};
    local unknown_keys = { tp = {}, hp = {}, mp = {}, delay = {}, rounds = {}, regen = {}, refresh = {} };
    local result = { tp_known = true, hp_known = true, mp_known = true, delay_known = true,
        rounds_known = true, regen_known = true, refresh_known = true, contributions = {}, unknown_sources = {} };
    local source = { kind = 'input' };
    local missing_rows = {};
    local function from(kind, id, name, condition)
        source = { kind = kind, id = id, name = name, condition = condition };
    end
    for _, field in pairs(fields) do totals[field] = 0; end

    local function missing(mod, reason, key)
        unknown[reason] = true;
        local row_key = mod .. ':' .. reason .. ':' .. (key or '') .. ':' .. tostring(source.id or '');
        if (not missing_rows[row_key]) then
            result.unknown_sources[#result.unknown_sources + 1] = { kind = source.kind, id = source.id,
                name = source.name, condition = source.condition, field = fields[mod], reason = reason, key = key };
            missing_rows[row_key] = true;
        end
        for _, domain in ipairs(domains[mod]) do
            result[domain .. '_known'] = false;
            unknown_keys[domain][reason .. ':' .. (key or '')] = true;
        end
    end
    local function add(mod, amount, estimated)
        if (fields[mod] ~= nil and type(amount) == 'number') then
            totals[fields[mod]] = totals[fields[mod]] + amount;
            if (amount ~= 0) then
                result.contributions[#result.contributions + 1] = { kind = source.kind, id = source.id,
                    name = source.name, condition = source.condition, field = fields[mod], value = amount, estimated = estimated == true };
            end
        end
    end
    local function add_mods(mods)
        for mod, amount in pairs(mods or {}) do add(tonumber(mod), amount); end
    end
    local main_job, main_level = snapshot.main_job or 0, snapshot.main_level or 0;
    local sub_job, sub_level = snapshot.sub_job or 0, snapshot.sub_level or 0;
    if (has(buffs, effects.sj_restriction) or has(buffs, effects.obliviscence)) then
        sub_job, sub_level = 0, 0;
    elseif (snapshot.sub_job == nil or snapshot.sub_level == nil) then
        for _, mod in ipairs({ 71, 73, 173, 25, 369, 370 }) do missing(mod, 'subjob unavailable'); end
    end
    if (snapshot.main_job == nil or snapshot.main_level == nil) then
        for _, mod in ipairs({ 71, 72, 73, 173, 25, 369, 370 }) do missing(mod, 'job unavailable'); end
    end
    if (snapshot.buffs == nil or snapshot.buffs_known == false) then
        for _, mod in ipairs({ 71, 72, 73, 173, 25, 369, 370 }) do missing(mod, 'buffs unavailable'); end
    end

    local best_traits = {};
    local function choose(trait)
        local previous = best_traits[trait.trait];
        if (previous == nil or trait.rank > previous.rank) then
            best_traits[trait.trait] = trait;
        end
    end
    for _, trait in ipairs(data.traits) do
        if ((trait.job == main_job and main_level >= trait.level) or (trait.job == sub_job and sub_level >= trait.level)) then
            choose(trait);
        end
    end
    local blue = { status = 'inactive', active = false, level = 0, spells = {}, traits = {}, direct_contributions = {} };
    result.blue_magic = blue;
    if (main_job == 16 or sub_job == 16) then
        local blue_level = main_job == 16 and main_level or sub_level;
        local known = snapshot.blue_spells ~= nil and snapshot.blue_spells_known ~= false;
        blue.role, blue.level, blue.active = main_job == 16 and 'main' or 'sub', blue_level, true;
        blue.status = known and 'confirmed' or (snapshot.blue_spells ~= nil and #snapshot.blue_spells > 0 and 'provisional' or 'unknown');
        local function contributions(mods)
            local rows = {};
            for mod, value in pairs(mods or {}) do
                rows[#rows + 1] = { field = fields[mod], value = value };
            end
            table.sort(rows, function(a, b) return a.field < b.field; end);
            return rows;
        end
        local points, seen = {}, {};
        for _, spell_id in ipairs(snapshot.blue_spells or {}) do
            local spell = data.blue_spells[spell_id];
            if (not seen[spell_id]) then
                seen[spell_id] = true;
                local eligible = spell ~= nil and spell.level <= blue_level;
                local mods = contributions(spell and spell.mods);
                blue.spells[#blue.spells + 1] = { id = spell_id, name = spell and spell.name or ('Spell ' .. spell_id),
                    level = spell and spell.level, eligible = eligible, contributions = mods };
                if (eligible) then
                    points[spell.category] = (points[spell.category] or 0) + spell.weight;
                    from('blue_spell', spell_id, spell.name);
                    if (known) then add_mods(spell.mods); end
                    for _, row in ipairs(mods) do
                        blue.direct_contributions[#blue.direct_contributions + 1] = { id = spell_id, name = spell.name,
                            field = row.field, value = row.value, applied = known };
                    end
                end
            end
        end
        if (not known) then
            local possible_points = {};
            for _, spell in pairs(data.blue_spells) do
                if (spell.level <= blue_level) then
                    possible_points[spell.category] = (possible_points[spell.category] or 0) + spell.weight;
                    from('blue_spell', nil, 'Blue Magic');
                    for mod in pairs(spell.mods or {}) do missing(mod, 'blue spells unavailable'); end
                end
            end
            for _, trait in ipairs(data.blue_traits) do
                local previous = best_traits[trait.trait];
                if ((possible_points[trait.category] or 0) >= trait.points and (previous == nil or previous.rank < trait.rank)) then
                    from('blue_trait', trait.trait, trait.name);
                    for mod in pairs(trait.mods) do missing(mod, 'blue spells unavailable'); end
                end
            end
        end
        local achieved = {};
        for _, trait in ipairs(data.blue_traits) do
            if ((points[trait.category] or 0) >= trait.points) then
                local previous = achieved[trait.trait];
                if (previous == nil or previous.rank < trait.rank) then achieved[trait.trait] = trait; end
                if (known) then choose(trait); end
            end
        end
        for _, trait in ipairs(data.blue_traits) do
            if (achieved[trait.trait] == trait) then
                local effective = best_traits[trait.trait];
                blue.traits[#blue.traits + 1] = { id = trait.trait, name = trait.name, rank = trait.rank,
                    tier = math.max(1, trait.rank), category = trait.category, points = points[trait.category], required = trait.points,
                    applied = known and effective == trait,
                    overridden = effective ~= nil and effective ~= trait and effective.rank >= trait.rank,
                    contributions = contributions(trait.mods) };
            end
        end
    end
    for _, trait in pairs(best_traits) do
        from(trait.category ~= nil and 'blue_trait' or 'trait', trait.trait, trait.name or ('trait ' .. trait.trait), 'rank ' .. trait.rank);
        add_mods(trait.mods);
    end

    if (main_job == 12 and main_level >= 75) then
        from('merit', data.merit_ids.store_tp, 'Store TP');
        local count = snapshot.merits and snapshot.merits[data.merit_ids.store_tp];
        if (count == nil) then
            missing(73, 'Store TP merits unavailable');
        else
            add(73, 2 * math.max(0, math.min(5, count)));
        end
    end
    local rounds_merit;
    if (main_level >= 75 and (main_job == 1 or main_job == 12)) then
        local id = main_job == 1 and data.merit_ids.double_attack or data.merit_ids.ikishoten;
        local count = snapshot.merits and snapshot.merits[id];
        from('merit', id, main_job == 1 and 'Double Attack' or 'Ikishoten');
        rounds_merit = tostring(id) .. '/' .. tostring(count or '?');
        if (count == nil) then missing(288, 'attack merits unavailable', tostring(id));
        elseif (main_job == 1) then add(288, math.max(0, math.min(5, count))); end
    end

    local equipped, equipped_counts = {}, {};
    for slot = 0, 15 do
        local worn = (snapshot.equipment or {})[slot];
        if (worn ~= nil and (worn.id or 0) > 0) then
            local item = data.items[worn.id];
            from('equipment', worn.id, item and item.name);
            local required = data.levels[worn.id];
            local allowed = required ~= nil and main_level >= required;
            equipped[worn.id] = allowed;
            if (allowed) then equipped_counts[worn.id] = (equipped_counts[worn.id] or 0) + 1; end
            if (allowed) then
                if (item ~= nil) then
                    add_mods(item.mods);
                    for _, latent in ipairs(item.latents) do
                        from('latent', worn.id, item.name, latent.condition .. '/' .. latent.param);
                        local active = latent_active(latent, snapshot, buffs, sub_job, slot);
                        if (active == nil) then
                            missing(latent.mod, 'item latent unavailable', worn.id .. '/' .. latent.condition .. '/' .. latent.param);
                        elseif (active) then
                            add(latent.mod, latent.value);
                        end
                    end
                end
                from('augment', worn.id, item and item.name);
                add_mods(worn.augment_mods);
                if (worn.augment_mods == nil) then
                    for _, augment in ipairs(worn.augments or {}) do
                        local definitions = data.augments[augment.id];
                        for _, definition in ipairs(definitions or {}) do
                            local value = augment.value or 0;
                            local base = definition.base;
                            add(definition.mod, (base > 0 and (base + value) or (base - value)) * definition.multiplier);
                        end
                        if (augment.id ~= 0 and not data.augment_ids[augment.id]) then
                            for _, mod in ipairs({ 71, 72, 73, 173, 25, 369, 370 }) do
                                missing(mod, 'augment unavailable', worn.id .. '/' .. augment.id .. '/' .. (augment.value or 0));
                            end
                        end
                    end
                end
            end
            if (not allowed and item ~= nil) then
                for mod in pairs(item.mods) do
                    if (domains[mod][1] == 'rounds') then missing(mod, 'level-synced accuracy or attacks', tostring(worn.id)); end
                end
            end
            if (required == nil or (allowed and worn.augments_known == false)) then
                for _, mod in ipairs({ 71, 72, 73, 173, 25, 369, 370 }) do
                    missing(mod, required == nil and 'equipment unavailable' or 'augment format unavailable', worn.id .. '/' .. identity(worn.extra));
                end
            end
        end
    end
    if (snapshot.equipment == nil or snapshot.equipment_known == false) then
        from('input');
        for _, mod in ipairs({ 71, 72, 73, 173, 25, 369, 370 }) do missing(mod, 'equipment unavailable'); end
    end
    for _, set in ipairs(data.sets) do
        local count = 0;
        for _, id in ipairs(set.items) do
            count = count + (equipped_counts[id] or 0);
        end
        if (count >= set.minimum) then
            from('set', set.id, 'equipment set ' .. set.id, count .. ' pieces');
            local index = math.min(count, set.maximum) - set.minimum + 1;
            for mod, values in pairs(set.mods) do add(mod, values[math.min(index, #values)]); end
        end
    end

    if (has(buffs, effects.food)) then
        local food = snapshot.food;
        local record = food and data.foods[food.id];
        from('food', food and food.id, record and record.name);
        if (food and food.power ~= nil and (food.id == nil or food.id == 0)) then
            if (food.power == 4) then add(73, 5); end
        elseif (record == nil) then
            for _, mod in ipairs({ 71, 72, 73, 25, 369, 370 }) do
                missing(mod, 'food unavailable', food and tostring(food.id) or identity((snapshot.effect_epochs or {})[effects.food]));
            end
        else
            add_mods(record.mods);
            for mod, values in pairs(record.party_mods) do
                if (food.party_size == nil) then
                    missing(mod, 'food party size unavailable', tostring(food.id));
                else
                    local index = food.party_size >= 4 and 1 or ((#values == 3 and food.party_size >= 2) and 2 or #values);
                    add(mod, values[index]);
                end
            end
        end
    end

    for _, spec in ipairs(effect_specs) do
        local id, mod = effects[spec[1]], spec[2];
        if (has(buffs, id)) then
            from('effect', id, spec[1]);
            local known = (snapshot.effects or {})[id];
            local value = known and (known[fields[mod]] or (known.mods or {})[mod]);
            if (value == nil and known and known.power ~= nil and spec[3] ~= nil) then
                value = known.power * spec[3];
            end
            if (value == nil) then
                missing(mod, spec[1] .. ' strength unavailable', identity((snapshot.effect_epochs or {})[id] or (known and known.key)));
            else
                add(mod, value);
            end
        end
    end

    local activated_counts = {};
    for item_id, active in pairs(snapshot.activated_items or {}) do
        local record = data.activated_items[item_id];
        local icon = record and (record.effect or effects.enchantment);
        local expired = type(active) == 'table' and active.expires_at ~= nil and snapshot.now ~= nil and active.expires_at <= snapshot.now;
        if (record and has(buffs, icon) and not expired and (not record.remove_on_unequip or equipped[item_id])) then
            from('activated', item_id, record.name);
            add_mods(record.mods);
            activated_counts[icon] = (activated_counts[icon] or 0) + 1;
        end
    end
    if (has(buffs, effects.enchantment) and ((activated_counts[effects.enchantment] or 0) == 0 or snapshot.activated_items_known == false)) then
        from('effect', effects.enchantment, 'unidentified enchantment');
        for _, mod in ipairs({ 71, 72, 25, 369, 370 }) do
            missing(mod, 'enchantment unavailable', identity((snapshot.effect_epochs or {})[effects.enchantment]));
        end
    end

    -- Item enchantments can share a spell icon. Only the unaccounted icons need a spell estimate.
    for _, spec in ipairs(speed_effects) do
        local id, mod = effects[spec[1]], spec[2];
        if (has(buffs, id)) then
            from('effect', id, spec[1]);
            local known = (snapshot.effects or {})[id];
            local value = known and (known[fields[mod]] or (known.mods or {})[mod]);
            local count = (snapshot.buff_counts or {})[id] or 1;
            local remaining = math.max(0, count - (activated_counts[id] or 0));
            if (value ~= nil) then
                add(mod, value);
            elseif (remaining > 0) then
                add(mod, spec[3] * remaining, not spec[4]);
                if (not spec[4]) then missing(mod, spec[1] .. ' strength unavailable', identity((snapshot.effect_epochs or {})[id])); end
            end
            if ((snapshot.activated_item_effects_known or {})[id] == false) then
                missing(mod, spec[1] .. ' item source unavailable', identity((snapshot.effect_epochs or {})[id]));
            end
        end
    end
    if (has(buffs, effects.last_resort)) then
        from('effect', effects.last_resort, 'Last Resort');
        local merit = 0;
        if (main_job == 8 and main_level >= 75) then
            local count = snapshot.merits and snapshot.merits[data.merit_ids.desperate_blows];
            if (count == nil) then missing(217, 'Desperate Blows merits unavailable');
            else merit = 500 * math.max(0, math.min(3, count)); end
        end
        add(217, totals.desperate_blows + merit);
    end
    if (has(buffs, effects.aftermath)) then
        from('effect', effects.aftermath, 'aftermath');
        local known = (snapshot.effects or {})[effects.aftermath];
        if (known and known.mods) then
            for mod, value in pairs(known.mods) do if (mod ~= 73) then add(mod, value); end end
        else
            for _, mod in ipairs({ 384, 369, 370, 25 }) do
                missing(mod, 'aftermath source unavailable', identity((snapshot.effect_epochs or {})[effects.aftermath]));
            end
        end
    end
    for _, spec in ipairs({ { 'regen', 370 }, { 'refresh', 369 } }) do
        local id, mod = effects[spec[1]], spec[2];
        if (has(buffs, id)) then
            from('effect', id, spec[1]);
            local known = (snapshot.effects or {})[id];
            local value = known and (known[fields[mod]] or (known.mods or {})[mod]);
            local remaining = math.max(0, ((snapshot.buff_counts or {})[id] or 1) - (activated_counts[id] or 0));
            if (value ~= nil) then add(mod, value);
            elseif (remaining > 0 or (snapshot.activated_item_effects_known or {})[id] == false) then
                missing(mod, spec[1] .. ' strength unavailable', identity((snapshot.effect_epochs or {})[id]));
            end
        end
    end
    -- Other visible effects can change the same totals. Their icon alone gives no strength.
    for id, record in pairs(data.effect_mods or {}) do
        if (has(buffs, id) and id ~= effects.aftermath and id ~= effects.enchantment and id ~= effects.food) then
            from('effect', id, record.name);
            local known = (snapshot.effects or {})[id];
            for mod in pairs(record.mods) do
                if (not (handled[id] or {})[mod]) then
                    local value = known and (known[fields[mod]] or (known.mods or {})[mod]);
                    if (value ~= nil) then add(mod, value);
                    else missing(mod, record.name .. ' strength unavailable', identity((snapshot.effect_epochs or {})[id])); end
                end
            end
        end
    end
    from('input');
    if (snapshot.pet_present ~= false and snapshot.pet_id == nil and (main_job == 15 or sub_job == 15)) then
        missing(369, 'avatar perpetuation unavailable');
    elseif (snapshot.pet_present ~= false and snapshot.pet_id and snapshot.pet_id >= 0 and snapshot.pet_id < 21) then
        missing(369, 'avatar perpetuation unavailable', tostring(snapshot.pet_id));
    end

    local region = snapshot.region or data.zone_regions[snapshot.zone];
    local boosted = false;
    local region_needed = has(buffs, effects.signet) or has(buffs, effects.sigil);
    if (region_needed and region == nil) then
        missing(72, 'Signet region unavailable', tostring(snapshot.zone or '?'));
    elseif (region ~= nil) then
        boosted = (has(buffs, effects.signet) and region <= 27) or (has(buffs, effects.sigil) and region >= 33 and region <= 40);
    end
    for field, value in pairs(totals) do result[field] = value; end
    result.hp_base = 10 + result.hp_heal;
    result.hp_step = 1;
    result.mp_base = 12 + result.mp_heal;
    result.mp_step = 1 + result.clear_mind;
    if (boosted) then
        result.hp_base = result.hp_base + 3 * math.floor(main_level / 10);
        if (snapshot.max_hp == nil) then
            missing(72, 'maximum HP unavailable');
        else
            result.hp_step = 1 + math.floor(snapshot.max_hp / 300);
        end
    end
    result.signet_recovery = boosted;
    result.unknown = sorted_values(unknown);
    result.passive_hp = math.max(0, result.regen) - result.regen_down;
    result.passive_mp = math.max(0, result.refresh) - result.refresh_down;
    local function key_for(domain)
        local parts = {};
        for mod, field in pairs(fields) do
            for _, affects in ipairs(domains[mod]) do
                if (affects == domain) then parts[#parts + 1] = mod .. '=' .. tostring(result[field]); end
            end
        end
        table.sort(parts);
        return table.concat(parts, '/') .. ':' .. table.concat(sorted_values(unknown_keys[domain]), '|');
    end
    result.delay_key = key_for('delay');
    for _, name in ipairs({ 'haste', 'march', 'slow', 'elegy' }) do
        local id = effects[name];
        if (has(buffs, id)) then
            result.delay_key = result.delay_key .. ':' .. id .. '/' .. tostring((snapshot.buff_counts or {})[id] or 1)
                .. '/' .. tostring((snapshot.effect_epochs or {})[id] or 0);
        end
    end
    result.tp_key = key_for('tp');
    result.rounds_key = key_for('rounds');
    if (rounds_merit ~= nil) then result.rounds_key = result.rounds_key .. ':merit/' .. rounds_merit; end
    for _, name in ipairs({ 'blindness', 'accuracy_boost', 'accuracy_down', 'aggressor', 'focus', 'footwork', 'fighters_roll', 'hunters_roll', 'madrigal', 'hasso' }) do
        local id = effects[name];
        if (has(buffs, id)) then result.rounds_key = result.rounds_key .. ':' .. id .. '/' .. tostring((snapshot.effect_epochs or {})[id] or 0); end
    end
    result.resting_key = ('%s/%s/%s/%s:%s:%s:%s:%s'):format(result.hp_base, result.hp_step, result.mp_base, result.mp_step,
        key_for('hp'), key_for('mp'), key_for('regen'), key_for('refresh'));
    return result;
end

modifiers.data = data;
return modifiers;
