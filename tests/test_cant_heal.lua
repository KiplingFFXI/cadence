-- Disease, plague and the curse that stops healing. Resting ticks still come on time but heal nothing.
-- The resting bar dims and says why, hides the gains and full times, and stays in step with the ticks
-- through the effect and after it wears off.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end
local function near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 0.05); end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local resting = require('core.resting');
local theme = require('ui.theme');
local imgui = require('imgui');

local ME = 1001;
local DISEASE, PLAGUE, CURSE = 8, 31, 20;

local function run_to(t) while (MOCK.now + 0.05 < t) do MOCK.frame(0.05); end MOCK.now = t; MOCK.frame(0); end
local function vitals(hp, mp, tp) MOCK.fire('packet_in', MOCK.vitals_packet(ME, hp, mp or 0, tp or 0)); end

-- One frame's draw calls.
local function frame()
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(0);
    MOCK.record_imgui = false;
    return MOCK.imgui_calls;
end
local function texts(calls)
    local all = '|';
    for _, c in ipairs(calls or frame()) do if (c[1] == 'dl:AddText') then all = all .. c[6] .. '|'; end end
    return all;
end
local function shows(word, calls) return texts(calls):find('|' .. word .. '|', 1, true) ~= nil; end
local function has(piece, calls) return texts(calls):find(piece, 1, true) ~= nil; end
local function seconds_shown(calls) return texts(calls):match('|%d+%.%d|') ~= nil; end
-- "full in 28s" after the gains, not the "HP full in" line under the bar.
local function until_full_shown(calls) return has('|full in', calls) or has('  full in', calls); end
local function word_colors(calls, word)
    local found = {};
    for _, c in ipairs(calls) do if (c[1] == 'dl:AddText' and c[6] == word) then found[c[5]] = true; end end
    return found;
end

-- The draw calls for the bar's fill, the ones after its track.
local function fill_calls(calls)
    local track, list = theme.u32(s.style.track_color), nil;
    for _, c in ipairs(calls) do
        if (list ~= nil and (c[1] == 'dl:AddRectFilled' or c[1] == 'dl:AddRectFilledMultiColor')) then
            table.insert(list, c);
        elseif (c[1] == 'dl:AddRectFilled' and c[4] == track) then
            list = {};
        end
    end
    return list or {};
end
local function alpha(c) return math.floor((c % 2 ^ 32) / 2 ^ 24); end
local function rgb(c) return (c % 2 ^ 32) % 2 ^ 24; end
local function dimmed_from(c, color)
    local full = theme.u32(color);
    return c ~= nil and rgb(c) == rgb(full) and alpha(c) > 0 and alpha(c) < alpha(full);
end
local function full_strength(c, color)
    local full = theme.u32(color);
    return c ~= nil and rgb(c) == rgb(full) and alpha(c) == alpha(full);
end

-- When the bar says the next tick lands.
local function target() local _, left = resting.progress(MOCK.now); return left and (MOCK.now + left); end
local function ticks() return select(3, resting.progress(MOCK.now)); end

-- Sits down at T with HP, MP and TP already known, so the first change can be a tick.
local function sit(T, hp, mp, tp)
    MOCK.player.status = 0;
    MOCK.now = T - 1;
    MOCK.frame(0);
    vitals(hp, mp, tp);
    MOCK.now = T;
    MOCK.player.status = 33;
    MOCK.frame(0);
end
local function stand()
    MOCK.player.buffs = {};
    MOCK.player.status = 0;
    MOCK.frame(0.05);
end

MOCK.fire('command', { command = '/cadence resting fulltimes on' });

--[[
    A WAR at TP 0 with no Signet, so only HP shows a tick. Server time S is 0.25 s before the sit
    shows up at T. Tick n lands at its 10 s mark plus a lateness that drops 1 s each tick, so the HP
    ticks land 21, 30, 42, 51, 60, 72, 81, 90, 102, 111 s after T. Each heals 1 HP more than the one
    before, counting from 10. Ticks under the effect still count. Max HP is 299, so one tick that
    heals more than 3 HP past the last one looks like a cure.
]]
local REAL = { 21, 30, 42, 51, 60, 72, 81, 90, 102, 111 };
local T = 1000;
MOCK.player.hp_max, MOCK.player.mp_max = 299, 0;
local hp = 100;
sit(T, hp, 0, 0);
for i = 1, 4 do
    run_to(T + REAL[i]);
    hp = hp + 9 + i;
    vitals(hp, 0, 0);
