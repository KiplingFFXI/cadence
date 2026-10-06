-- The TP line. Which hits give TP, learning TP per hit from your own rounds, what keeps a change
-- from counting, rounds to 1000, TP from being hit counting toward it, and the line under the auto
-- attack bar.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };   -- a 240 delay sword, 64 TP a hit
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local tp = require('core.tp');
local packets = require('core.packets');
local hud = require('ui.hud');
local player = require('core.player');
local theme = require('ui.theme');

local ME, MOB, OTHER = 1001, 0x01000200, 2001;
local HIT = { { message = 1 } };
local TWO_HITS = { { message = 1 }, { message = 1 } };
local MISS = { resolution = 1, message = 15 };
local COUNTERED = { { message = 1 }, { resolution = 1, message = 15, reaction = 63 } };
local SPIKES = 1;

local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do MOCK.frame(1 / 60); end
    MOCK.record_imgui = false;
end
local tp_now = 0;
local function vitals(value)
    tp_now = value;
    MOCK.fire('packet_in', MOCK.vitals_packet(ME, 1000, 0, value));
end
local function gain(n) vitals(tp_now + n); end
local function round(results) MOCK.fire('packet_in', MOCK.action_packet(ME, 1, 0, MOB, results or HIT)); end
local function later(seconds) MOCK.now = MOCK.now + (seconds or 3); end
local function per_hit() local value, learned = tp.per_hit(); return value, learned; end

-- Which results give TP.
local function hits_of(results) return packets.melee_hits(MOCK.action_packet(ME, 1, 0, MOB, results)); end
check('a hit gives TP', hits_of(HIT) == 1);
check('a critical hit gives TP', hits_of({ { message = 67 } }) == 1);
check('a guarded hit gives TP', hits_of({ { resolution = 2, message = 1 } }) == 1);
check('a blocked hit gives TP', hits_of({ { resolution = 4, message = 1 } }) == 1);
check('a miss gives none', hits_of({ { resolution = 1, message = 15 } }) == 0);
check('a parry gives none', hits_of({ { resolution = 3, message = 70 } }) == 0);
check('a shadow gives none', hits_of({ { message = 31, damage = 1 } }) == 0);
check('a hit for 0 gives none', hits_of({ { message = 1, damage = 0 } }) == 0);
check('a hit and a miss is one', hits_of({ { message = 1 }, { resolution = 1, message = 15 } }) == 1);
check('reads past an added effect', hits_of({ { message = 1, add_effect = true }, { message = 1 } }) == 2);
local hits, hit_back, clean_start = hits_of(COUNTERED);
check('a countered attack flags the round', hits == 1 and hit_back == true, tostring(hits) .. ' ' .. tostring(hit_back));
hits, hit_back = hits_of({ { message = 1, reaction = SPIKES }, { message = 1 } });
check('reads past spikes without flagging them', hits == 2 and hit_back == false, tostring(hits) .. ' ' .. tostring(hit_back));
hits, hit_back, clean_start = hits_of(TWO_HITS);
check('no counter, no flag', hits == 2 and hit_back == false);
check('a first hit is a clean start', clean_start == true);
hits, hit_back, clean_start = hits_of({ MISS, { message = 1 } });
check('a first miss is not', hits == 1 and clean_start == false, tostring(hits) .. ' ' .. tostring(clean_start));
check('a first guarded hit is not', select(3, hits_of({ { resolution = 2, message = 1 } })) == false);

-- The delay TP is worked out from. Fists split theirs, and one bare hand without them attacks once.
local delay = require('core.delay');
local function bare(main_job, sub_job, sub_used)
    return { main = nil, sub = nil, sub_used = sub_used, main_job = main_job, main_level = 75,
        sub_job = sub_job, sub_level = 37, buffs = {} };
end
check('WAR fists split 480', delay.tp_delay(bare(1, 13, false)) == 240 and delay.attacks_twice(bare(1, 13, false)));
check('WHM/BLM bare-handed is one 480 attack', delay.tp_delay(bare(3, 4, false)) == 480 and not delay.attacks_twice(bare(3, 4, false)));
check('a WHM with a hand-to-hand sub fights with fists', delay.attacks_twice(bare(3, 6, false)));
check('a shield means one bare-handed attack', delay.tp_delay(bare(1, 13, true)) == 480 and not delay.attacks_twice(bare(1, 13, true)));
check('MNK fists after Martial Arts', delay.tp_delay(bare(2, 13, false)) == 150, delay.tp_delay(bare(2, 13, false)));
MOCK.items[12292] = { Delay = 0, Skill = 0 };   -- a shield
MOCK.player.equipment[1] = 12292;
local with_shield = player.read_loadout();
MOCK.player.equipment[1] = nil;
check('a shield is seen in the sub slot', with_shield.sub == nil and with_shield.sub_used == true);
check('an empty sub slot is seen too', player.read_loadout().sub_used == false);

