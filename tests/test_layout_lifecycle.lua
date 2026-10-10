-- Interrupted gestures cannot carry another character's layout into Undo.
local out, fails = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then fails = fails + 1; end
end
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local hud, presets, defaults = require('ui.hud'), require('ui.presets'), require('ui.defaults');
local function command(words) MOCK.fire('command', { command = '/cadence ' .. words }); end
local s = MOCK.settings.current;
s.style.shared_spot, s.style.locked = false, false;
s.attack.x, s.resting.x, s.enemy.x = 100, 150, 200;
hud.refresh(s);
command('preview attack normal');
MOCK.frame();
MOCK.key_shift, MOCK.mouse_down = true, true;
MOCK.window_pos['##cadence_attack'] = { 220, 300 };
MOCK.frame();
check('a real drag changed the old layout', s.attack.x == 220);

local player = require('core.player');
local entity = player.entity;
player.entity = function () return nil; end;
MOCK.mouse_down, MOCK.window_pos['##cadence_attack'] = false, nil;
MOCK.frame();
local other = defaults.make();
other.attack.x, other.resting.x, other.enemy.x = 700, 750, 800;
MOCK.settings.switch_character(other);
check('character replacement clears existing Undo', not presets.can_undo());
player.entity = entity;
MOCK.frame();
check('resuming drawing cannot recreate the previous character Undo', not presets.can_undo());
command('undo');
check('the new character keeps its own layout', other.attack.x == 700 and other.resting.x == 750 and other.enemy.x == 800);

-- An ordinary redraw of the same settings table keeps the original gesture snapshot.
s = other;
s.style.shared_spot, s.style.locked = false, false;
command('preview attack normal');
MOCK.frame();
MOCK.mouse_down = true;
MOCK.window_pos['##cadence_attack'] = { 330, 300 };
MOCK.frame();
hud.refresh(s);
MOCK.mouse_down, MOCK.window_pos['##cadence_attack'] = false, nil;
MOCK.frame();
check('same-table refresh preserves one-step Undo', presets.can_undo());
command('undo');
check('same-table gesture Undo restores the start of the drag', s.attack.x == 700);

-- Cancellation while the button is held prevents the old gesture from starting again.
MOCK.mouse_down = true;
MOCK.window_pos['##cadence_attack'] = { 250, 300 };
MOCK.frame();
hud.cancel_layout_gesture();
presets.forget_undo();
s.attack.x = 600;
hud.refresh(s);
MOCK.window_pos['##cadence_attack'] = { 260, 300 };
MOCK.frame();
check('the cancelled mouse hold cannot move the replacement layout', s.attack.x == 600);
MOCK.mouse_down, MOCK.window_pos['##cadence_attack'] = false, nil;
MOCK.frame();
check('a cancelled gesture emits no stale Undo', not presets.can_undo());
MOCK.mouse_down = true;
MOCK.window_pos['##cadence_attack'] = { 350, 300 };
MOCK.frame();
MOCK.mouse_down, MOCK.window_pos['##cadence_attack'] = false, nil;
MOCK.frame();
check('a new gesture works after releasing the cancelled hold', s.attack.x == 350 and presets.can_undo());
command('undo');
check('new gesture Undo uses the replacement layout', s.attack.x == 600);
-- Reset all reuses the settings table, so its explicit lifecycle hook matters.
MOCK.mouse_down = true;
MOCK.window_pos['##cadence_attack'] = { 180, 300 };
MOCK.frame();
command('reset all');
command('reset all');
MOCK.mouse_down, MOCK.window_pos['##cadence_attack'] = false, nil;
MOCK.frame();
check('Reset all cannot recreate a cancelled gesture Undo', not presets.can_undo());
check('Reset all keeps the default layout after mouse release', s.attack.x == defaults.make().attack.x);
out[#out + 1] = fails == 0 and 'ALL OK' or (fails .. ' FAILED');
return table.concat(out, '\n');