end
run_to(T + 52);
local calls = frame();
check('before the effect the seconds, gains and full times show', seconds_shown(calls) and has('+13 HP', calls)
    and until_full_shown(calls) and has('HP full in', calls), texts(calls));
check('and the bar is at full strength', full_strength(fill_calls(calls)[1] and fill_calls(calls)[1][4],
    s.resting.fill_start));
check('it knows the pattern', resting.pattern_known() and near(target(), T + 60), target());

-- Disease lands between ticks.
MOCK.player.buffs = { DISEASE };
run_to(T + 55);
calls = frame();
local bar = fill_calls(calls);
check('diseased shows in place of the seconds', shows('diseased', calls) and not seconds_shown(calls), texts(calls));
check('in the detail color', word_colors(calls, 'diseased')[theme.u32(s.style.detail_color)]);
check('the bar dims', bar[1] and dimmed_from(bar[1][4], s.resting.fill_start), bar[1] and bar[1][4]);
check('the gains step aside', not has('|+', calls), texts(calls));
check('so does time until full', not until_full_shown(calls), texts(calls));
check('and the full times', not has('HP full', calls) and not has('HP --', calls), texts(calls));
check('the label stays', shows('RESTING', calls));

-- The ticks at 60, 72 and 81 heal nothing, so nothing shows up. The bar keeps their time.
local in_step, seen = true, {};
for _, t in ipairs({ 58, 62, 65, 70, 74, 79, 83 }) do
    run_to(T + t);
    local want = (t < 60 and 60) or (t < 72 and 72) or (t < 81 and 81) or 90;
    if (not near(target(), T + want)) then in_step = false; end
    table.insert(seen, ('%d:%.2f'):format(t, (target() or 0) - T));
end
check('the bar stays on the ticks under the effect', in_step, table.concat(seen, ' '));
check('the ticks under it still count', ticks() == 7, ticks());
calls = frame();
check('still diseased after missing ticks', shows('diseased', calls), texts(calls));

-- It wears off at 85. The next tick heals the full count, 17, bigger than the 13 before it by more
-- than one tick's step. That isn't a cure.
MOCK.player.buffs = {};
run_to(T + 85);
calls = frame();
check('once it wears off the seconds come back', seconds_shown(calls) and not shows('diseased', calls), texts(calls));
check('at full strength', full_strength(fill_calls(calls)[1] and fill_calls(calls)[1][4], s.resting.fill_start));
check('with no gains, since the last tick healed nothing', not has('|+', calls), texts(calls));
-- Eight gains17..24 fill at162, on the retained9/9/12 phase,77s after the cure.
check('the model restores phase-aware full times before another heal', near(resting.until_full(MOCK.now), 77)
    and has('HP full in 1:17', calls) and until_full_shown(calls), texts(calls));
check('the next tick is still due on time', near(target(), T + 90), target());
run_to(T + REAL[8]);
hp = hp + 17;
vitals(hp, 0, 0);
check('the first tick after it shows up', resting.seen_at() == T + 90 and ticks() == 8, ticks());
calls = frame();
check('and shows what it restored', has('+17 HP', calls), texts(calls));
check('the next one comes 12 s later', near(target(), T + 102), target());
run_to(T + REAL[9]);
hp = hp + 18;
vitals(hp, 0, 0);
run_to(T + REAL[10]);
hp = hp + 19;
vitals(hp, 0, 0);
calls = frame();
check('it keeps counting in step after', resting.seen_at() == T + 111 and ticks() == 10, ticks());
check('and works out when you\'re full again', until_full_shown(calls) and has('HP full in', calls)
    and not has('HP full in --', calls), texts(calls));
stand();

