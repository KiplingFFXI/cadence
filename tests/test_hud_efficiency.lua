-- Steady timer drawing should reuse its hit-test records, including an attached enemy strip.
local out, failed = {}, 0;
local function check(name, yes, bytes)
    out[#out + 1] = (yes and 'ok   ' or 'FAIL ') .. name .. (' (%.1f bytes per frame)'):format(bytes);
    if (not yes) then failed = failed + 1; end
end
addon.name = 'cadence';
local imgui, hud = require('imgui'), require('ui.hud');
local s = require('ui.defaults').make();
local rest = { fill = 0.5, left = 10, gained_hp = 0, gained_mp = 0, full = false, flash = 0, full_meta = {} };
local enemy = { fill = 0.5, left = 2, delay = 4, learned = true, name = 'Goblin', waiting = false };
local attached = false;
MOCK.mouse = { -1, -1 };
hud.refresh(s);
local function draw()
    hud.begin_frame();
    hud.join_below(attached);
    hud.draw_attack(0.5, 1.5, 3, true);
    hud.draw_resting(rest);
    hud.draw_enemy(enemy);
    hud.end_frame();
end
-- Keep the mock's own temporary tables and generated wrappers out of the measurement.
MOCK.record_imgui = true;
MOCK.imgui_calls = {};
draw();
MOCK.record_imgui = false;
local list = imgui.GetWindowDrawList();
for _, call in ipairs(MOCK.imgui_calls) do
    local method = call[1]:match('^dl:(.+)$');
    if (method) then rawset(list, method, list[method]);
    else rawset(imgui, call[1], imgui[call[1]]); end
end
local io_state, next_pos = { DisplaySize = { x = 1600, y = 1200 } }, { 0, 0 };
rawset(imgui, 'GetIO', function () return io_state; end);
rawset(imgui, 'SetNextWindowPos', function (pos) next_pos[1], next_pos[2] = pos[1], pos[2]; end);
rawset(imgui, 'SetNextWindowSize', function () end);
rawset(imgui, 'GetWindowPos', function () return next_pos[1], next_pos[2]; end);
if (jit) then jit.off(); end
local function measure()
    for _ = 1, 20 do draw(); end
    collectgarbage('collect');
    collectgarbage('stop');
    local before = collectgarbage('count');
    for _ = 1, 100 do draw(); end
    local bytes = (collectgarbage('count') - before) * 1024 / 100;
    collectgarbage('restart');
    return bytes;
end
local bytes = measure();
check('three steady timers allocate no new frame tables', bytes < 8, bytes);
attached, s.enemy.attached = true, true;
hud.refresh(s);
bytes = measure();
check('an attached enemy strip also reuses its frame tables', bytes < 8, bytes);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
