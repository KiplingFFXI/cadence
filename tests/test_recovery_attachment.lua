-- Attached recovery shares the attack stack without changing its saved standalone layout.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
addon.name = 'cadence';
local imgui, hud = require('imgui'), require('ui.hud');
local s = require('ui.defaults').make();
s.attack.x, s.attack.y, s.attack.width = 80, 50, 300;
s.recovery.x, s.recovery.y, s.recovery.width = 450, 200, 190;
s.recovery.enabled, s.recovery.attached = true, true;
s.enemy.enabled, s.enemy.attached = true, true;
s.style.text_shadow, s.style.text_outline, s.style.layout_guides = false, false, false;
MOCK.screen, MOCK.mouse = { 1000, 700 }, { -1, -1 };
local recovery = { fill = 0.5, left = 1.5, duration = 2.5, kind = 'spell', estimated = true };
local enemy = { fill = 0.5, left = 2, delay = 4, learned = true, name = 'Goblin', waiting = false };
local resting = { fill = 0.5, left = 5, flash = 0 };
local retained = { fill = 0.5, left = 2, duration = 4 };
local function draw(host, show_recovery, show_enemy)
    hud.begin_frame();
    hud.join_below(show_enemy and s.enemy.attached and s.attack.enabled,
        show_recovery and s.recovery.attached and s.attack.enabled);
    if (host == 'attack') then hud.draw_attack(0.5, 2, 4, true);
    elseif (host == 'resting') then hud.draw_resting(resting);
    elseif (host == 'retained') then hud.draw_reengage(retained); end
    if (show_recovery) then hud.draw_recovery(recovery); end
    if (show_enemy) then hud.draw_enemy(enemy); end
    return hud.end_frame();
end
local function capture(host, show_recovery, show_enemy)
    hud.refresh(s);
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    local changed, before = draw(host, show_recovery, show_enemy);
    MOCK.record_imgui = false;
    local windows, next_pos, next_size = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'SetNextWindowPos') then next_pos = call[2]; end
        if (call[1] == 'SetNextWindowSize') then next_size = call[2]; end
        if (call[1] == 'Begin') then
            windows[call[2]:sub(11)] = { x = next_pos[1], y = next_pos[2], width = next_size[1], height = next_size[2], flags = call[4] };
        end
    end
    return windows, changed, before;
end
local function fits(w)
    return w.x >= 0 and w.y >= 0 and w.x + w.width <= MOCK.screen[1] and w.y + w.height <= MOCK.screen[2];
end
local function preserved()
    return s.recovery.x == 450 and s.recovery.y == 200 and s.recovery.width == 190;
end
local w = capture('attack', true, true);
local _, ah = hud.element_size('attack');
local _, rh = hud.element_size('recovery');
local _, eh = hud.element_size('enemy');
check('the three cards share a width and touch only at their borders', w.attack.width == w.recovery.width
    and w.recovery.width == w.enemy.width and w.recovery.y == w.attack.y + ah - 1
    and w.enemy.y == w.recovery.y + rh - 1);
check('the host hitbox covers both strips', w.attack.height == ah + rh + eh - 2);
check('attachment leaves standalone position and width unchanged', preserved());
check('attached strips stay click-through under a visible host', bit.band(w.recovery.flags, ImGuiWindowFlags_NoInputs) ~= 0);

local before_y = w.enemy.y;
w = capture('attack', false, true);
check('expired recovery leaves no extra gap or host hitbox', w.recovery == nil and w.enemy.y == before_y - rh + 1
    and w.attack.height == ah + eh - 1);
w = capture(nil, true, true);
check('idle recovery remains below the saved attack anchor with enemy below it', w.attack == nil
    and w.recovery.x == s.attack.x and w.recovery.y == s.attack.y + ah - 1
    and w.enemy.y == w.recovery.y + rh - 1);
w = capture(nil, true, false);
check('an idle recovery-only window has no invisible host-sized hitbox', w.attack == nil and w.recovery.height == rh);
MOCK.mouse = { w.recovery.x + 2, w.recovery.y + 2 };
hud.begin_frame(); hud.join_below(false, true); hud.draw_recovery(recovery);
check('idle recovery hover still avoids timing snapshots', not hud.needs_details()); hud.end_frame();
w = capture(nil, true, true);
MOCK.mouse = { w.enemy.x + 2, w.enemy.y + 2 };
hud.begin_frame(); hud.join_below(true, true); hud.draw_recovery(recovery); hud.draw_enemy(enemy);
check('enemy hover wins over the recovery host hitbox', hud.needs_details()); hud.end_frame();
MOCK.mouse = { -1, -1 };

s.style.shared_spot, s.resting.width = true, 360;
w = capture('resting', true, true);
local _, resting_height = hud.element_size('resting');
check('shared resting carries both strips at its own width', w.resting.width == w.recovery.width
    and w.enemy.width == w.resting.width and w.recovery.y == w.resting.y + resting_height - 1
    and w.enemy.y == w.recovery.y + rh - 1);
