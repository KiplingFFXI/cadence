local defaults = require('ui.defaults');
local history = require('ui.history');
local layouts = require('ui.layouts');
local out, failed = {}, 0;
local function check(name, yes)
    out[#out + 1] = (yes and 'ok   ' or 'FAIL ') .. name;
    if (not yes) then failed = failed + 1; end
end
local s = defaults.make();
s.attack.x, s.attack.width, s.attack.bar_height = 37, 500, 11;
s.attack.label_text, s.attack.show_label, s.attack.tp_goal = 'Swings', false, 3000;
s.attack.fill_start[1] = 0.1;
s.resting.y, s.resting.sound, s.resting.goal_value = 491, true, 72;
s.resting.goal_mode = 'amount';
s.enemy.which, s.enemy.attached, s.enemy.keep_last = 'attacker', true, false;
s.style.font_name, s.style.font_size, s.style.scale = 'Arial', 23, 1.5;
s.job_links.BLM = 'Nuker';
local before = history.capture(s);
local preview, meta = layouts.preview(s, 'Melee / TP');
check('preview returns an independent settings copy and leaves live state untouched',
    preview ~= s and preview.attack ~= s.attack and history.equal(s, before) and meta.id == 'melee');
check('Melee / TP enables its timing and progress readouts', preview.attack.enabled and preview.attack.show_tp
    and preview.attack.show_tp_hits and preview.attack.show_tp_rounds and preview.attack.show_tp_time
    and preview.attack.show_delay and preview.resting.show_until_full and not preview.enemy.enabled);
preview.attack.fill_start[1], meta.name = 1, 'Mutated';
check('preview colors and metadata do not alias live settings or library records',
    s.attack.fill_start[1] == 0.1 and layouts.find('melee').name == 'Melee / TP');
for _, entry in ipairs(layouts.list()) do
    local result = layouts.preview(s, entry.id);
    check(entry.name .. ' preserves personal styling and targets',
        result.attack.x == 37 and result.attack.width == 500 and result.attack.bar_height == 11
        and result.attack.label_text == 'Swings' and not result.attack.show_label and result.attack.tp_goal == 3000
        and result.attack.fill_start[1] == 0.1 and result.resting.y == 491 and result.resting.sound
        and result.resting.goal_value == 72 and result.resting.goal_mode == 'amount'
        and result.enemy.which == 'attacker' and result.enemy.attached and not result.enemy.keep_last
        and result.style.font_name == 'Arial' and result.style.font_size == 23 and result.style.scale == 1.5
        and result.job_links.BLM == 'Nuker');
    check(entry.name .. ' matches only after applying its readouts', layouts.apply(result, entry.id) and layouts.matches(result, entry.id));
    result.attack.x, result.style.font_size = 91, 12;
    check(entry.name .. ' allows personal styling without becoming modified', layouts.matches(result, entry.id));
    result.attack.enabled = not result.attack.enabled;
    check(entry.name .. ' detects a changed readout', not layouts.matches(result, entry.id));
end
layouts.apply(s, 'minimal');
check('Minimal removes extra rows and the enemy timer', s.attack.enabled and s.resting.enabled and not s.enemy.enabled
    and not s.attack.show_tp and not s.resting.show_next_gains and not s.resting.show_until_full);
layouts.apply(s, 'resting');
check('Resting enables recovery detail and preserves explicit false choices', not s.attack.enabled and not s.enemy.enabled
    and s.resting.enabled and s.resting.show_gains and s.resting.show_next_gains and s.resting.show_ticks
    and s.resting.show_each_full and s.resting.show_goal);
layouts.apply(s, 'Enemy tracking');
check('Enemy tracking enables all timers and enemy detail', s.attack.enabled and s.resting.enabled and s.enemy.enabled
    and s.enemy.show_holds and s.enemy.show_effects and s.enemy.show_on_you);
before = history.capture(s);
check('invalid layouts never mutate settings', not layouts.apply(s, 'unknown')
    and layouts.preview(s, 'unknown') == nil and history.equal(s, before));
check('each layout includes a description and change summary', #layouts.list() == 4
    and #layouts.find('enemy').changes >= 3 and #layouts.find('minimal').description > 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
