-- The enemy timer remembering each monster's attack speed by zone and name until another character
-- logs in. The next monster with that name in that zone starts from it.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end
local function near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 1e-6); end

local enemy = require('core.enemy');
local monster_effects = require('core.monster_effects');

local ME, TANK = 1001, 2001;
local HOJO_NI = monster_effects.landed(4, 345, 236, monster_effects.SLOW);

-- Clocks on their own -------------------------------------------------------------------------------

-- The monster engages at `t`, attacks 2.8 s later, then `gaps` more times `gap` seconds apart. Returns
-- when its last round came.
local function fight(id, t, gap, gaps)
    enemy.on_engage(t, id);
    t = t + 2.8;
    enemy.on_round(t, id, TANK);
    for _ = 1, gaps do
        t = t + gap;
        enemy.on_round(t, id, TANK);
    end
    return t;
end

-- A monster's server id the way Phoenix builds it, with its zone in bits 12 to 23.
local function in_zone(zone, index) return 0x01000000 + zone * 0x1000 + index; end

-- The delay a new monster with this name starts from in that zone, or 4.0 when nothing is kept for it.
local function starts_from(zone, name)
    local probe = in_zone(zone, 0x7FF);
    enemy.forget(probe);
    enemy.on_engage(0, probe);
    enemy.recall(0, probe, name);
    local _, _, delay = enemy.progress(0, probe);
    enemy.forget(probe);
    return delay;
end