-- Whether you're one of an action's targets, even after another target's added effect and spikes.
local aoe = MOCK.action_packet_multi(MOB, 11, 0, {
    { id = OTHER, results = { { message = 1, add_effect = true }, { message = 1, reaction = SPIKES } } },
    { id = ME, results = HIT },
});
check('finds you as a second target', packets.action_has_target(aoe, ME));
check('finds the first target', packets.action_has_target(aoe, OTHER));
check('someone else is not you', not packets.action_has_target(aoe, 3001));
check('a single other target is not you', not packets.action_has_target(MOCK.action_packet(MOB, 1, 0, OTHER, HIT), ME));

-- Nothing is known before you engage.
check('no rounds before anything is known', tp.rounds_to(1000, 0) == nil);

-- Engaged with a 240 delay sword, the first guess is 64 a hit. Two guessed rounds at 0.9 hits start
-- the average, so 16 hits takes 18 rounds.
MOCK.now = 100;
MOCK.player.status = 1;
frames(2);
local value, learned = per_hit();
check('first guess from the weapon', value == 64 and not learned, tostring(value) .. ' ' .. tostring(learned));
check('rounds from the guess', tp.rounds_to(1000, 0) == 18, tp.rounds_to(1000, 0));
check('no rounds at the goal', tp.rounds_to(1000, 1000) == nil and tp.rounds_to(1000, 1400) == nil);
check('one hit left is one round', tp.rounds_to(1000, 999) == 1, tp.rounds_to(1000, 999));

-- A first sample that matches the guess locks it in.
vitals(0);
later();
round();
gain(64);
value, learned = per_hit();
check('a sample matching the guess locks it', value == 64 and learned, tostring(value) .. ' ' .. tostring(learned));

-- New weapon with Store TP the client can't see: 70 a hit. One sample isn't enough, two agreeing are.
MOCK.items[16536] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16536;
later();
round();
gain(70);
value, learned = per_hit();
check('a new weapon drops what was learned', value == 64 and not learned, tostring(value) .. ' ' .. tostring(learned));
later();
round(TWO_HITS);
gain(140);
value, learned = per_hit();
check('two agreeing samples lock it', value == 70 and learned, tostring(value) .. ' ' .. tostring(learned));

-- Each of these feeds two rounds that would lock in 80 a hit if they counted. A clean round at 80
-- afterwards locks it in if even one of them slipped through. Then one at 70 puts things back.
local function still_70(name)
    later(7); vitals(0); later(); round(); gain(80);
    value = per_hit();
    check(name, value == 70, value);
    later(); round(); gain(70);
end
for _ = 1, 2 do later(); round(); MOCK.fire('packet_in', MOCK.action_packet(MOB, 1, 0, ME, HIT)); gain(80); end
still_70('a monster hitting you keeps it from counting');
for _ = 1, 2 do later(); MOCK.fire('packet_in', MOCK.action_packet(MOB, 1, 0, ME, HIT)); round(); gain(80); end
still_70('a monster hitting you just before your round keeps it from counting');
for _ = 1, 2 do
    later(); round();
    MOCK.fire('packet_in', MOCK.action_packet_multi(MOB, 11, 0, { { id = OTHER, results = HIT }, { id = ME, results = HIT } }));
    gain(80);
end
still_70('a TP move that hits you among others keeps it from counting');
for _ = 1, 2 do later(); round(); MOCK.fire('packet_in', MOCK.action_packet(ME, 6, 35, ME, { { message = 100 } })); gain(80); end
still_70('another action of yours keeps it from counting');
MOCK.player.buffs = { 170 };
for _ = 1, 2 do later(); round(); gain(80); end
MOCK.player.buffs = {};
still_70('Regain keeps it from counting');
MOCK.player.buffs = { 54 };
for _ = 1, 2 do later(); round(); gain(80); end
MOCK.player.buffs = {};
still_70('Meikyo Shisui keeps it from counting');
for _ = 1, 2 do later(); round(COUNTERED); gain(80); end
still_70('a counter keeps it from counting');
for _ = 1, 2 do later(); round(); later(0.6); gain(80); end
still_70('a late update keeps it from counting');
for _ = 1, 2 do later(); round(TWO_HITS); gain(161); end
still_70('a change that splits unevenly keeps it from counting');

