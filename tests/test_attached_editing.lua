-- Every visible part of an attached stack stays editable while Shift is held.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
addon.name = 'cadence';
local hud, imgui = require('ui.hud'), require('imgui');
local s = require('ui.defaults').make();
s.style.text_shadow, s.style.text_outline, s.style.layout_guides = false, false, false;
s.attack.x, s.attack.y, s.attack.width = 30, 40, 300;
s.enemy.x, s.enemy.y, s.enemy.width, s.enemy.enabled, s.enemy.attached = 60, 80, 240, true, true;
s.recovery.x, s.recovery.y, s.recovery.enabled, s.recovery.attached = 450, 120, true, true;
s.enemycast.x, s.enemycast.y, s.enemycast.enabled, s.enemycast.attached = 500, 320, true, true;
MOCK.screen, MOCK.mouse = { 1000, 700 }, { -1, -1 };
local recovery = { fill = 0.5, left = 1.5, duration = 2.5, kind = 'spell', estimated = true };
local enemy = { fill = 0.5, left = 2, delay = 4, learned = true, name = 'Goblin' };
local cast = { fill = 0.5, left = 2, duration = 4, spell = 'Fire', waiting = false };
local rest = { fill = 0.5, left = 5, flash = 0 };
local movable, active, activated, last_id, mouse_x, mouse_y = true, nil, false, nil, 100, 100;
rawset(imgui, 'InvisibleButton', function(id) last_id = id; end);
rawset(imgui, 'IsItemActivated', function() return last_id == active and activated; end);
rawset(imgui, 'IsItemActive', function() return last_id == active; end);
rawset(imgui, 'GetMousePos', function() return mouse_x, mouse_y; end);
local function frame(host, with_recovery)
    hud.refresh(s); hud.set_movable(movable);
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    hud.begin_frame(with_recovery and recovery or nil, cast);
    hud.join_below(s.enemy.attached and s.attack.enabled, with_recovery and s.recovery.attached and s.attack.enabled,
        s.enemycast.attached and s.enemy.enabled);
    if (host == 'attack') then hud.draw_attack(0.5, 2, 4, true);
    elseif (host == 'resting') then hud.draw_resting(rest); end
    if (with_recovery) then hud.draw_recovery(recovery); end
    hud.draw_enemy(enemy); hud.draw_enemycast(cast);
    local changed, before = hud.end_frame();
    MOCK.record_imgui = false;
    local windows, pos, size, condition = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'SetNextWindowPos') then pos, condition = call[2], call[3]; end
        if (call[1] == 'SetNextWindowSize') then size = call[2]; end
        if (call[1] == 'Begin') then
            windows[call[2]:sub(11)] = { x = pos[1], y = pos[2], width = size[1], height = size[2], flags = call[4], condition = condition };
        end
    end
    return windows, changed, before;
end
local function start(id, host, with_recovery)
    active, activated, MOCK.mouse_down, mouse_x, mouse_y = id, true, true, 100, 100;
    frame(host, with_recovery); activated = false;
end
local function finish(host, with_recovery)
    active, MOCK.mouse_down = nil, false;
    return frame(host, with_recovery);
end
local w = frame(nil, false);
check('the idle enemy provides a movable host for its cast strip', bit.band(w.enemy.flags, ImGuiWindowFlags_NoInputs) == 0
    and bit.band(w.enemycast.flags, ImGuiWindowFlags_NoInputs) == 0
    and w.enemy.height == select(2, hud.element_size('enemy')));
local old_x, old_y = s.attack.x, s.attack.y;
start('##move_enemycast', nil, false); mouse_x, mouse_y = 122, 118; frame(nil, false);
local changed, before;
w, changed, before = finish(nil, false);
check('dragging the idle cast strip moves the shared attack anchor once', changed and s.attack.x == old_x + 22
    and s.attack.y == old_y + 18 and before.attack.x == old_x and before.attack.y == old_y
    and s.enemycast.x == 500 and s.enemycast.y == 320);
local _, repeat_change = frame(nil, false);
check('a finished child drag is not saved again', not repeat_change);
for _, key in ipairs({ 'recovery', 'enemy', 'enemycast' }) do
    local old = s[key].height_scale;
    local attack_height, attack_width = s.attack.height_scale, s.attack.width;
    start('##grip_height_' .. key, 'attack', true); mouse_y = 108; frame('attack', true);
    w, changed, before = finish('attack', true);
    check(key .. ' resizes its own attached height and records one undo', changed and s[key].height_scale > old
        and before[key].height_scale == old and s.attack.height_scale == attack_height and s.attack.width == attack_width);
end
old_x, old_y = s.attack.x, s.attack.y;
start('##move_recovery', 'attack', true); mouse_x, mouse_y = 111, 109; frame('attack', true);
w = frame('attack', true);
check('the host follows a held child drag before release', w.attack.condition == ImGuiCond_Always);
finish('attack', true);
check('dragging a pinned recovery strip moves the whole visible stack', s.attack.x == old_x + 11 and s.attack.y == old_y + 9
    and s.recovery.x == 450 and s.recovery.y == 120);
s.style.shared_spot = true;
old_x, old_y = s.attack.x, s.attack.y;
start('##move_enemy', 'resting', true); mouse_x, mouse_y = 107, 112; frame('resting', true); finish('resting', true);
check('a child drag follows the shared resting host', s.attack.x == old_x + 7 and s.attack.y == old_y + 12);
s.style.shared_spot, s.attack.enabled = false, false;
w = frame(nil, false);
check('a disabled attack host restores the enemy full card and own width', w.enemy.width == s.enemy.width + 22
    and w.enemy.height == select(2, hud.element_size('enemy')));
old_x, old_y = s.enemy.x, s.enemy.y;
local saved_attack_x = s.attack.x;
start('##move_enemycast', nil, false); mouse_x, mouse_y = 109, 114; frame(nil, false); finish(nil, false);
check('dragging casting with attack off moves only its enemy host', s.enemy.x == old_x + 9 and s.enemy.y == old_y + 14
    and s.attack.x == saved_attack_x and s.enemycast.x == 500);
s.style.locked = true;
w = frame(nil, false);
check('locked attached windows pass clicks through', bit.band(w.enemy.flags, ImGuiWindowFlags_NoInputs) ~= 0
    and bit.band(w.enemycast.flags, ImGuiWindowFlags_NoInputs) ~= 0);
s.style.locked, movable = false, false;
w = frame(nil, false);
check('ordinary gameplay keeps every attached window click-through', bit.band(w.enemy.flags, ImGuiWindowFlags_NoInputs) ~= 0
    and bit.band(w.enemycast.flags, ImGuiWindowFlags_NoInputs) ~= 0);
movable, s.attack.enabled = true, true;
MOCK.screen, s.attack.x, s.attack.y = { 400, 300 }, 390, 290;
w = frame(nil, false);
check('an idle joined stack stays inside the screen', w.enemy.x >= 0 and w.enemy.y >= 0
    and w.enemycast.x + w.enemycast.width <= 400 and w.enemycast.y + w.enemycast.height <= 300);
start('##move_enemycast', nil, false);
local drawn_x = w.enemy.x;
mouse_x = 90; frame(nil, false); finish(nil, false);
check('dragging a clamped stack starts from its visible anchor', s.attack.x == drawn_x - 10);
check('attached editing sends no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
