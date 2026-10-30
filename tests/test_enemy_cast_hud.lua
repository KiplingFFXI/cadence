-- Casting can stand alone or finish the joined enemy stack without claiming completion.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
addon.name = 'cadence';
local imgui, hud = require('imgui'), require('ui.hud');
local s = require('ui.defaults').make();
s.style.text_shadow, s.style.text_outline, s.style.layout_guides = false, false, false;
s.attack.x, s.attack.y, s.attack.width = 20, 30, 300;
s.enemy.x, s.enemy.y, s.enemy.width, s.enemy.enabled = 60, 70, 280, true;
s.recovery.enabled, s.recovery.attached = true, true;
s.enemycast.x, s.enemycast.y, s.enemycast.width, s.enemycast.enabled = 500, 300, 240, true;
MOCK.screen, MOCK.mouse = { 1000, 700 }, { -1, -1 };
local view = { spell = 'Firaga III', duration = 6, left = 2.01, fill = 0.66, estimated = true, waiting = false };
local recovery = { fill = 0.5, left = 1.5, duration = 2.5, kind = 'spell', estimated = true };
local enemy = { fill = 0.5, left = 2, delay = 4, name = 'Goblin', learned = true };
local rest = { fill = 0.5, left = 5, flash = 0 };
local function draw(host, with_recovery, with_enemy)
    hud.begin_frame(with_recovery and recovery or nil, view);
    hud.join_below(with_enemy and s.enemy.attached and s.attack.enabled,
        with_recovery and s.recovery.attached and s.attack.enabled, s.enemycast.attached and s.enemy.enabled);
    if (host == 'attack') then hud.draw_attack(0.5, 2, 4, true);
    elseif (host == 'resting') then hud.draw_resting(rest); end
    if (with_recovery) then hud.draw_recovery(recovery); end
    if (with_enemy) then hud.draw_enemy(enemy); end
    hud.draw_enemycast(view);
    return hud.end_frame();
