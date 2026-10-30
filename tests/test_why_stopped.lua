-- While a spell, ranged attack, item or effect stops the auto attack bar, the bar dims and says why in
-- place of the seconds. Loaded mid-fight, it shows "--" until the first attack.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end
local function near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 0.05); end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };   -- 4.0 s
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local attack = require('core.attack');
local hud = require('ui.hud');
local theme = require('ui.theme');

local ME, MOB = 1001, 0x01000200;
local function run_to(t) while (MOCK.now + 1 / 60 < t) do MOCK.frame(1 / 60); end MOCK.now = t; end
local function round() MOCK.fire('packet_in', MOCK.action_packet(ME, 1, 0, MOB, { { message = 1 } })); end
local function says(message) MOCK.fire('packet_in', MOCK.message_packet(ME, MOB, 0, 0, message, 0x200)); end
-- A spell (8), item (9) or ranged attack (12) starting, and one finishing (4, 5 or 2).
local function starts(category) MOCK.fire('packet_in', MOCK.action_packet(ME, category, 0x6163, ME, { { message = 327 } })); end
local function finishes(category)
    MOCK.fire('packet_in', MOCK.action_packet(ME, category, category == 5 and 4112 or 1, MOB, { { message = 7 } }));
end

-- One frame's draw calls.
local function frame()
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    return MOCK.imgui_calls;
end
local function texts(calls)
    local all = '|';
    for _, c in ipairs(calls or frame()) do if (c[1] == 'dl:AddText') then all = all .. c[6] .. '|'; end end
    return all;
end
local function shows(word, calls) return texts(calls):find('|' .. word .. '|', 1, true) ~= nil; end
local function seconds_shown(calls) return texts(calls):match('|%d+%.%d|') ~= nil; end

-- The colors a word was drawn in, shadow included.
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
-- True when `c` is `color` with less alpha, but not none.
local function dimmed_from(c, color)
    local full = theme.u32(color);
    return c ~= nil and rgb(c) == rgb(full) and alpha(c) > 0 and alpha(c) < alpha(full);
end

--[[
    Loaded while you're already engaged. No status has been seen, so the first attack's time isn't known.
]]
MOCK.now = 100;
MOCK.player.status = 1;
check('loaded mid-fight, it says --', shows('--'));
local fill, left = attack.progress(MOCK.now);
check('with an empty bar and no seconds', fill == 0 and left == nil, tostring(fill) .. ' ' .. tostring(left));
run_to(102.0);
local calls = frame();
check('no made-up first attack', shows('--', calls) and not shows('ready', calls), texts(calls));
check('the delay still shows', texts(calls):find('|4.00s est.|', 1, true) ~= nil, texts(calls));
check('the -- is in the detail color', word_colors(calls, '--')[theme.u32(s.style.detail_color)]);
s.attack.almost_mark = true;
check('the ready mark has nothing to mark', shows('--'));
s.attack.almost_mark = false;
says(4);
check('the server saying too far still shows', shows('too far'));
MOCK.player.buffs = { 2 };
run_to(102.5);
check('so does falling asleep', shows('asleep'));
MOCK.player.buffs = {};
run_to(103.0);
round();
calls = frame();
check('the first attack starts the count', shows('4.0', calls), texts(calls));

-- Engaging while cadence watches counts to the first attack, after zoning too.
MOCK.player.status = 0;
MOCK.frame(1 / 60);
MOCK.player.status = 1;
MOCK.frame(1 / 60);
check('engaging counts to the first attack', shows('2.8'));
MOCK.fire('packet_in', MOCK.zone_packet(ME));
MOCK.player.status = 0;
MOCK.frame(1 / 60);
MOCK.player.status = 1;
MOCK.frame(1 / 60);
check('so does engaging after zoning', shows('2.8'));

-- A steady fight. The last round is at t0 + 13.6 and the next is due at t0 + 17.6.
local function engaged_at(t0)
    MOCK.player.buffs = {};
    MOCK.player.status = 0;
    MOCK.now = t0;
    MOCK.frame(1 / 60);
    MOCK.player.status = 1;
    MOCK.frame(1 / 60);
    for _, t in ipairs({ 1.6, 5.6, 9.6, 13.6 }) do run_to(t0 + t); round(); end
end

--[[
    Spells, ranged attacks and items.
]]
local T = 1000;
engaged_at(T);
run_to(T + 14.6);
calls = frame();
local bar = fill_calls(calls);
check('a running bar has its full gradient', bar[1] and bar[1][1] == 'dl:AddRectFilledMultiColor'
    and bar[1][4] == theme.u32(s.attack.fill_start), bar[1] and bar[1][4]);

