-- Keep the last monster. The enemy timer stays on the monster it was following while you target a
-- party member, an NPC or nothing, until that monster dies, stops fighting or goes quiet.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

local enemy = require('core.enemy');
local monster_effects = require('core.monster_effects');

local ME, TANK = 1001, 2001;
local MOB, MOB2, SHEEP, TREANT = 0x01000200, 0x01000201, 0x01000202, 0x01000805;

-- Active on its own -------------------------------------------------------------------------------
do
    enemy.reset();
    check('no clock, not active', not enemy.active(0, MOB));

    enemy.on_engage(100, MOB);
    check('engaging counts', enemy.active(109.9, MOB) and not enemy.active(110.1, MOB));
    enemy.on_round(110.5, MOB, TANK);
    check('a round on someone else counts', enemy.active(120.4, MOB) and not enemy.active(120.6, MOB));
    enemy.on_paralyzed(121, MOB, TANK);
    check('so does a paralyzed round', enemy.active(130.9, MOB) and not enemy.active(131.1, MOB));

    -- A long spell 1 s after a round. Its next round comes 2 s after the spell, plus the 3 s it had left.
    enemy.reset();
    enemy.on_round(0, MOB, TANK);
    enemy.on_hold_begin(1, MOB, 'spell');
    check('an active spell remains followed beyond the ordinary quiet window', enemy.active(10.9, MOB) and enemy.active(30, MOB));
    enemy.on_hold_end(8, MOB, false);
    check('and so does it ending', enemy.active(12.9, MOB) and enemy.active(17.9, MOB) and not enemy.active(18.1, MOB));

    -- A monster that attacks with a TP move, like a flying wyrm.
    enemy.reset();
    enemy.on_round(0, MOB, TANK);
    enemy.on_hold_end(4, MOB, false);
    check('a TP move in place of a round counts', enemy.active(13.9, MOB));

    -- Someone's Slow landing on it isn't the monster doing anything.
    enemy.reset();
    enemy.on_round(0, MOB, TANK);
    enemy.on_effect(5, MOB, { effect = monster_effects.SLOW, power = 1250, exact = false, sure_for = 60, lasts = 180 },
        false);
    check('an effect landing on it doesn\'t count', not enemy.active(10.1, MOB));

    -- A slow monster under Slow II and Carnage Elegy attacks about every 11 s. It gets one and a half of
    -- its own delay instead of 10 s.
    enemy.reset();
    enemy.on_engage(0, MOB);
    local t = 0;
    for _ = 1, 5 do t = t + 6.4; enemy.on_round(t, MOB, TANK); end
    enemy.on_effect(t, MOB, monster_effects.landed(4, 79, 236, 13), false);
    enemy.on_effect(t, MOB, monster_effects.landed(4, 422, 237, 194), false);
    local _, _, slowed = enemy.progress(t, MOB);
    check('the slowed monster attacks over 10 s apart', slowed > 10, slowed);
    check('it stays active past 10 s', enemy.active(t + 12, MOB));
    check('and lets go after one and a half of its delay', enemy.active(t + slowed * 1.5 - 0.1, MOB)
        and not enemy.active(t + slowed * 1.5 + 0.1, MOB), slowed * 1.5);

    enemy.reset();
    check('zoning clears it', not enemy.active(0.1, MOB));
end

-- The whole addon ---------------------------------------------------------------------------------
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
s.enemy.enabled = true;

local PARTY, NPC = 0x010, 0x300;
MOCK.entities[0x200] = { ServerId = MOB, Name = 'Young Quadav', Status = 1, SpawnFlags = 0x10 };
MOCK.entities[0x201] = { ServerId = MOB2, Name = 'Goblin Thug', Status = 1, SpawnFlags = 0x10 };
MOCK.entities[0x202] = { ServerId = SHEEP, Name = 'Mad Sheep', Status = 0, SpawnFlags = 0x10 };
MOCK.entities[0x705] = { ServerId = TREANT, Name = 'Twinkling Treant', Status = 1, SpawnFlags = 0x10 };
MOCK.entities[PARTY] = { ServerId = TANK, Name = 'Tankman', Status = 1, SpawnFlags = 0x01 };
MOCK.entities[NPC] = { ServerId = 0x01000300, Name = 'Some NPC', Status = 0, SpawnFlags = 0x02 };
local NAMES = { 'Young Quadav', 'Goblin Thug', 'Mad Sheep', 'Twinkling Treant' };

