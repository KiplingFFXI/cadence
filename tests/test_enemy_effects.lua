-- Slow, Elegy, Haste and Hundred Fists on a monster. What counts as landing, how the enemy timer's
-- delay follows them, how gaps are kept apart, and the tag.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end
local function near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 0.001); end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local enemy = require('core.enemy');
local effects = require('core.monster_effects');
local packets = require('core.packets');
local hud = require('ui.hud');

local ME, OTHER, MOB = 1001, 2001, 0x01000200;
local SPELL, TP_MOVE, PET = 4, 11, 13;

-- What counts as landing ------------------------------------------------------------------------
local slow = effects.landed(SPELL, 56, 236, 13);
check('Slow landing', slow and slow.effect == 13 and slow.power == 1825 and not slow.exact);
check('Slow II landing', effects.landed(SPELL, 79, 236, 13).power == 2380);
check('Hojo: Ni is exact', effects.landed(SPELL, 345, 236, 13).exact and effects.landed(SPELL, 345, 236, 13).lasts == 300);
check('Carnage Elegy landing', effects.landed(SPELL, 422, 237, 194).power == 5000);
check('a second target of the same cast', effects.landed(SPELL, 56, 277, 13) ~= nil);
check('a resisted Slow is nothing', effects.landed(SPELL, 56, 85, 13) == nil);
check('a Slow that has no effect is nothing', effects.landed(SPELL, 56, 75, 13) == nil);
check('some other effect is nothing', effects.landed(SPELL, 58, 236, 4) == nil);
check('an unknown slowing spell gets a guess', effects.landed(SPELL, 9999, 236, 13).power == 2000);
check('Refueling', effects.landed(TP_MOVE, 569, 186, 33).power == 2000);
check('a failed buff TP move is nothing', effects.landed(TP_MOVE, 569, 189, 33) == nil);
check('Hundred Fists', effects.landed(TP_MOVE, 690, 101, 46).lasts == 45);
check('Leviathan\'s Slowga', effects.landed(PET, 580, 127, 13).power == 3000 and effects.landed(PET, 580, 127, 13).exact);
check('a missed Slowga is nothing', effects.landed(PET, 580, 156, 13) == nil);
check('Dispel taking one off', effects.removed(341) and not effects.removed(236));
check('a monster erasing one off itself', effects.removed(159));

-- Every result on every target.
local rows = {};
local aoe = MOCK.action_packet_multi(ME, SPELL, 56, {
    { id = MOB, results = { { message = 236, damage = 13, add_effect = true } } },
    { id = MOB + 1, results = { { message = 85, damage = 13 }, { message = 277, damage = 13, reaction = true } } },
});
local n = packets.action_results(aoe, rows);
check('reads every result on every target', n == 3 and rows[1].target == MOB and rows[1].message == 236
    and rows[1].param == 13 and rows[3].target == MOB + 1 and rows[3].message == 277, n);

-- The delay follows the effects ---------------------------------------------------------------------
local now = 1000;
local function rounds(id, gap, times)
    for _ = 1, times do
        now = now + gap;
        enemy.on_round(now, id, ME);
    end
end
local function state(id)
    local _, _, delay, learned, _, tag = enemy.progress(now, id);
    return delay, learned, tag;
end

enemy.on_engage(now, MOB);
rounds(MOB, 4.0, 5);
local delay, learned, tag = state(MOB);
check('learns 4.0 with nothing on', near(delay, 4.0) and learned and tag == nil, delay);

-- Your Slow lands mid-attack. The attack already under way keeps its time.
local due = select(2, enemy.progress(now, MOB));
now = now + 1.0;
enemy.on_effect(now, MOB, slow, true);
local _, left = enemy.progress(now, MOB);
check('the attack under way keeps its time', near(left, due - 1.0), left);
delay, learned, tag = state(MOB);
check('a slowed guess right away', near(delay, 4.0 * 1.1825) and not learned and tag == 'slow', delay .. ' ' .. tostring(tag));

-- That gap started before the Slow, so it's still a plain one. Then slowed gaps are learned.
now = now + 3.0;
enemy.on_round(now, MOB, ME);
delay = state(MOB);
check('the gap it landed in counts as plain', near(delay, 4.73), delay);
rounds(MOB, 4.8, 3);
delay, learned = state(MOB);
check('learns the slowed delay', near(delay, 4.8) and learned, delay);

-- It wears off. The plain delay is back at once, already learned.
enemy.on_effect_gone(now, MOB, 13);
delay, learned, tag = state(MOB);
check('back to the plain delay when it wears off', near(delay, 4.0) and learned and tag == nil, delay);

