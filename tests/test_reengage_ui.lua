-- The idle card always identifies its estimated cooldown and drops combat-only rows.
local out, failed = {}, 0;
local function check(name, condition, detail)
    out[#out + 1] = (condition and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not condition) then failed = failed + 1; end
end
addon.name = 'cadence';
local imgui, hud, defaults = require('imgui'), require('ui.hud'), require('ui.defaults');
local s = defaults.make();
MOCK.mouse = { -1, -1 };
check('older settings start with retention off', s.attack.linger_seconds == 0);
for _, case in ipairs({ { -3, 0 }, { 0, 0 }, { 1, 1 }, { 12, 1 }, { 4.9, 1 }, { 0.5, 1 }, { '5', 0 }, { 0 / 0, 0 } }) do
    s.attack.linger_seconds = case[1]; defaults.tidy(s);
    check('retention settings normalize to off or on for ' .. tostring(case[1]), s.attack.linger_seconds == case[2]);
end
s.style.text_shadow, s.style.text_outline = false, false;
s.attack.x, s.attack.y = 40, 40;
s.attack.show_tp, s.attack.show_tp_hits, s.attack.show_tp_time = true, true, true;
MOCK.measure = function(text, px) return math.ceil(#text * px * 0.53) + 2; end;
local view = { fill = 0.5, left = 2.01, duration = 4, unknown = false, elapsed = false, conservative = false };
local enemy = { fill = 0.5, left = 2, delay = 4, learned = true, name = 'Goblin', waiting = false };
local tp = { tp = 640, goal = 1000, rounds = 4, hits = 5, estimated = true, time_to_goal = 20 };
local function capture(draw, attached)
    hud.refresh(s);
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    hud.begin_frame(); hud.join_below(attached == true); draw(); hud.end_frame();
    MOCK.record_imgui = false;
    local texts, positions, windows = {}, {}, {};
    local next_pos, next_size;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'dl:AddText') then texts[#texts + 1] = call[6]; positions[call[6]] = call; end
        if (call[1] == 'SetNextWindowPos') then next_pos = call[2]; end
        if (call[1] == 'SetNextWindowSize') then next_size = call[2]; end
        if (call[1] == 'Begin') then windows[call[2]] = { x = next_pos[1], y = next_pos[2], width = next_size[1], height = next_size[2] }; end
    end
    return table.concat(texts, '|'), positions, windows;
end
local function draw() hud.draw_reengage(view); end;
local text, pos, windows = capture(draw);
check('cooldown identifies its context and rounds up estimated tenths', text == 'Re-engage|~2.1s', text);
local idle_height = select(2, hud.element_size('attack'));
capture(function() hud.draw_attack(0.5, 2, 4, true, tp, 'too far', 'spell', 'not facing'); end);
check('idle card omits the combat footer heights', select(2, hud.element_size('attack')) > idle_height);
text = capture(draw);
check('switching from combat leaves no TP delay range or hold text', text == 'Re-engage|~2.1s', text);
s.attack.show_label, s.attack.show_value, s.attack.show_delay, s.style.show_labels = false, false, false, false;
s.attack.numbers_only, s.attack.label_text = true, 'My custom attack';
text = capture(draw);
check('text only and hidden labels retain cooldown context', text == 'Re-engage|~2.1s', text);
local text_height = select(2, hud.element_size('attack'));
s.attack.numbers_only = false;
capture(draw);
check('text only removes only the bar and its gap', select(2, hud.element_size('attack')) > text_height);
view.unknown, view.left = true, nil;
text = capture(draw);
check('missing timing is explicit', text == 'Re-engage|Timing unknown', text);
view.unknown, view.left, view.elapsed, view.fill = false, 0, true, 1;
text = capture(draw);
check('expiry never claims an attack is ready', text == 'Re-engage|Estimate elapsed' and not text:lower():find('ready', 1, true), text);
s.attack.width, s.attack.height_scale, s.style.label_size = defaults.WIDTH[1], defaults.HEIGHT_SCALE[2], defaults.LABEL_SIZE[2];
text, pos = capture(draw);
local width = math.floor(s.attack.width * s.style.scale * s.style.font_size / 14 + 0.5);
local fit = true;
for _, call in pairs(pos) do
    if (MOCK.measure(call[6], call[3]) > width) then fit = false; end
end
check('minimum width and maximum height fit both full phrases', fit, text);
check('narrow cards put the estimate on its own row', pos['Estimate elapsed'][4][2] > pos['Re-engage'][4][2]);
s.enemy.enabled, s.enemy.attached = true, true;
text, pos, windows = capture(function() draw(); hud.draw_enemy(enemy); end, true);
local attack_window, enemy_window = windows['##cadence_attack'], windows['##cadence_enemy'];
local own_height = select(2, hud.element_size('attack'));
check('the attached strip follows the retained card height', enemy_window.y == attack_window.y + own_height - 1);
check('the attached strip shares width and stays inside the host', enemy_window.width == attack_window.width
    and enemy_window.y + enemy_window.height == attack_window.y + attack_window.height);
text = capture(function() hud.draw_attack(0.5, 2, 4, true, tp); end);
check('normal attack drawing restores its own rows and custom label setting', text:find('TP 640', 1, true)
    and not text:find('Re-engage', 1, true), text);
check('rendering never replaces the saved label', s.attack.label_text == 'My custom attack');

local window = require('ui.settings_window');
window.set_open(true); window.select_tab('Timers');
MOCK.imgui_calls, MOCK.record_imgui = {}, true;
s.attack.linger_seconds = 0;
window.draw(s, '1.3.0', false, false);
MOCK.record_imgui = false;
local checkbox, slider;
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'Checkbox' and call[2] == 'Show re-engage timer') then checkbox = call; end
    if (call[1] == 'SliderInt' and call[2] == 'Keep after combat') then slider = call; end
end
check('settings exposes the re-engage checkbox without a duration slider', checkbox ~= nil and slider == nil);
local old_checkbox = imgui.Checkbox;
rawset(imgui, 'Checkbox', function(label, value)
    if (label == 'Show re-engage timer') then value[1] = not value[1]; return true; end
    return old_checkbox(label, value);
end);
local change = window.draw(s, '1.3.0', false, false);
check('checking the option enables automatic visibility and records an undoable saved edit', s.attack.linger_seconds == 1
    and change.changed and change.edited and change.save and change.label == 'Show re-engage timer');
s.attack.linger_seconds = 7;
change = window.draw(s, '1.3.0', false, false);
check('unchecking a legacy enabled value turns the option off', s.attack.linger_seconds == 0
    and change.changed and change.save and change.label == 'Show re-engage timer');
rawset(imgui, 'Checkbox', old_checkbox);
check('settings search finds the new toggle and automatic behavior', window.search_tabs('re-engage').Timers
    and window.search_tabs('five seconds').Timers);

-- Warm the mock wrappers before measuring the HUD itself.
s.attack.width, s.attack.height_scale, s.style.label_size = 240, 1, 0;
view.left, view.elapsed, view.fill = 2.01, false, 0.5;
capture(function() draw(); hud.draw_enemy(enemy); end, true);
local list = imgui.GetWindowDrawList();
for _, call in ipairs(MOCK.imgui_calls) do
    local method = call[1]:match('^dl:(.+)$');
    if (method) then rawset(list, method, list[method]); else rawset(imgui, call[1], imgui[call[1]]); end
end
local io_state, next_pos = { DisplaySize = { x = 1600, y = 1200 } }, { 0, 0 };
rawset(imgui, 'GetIO', function() return io_state; end);
rawset(imgui, 'SetNextWindowPos', function(p) next_pos[1], next_pos[2] = p[1], p[2]; end);
rawset(imgui, 'SetNextWindowSize', function() end);
rawset(imgui, 'GetWindowPos', function() return next_pos[1], next_pos[2]; end);
local function steady()
    hud.begin_frame(); hud.join_below(true); draw(); hud.draw_enemy(enemy); hud.end_frame();
end
if (jit) then jit.off(); end
for _ = 1, 20 do steady(); end
collectgarbage('collect'); collectgarbage('stop');
local before = collectgarbage('count');
for _ = 1, 100 do steady(); end
local bytes = (collectgarbage('count') - before) * 1024 / 100;
collectgarbage('restart');
check('steady retained and attached cards reuse frame tables', bytes < 16, ('%.1f bytes per frame'):format(bytes));
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