do
    enemy.reset();
    enemy.forget_speeds();
    local GIGAS, GIGAS2, OTHER, ODD, AGGRO = in_zone(102, 0x100), in_zone(102, 0x101), in_zone(103, 0x102),
        in_zone(102, 0x103), in_zone(102, 0x104);

    -- An 8 s gigas, learned from three clean gaps, then kept as it dies.
    fight(GIGAS, 0, 8.0, 3);
    enemy.remember(GIGAS, 'Gigas Bonecutter');
    enemy.forget(GIGAS);

    -- The next one with that name still attacks first 2.8 s after it engages. The round after that
    -- comes on the kept 8 s, and it says est. until its own gaps show it.
    enemy.on_engage(100, GIGAS2);
    enemy.recall(100, GIGAS2, 'Gigas Bonecutter');
    local _, left, delay, learned = enemy.progress(100, GIGAS2);
    check('the first round still comes 2.8 s after it engages', near(left, 2.8), left);
    enemy.on_round(102.8, GIGAS2, TANK);
    _, left, delay, learned = enemy.progress(102.8, GIGAS2);
    check('the second round comes on the kept delay', near(left, 8.0) and near(delay, 8.0), left);
    check('it still says est.', learned == false);
    enemy.on_round(110.8, GIGAS2, TANK);
    enemy.on_round(118.8, GIGAS2, TANK);
    _, _, delay, learned = enemy.progress(118.8, GIGAS2);
    check('still est. after two gaps of its own', near(delay, 8.0) and learned == false, tostring(learned));
    enemy.on_round(126.8, GIGAS2, TANK);
    _, _, delay, learned = enemy.progress(126.8, GIGAS2);
    check('learned after three gaps of its own', near(delay, 8.0) and learned == true, tostring(learned));

    -- Another name, or the same name in another zone, starts from 4.0. Nothing kept means no clock.
    check('another name starts from 4.0', near(starts_from(102, 'Gigas Catapulter'), 4.0));
    check('another zone starts from 4.0', near(starts_from(103, 'Gigas Bonecutter'), 4.0));
    enemy.recall(200, OTHER, 'Gigas Bonecutter');
    check('no clock is made for a name with nothing kept', not enemy.has(OTHER));

    -- This one attacks every 4 s. Its first gap takes over from the kept 8 s right away.
    enemy.on_engage(300, ODD);
    enemy.recall(300, ODD, 'Gigas Bonecutter');
    enemy.on_round(302.8, ODD, TANK);
    enemy.on_round(306.8, ODD, TANK);
    _, left, delay, learned = enemy.progress(306.8, ODD);
    check('a first gap far from the kept delay takes over', near(delay, 4.0) and near(left, 4.0) and not learned, delay);

    -- One that attacks before the timer follows it. The next round it set from 4.0 moves to 8 s.
    enemy.on_round(400, AGGRO, ME);
    enemy.recall(400.02, AGGRO, 'Gigas Bonecutter');
    _, left, delay = enemy.progress(400.02, AGGRO);
    check('a round before it was followed moves to the kept delay', near(left, 7.98) and near(delay, 8.0), left);

    -- Hojo: Ni lands after its 8 s was learned. Its slowed gaps aren't what's kept.
    local SLOWED = in_zone(102, 0x105);
    local t = fight(SLOWED, 500, 8.0, 3);
    enemy.on_effect(t + 1, SLOWED, HOJO_NI, true);
    t = t + 8.0;
    for _ = 1, 3 do
        enemy.on_round(t, SLOWED, TANK);
        t = t + 9.6;
    end
    local _, _, slowed = enemy.progress(t - 9.6, SLOWED);
    check('it attacks slower under Hojo', near(slowed, 9.6, 0.001), slowed);
    enemy.remember(SLOWED, 'Gigas Slowed');
    check('it is kept at its speed with no Slow on', near(starts_from(102, 'Gigas Slowed'), 8.0), starts_from(102, 'Gigas Slowed'));

    -- Slowed from the pull, it never attacked without Slow. Nothing is kept.
    local PULLED = in_zone(102, 0x106);
    enemy.on_engage(600, PULLED);
    enemy.on_effect(600.5, PULLED, HOJO_NI, true);
    t = 602.8;
    for _ = 1, 4 do
        enemy.on_round(t, PULLED, TANK);
        t = t + 9.6;
    end
    enemy.remember(PULLED, 'Slowed Sheep');
    check('a monster slowed the whole fight is not kept', near(starts_from(102, 'Slowed Sheep'), 4.0));

    -- Two gaps aren't enough to keep it.
    local SHORT = in_zone(102, 0x107);
    fight(SHORT, 700, 6.0, 2);
    enemy.remember(SHORT, 'Short Fight');
    check('a speed that wasn\'t learned yet is not kept', near(starts_from(102, 'Short Fight'), 4.0));

    -- At most 64 names. Saving one again makes it the newest. The oldest goes first.
    enemy.reset();
    enemy.forget_speeds();
    local function learn(i)
        local id = in_zone(102, i);
        fight(id, i * 100, 6.0, 3);
        enemy.remember(id, 'Mob ' .. i);
        enemy.forget(id);
    end
    for i = 1, 64 do learn(i); end
    check('64 names are kept', near(starts_from(102, 'Mob 1'), 6.0) and near(starts_from(102, 'Mob 64'), 6.0));
    learn(1);
    learn(65);
    check('the oldest goes past 64', near(starts_from(102, 'Mob 2'), 4.0), starts_from(102, 'Mob 2'));
    check('one saved again stays', near(starts_from(102, 'Mob 1'), 6.0) and near(starts_from(102, 'Mob 3'), 6.0)
        and near(starts_from(102, 'Mob 65'), 6.0));

    -- A name saved again takes its newer speed.
    local AGAIN = in_zone(102, 0x200);
    fight(AGAIN, 9000, 7.2, 3);
    enemy.remember(AGAIN, 'Mob 3');
    enemy.forget(AGAIN);
    check('a name saved again takes the newer speed', near(starts_from(102, 'Mob 3'), 7.2), starts_from(102, 'Mob 3'));

    -- One round with nothing on it, then Hojo lands, then the timer follows it. The server set that next
    -- round from its plain speed, so the kept 8 s is used.
    local HOJOED = in_zone(102, 0x201);
    fight(GIGAS, 9500, 8.0, 3);
    enemy.remember(GIGAS, 'Gigas Bonecutter');
    enemy.forget(GIGAS);
    enemy.on_round(9600, HOJOED, TANK);
    enemy.on_effect(9601, HOJOED, HOJO_NI, true);
    enemy.recall(9602, HOJOED, 'Gigas Bonecutter');
    _, left = enemy.progress(9602, HOJOED);
    check('a round before Hojo still comes on the kept speed', near(left, 6.0), left);

    enemy.forget_speeds();
    check('forgetting them all', near(starts_from(102, 'Mob 65'), 4.0) and near(starts_from(102, 'Mob 1'), 4.0));
    enemy.reset();
end

-- The whole addon -----------------------------------------------------------------------------------
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
MOCK.fire('command', { command = '/cadence enemy on' });
MOCK.now = 1000;