-- Elegy and Slow add up. Haste replaces Slow and keeps Elegy.
enemy.on_effect(now, MOB, slow, true);
enemy.on_effect(now, MOB, effects.landed(SPELL, 421, 237, 194), true);
delay, _, tag = state(MOB);
check('Slow and Elegy add up', near(delay, 4.0 * 1.4325) and tag == 'slow+elegy', delay .. ' ' .. tostring(tag));
enemy.on_effect(now, MOB, effects.landed(SPELL, 57, 230, 33), false);
delay, _, tag = state(MOB);
check('Haste takes Slow off and keeps Elegy', near(delay, 4.0 * (1 + 0.25 - 0.1465)) and tag == 'elegy+haste',
    delay .. ' ' .. tostring(tag));
enemy.on_effect_gone(now, MOB, 33);
enemy.on_effect_gone(now, MOB, 194);
check('Dispel and wear-off clear them', state(MOB) == 4.0 and select(3, state(MOB)) == nil);

-- A gap that started before Elegy landed on a slowed monster fits neither list, so it's dropped.
local MIX = MOB + 8;
enemy.on_engage(now, MIX);
rounds(MIX, 4.0, 4);
now = now + 1.0;
enemy.on_effect(now, MIX, slow, true);
now = now + 3.0;
enemy.on_round(now, MIX, ME);
rounds(MIX, 4.8, 3);
check('slowed gaps learned', near(state(MIX), 4.8) and select(2, state(MIX)), state(MIX));
now = now + 1.0;
enemy.on_effect(now, MIX, effects.landed(SPELL, 421, 237, 194), true);
now = now + 3.8;
enemy.on_round(now, MIX, ME);
check('a gap from before a change is dropped', near(state(MIX), 4.0 * 1.4325), state(MIX));

-- An effect that's always the same strength is known as soon as the plain delay is. A Slow isn't.
enemy.on_effect(now, MOB, effects.landed(SPELL, 345, 236, 13), true);
delay, learned = state(MOB);
check('Hojo: Ni is known right away', near(delay, 4.0 * 1.1953) and learned, tostring(delay) .. ' ' .. tostring(learned));
enemy.on_effect(now, MOB, slow, true);
check('Slow is still a guess', not select(2, state(MOB)));
enemy.on_effect_gone(now, MOB, 13);

-- Slow landing on a hasted monster takes the Haste off.
enemy.on_effect(now, MOB, effects.landed(SPELL, 57, 230, 33), false);
enemy.on_effect(now, MOB, slow, true);
check('Slow takes Haste off', select(3, state(MOB)) == 'slow' and near(state(MOB), 4.0 * 1.1825), select(3, state(MOB)));
enemy.on_effect_gone(now, MOB, 13);

-- An effect that ran out while nobody watched that monster is gone by its next attack.
local UNSEEN = MOB + 10;
enemy.on_engage(now, UNSEEN);
rounds(UNSEEN, 4.0, 4);
enemy.on_effect(now, UNSEEN, slow, false);
now = now + 181;
enemy.on_round(now, UNSEEN, ME);
check('ran out before its next attack', near(select(2, enemy.progress(now, UNSEEN)), 4.0), select(2, enemy.progress(now, UNSEEN)));

-- Haste can take off at most 43.75%. Slow and Elegy can at most double it.
enemy.on_effect(now, MOB, { effect = 33, power = 9000, sure_for = 60, lasts = 60 }, true);
check('haste is capped', near(state(MOB), 4.0 * 0.5625), state(MOB));
enemy.on_effect_gone(now, MOB, 33);
enemy.on_effect(now, MOB, { effect = 13, power = 6000, sure_for = 60, lasts = 60 }, true);
enemy.on_effect(now, MOB, { effect = 194, power = 6000, sure_for = 60, lasts = 60 }, true);
check('slow is capped at double', near(state(MOB), 8.0), state(MOB));
enemy.on_effect_gone(now, MOB, 13);
enemy.on_effect_gone(now, MOB, 194);

-- Someone else's Slow. It's sure for 90 s, maybe on until 180 s, then gone.
enemy.on_effect(now, MOB, slow, false);
check('someone else\'s Slow shows', select(3, state(MOB)) == 'slow');
now = now + 91;
check('might have worn off after 90 s', select(3, state(MOB)) == 'slow?', select(3, state(MOB)));
now = now + 90;
delay, _, tag = state(MOB);
check('gone after 180 s', tag == nil and near(delay, 4.0), tostring(tag));

