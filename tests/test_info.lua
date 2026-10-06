-- /cadence info. The getters it reads on their own, then what it says through the whole addon as the
-- delay, TP per hit, TP from being hit and resting pattern get learned, through zoning and another
-- character.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

local attack = require('core.attack');
local resting = require('core.resting');

-- Keys in the form delay.key makes. That's weapons, jobs and levels, then the buff ids. 33 is Haste and
-- 214 is March.
local PLAIN, OTHER, HASTE, MARCH = '1:0:1/75:0/0:', '2:0:1/75:0/0:', '1:0:1/75:0/0:33', '1:0:1/75:0/0:214';

-- `n` rounds `gap` apart with `key`, after time `t`. Returns the time of the last one.
local function rounds(t, n, gap, key, estimate)
    for _ = 1, n do
        t = t + gap;
        attack.on_round(t, estimate or 4.0, key);
    end
    return t;
end
local function guess(estimate, key)
    local d, learned, e = attack.delay_in_use(estimate, key);
    return ('%.2f %s %.2f'):format(d, tostring(learned), e);
end
-- What an engage with `estimate` and `key` starts on, written the same way as guess().
local function engaged_on(t, estimate, key)
    attack.engage(t, estimate, key);
    local _, _, d = attack.progress(t);
    return ('%.2f %s %.2f'):format(d, tostring(attack.is_learned()), estimate);
end

-- The delay out of a fight is the one an engage would start on ------------------------------------------
attack.forget_learned();
attack.reset();
check('nothing learned, so the estimate', guess(4.0, PLAIN) == '4.00 false 4.00', guess(4.0, PLAIN));
check('no keys kept', attack.kept_count() == 0, attack.kept_count());

attack.engage(0, 4.0, PLAIN);
local t = rounds(0, 5, 3.6, PLAIN);
check('in a fight it\'s the delay in use, whatever is passed', guess(9.9, OTHER) == '3.60 true 4.00', guess(9.9, OTHER));
check('one key kept', attack.kept_count() == 1, attack.kept_count());
attack.disengage();
check('out of a fight it\'s the learned one for that key', guess(4.0, PLAIN) == '3.60 true 4.00', guess(4.0, PLAIN));
check('a key with nothing learned is the estimate', guess(3.41, HASTE) == '3.41 false 3.41', guess(3.41, HASTE));

-- Gaps within 0.04 s of the estimate show the estimate, like the bar.
attack.engage(t + 5, 4.0, OTHER);
t = rounds(t + 5, 4, 3.98, OTHER);
check('two keys kept', attack.kept_count() == 2, attack.kept_count());
attack.disengage();
check('a learned delay close to the estimate shows the estimate', guess(4.0, OTHER) == '4.00 true 4.00',
    guess(4.0, OTHER));
check('and an engage starts on the same', engaged_on(t + 10, 4.0, OTHER) == '4.00 true 4.00',
    engaged_on(t + 10, 4.0, OTHER));
attack.disengage();

-- Two gaps aren't enough to count.
attack.engage(t + 20, 3.41, HASTE);
t = rounds(t + 20, 3, 3.1, HASTE, 3.41);
check('two gaps are not a kept key', attack.kept_count() == 2, attack.kept_count());
attack.disengage();
check('and out of a fight that key is still the estimate', guess(3.41, HASTE) == '3.41 false 3.41', guess(3.41, HASTE));
check('a close learned delay snaps to its own estimate, not the last fight\'s', guess(4.0, OTHER) == '4.00 true 4.00',
    guess(4.0, OTHER));

-- Looking doesn't change which keys are kept. Using 17 new keys would drop PLAIN.
for i = 1, 20 do attack.delay_in_use(4.0, 'new' .. i); end
check('looking at 20 new keys keeps every learned one', attack.kept_count() == 2, attack.kept_count());
check('PLAIN still starts learned', engaged_on(t + 30, 4.0, PLAIN) == '3.60 true 4.00', engaged_on(t + 30, 4.0, PLAIN));

-- March starts over each time it's a new key, but not while the same key stays on.
t = rounds(t + 30, 5, 3.3, MARCH, 3.76);
check('March learned while it lasts', guess(0, PLAIN) == '3.30 true 3.76', guess(0, PLAIN));
check('the March key in use is counted', attack.kept_count() == 3, attack.kept_count());
attack.disengage();
check('out of a fight with the same March still on, it\'s kept', guess(3.76, MARCH) == '3.30 true 3.76',
    guess(3.76, MARCH));
