-- Search, navigation and copying use real UI modules and preserve the selected settings.
local out, fails = {}, 0;
local function check(name, ok) out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name; if (not ok) then fails = fails + 1; end end
addon.name = 'cadence';
local imgui, nav, search = require('imgui'), require('ui.navigation'), require('ui.search');
local window, defaults = require('ui.settings_window'), require('ui.defaults');
local s = defaults.make();
nav.draw = MOCK.real_navigation_draw;
local tabs = { { 'Timers' }, { 'Appearance' }, { 'Details' }, { 'Profiles' } };
local rows = nav.rows({ 'Timers', 'Appearance', 'Details', 'Profiles' }, 130, function (text) return #text * 8; end, 16, 8);
local count, fits = 0, true;
for _, row in ipairs(rows) do
    local used = -8;
    for _, item in ipairs(row) do count, used = count + 1, used + item.width + 8; end
    fits = fits and used <= 130;
end
check('wrapping retains every tab within the available width', count == 4 and #rows > 1 and fits);
local shown;
local original_button = imgui.Button;
rawset(imgui, 'Button', function (label) return label == 'Details##cadence_tab'; end);
nav.draw(tabs, s.window_style, { Timers = true, Appearance = true, Details = true, Profiles = true }, function (tab) shown = tab[1]; end);
check('a real navigation click selects just its page', shown == 'Details' and nav.current() == 'Details');
nav.draw(tabs, s.window_style, { Profiles = true }, function (tab) shown = tab[1]; end);
check('a filtered-out selection moves to an available page', shown == 'Profiles');
rawset(imgui, 'Button', original_button);
local same_matches, saved_size, size_reused = { Timers = true }, nil, true;
local measure, measured = imgui.CalcTextSize, 0;
rawset(imgui, 'CalcTextSize', function (...) measured = measured + 1; return measure(...); end);
rawset(imgui, 'Button', function (_, size)
    if (saved_size) then size_reused = size_reused and rawequal(saved_size, size); else saved_size = size; end
    return false;
end);
nav.draw(tabs, s.window_style, same_matches, function () end);
local initial_measures = measured;
for i = 1, 20 do nav.draw(tabs, s.window_style, same_matches, function () end); end
check('quiet navigation reuses measured rows and button sizes', measured == initial_measures and size_reused);
rawset(imgui, 'CalcTextSize', measure); rawset(imgui, 'Button', original_button);
check('unchanged settings queries reuse their matches', rawequal(window.search_tabs('scale'), window.search_tabs('scale')));
local found = window.search_tabs('next tick');
check('settings search includes control help', found.Timers == true and found.Profiles == false);
found = window.search_tabs('store tp');
check('modifier terms find Details', found.Details == true);
found = window.search_tabs('blue magic');
local only_details = found.Details;
for name, matches in pairs(found) do if (matches and name ~= 'Details') then only_details = false; end end
check('Blue Magic does not match unrelated pages', only_details);
check('window color search includes row names', window.search_tabs('scrollbar').Appearance);
check('search treats punctuation literally and requires every word', search.matches('HP +10 food', '+10 food') and not search.matches('HP +10 food', '+10 haste'));
MOCK.imgui_calls, MOCK.record_imgui = {}, true;
search.query('successful hits', s.window_style.headings); search.begin_page('Timers');
search.mark('Successful hits', 'Counts successful attacks.'); search.mark('Successful hits', 'Counts successful attacks.');
search.begin_page(nil); search.query('', s.window_style.headings);
MOCK.record_imgui = false;
local jumps, marks = 0, 0;
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'SetScrollHereY') then jumps = jumps + 1; end
    if (call[1] == 'dl:AddRect') then marks = marks + 1; end
end
check('matching controls highlight and jump only once for the page/query', jumps == 1 and marks == 1);
local details = { attack = { source = 'observed', samples = 2, delay = 3 }, modifiers = { unknown = {}, contributions = {} } };
for i = 1, 130 do details.modifiers.contributions[i] = { kind = 'equipment', name = 'Piece ' .. i, field = 'store_tp', value = i }; end
for i = 1, 45 do details.modifiers.unknown[i] = 'Missing input ' .. i; end
details.enemy = { holding = 'sleep', waiting = true, effects = { { id = 2, control = 'sleep', uncertain = true,
    duration_estimate = 60, duration_basis = 'source spell duration', cast_inputs = { equipment_known = true,
    equipment = { { id = 123, slot = 1, augment = 7 } }, buffs_known = false, merits_known = false } } } };
local full = window.details_text(details, '');
check('control evidence has no fabricated speed and keeps cast timing qualified', full:find('Cast-time duration estimate: 60.00 s before resists, not time remaining.', 1, true)
    and full:find('Cast gear: item 123', 1, true) and full:find('augment 7', 1, true) and not full:find('Speed amount:', 1, true));
local filtered = window.details_text(details, 'contributions');
check('Copy all includes contributions and unknown inputs past the old display limits', full:find('Piece 130', 1, true) and full:find('Missing input 45', 1, true));
check('Copy shown follows the section search', filtered:find('Piece 130', 1, true) and not filtered:find('AUTO ATTACK', 1, true));
check('an empty search match has an explicit copy result', window.details_text(details, 'xyznotfound') == 'No matching details.');
window.set_open(true); nav.select('Details');
check('Details requests a snapshot only while its window is open', window.needs_details());
window.set_open(false); check('closed settings do not request a snapshot', not window.needs_details());
window.set_open(true); nav.select('Timers'); check('ordinary settings do not request a snapshot', not window.needs_details());
nav.select('Details');
local original_input = imgui.InputText;
rawset(imgui, 'InputText', function (label, value) if (label == 'Find details') then value[1] = 'contributions'; return true; end return false; end);
rawset(imgui, 'Button', function (label) return label == 'Copy shown'; end);
MOCK.imgui_calls, MOCK.record_imgui = {}, true;
window.draw(s, 'test', false, false, nil, details);
MOCK.record_imgui = false;
check('Copy shown button uses the filtered complete evidence', MOCK.clipboard == filtered);
local button_at, page_at;
for i, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'BeginChild' and call[2] == '##page_Details') then page_at = i; end
    if (call[1] == 'Separator' and not page_at) then button_at = i; end
