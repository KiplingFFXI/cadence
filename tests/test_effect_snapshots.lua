-- Only supported cast-time inputs refine a duration; resists remain uncertain.
local out, failed = {}, 0;
local function check(name, value)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name;
    if (not value) then failed = failed + 1; end
end
local effects = require('core.monster_effects');
local enemy = require('core.enemy');
local own = { main_job = 10, main_level = 75, equipment_known = true, buffs_known = true,
    merits_known = true, equipment = { { slot = 2, id = 17371 } }, buffs = { [348] = true }, merits = {} };
local cast = effects.landed(4, 422, 237, 194, own);
check('Carnage Elegy keeps horn and Troubadour duration', cast.duration_estimate == 432 and cast.inputs_known);
check('resists still make duration uncertain', cast.duration_uncertain and cast.sure_for == 216);
check('cast evidence identifies the applied item', cast.cast_inputs.equipment[1].id == 17371 and cast.cast_inputs.buffs.troubadour);
local MOB = 0x01000200;
enemy.on_round(0, MOB, 1001);
enemy.on_effect(1, MOB, cast, true);
own.equipment[1].id, own.buffs[348] = 0, false;
check('later equipment and buff changes cannot rewrite the cast', enemy.info(2, MOB).effects[1].duration_estimate == 432
    and enemy.info(2, MOB).effects[1].cast_inputs.equipment[1].id == 17371);
own.equipment[1].id, own.buffs[348] = 17841, true;
local lullaby = effects.landed(4, 376, 236, 2, own);
check('Lullaby uses its own instrument bonus', lullaby.duration_estimate == 72 and lullaby.control == 'sleep');
own.equipment_known = false;
local unknown = effects.landed(4, 422, 237, 194, own);
check('gear transitions do not become confirmed durations', not unknown.inputs_known and unknown.duration_estimate == nil and unknown.lasts == 540);
own.equipment_known, own.buffs_known = true, false;
check('unknown Troubadour state stays uncertain', not effects.landed(4, 422, 237, 194, own).inputs_known);
own.buffs_known, own.equipment[1].id = true, 18341;
check('unresolved duration latent stays uncertain', not effects.landed(4, 422, 237, 194, own).inputs_known);
own.equipment[1].id = 17856;
check('level-scaled duration gear stays uncertain', not effects.landed(4, 422, 237, 194, own).inputs_known);
own.equipment[1].id, own.buffs[348] = 0, false;
own.merits[0x090C] = 1;
check('disabled era duration merit is not silently applied', not effects.landed(4, 56, 236, 13, own).inputs_known);
own.merits[0x090C], own.merits[0x0902] = 0, 3;
local slow = effects.landed(4, 79, 236, 13, own);
check('Slow II keeps the received merit evidence', slow.cast_inputs.merits.slow_ii == 3 and slow.duration_estimate == 180 and not slow.exact);
local other = effects.landed(4, 422, 237, 194);
check('another caster retains the conservative maximum', other.lasts == 540 and other.duration_estimate == nil);
check('unknown spell durations do not borrow a known spell', effects.landed(4, 9999, 236, 2, own).duration_estimate == nil);
own.equipment[1].id = 17371;
own.equipment[1].augments_known = true;
own.equipment[1].augments = { { id = 67, value = 0 } };
local augmented = effects.landed(4, 422, 237, 194, own);
check('supported All songs augment contributes at landing', augmented.duration_estimate == 234 and augmented.inputs_known);
own.equipment[1].augments_known = false;
check('unknown augment encoding prevents complete-duration claim', not effects.landed(4, 422, 237, 194, own).inputs_known);
own.equipment[1].augments_known = true;
own.equipment[1].augments = { { id = 999999, value = 0 } };
check('unknown augment ID prevents complete-duration claim', not effects.landed(4, 422, 237, 194, own).inputs_known);

check('damage and removal messages remain distinct', effects.is_damage(1) and not effects.is_damage(236) and effects.removed(168));
if (failed > 0) then out[#out + 1] = failed .. ' FAILED'; else out[#out + 1] = 'ALL PASSED'; end
return table.concat(out, '\n');