check('and an engage starts on it', engaged_on(t + 10, 3.76, MARCH) == '3.30 true 3.76', engaged_on(t + 10, 3.76, MARCH));
t = rounds(t + 10, 1, 3.3, PLAIN);
attack.disengage();
check('once another key is used, March isn\'t counted', attack.kept_count() == 2, attack.kept_count());
check('and the next March is the estimate', guess(3.76, MARCH) == '3.76 false 3.76', guess(3.76, MARCH));
check('which is what an engage starts on', engaged_on(t + 10, 3.76, MARCH) == '3.76 false 3.76',
    engaged_on(t + 10, 3.76, MARCH));

-- Zoning keeps the exact keys. A March key in use doesn't come back after it.
t = rounds(t + 10, 5, 3.3, MARCH, 3.76);
check('March in use is counted again', attack.kept_count() == 3, attack.kept_count());
attack.reset();
check('after zoning only the exact keys are counted', attack.kept_count() == 2, attack.kept_count());
check('PLAIN after zoning', guess(4.0, PLAIN) == '3.60 true 4.00', guess(4.0, PLAIN));
check('March after zoning is the estimate', guess(3.76, MARCH) == '3.76 false 3.76', guess(3.76, MARCH));
attack.forget_learned();
check('another character has nothing kept', attack.kept_count() == 0 and guess(4.0, PLAIN) == '4.00 false 4.00',
    guess(4.0, PLAIN));
attack.reset();

-- The resting pattern is known after two gaps between ticks, and starts over each time you sit.
resting.reset();
resting.on_vitals(0, 1000, 0, 0, 1200, 0);
resting.start(0);
check('not known when you sit', not resting.pattern_known());
resting.on_vitals(1, 500, 0, 0, 1200, 0);
resting.on_vitals(21.4, 520, 0, 0, 1200, 0);
check('not known after the first tick', not resting.pattern_known());
resting.on_vitals(30.4, 541, 0, 0, 1200, 0);
check('not known after one gap', not resting.pattern_known());
resting.on_vitals(42.4, 563, 0, 0, 1200, 0);
check('known after two gaps', resting.pattern_known());
resting.stop();
resting.start(60);
check('sitting again starts over', not resting.pattern_known());
resting.reset();

-- Through the whole addon -----------------------------------------------------------------------------
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };   -- a 240 delay sword, 4.00 s and 64 TP a hit on WAR/NIN
MOCK.items[16540] = { Delay = 264, Skill = 3 };   -- a 264 delay sword, 4.40 s
MOCK.player.equipment[0] = 16535;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local tp = require('core.tp');
local json = require('json');

local ME, MOB = 1001, 0x01000200;
local HASTE_BUFF = 33;

-- Runs a command. Returns what it printed, without the [cadence] header, and whether it was blocked.
local function said(command)
    local before = #MOCK.printed;
    local e = { command = command };
    MOCK.fire('command', e);
    local lines = {};
    for i = before + 1, #MOCK.printed do
        table.insert(lines, (MOCK.printed[i]:gsub('^%[cadence%] ', '')));
    end
    return lines, e.blocked;
end
local function info() return said('/cadence info'); end
local function round(gap, results)
    MOCK.now = MOCK.now + gap;
    MOCK.fire('packet_in', MOCK.action_packet(ME, 1, 0, MOB, results or { { message = 1 } }));
end
local hp, tp_now = 1000, 0;
local function vitals(at, new_hp, new_tp)
    MOCK.now = at or MOCK.now;
    hp, tp_now = new_hp or hp, new_tp or tp_now;
    MOCK.fire('packet_in', MOCK.vitals_packet(ME, hp, 0, tp_now));
end
local function status(value)
    MOCK.player.status = value;
    MOCK.frame(1 / 60);
end

local FIRST = ('This is what cadence %s has worked out about you right now.'):format(addon.version);
local NOT_RESTING = 'You aren\'t resting. The resting timer learns the 9, 9, 12 pattern again each time you '
    .. 'start resting.';

MOCK.now = 100;
local lines, blocked = info();
check('before anything, every line', table.concat(lines, '|') == table.concat({
    FIRST,
    'Your auto attack delay is 4.00 s est. It isn\'t learned from your attacks yet.',
    'Your weapons, job and buffs alone say 4.00 s.',
    'cadence has no learned delays saved yet.',
    'Your TP per hit is 64. It isn\'t locked in yet.',
    NOT_RESTING,
}, '|'), table.concat(lines, '|'));
check('the command is blocked', blocked == true);