-- One frame `dt` seconds on. Returns the enemy timer's text, or nil when it isn't drawn.
local function frame(dt)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(dt or 0);
    MOCK.record_imgui = false;
    local inside, drawn, words = false, false, {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'Begin') then
            inside = c[2] == '##cadence_enemy';
            drawn = drawn or inside;
        end
        if (inside and c[1] == 'dl:AddText') then table.insert(words, tostring(c[6])); end
    end
    return drawn and table.concat(words, '|') or nil;
end

local next_index = 0x210;
-- The zone new monsters spawn in. Their server ids carry it, the way Phoenix builds them.
local current_zone = 101;
local function spawn(name)
    local index = next_index;
    next_index = next_index + 1;
    local id = 0x01000000 + current_zone * 0x1000 + index;
    MOCK.entities[index] = { ServerId = id, Name = name, Status = 0, SpawnFlags = 0x10 };
    return index, id;
end
local function round(id, target) MOCK.fire('packet_in', MOCK.action_packet(id, 1, 0, target or TANK, { { message = 1 } })); end
local function defeat(id) MOCK.fire('packet_in', MOCK.message_packet(ME, id, 0, 0, 6)); end
local function zone(number)
    current_zone = number;
    MOCK.fire('packet_in', MOCK.zone_packet(ME, number));
end

-- Targets the monster and pulls it. It attacks 2.8 s later, then `rounds` more times `gap` seconds
-- apart. A long quiet spell first lets the last fight's monster go.
local function pull(index, gap, rounds)
    local id = MOCK.entities[index].ServerId;
    MOCK.now = MOCK.now + 100;
    MOCK.player.target_index = index;
    frame();
    MOCK.entities[index].Status = 1;
    frame();
    MOCK.now = MOCK.now + 2.8;
    round(id);
    frame();
    for _ = 1, rounds or 0 do
        MOCK.now = MOCK.now + gap;
        round(id);
        frame();
    end
    return id;
end

-- Pulls a new monster with this name and lets it attack once. Returns its delay, the seconds left
-- and the timer's text.
local function second_fight(name)
    local index = spawn(name);
    local id = pull(index);
    local _, left, delay = enemy.progress(MOCK.now, id);
    local text = frame();
    MOCK.entities[index].Status = 3;
    defeat(id);
    frame();
    return delay, left, text;
end

-- Before the first zone packet, like when cadence loads mid-game. The zone comes from the monster's id.
local index, id = spawn('Wild Sheep');
pull(index, 5.6, 3);
MOCK.entities[index].Status = 3;
frame();
check('kept before the first zone packet', near(second_fight('Wild Sheep'), 5.6));

zone(102);
check('zoning in starts a new zone', near(second_fight('Wild Sheep'), 4.0));
zone(101);
check('and zoning back keeps what was learned before the first zone packet', near(second_fight('Wild Sheep'), 5.6));
zone(102);

-- Killed with the defeat message, which drops the clock before its status changes.
index, id = spawn('Gigas Bonecutter');
pull(index, 8.0, 3);
local text = frame();
check('the first one learns its 8 s', text ~= nil and text:find('Gigas Bonecutter  8.00s', 1, true) ~= nil
    and text:find('est.', 1, true) == nil, text);
defeat(id);
MOCK.entities[index].Status = 3;
frame();
local delay, left;
delay, left, text = second_fight('Gigas Bonecutter');
check('the next one\'s second round comes on the kept 8 s', near(delay, 8.0) and near(left, 8.0), left);
check('and it says est.', text ~= nil and text:find('Gigas Bonecutter  8.00s est.', 1, true) ~= nil, text);

check('another name in that zone starts from 4.0', near(second_fight('Gigas Catapulter'), 4.0));
zone(103);
check('the same name in another zone starts from 4.0', near(second_fight('Gigas Bonecutter'), 4.0));
zone(102);
check('zoning back keeps what was learned there', near(second_fight('Gigas Bonecutter'), 8.0));

-- One that attacks you with nothing targeted. The round it set from 4.0 moves to the kept 8 s.
MOCK.now = MOCK.now + 100;
MOCK.player.target_index = 0;
index, id = spawn('Gigas Bonecutter');
MOCK.entities[index].Status = 1;
round(id, ME);
text = frame();
_, left = enemy.progress(MOCK.now, id);
check('a monster hitting you starts from the kept 8 s', near(left, 8.0) and text ~= nil
    and text:find('8.00s est.', 1, true) ~= nil, tostring(left) .. ' ' .. tostring(text));