-- TP rising with nothing behind it holds changes off for 6 seconds.
later(7);
gain(30);
for _ = 1, 2 do later(1); round(); gain(80); end
still_70('TP rising on its own holds changes off');

-- At the cap, the change is cut short.
later(7);
vitals(2960);
later(7);
for _ = 1, 2 do later(); round(); vitals(3000); vitals(2960); end
still_70('a change that reaches 3000 keeps it from counting');

-- Rounds with nothing in the way do lock in 80, so the checks above held for their reason. A
-- monster's spikes don't get in the way, since they give you no TP.
later(7);
vitals(100);
later(7);
for _ = 1, 2 do later(); round({ { message = 1, reaction = SPIKES } }); gain(80); end
value, learned = per_hit();
check('rounds against spikes relearn it', value == 80 and learned, tostring(value) .. ' ' .. tostring(learned));

-- Zoning keeps what was learned.
MOCK.fire('packet_in', MOCK.zone_packet(ME));
value, learned = per_hit();
check('zoning keeps it', value == 80 and learned);

-- The line under the bar.
local function drawn(tp_view, width)
    s.attack.width = width or 240;
    hud.refresh(s);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.draw_attack(0.5, 1.9, 3.78, true, tp_view);
    hud.end_frame();
    MOCK.record_imgui = false;
    local texts, colors = {}, {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddText') then
            table.insert(texts, c[6]);
            colors[c[6]] = colors[c[6]] or {};
            colors[c[6]][c[5]] = true;
        end
    end
    return '|' .. table.concat(texts, '|') .. '|', colors;
end
local tp_color = theme.u32(s.attack.tp_color);

local texts, colors = drawn({ tp = 640, goal = 1000, rounds = 3 });
check('shows your TP', texts:find('|TP 640|', 1, true) ~= nil, texts);
check('shows rounds to 1000', texts:find('|1000 TP in ~3 rounds|', 1, true) ~= nil, texts);
check('TP below 1000 is not in the TP color', not colors['TP 640'][tp_color]);
texts = drawn({ tp = 960, goal = 1000, rounds = 1 });
check('one round is singular', texts:find('|1000 TP in ~1 round|', 1, true) ~= nil, texts);
texts, colors = drawn({ tp = 1000, goal = 1000, rounds = nil });
check('at 1000 it shows TP only', texts:find('|TP 1000|', 1, true) ~= nil and texts:find('round', 1, true) == nil, texts);
check('at 1000 it turns the TP color', colors['TP 1000'] and colors['TP 1000'][tp_color] == true);
texts = drawn({ tp = 640, goal = 1000, rounds = 3 }, 120);
check('a narrow card gets the short form', texts:find('|~3 rounds|', 1, true) ~= nil and texts:find('1000 TP in', 1, true) == nil, texts);
MOCK.measure = function (text) return #text * 12; end
texts = drawn({ tp = 640, goal = 1000, rounds = 3 }, 120);
MOCK.measure = nil;
check('too narrow for either leaves the right side empty', texts:find('round', 1, true) == nil and texts:find('|TP 640|', 1, true) ~= nil, texts);
texts = drawn(nil);
check('no view, no line', texts:find('TP', 1, true) == nil, texts);

-- The card grows by one line of text for it.
s.attack.width = 240;
local _, with_line = hud.element_size('attack');
s.attack.show_tp = false;
hud.refresh(s);
local _, without_line = hud.element_size('attack');
check('the TP line makes the card taller', with_line > without_line, with_line .. ' vs ' .. without_line);

-- In a fight it reads your TP, and turned off it draws and reads nothing.
MOCK.player.tp = 640;
frames(1);
texts = '';
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText') then texts = texts .. '|' .. c[6]; end end
check('turned off, no TP line', texts:find('TP ', 1, true) == nil, texts);
s.attack.show_tp = true;
hud.refresh(s);
frames(1);
texts = '';
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText') then texts = texts .. '|' .. c[6] .. '|'; end end
check('in a fight it shows your TP', texts:find('|TP 640|', 1, true) ~= nil, texts);
local rounds_left = tp.rounds_to(1000, 640);
check('in a fight it shows rounds from what was learned',
    texts:find(('|1000 TP in ~%d round'):format(rounds_left), 1, true) ~= nil, rounds_left .. ' ' .. texts);
s.attack.show_tp_rounds = false;
frames(1);
texts = '';
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText') then texts = texts .. '|' .. c[6] .. '|'; end end
check('rounds off leaves TP only', texts:find('|TP 640|', 1, true) ~= nil and texts:find('round', 1, true) == nil, texts);
s.attack.show_tp_rounds = true;

-- Turned off, your rounds aren't read for it.
s.attack.show_tp = false;
vitals(tp_now);
local learned_before = select(1, per_hit());
for _ = 1, 2 do later(); round(); gain(90); end
check('turned off, nothing is learned', select(1, per_hit()) == learned_before, select(1, per_hit()));
s.attack.show_tp = true;

-- The sample timer shows a TP line too, so its look can be set up.
MOCK.player.status = 0;
MOCK.fire('command', { command = '/cadence' });
frames(1);
texts = '';
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText') then texts = texts .. '|' .. c[6] .. '|'; end end
check('the sample shows a TP line', texts:find('|TP %d+|') ~= nil, texts);

-- The sample gains 128 a round, and its rounds count down with it.
local function sample_at(step)
    MOCK.now = 4.2 * (600 + step) + 0.5;
    frames(1);
    local all = '';
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText') then all = all .. '|' .. c[6] .. '|'; end end
    return all;
end
texts = sample_at(0);
check('the sample at 512 is 4 rounds out', texts:find('|TP 512|', 1, true) and texts:find('|1000 TP in ~4 rounds|', 1, true), texts);
texts = sample_at(3);
check('the sample at 896 is 1 round out', texts:find('|TP 896|', 1, true) and texts:find('|1000 TP in ~1 round|', 1, true), texts);
texts = sample_at(4);
check('the sample at 1024 shows TP only', texts:find('|TP 1024|', 1, true) and not texts:find('round', 1, true), texts);
MOCK.fire('command', { command = '/cadence' });

-- Every look has its own TP color, and Reset look puts the default back.
local presets = require('ui.presets');
local default_tp = {};
for i, v in ipairs(s.attack.tp_color) do default_tp[i] = v; end
local seen = {};
for _, name in ipairs(presets.NAMES) do
    presets.apply(s, name);
    seen[theme.u32(s.attack.tp_color)] = true;
end
local distinct = 0;
for _ in pairs(seen) do distinct = distinct + 1; end
check('every look has its own TP color', distinct == #presets.NAMES, distinct);
presets.reset(s);
check('reset look puts the TP color back', theme.u32(s.attack.tp_color) == theme.u32(default_tp));

-- Rounds to 1000 from what was learned. A new weapon starts the average over.
MOCK.player.status = 1;
frames(1);
MOCK.items[16537] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16537;
later(7); vitals(0); later(7);
later(); round(); gain(80);
later(); round(TWO_HITS); gain(160);
-- 13 hits at 80, over (1.8 guessed + 1 + 2) hits in 4 rounds. The guess of 64 would say 13.
check('rounds from the learned TP and hit rate', tp.rounds_to(1000, 0) == 11, tp.rounds_to(1000, 0));
for _ = 1, 4 do later(); round({ MISS }); end
check('missing a lot pushes the rounds up', tp.rounds_to(1000, 0) == 22, tp.rounds_to(1000, 0));
for _ = 1, 16 do later(); round({ HIT[1], HIT[1], HIT[1] }); end
check('three hits a round still leave one round for the last hit', tp.rounds_to(1000, 999) == 1, tp.rounds_to(1000, 999));

-- A Samurai 75's Zanshin hit gets extra TP from Ikishoten, so a round that starts without a plain
-- hit doesn't count. Store TP 25 makes the guess 80.
MOCK.player.main_job = 12;
later(7); vitals(0); later(7);
later(); round(); gain(80);
value, learned = per_hit();
check('Samurai Store TP in the guess', value == 80 and learned, tostring(value) .. ' ' .. tostring(learned));
for _ = 1, 2 do later(); round({ MISS, { message = 1 } }); gain(170); end
value = per_hit();
check('a possible Zanshin round keeps it from counting', value == 80, value);
for _ = 1, 2 do later(); round({ { resolution = 2, message = 1 }, { message = 1 } }); gain(250); end
value = per_hit();
check('a guarded first hit keeps it from counting too', value == 80, value);
for _ = 1, 2 do later(); round(TWO_HITS); gain(180); end
value = per_hit();
check('a clean start still counts', value == 90, value);
MOCK.player.main_job = 1;

-- TP from anything but your own hits counts toward rounds to 1000 too. Each of your rounds moves an
-- average a third of the way toward what came in since the round before.
local function hit_me() MOCK.fire('packet_in', MOCK.action_packet(MOB, 1, 0, ME, HIT)); end
local function ability(id) MOCK.fire('packet_in', MOCK.action_packet(ME, 6, id, ME, { { message = 100 } })); end
local function other() return tp.other_per_round(); end
-- True when the last round moved the average a third of the way from `before` to `got`.
local function folded(before, got) return math.abs(other() - (before + (got - before) / 3)) < 1e-9; end

-- The Samurai's rounds above got more TP than their hits gave. Engaging starts that over.
check('the last fight left some', other() > 0, other());
MOCK.items[16538] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16538;
MOCK.player.status = 0; frames(1); MOCK.player.status = 1; frames(1);
check('engaging starts it over', other() == 0 and tp.rounds_to(1000, 0) == 18,
    other() .. ' ' .. tostring(tp.rounds_to(1000, 0)));

-- A 240 delay monster lands a 21 TP hit on you between each of your rounds. After 6 rounds, 16 hits
-- from 0 take 13 rounds, not 16. From 640 it's 5, not 6.
later(7); vitals(0); later(7);
later(); round(); gain(64);
for _ = 1, 6 do later(1); hit_me(); gain(21); later(2); round(); gain(64); end
check('being hit brings rounds down', tp.rounds_to(1000, 0) == 13, tp.rounds_to(1000, 0));
check('from 640 too', tp.rounds_to(1000, 640) == 5, tp.rounds_to(1000, 640));
MOCK.player.tp = 640;
frames(1);
texts = '';
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText') then texts = texts .. '|' .. c[6] .. '|'; end end
check('and the line under the bar says so', texts:find('|1000 TP in ~5 rounds|', 1, true) ~= nil, texts);

-- A monster's hit in the same update as your round counts past your own hits.
later(); hit_me(); round(); gain(85);
local before = other();
later(); round(); gain(64);
check('a monster hit in your round\'s update counts', folded(before, 21), other());

-- A TP move that takes TP away leaves its stretch out, with what came before it.
later(1); hit_me(); gain(21); hit_me(); vitals(tp_now - 100);
before = other();
later(2); round(); gain(64);
check('TP going down leaves the stretch out', other() == before, other());

-- So does another action of yours.
later(1); hit_me(); gain(21); ability(35);
before = other();
later(2); round(); gain(64);
check('another action of yours leaves the stretch out', other() == before, other());

-- Meditate's TP comes with no buff to show it. A stretch that starts in the 24 seconds after it is left
-- out. Its last tick here comes 23 seconds in.
vitals(0);
ability(63);
before = other();
later(1.5); round(); gain(64);
for _ = 1, 7 do later(1.5); gain(200); later(1.5); round(); gain(64); end
later(0.5); gain(200);
later(2.5); round(); gain(64);
check('Meditate\'s TP is left out', other() == before, other());
later(1); hit_me(); gain(21); later(2); round(); gain(64);
check('a stretch that starts 25.5 seconds after it counts', folded(before, 21), other());

-- Under Meikyo Shisui your hits give no TP, so all of the change is from something else.
MOCK.player.buffs = { 54 };
later(); hit_me(); round(); gain(21);
MOCK.player.buffs = {};
before = other();
later(); round(); gain(64);
check('under Meikyo Shisui being hit still counts', folded(before, 21), other());

-- 240 delay is 4 seconds. A round more than 6.4 seconds after the last had a pause in it.
later(1); hit_me(); gain(21);
before = other();
later(5.6); round(); gain(64);
check('a round 6.6 seconds after the last leaves the stretch out', other() == before, other());
later(1); hit_me(); gain(21);
before = other();
later(5.2); round(); gain(64);
check('one 6.2 seconds after it still counts', folded(before, 21), other());

-- A change that reaches 3000 can't show all the TP that came. At 3000 no stretch starts, so nothing
-- wears the average down either.
ability(35); vitals(2950);
later(); round({ MISS }); hit_me(); vitals(3000);
before = other();
later(); round({ MISS });
check('a change that reaches 3000 leaves the stretch out', other() == before, other());
for _ = 1, 3 do later(); round({ MISS }); end
check('held at 3000 it stays put', other() == before, other());

-- New weapons. Until TP per hit is locked in again, a change with your hits in it is left out. One with
-- none of them still counts. A change smaller than the first guess is only left out too, since the
-- guess can be off.
vitals(0);
MOCK.items[16539] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16539;
later(); hit_me(); round(); gain(85);
check('TP per hit isn\'t locked in yet', not select(2, per_hit()));
later(1); hit_me(); gain(21);
before = other();
later(2); round(); gain(50);
check('until TP per hit is locked in, only the change without your hits counts', folded(before, 21), other());
later(1); hit_me(); gain(21);
before = other();
later(2); round(); gain(50);
check('a change below the guess doesn\'t throw the stretch out', folded(before, 21) and select(1, per_hit()) == 50,
    other());

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
