-- The separate recovery card stays estimated and shares the normal layout controls.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
addon.name = 'cadence';
local imgui, defaults, hud = require('imgui'), require('ui.defaults'), require('ui.hud');
local history, presets, preview = require('ui.history'), require('ui.presets'), require('ui.preview');
local window, tips = require('ui.settings_window'), require('ui.tips');
local s = defaults.make();
check('the timer starts off and unattached with independent colors', not s.recovery.enabled and not s.recovery.attached
    and s.recovery.fill_start ~= s.attack.fill_start and s.recovery.fill_end ~= s.attack.fill_end);
local old_attack = s.attack;
s.recovery = nil;
defaults.tidy(s);
check('older settings gain the optional timer without replacing attack settings', not s.recovery.enabled and s.attack == old_attack);
s.recovery.attached = nil;
defaults.tidy(s);
check('older recovery settings keep their independent layout', s.recovery.attached == false);
s.recovery.width, s.recovery.height_scale, s.recovery.label_text = 900, 9, 'Recovery\n' .. string.rep('x', 30);
defaults.tidy(s);
check('recovery geometry and label use the normal settings limits', s.recovery.width == 640
    and s.recovery.height_scale == 2.5 and #s.recovery.label_text == 23 and not s.recovery.label_text:find('\n'));
s = defaults.make();
s.recovery.x, s.recovery.y = 20, 90;
s.attack.x, s.attack.y = 400, 400;
s.style.shared_spot = true;
s.style.text_shadow, s.style.text_outline = false, false;
MOCK.mouse = { -1, -1 };
local view = { fill = 0.4, left = 1.01, duration = 2.5, kind = 'spell', estimated = true };
local function capture(fn)
    hud.refresh(s);
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    hud.begin_frame(); hud.join_below(false); fn(); hud.end_frame({ recovery = view });
    MOCK.record_imgui = false;
    local text, windows, next_pos = {}, {}, nil;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'dl:AddText') then text[#text + 1] = call[6]; end
        if (call[1] == 'SetNextWindowPos') then next_pos = call[2]; end
        if (call[1] == 'Begin') then windows[call[2]] = next_pos; end
    end
    return table.concat(text, '|'), windows;
end
local text, windows = capture(function() hud.draw_recovery(view); end);
check('the live card identifies its action and rounds estimated tenths up', text == '~1.1s|ACTION RECOVERY|Spell', text);
check('recovery keeps its own position with shared attack/resting placement', windows['##cadence_recovery'][1] == 20
    and windows['##cadence_recovery'][2] == 90 and windows['##cadence_attack'] == nil);
view.kind = 'weaponskill';
text = capture(function() hud.draw_recovery(view); end);
check('weapon skill recovery names its source', text:find('Weapon skill', 1, true) ~= nil, text);
s.recovery.show_source, s.recovery.show_label = false, false;
s.recovery.numbers_only = true;
text = capture(function() hud.draw_recovery(view); end);
check('text-only recovery keeps the estimate without combat readouts', text == '~1.1s', text);
view.left = 0;
text, windows = capture(function() hud.draw_recovery(view); end);
check('an expired view draws no card or ready claim', text == '' and windows['##cadence_recovery'] == nil);
text = capture(function() hud.draw_recovery(nil); end);
check('a missing view draws nothing', text == '');
view.left = 1.01;
local explanation = tips.text('recovery');
check('hover explains supported actions and unknown timing without a countdown claim', explanation:find('completed spells, weapon skills, job abilities, items and ranged attacks', 1, true)
    and explanation:find('Individual recasts', 1, true) and explanation:find('not a recovery countdown', 1, true));
MOCK.mouse = { s.recovery.x + 1, s.recovery.y + 1 };
hud.begin_frame(); hud.draw_recovery(view);
check('recovery hover does not request a loadout or timing snapshot', not hud.needs_details());
hud.end_frame();
MOCK.now = MOCK.now + 0.3;
MOCK.imgui_calls, MOCK.record_imgui = {}, true;
hud.begin_frame(); hud.draw_recovery(view); hud.end_frame();
MOCK.record_imgui = false;
local static_tip = false;
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'TextUnformatted' and call[2] == explanation) then static_tip = true; end
end
check('the hover explanation still draws without a snapshot', static_tip);
MOCK.mouse = { -1, -1 };

s.recovery.enabled, s.recovery.width, s.recovery.height_scale, s.recovery.attached = true, 311, 1.4, true;
for _, name in ipairs(presets.NAMES) do
    presets.apply(s, name);
    check(name .. ' styles the new card without changing its geometry', presets.current(s) == name
        and s.recovery.enabled and s.recovery.width == 311 and s.recovery.height_scale == 1.4 and s.recovery.attached
        and s.recovery.fill_start ~= s.attack.fill_start);
end
s.recovery.label_text = 'Recovery';
local x, y = s.recovery.x, s.recovery.y;
history.reset_section(s, 'recovery');
check('recovery reset preserves its position and label', not s.recovery.enabled and not s.recovery.attached and s.recovery.width == 240
    and s.recovery.x == x and s.recovery.y == y and s.recovery.label_text == 'Recovery');
history.undo(s);
check('recovery reset has one normal undo', s.recovery.enabled and s.recovery.attached and s.recovery.width == 311 and s.recovery.height_scale == 1.4);
history.reset_section(s, 'timers');
check('Timers reset includes action recovery', not s.recovery.enabled and not s.recovery.attached and s.recovery.height_scale == 1);

