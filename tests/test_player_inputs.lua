-- Weapon details and sub-slot occupancy come from one read of each equipped slot.
local out, fails = {}, 0;
local function check(name, condition)
    out[#out + 1] = (condition and 'ok   ' or 'FAIL ') .. name;
    if (not condition) then fails = fails + 1; end
end
local memory = AshitaCore:GetMemoryManager();
local inventory = memory:GetInventory();
local read_slot, reads = inventory.GetEquippedItem, {};
inventory.GetEquippedItem = function (self, slot)
    reads[slot] = (reads[slot] or 0) + 1;
    return read_slot(self, slot);
end;
memory.GetInventory = function () return inventory; end;
AshitaCore.GetMemoryManager = function () return memory; end;
local player = require('core.player');
MOCK.items[100], MOCK.items[101] = { Delay = 240, Skill = 3 }, { Delay = 0, Skill = 0 };
MOCK.player.equipment[0], MOCK.player.equipment[1] = 100, 101;
local loadout = player.read_loadout();
check('each weapon slot is read once per loadout', reads[0] == 1 and reads[1] == 1);
check('a shield is occupied but has no attack delay', loadout.main.id == 100 and loadout.sub == nil and loadout.sub_used);
MOCK.player.equipment[1] = nil;
loadout = player.read_loadout();
check('empty sub slot is unoccupied', loadout.sub == nil and not loadout.sub_used);
MOCK.player.equipment[1] = 102;
loadout = player.read_loadout();
check('unavailable resources do not turn an occupied slot into an empty one', loadout.sub == nil and loadout.sub_used);
MOCK.items[102] = { Delay = 210, Skill = 3 };
loadout = player.read_loadout();
check('an offhand weapon retains its own delay and skill', loadout.sub.id == 102 and loadout.sub.delay == 210 and loadout.sub.skill == 3 and loadout.sub_used);
MOCK.player.buffs = { 214, 214, 33 };
loadout = player.read_loadout();
check('duplicate buffs still retain counts for speed estimates', loadout.buffs_known and loadout.buff_counts[214] == 2 and loadout.buff_counts[33] == 1);
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
