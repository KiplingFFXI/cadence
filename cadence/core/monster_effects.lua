--[[
    Slow, Elegy, Haste and Hundred Fists on a monster, as the game shows them to you.

    They change how fast a monster attacks (LSB CBattleEntity::GetWeaponDelay). Slow and Elegy take a
    share off its speed and Haste adds one. They all add together. The total is capped so a monster
    attacks at most twice as slow or 43.75% faster. Hundred Fists ignores the others and lasts 45 s.
    The server works out a monster's next attack when it attacks. An effect that lands mid-attack
    only changes the attack after that.
    You see these land on a monster in the action packet, from anyone within about 30 yalms. The
    effect id is in the result. Only the caster gets a wear-off message. An effect someone else cast
    is timed from how long it can last. How strong a Slow or Elegy is depends on the caster. Those
    are a guess until the monster's own attacks show it.
]]

local monster_effects = {};
local timing_data = require('data.phoenix_effects');

local SLOW, HASTE, HUNDRED_FISTS, ELEGY = 13, 33, 46, 194;

monster_effects.SLOW          = SLOW;
monster_effects.HASTE         = HASTE;
monster_effects.HUNDRED_FISTS = HUNDRED_FISTS;
monster_effects.ELEGY         = ELEGY;

-- Action categories that can put one of these on a monster.
local SPELL_FINISH    = 4;
local MOBSKILL_FINISH = 11;
local PET_SKILL       = 13;

-- Result messages for a spell or song landing, like "is inflicted with" and "receives the effect
-- of", plus the ones for a second target of the same cast.
local SPELL_LANDED = { [230] = true, [236] = true, [237] = true, [266] = true, [268] = true, [271] = true,
    [277] = true, [278] = true };
local TP_MOVE_BUFF = 186;
local HUNDRED_FISTS_USED = 101;
local PET_SKILL_LANDED = 127;

-- Result messages for Dispel, Erase and the like taking an effect off. A monster's own TP move that
-- erases one counts too. The result carries the effect id.
local REMOVED = { [83] = true, [123] = true, [159] = true, [168] = true, [321] = true,
    [341] = true, [342] = true, [343] = true, [378] = true };

-- 0x029 messages for an effect wearing off, and for a monster being defeated.
monster_effects.WEARS_OFF = { [204] = true, [206] = true };
monster_effects.DEFEATED  = { [6] = true, [20] = true };

--[[
    What each spell, TP move or pet skill does, by its id. `power` is how much speed it takes off or
    adds, out of 10000. `exact` means it's always that much. `sure_for` is how long it lasts at the
    least and `lasts` at the most, in seconds. Another player's cast could be half resisted, which
    halves how long it lasts. After `sure_for` it might already be off. Elegy's backstop allows
    for song gear and Troubadour doubling the duration.
]]
local SPELLS = {
    [56]  = { effect = SLOW,  power = 1825, exact = false, sure_for = 90,  lasts = 180 },  -- Slow
    [79]  = { effect = SLOW,  power = 2380, exact = false, sure_for = 90,  lasts = 180 },  -- Slow II
    [344] = { effect = SLOW,  power = 1465, exact = true,  sure_for = 90,  lasts = 180 },  -- Hojo: Ichi
    [345] = { effect = SLOW,  power = 1953, exact = true,  sure_for = 150, lasts = 300 },  -- Hojo: Ni
    [548] = { effect = SLOW,  power = 2500, exact = true,  sure_for = 45,  lasts = 90 },   -- Filamented Hold
    [421] = { effect = ELEGY, power = 2500, exact = false, sure_for = 60,  lasts = 360 },  -- Battlefield Elegy
    [422] = { effect = ELEGY, power = 5000, exact = true,  sure_for = 90,  lasts = 540 },  -- Carnage Elegy
    [57]  = { effect = HASTE, power = 1465, exact = true,  sure_for = 180, lasts = 180 },  -- Haste
};
local TP_MOVES = {
    [569]  = { effect = HASTE, power = 2000, exact = true,  sure_for = 180, lasts = 180 },  -- Refueling
    [1782] = { effect = HASTE, power = 3000, exact = true,  sure_for = 90,  lasts = 150 },  -- Animating Wail
};
local PET_SKILLS = {
    [580] = { effect = SLOW, power = 3000, exact = true, sure_for = 90, lasts = 380 },     -- Leviathan's Slowga
};

