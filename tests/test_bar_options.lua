-- Numbers only, draining bars, the ready mark, custom labels, and what Shift shows on a timer. With
-- Shift held, a timer gets an outline and edges you drag to resize it.
local out, fails = {}, 0;
local function near_px(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.01; end
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local hud = require('ui.hud');
local theme = require('ui.theme');
local presets = require('ui.presets');
local imgui = require('imgui');

-- At scale 1 and 14 px text the auto attack bar is 240 wide and starts 12 in from the card's left edge.
local LEFT = s.attack.x + 12;
local BAR_WIDTH = 240;

local function drawn(fill, left)
    hud.refresh(s);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.draw_attack(fill, left, 3.0, true, nil);
    local saved = hud.end_frame();
    MOCK.record_imgui = false;
    return MOCK.imgui_calls, saved;
end
local function rects_in(calls, color)
    local found = {};
    for _, c in ipairs(calls) do
        if (c[1] == 'dl:AddRectFilled' and c[4] == color) then table.insert(found, { c[2][1], c[3][1] }); end
    end
    return found;
end
local function texts_in(calls)
    local all = '|';
    for _, c in ipairs(calls) do if (c[1] == 'dl:AddText') then all = all .. c[6] .. '|'; end end
    return all;
end
local almost = theme.u32(s.attack.almost_color);
local ready = theme.u32(s.attack.ready_color);
local track = theme.u32(s.style.track_color);

-- Numbers only drops the bar and the gap under it, and keeps the text row even with everything in it off.
s.attack.show_tp = false;
hud.refresh(s);
local _, with_bar = hud.element_size('attack');
s.attack.numbers_only = true;
hud.refresh(s);
local _, numbers = hud.element_size('attack');
check('numbers only drops the bar and its gap', with_bar - numbers == s.attack.bar_height + 5, with_bar .. ' vs ' .. numbers);
check('numbers only draws no bar', #rects_in(drawn(0.5, 1.5), track) == 0);
s.style.show_labels, s.attack.show_value, s.attack.show_delay = false, false, false;
check('numbers only keeps the text row', #rects_in(drawn(0.5, 1.5), track) == 0 and select(2, hud.element_size('attack')) == numbers);
s.style.show_labels, s.attack.show_value, s.attack.show_delay = true, true, true;
s.attack.numbers_only = false;

-- The almost ready part of the bar fills from the left, or drains away with the bar.
local calls = drawn(0.9, 0.3);
local bar = rects_in(calls, almost)[1];
check('a filling bar covers what has gone by', bar and bar[1] == LEFT and bar[2] == LEFT + 216, bar and (bar[1] .. '-' .. bar[2]));
s.style.bar_drains = true;
bar = rects_in(drawn(0.9, 0.3), almost)[1];
check('a draining bar covers what is left', bar and bar[1] == LEFT and bar[2] == LEFT + 24, bar and (bar[1] .. '-' .. bar[2]));
bar = rects_in(drawn(1, 0), ready)[1];
check('a drained bar fills back up in the ready color', bar and bar[2] - bar[1] == BAR_WIDTH, bar and (bar[2] - bar[1]));
s.style.bar_drains = false;

-- The ready mark sits where the almost ready color starts, a pixel wide.
local function marks()
    local found = {};
    for _, r in ipairs(rects_in(drawn(0.5, 1.5), almost)) do
        if (r[2] - r[1] == 1) then table.insert(found, r[1]); end
    end
    return found;
end
check('no mark by default', #marks() == 0);
s.attack.almost_mark = true;
local at = marks();
check('the mark sits where almost ready starts', #at == 1 and at[1] == LEFT + 200, at[1]);
s.style.bar_drains = true;
at = marks();
check('a draining bar has the mark from the left', #at == 1 and at[1] == LEFT + 40, at[1]);
s.style.bar_drains = false;
s.attack.almost_ready = false;
check('no mark without the almost ready color', #marks() == 0);
s.attack.almost_ready = true;
check('no mark once ready', #rects_in(drawn(1, 0), almost) == 0);
s.attack.almost_mark = false;

-- Custom labels, with the default when the box is empty.
s.attack.label_text = 'AA';
check('a custom label shows', texts_in(drawn(0.5, 1.5)):find('|AA|', 1, true) ~= nil);
s.attack.label_text = '';
check('an empty label shows the default', texts_in(drawn(0.5, 1.5)):find('|AUTO ATTACK|', 1, true) ~= nil);

-- Label size. Auto draws the name at the small text size. A size of its own draws it at that size,
-- and a name bigger than the numbers makes the row taller, with the number moved down to its baseline.
local function drawn_at(text)
    for _, c in ipairs(drawn(0.5, 1.5)) do
        if (c[1] == 'dl:AddText' and c[6] == text) then return c[3], c[4][2]; end
    end
end
s.attack.show_tp = false;
s.style.text_shadow = false;
hud.refresh(s);
local _, auto_height = hud.element_size('attack');
local name_px = drawn_at('AUTO ATTACK');
local _, value_y = drawn_at('1.5');
check('auto draws the name at the small text size', name_px == 11, name_px);
s.style.label_size = 12;
hud.refresh(s);
check('a name smaller than the numbers keeps the row', select(2, hud.element_size('attack')) == auto_height
    and drawn_at('AUTO ATTACK') == 12);
s.style.label_size = 20;
hud.refresh(s);
local _, big_height = hud.element_size('attack');
local big_px = drawn_at('AUTO ATTACK');
local _, big_value_y = drawn_at('1.5');
check('a bigger name draws at its size', big_px == 20, big_px);
check('and makes the row taller', big_height == auto_height + 6, big_height .. ' vs ' .. auto_height);
check('the number moves down to share its baseline', near_px(big_value_y, value_y + 4.5), big_value_y .. ' vs ' .. value_y);
s.style.scale = 2.0;
hud.refresh(s);
check('scale applies on top', drawn_at('AUTO ATTACK') == 40, drawn_at('AUTO ATTACK'));
s.style.scale = 1.0;
s.style.show_labels = false;
hud.refresh(s);
check('with labels off the row goes back', select(2, hud.element_size('attack')) < big_height);
s.style.show_labels = true;
s.enemy.enabled, s.enemy.attached = true, true;
hud.refresh(s);
local _, big_strip = hud.element_size('enemy');
s.style.label_size = 0;
hud.refresh(s);
check('the attached strip grows for a bigger name too', big_strip > select(2, hud.element_size('enemy')));
s.enemy.enabled, s.enemy.attached = false, false;
s.style.label_size = 20;
presets.reset(s);
check('reset look puts label size back to auto', s.style.label_size == 0);
s.style.text_shadow = true;
s.attack.show_tp = true;
hud.refresh(s);

-- Detail size. Auto draws the small text at the small text size. A size of its own draws the delay
-- next to the name and the TP line under the bar at that size, and grows the rows to fit.
local function drawn_with_tp()
    hud.refresh(s);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.draw_attack(0.5, 1.5, 3.0, true, { tp = 640, goal = 1000, rounds = 3 });
    hud.end_frame();
    MOCK.record_imgui = false;
    local sizes = {};
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText') then sizes[c[6]] = c[3]; end end
    return sizes;
end
s.style.text_shadow = false;
local sizes = drawn_with_tp();
local _, auto_rows = hud.element_size('attack');
check('auto draws the small text at the small size', sizes['3.00s'] == 11 and sizes['TP 640'] == 11,
    tostring(sizes['3.00s']) .. ' ' .. tostring(sizes['TP 640']));
s.style.detail_size = 12;
sizes = drawn_with_tp();
check('a size of its own for the delay and the TP line', sizes['3.00s'] == 12 and sizes['TP 640'] == 12
    and sizes['AUTO ATTACK'] == 11 and sizes['1.5'] == 14);
check('the line under the bar grows with it', select(2, hud.element_size('attack')) == auto_rows + 1,
    select(2, hud.element_size('attack')) .. ' vs ' .. auto_rows);
s.style.detail_size = 20;
drawn_with_tp();
check('small text bigger than the numbers grows the row too', select(2, hud.element_size('attack')) == auto_rows + 6 + 9,
    select(2, hud.element_size('attack')) .. ' vs ' .. auto_rows);
s.attack.show_delay = false;
hud.refresh(s);
check('with no small text next to the name the row goes back', select(2, hud.element_size('attack')) == auto_rows + 9,
    select(2, hud.element_size('attack')));
s.attack.show_delay = true;
s.style.detail_size = 0;

-- Text outline. Eight copies around the text in the outline color, then the text. Bigger text gets
-- a thicker outline.
local edge = theme.u32(s.style.outline_color);
local function copies(text)
    local around, xs, ys, main = 0, {}, {}, nil;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddText' and c[6] == text) then
            if (c[5] == edge) then
                around = around + 1;
                table.insert(xs, c[4][1]);
                table.insert(ys, c[4][2]);
            else
                main = c[4];
            end
        end
    end
    local reach = 0;
    for i = 1, #xs do reach = math.max(reach, math.abs(xs[i] - main[1]), math.abs(ys[i] - main[2])); end
    return around, reach;
end
drawn(0.5, 1.5);
check('no outline by default', copies('AUTO ATTACK') == 0);
s.style.text_outline = true;
drawn(0.5, 1.5);
local around, reach = copies('AUTO ATTACK');
check('an outline all the way around', around == 8 and reach == 1, around .. ' ' .. reach);
s.style.label_size, s.style.scale = 20, 2.0;
drawn(0.5, 1.5);
around, reach = copies('AUTO ATTACK');
check('bigger text gets a thicker outline', around == 8 and reach == 3, around .. ' ' .. reach);
s.style.label_size, s.style.scale = 0, 1.0;
s.style.text_shadow = true;
local shadows = 0;
for _, c in ipairs(drawn(0.5, 1.5)) do
    if (c[1] == 'dl:AddText' and c[6] == 'AUTO ATTACK') then shadows = shadows + 1; end
end
check('outline and shadow together', shadows == 10, shadows);
s.style.detail_size, s.style.outline_color[1] = 18, 0.5;
presets.reset(s);
check('reset look puts detail size and the outline back', s.style.detail_size == 0 and not s.style.text_outline
    and s.style.outline_color[1] ~= 0.5);
s.attack.show_tp = true;
hud.refresh(s);

-- Shift shows the grips. Locked, or with Shift up, there are none.
local function grips()
    local ids = {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'InvisibleButton') then ids[c[2]] = true; end
    end
    return ids;
end
drawn(0.5, 1.5);
check('no grips without Shift', next(grips()) == nil);
hud.set_movable(true);
drawn(0.5, 1.5);
local ids = grips();
check('Shift shows all three grips', ids['##grip_width_attack'] and ids['##grip_height_attack'] and ids['##grip_corner_attack']);
s.attack.numbers_only = true;
drawn(0.5, 1.5);
ids = grips();
check('numbers only keeps its whole-height grip', ids['##grip_width_attack'] and ids['##grip_height_attack']);
s.attack.numbers_only = false;
s.style.locked = true;
drawn(0.5, 1.5);
check('locked has no grips', next(grips()) == nil);
s.style.locked = false;

-- The attached enemy strip follows the card above it, so it has no grips of its own.
s.enemy.enabled, s.enemy.attached = true, true;
hud.refresh(s);
MOCK.imgui_calls = {};
MOCK.record_imgui = true;
hud.begin_frame();
hud.join_below(true);
hud.draw_attack(0.5, 1.5, 3.0, true, nil);
hud.draw_enemy({ fill = 0.3, left = 2.0, delay = 4.0, learned = true, waiting = false, name = 'Goblin' });
hud.end_frame();
MOCK.record_imgui = false;
ids = grips();
check('the attached strip has no grips', ids['##grip_width_attack'] and not ids['##grip_width_enemy']);

-- With the mouse on the joined card, Shift outlines all of it. Between fights the auto attack card is
-- gone and the strip stays where it hangs. It can't be dragged there, so it gets no outline.
local OUTLINE = theme.u32(theme.with_alpha(theme.palette.ember, 0.85));
local function outlines()
    local n = 0;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddRect' and c[4] == OUTLINE) then n = n + 1; end
    end
    return n;
end
local strip = { fill = 0.3, left = 2.0, delay = 4.0, learned = true, waiting = false, name = 'Goblin' };
rawset(imgui, 'IsWindowHovered', function () return true; end);
MOCK.imgui_calls = {};
MOCK.record_imgui = true;
hud.begin_frame();
hud.join_below(true);
hud.draw_attack(0.5, 1.5, 3.0, true, nil);
hud.draw_enemy(strip);
hud.end_frame();
check('both parts of the joined card draw its outline', outlines() == 2, outlines());
MOCK.imgui_calls = {};
hud.begin_frame();
hud.join_below(true);
hud.draw_enemy(strip);
hud.end_frame();
MOCK.record_imgui = false;
check('with the card gone, the strip has no outline', outlines() == 0, outlines());
rawset(imgui, 'IsWindowHovered', nil);
s.enemy.enabled, s.enemy.attached = false, false;

-- With the auto attack timer off, the attached strip sits at its own spot. It takes the auto attack
-- timer's width, so only its bottom edge can be dragged.
s.attack.enabled = false;
s.enemy.enabled, s.enemy.attached = true, true;
hud.refresh(s);
MOCK.imgui_calls = {};
MOCK.record_imgui = true;
hud.begin_frame();
hud.join_below(false);
hud.draw_enemy({ fill = 0.3, left = 2.0, delay = 4.0, learned = true, waiting = false, name = 'Goblin' });
hud.end_frame();
MOCK.record_imgui = false;
ids = grips();
check('a strip on its own gets only its bottom edge', ids['##grip_height_enemy'] and not ids['##grip_width_enemy']
    and not ids['##grip_corner_enemy']);
s.attack.enabled = true;
s.enemy.enabled, s.enemy.attached = false, false;

-- Dragging a grip. The mouse moves 60 right and 10 down from where the drag started.
local drag = { id = nil, started = false };
local last_id = nil;
local mouse = { 0, 0 };
rawset(imgui, 'InvisibleButton', function (id) last_id = id; end);
rawset(imgui, 'IsItemActivated', function () return last_id == drag.id and not drag.started; end);
rawset(imgui, 'IsItemActive', function () return last_id == drag.id; end);
rawset(imgui, 'GetMousePos', function () return mouse[1], mouse[2]; end);
local function drag_grip(id, dx, dy)
    drag.id, drag.started = id, false;
    mouse[1], mouse[2] = 900, 700;
    MOCK.mouse_down = true;
    drawn(0.5, 1.5);
    drag.started = true;
    mouse[1], mouse[2] = 900 + dx, 700 + dy;
    drawn(0.5, 1.5);
    drag.id = nil;
    MOCK.mouse_down = false;
    local _, saved = drawn(0.5, 1.5);
    return saved;
end
local saved = drag_grip('##grip_width_attack', 60, 10);
check('the right edge sets the width', s.attack.width == 300 and s.attack.bar_height == 5, s.attack.width .. ' ' .. s.attack.bar_height);
check('letting go saves it', saved == true);
local before_height = select(2, hud.element_size('attack'));
drag_grip('##grip_height_attack', 60, 10);
check('the bottom edge sets whole height without changing thickness', s.attack.width == 300
    and s.attack.bar_height == 5 and math.abs(select(2, hud.element_size('attack')) - before_height - 10) <= 2);
before_height = select(2, hud.element_size('attack'));
drag_grip('##grip_corner_attack', -20, -5);
check('the corner sets width and whole height', s.attack.width == 280 and s.attack.bar_height == 5
    and math.abs(select(2, hud.element_size('attack')) - before_height + 5) <= 2);

drag_grip('##grip_corner_attack', -900, -900);
check('a drag stops at the smallest size', s.attack.width == 120 and s.attack.height_scale == 0.5
    and s.attack.bar_height == 5);
drag_grip('##grip_corner_attack', 5000, 5000);
check('and at the largest', s.attack.width == 640 and s.attack.height_scale == 2.5
    and s.attack.bar_height == 5);
s.style.scale = 2.0;
s.attack.width, s.attack.bar_height, s.attack.height_scale = 240, 5, 1;
hud.refresh(s);
before_height = select(2, hud.element_size('attack'));
drag_grip('##grip_corner_attack', 60, 10);
check('scale 2 keeps the height drag in screen pixels', s.attack.width == 270 and s.attack.bar_height == 5
    and math.abs(select(2, hud.element_size('attack')) - before_height - 10) <= 2);
s.style.scale = 1.0;

-- The separate enemy strip changes its whole height too, preserving the thinner progress bar setting.
s.attack.enabled = false;
s.enemy.enabled, s.enemy.attached, s.enemy.bar_height, s.enemy.height_scale = true, true, 5, 1;
local function drag_strip(dy)
    drag.id, drag.started = '##grip_height_enemy', false;
    mouse[1], mouse[2] = 900, 700;
    for step = 1, 2 do
        hud.refresh(s);
        hud.begin_frame();
        hud.join_below(false);
        hud.draw_enemy({ fill = 0.3, left = 2.0, delay = 4.0, learned = true, waiting = false, name = 'Goblin' });
        hud.end_frame();
        drag.started = true;
        mouse[2] = 700 + dy;
    end
    drag.id = nil;
end
hud.refresh(s);
before_height = select(2, hud.element_size('enemy'));
drag_strip(6);
check('the strip bottom edge follows the mouse without changing bar thickness', s.enemy.height_scale > 1
    and s.enemy.bar_height == 5 and math.abs(select(2, hud.element_size('enemy')) - before_height - 6) <= 2);
s.attack.enabled = true;
s.attack.height_scale = 1;
s.enemy.enabled, s.enemy.attached, s.enemy.bar_height = false, false, 5;
for _, name in ipairs({ 'InvisibleButton', 'IsItemActivated', 'IsItemActive', 'GetMousePos' }) do rawset(imgui, name, nil); end
hud.set_movable(false);

-- Reset look puts the bar options and labels back.
s.attack.label_text, s.attack.numbers_only, s.attack.almost_mark, s.style.bar_drains = 'AA', true, true, true;
s.resting.label_text, s.enemy.numbers_only = 'HEAL', true;
presets.reset(s);
check('reset look puts the bar options back', s.attack.label_text == '' and not s.attack.numbers_only
    and not s.attack.almost_mark and not s.style.bar_drains and s.resting.label_text == '' and not s.enemy.numbers_only);

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