--[[
    Plague and the curse get their own words. Plague drains TP and MP on the 3 s pass, which looks
    like a tick. Those don't count.
]]
T = 2000;
MOCK.player.hp_max, MOCK.player.mp_max = 1200, 300;
sit(T, 500, 100, 600);
run_to(T + 21);
vitals(510, 112, 500);
run_to(T + 30);
vitals(521, 125, 400);
check('an MP job sees its ticks', ticks() == 2 and near(target(), T + 42), target());
MOCK.player.buffs = { PLAGUE };
run_to(T + 31);
calls = frame();
check('plague says plagued', shows('plagued', calls) and not seconds_shown(calls), texts(calls));
local tp_left, mp_left = 400, 125;
for _, t in ipairs({ 33, 36, 39, 42, 45, 48, 51 }) do
    run_to(T + t);
    tp_left, mp_left = tp_left - 50, mp_left - 3;
    vitals(521, mp_left, tp_left);
end
check('plague draining TP and MP isn\'t a tick', resting.seen_at() == T + 30 and ticks() == 3, ticks());
run_to(T + 51.5);
check('the bar is still on the ticks', near(target(), T + 60), target());
MOCK.player.buffs = { CURSE };
run_to(T + 52);
calls = frame();
check('the curse that stops healing says cursed', shows('cursed', calls), texts(calls));
-- The other curse only lowers max HP and MP. The tick at 60 heals as usual, with the two skipped
-- ticks' steps on top.
MOCK.player.buffs = { 9 };
run_to(T + 53);
calls = frame();
check('the curse that only lowers max HP and MP doesn\'t', seconds_shown(calls) and not shows('cursed', calls),
    texts(calls));
run_to(T + 60);
vitals(535, mp_left + 16, 0);
check('and its ticks count', resting.seen_at() == T + 60 and ticks() == 5, ticks());
MOCK.player.buffs = { CURSE, PLAGUE, DISEASE };
run_to(T + 61);
check('with more than one on, disease is named first', shows('diseased'));

-- Full needs no healing, so "full" wins.
vitals(1200, 300, 0);
run_to(T + 62);
calls = frame();
check('at full HP and MP it says full', shows('full', calls) and not shows('diseased', calls), texts(calls));
bar = fill_calls(calls);
check('and the bar isn\'t dimmed', bar[1] and full_strength(bar[1][4], s.resting.full_color));

-- With the box off, the bar looks the way it always did.
vitals(1100, 300, 0);
MOCK.printed = {};
MOCK.fire('command', { command = '/cadence resting why off' });
check('the command turns it off', s.resting.show_why == false
    and MOCK.printed[1] == '[cadence] Why it can\'t heal is off for the resting timer.', MOCK.printed[1]);
run_to(T + 63);
calls = frame();
bar = fill_calls(calls);
check('off, the seconds show', seconds_shown(calls) and not shows('diseased', calls), texts(calls));
check('off, the bar isn\'t dimmed', bar[1] and full_strength(bar[1][4], s.resting.fill_start), bar[1] and bar[1][4]);
check('off, the timer still follows the ticks', near(target(), T + 72), target());
MOCK.fire('command', { command = '/cadence resting why' });
check('the command with no word flips it back', s.resting.show_why == true);
check('and it shows again', shows('diseased'));
stand();

--[[
    The effect wears off on the very tick that heals you. That tick's HP change comes in a moment
    before cadence reads your buffs again. It still counts, at the time it came in.
]]
T = 3000;
MOCK.player.hp_max, MOCK.player.mp_max = 299, 0;
hp = 100;
sit(T, hp, 0, 0);
for i = 1, 4 do
    run_to(T + REAL[i]);
    hp = hp + 9 + i;
    vitals(hp, 0, 0);
end
MOCK.player.buffs = { DISEASE };
run_to(T + 55);
run_to(T + 59.9);
hp = hp + 14;
vitals(hp, 0, 0);
check('a change while it still looks on waits', resting.seen_at() == T + 51, resting.seen_at());
MOCK.player.buffs = {};
run_to(T + 60.3);
check('once it\'s gone, that change is the tick', resting.seen_at() == T + 59.9 and ticks() == 5, ticks());
check('counted once', near(target(), T + 72, 0.2), target());
stand();

