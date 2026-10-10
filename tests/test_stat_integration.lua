-- Normal addon callbacks join passive client state, generated Phoenix rules and resting estimates.
local out, fails = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then fails = fails + 1; end
end
local base_memory = AshitaCore.GetMemoryManager();
local party = base_memory:GetParty();
party.GetMemberIsActive = function (_, i) return i == 0; end;
party.GetMemberServerId = function (_, i) return i == 0 and MOCK.player.server_id or 0; end;
party.GetMemberMainJob = function () return MOCK.player.main_job; end;
party.GetMemberZone = function () return MOCK.player.zone; end;
party.GetMemberHP = function () return MOCK.player.hp; end;
party.GetMemberMP = function () return MOCK.player.mp; end;
party.GetMemberHPPercent = function () return math.floor(MOCK.player.hp * 100 / MOCK.player.hp_max); end;
base_memory.GetParty = function () return party; end;
AshitaCore.GetMemoryManager = function () return base_memory; end;
MOCK.player.main_job, MOCK.player.sub_job, MOCK.player.sub_level = 4, 3, 37;
MOCK.player.hp_max, MOCK.player.mp_max, MOCK.player.hp, MOCK.player.mp = 900, 300, 500, 100;
MOCK.player.zone, MOCK.player.buffs = 100, { 253 };
MOCK.player.status = 33;
MOCK.player.equipment[0] = 17559;
MOCK.items[17559] = { Delay = 366, Skill = 12 };
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local observer, resting = require('core.stat_state'), require('core.resting');
local function frame(now)
    MOCK.now = now;
    MOCK.frame(0);
end
local function incoming(e, now)
    MOCK.now = now;
    MOCK.fire('packet_in', e);
end
local function vitals(now, hp, mp)
    incoming(MOCK.vitals_packet(1001, hp, mp, 0), now);
    MOCK.player.hp, MOCK.player.mp = hp, mp;
end
local function item(id, now)
    incoming(MOCK.action_packet(1001, 5, id, 1001, { { message = 0 } }), now);
end
local function packet(id, size, fields)
    local b = MOCK.bytes(size);
    for offset, pair in pairs(fields or {}) do
        for i = 0, pair[2] - 1 do b[offset + i] = math.floor(pair[1] / 256 ^ i) % 256; end
    end
    return { id = id, size = size, data = MOCK.to_string(b), data_raw = b };
end

frame(1);
local model = observer.info();
check('live-shaped memory feeds BLM traits Dark Staff and regional Signet', model.mp_base == 37 and model.mp_step == 3 and model.hp_base == 31 and model.hp_step == 4 and model.mp_known);
vitals(1.1, 500, 100);
MOCK.player.status = 33;
frame(1.3);
local hp, mp = resting.next_gains();
check('resting has a useful first estimate before observing any tick', hp == 31 and mp == 37, mp);
item(4576, 1.4);
MOCK.player.buffs = { 253, 251 };
frame(1.7);
check('successful Wizard Cookie updates the real first MP estimate', select(2, resting.next_gains()) == 44 and observer.info().mp_known);
vitals(1.9, 500, 100);
vitals(22.5, 531, 144);
local _, gain, confidence = resting.next_gains();
check('first clean gain replaces the model without adding the cookie twice', gain == 47 and confidence.mp == 'observed', gain);
local key, count = observer.info().resting_key, select(3, resting.progress(22.5));
MOCK.player.equipment[13] = 15543;
incoming(packet(0x050, 8), 23);
frame(23.3);
check('a Store TP ring keeps the learned MP amount and resting phase', observer.info().resting_key == key and select(2, resting.next_gains()) == 47 and select(3, resting.progress(23.3)) == count);
MOCK.player.equipment[0] = nil;
incoming(packet(0x050, 8), 24);
frame(24.3);
check('removing Dark Staff adjusts the next amount at the existing tick index', select(2, resting.next_gains()) == 37 and select(3, resting.progress(24.3)) == count);
MOCK.player.buffs = { 253 };
frame(25);
check('food wearoff removes only its modeled contribution', observer.info().mp_base == 27 and select(2, resting.next_gains()) == 30);

MOCK.player.status, MOCK.player.main_job, MOCK.player.sub_job = 1, 12, 1;
MOCK.player.mp_max = 0;
frame(26);
check('SAM begins with its trait and ring but unknown allocated merits', observer.info().store_tp == 30 and not observer.info().tp_known);
incoming(packet(0x08C, 12, { [4] = { 1, 2 }, [8] = { 1092, 2 }, [11] = { 5, 1 } }), 26.2);
frame(26.5);
check('normal merit data completes SAM trait merits and Rajas', observer.info().store_tp == 40 and observer.info().tp_known);
item(5190, 26.6);
MOCK.player.buffs = { 253, 251 };
frame(26.9);
check('observed Carbonara raises total Store TP to46', observer.info().store_tp == 46 and observer.info().tp_known);
incoming(MOCK.zone_packet(1001, 100), 27);
frame(27.3);
check('the same character keeps observed food and merits through a zone', observer.info().store_tp == 46 and observer.info().tp_known);