MOCK.entities[index].Status = 3;
defeat(id);
frame();

-- Someone else pulled it. It's already fighting when you target it, before cadence has seen a round
-- from it. The first round it sees sets the next one from the kept 8 s.
MOCK.now = MOCK.now + 100;
index, id = spawn('Gigas Bonecutter');
MOCK.entities[index].Status = 1;
MOCK.player.target_index = index;
frame();
round(id);
frame();
_, left = enemy.progress(MOCK.now, id);
check('one already fighting when you target it starts from the kept 8 s', near(left, 8.0), left);
MOCK.entities[index].Status = 3;
defeat(id);
frame();

-- It dies with no defeat message seen.
index = spawn('Goblin Smithy');
pull(index, 4.8, 3);
MOCK.entities[index].Status = 3;
frame();
check('kept when it dies', near(second_fight('Goblin Smithy'), 4.8));

-- It gives up the fight.
index = spawn('Forest Hare');
pull(index, 5.2, 3);
MOCK.entities[index].Status = 0;
frame();
check('kept when it gives up the fight', near(second_fight('Forest Hare'), 5.2));

-- You target another monster while it's still fighting, and it's already fighting too.
index = spawn('Ice Bat');
id = pull(index, 3.2, 3);
local next_bat, next_bat_id = spawn('Ice Bat');
MOCK.entities[next_bat].Status = 1;
MOCK.player.target_index = next_bat;
frame();
MOCK.now = MOCK.now + 0.5;
round(next_bat_id);
frame();
local _, bat_left, bat_delay = enemy.progress(MOCK.now, next_bat_id);
check('kept when the timer moves straight to another monster', near(bat_delay, 3.2) and near(bat_left, 3.2),
    tostring(bat_left) .. ' ' .. tostring(bat_delay));
MOCK.entities[next_bat].Status = 3;
defeat(next_bat_id);
MOCK.entities[index].Status = 3;
defeat(id);

-- It goes quiet while you target nothing. Keep the last monster lets go of it.
index = spawn('Giant Bee');
pull(index, 4.4, 3);
MOCK.player.target_index = 0;
check('still followed for a while', frame(5) ~= nil);
frame(10);
check('kept when it goes quiet', near(second_fight('Giant Bee'), 4.4));

-- Hojo: Ni is on it when it dies. Its speed with no Slow on is what's kept.
index, id = spawn('Gigas Slowed');
pull(index, 8.0, 3);
MOCK.fire('packet_in', MOCK.action_packet(ME, 4, 345, id, { { message = 236, damage = monster_effects.SLOW } }));
for i = 1, 3 do
    MOCK.now = MOCK.now + ((i == 1) and 8.0 or 9.6);
    round(id);
    frame();
end
local _, _, slowed = enemy.progress(MOCK.now, id);
check('it attacks slower under Hojo', near(slowed, 9.6, 0.001), slowed);
defeat(id);
MOCK.entities[index].Status = 3;
frame();
check('a monster slowed when it died is kept at its plain speed', near(second_fight('Gigas Slowed'), 8.0));

-- With the enemy timer off, nothing is read or kept, and no clock is made.
local player = require('core.player');
local names_read = 0;
local entity_name = player.entity_name;
player.entity_name = function (...) names_read = names_read + 1; return entity_name(...); end
MOCK.fire('command', { command = '/cadence enemy off' });
index, id = spawn('Gigas Bonecutter');
pull(index, 4.0, 3);
check('the timer off makes no clock for a kept name', not enemy.has(id) and names_read == 0, names_read);
MOCK.entities[index].Status = 3;
defeat(id);
frame();
MOCK.fire('command', { command = '/cadence enemy on' });
check('the timer off changes nothing kept', near(second_fight('Gigas Bonecutter'), 8.0));
player.entity_name = entity_name;

-- Another character logs in. What the last one learned is gone.
MOCK.settings.switch_character(nil);
s = MOCK.settings.current;
s.enemy.enabled = true;
zone(102);
check('another character starts from 4.0', near(second_fight('Gigas Bonecutter'), 4.0) and near(second_fight('Goblin Smithy'), 4.0));

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
