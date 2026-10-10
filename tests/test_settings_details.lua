-- The Details and Preview tabs keep live evidence separate from temporary samples and saved goals.
local out, fails = {}, 0;
local function check(name, condition)
    out[#out + 1] = (condition and 'ok   ' or 'FAIL ') .. name;
    if (not condition) then fails = fails + 1; end
end

addon.name = 'cadence';
local defaults = require('ui.defaults');
local window = require('ui.settings_window');
local imgui = require('imgui');
local settings = defaults.make();
local tab, clicked, picked, toggled = 'Preview', nil, nil, nil;
local preview = { timer = 'auto', state = 'normal', paused = false };
window.set_open(true);
rawset(imgui, 'BeginTabItem', function (name) return name == tab; end);
rawset(imgui, 'BeginChild', function () return true; end);
rawset(imgui, 'Button', function (name) return name == clicked; end);
rawset(imgui, 'BeginCombo', function (name) return picked and name == picked[1]; end);
rawset(imgui, 'Selectable', function (name) return picked and name == picked[2]; end);
rawset(imgui, 'Checkbox', function (name, value)
    if (name ~= toggled) then return false; end
    value[1] = not value[1];
    return true;
end);
local function draw(details)
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    local result = window.draw(settings, 'test', false, false, preview, details);
    MOCK.record_imgui = false;
    return result;
end
local result = draw();
check('preview is unchanged without an action', result.preview == nil and not result.changed and not result.save);
picked = { 'Timer##preview', 'Resting' };
result = draw();
check('timer preview returns a complete temporary selection', result.preview and result.preview.timer == 'resting'
    and result.preview.state == 'normal' and result.preview.paused == false and not result.changed and not result.save);
preview = result.preview;
picked = { 'State##preview', 'Full' };
result = draw();
check('preview state preserves the selected timer', result.preview and result.preview.timer == 'resting' and result.preview.state == 'full');
preview, picked, toggled = result.preview, nil, 'Pause preview';
result = draw();
check('pausing preview does not save settings', result.preview and result.preview.paused and not result.changed and not result.save);
preview, toggled = result.preview, 'Time to TP goal';
result = draw();
check('time to TP goal is an optional saved setting', settings.attack.show_tp_time and result.changed and result.save);
toggled = 'Recovery goal';
result = draw();
check('recovery goal is an optional saved setting', settings.resting.show_goal and result.changed and result.save);
toggled = nil;
settings.resting.goal_mode, settings.resting.goal_value = 'amount', 5000;
picked = { 'Measure##goal', 'Percent' };
result = draw();
check('switching to percent clamps the old fixed amount immediately', settings.resting.goal_mode == 'percent'
    and settings.resting.goal_value == 100 and result.changed and result.save);
picked, toggled = nil, 'Alignment guides';
result = draw();
check('alignment guides save separately from previews', settings.style.layout_guides and result.changed and result.save and result.preview == nil);
toggled, tab = nil, 'Details';
local details = {
    attack = { delay = 4, modeled_delay = 4.2, source = 'observed', samples = 4, rejected = 1,
        sample_age = 2, last_rejection = 'range changed', next_interval_changed = true, next_interval_model = 3.8 },
    tp = { per_hit = 80, modeled_per_hit = 75, source = 'observed', samples = 3, hits_per_round = 1.8 },
    resting = { next_hp = 22, next_mp = 34, pattern_known = false, accepted = 2, rejected = 1, last_decision = 'waiting' },
    enemy = { delay = 4.5, source = 'estimated', samples = 1 },
    modifiers = { unknown = { 'March strength unavailable' }, evidence = { age = 0.1, blue_status = 'provisional' },
        contributions = { { kind = 'equipment', name = 'haste_belt', field = 'haste_gear', value = 1000 } } },
};
draw(details);
local text = {};
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'TextUnformatted') then text[#text + 1] = call[2]; end
end
text = table.concat(text, '\n');
check('details explain current model observations and rejected samples', text:find('In use: 4.00 s', 1, true)
    and text:find('Model: 4.20 s', 1, true) and text:find('Samples: 4', 1, true) and text:find('range changed', 1, true));
check('details distinguish the following interval from the pending countdown', text:find('Following interval: 3.80 s', 1, true)
    and text:find('current countdown keeps its place', 1, true));
check('details show unknown inputs contributions and provisional sources', text:find('March strength unavailable', 1, true)
    and text:find('Gear haste +10.00%', 1, true) and text:find('BLU memory candidate is provisional', 1, true));
-- Applied speed uses percent inputs, while source contribution rows retain their native units.
local function details_text(value)
    draw(value);
    local result = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'TextUnformatted') then result[#result + 1] = call[2]; end
    end
    return table.concat(result, '\n');
end
local function detailed(speed, blue)
    return { speed = speed, modifiers = { blue_magic = blue, unknown = {}, contributions = {} } };
end
local speed = {
    gear = { raw = 40, effective = 25, cap = 25, minimum = 0 },
    magic = { raw = -12, effective = -12, cap = 43.75, minimum = -100 },
    ability = { raw = 30, effective = 25, cap = 25, minimum = 0 },
    combined = { raw = 38, effective = 38, cap = 80, minimum = -100 },
    martial_arts = 120, dual_wield = 15, delay_flat = -300, delay_percent = -5,
    modeled_interval = 1.5, before_limit = 1.2, minimum_interval = 1.5, maximum_interval = 8,
    limit_adjustment = .3, known = false, unknown = { 'March potency' },
};
local blue = { status = 'confirmed', role = 'sub', level = 37, active = true,
    spells = { { id = 1, name = 'Cocoon', level = 8, eligible = true },
        { id = 2, name = 'Animating Wail', level = 79, eligible = false },
        { id = 999, name = 'Spell 999', eligible = false } },
    traits = { { name = 'Clear Mind', rank = 1, points = 8, required = 8, applied = true,
        contributions = { { field = 'clear_mind', value = 1 } } },
        { name = 'Dual Wield', rank = 1, points = 8, required = 8, applied = false, overridden = true,
            contributions = { { field = 'dual_wield', value = 10 } } } },
    direct_contributions = { { name = 'Pollen', field = 'mp_heal', value = 1, applied = true } },
};
text = details_text(detailed(speed, blue));
check('speed details distinguish raw applied and capped haste', text:find('Gear haste: 40.00% raw -> 25.00% applied | cap 25.00%', 1, true)
    and text:find('Magic haste: -12.00% raw -> -12.00% applied', 1, true));
check('speed details show applied traits flat delay and final interval bounds', text:find('120.00 delay units | Dual Wield: 15.00%', 1, true)
    and text:find('Flat delay: -0.30 s | Percentage delay: -5.00%', 1, true)
    and text:find('Interval limit: 1.20 s -> 1.50 s', 1, true));
check('uncertain speed remains explicitly estimated', text:find('Modeled interval: 1.50 s (estimated)', 1, true)
    and text:find('Unknown speed input: March potency', 1, true));
check('BLU details show eligibility thresholds and native trait precedence', text:find('BLU sub Lv. 37', 1, true)
    and text:find('Clear Mind rank 1: 8 points / 8 required | applied', 1, true)
    and text:find('native trait takes precedence', 1, true)
    and text:find('Animating Wail (Lv. 79) | above current BLU level', 1, true));
check('unmapped BLU spells do not invent a level restriction', text:find('Spell 999 (Lv. ?) | not in the current source profile', 1, true));
check('direct spell bonuses state whether they apply', text:find('Spell bonus: Pollen | MP while resting +1.00 | applied', 1, true));
blue.status = 'provisional';
text = details_text(detailed(speed, blue));
check('provisional BLU values are displayed without claiming application', text:find('Provisional set candidate.', 1, true)
    and text:find('Clear Mind rank 1: 8 points / 8 required | candidate, not applied', 1, true)
    and text:find('Spell bonus: Pollen | MP while resting +1.00 | not applied', 1, true));
blue.status, blue.spells, blue.traits = 'unknown', {}, {};
text = details_text(detailed(speed, blue));
check('missing BLU evidence is distinct from a confirmed empty set', text:find('current spell set is unknown', 1, true)
    and not text:find('No relevant trait threshold', 1, true));
blue.active, blue.status = false, 'inactive';
speed.hundred_fists, speed.gear.effective, speed.magic.effective, speed.ability.effective = true, 0, 0, 0;
text = details_text(detailed(speed, blue));
check('Hundred Fists is an override rather than a haste cap', text:find('Hundred Fists overrides', 1, true)
    and text:find('Gear haste: 40.00% raw -> 0.00% applied', 1, true) and not text:find('| cap', 1, true));
check('inactive BLU does not show stale candidate spells', text:find('BLU subjob traits are inactive.', 1, true)
    and not text:find('Set spells:', 1, true));
for _, selection in ipairs({ { 'Relearn attack', 'attack' }, { 'Relearn TP', 'tp' }, { 'Relearn enemy', 'enemy' } }) do
    clicked = selection[1];
    result = draw(details);
    check(selection[1] .. ' sends only its requested action', result.relearn == selection[2] and not result.changed and not result.save);
end
clicked = nil;
result = draw(nil);
check('missing details and old callers remain safe', result.relearn == nil and pcall(window.draw, settings, 'test', false, false));
for _, name in ipairs({ 'BeginTabItem', 'BeginChild', 'Button', 'BeginCombo', 'Selectable', 'Checkbox' }) do rawset(imgui, name, nil); end

settings.resting.goal_stat, settings.resting.goal_mode, settings.resting.goal_value = 'bad', 'bad', 99999;
defaults.tidy(settings);
check('invalid goal choices recover to full MP percent', settings.resting.goal_stat == 'mp' and settings.resting.goal_mode == 'percent' and settings.resting.goal_value == 100);
settings.resting.goal_mode, settings.resting.goal_value = 'amount', 200000;
defaults.tidy(settings);
check('fixed goal values have their own upper bound', settings.resting.goal_value == 99999);
settings.resting.goal_value = -20;
defaults.tidy(settings);
check('fixed goal values stay positive', settings.resting.goal_value == 1);
settings.resting.goal_value = 0 / 0;
defaults.tidy(settings);
check('a corrupt goal number gets the default', settings.resting.goal_value == 100);

out[#out + 1] = fails == 0 and 'ALL OK' or (fails .. ' FAILED');
return table.concat(out, '\n');