local profiles, profile_settings = require('ui.profiles'), defaults.make();
profile_settings.recovery.attached, profile_settings.recovery.width, profile_settings.recovery.height_scale = true, 311, 1.4;
check('a profile saves recovery attachment', profiles.save(profile_settings, 'Attached recovery'));
profile_settings.recovery.attached, profile_settings.recovery.width = false, 420;
check('a profile restores attachment and independent dimensions', profiles.load(profile_settings, 'Attached recovery')
    and profile_settings.recovery.attached and profile_settings.recovery.width == 311 and profile_settings.recovery.height_scale == 1.4);

window.set_open(true); window.select_tab('Timers');
MOCK.imgui_calls, MOCK.record_imgui = {}, true;
window.draw(s, '1.3.0', false, false);
MOCK.record_imgui = false;
local toggle, width, source, fold, attach = false, false, false, false, false;
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'Button' and call[2] == 'OFF##recovery') then toggle = true; end
    if (call[1] == 'SliderInt' and call[2] == 'Width##recovery') then width = true; end
    if (call[1] == 'Checkbox' and call[2] == 'Action source##recovery') then source = true; end
    if (call[1] == 'Checkbox' and call[2] == 'Attach under auto attack##recovery') then attach = true; end
    if (call[1] == 'CollapsingHeader' and call[2] == 'Recovery options##section') then fold = true; end
end
check('Timers exposes the recovery toggle and folded display controls', toggle and width and source and fold and attach);
check('search finds recovery timing and custom labels', window.search_tabs('action recovery').Timers
    and window.search_tabs('Unavailable timing').Timers and window.search_tabs('recovery label').Appearance
    and window.search_tabs('attached enemy timer').Timers);

local function recovery_slider_locks()
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    window.draw(s, '1.4.0', false, false);
    MOCK.record_imgui = false;
    local stack, disabled, sliders = {}, false, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'BeginDisabled') then stack[#stack + 1], disabled = disabled, disabled or call[2] == true;
        elseif (call[1] == 'EndDisabled') then disabled = table.remove(stack);
        elseif ((call[1] == 'SliderInt' or call[1] == 'SliderFloat') and call[2]:find('##recovery', 1, true)) then
            sliders[call[2]] = disabled;
        end
    end
    return sliders;
end
s.recovery.attached, s.attack.enabled = true, true;
local locks = recovery_slider_locks();
check('attachment follows host width while height and bar thickness stay editable', locks['Width##recovery'] == true
    and locks['Height##recovery'] == false and locks['Bar height##recovery'] == false);
s.attack.enabled = false;
locks = recovery_slider_locks();
check('width is editable when the auto attack timer is disabled', locks['Width##recovery'] == false);
s.recovery.attached, s.attack.enabled = false, true;
locks = recovery_slider_locks();
check('width is editable for the separate recovery card', locks['Width##recovery'] == false);

s.attack.enabled, s.resting.enabled, s.enemy.enabled, s.recovery.enabled = false, false, false, true;
s.recovery.show_value, s.recovery.show_source = true, true;
for _, state in ipairs({ 'normal', 'blocked', 'waiting', 'full' }) do
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    preview.draw(s, state, true);
    MOCK.record_imgui = false;
    local words = {};
    for _, call in ipairs(MOCK.imgui_calls) do if (call[1] == 'dl:AddText') then words[#words + 1] = call[6]; end end
    local shown = table.concat(words, '|');
    check(state .. ' sample remains a recovery estimate', shown:find('~1.5s', 1, true)
        and not shown:find('ready', 1, true), shown);
end

s.recovery.width, s.recovery.height_scale, s.recovery.bar_height = 240, 1, 5;
s.recovery.numbers_only, s.style.layout_guides = false, false;
hud.refresh(s); hud.set_movable(true);
local drag, last_id, mouse = { active = true, started = false }, nil, { 100, 100 };
rawset(imgui, 'InvisibleButton', function(id) last_id = id; end);
rawset(imgui, 'IsItemActivated', function() return last_id == '##grip_corner_recovery' and drag.active and not drag.started; end);
rawset(imgui, 'IsItemActive', function() return last_id == '##grip_corner_recovery' and drag.active; end);
rawset(imgui, 'GetMousePos', function() return mouse[1], mouse[2]; end);
local function frame()
    hud.begin_frame(); hud.join_below(false); hud.draw_recovery(view); return hud.end_frame();
end
local original_height = select(2, hud.element_size('recovery'));
MOCK.mouse_down = true;
frame();
drag.started, mouse[1], mouse[2] = true, 140, 108;
frame();
drag.active, MOCK.mouse_down = false, false;
local changed, before = frame();
check('Shift corner resizing changes width and whole height', s.recovery.width == 280 and s.recovery.bar_height == 5
    and math.abs(select(2, hud.element_size('recovery')) - original_height - 8) <= 2);
check('recovery gestures preserve a snapshot for layout undo', changed and before.recovery.width == 240 and before.recovery.height_scale == 1);
for _, name in ipairs({ 'InvisibleButton', 'IsItemActivated', 'IsItemActive', 'GetMousePos' }) do rawset(imgui, name, nil); end
hud.set_movable(false);

capture(function() hud.draw_recovery(view); end);
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
if (jit) then jit.off(); end
for _ = 1, 20 do frame(); end
collectgarbage('collect'); collectgarbage('stop');
local allocated = collectgarbage('count');
for _ = 1, 100 do frame(); end
local bytes = (collectgarbage('count') - allocated) * 1024 / 100;
collectgarbage('restart');
check('the steady recovery HUD reuses its frame tables', bytes < 16, ('%.1f bytes per frame'):format(bytes));
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
