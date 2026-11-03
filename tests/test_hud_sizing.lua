-- Attached size queries must not recurse through their parents on Ashita's MoonJIT runtime.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
addon.name = 'cadence';
local hud = require('ui.hud');
local s = require('ui.defaults').make();
s.attack.width, s.resting.width, s.enemy.width = 300, 360, 220;
s.enemy.enabled, s.enemy.attached = true, true;
s.recovery.enabled, s.recovery.attached = true, true;
s.enemycast.enabled, s.enemycast.attached = true, true;
s.style.shared_spot = true;
local original = hud.element_size;
local depth, maximum = 0, 0;
hud.element_size = function(key)
    depth = depth + 1;
    maximum = math.max(maximum, depth);
    local width, height = original(key);
    depth = depth - 1;
    return width, height;
end;
hud.refresh(s);
hud.begin_frame(); hud.join_below(true, true, true);
local attack_width = hud.element_size('attack');
local enemy_width = hud.element_size('enemy');
local recovery_width = hud.element_size('recovery');
local cast_width, cast_height = hud.element_size('enemycast');
check('a hidden host supplies its width throughout the attached stack',
    enemy_width == attack_width and recovery_width == attack_width and cast_width == attack_width);
check('attached size queries never recursively measure a parent', maximum == 1);
hud.end_frame();

s.enemy.attached = false;
hud.refresh(s); hud.begin_frame();
enemy_width = hud.element_size('enemy');
cast_width = hud.element_size('enemycast');
check('casting inherits an independent enemy card width', cast_width == enemy_width and cast_width ~= attack_width);
hud.end_frame();

s.attack.enabled = false;
hud.refresh(s); hud.begin_frame();
recovery_width = hud.element_size('recovery');
check('a disabled attack host restores the recovery card width', recovery_width ~= attack_width);
hud.end_frame();

s.attack.enabled, s.enemy.attached = true, true;
hud.refresh(s); hud.begin_frame(); hud.join_below(true, true, true);
hud.draw_resting({ fill = 0.5, left = 10, flash = 0 });
local resting_width = hud.element_size('resting');
enemy_width = hud.element_size('enemy');
cast_width = hud.element_size('enemycast');
check('a visible shared resting host supplies its own wider width',
    enemy_width == resting_width and cast_width == resting_width and resting_width ~= attack_width);
local _, current_cast_height = hud.element_size('enemycast');
check('inherited widths preserve the child height', current_cast_height == cast_height);
hud.end_frame();
hud.element_size = original;
check('sizing sends no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or failed .. ' FAILED';
return table.concat(out, '\n');