-- Used when the id isn't one of those above.
local SOME_SLOW  = { effect = SLOW,  power = 2000, exact = false, sure_for = 90,  lasts = 180 };
local SOME_ELEGY = { effect = ELEGY, power = 2500, exact = false, sure_for = 60,  lasts = 540 };
local SOME_HASTE = { effect = HASTE, power = 2000, exact = false, sure_for = 90,  lasts = 180 };
local FISTS      = { effect = HUNDRED_FISTS, power = 0, exact = true, sure_for = 45, lasts = 45 };
local FALLBACK   = { [SLOW] = SOME_SLOW, [ELEGY] = SOME_ELEGY, [HASTE] = SOME_HASTE };

local CONTROLS = { [2] = 'sleep', [19] = 'sleep', [193] = 'sleep',
    [7] = 'petrification', [10] = 'stun', [28] = 'terror' };
local LANDED = { [127] = true, [186] = true, [230] = true, [236] = true, [237] = true,
    [242] = true, [243] = true, [266] = true, [267] = true, [268] = true, [271] = true,
    [277] = true, [278] = true, [319] = true, [320] = true, [160] = true, [164] = true };
local COMPLETED = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true,
    [6] = true, [11] = true, [13] = true };
local DAMAGE = { [1] = true, [2] = true, [67] = true, [110] = true, [163] = true,
    [185] = true, [229] = true, [252] = true, [264] = true, [317] = true,
    [352] = true, [353] = true, [576] = true, [577] = true };