-- Your own Slow waits for its wear-off, with a backstop.
enemy.on_effect(now, MOB, slow, true);
now = now + 185;
check('yours stays until it wears off', select(3, state(MOB)) == 'slow');
now = now + 10;
check('and goes if the wear-off never comes', select(3, state(MOB)) == nil);

-- A monster slowed from the pull has no plain gaps. Its slowed gaps, with the Slow worked back out,
-- stand in for them.
local FRESH = MOB + 5;
enemy.on_engage(now, FRESH);
enemy.on_effect(now, FRESH, slow, true);
rounds(FRESH, 4.8, 5);
enemy.on_effect_gone(now, FRESH, 13);
delay, learned = state(FRESH);
check('slowed from the pull', near(delay, 4.8 / 1.1825) and not learned, delay);

-- Hundred Fists. A quarter of the delay, its gaps aren't kept, and it's over in 45 s.
local FISTS = MOB + 6;
enemy.on_engage(now, FISTS);
rounds(FISTS, 4.0, 4);
enemy.on_effect(now, FISTS, effects.landed(TP_MOVE, 690, 101, 46), false);
rounds(FISTS, 1.0, 4);
delay, learned, tag = state(FISTS);
check('Hundred Fists', near(delay, 1.0) and learned and tag == 'hundred fists', delay .. ' ' .. tostring(tag));
now = now + 46;
check('Hundred Fists wears off', near(state(FISTS), 4.0) and select(2, state(FISTS)), state(FISTS));

-- A quiet monster whose effect has run out is dropped like any other.
local LEFT_ALONE = MOB + 11;
enemy.on_effect(now, LEFT_ALONE, slow, false);
enemy.sweep(now + 60, nil);
check('kept while someone else\'s Slow could be on', enemy.has(LEFT_ALONE));
enemy.sweep(now + 181, nil);
check('dropped once it has run out', not enemy.has(LEFT_ALONE));

-- A quiet monster with an effect on is kept, so the effect isn't lost.
local QUIET = MOB + 7;
enemy.on_effect(now, QUIET, slow, true);
enemy.sweep(now + 60, nil);
check('kept by the sweep while slowed', enemy.has(QUIET));
enemy.on_effect_gone(now + 60, QUIET, 13);
enemy.sweep(now + 200, nil);
check('dropped once it isn\'t', not enemy.has(QUIET));

-- Through the addon's packets ------------------------------------------------------------------------
enemy.reset();
s.enemy.enabled = true;
MOCK.now = 500;
local function packet(p) MOCK.fire('packet_in', p); end
local function mob_round() packet(MOCK.action_packet(MOB, 1, 0, ME, { { message = 1 } })); end
for _ = 1, 5 do MOCK.now = MOCK.now + 4.0; mob_round(); end
packet(MOCK.action_packet(OTHER, SPELL, 56, MOB, { { message = 236, damage = 13 } }));
local _, _, d, _, _, t = enemy.progress(MOCK.now, MOB);
check('another player\'s Slow is seen', t == 'slow' and near(d, 4.73), tostring(t) .. ' ' .. tostring(d));
packet(MOCK.message_packet(OTHER, MOB, 13, 0, 206, 0x200));
check('someone else\'s wear-off message is ignored', select(6, enemy.progress(MOCK.now, MOB)) == 'slow');
packet(MOCK.message_packet(ME, MOB, 13, 0, 206, 0x200));
check('your wear-off message takes it off', select(6, enemy.progress(MOCK.now, MOB)) == nil);
packet(MOCK.action_packet(ME, SPELL, 56, MOB, { { message = 236, damage = 13 } }));
MOCK.now = MOCK.now + 185;
check('your own Slow waits for its wear-off', select(6, enemy.progress(MOCK.now, MOB)) == 'slow');
packet(MOCK.message_packet(ME, MOB, 13, 0, 206, 0x200));
packet(MOCK.action_packet(MOB, TP_MOVE, 569, MOB, { { message = 186, damage = 33 } }));
check('a monster\'s Refueling is seen', select(6, enemy.progress(MOCK.now, MOB)) == 'haste');
packet(MOCK.action_packet(ME, SPELL, 260, MOB, { { message = 341, damage = 33 } }));
check('your Dispel takes it off', select(6, enemy.progress(MOCK.now, MOB)) == nil);
packet(MOCK.action_packet(OTHER, SPELL, 421, MOB, { { message = 237, damage = 194 } }));
packet(MOCK.action_packet(MOB, TP_MOVE, 1245, MOB, { { message = 159, damage = 194 } }));
check('a monster\'s TP move erasing Elegy takes it off', select(6, enemy.progress(MOCK.now, MOB)) == nil);
-- Elegy through the packets. Your own Battlefield Elegy, then someone's Slow on top, then your Elegy
-- wearing off leaves the Slow.
local SINGER = MOB + 20;
for _ = 1, 5 do MOCK.now = MOCK.now + 4.0; packet(MOCK.action_packet(SINGER, 1, 0, ME, { { message = 1 } })); end
packet(MOCK.action_packet(ME, SPELL, 421, SINGER, { { message = 237, damage = 194 } }));
local _, _, ed, el, _, et = enemy.progress(MOCK.now, SINGER);
check('your Elegy is seen', et == 'elegy' and near(ed, 5.0) and not el, tostring(et) .. ' ' .. tostring(ed));
packet(MOCK.action_packet(OTHER, SPELL, 56, SINGER, { { message = 236, damage = 13 } }));
_, _, ed, _, _, et = enemy.progress(MOCK.now, SINGER);
check('Elegy and Slow add up', et == 'slow+elegy' and near(ed, 4.0 * 1.4325), tostring(et) .. ' ' .. tostring(ed));
packet(MOCK.message_packet(ME, SINGER, 194, 0, 206, 0x214));
_, _, ed, _, _, et = enemy.progress(MOCK.now, SINGER);
check('your Elegy wearing off leaves the Slow', et == 'slow' and near(ed, 4.0 * 1.1825), tostring(et) .. ' ' .. tostring(ed));