end
local function capture(host, with_recovery, with_enemy)
    hud.refresh(s);
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    local changed, before = draw(host, with_recovery, with_enemy);
    MOCK.record_imgui = false;
    local windows, words, pos, size = {}, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'SetNextWindowPos') then pos = call[2]; end
        if (call[1] == 'SetNextWindowSize') then size = call[2]; end
        if (call[1] == 'Begin') then windows[call[2]:sub(11)] = { x = pos[1], y = pos[2], width = size[1], height = size[2] }; end
        if (call[1] == 'dl:AddText') then words[#words + 1] = call[6]; end
    end
    return windows, table.concat(words, '|'), changed, before;
end
local w, text = capture(nil, false, false);
check('the standalone card identifies the spell and estimated time', text:find('ENEMY CAST', 1, true)
    and text:find('Firaga III', 1, true) and text:find('~2.1s', 1, true), text);
check('the standalone card uses its own position', w.enemycast.x == 500 and w.enemycast.y == 300);
view.left, view.waiting, view.fill = 0, true, 1;
w, text = capture(nil, false, false);
check('an elapsed estimate stays waiting without a completion claim', text:find('waiting', 1, true)
    and not text:find('ready', 1, true) and not text:find('~0', 1, true), text);
s.enemycast.show_value, s.enemycast.show_label, s.enemycast.show_spell = false, false, false;
w, text = capture(nil, false, false);
check('unknown timing remains visible when optional readouts are hidden', text:find('waiting', 1, true), text);
s.enemycast.show_value, s.enemycast.show_label, s.enemycast.show_spell = true, true, true;
view.left, view.waiting, view.fill = 2, false, 0.5;
s.enemycast.attached = true;
w = capture(nil, false, true);
local _, eh = hud.element_size('enemy');
local _, ch = hud.element_size('enemycast');
check('casting attaches below the standalone enemy card and inherits width', w.enemycast.width == w.enemy.width
    and w.enemycast.y == w.enemy.y + eh - 1 and w.enemy.height == eh + ch - 1);
s.enemy.attached = true;
w = capture('attack', true, true);
local _, ah = hud.element_size('attack');
local _, rh = hud.element_size('recovery');
eh = select(2, hud.element_size('enemy'));
check('the full stack orders attack recovery enemy and casting', w.recovery.y == w.attack.y + ah - 1
    and w.enemy.y == w.recovery.y + rh - 1 and w.enemycast.y == w.enemy.y + eh - 1
    and w.enemycast.width == w.attack.width);
w = capture(nil, true, true);
check('the idle stack has no overlap when attack is hidden', w.attack == nil and w.enemy.y == w.recovery.y + rh - 1
    and w.enemycast.y == w.enemy.y + eh - 1);
s.style.shared_spot, s.resting.width = true, 360;
w = capture('resting', true, true);
check('shared resting carries the whole attached stack', w.resting.width == w.enemycast.width
    and w.enemycast.y == w.enemy.y + eh - 1);
s.style.shared_spot = false;
MOCK.screen = { 400, 300 }; s.attack.x, s.attack.y = 380, 290;
w = capture('attack', true, true);
check('the full stack fits the bottom and right screen edges', w.attack.x >= 0 and w.attack.y >= 0
    and w.enemycast.x + w.enemycast.width <= 400 and w.enemycast.y + w.enemycast.height <= 300);
s.enemycast.show_value, s.enemycast.show_label, s.enemycast.show_spell = false, false, false;
capture('attack', true, true);
view.left, view.waiting = 0, true;
w, text = capture('attack', true, true);
check('the first waiting frame reserves its forced header in the full stack', text:find('waiting', 1, true)
    and w.enemycast.y + w.enemycast.height <= 300 and w.enemycast.y == w.enemy.y + select(2, hud.element_size('enemy')) - 1);
s.enemycast.show_value, s.enemycast.show_label, s.enemycast.show_spell = true, true, true;
view.left, view.waiting = 2, false;
MOCK.screen = { 1000, 700 };
s.enemy.enabled = false;
w = capture(nil, false, false);
check('turning the enemy host off restores the saved standalone layout', w.enemycast.x == 500 and w.enemycast.y == 300
    and s.enemycast.width == 240 and s.enemycast.x == 500);
s.enemy.enabled, s.enemy.attached, s.enemycast.attached = true, false, false;
hud.set_movable(true);
capture(nil, false, false);
local drag, last_id, mouse = { active = true, started = false }, nil, { 100, 100 };
rawset(imgui, 'InvisibleButton', function(id) last_id = id; end);
rawset(imgui, 'IsItemActivated', function() return last_id == '##grip_corner_enemycast' and drag.active and not drag.started; end);
rawset(imgui, 'IsItemActive', function() return last_id == '##grip_corner_enemycast' and drag.active; end);
rawset(imgui, 'GetMousePos', function() return mouse[1], mouse[2]; end);
MOCK.mouse_down = true; capture(nil, false, false);
drag.started, mouse[1], mouse[2] = true, 140, 108; capture(nil, false, false);
drag.active, MOCK.mouse_down = false, false;
local changed, before;
w, text, changed, before = capture(nil, false, false);
check('the casting card supports two-axis Shift resize and undo', changed and before.enemycast.width == 240
    and s.enemycast.width == 280 and s.enemycast.height_scale > 1 and s.enemycast.bar_height == 5);
for _, name in ipairs({ 'InvisibleButton', 'IsItemActivated', 'IsItemActive', 'GetMousePos' }) do rawset(imgui, name, nil); end
hud.set_movable(false);
capture(nil, false, false);
local list = imgui.GetWindowDrawList();
for _, call in ipairs(MOCK.imgui_calls) do
    local method = call[1]:match('^dl:(.+)$');
    if (method) then rawset(list, method, list[method]); else rawset(imgui, call[1], imgui[call[1]]); end
end
local io_state, next_pos = { DisplaySize = { x = 1000, y = 700 } }, { 0, 0 };
rawset(imgui, 'GetIO', function() return io_state; end);
rawset(imgui, 'SetNextWindowPos', function(p) next_pos[1], next_pos[2] = p[1], p[2]; end);
rawset(imgui, 'SetNextWindowSize', function() end);
rawset(imgui, 'GetWindowPos', function() return next_pos[1], next_pos[2]; end);
if (jit) then jit.off(); end
for _ = 1, 20 do draw(nil, false, false); end
collectgarbage('collect'); collectgarbage('stop');
local allocated = collectgarbage('count');
for _ = 1, 100 do draw(nil, false, false); end
local bytes = (collectgarbage('count') - allocated) * 1024 / 100;
collectgarbage('restart');
check('the steady casting HUD reuses its frame tables', bytes < 16, ('%.1f bytes per frame'):format(bytes));
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