check('info changes and saves nothing', (function ()
    local saves, before = MOCK.saved, json.encode(s);
    info();
    return MOCK.saved == saves and json.encode(s) == before;
end)());
check('/cad info, any case and extra words say the same',
    table.concat(said('/cad INFO please'), '|') == table.concat(info(), '|'));

-- Engaged and learned. The weapon still says 4.00 s.
status(1);
round(1.6);
for _ = 1, 4 do round(3.6); end
lines = info();
check('a learned delay', lines[2] == 'Your auto attack delay is 3.60 s, learned from your attacks.', lines[2]);
check('with what the weapon says', lines[3] == 'Your weapons, job and buffs alone say 4.00 s.', lines[3]);
check('one mix', lines[4] == 'cadence has a learned delay saved for 1 mix of weapons, jobs and buffs.', lines[4]);
check('TP per hit is the first guess', lines[5] == 'Your TP per hit is 64. It isn\'t locked in yet.', lines[5]);

-- A weapon swapped mid-fight counts from the next round. Until then the bar and info keep the old one.
MOCK.player.equipment[0] = 16540;
lines = info();
check('mid-fight, the delay in use until the next round', lines[2] == 'Your auto attack delay is 3.60 s, learned from '
    .. 'your attacks.' and lines[3] == 'Your weapons, job and buffs alone say 4.00 s.', lines[2] .. ' ' .. lines[3]);
status(0);
lines = info();
check('out of the fight it\'s the weapon you hold', lines[2] == 'Your auto attack delay is 4.40 s est. It isn\'t '
    .. 'learned from your attacks yet.' and lines[3] == 'Your weapons, job and buffs alone say 4.40 s.',
    lines[2] .. ' ' .. lines[3]);
check('and TP per hit for it too', lines[5] == 'Your TP per hit is 70. It isn\'t locked in yet.', lines[5]);
MOCK.player.equipment[0] = 16535;
lines = info();
check('and the first one comes back learned', lines[2] == 'Your auto attack delay is 3.60 s, learned from your attacks.',
    lines[2]);
check('with its own TP per hit', lines[5] == 'Your TP per hit is 64. It isn\'t locked in yet.', lines[5]);

-- Haste is its own mix.
status(1);
round(1.6);
MOCK.player.buffs = { HASTE_BUFF };
round(3.6);
lines = info();
check('Haste starts on its estimate', lines[2] == 'Your auto attack delay is 3.41 s est. It isn\'t learned from '
    .. 'your attacks yet.' and lines[3] == 'Your weapons, job and buffs alone say 3.41 s.', lines[2] .. ' ' .. lines[3]);
for _ = 1, 3 do round(3.1); end
lines = info();
check('Haste learned', lines[2] == 'Your auto attack delay is 3.10 s, learned from your attacks.', lines[2]);
check('two mixes', lines[4] == 'cadence has learned delays saved for 2 mixes of weapons, jobs and buffs.', lines[4]);
MOCK.player.buffs = {};
round(3.1);

-- TP per hit locks in from two rounds that agree. Store TP the client can't see makes it 70.
vitals(nil, nil, 0);
round(3.6);
vitals(nil, nil, 70);
lines = info();
check('one sample isn\'t locked in', lines[5] == 'Your TP per hit is 64. It isn\'t locked in yet.', lines[5]);
round(3.6);
vitals(nil, nil, 140);
lines = info();
check('two agreeing samples are', lines[5] == 'Your TP per hit is 70 and it\'s locked in. It started from 64.', lines[5]);
local value, locked, first = tp.per_hit();
check('tp.per_hit gives the first guess third', value == 70 and locked and first == 64,
    tostring(value) .. ' ' .. tostring(locked) .. ' ' .. tostring(first));