-- A Carnage Elegy is always the same strength, and a magic burst Elegy counts too.
packet(MOCK.action_packet(ME, SPELL, 422, SINGER, { { message = 268, damage = 194 } }));
_, _, ed, el, _, et = enemy.progress(MOCK.now, SINGER);
check('a magic burst Carnage Elegy is seen', et == 'slow+elegy' and near(ed, 4.0 * (1 + 0.1825 + 0.5)),
    tostring(et) .. ' ' .. tostring(ed));
packet(MOCK.action_packet(OTHER, SPELL, 422, SINGER + 1, { { message = 237, damage = 194 } }));
check('Carnage Elegy alone on a new monster', select(6, enemy.progress(MOCK.now, SINGER + 1)) == nil
    and enemy.has(SINGER + 1));
packet(MOCK.action_packet(OTHER, SPELL, 421, SINGER + 2, { { message = 85, damage = 194 } }));
check('a resisted Elegy is nothing', not enemy.has(SINGER + 2));

packet(MOCK.message_packet(ME, MOB, 0, 0, 6, 0x200));
check('a defeated monster is forgotten', not enemy.has(MOB));

s.enemy.enabled = false;
packet(MOCK.action_packet(OTHER, SPELL, 56, MOB + 9, { { message = 236, damage = 13 } }));
check('nothing is tracked with the enemy timer off', not enemy.has(MOB + 9));
s.enemy.enabled = true;

-- The tag on the timer.
local function detail(view)
    hud.refresh(s);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.draw_enemy(view);
    hud.end_frame();
    MOCK.record_imgui = false;
    local all = '|';
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText') then all = all .. c[6] .. '|'; end end
    return all;
end
local view = { fill = 0.5, left = 2.0, delay = 4.73, learned = false, waiting = false, name = 'Goblin', tag = 'slow' };
check('the tag shows after the delay', detail(view):find('|Goblin  4.73s est.  slow|', 1, true) ~= nil, detail(view));
s.enemy.show_effects = false;
check('turned off, no tag', detail(view):find('slow', 1, true) == nil);
-- The tag is enough to give the timer its text row.
s.enemy.show_name, s.enemy.show_delay, s.enemy.show_value, s.style.show_labels = false, false, false, false;
s.enemy.show_effects = true;
hud.refresh(s);
local _, with_tag = hud.element_size('enemy');
s.enemy.show_effects = false;
hud.refresh(s);
local _, without = hud.element_size('enemy');
check('the tag alone keeps the text row', with_tag > without, with_tag .. ' vs ' .. without);
s.enemy.show_name, s.enemy.show_delay, s.enemy.show_value, s.style.show_labels = true, true, true, true;
s.enemy.show_effects = true;
view.tag = nil;
check('no effects, no tag', detail(view):find('|Goblin  4.73s est.|', 1, true) ~= nil, detail(view));

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
