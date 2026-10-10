-- Whole-card vertical resizing from the player's large-text, minimum-thickness resting layout.
local hud, defaults, imgui = require('ui.hud'), require('ui.defaults'), require('imgui');
local s = defaults.make();
s.style.shared_spot, s.style.locked, s.style.layout_guides = false, false, false;
s.style.label_size, s.style.detail_size, s.style.scale = 32, 29, 0.87;
s.style.text_shadow = false;
s.attack.x, s.attack.y, s.resting.x, s.resting.y = 30, 30, 600, 250;
s.resting.bar_height, s.resting.height_scale = 2, 1;
s.resting.show_next_gains, s.resting.show_ticks, s.resting.show_each_full = true, true, true;
s.enemy.attached = false;
local out, fails = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then fails = fails + 1; end
end
local last_id, active_id, activated, mouse_x, mouse_y = nil, nil, false, 900, 700;
rawset(imgui, 'InvisibleButton', function (id) last_id = id; end);
rawset(imgui, 'IsItemActivated', function () return last_id == active_id and activated; end);
rawset(imgui, 'IsItemActive', function () return last_id == active_id; end);
rawset(imgui, 'GetMousePos', function () return mouse_x, mouse_y; end);
local view = { fill = 0.5, left = 4, gained_hp = 19, gained_mp = 0, full = false, flash = 0,
    next_hp = 21, hp_full_in = 14, has_mp = false, full_meta = { ticks = 2, confidence = 'estimated' } };
local enemy = { fill = 0.5, left = 2, delay = 4, learned = true, waiting = false };
hud.refresh(s);
local function frame(movable)
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    hud.set_movable(movable ~= false);
    hud.begin_frame();
    hud.join_below(s.enemy.attached and s.attack.enabled);
    if (s.attack.enabled) then hud.draw_attack(0.5, 2, 4, true, nil); end
    hud.draw_resting(view);
    hud.draw_enemy(enemy);
    local changed, before = hud.end_frame();
    MOCK.record_imgui = false;
    return changed, before;
end
local function fonts()
    local found = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'dl:AddText') then found[call[6]] = call[3]; end
    end
    return found;
end
local function begin(id)
    active_id, activated, mouse_x, mouse_y, MOCK.mouse_down = id, true, 900, 700, true;
    frame();
    activated = false;
end
local function finish()
    active_id, MOCK.mouse_down = nil, false;
    return frame();
end
local function height(key) return select(2, hud.element_size(key)); end
frame(false);
local width, original = hud.element_size('resting');
local attack_width, attack_height = hud.element_size('attack');
local enemy_width, enemy_height = hud.element_size('enemy');
local original_fonts = fonts();
begin('##grip_height_resting');
check('clicking the bottom edge alone keeps the starting height scale', s.resting.height_scale == 1);
mouse_y = 660; frame();
local smaller = height('resting');
check('A minimum-thickness resting card shrinks by the vertical drag', smaller < original
    and math.abs(smaller - (original - 40)) <= 2, original .. ' -> ' .. smaller);
check('vertical resize preserves width thickness and placement', hud.element_size('resting') == width
    and s.resting.bar_height == 2 and s.resting.x == 600 and s.resting.y == 250);
frame();
local smaller_fonts = fonts();
check('the resting name and detail text shrink with its card', smaller_fonts.RESTING < original_fonts.RESTING
    and smaller_fonts['HP full in 14s'] < original_fonts['HP full in 14s']);
check('other timer sizes and fonts stay unchanged', hud.element_size('attack') == attack_width
    and height('attack') == attack_height and hud.element_size('enemy') == enemy_width
    and height('enemy') == enemy_height and smaller_fonts['AUTO ATTACK'] == original_fonts['AUTO ATTACK']);
local scale = s.resting.height_scale;
for _ = 1, 12 do frame(); end
check('holding still never compounds the height change', s.resting.height_scale == scale and height('resting') == smaller);
local changed, before = finish();
check('release returns one Undo snapshot with the original height and thickness',
    changed and before and before.resting.height_scale == 1 and before.resting.bar_height == 2);
check('quiet frames do not repeat the completed gesture', not frame());
begin('##grip_height_resting'); mouse_y = -5000; frame(); finish();
check('vertical shrinking stops at one-half height scale', s.resting.height_scale == 0.5);
begin('##grip_height_resting'); mouse_y = 5000; frame(); finish();
check('vertical growth stops at two-and-a-half height scale', s.resting.height_scale == 2.5);
s.resting.height_scale = 1; hud.refresh(s);
begin('##grip_corner_resting'); mouse_x, mouse_y = 940, 680; frame(); finish();
check('corner drag changes width and whole height together', s.resting.width > 240
    and s.resting.height_scale < 1 and s.resting.bar_height == 2);

s.resting.numbers_only, s.resting.height_scale = true, 1; hud.refresh(s);
original = height('resting');
begin('##grip_height_resting'); mouse_y = 680; frame(); finish();
check('Text only still supports vertical resizing', s.resting.height_scale < 1
    and math.abs(height('resting') - original + 20) <= 2 and s.resting.bar_height == 2);

s.enemy.attached, s.enemy.height_scale, s.attack.height_scale = true, 0.6, 1.7;
hud.refresh(s);
hud.begin_frame();
local standalone_width, standalone_height = hud.element_size('enemy');
hud.end_frame();
frame();
check('attached strip inherits width without inheriting host height metrics',
    standalone_width == hud.element_size('attack') and standalone_height == height('enemy'));
local seen_fonts = fonts();
check('joined timers draw their separate vertical text sizes', seen_fonts.ENEMY
    and seen_fonts['AUTO ATTACK'] and seen_fonts.ENEMY < seen_fonts['AUTO ATTACK']);
local attack_scale, enemy_scale = s.attack.height_scale, s.enemy.height_scale;
begin('##grip_height_enemy'); mouse_y = 750; frame(); finish();
check('a pinned attached strip cannot resize itself through its host', s.enemy.height_scale == enemy_scale
    and s.attack.height_scale == attack_scale);
s.attack.enabled = false; hud.refresh(s); frame();
original = height('enemy');
begin('##grip_height_enemy'); mouse_y = 710; frame(); finish();
check('an attached strip on its own resizes vertically', s.enemy.height_scale > enemy_scale
    and math.abs(height('enemy') - original - 10) <= 2);

s.style.locked = true; hud.refresh(s);
scale = s.resting.height_scale;
begin('##grip_height_resting'); mouse_y = 600; frame(); finish();
check('locked timers retain their vertical scale', s.resting.height_scale == scale);
s.style.locked = false; hud.refresh(s);
active_id, activated, MOCK.mouse_down, mouse_y = '##grip_height_resting', true, true, 700;
frame(false); activated, mouse_y = false, 600; frame(false); finish();
check('ordinary gameplay does not resize a timer', s.resting.height_scale == scale);

begin('##grip_height_resting'); mouse_y = 650; frame();
local replacement = defaults.make();
s = replacement; hud.refresh(s);
mouse_y = 600; frame();
changed, before = finish();
check('a character replacement cancels the old resize and Undo snapshot', not changed and before == nil
    and replacement.resting.height_scale == 1 and replacement.attack.height_scale == 1);
check('vertical resizing sends no game commands', #MOCK.commands == 0);
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
