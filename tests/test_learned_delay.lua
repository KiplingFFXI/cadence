-- The auto attack delay learned for each key. It's kept through buff changes and zoning, for the
-- last 16 keys, and dropped when another character logs in. Then the same through the whole addon, and
-- a March that wears off between fights.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end
local function near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 1e-6); end

local attack = require('core.attack');

-- `n` rounds `gap` apart with `key`, after time `t`. Returns the time of the last one.
local function rounds(t, n, gap, key, estimate)
    for _ = 1, n do
        t = t + gap;
        attack.on_round(t, estimate or 4.0, key);
    end
    return t;
end
local function delay_in_use(t) local _, _, d = attack.progress(t); return d; end

-- Haste lands and wears off. Each key keeps its own gaps.
attack.reset();
attack.engage(0, 4.0, 'plain');
local t = rounds(0, 5, 3.6, 'plain');
check('learns the plain delay', attack.is_learned() and near(delay_in_use(t), 3.6), delay_in_use(t));
t = rounds(t, 1, 3.6, 'haste', 3.41);
check('a new key starts on the estimate', not attack.is_learned() and near(delay_in_use(t), 3.41), delay_in_use(t));
t = rounds(t, 4, 3.1, 'haste', 3.41);
check('learns the hasted delay', attack.is_learned() and near(delay_in_use(t), 3.1), delay_in_use(t));
t = rounds(t, 1, 3.1, 'plain');
check('Haste wearing off brings back the plain delay', attack.is_learned() and near(delay_in_use(t), 3.6), delay_in_use(t));
t = rounds(t, 1, 3.6, 'haste', 3.41);
check('Haste landing again brings back the hasted delay', attack.is_learned() and near(delay_in_use(t), 3.1), delay_in_use(t));

-- Zoning keeps it. The first attack still comes 2.8 s after you engage.
t = rounds(t, 1, 3.1, 'plain');
attack.reset();
check('nothing is shown between zoning and engaging', attack.progress(t) == nil and not attack.is_learned());
t = t + 60;
attack.engage(t, 4.0, 'plain');
local _, left = attack.progress(t);
check('after zoning the learned delay is back', attack.is_learned() and near(delay_in_use(t), 3.6), delay_in_use(t));
check('the first attack is still 2.8 s out', near(left, 2.8), left);

-- Armor isn't in the key. After an armor change the kept gaps roll out as new ones come in.
t = rounds(t, 1, 1.6, 'plain');
t = rounds(t, 3, 3.2, 'plain');
check('new gaps mix with the kept ones', near(delay_in_use(t), 3.4), delay_in_use(t));
t = rounds(t, 3, 3.2, 'plain');
check('six new gaps replace them', near(delay_in_use(t), 3.2), delay_in_use(t));

-- March, Slow and Elegy change strength from one cast to the next, so their keys start over each time.
-- Keys in the form delay.key makes. That's weapons, jobs and levels, then the buff ids.
local PLAIN, HASTE, MARCH = '1:0:1/75:0/0:', '1:0:1/75:0/0:33', '1:0:1/75:0/0:214';
attack.forget_learned();
attack.reset();
attack.engage(0, 4.0, PLAIN);
t = rounds(0, 5, 3.6, PLAIN);
t = rounds(t, 5, 3.3, MARCH, 3.76);
check('a March key learns while it lasts', attack.is_learned() and near(delay_in_use(t), 3.3), delay_in_use(t));
t = rounds(t, 5, 3.1, HASTE, 3.41);
t = rounds(t, 1, 3.3, MARCH, 3.76);
check('a new March starts on the estimate again', not attack.is_learned() and near(delay_in_use(t), 3.76), delay_in_use(t));
t = rounds(t, 1, 3.3, HASTE, 3.41);
check('Haste still comes back learned', attack.is_learned() and near(delay_in_use(t), 3.1), delay_in_use(t));
attack.reset();
attack.engage(t + 60, 3.76, MARCH);
check('and so does March after zoning', not attack.is_learned());

-- Only 16 keys are kept. Using one again makes it the newest.
attack.forget_learned();
attack.reset();
attack.engage(0, 4.0, 'k0');
t = rounds(0, 4, 3.6, 'k0');
check('k0 learned', attack.is_learned());
for i = 1, 15 do t = rounds(t, 1, 3.6, 'other' .. i); end
t = rounds(t, 1, 3.6, 'k0');
check('a key outlasts 15 others', attack.is_learned());
for i = 16, 30 do t = rounds(t, 1, 3.6, 'other' .. i); end
t = rounds(t, 1, 3.6, 'k0');
check('going back to a key keeps it longer', attack.is_learned());
for i = 31, 46 do t = rounds(t, 1, 3.6, 'other' .. i); end
t = rounds(t, 1, 3.6, 'k0');
check('16 newer keys drop it', not attack.is_learned());

