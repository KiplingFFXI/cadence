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
local REMOVED = { [159] = true, [341] = true, [342] = true, [343] = true, [378] = true };

-- 0x029 messages for an effect wearing off, and for a monster being defeated.
monster_effects.WEARS_OFF = { [204] = true, [206] = true };
monster_effects.DEFEATED  = { [6] = true, [20] = true };

--[[
    What each spell, TP move or pet skill does, by its id. `power` is how much speed it takes off or
    adds, out of 10000. `exact` means it's always that much. `sure_for` is how long it lasts at the
    least and `lasts` at the most, in seconds. Another player's cast could be half resisted, which
    halves how long it lasts. After `sure_for` it might already be off.
]]
local SPELLS = {
    [56]  = { effect = SLOW,  power = 1825, exact = false, sure_for = 90,  lasts = 180 },  -- Slow
    [79]  = { effect = SLOW,  power = 2380, exact = false, sure_for = 90,  lasts = 180 },  -- Slow II
    [344] = { effect = SLOW,  power = 1465, exact = true,  sure_for = 90,  lasts = 180 },  -- Hojo: Ichi
    [345] = { effect = SLOW,  power = 1953, exact = true,  sure_for = 150, lasts = 300 },  -- Hojo: Ni
    [548] = { effect = SLOW,  power = 2500, exact = true,  sure_for = 45,  lasts = 90 },   -- Filamented Hold
    [421] = { effect = ELEGY, power = 2500, exact = false, sure_for = 60,  lasts = 180 },  -- Battlefield Elegy
    [422] = { effect = ELEGY, power = 5000, exact = true,  sure_for = 90,  lasts = 270 },  -- Carnage Elegy
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
local SOME_ELEGY = { effect = ELEGY, power = 2500, exact = false, sure_for = 60,  lasts = 180 };
local SOME_HASTE = { effect = HASTE, power = 2000, exact = false, sure_for = 90,  lasts = 180 };
local FISTS      = { effect = HUNDRED_FISTS, power = 0, exact = true, sure_for = 45, lasts = 45 };
local FALLBACK   = { [SLOW] = SOME_SLOW, [ELEGY] = SOME_ELEGY, [HASTE] = SOME_HASTE };

--[[
    What landed, from one result of an action. `id` is the action's spell, TP move or pet skill id.
    Returns the effect's entry from the tables above, or nil when nothing cadence tracks landed. A
    failed cast carries the effect id too, so the message has to say it landed.
]]
function monster_effects.landed(category, id, message, effect)
    if (category == SPELL_FINISH and SPELL_LANDED[message]) then
        local spell = SPELLS[id];
        if (spell ~= nil and spell.effect == effect) then
            return spell;
        end
        return FALLBACK[effect];
    elseif (category == MOBSKILL_FINISH and message == TP_MOVE_BUFF and effect == HASTE) then
        return TP_MOVES[id] or SOME_HASTE;
    elseif (category == MOBSKILL_FINISH and message == HUNDRED_FISTS_USED and effect == HUNDRED_FISTS) then
        return FISTS;
    elseif (category == PET_SKILL and message == PET_SKILL_LANDED and effect == SLOW) then
        return PET_SKILLS[id] or SOME_SLOW;
    end
    return nil;
end

-- True when a result took an effect off the monster.
function monster_effects.removed(message)
    return REMOVED[message] == true;
end

-- True for the action categories worth looking through.
function monster_effects.can_land(category)
    return category == SPELL_FINISH or category == MOBSKILL_FINISH or category == PET_SKILL;
end

return monster_effects;