--[[
    Diseased from the moment you sit. With no tick ever seen, the timer goes on its first guess. It
    takes the ticks to land 21.4, 30.4, 42.4 and 51.4 s after T. Here they land 19.4, 31.4, 40.4 and
    49.4 s after T, so the fourth comes 2 s early. It's the first one after the effect, and it heals 13.
]]
T = 4000;
hp = 100;
MOCK.player.buffs = { DISEASE };
sit(T, hp, 0, 0);
run_to(T + 1);
check('sitting down diseased says so', shows('diseased'));
run_to(T + 45);
check('it counts the ticks on its own', ticks() == 3 and near(target(), T + 51.4), ticks());
MOCK.player.buffs = {};
run_to(T + 46);
run_to(T + 49.4);
hp = hp + 13;
vitals(hp, 0, 0);
check('the first tick after it counts even 2 s off the guess', resting.seen_at() == T + 49.4, resting.seen_at());
stand();

--[[
    The effect comes and goes between two ticks. No tick healed nothing, so the gains are still true.
]]
T = 5000;
hp = 100;
sit(T, hp, 0, 0);
for i = 1, 2 do
    run_to(T + REAL[i]);
    hp = hp + 9 + i;
    vitals(hp, 0, 0);
end
MOCK.player.buffs = { PLAGUE };
run_to(T + 33);
MOCK.player.buffs = {};
run_to(T + 35);
check('gains stay when no tick went by under it', has('+11 HP'));
stand();

-- Standing up still diseased, the settings window's sample isn't diseased.
T = 6000;
MOCK.player.buffs = { DISEASE };
sit(T, 100, 0, 0);
run_to(T + 2);
MOCK.player.status = 0;
MOCK.fire('command', { command = '/cadence' });
run_to(T + 3);
calls = frame();
check('the sample counts as usual', seconds_shown(calls) and not shows('diseased', calls), texts(calls));
MOCK.fire('command', { command = '/cadence' });
stand();

-- The box, its (?) and its tip ------------------------------------------------------------------------
MOCK.fire('command', { command = '/cadence' });
calls = frame();
local after_ticks, box_at, next_at = false, nil, nil;
for i, c in ipairs(calls) do
    if (c[1] == 'Checkbox' and c[2] == 'Ticks until full') then after_ticks = true; end
    if (c[1] == 'Checkbox' and c[2] == 'Next tick gains##resting') then next_at = i; end
    if (c[1] == 'Checkbox' and c[2] == 'Why it can\'t heal') then
        box_at = i;
        check('the box follows Ticks until full among recovery readouts', after_ticks);
    end
end
check('the window has the box before Next tick gains', box_at ~= nil and next_at ~= nil and box_at < next_at);
rawset(imgui, 'IsItemHovered', function () return true; end);
calls = frame();
rawset(imgui, 'IsItemHovered', nil);
local tip, inside, past_box = nil, false, false;
for _, c in ipairs(calls) do
    if (c[1] == 'Checkbox' and c[2] == 'Why it can\'t heal') then past_box = true; end
    if (c[1] == 'BeginTooltip') then inside = true; end
    if (c[1] == 'EndTooltip') then inside = false; end
    if (past_box and inside and c[1] == 'TextUnformatted') then tip = tostring(c[2]); break; end
end
check('its (?) has a tip', tip ~= nil);
check('the tip names the three words', tip and tip:find('"diseased"', 1, true) and tip:find('"plagued"', 1, true)
    and tip:find('"cursed"', 1, true), tip);
