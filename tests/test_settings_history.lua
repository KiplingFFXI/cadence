local defaults = require('ui.defaults');
local history = require('ui.history');
local out, failed = {}, 0;
local function check(name, yes)
    out[#out + 1] = (yes and 'ok   ' or 'FAIL ') .. name;
    if (not yes) then failed = failed + 1; end
end
local s = defaults.make();
local before = history.capture(s);
s.attack.show_tp = false;
s.attack.fill_start[1] = 0.125;
check('one edit stores its label', history.record(s, before, 'Attack details') and history.status(s) == 'Attack details');
local attack, color, tabs, links = s.attack, s.attack.fill_start, s.window.tabs, s.job_links;
local ok, label = history.undo(s);
check('undo restores independent fields and their existing tables', ok and label == 'Attack details'
    and history.equal(s, before) and s.attack == attack and s.attack.fill_start == color);
check('empty undo is harmless', not history.undo(s) and history.status(s) == nil);
check('unchanged settings do not create an entry', not history.record(s, history.capture(s), 'No change'));

before = history.capture(s);
s.window.x, s.window.width = 333, 1001;
check('moving or sizing the settings window alone is not an edit', not history.record(s, before, 'Window'));
before = history.capture(s);
s.attack.x, s.attack.width = 100, 500;
check('timer geometry is an edit', history.record(s, before, 'Timer position'));
history.undo(s);
check('timer geometry restores while settings window geometry stays current',
    s.attack.x == before.attack.x and s.attack.width == before.attack.width and s.window.x == 333 and s.window.width == 1001);

before = history.capture(s);
s.window.tabs.Enemy = false;
s.job_links.BLM = 'Nuker';
history.record(s, before, 'Navigation and links');
history.undo(s);
check('undo preserves character-owned navigation and job-link identities',
    s.window.tabs == tabs and s.job_links == links and s.window.tabs.Enemy == before.window.tabs.Enemy and s.job_links.BLM == nil);

s.profile_source = T{ kind = 'profile', name = 'Before' };
before = history.capture(s);
s.attack.show_tp = false;
s.profile_source = T{ kind = 'layout', name = 'minimal' };
history.record(s, before, 'Layout');
history.undo(s);
check('undo restores the previous baseline marker', s.profile_source.kind == 'profile' and s.profile_source.name == 'Before');
before = { attack = { x = s.attack.x, width = s.attack.width } };
s.attack.x, s.attack.width, s.resting.show_ticks = 17, 299, true;
history.record_patch(s, before, 'Move timer');
history.undo(s);
check('partial HUD snapshot restores only its own fields', s.attack.x == before.attack.x
    and s.attack.width == before.attack.width and s.resting.show_ticks and s.enemy ~= nil and s.style ~= nil);

history.clear(s);
for i = 1, 10 do
    before = history.capture(s); s.attack.x = i;
    history.record(s, before, 'Edit ' .. i);
end
local count = 0;
while history.undo(s) do count = count + 1; end
check('only the newest eight edits remain', count == 8 and s.attack.x == 2);
local other = defaults.make();
before = history.capture(s); s.enemy.enabled = true; history.record(s, before, 'Enemy');
check('history is isolated by active settings owner', history.status(other) == nil and not history.undo(other));
history.clear(s);
check('clearing the owner removes old edits', history.status(s) == nil);

local base = defaults.make();
s = defaults.make();
s.attack.x, s.attack.y, s.attack.label_text = 19, 37, 'My swings';
s.attack.width, s.attack.show_tp, s.resting.sound = 500, false, true;
s.job_links.BLM = 'Nuker';
local changed = history.reset_section(s, 'auto attack');
check('attack reset preserves position, custom label and unrelated settings', changed and s.attack.width == base.attack.width
    and s.attack.show_tp == base.attack.show_tp and s.attack.x == 19 and s.attack.y == 37
    and s.attack.label_text == 'My swings' and s.resting.sound and s.job_links.BLM == 'Nuker');
check('section reset can be undone', history.undo(s) and s.attack.width == 500 and not s.attack.show_tp);
s.resting.show_next_gains, s.enemy.enabled = true, true;
history.reset_section(s, 'timers');
check('Timers resets attack and resting, leaving enemy choices', not s.resting.show_next_gains and s.enemy.enabled);

s.window_style.font_size, s.window_style.spacing = 24, 12;
s.window_style.background[1] = 0.123;
local custom_color = s.window_style.background[1];
s.style.hover_tips, s.style.record_diagnostics = false, true;
history.reset_section(s, 'window');
check('Window reset changes its controls but preserves palette and position', s.window_style.font_size == base.window_style.font_size
    and s.window_style.spacing == base.window_style.spacing and s.window_style.background[1] == custom_color
    and s.style.hover_tips and not s.style.record_diagnostics and s.attack.x == 19);
s.window_style.font_size = 23;
history.reset_section(s, 'window colors');
check('Window colors reset preserves window font and timer colors', s.window_style.font_size == 23
    and history.equal(s.window_style.background, base.window_style.background));

s.style.font_size, s.style.locked, s.style.shared_spot = 28, true, true;
s.attack.width, s.attack.label_text, s.attack.x = 400, 'Custom', 77;
s.job_links.BLM = 'Nuker';
history.reset_section(s, 'Look');
check('Appearance reset preserves positions, custom labels, locks and job links', s.style.font_size == base.style.font_size
    and s.attack.width == base.attack.width and s.style.locked and s.style.shared_spot
    and s.attack.x == 77 and s.attack.label_text == 'Custom' and s.job_links.BLM == 'Nuker');

s.attack.show_tp_time, s.attack.tp_goal = true, 3000;
s.resting.show_goal, s.resting.goal_value, s.resting.sound = true, 72, true;
s.style.layout_guides, s.style.scale = true, 1.5;
history.reset_section(s, 'preview');
check('Preview reset touches only saved goal and alignment controls', not s.attack.show_tp_time and s.attack.tp_goal == 3000
    and not s.resting.show_goal and s.resting.goal_value == base.resting.goal_value and s.resting.sound
    and not s.style.layout_guides and s.style.scale == 1.5);
links = s.job_links;
history.reset_section(s, 'profiles');
check('Job links reset clears the same owned table', s.job_links == links and next(links) == nil);
history.undo(s);
check('Job links undo restores values in the same table', s.job_links == links and links.BLM == 'Nuker');
before = history.capture(s);
check('Details is not a resettable section', not history.reset_section(s, 'details') and history.equal(before, s));
history.clear(s); s.attack.show_tp = false;
history.reset_section(s, 'attack', { record = false });
check('callers can record one grouped reset without a duplicate entry', history.status(s) == nil and s.attack.show_tp);
local sections = history.sections(); sections[1].name = 'Changed';
check('section metadata is safe to edit outside the module', history.sections()[1].name == 'Timers');
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
