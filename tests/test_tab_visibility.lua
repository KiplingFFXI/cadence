-- Hidden tabs retain their settings and can be reached by search or an explicit jump.
local out, failed = {}, 0;
local function check(name, value)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name;
    if (not value) then failed = failed + 1; end
end
local imgui, nav = require('imgui'), require('ui.navigation');
nav.draw = MOCK.real_navigation_draw;
local look = require('ui.theme').window_style('phoenix');
local saved = nav.normalize({ Details = false, Profiles = false, Appearance = false, Enemy = 'bad', Unknown = false });
check('normalization keeps valid hidden tabs and repairs mandatory or malformed values', not saved.Details and not saved.Profiles
    and saved.Appearance and saved.Enemy and saved.Unknown == nil);
check('Appearance cannot be hidden', not nav.set_visible(saved, 'Appearance', false) and saved.Appearance);
check('invalid tab names do not change visibility', not nav.set_visible(saved, 'Missing', false));
local tabs, all = {}, {};
for _, name in ipairs(nav.TAB_NAMES) do tabs[#tabs + 1], all[name] = { name }, true; end
local clicked, buttons, shown = {}, {}, nil;
rawset(imgui, 'Button', function (label)
    buttons[label] = true;
    local value = clicked[label]; clicked[label] = nil;
    return value == true;
end);
local function draw(matches, searching)
    buttons, shown = {}, nil;
    return nav.draw(tabs, look, matches or all, function (tab) shown = tab[1]; end, saved, { searching = searching });
end
nav.select('Timers'); draw();
check('hidden tabs are absent while their saved choices remain', buttons['Timers##cadence_tab'] and not buttons['Details##cadence_tab']
    and not buttons['Profiles##cadence_tab'] and saved.Details == false);
local measured, measure = 0, imgui.CalcTextSize;
rawset(imgui, 'CalcTextSize', function (...) measured = measured + 1; return measure(...); end);
draw(); local before = measured; draw();
check('unchanged visibility reuses the measured layout', measured == before);
nav.set_visible(saved, 'Enemy', false); draw();
check('editing the existing visibility table updates the cached layout', not buttons['Enemy##cadence_tab']);
draw({ Details = true, Profiles = true }, true);
check('search offers to reveal hidden matching tabs', buttons['Show hidden matches (2)##reveal_tabs'] and shown == nil);
clicked['Show hidden matches (2)##reveal_tabs'] = true;
check('revealing matches reports a save and selects the first result', draw({ Details = true, Profiles = true }, true)
    and saved.Details and saved.Profiles and shown == 'Details');
nav.set_visible(saved, 'Details', false);
nav.select('Details');
check('a jump reveals a hidden page and reports its visibility change', draw() and saved.Details and shown == 'Details');
nav.set_visible(saved, 'Profiles', false);
local ok, changed = nav.select('Profiles', saved);
check('a jump can also reveal immediately with the saved table', ok and changed and saved.Profiles);
for _, name in ipairs(nav.TAB_NAMES) do nav.set_visible(saved, name, false); end
draw();
check('hiding all optional tabs falls back to Appearance', shown == 'Appearance' and buttons['Appearance##cadence_tab']);
check('Restore all tabs reports its saved change', nav.restore(saved));
draw();
local complete = true;
for _, name in ipairs(nav.TAB_NAMES) do complete = complete and buttons[name .. '##cadence_tab'] == true; end
check('Restore all tabs makes every tab available', complete and not nav.restore(saved));
for _, alias in ipairs({ 'Look', 'Window', 'Window colors', 'window_colors' }) do
    check(alias .. ' still opens Appearance', nav.select(alias) and nav.current() == 'Appearance');
end
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