-- Another character logs in. Nothing learned carries over, and learning starts over from there.
attack.forget_learned();
attack.reset();
attack.engage(0, 4.0, 'plain');
t = rounds(0, 5, 3.6, 'plain');
attack.forget_learned();
check('forgotten mid-fight', not attack.is_learned());
t = rounds(t, 1, 3.6, 'plain');
check('the next round starts over', not attack.is_learned() and near(delay_in_use(t), 4.0), delay_in_use(t));
t = rounds(t, 3, 3.6, 'plain');
t = rounds(t, 1, 3.6, 'haste', 3.41);
t = rounds(t, 1, 3.6, 'plain');
check('what it learns after that is kept', attack.is_learned() and near(delay_in_use(t), 3.6), delay_in_use(t));
attack.forget_learned();
attack.reset();
attack.engage(t, 4.0, 'plain');
check('the next engage starts over too', not attack.is_learned() and near(delay_in_use(t), 4.0), delay_in_use(t));

-- The whole addon. A 240 delay sword on WAR/NIN is 4.00 s. Gear haste makes it 3.60 s.
attack.forget_learned();
attack.reset();
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');

local ME, MOB = 1001, 0x01000200;
local HASTE = 33;

-- The small text next to AUTO ATTACK after one frame.
local function shown()
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddText' and tostring(c[6]):find('^%d+%.%d%ds')) then
            return c[6];
        end
    end
    return nil;
end
local function round(gap)
    MOCK.now = MOCK.now + gap;
    MOCK.fire('packet_in', MOCK.action_packet(ME, 1, 0, MOB, { { message = 1 } }));
end
local function engage()
    MOCK.player.status = 1;
    MOCK.frame(1 / 60);
end
local function zone()
    MOCK.player.status = 0;
    MOCK.fire('packet_in', MOCK.zone_packet(ME));
    MOCK.frame(1 / 60);
    engage();
end

MOCK.now = 100;
engage();
check('the addon starts on the estimate', shown() == '4.00s est.', shown());
round(1.6);
for _ = 1, 4 do round(3.6); end
check('the addon learns 3.60 s', shown() == '3.60s', shown());

MOCK.player.buffs = { HASTE };
round(3.6);
check('Haste starts on its estimate', (shown() or ''):find('est.', 1, true) ~= nil, shown());
MOCK.player.buffs = {};
round(3.4);
check('Haste wearing off shows 3.60 s again', shown() == '3.60s', shown());

zone();
check('zoning keeps 3.60 s', shown() == '3.60s', shown());

MOCK.settings.switch_character(nil);
zone();
check('another character starts on the estimate', shown() == '4.00s est.', shown());

-- Between fights with nothing on screen. After a fight with March on you, your buffs are read until it
-- wears off. A March sung after that is a new one and is measured again.
local MARCH = 214;
local player = require('core.player');
local buff_reads, read_buffs = 0, player.read_buffs;
player.read_buffs = function (...) buff_reads = buff_reads + 1; return read_buffs(...); end
local function disengage()
    MOCK.player.status = 0;
    MOCK.frame(1 / 60);
end
local function wait(seconds)
    for _ = 1, seconds * 60 do MOCK.frame(1 / 60); end
end
local function info_delay()
    local printed = #MOCK.printed;
    MOCK.fire('command', { command = '/cadence info' });
    for i = printed + 1, #MOCK.printed do
        if (MOCK.printed[i]:find('Your auto attack delay', 1, true)) then return MOCK.printed[i]; end
    end
    return '';
end

disengage();
MOCK.player.buffs = { MARCH };
engage();
round(2.8);
for _ = 1, 5 do round(3.2); end
check('a fight under March learns 3.20 s', shown() == '3.20s', shown());

disengage();
buff_reads = 0;
wait(20);
check('with March still on, your buffs are read five times a second', buff_reads >= 95 and buff_reads <= 101,
    buff_reads);
engage();
check('the same March staying on keeps 3.20 s', shown() == '3.20s', shown());

disengage();
wait(5);
MOCK.player.buffs = {};
wait(1);
MOCK.player.buffs = { MARCH };
wait(5);
check('/cadence info calls a new March an estimate', info_delay():find('3.76 s est.', 1, true) ~= nil, info_delay());
engage();
check('a new March starts on its estimate', shown() == '3.76s est.', shown());

-- The same in a fight. A March that wears off and lands again between two rounds is measured again.
round(2.8);
for _ = 1, 5 do round(3.2); end
check('the new March learns 3.20 s', shown() == '3.20s', shown());
MOCK.player.buffs = {};
wait(1);
MOCK.player.buffs = { MARCH };
wait(1);
round(1.2);
check('a March sung again mid-fight starts on its estimate', shown() == '3.76s est.', shown());

-- After a fight with no March, Slow or Elegy, nothing reads your buffs between fights.
MOCK.player.buffs = {};
round(3.2);
disengage();
buff_reads = 0;
wait(5);
check('after a fight without March, your buffs aren\'t read', buff_reads == 0, buff_reads);
player.read_buffs = read_buffs;

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