starts(8);
calls = frame();
bar = fill_calls(calls);
check('a spell says casting', shows('casting', calls) and not seconds_shown(calls), texts(calls));
check('and dims the gradient', bar[1] and bar[1][1] == 'dl:AddRectFilledMultiColor'
    and dimmed_from(bar[1][4], s.attack.fill_start), bar[1] and bar[1][4]);
check('without flattening it', bar[1] and rgb(bar[1][4]) ~= rgb(bar[1][5]) and alpha(bar[1][4]) == alpha(bar[1][5]));

-- Rounded ends sit beside the gradient, so a dimmed fill has no brighter seams.
s.style.rounding = 6;
hud.refresh(s);
bar = fill_calls(frame());
local gradient, first_end, last_end = bar[1], bar[2], bar[3];
check('rounded ends don\'t overlap the gradient', gradient and first_end and last_end
    and gradient[1] == 'dl:AddRectFilledMultiColor' and first_end[3][1] <= gradient[2][1] and gradient[3][1] <= last_end[2][1],
    last_end and ('%s..%s %s..%s %s..%s'):format(first_end[2][1], first_end[3][1], gradient[2][1], gradient[3][1],
        last_end[2][1], last_end[3][1]));
check('and are dimmed too', first_end and dimmed_from(first_end[4], s.attack.fill_start)
    and last_end and alpha(last_end[4]) == alpha(first_end[4]));

-- However short the fill, no gradient is drawn backwards between the ends. The bar is 240 px wide.
local backwards = {};
for px = 1, 20 do
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.draw_attack(px / 240, 3, 4.0, true, nil, nil, 'spell');
    hud.end_frame();
    MOCK.record_imgui = false;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddRectFilledMultiColor' and c[3][1] < c[2][1]) then table.insert(backwards, px); end
    end
