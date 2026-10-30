-- Hiding a grabbed timer ends its mouse hold without discarding movement or Undo.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
addon.name = 'cadence';
local hud, imgui, defaults, history = require('ui.hud'), require('imgui'), require('ui.defaults'), require('ui.history');
local s, lines, active, activated, item, mouse_x, mouse_y, current_window, clicked_window;
local draw_list = { AddLine = function() lines = lines + 1; end };
rawset(imgui, 'GetForegroundDrawList', function() return draw_list; end);
rawset(imgui, 'InvisibleButton', function(id) item = id; end);
rawset(imgui, 'IsItemActivated', function() return item == active and activated; end);
rawset(imgui, 'IsItemActive', function() return item == active; end);
rawset(imgui, 'GetMousePos', function() return mouse_x, mouse_y; end);
rawset(imgui, 'IsMouseClicked', function() return clicked_window ~= nil; end);
rawset(imgui, 'IsWindowHovered', function() return current_window == clicked_window; end);
local begin = imgui.Begin;
rawset(imgui, 'Begin', function(name, ...) current_window = name; return begin(name, ...); end);
local recovery = { fill = 0.5, left = 1.5, duration = 2.5, kind = 'spell' };
local resting = { fill = 0.5, left = 5, gained_hp = 0, gained_mp = 0, flash = 0 };
local function reset()
    MOCK.mouse_down, MOCK.screen = false, { 1000, 700 };
    MOCK.window_pos['##cadence_attack'] = nil;
    s = defaults.make();
    s.style.layout_guides, s.style.text_shadow, s.style.text_outline = true, false, false;
    s.attack.x, s.attack.y, s.attack.width = 30, 40, 300;
    s.resting.x, s.resting.y = 700, 400;
    s.recovery.enabled, s.recovery.attached = true, true;
    active, activated, item, mouse_x, mouse_y, clicked_window = nil, false, nil, 100, 100, nil;
    hud.refresh(s);
end
local function frame(attack, recover, rest)
    lines, MOCK.imgui_calls, MOCK.record_imgui = 0, {}, true;
    hud.set_movable(true); hud.begin_frame(recover and recovery or nil); hud.join_below(false, recover, false);
    if (attack) then hud.draw_attack(0.5, 2, 4, true); end
    if (recover) then hud.draw_recovery(recovery); end
    if (rest) then hud.draw_resting(resting); end
    local changed, before = hud.end_frame();
    MOCK.record_imgui = false;
    return changed, before;
end
local function start(id)
    MOCK.mouse_down, active, activated = true, id, true;
    frame(true, true); activated = false;
end
local function click_through()
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'Begin' and bit.band(call[4], ImGuiWindowFlags_NoInputs) == 0) then return false; end
    end
    return true;
end
for _, another_visible in ipairs({ false, true }) do
    reset(); frame(true, true, another_visible); start('##move_recovery');
    mouse_x = 570; frame(true, true, another_visible);
    check('an attached drag reaches its guide before hiding', s.attack.x == 500 and lines > 0);
    local completed_x = s.attack.x;
    local changed = frame(false, false, another_visible);
    check(another_visible and 'another visible timer does not retain the hidden drag guide' or 'hiding every timer clears its drag guide',
        lines == 0 and not changed and s.attack.x == completed_x);
    mouse_x, mouse_y = 800, 350;
    frame(true, true, another_visible);
    check('returning before mouse release cannot resume the old attached drag', s.attack.x == completed_x and s.attack.y == 40
        and lines == 0 and click_through());
    MOCK.mouse_down, active = false, nil;
    local before;
    changed, before = frame(false, false, another_visible);
    check('release while hidden saves completed movement with its original Undo snapshot', changed and before.attack.x == 30
        and before.attack.y == 40 and s.attack.x == completed_x);
    history.record_patch(s, before, 'Move or resize timers');
    check('the interrupted hold emits no second save', not frame(true, true, another_visible));
    history.undo(s);
    check('Undo restores the movement made before hiding', s.attack.x == 30 and s.attack.y == 40);