local function packet(p) MOCK.fire('packet_in', p); end
local function round_on(actor, target) packet(MOCK.action_packet(actor, 1, 0, target, { { message = 1 } })); end
local function target(index) MOCK.player.target_index = index; end
local function zone() packet(MOCK.zone_packet(ME)); end

-- The monster's name on the enemy timer after one frame at `now`, or nil when the timer isn't drawn.
local function shown(now)
    MOCK.now = now or MOCK.now;
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    local inside, drawn, words = false, false, {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'Begin') then
            inside = c[2] == '##cadence_enemy';
            drawn = drawn or inside;
        end
        if (inside and c[1] == 'dl:AddText') then table.insert(words, tostring(c[6])); end
    end
    if (not drawn) then return nil; end
    local text = table.concat(words, '|');
    for _, name in ipairs(NAMES) do
        if (text:find(name, 1, true)) then return name; end
    end
    return text;
end
local function expect(label, want, now)
    local name = shown(now);
    check(label, name == want, tostring(name));
end

check('on by default', require('ui.defaults').make().enemy.keep_last == true);

-- Your target fights the tank, then you target a party member, an NPC or nothing.
target(0x200);
MOCK.now = 100;
round_on(MOB, TANK);
expect('follows the monster you target', 'Young Quadav');
target(PARTY);
expect('a party member targeted keeps it', 'Young Quadav');
target(NPC);
expect('so does an NPC', 'Young Quadav');
target(0);
expect('and nothing', 'Young Quadav');
round_on(MOB2, ME);
expect('a monster hitting you doesn\'t take it over', 'Young Quadav');

target(PARTY);
local stayed = true;
for i = 1, 4 do
    MOCK.now = 100 + 4 * i;
    round_on(MOB, TANK);
    stayed = stayed and shown() == 'Young Quadav';
end
check('it stays while it keeps fighting', stayed);
expect('still 10 s after its last round', 'Young Quadav', 125.9);
expect('then it goes quiet and is let go', nil, 126.1);

-- The monster it fell back to, hitting you with nothing targeted, is kept the same way.
target(0);
MOCK.now = 130;
round_on(MOB2, ME);
expect('falls back to whoever hits you', 'Goblin Thug');
target(PARTY);
MOCK.now = 131;
round_on(MOB2, TANK);
expect('and keeps that one once it turns to the tank', 'Goblin Thug');

-- Targeting another monster switches to it, the same as with the setting off. Targeting an idle one
-- lets go of the kept one.
target(0x200);
MOCK.now = 136;
round_on(MOB, TANK);
expect('targeting another monster switches to it', 'Young Quadav');
target(PARTY);
expect('and that one is kept', 'Young Quadav');
target(0x202);
expect('an idle monster targeted lets it go', nil);
target(PARTY);
expect('then there\'s nothing to keep', nil);

-- A target you pull counts from when it engages, before its first round.
zone();
target(0x202);
expect('an idle target shows nothing', nil, 140);
MOCK.entities[0x202].Status = 1;
expect('the pull shows it', 'Mad Sheep');
target(PARTY);
expect('kept before its first round', 'Mad Sheep', 141);
expect('until 10 s after it engaged', 'Mad Sheep', 149.9);
expect('then let go', nil, 150.2);
MOCK.entities[0x202].Status = 0;

-- A long spell holds its next round back for more than 10 s.
zone();
target(0x200);
MOCK.now = 160;
round_on(MOB, TANK);
expect('a caster', 'Young Quadav');
target(PARTY);
MOCK.now = 161;
packet(MOCK.action_packet(MOB, 8, 0x68776163, TANK, { { message = 0 } }));
expect('kept while it casts past 10 s', 'Young Quadav', 170.5);
MOCK.now = 170.6;
packet(MOCK.action_packet(MOB, 4, 176, TANK, { { message = 2 } }));
expect('and after the spell until its next round', 'Young Quadav', 175.4);

-- Dying, giving up the fight and walking out of sight each let it go.
local function kept_then(label, change, undo)
    zone();
    target(0x200);
    round_on(MOB, TANK);
    shown();
    target(PARTY);
    local before = shown();
    change();
    local after = shown();
    check(label, before == 'Young Quadav' and after == nil, tostring(before) .. ' then ' .. tostring(after));
    undo();