end
check('a short fill draws no gradient backwards', #backwards == 0, table.concat(backwards, ' '));
s.style.rounding = 0;
hud.refresh(s);

finishes(4);
calls = frame();
check('the seconds come back once the spell ends', seconds_shown(calls) and not shows('casting', calls), texts(calls));
bar = fill_calls(calls);
check('and the bar brightens', bar[1] and bar[1][4] == theme.u32(s.attack.fill_start));

starts(12);
check('a ranged attack says ranged', shows('ranged'));
finishes(2);
check('then counts again', seconds_shown());
starts(9);
check('an item says item', shows('item'));
finishes(5);
check('then counts again', seconds_shown());

--[[
    Effects that stop attacks, each with its word.
]]
local WORDS = { [2] = 'asleep', [7] = 'petrified', [10] = 'stunned', [19] = 'asleep', [28] = 'terrified',
    [159] = 'penalty', [193] = 'asleep' };
local wrong = {};
for _, id in ipairs({ 2, 7, 10, 19, 28, 159, 193 }) do
    T = T + 100;
    engaged_at(T);
    run_to(T + 14.6);
    MOCK.player.buffs = { id };
    run_to(T + 15.0);
    calls = frame();
    if (not shows(WORDS[id], calls) or seconds_shown(calls)) then table.insert(wrong, id .. ' ' .. texts(calls)); end
    MOCK.player.buffs = {};
end
check('every effect that stops attacks has its word', #wrong == 0, table.concat(wrong, ', '));

-- Stun and Lullaby at once. The first one in cadence's list is named.
T = T + 100;
engaged_at(T);
run_to(T + 14.6);
MOCK.player.buffs = { 193, 10 };
run_to(T + 15.0);
check('two at once, the first in the list is named', shows('stunned'));

-- Stunned mid-spell. The stun cuts the spell off, so it's named, before the interrupt and after.
T = T + 100;
engaged_at(T);
run_to(T + 14.0);
starts(8);
run_to(T + 14.2);
MOCK.player.buffs = { 10 };
run_to(T + 14.6);
check('stunned mid-spell says stunned', shows('stunned'));
MOCK.fire('packet_in', MOCK.action_packet(ME, 8, 0x7073, ME, { { message = 16 } }));
check('and still does once the spell is cut off', shows('stunned'));
MOCK.player.buffs = {};
run_to(T + 15.0);
check('the unknown recovery stays explicit after stun wears off', shows('recovery unknown') and not seconds_shown());
round();
check('an observed round restores the countdown after interruption', seconds_shown());

--[[
    What comes first, and the colors.
]]
-- Ready and too far, then put to sleep. The word comes first, and the ready color dims.
T = T + 100;
engaged_at(T);
run_to(T + 18.0);
says(4);
check('ready and out of range says too far', shows('too far'));
MOCK.player.buffs = { 2 };
run_to(T + 18.4);
calls = frame();
bar = fill_calls(calls);
check('asleep comes before too far', shows('asleep', calls) and not shows('too far', calls), texts(calls));
check('the full bar dims its ready color', bar[1] and bar[1][1] == 'dl:AddRectFilled'
    and dimmed_from(bar[1][4], s.attack.ready_color), bar[1] and bar[1][4]);
check('the word is in the detail color, not the ready color', word_colors(calls, 'asleep')[theme.u32(s.style.detail_color)]
    and not word_colors(calls, 'asleep')[theme.u32(s.attack.ready_color)]);
MOCK.player.buffs = {};
run_to(T + 18.8);
check('awake again it says too far', shows('too far'));

-- Stopped just before an attack, the bar keeps its almost ready color, dimmed, and doesn't look ready
-- to go.
T = T + 100;
engaged_at(T);
run_to(T + 17.3);
MOCK.player.buffs = { 7 };
run_to(T + 18.0);
calls = frame();
bar = fill_calls(calls);
check('frozen just before an attack says petrified', shows('petrified', calls), texts(calls));
check('its almost ready color is dimmed', bar[1] and dimmed_from(bar[1][4], s.attack.almost_color), bar[1] and bar[1][4]);
check('and the word isn\'t in the almost ready color', not word_colors(calls, 'petrified')[theme.u32(s.attack.almost_color)]);

-- Turned off, the bar shows its seconds and doesn't dim.
s.attack.show_why = false;
calls = frame();
bar = fill_calls(calls);
check('turned off, it shows the seconds', seconds_shown(calls) and not shows('petrified', calls), texts(calls));
check('and doesn\'t dim', bar[1] and bar[1][4] == theme.u32(s.attack.almost_color), bar[1] and bar[1][4]);
s.attack.show_why = true;

-- With Seconds left off there's no word, but the bar still dims.
s.attack.show_value = false;
calls = frame();
bar = fill_calls(calls);
check('with Seconds left off, no word', not shows('petrified', calls), texts(calls));
check('but the bar still dims', bar[1] and dimmed_from(bar[1][4], s.attack.almost_color), bar[1] and bar[1][4]);
s.attack.show_value = true;
MOCK.player.buffs = {};

--[[
    The timer on its own.
]]
local function why(t) return select(5, attack.progress(t)); end
attack.reset();
attack.engage(0, 4.0, 'unit');
check('nothing stops a fresh timer', why(0.5) == nil);
attack.on_cast_begin(1.0, 'ranged');
check('a ranged attack holds it', why(1.2) == 'ranged');
attack.on_cast_end(1.5);
check('nothing once it ends', why(1.6) == nil, why(1.6));
attack.on_disabled(2.0, 28);
check('terror stops it', why(2.2) == 28, why(2.2));
attack.on_enabled(3.0);
check('nothing once it wears off', why(3.1) == nil, why(3.1));
attack.on_cast_begin(4.0, 'spell');
attack.on_disabled(4.2, 10);
check('stun comes before the spell it cuts off', why(4.3) == 10, why(4.3));
attack.on_enabled(5.0);
check('the spell shows again once the stun is gone', why(5.1) == 'spell', why(5.1));
attack.on_cast_end(5.2);

attack.engage(10, 4.0, 'unit', true);
fill, left = attack.progress(12);
check('joined late, the bar is empty with no seconds', fill == 0 and left == nil);
attack.on_round(12.5, 4.0, 'unit');
fill, left = attack.progress(13.0);
check('the first round starts the count', near(left, 3.5) and near(fill, 0.125), tostring(fill) .. ' ' .. tostring(left));
attack.engage(20, 4.0, 'unit');
check('engaging otherwise counts to the first attack', near(select(2, attack.progress(20.4)), 2.4));

--[[
    The setting.
]]
check('on by default', require('ui.defaults').make().attack.show_why == true);
MOCK.fire('command', { command = '/cadence' });
calls = frame();
local order = {};
for _, c in ipairs(calls) do
    if (c[1] == 'Checkbox' and (c[2] == 'Range / facing' or c[2] == 'Why it stopped' or c[2] == 'Seconds left##resting')) then
        table.insert(order, c[2]);
    end
end
check('it sits after Range / facing in the auto attack section', table.concat(order, ', ')
    == 'Range / facing, Why it stopped, Seconds left##resting', table.concat(order, ', '));

-- Its (?) says what it does.
rawset(require('imgui'), 'IsItemHovered', function () return true; end);
calls = frame();
rawset(require('imgui'), 'IsItemHovered', nil);
local tip, after = nil, false;
for _, c in ipairs(calls) do
    if (c[1] == 'Checkbox') then after = c[2] == 'Why it stopped'; end
    if (after and tip == nil and c[1] == 'TextUnformatted') then tip = tostring(c[2]); end
end
check('its tip names the words', tip ~= nil and tip:find('"casting"', 1, true) ~= nil and tip:find('"asleep"', 1, true) ~= nil,
    tip);
MOCK.fire('command', { command = '/cadence' });

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