w = capture('retained', true, true);
check('re-engage uses its actual compact host height', w.recovery.y == w.attack.y + select(2, hud.element_size('attack')) - 1);
s.style.shared_spot = false;

MOCK.screen = { 400, 250 };
s.attack.x, s.attack.y = 380, 240;
w = capture('attack', true, true);
check('the complete visible stack is clamped inside a small screen', fits(w.attack) and fits(w.recovery) and fits(w.enemy)
    and w.enemy.y + w.enemy.height == MOCK.screen[2]);
local live_top = w.attack.y;
w = capture('attack', false, true);
check('expired recovery does not reserve bottom-edge clamp space', w.attack.y == live_top + rh - 1);
w = capture(nil, true, true);
check('an idle stack is clamped together', fits(w.recovery) and fits(w.enemy) and w.enemy.y + w.enemy.height == MOCK.screen[2]);
check('clamping does not rewrite either saved layout', s.attack.x == 380 and s.attack.y == 240 and preserved());

MOCK.screen = { 1000, 700 };
s.attack.enabled = false;
w = capture(nil, true, false);
check('disabling attack restores the full standalone recovery card', w.recovery.x == 450 and w.recovery.y == 200
    and w.recovery.width == select(1, hud.element_size('recovery')) and w.recovery.width < 300 and w.recovery.height > rh);
s.attack.enabled, s.recovery.attached = true, false;
w = capture('attack', true, true);
check('detaching restores the saved independent position and width', w.recovery.x == 450 and w.recovery.y == 200
    and w.recovery.width < w.attack.width and preserved());

s.recovery.attached = true;
s.attack.x, s.attack.y = 80, 50;
hud.set_movable(true);
w = capture(nil, true, false);
check('Shift can move an idle attached recovery strip', bit.band(w.recovery.flags, ImGuiWindowFlags_NoInputs) == 0);
MOCK.mouse_down = true;
MOCK.window_pos['##cadence_recovery'] = { 105, w.recovery.y + 16 };
capture(nil, true, false);
check('dragging idle recovery moves the attack anchor by the actual delta', s.attack.x == 105 and s.attack.y == 66 and preserved());
MOCK.mouse_down = false;
MOCK.window_pos['##cadence_recovery'] = nil;
local changed, before;
w, changed, before = capture(nil, true, false);
check('the idle drag has one undo snapshot of the original anchor', changed and before.attack.x == 80 and before.attack.y == 50
    and before.recovery.x == 450 and before.recovery.width == 190);
local _, again = capture(nil, true, false);
check('an unchanged frame does not save the drag again', not again);
MOCK.mouse_down = true;
MOCK.window_pos['##cadence_recovery'] = { w.recovery.x, w.recovery.y };
s.recovery.attached = false;
capture(nil, true, false);
check('detaching during a held drag does not overwrite the standalone layout', preserved());
MOCK.mouse_down = false;
MOCK.window_pos['##cadence_recovery'] = nil;
w, changed = capture(nil, true, false);
check('the detached card returns to its saved position without another save', w.recovery.x == 450 and w.recovery.y == 200 and not changed);
s.recovery.attached = true;
capture(nil, true, false);

local drag, last_id, mouse = { active = true, started = false }, nil, { 100, 100 };
rawset(imgui, 'InvisibleButton', function(id) last_id = id; end);
rawset(imgui, 'IsItemActivated', function() return last_id == '##grip_height_recovery' and drag.active and not drag.started; end);
rawset(imgui, 'IsItemActive', function() return last_id == '##grip_height_recovery' and drag.active; end);
rawset(imgui, 'GetMousePos', function() return mouse[1], mouse[2]; end);
MOCK.mouse_down = true;
capture(nil, true, false);
drag.started, mouse[2] = true, 108;
capture(nil, true, false);
drag.active, MOCK.mouse_down = false, false;
w, changed, before = capture(nil, true, false);
check('idle strip height resizing preserves inherited and standalone widths', changed and s.recovery.height_scale > 1
    and before.recovery.height_scale == 1 and s.attack.width == 300 and preserved());
for _, name in ipairs({ 'InvisibleButton', 'IsItemActivated', 'IsItemActive', 'GetMousePos' }) do rawset(imgui, name, nil); end
hud.set_movable(false);

capture('attack', true, true);
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
for _ = 1, 20 do draw('attack', true, true); end
collectgarbage('collect'); collectgarbage('stop');
local allocated = collectgarbage('count');
for _ = 1, 100 do draw('attack', true, true); end
local bytes = (collectgarbage('count') - allocated) * 1024 / 100;
collectgarbage('restart');
check('the steady attached stack reuses its frame tables', bytes < 16, ('%.1f bytes per frame'):format(bytes));
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