check('the tip is 200 characters or less', tip and #tip <= 200, tip and #tip);
MOCK.fire('command', { command = '/cadence' });

-- The command row and its help.
MOCK.printed = {};
MOCK.fire('command', { command = '/cadence help resting' });
local listed = false;
for _, line in ipairs(MOCK.printed) do if (line:find('why (Why it can\'t heal)', 1, true)) then listed = true; end end
check('/cadence help resting lists it', listed, table.concat(MOCK.printed, ' / '));

-- The server's own packets around the effect -----------------------------------------------------------
-- The effect landing or going away sends your HP, MP and TP with nothing changed, and plague's drain
-- only takes TP and MP. Neither one is a tick. A WAR with no MP and no TP is the hard case.
local function steps(buffs)
    local t = 0;
    return function (target)
        while (t < target - 1e-9) do
            t = t + 0.05;
            if (math.floor(t * 20 + 0.5) % 4 == 0) then resting.on_buffs(t, buffs); end
            resting.update(t);
        end
        return t;
    end
end

-- Ticks at 21 and 30. Disease from 31 until it wears off at 58.8, 1.2 s before the tick at 60.
resting.reset();
local war_hp = 500;
resting.on_vitals(0, war_hp, 0, 0, 2000, 0);
resting.start(0);
local buffs = {};
local step_to = steps(buffs);
local t = step_to(21.0);
war_hp = war_hp + 10;
resting.on_vitals(t, war_hp, 0, 0, 2000, 0);
t = step_to(30.0);
war_hp = war_hp + 11;
resting.on_vitals(t, war_hp, 0, 0, 2000, 0);
t = step_to(31.0);
resting.on_vitals(t, war_hp, 0, 0, 2000, 0);
buffs[DISEASE] = true;
t = step_to(58.8);
resting.on_vitals(t, war_hp, 0, 0, 2000, 0);
buffs[DISEASE] = nil;
t = step_to(59.2);
check('the packet when it wears off is no tick', near(resting.seen_at(), 30.0), resting.seen_at());
t = step_to(60.0);
war_hp = war_hp + 14;
resting.on_vitals(t, war_hp, 0, 0, 2000, 0);
step_to(60.3);
check('so the tick right after it is the one seen', near(resting.seen_at(), 60.0), resting.seen_at());

-- A mage at full HP. The disease wears off on the same pass as the tick at 60, so that tick heals,
-- but only MP. It still counts.
resting.reset();
local mage_mp = 100;
resting.on_vitals(0, 2000, mage_mp, 0, 2000, 800);
resting.start(0);
buffs = {};
step_to = steps(buffs);
t = step_to(21.0);
mage_mp = mage_mp + 12;
resting.on_vitals(t, 2000, mage_mp, 0, 2000, 800);
t = step_to(30.0);
mage_mp = mage_mp + 13;
resting.on_vitals(t, 2000, mage_mp, 0, 2000, 800);
t = step_to(31.0);
buffs[DISEASE] = true;
t = step_to(60.0);
mage_mp = mage_mp + 16;
resting.on_vitals(t, 2000, mage_mp, 0, 2000, 800);
buffs[DISEASE] = nil;
step_to(60.3);
check('a tick that only heals MP as it wears off still counts', near(resting.seen_at(), 60.0), resting.seen_at());

-- Plagued from the start with 1500 TP. A party member cures it on the 45 s pass, so the last 50 TP
-- drain comes in the same packet as the cure. The next heal is at 51.
resting.reset();
local tp_left = 1500;
resting.on_vitals(0, war_hp, 0, tp_left, 2000, 0);
buffs = { [PLAGUE] = true };
resting.on_buffs(0, buffs);
resting.start(0);
step_to = steps(buffs);
for pass = 3, 45, 3 do
    t = step_to(pass);
    tp_left = tp_left - 50;
    resting.on_vitals(t, war_hp, 0, tp_left, 2000, 0);
end
buffs[PLAGUE] = nil;
t = step_to(45.5);
check('the drain that comes with the cure is no tick', resting.seen_at() == nil or resting.seen_at() < 45, resting.seen_at());
t = step_to(51.0);
war_hp, tp_left = war_hp + 15, tp_left - 100;
resting.on_vitals(t, war_hp, 0, tp_left, 2000, 0);
step_to(51.3);
check('and the heal at 51 is seen', near(resting.seen_at(), 51.0), resting.seen_at());
resting.reset();

table.insert(out, fails == 0 and 'ALL OK' or (fails .. ' FAILED'));
return table.concat(out, '\n');