-- Keep only the inputs used by this cast. Later equipment swaps cannot change them.
local function with_context(info, category, action, context)
    local result = {};
    for key, value in pairs(info) do result[key] = value; end
    local source = category == SPELL_FINISH and timing_data.spells[action] or nil;
    if (source ~= nil and source.effect ~= info.effect and not (info.control == 'sleep' and source.effect == 2)) then
        source = nil;
    end
    result.duration_basis = 'unknown caster inputs';
    result.inputs_known = false;
    result.duration_uncertain = true;
    if (context == nil or source == nil) then
        if (info.control and source ~= nil) then
            result.duration_estimate, result.lasts = source.seconds, source.seconds;
            result.duration_basis = source.random and 'random maximum; caster inputs unknown'
                or 'source duration; caster inputs unknown';
        end
        return result;
    end

    local known = true;
    local bonus, duration_bonus = 0, 0;
    local inputs = { equipment = {}, buffs = {}, merits = {},
        equipment_known = context.equipment_known == true, buffs_known = context.buffs_known == true,
        merits_known = context.merits_known == true };
    if (source.song or source.enfeebling) then
        known = inputs.equipment_known;
        for _, item in ipairs(context.equipment or {}) do
            local gear = timing_data.gear[item.id];
            if (timing_data.latent_items[item.id] or item.augments_known == false) then known = false; end
            for _, augment in ipairs(item.augments or {}) do
                if (not timing_data.augment_ids[augment.id]) then known = false; end
                for _, definition in ipairs(timing_data.augments[augment.id] or {}) do
                    local value = (definition.base > 0 and (definition.base + augment.value)
                        or (definition.base - augment.value)) * definition.multiplier;
                    local song = source.song and (definition.key == source.song or definition.key == 'songs');
                    local duration = definition.key == (source.song and 'song_duration' or 'enfeebling_duration');
                    if (song) then bonus = bonus + value; end
                    if (duration) then duration_bonus = duration_bonus + value; end
                    if (song or duration) then
                        inputs.equipment[#inputs.equipment + 1] = { slot = item.slot, id = item.id,
                            augment = augment.id, song_bonus = song and value or 0,
                            duration_percent = duration and value or 0 };
                    end
                end
            end
            if (gear ~= nil) then
                if (context.main_level == nil or gear.level > context.main_level) then
                    known = false;
                else
                    local value = source.song and ((gear[source.song] or 0) + (gear.songs or 0)) or 0;
                    local duration = source.song and (gear.song_duration or 0) or (gear.enfeebling_duration or 0);
                    bonus, duration_bonus = bonus + value, duration_bonus + duration;
                    if (value ~= 0 or duration ~= 0) then
                        inputs.equipment[#inputs.equipment + 1] = { slot = item.slot, id = item.id,
                            song_bonus = value, duration_percent = duration };
                    end
                end
            end
        end
    end
    local seconds = source.seconds;
    if (source.song) then
        known = known and inputs.buffs_known;
        inputs.buffs.troubadour = context.buffs and context.buffs[timing_data.troubadour] == true or false;
        seconds = math.floor(seconds * (1 + bonus / 10 + duration_bonus / 100));
        if (inputs.buffs.troubadour) then seconds = seconds * 2; end
    elseif (source.enfeebling) then
        -- This duration merit is disabled in the configured era. A nonzero received rank is uncertain.
        local merit = timing_data.merits.enfeebling_duration;
        if (context.merits_known and context.merits) then
            inputs.merits.enfeebling_duration = context.merits[merit] or 0;
            if (inputs.merits.enfeebling_duration ~= 0) then known = false; end
            inputs.merits.slow_ii = context.merits[timing_data.merits.slow_ii] or 0;
        end
        -- Saboteur is outside this source profile; seeing it makes the duration unknown.
        if (context.buffs and context.buffs[454]) then known = false; end
        seconds = math.floor(seconds * (1 + duration_bonus / 100));
    end
    result.cast_inputs = inputs;
    result.inputs_known = known;
    result.duration_estimate = known and seconds or nil;
    result.duration_basis = known and (source.random and 'random maximum before resists'
        or ((source.song or source.enfeebling) and 'inputs at landing before resists' or 'source duration before resists'))
        or 'unresolved cast inputs';
    if (known) then
        result.lasts = seconds;
        result.sure_for = source.random and 0 or seconds / 2;
    end
    return result;
end

-- A landed message establishes the observation, never an exact duration or resume time.
function monster_effects.landed(category, id, message, effect, context)
    if (not COMPLETED[category]) then return nil; end
    local control = CONTROLS[effect];
    if (control and LANDED[message]) then
        local info = { effect = control == 'sleep' and 2 or effect, control = control,
            sure_for = 0, lasts = 180, duration_uncertain = true };
        return with_context(info, category, id, context);
    end
    local info;
    if (category == SPELL_FINISH and SPELL_LANDED[message]) then
        local spell = SPELLS[id];
        info = (spell ~= nil and spell.effect == effect) and spell or FALLBACK[effect];
    elseif (category == MOBSKILL_FINISH and message == TP_MOVE_BUFF and effect == HASTE) then
        info = TP_MOVES[id] or SOME_HASTE;
    elseif (category == MOBSKILL_FINISH and message == HUNDRED_FISTS_USED and effect == HUNDRED_FISTS) then
        info = FISTS;
    elseif (category == PET_SKILL and PET_SKILL_LANDED == message and effect == SLOW) then
        info = PET_SKILLS[id] or SOME_SLOW;
    elseif (LANDED[message] and FALLBACK[effect]) then
        info = FALLBACK[effect];
    end
    if (info ~= nil and context ~= nil) then return with_context(info, category, id, context); end
    return info;
end

function monster_effects.is_damage(message)
    return DAMAGE[message] == true;
end

-- True when a result took an effect off the monster.
function monster_effects.removed(message)
    return REMOVED[message] == true;
end

-- True for the action categories worth looking through.
function monster_effects.can_land(category)
    return COMPLETED[category] == true;
end

return monster_effects;