MOCK.player.main_job, MOCK.player.sub_job, MOCK.player.sub_level = 16, 0, 0;
MOCK.player.buffs = {};
frame(28);
check('BLU begins with unknown set spells', not observer.info().tp_known);
incoming(packet(0x044, 28, { [4] = { 16, 1 }, [8] = { 33, 1 }, [9] = { 128, 1 } }), 28.1);
frame(28.4);
check('normal BLU spell state completes trait10 plus ring5', observer.info().store_tp == 15 and observer.info().tp_known, observer.info().store_tp);

local delay, player = require('core.delay'), require('core.player');
local function seconds()
    local loadout = player.read_loadout();
    loadout.modifiers = observer.info();
    return delay.estimate(loadout);
end
MOCK.player.main_job, MOCK.player.sub_job = 1, 0;
MOCK.player.equipment[0] = 16535;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
frame(29);
local base_delay_key, base_tp_key = observer.info().delay_key, observer.info().tp_key;
check('speed integration starts from a four-second weapon', seconds() == 4);
MOCK.player.equipment[4] = 15270;
incoming(packet(0x050, 8), 29.1);
frame(29.4);
check('Walahra Turban improves the real estimate to3.8 seconds', seconds() == 3.8 and observer.info().haste_gear == 500);
check('gear haste changes speed evidence but preserves TP per hit', observer.info().delay_key ~= base_delay_key and observer.info().tp_key == base_tp_key);
MOCK.player.equipment[4] = nil;
incoming(packet(0x050, 8), 29.5);
frame(29.8);
incoming(MOCK.action_packet(2001, 4, 56, 1001, { { message = 236, damage = 13 } }), 30);
MOCK.player.buffs = { 13 };
frame(30.3);
local slow_key = observer.info().delay_key;
check('landed Slow increases the actual delay estimate', seconds() > 4 and not observer.info().delay_known);
incoming(MOCK.action_packet(2001, 4, 56, 1001, { { message = 236, damage = 13 } }), 30.4);
frame(30.7);
check('same-icon Slow refresh invalidates speed while retaining TP stats', observer.info().delay_key ~= slow_key and observer.info().tp_key == base_tp_key);
MOCK.player.buffs = { 214, 214 };
frame(31);
check('two March icons contribute two estimated effects', observer.info().haste_magic == 1200 and not observer.info().delay_known, observer.info().haste_magic);
MOCK.player.buffs = {};
MOCK.player.equipment[10] = 15290;
incoming(packet(0x050, 8), 31.1);
frame(31.4);
incoming(MOCK.action_packet(1001, 5, 15290, 1001, { { message = 230, damage = 33 } }), 31.5);
MOCK.player.buffs = { 33 };
frame(31.8);
check('observed Haste Belt uses its1000 power instead of adding spell haste', observer.info().haste_magic == 1000 and seconds() == 3.6, observer.info().haste_magic);
incoming(MOCK.action_packet(2001, 4, 57, 1001, { { message = 230, damage = 33 } }), 32);
MOCK.player.buffs = { 33, 33 };
frame(32.3);
check('a separate Haste icon adds only the residual spell estimate', observer.info().haste_magic == 2465, observer.info().haste_magic);
MOCK.player.equipment[10], MOCK.player.buffs = nil, { 33 };
incoming(packet(0x050, 8), 32.4);
frame(32.7);
check('removing Haste Belt leaves the remaining Haste estimate', observer.info().haste_magic == 1465, observer.info().haste_magic);
local before_hp = observer.snapshot().hp;
local rejected = MOCK.vitals_packet(1001, 1, 1, 1);
rejected.blocked = true;
incoming(rejected, 32.8);
check('blocked vitals cannot enter through the main callback', observer.snapshot().hp == before_hp);
rejected = MOCK.zone_packet(2002, 69);
rejected.injected = true;
incoming(rejected, 32.9);
check('injected zoning cannot reset character evidence', observer.snapshot().merits[1092] == 5);
check('passive integration queues no commands', #MOCK.commands == 0);
for _, line in ipairs(MOCK.printed) do
    check('no callback or rendering error', not line:find('Drawing stopped', 1, true));
end
out[#out + 1] = fails == 0 and 'ALL OK' or (fails .. ' FAILED');
return table.concat(out, '\n');