check('nothing has come from being hit, so there\'s no line for it', #lines == 6, #lines);

-- In a fight it says how much more TP a round has lately come from other things, once that's 1 or more.
-- 21 TP your hits don't explain moves it a third of the way, to 7. Five rounds that only get their own
-- 70 take it under 1. Another 21 takes it to 7.6.
local function from_others(n)
    return ('Lately about %d more TP a round has come from other things, like being hit or Regain.'):format(n);
end
local function hit_round() round(3.6); vitals(nil, nil, tp_now + 70); end
vitals(nil, nil, 161);
round(3.6);
lines = info();
check('TP from being hit shows in a fight', lines[6] == from_others(7) and lines[7] == NOT_RESTING, lines[6]);
for _ = 1, 4 do hit_round(); end
lines = info();
check('it fades with nothing more', lines[6] == from_others(1), lines[6]);
hit_round();
lines = info();
check('and goes once it\'s under 1', #lines == 6 and lines[6] == NOT_RESTING, lines[6]);
vitals(nil, nil, tp_now + 21);
round(3.6);
lines = info();
check('7.6 says about 8', lines[6] == from_others(8), lines[6]);
s.attack.show_tp = false;
lines = info();
s.attack.show_tp = true;
check('with the TP line off it isn\'t said', #lines == 6, #lines);

-- Resting. The pattern is known after the third tick.
status(33);
local sat = MOCK.now;
vitals(sat + 1, 500);
lines = info();
check('out of a fight TP from being hit isn\'t said', #lines == 6, #lines);
check('resting, not known yet', lines[6] == 'The resting timer hasn\'t seen enough ticks to know the 9, 9, 12 '
    .. 'pattern yet.', lines[6]);
vitals(sat + 21.4, 520);
vitals(sat + 30.4, 541);
lines = info();
check('two ticks are not enough', lines[6] == 'The resting timer hasn\'t seen enough ticks to know the 9, 9, 12 '
    .. 'pattern yet.', lines[6]);
vitals(sat + 42.4, 563);
lines = info();
check('three ticks are', lines[6] == 'The resting timer has seen enough ticks to know the 9, 9, 12 pattern.', lines[6]);
status(0);
lines = info();
check('standing up, it says it learns it again', lines[6] == NOT_RESTING, lines[6]);

-- Zoning keeps what was learned.
MOCK.fire('packet_in', MOCK.zone_packet(ME));
MOCK.frame(1 / 60);
lines = info();
check('zoning keeps the delay', lines[2] == 'Your auto attack delay is 3.60 s, learned from your attacks.'
    and lines[4] == 'cadence has learned delays saved for 2 mixes of weapons, jobs and buffs.', lines[2] .. ' ' .. lines[4]);
check('and TP per hit', lines[5] == 'Your TP per hit is 70 and it\'s locked in. It started from 64.', lines[5]);

-- Another character starts over on the delay.
MOCK.settings.switch_character(nil);
lines = info();
check('another character has no delays saved', lines[2] == 'Your auto attack delay is 4.00 s est. It isn\'t learned '
    .. 'from your attacks yet.' and lines[4] == 'cadence has no learned delays saved yet.', lines[2] .. ' ' .. lines[4]);
check('or TP per hit', lines[5] == 'Your TP per hit is 64. It isn\'t locked in yet.', lines[5]);
check('or TP from being hit', tp.other_per_round() == 0, tp.other_per_round());

-- With the TP line off, TP per hit isn't learned, and info says why.
local tp_was = MOCK.settings.current.attack.show_tp;
MOCK.settings.current.attack.show_tp = false;
lines = info();
check('TP per hit says it needs the TP line', lines[5] == 'Your TP per hit is 64. It\'s only learned while the auto '
    .. 'attack timer and Your TP are on.', lines[5]);
MOCK.settings.current.attack.show_tp = tp_was;

-- With the enemy timer on, it still says nothing about monsters.
s.enemy.enabled = true;
lines = info();
local about_monsters = nil;
for _, line in ipairs(lines) do
    local lower = line:lower();
    if (lower:find('monster', 1, true) or lower:find('enemy', 1, true)) then about_monsters = line; end
end
check('six lines and nothing about monsters', #lines == 6 and about_monsters == nil, about_monsters or #lines);

-- Help lists it, and stays short.
local help = said('/cadence help');
local listed = false;
for _, line in ipairs(help) do
    if (line == '/cadence info  says what cadence has worked out about you, like your delay and TP per hit.') then
        listed = true;
    end
end
check('help lists it', listed);
check('help is still 20 lines or fewer', #help <= 20, #help);

-- Every line reads like everything else in cadence.
local odd = nil;
for _, line in ipairs(MOCK.printed) do
    if (line:find(';', 1, true) or line:find('\226\128\148', 1, true) or line:find('\226\128\147', 1, true)
        or line:find('Didn\'t recognize', 1, true) or line:find('Drawing stopped', 1, true)) then
        odd = line;
    end
end
check('no semicolons, dashes, unknown words or drawing errors', odd == nil, odd);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
