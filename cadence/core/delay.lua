--[[
    Works out your auto attack delay the way the server does in LSB CBattleEntity::GetWeaponDelay.
    It starts from your weapons, known gear modifiers, job traits and haste buffs.

    Known gear includes haste and slow, delay changes and conditional bonuses. Unidentified effects
    still start from a guess. Your real attacks teach the timer what those gaps actually are.
]]

local delay = {};

-- Delay is counted in 1/60 s units. An empty main hand attacks like a 480 delay weapon.
local UNARMED_DELAY = 480;

-- The client item data stores hand-to-hand delay 240 lower than the server does.
local H2H_CLIENT_OFFSET = 240;

local SKILL_HAND_TO_HAND = 1;
local TWO_HANDED     = { [4] = true, [6] = true, [7] = true, [8] = true, [10] = true, [12] = true };
local DUAL_WIELDABLE = { [2] = true, [3] = true, [5] = true, [9] = true, [11] = true };

local JOB_WAR = 1;
local JOB_MNK = 2;
local JOB_THF = 6;
local JOB_SAM = 12;
local JOB_NIN = 13;
local JOB_PUP = 18;
local JOB_DNC = 19;

-- Jobs with a hand-to-hand skill rank (sql/skill_ranks.sql).
local HAND_TO_HAND_JOBS = {
    [JOB_WAR] = true, [JOB_MNK] = true, [JOB_THF] = true, [JOB_NIN] = true, [JOB_PUP] = true, [JOB_DNC] = true,
};

-- Trait ranks as { level, value }, highest first (sql/traits.sql, era rows only).
-- The best rank from your main or sub job applies.
local MARTIAL_ARTS = {
    [JOB_MNK] = { { 75, 180 }, { 61, 160 }, { 46, 140 }, { 31, 120 }, { 16, 100 }, { 1, 80 } },
    [JOB_PUP] = { { 75, 120 }, { 50, 100 }, { 25, 80 } },
};
local DUAL_WIELD = {
    [JOB_NIN] = { { 65, 30 }, { 45, 25 }, { 25, 15 }, { 10, 10 } },
};
local STORE_TP = {
    [JOB_SAM] = { { 70, 25 }, { 50, 20 }, { 30, 15 }, { 10, 10 } },
};

-- The shortest delays the server works out TP from, for each fist and for one bare-handed attack.
local SHORTEST_TP_DELAY         = 48;
local SHORTEST_UNARMED_TP_DELAY = 96;

-- Buffs the client can see and how much delay they take off. Negative values add delay. `guessed`
-- marks the ones whose strength changes from one cast to the next.
local HASTE_BUFFS = {
    [33]  = { magic = 0.1465 },                         -- Haste
    [214] = { magic = 0.06, guessed = true },           -- March. Varies with skill and instrument.
    [126] = { magic = 0.25 },                           -- Spirit Surge
    [13]  = { magic = -0.18, guessed = true },          -- Slow. Varies with the caster's MND.
    [194] = { magic = -0.25, guessed = true },          -- Elegy. Carnage Elegy is stronger.
    [1]   = { magic = -1.0 },                           -- Weakness
    [353] = { ability = 0.10, two_handed_only = true }, -- Hasso
};
local HUNDRED_FISTS = 46;

local MAGIC_HASTE_CAP   = 0.4375;
local ABILITY_HASTE_CAP = 0.25;
-- Phoenix sets main.DELAY_REDUCTION_CAP to 0.93; the source default is 0.80.
-- The separate final weapon-delay floor still applies after percentage delay.
local PHOENIX_HASTE_CAP = 0.93;

local function to_ms(delay_units)
    return math.floor(delay_units * 1000 / 60);
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value));
end

local function trait(ranks_by_job, job, level)
    local ranks = ranks_by_job[job];
    if (ranks == nil) then
        return 0;
    end
    for _, rank in ipairs(ranks) do
        if (level >= rank[1]) then
            return rank[2];
        end
    end
    return 0;
end

local function best_trait(ranks_by_job, loadout)
    return math.max(
        trait(ranks_by_job, loadout.main_job, loadout.main_level),
        trait(ranks_by_job, loadout.sub_job, loadout.sub_level));
end

-- Known equipment and trait totals come from the current modifier model. A caller without one
-- still gets the job-only estimate.
local function modifier(loadout, name, traits)
    local model = loadout.modifiers;
    if (model ~= nil and model[name] ~= nil) then
        return model[name];
    end
    return traits and best_trait(traits, loadout) or 0;
end

-- True when both hands hold weapons that can be dual wielded. `skill` is the main weapon's skill.
local function dual_wielding(loadout, skill)
    return (DUAL_WIELDABLE[skill] and loadout.sub ~= nil and DUAL_WIELDABLE[loadout.sub.skill]) == true;
end