end
check('navigation stays outside the scrolling page', button_at and page_at and button_at < page_at);
rawset(imgui, 'Button', function (label) return label == 'Copy all'; end);
window.draw(s, 'test', false, false, nil, details);
check('Copy all ignores the active details search', MOCK.clipboard == full);
rawset(imgui, 'InputText', original_input); rawset(imgui, 'Button', original_button);
local entered, pending_open, last_size = '', nil, nil;
rawset(imgui, 'InputText', function (label, value) if (label == 'Find settings') then value[1] = entered; return true; end return false; end);
rawset(imgui, 'SetNextItemOpen', function (value) pending_open = value; end);
rawset(imgui, 'CollapsingHeader', function (label)
    local value = pending_open; pending_open = nil;
    if (label == 'SIZE##section') then last_size = value == true; return last_size; end
    return value == nil and true or value;
end);
nav.select('Appearance'); window.draw(s, 'test', false, false, nil, details);
check('an appearance section can fold without changing settings', last_size == false);
entered = 'scale'; window.draw(s, 'test', false, false, nil, details);
check('search opens folded sections so matching controls are reachable', last_size == true);
entered = ''; window.draw(s, 'test', false, false, nil, details);
check('clearing search restores the previous fold state', last_size == false);
rawset(imgui, 'InputText', original_input); rawset(imgui, 'SetNextItemOpen', nil); rawset(imgui, 'CollapsingHeader', nil);

for _, item in ipairs({ { 'Tag brackets', 'Appearance' }, { 'Tag word', 'Appearance' }, { 'Replies', 'Appearance' },
    { 'State', 'Preview' }, { 'Measure', 'Preview' }, { 'Relearn', 'Details' },
    { 'One layout for all characters', 'Appearance' }, { 'Why it can\'t heal', 'Timers' }, { 'Overwrite', 'Profiles' } }) do
    check('visible control search finds ' .. item[1], window.search_tabs(item[1])[item[2]] == true);
end
rawset(imgui, 'InputText', function (label, value)
    if (label == 'Find settings') then value[1] = 'State'; end
    return false;
end);
nav.select('Preview');
MOCK.imgui_calls, MOCK.record_imgui = {}, true;
window.draw(s, 'test', false, false, nil, details);
MOCK.record_imgui = false;
local state_marks = 0;
for _, call in ipairs(MOCK.imgui_calls) do if (call[1] == 'dl:AddRect') then state_marks = state_marks + 1; end end
check('the matching dropdown label highlights even when its help uses different words', state_marks > 0);
rawset(imgui, 'InputText', original_input);

for _, alias in ipairs({ 'Look', 'Window', 'Window colors' }) do
    check(alias .. ' navigation opens Appearance', nav.select(alias) and nav.current() == 'Appearance');
end
check('window controls and colors only add the Appearance search result', window.search_tabs('scrollbar').Appearance
    and window.search_tabs('scrollbar').Window == nil and window.search_tabs('scrollbar')['Window colors'] == nil);
local show_window, show_colors = false, true;
rawset(imgui, 'InputText', function (label, value)
    if (label == 'Find settings') then value[1] = ''; end
    return false;
end);
rawset(imgui, 'CollapsingHeader', function (label)
    if (label == 'WINDOW##section') then return show_window; end
    if (label == 'WINDOW COLORS##section') then return show_colors; end
    return true;
end);
local function appearance_controls()
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    nav.select('Appearance'); window.draw(s, 'test', false, false, nil, details);
    MOCK.record_imgui = false;
    local font, color, scale = false, false, false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'BeginCombo' and call[2] == 'Font##window') then font = true; end
        if (call[1] == 'ColorEdit4' and call[2] == '##text') then color = true; end
        if (call[1] == 'SliderFloat' and call[2] == 'Scale') then scale = true; end
    end
    return font, color, scale;
end
local font, color, scale = appearance_controls();
check('Window folds independently while colors and timer controls remain', not font and color and scale);
show_window, show_colors = true, false;
font, color, scale = appearance_controls();
check('Window colors folds independently while window and timer controls remain', font and not color and scale);
rawset(imgui, 'InputText', original_input); rawset(imgui, 'CollapsingHeader', nil);

check('search and copy leave saved settings unchanged', s.style.hover_tips and s.attack.tp_goal == 1000);
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED'); return table.concat(out, '\n');
