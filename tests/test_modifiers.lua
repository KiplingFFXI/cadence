local modifiers = require('core.modifiers');
local data = modifiers.data;
local effect = data.effect_ids;
local out, failed = {}, 0;
local function check(name, condition, detail)
    if (condition) then
        out[#out + 1] = 'ok   ' .. name;
    else
        failed = failed + 1;
        out[#out + 1] = 'FAIL ' .. name .. ' ' .. tostring(detail or '');
    end
end
local function player(job, level, sub, sub_level)
    return { main_job = job or 1, main_level = level or 75, sub_job = sub or 0, sub_level = sub_level or 0,
        equipment = {}, buffs = {}, merits = { [1092] = 0 }, blue_spells = {},
        max_hp = 900, max_mp = 300, hp = 450, mp = 100, engaged = false,
        region = 0, zone = 100, flags = {} };
end

do
    local p = player(12);
    p.merits[1092] = 5;
    p.equipment[13] = { id = 15543, augments_known = true };
    p.buffs[effect.food] = true;
    p.food = { id = 5190 };
    local r = modifiers.calculate(p);
    check('SAM75 merits Rajas Carbonara gives46 Store TP', r.store_tp == 46 and r.tp_known, r.store_tp);
    p.main_level = 74;
    check('SAM merits stop below75', modifiers.calculate(p).store_tp == 36);
    p.main_level, p.main_job, p.sub_job, p.sub_level = 75, 1, 12, 37;
    check('SAM sub traits work without main job merits', modifiers.calculate(p).store_tp == 26);
    p.main_job, p.sub_job, p.sub_level, p.food, p.buffs = 12, 0, 0, nil, {};
    p.merits = {};
    r = modifiers.calculate(p);
    check('missing merit count remains unknown', not r.tp_known and r.store_tp == 30);
    p.merits[1092] = 0;
    check('explicit zero merits is known', modifiers.calculate(p).tp_known);
end

do
    local p = player(16, 75, 12, 37);
    p.blue_spells = { 545, 640 };
    check('BLU and SAM keep stronger trait', modifiers.calculate(p).store_tp == 15);
    p.sub_job, p.sub_level = 0, 0;
    check('BLU set spells provide Store TP10', modifiers.calculate(p).store_tp == 10);
    p.blue_spells = nil;
    check('BLU unknown set does not claim trait zero is exact', not modifiers.calculate(p).tp_known);
    p.main_level = 20;
    check('BLU below relevant unlocks is known without set packet', modifiers.calculate(p).tp_known and modifiers.calculate(p).mp_known);
    p = player(16, 75, 12, 37);
    p.blue_spells = nil;
    check('unknown BLU cannot exceed stronger SAM trait in era', modifiers.calculate(p).tp_known);
    p = player(16, 75);
    p.blue_spells = { 536, 598 };
    local r = modifiers.calculate(p);
    check('BLU Clear MindI is3 initial MP', r.mp_base == 15 and r.mp_step == 1, r.mp_base);
    p = player(4, 75, 3, 37);
    r = modifiers.calculate(p);
    check('Clear MindV beats subjob and gives27 plus3 per tick', r.mp_base == 27 and r.mp_step == 3, r.mp_base);
end

do
    local p = player(16, 75);
    p.blue_spells_known = true;
    local empty = modifiers.calculate(p);
    p.blue_spells = { 532 };
    local r = modifiers.calculate(p);
    check('Blitzstrahl applies direct DEX without needing a trait', r.dexterity == 3 and r.rounds_known);
    check('direct Blue Magic stats reset only the affected forecast', r.rounds_key ~= empty.rounds_key and r.tp_key == empty.tp_key
        and r.delay_key == empty.delay_key and r.resting_key == empty.resting_key);
    check('confirmed spell detail names its level and contribution', r.blue_magic.status == 'confirmed' and r.blue_magic.role == 'main'
        and r.blue_magic.spells[1].name == 'Blitzstrahl' and r.blue_magic.spells[1].level == 44
        and r.blue_magic.spells[1].eligible and r.blue_magic.direct_contributions[1].field == 'dexterity'
        and r.blue_magic.direct_contributions[1].value == 3 and r.blue_magic.direct_contributions[1].applied);
    p.blue_spells = { 532, 532 };
    check('duplicate Blue Magic ids cannot add stats twice', modifiers.calculate(p).dexterity == 3
        and #modifiers.calculate(p).blue_magic.spells == 1);
    p.main_level = 43;
    r = modifiers.calculate(p);
    check('level sync excludes higher-level spell stats and explains eligibility', r.dexterity == 0 and not r.blue_magic.spells[1].eligible);
    p.main_job, p.main_level, p.sub_job, p.sub_level = 3, 75, 16, 37;
    r = modifiers.calculate(p);
    check('BLU subjob uses its own spell level', r.dexterity == 0 and r.blue_magic.role == 'sub' and r.blue_magic.level == 37);
    p.blue_spells = { 620 };
    local battle_dance = modifiers.calculate(p);
    p.blue_spells = { 623 };
    r = modifiers.calculate(p);
    check('eligible direct stats work on BLU subjob', r.dexterity == 2 and r.blue_magic.spells[1].eligible);
    check('equal direct spell bonuses preserve the round context', battle_dance.rounds_key == r.rounds_key);
    p.blue_spells = {};
    check('unsetting a direct stat spell removes its contribution', modifiers.calculate(p).dexterity == 0
        and modifiers.calculate(p).rounds_key ~= r.rounds_key);
    p = player(16, 44);
    p.blue_spells, p.blue_spells_known = nil, false;
    r = modifiers.calculate(p);
    check('unknown BLU set includes direct accuracy uncertainty before trait unlock', not r.rounds_known and r.dexterity == 0
        and r.blue_magic.status == 'unknown');
    p.blue_spells = { 532 };
    r = modifiers.calculate(p);
    check('provisional spells remain visible without applying candidate stats', r.blue_magic.status == 'provisional'
        and r.blue_magic.direct_contributions[1].value == 3 and not r.blue_magic.direct_contributions[1].applied
        and r.dexterity == 0 and not r.rounds_known);
    p.blue_spells_known = true;
    check('server-confirmed list resolves direct stat uncertainty', modifiers.calculate(p).rounds_known and modifiers.calculate(p).dexterity == 3);
    p = player(16, 75, 12, 37);
    p.blue_spells = { 545, 640 };
    r = modifiers.calculate(p);
    local trait = r.blue_magic.traits[1];
    check('Blue Magic trait detail explains a stronger native trait', trait.name == 'Store TP' and trait.tier == 1
        and trait.points == 2 and trait.required == 2 and trait.overridden and not trait.applied and r.store_tp == 15);
    p.sub_job, p.sub_level = 0, 0;
    r = modifiers.calculate(p);
    check('eligible Blue Magic trait detail matches the applied total', r.blue_magic.traits[1].applied
        and not r.blue_magic.traits[1].overridden and r.store_tp == 10);
    p.blue_spells_known = false;
    r = modifiers.calculate(p);
    check('provisional trait detail never claims applied bonuses', r.blue_magic.traits[1].points == 2
        and not r.blue_magic.traits[1].applied and r.store_tp == 0 and not r.tp_known);
    p = player(3, 75, 16, 37);
    p.blue_spells = { 536, 598 };
    p.buffs[effect.sj_restriction] = true;
    r = modifiers.calculate(p);
    check('restricted BLU subjob has no active spell detail', not r.blue_magic.active and r.blue_magic.status == 'inactive'
        and #r.blue_magic.spells == 0);
    check('generated Blue Magic provenance includes direct spell stats', data.source_hashes['sql/blue_spell_mods.sql'] ~= nil);
    local eligible_spells, direct_spells = 0, 0;
    for id, spell in pairs(data.blue_spells) do
        eligible_spells = eligible_spells + 1;
        if (next(spell.mods) ~= nil) then direct_spells = direct_spells + 1; end
    end
    check('pinned Blue Magic inventory includes every eligible spell and ten direct DEX sources', eligible_spells == 107
        and direct_spells == 10 and data.coverage[9].blue_spells == 10 and data.blue_spells[670] == nil);
end

do
    local p = player(13, 75);
    p.equipment[5] = { id = 13782 };
    p.equipment[11] = { id = 14739 };
    local r = modifiers.calculate(p);
    check('native and equipped Dual Wield sum', r.dual_wield == 40, r.dual_wield);
    p.main_level = 50;
    r = modifiers.calculate(p);
    check('level sync disables high-level gear modifiers', r.dual_wield == 25, r.dual_wield);
    p = player();
    p.equipment[1] = { id = 19024 };
    check('Sword Strap contributes TP delay percent', modifiers.calculate(p).delay_percent == -3);
    p.equipment[0] = { id = 17960 };
    p.equipment[10] = { id = 15948 };
    check('negative Store TP is retained', modifiers.calculate(p).store_tp == -11);
    p = player(2, 75, 18, 37);
    check('Martial Arts takes stronger trait', modifiers.calculate(p).martial_arts == 180);
    p = player(1, 75, 12, 37);
    p.buffs[effect.sj_restriction] = true;
    check('subjob restriction removes native subjob modifiers', modifiers.calculate(p).store_tp == 0);
end

do
    local p = player();
    p.equipment[13] = { id = 15543, augments = { { id = 44, value = 3 }, { id = 51, value = 4 }, { id = 52, value = 2 }, { id = 115, value = 31 } } };
    local r = modifiers.calculate(p);
    check('standard augments decode value plus base and ignore pet', r.store_tp == 9 and r.hp_heal == 5 and r.mp_heal == 3);
    p.main_level = 20;
    r = modifiers.calculate(p);
    check('level sync also removes augment modifiers', r.store_tp == 0 and r.hp_heal == 0 and r.mp_heal == 0);
    p.main_level = 75;
    p.equipment[13] = { id = 15543, extra = 'unknownA', augments_known = false };
    r = modifiers.calculate(p);
    check('unreadable augments leave affected models unknown', not r.tp_known and not r.hp_known and not r.mp_known);
    p.equipment[13].extra = 'unknownB';
    check('unknown augment identity changes learning key', r.tp_key ~= modifiers.calculate(p).tp_key);
    p.equipment[13] = { id = 15543, augments = { { id = 48, value = 3 } } };
    check('negative delay augment keeps its sign', modifiers.calculate(p).delay_percent == -4);
end

do
    local p = player();
    p.equipment[10] = { id = 15282 };
    p.sub_job, p.sub_level = 12, 37;
    check('Katana Obi conditional subjob bonus', modifiers.calculate(p).store_tp == 16);
    p = player(12);
    p.equipment[0] = { id = 18445 };
    p.hp, p.max_hp = 500, 1000;
    local r = modifiers.calculate(p);
    check('HP-under latent includes exact50 percent', r.store_tp == 35);
    p.hp = 501;
    check('HP-under latent turns off above50', modifiers.calculate(p).store_tp == 25);
    p.hp = 800;
    local a = modifiers.calculate(p);
    p.hp = 801;
    check('HP changes within latent condition do not change key', a.tp_key == modifiers.calculate(p).tp_key);
    p = player();
    p.equipment[11] = { id = 16025 };
    check('unknown other-party jobs leaves latent unknown', not modifiers.calculate(p).tp_known);
    p.another_party_jobs = { [12] = 1 };
    check('other-party SAM activates earring', modifiers.calculate(p).store_tp == 1 and modifiers.calculate(p).tp_known);
    p.another_party_jobs = {};
    check('known absence of party SAM disables earring', modifiers.calculate(p).store_tp == 0 and modifiers.calculate(p).tp_known);
    p.party_known = false;
    check('partial party list cannot prove absence', not modifiers.calculate(p).tp_known);
    p.another_party_jobs = { [12] = 1 };
    check('partial party list can still prove job presence', modifiers.calculate(p).tp_known and modifiers.calculate(p).store_tp == 1);
    p = player();
    p.equipment[13] = { id = 14653 };
    p.flags.garrison = true;
    check('Garrison level rows stack at75', modifiers.calculate(p).mp_heal == 4, modifiers.calculate(p).mp_heal);
    p.flags.garrison = nil;
    check('unavailable Garrison flag remains unknown', not modifiers.calculate(p).mp_known);
end

do
    local p = player();
    p.buffs[effect.food] = true;
    p.food = { id = 5758, party_size = 4 };
    local r = modifiers.calculate(p);
    check('party curry uses size recorded when eaten', r.hp_heal == 6 and r.mp_heal == 3);
    p.party_size = 1;
    check('later party change does not change food', modifiers.calculate(p).resting_key == r.resting_key);
    p.food.party_size = 2;
    check('two-member curry uses middle tier', modifiers.calculate(p).hp_heal == 4 and modifiers.calculate(p).mp_heal == 2);
    p.food.party_size = nil;
    r = modifiers.calculate(p);
    check('missing curry party size affects recovery only', not r.hp_known and not r.mp_known and r.tp_known);
    p.food = nil;
    r = modifiers.calculate(p);
    check('unidentified Food icon does not assume a potency', not r.hp_known and not r.mp_known and not r.tp_known);
    p.buffs = {};
    check('worn-off food clears uncertainty', modifiers.calculate(p).tp_known);
end

do
    local p = player();
    p.buffs[effect.signet] = true;
    local r = modifiers.calculate(p);
    check('Signet75 max900 gives31 base4 step', r.hp_base == 31 and r.hp_step == 4 and r.hp_known);
    p.max_hp = 1199;
    local a = modifiers.calculate(p);
    p.max_hp = 1200;
    local b = modifiers.calculate(p);
    check('current maximum HP changes Signet step at300 boundary', a.hp_step == 4 and b.hp_step == 5 and a.resting_key ~= b.resting_key);
    p.region = 28;
    r = modifiers.calculate(p);
    check('TOAU region gets ordinary HP formula under Signet', r.hp_base == 10 and r.hp_step == 1);
    p.region = nil;
    p.zone = 100;
    check('zone maps to server region when region not supplied', modifiers.calculate(p).hp_base == 31);
    p.zone = 9999;
    check('unknown Signet region remains unknown', not modifiers.calculate(p).hp_known);
    p = player();
    p.equipment[11] = { id = 16006 };
    p.equipment[0] = { id = 18450 };
    check('Brilliant set grants healing HP', modifiers.calculate(p).hp_heal == 10);
end

do
    local p = player();
    p.buffs[effect.samurai_roll] = true;
    local r = modifiers.calculate(p);
    check('Samurai Roll icon does not imply maximum power', not r.tp_known and r.store_tp == 0);
    p.effects = { [effect.samurai_roll] = { store_tp = 42 } };
    check('known Samurai Roll uses supplied final strength', modifiers.calculate(p).store_tp == 42 and modifiers.calculate(p).tp_known);
    p.buffs[effect.inhibit_tp] = true;
    check('unknown Inhibit TP makes TP uncertain', not modifiers.calculate(p).tp_known);
    p.effects[effect.inhibit_tp] = { power = 25 };
    check('known Inhibit TP is separate from Store TP', modifiers.calculate(p).inhibit_tp == 25 and modifiers.calculate(p).store_tp == 42);
    p = player();
    p.buffs[effect.aftermath] = true;
    check('generic aftermath icon leaves strength unknown', not modifiers.calculate(p).tp_known);
    p.effects = { [effect.aftermath] = { store_tp = 7 } };
    check('proven Amano aftermath adds7 Store TP', modifiers.calculate(p).tp_known and modifiers.calculate(p).store_tp == 7);
    p.effects[effect.aftermath].store_tp = 0;
    check('proven other relic aftermath has known zero Store TP', modifiers.calculate(p).tp_known and modifiers.calculate(p).store_tp == 0);
    p = player();
    p.buffs[effect.healers_roll] = true;
    p.effects = { [effect.healers_roll] = { power = 10 } };
    check('era Healer Roll adds hMP', modifiers.calculate(p).mp_base == 22);
    p = player();
    p.buffs[effect.enchantment] = true;
    p.activated_items = { [18402] = { expires_at = 100 } };
    p.now = 10;
    check('activated Mana Wand adds hMP without requiring still equipped', modifiers.calculate(p).mp_heal == 2);
    p.activated_items = { [14677] = { expires_at = 100 } };
    p.equipment[13] = { id = 14677 };
    check('equipped activated Sanation Ring adds hMP3', modifiers.calculate(p).mp_heal == 3);
    p.equipment[13] = nil;
    check('Sanation Ring unequip stops contribution', modifiers.calculate(p).mp_heal == 0);
    p = player();
    p.equipment[0] = { id = 18402 };
    check('equipping a charged item alone gives no activated bonus', modifiers.calculate(p).mp_heal == 0);
end

do
    local p = player();
    local initial = modifiers.calculate(p);
    p.equipment[0] = { id = 16555 };
    p.buffs[33], p.buffs[8], p.buffs[20] = true, true, true;
    local unrelated = modifiers.calculate(p);
    check('irrelevant equipment and buffs preserve modifier keys', initial.tp_key == unrelated.tp_key and initial.resting_key == unrelated.resting_key);
    p.equipment[13] = { id = 15543 };
    local tp_change = modifiers.calculate(p);
    check('Store TP equipment does not reset recovery or delay key', tp_change.tp_key ~= unrelated.tp_key and tp_change.resting_key == unrelated.resting_key and tp_change.delay_key == unrelated.delay_key);
    p.equipment[0] = { id = 17559 };
    local mp_change = modifiers.calculate(p);
    check('Dark Staff changes recovery key without TP modifier key', mp_change.resting_key ~= tp_change.resting_key and mp_change.tp_key == tp_change.tp_key);
    p = player();
    p.buffs[effect.samurai_roll] = true;
    p.effect_epochs = { [effect.samurai_roll] = 1 };
    local first = modifiers.calculate(p);
    p.effect_epochs[effect.samurai_roll] = 2;
    check('unknown recast strength changes TP learning key', modifiers.calculate(p).tp_key ~= first.tp_key);
end

check('empty snapshots are safe and unknown', not modifiers.calculate({}).tp_known);
do
    local p = player();
    p.buffs_known = false;
    local r = modifiers.calculate(p);
    check('unavailable buff read is unknown even with an empty map', not r.tp_known and not r.hp_known and not r.mp_known);
    p.buffs_known = true;
    p.sub_job = nil;
    check('missing subjob is not treated as known absence', not modifiers.calculate(p).tp_known and not modifiers.calculate(p).mp_known);
end
check('generated profile is pinned', data.source.ref == '465ac4c076aebd70170fe8fde032e5066ce0737e');
check('relic mapping links Amano75 to Kaiten with7 Store TP', data.relic_aftermath[18318].weaponskill == 153 and data.relic_aftermath[18318].store_tp == 7);
if (failed > 0) then out[#out + 1] = tostring(failed) .. ' FAILED'; end
return table.concat(out, '\n');