--[[
    Returns your delay between attacks in seconds.

    loadout = {
        main = { id = <item id>, delay = <client delay>, skill = <skill id> } or nil for an empty hand,
        sub  = same, or nil,
        sub_used = true when anything is in the sub slot, a shield included,
        main_job, main_level, sub_job, sub_level,
        buffs = { [buff id] = true, ... },
    }
]]
local SPEED_FIELDS = { haste_magic = true, haste_ability = true, twohand_haste_ability = true,
    haste_gear = true, delay_flat = true, delay_percent = true, martial_arts = true, dual_wield = true,
    desperate_blows = true };

-- The details and the timer use the same arithmetic. Ordinary timer reads make no extra tables.
local function calculate(loadout, details)
    local main = loadout.main;
    local skill = main and main.skill or SKILL_HAND_TO_HAND;
    local is_h2h = skill == SKILL_HAND_TO_HAND;
    local main_units = main and main.delay or UNARMED_DELAY;
    if (main ~= nil and is_h2h) then main_units = main_units + H2H_CLIENT_OFFSET; end

    local flat = modifier(loadout, 'delay_flat');
    local percent = modifier(loadout, 'delay_percent');
    local weapon_ms = to_ms(main_units) + flat;
    local martial = is_h2h and modifier(loadout, 'martial_arts', MARTIAL_ARTS) or 0;
    local martial_ms, dual = to_ms(martial), 0;
    if (not is_h2h and dual_wielding(loadout, skill)) then
        weapon_ms = weapon_ms + to_ms(loadout.sub.delay);
        dual = modifier(loadout, 'dual_wield', DUAL_WIELD);
    end

    local magic, ability, gear = 0, 0, 0;
    local model = loadout.modifiers;
    if (model ~= nil and model.haste_magic ~= nil) then
        magic = modifier(loadout, 'haste_magic') / 10000;
        ability = modifier(loadout, 'haste_ability') / 10000;
        if (TWO_HANDED[skill]) then ability = ability + modifier(loadout, 'twohand_haste_ability') / 10000; end
        gear = modifier(loadout, 'haste_gear') / 10000;
    else
        for buff, haste in pairs(HASTE_BUFFS) do
            if (loadout.buffs[buff] and (not haste.two_handed_only or TWO_HANDED[skill])) then
                magic = magic + (haste.magic or 0);
                ability = ability + (haste.ability or 0);
            end
        end
    end
    local raw_magic, raw_ability, raw_gear = magic, ability, gear;
    magic = clamp(magic, -1.0, MAGIC_HASTE_CAP);
    ability = clamp(ability, -ABILITY_HASTE_CAP, ABILITY_HASTE_CAP);
    gear = math.min(0.25, gear);
    local haste = clamp(1 - magic - ability - gear, 1 - PHOENIX_HASTE_CAP, 2.0);
    local fists = loadout.buffs[HUNDRED_FISTS] == true;
    local final_ms, before_limit, minimum, maximum;
    if (fists) then
        -- Hundred Fists also works with a staff or club. Other multipliers do not apply.
        before_limit = math.floor((weapon_ms - martial_ms) * 0.25);
        minimum, maximum = 400, 2000;
        final_ms = math.floor(clamp(weapon_ms - martial_ms, 1600, 8000) * 0.25);
    else
        final_ms = math.floor((weapon_ms - martial_ms) * (1 - dual / 100));
        final_ms = math.floor(final_ms * haste);
        before_limit = math.floor(final_ms * (1 + percent / 100));
        minimum, maximum = math.floor(weapon_ms * 0.2), weapon_ms * 2;
        final_ms = clamp(before_limit, minimum, maximum);
    end

    if (details) then
        details.gear = { raw = raw_gear * 100, effective = fists and 0 or gear * 100, cap = 25,
            capped = (raw_gear - gear) * 100 };
        details.magic = { raw = raw_magic * 100, effective = fists and 0 or magic * 100, cap = 43.75,
            minimum = -100, capped = (raw_magic - magic) * 100 };
        details.ability = { raw = raw_ability * 100, effective = fists and 0 or ability * 100, cap = 25,
            minimum = -25, capped = (raw_ability - ability) * 100 };
        details.combined = { raw = (magic + ability + gear) * 100,
            effective = fists and 0 or (1 - haste) * 100, cap = PHOENIX_HASTE_CAP * 100, minimum = -100 };
        details.martial_arts, details.dual_wield = martial, fists and 0 or dual;
        details.delay_flat, details.delay_percent = flat, fists and 0 or percent;
        details.raw_dual_wield, details.raw_delay_percent = dual, percent;
        details.modeled_interval, details.before_limit = final_ms / 1000, before_limit / 1000;
        details.minimum_interval, details.maximum_interval = minimum / 1000, maximum / 1000;
        details.limit_adjustment, details.hundred_fists = (final_ms - before_limit) / 1000, fists;
        details.known = model ~= nil and model.delay_known == true and not model.transition;
        details.unknown = {};
        local seen = {};
        for _, row in ipairs(model and model.unknown_sources or {}) do
            if (SPEED_FIELDS[row.field] and not seen[row.reason]) then
                seen[row.reason] = true;
                details.unknown[#details.unknown + 1] = row.reason;
            end
        end
        if (model and model.transition) then details.unknown[#details.unknown + 1] = 'Equipment or effects are changing.'; end
        if (not details.known and #details.unknown == 0) then
            details.unknown[1] = 'Some speed inputs are unavailable.';
        end
    end
    return final_ms / 1000;
end

function delay.estimate(loadout)
    return calculate(loadout);
end

-- Haste values are percentages, flat delay is milliseconds, and intervals are seconds.
function delay.breakdown(loadout)
    local details = {};
    calculate(loadout, details);
    return details;
end

-- An empty main hand fights with both fists only when one of your jobs has hand-to-hand skill and the
-- sub slot is empty. Otherwise it's one bare-handed attack a round.
local function fights_with_fists(loadout)
    return not loadout.sub_used and (HAND_TO_HAND_JOBS[loadout.main_job] or HAND_TO_HAND_JOBS[loadout.sub_job]) == true;
end

--[[
    The delay the server works out your TP per hit from, in 1/60 s units. Haste doesn't change it.
    Two weapons count as their average cut by Dual Wield. Fists count as half their delay after
    Martial Arts. Same loadout shape as delay.estimate().
]]
function delay.tp_delay(loadout)
    local main = loadout.main;
    local skill = main and main.skill or SKILL_HAND_TO_HAND;
    local units = main and main.delay or UNARMED_DELAY;
    if (main ~= nil and skill == SKILL_HAND_TO_HAND) then
        units = units + H2H_CLIENT_OFFSET;
    end
    if (skill == SKILL_HAND_TO_HAND) then
        local martial = modifier(loadout, 'martial_arts', MARTIAL_ARTS);
        if (main == nil and not fights_with_fists(loadout)) then
            units = math.max(units - martial, SHORTEST_UNARMED_TP_DELAY);
        else
            units = math.max((units - martial) / 2, SHORTEST_TP_DELAY);
        end
    elseif (dual_wielding(loadout, skill)) then
        units = (units + loadout.sub.delay) * (100 - modifier(loadout, 'dual_wield', DUAL_WIELD)) / 200;
    end
    return math.floor(units * math.max(1 + modifier(loadout, 'delay_percent') / 100, 0.85));
end

-- True when you attack with two weapons or fists. Both attack twice a round.
function delay.attacks_twice(loadout)
    local main = loadout.main;
    if (main == nil) then
        return fights_with_fists(loadout);
    end
    return main.skill == SKILL_HAND_TO_HAND or dual_wielding(loadout, main.skill);
end

-- Known Store TP, including eligible merits, or the job-only estimate before a model is available.
function delay.store_tp(loadout)
    return modifier(loadout, 'store_tp', STORE_TP);
end

--[[
    Returns a short text key naming everything the estimate depends on. The auto attack timer
    keeps the delay it learned with each key. New weapons, jobs or buffs mean a new delay.
]]
function delay.key(loadout)
    local haste_ids = {};
    for id in pairs(loadout.buffs) do
        if (HASTE_BUFFS[id] or id == HUNDRED_FISTS) then
            table.insert(haste_ids, id);
        end
    end
    table.sort(haste_ids);

    local gear = '';
    if (loadout.modifiers ~= nil) then
        gear = (loadout.modifiers.delay_key or ('%g/%g/%g'):format(
            modifier(loadout, 'dual_wield', DUAL_WIELD), modifier(loadout, 'martial_arts', MARTIAL_ARTS),
            modifier(loadout, 'delay_percent'))) .. ':';
    end
    return ('%d:%d:%d/%d:%d/%d:%s%s'):format(
        loadout.main and loadout.main.id or 0,
        loadout.sub and loadout.sub.id or 0,
        loadout.main_job, loadout.main_level,
        loadout.sub_job, loadout.sub_level,
        gear, table.concat(haste_ids, ','));
end

-- True when a key has March, Slow or Elegy in it and that buff isn't in `buffs`, your buffs right now.
-- Once it wears off, the next one is a new cast.
function delay.guess_worn_off(loadout_key, buffs)
    local ids = loadout_key:match(':([%d,]*)$') or '';
    for id in ids:gmatch('%d+') do
        id = tonumber(id);
        local buff = HASTE_BUFFS[id];
        if (buff ~= nil and buff.guessed and not buffs[id]) then
            return true;
        end
    end
    return false;
end

local NO_BUFFS = {};

-- False when a key has March, Slow or Elegy in it. The next one can be stronger or weaker. The delay
-- learned with the last one can't be trusted. With no buffs on, any of them counts as worn off.
function delay.exact(loadout_key)
    return not delay.guess_worn_off(loadout_key, NO_BUFFS);
end

return delay;