end
reset(); frame(true, true); start('##grip_height_recovery'); mouse_y = 110; frame(true, true);
local completed_height = s.recovery.height_scale;
frame(false, false); mouse_y = 220; frame(true, true);
check('a hidden resize cannot resume from the old mouse origin', completed_height > 1 and s.recovery.height_scale == completed_height);
MOCK.mouse_down, active = false, nil;
local changed, before = frame(true, true);
check('the completed part of a hidden resize has one Undo snapshot', changed and before.recovery.height_scale == 1);
reset(); frame(true, false);
MOCK.mouse_down, MOCK.window_pos['##cadence_attack'] = true, { 500, 40 };
frame(true, false); MOCK.window_pos['##cadence_attack'] = nil;
frame(false, false, true); MOCK.window_pos['##cadence_attack'] = { 650, 170 };
frame(true, false, true);
check('a hidden standalone drag cannot resume while another timer remains', s.attack.x == 500 and s.attack.y == 40 and lines == 0);
MOCK.mouse_down, MOCK.window_pos['##cadence_attack'] = false, nil;
changed, before = frame(true, false);
check('a standalone drag retains its initial Undo snapshot', changed and before.attack.x == 30);
reset(); frame(true, false);
MOCK.mouse_down, clicked_window = true, '##cadence_attack'; frame(true, false); clicked_window = nil;
frame(false, false); MOCK.window_pos['##cadence_attack'] = { 650, 170 }; frame(true, false);
check('a timer hidden after click but before movement cannot jump on return', s.attack.x == 30 and s.attack.y == 40);
MOCK.mouse_down, MOCK.window_pos['##cadence_attack'] = false, nil;
check('an interrupted click without movement has no save or Undo', not frame(true, false));
start('##move_recovery'); mouse_x = 120; frame(true, true);
check('a fresh click after release can move the timer normally', s.attack.x == 50);
MOCK.mouse_down, active = false, nil; frame(true, true);

-- Exercise the real render callback's early exits, not only a HUD frame with no cards.
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
s = MOCK.settings.current;
s.recovery.enabled, s.recovery.attached = true, true;
s.enemy.enabled, s.enemycast.enabled, s.resting.enabled = false, false, false;
s.style.layout_guides, s.style.text_shadow, s.style.text_outline = false, false, false;
local window = require('ui.settings_window');
local draw_window = window.draw;
window.draw = function() return {}; end;
MOCK.key_shift, MOCK.player.status = true, 0;
local function main_frame()
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
end
local function hide(reason, on)
    if (reason == 'map') then MOCK.menu_name = on and 'map0' or nil;
    elseif (reason == 'event') then MOCK.in_event = on;
    elseif (reason == 'game UI') then MOCK.ui_hidden = on;
    elseif (reason == 'missing player') then MOCK.zoning = on;
    elseif (reason == 'no visible timers') then window.set_open(not on); end
end
for _, reason in ipairs({ 'map', 'event', 'game UI', 'missing player', 'no visible timers' }) do
    for _, release_hidden in ipairs({ false, true }) do
        MOCK.mouse_down, active, activated, mouse_x, mouse_y = false, nil, false, 100, 100;
        s.attack.x, s.attack.y = 30, 40;
        hud.cancel_layout_gesture(); hud.refresh(s); window.set_open(true); main_frame();
        local saves = MOCK.saved;
        MOCK.mouse_down, active, activated = true, '##move_recovery', true;
        main_frame(); activated = false; mouse_x = 120; main_frame();
        check(reason .. ': the attached card moves before hiding', s.attack.x == 50 and MOCK.saved == saves);
        hide(reason, true); main_frame();
        if (release_hidden) then
            MOCK.mouse_down, active = false, nil; main_frame();
            check(reason .. ': release while hidden saves once', MOCK.saved == saves + 1);
            hide(reason, false); main_frame();
        else
            mouse_x, mouse_y = 350, 240; hide(reason, false); main_frame();
            check(reason .. ': returning while held cannot resume the drag', s.attack.x == 50 and s.attack.y == 40 and click_through());
            MOCK.mouse_down, active = false, nil; main_frame();
        end
        main_frame();
        check(reason .. ': only one save and original Undo survive', MOCK.saved == saves + 1
            and history.undo(s) and s.attack.x == 30 and s.attack.y == 40);
    end
end
window.draw = draw_window;
local drawing_error = false;
for _, line in ipairs(MOCK.printed) do drawing_error = drawing_error or line:find('Drawing stopped', 1, true) ~= nil; end
check('early-return gesture cleanup raises no drawing error', not drawing_error);
check('hidden gesture handling sends no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