end
MOCK.now = 180;
kept_then('it dies', function () MOCK.entities[0x200].Status = 3; end, function () MOCK.entities[0x200].Status = 1; end);
check('and its clock goes', not enemy.has(MOB));
kept_then('it disengages', function () MOCK.entities[0x200].Status = 0; end, function () MOCK.entities[0x200].Status = 1; end);
local quadav = MOCK.entities[0x200];
kept_then('it walks out of sight', function () MOCK.entities[0x200] = nil; end, function () MOCK.entities[0x200] = quadav; end);

-- A monster a script spawned has an id that isn't its index.
zone();
target(0x705);
MOCK.now = 190;
round_on(TREANT, TANK);
expect('a spawned monster', 'Twinkling Treant');
target(PARTY);
expect('is kept too', 'Twinkling Treant');

-- Turned off, and the other two Follows choices.
zone();
s.enemy.keep_last = false;
target(0x200);
MOCK.now = 200;
round_on(MOB, TANK);
expect('turned off', 'Young Quadav');
target(PARTY);
expect('a party member target lets it go', nil);

s.enemy.keep_last = true;
s.enemy.which = 'target';
target(0x200);
expect('my target only', 'Young Quadav');
target(PARTY);
expect('keeps it too', 'Young Quadav');
s.enemy.keep_last = false;
expect('but not turned off', nil);
s.enemy.keep_last = true;

zone();
s.enemy.which = 'attacker';
target(0x200);
MOCK.now = 210;
round_on(MOB, TANK);
target(PARTY);
expect('whoever hits me keeps nothing on the tank', nil);
s.enemy.which = 'target_first';

-- Picking a party member for a spell with <stpc> still holds your target, with the setting off too.
zone();
s.enemy.keep_last = false;
target(0x200);
MOCK.now = 220;
round_on(MOB, TANK);
expect('before the pick', 'Young Quadav');
MOCK.player.subtargeting, MOCK.player.held_target_index = true, 0x200;
target(PARTY);
expect('picking a party member for a spell keeps it', 'Young Quadav', 229);
expect('past 10 s too, since it\'s still your target', 'Young Quadav', 231);
MOCK.player.subtargeting, MOCK.player.held_target_index = false, nil;
s.enemy.keep_last = true;

-- The setting sits under Follows, greyed out following whoever hits you.
local function window_calls()
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    return MOCK.imgui_calls;
end
local function find_setting(calls)
    local order, disabled = {}, nil;
    for i, c in ipairs(calls) do
        if ((c[1] == 'BeginCombo' and c[2] == 'Follows##enemy') or (c[1] == 'Checkbox'
            and (c[2] == 'Keep the last monster' or c[2] == 'Attach under auto attack'))) then
            table.insert(order, c[2]);
        end
        if (c[1] == 'Checkbox' and c[2] == 'Keep the last monster') then
            local before = calls[i - 1];
            disabled = 'no BeginDisabled';
            if (before ~= nil and before[1] == 'BeginDisabled') then disabled = before[2]; end
        end
    end
    return table.concat(order, ', '), disabled;
end
MOCK.fire('command', { command = '/cadence' });
local order, disabled = find_setting(window_calls());
check('it sits right under Follows', order == 'Follows##enemy, Keep the last monster, Attach under auto attack', order);
check('live following your target first', disabled == false, tostring(disabled));
s.enemy.which = 'target';
order, disabled = find_setting(window_calls());
check('and your target only', disabled == false, tostring(disabled));
s.enemy.which = 'attacker';
order, disabled = find_setting(window_calls());
check('greyed out following whoever hits you', disabled == true, tostring(disabled));
s.enemy.which = 'target_first';

rawset(require('imgui'), 'IsItemHovered', function () return true; end);
local calls = window_calls();
rawset(require('imgui'), 'IsItemHovered', nil);
local tip, after = nil, false;
for _, c in ipairs(calls) do
    if (c[1] == 'Checkbox') then after = c[2] == 'Keep the last monster'; end
    if (after and tip == nil and c[1] == 'TextUnformatted') then tip = tostring(c[2]); end
end
check('its tip says what it keeps and when it lets go', tip ~= nil and tip:find('party member', 1, true) ~= nil
    and tip:find('10 s', 1, true) ~= nil, tip);
MOCK.fire('command', { command = '/cadence' });

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
