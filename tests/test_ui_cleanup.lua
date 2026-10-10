-- Search and sample drawing keep their state and finish edits at page boundaries.
local out, fails = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. detail) or '');
    if (not ok) then fails = fails + 1; end
end
local imgui, window = require('imgui'), require('ui.settings_window');
local nav, search = require('ui.navigation'), require('ui.search');
local s = require('ui.defaults').make();
nav.draw = MOCK.real_navigation_draw;
window.set_open(true);
local input, header = imgui.InputText, imgui.CollapsingHeader;
local value, next_open, tabs_open, active = '', nil, nil, false;
local width, search_size;
local item_width = imgui.SetNextItemWidth;
rawset(imgui, 'SetNextItemWidth', function (size) width = size; return item_width(size); end);
rawset(imgui, 'InputText', function (label, data, ...)
    if (label == 'Find settings') then data[1], search_size = value, width; end
    return input(label, data, ...);
end);
rawset(imgui, 'SetNextItemOpen', function (shown) next_open = shown; end);
rawset(imgui, 'CollapsingHeader', function (label, ...)
    if (label == 'TABS##section') then tabs_open = next_open; next_open = nil; return false; end
    next_open = nil;
    return header(label, ...);
end);
rawset(imgui, 'IsAnyItemActive', function () return active; end);
local function draw()
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    local result = window.draw(s, '1.2.0', false, false);
    MOCK.record_imgui = false;
    return result;
end
window.select_tab('Appearance'); draw();
value = '   '; draw();
local stepped = false;
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'Button' and c[2] == 'Next match') then stepped = true; end end
check('spaces do not open folded groups or show empty search navigation', tabs_open == false and not stepped);
value = ''; active = true;
check('an active mouse or keyboard item keeps its edit open', draw().editing == true);
active = false; window.select_tab('Enemy');
check('switching away exposes the completed edit even when the old widget is absent', draw().editing == false);
MOCK.content_width = 436;
value = 'Undo'; draw(); draw();
local reserved = 4 + imgui.CalcTextSize('Find settings') + 8 + imgui.CalcTextSize('(?)')
    + 8 + imgui.CalcTextSize('Clear') + 16 + 8 + imgui.CalcTextSize('(?)');
check('the search input leaves room for both help marks and Clear', search_size + reserved <= MOCK.content_width);
local minimum;
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'SetNextWindowSizeConstraints') then minimum = c[2][2]; end end
check('search controls add room to the rendered minimum height', minimum == 504);
MOCK.content_width = nil;
value = '';
window.open_details('attack');
local available = imgui.GetContentRegionAvail;
rawset(imgui, 'GetContentRegionAvail', function () return 436, 40; end);
draw();
local nested, evidence = false, false;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'BeginChild' and c[2] == '##estimate_details') then nested = true; end
    if (c[1] == 'CollapsingHeader' and c[2] == 'AUTO ATTACK') then evidence = true; end
end
check('short Details pages keep evidence in the outer scroll instead of a tiny child', not nested and evidence);
rawset(imgui, 'GetContentRegionAvail', available);

local preview = require('ui.preview');
s.style.text_shadow, s.style.text_outline = false, true;
s.style.font_size, s.style.scale = 32, 1;
s.attack.show_label, s.attack.show_delay, s.attack.show_tp = false, false, false;
s.resting.enabled = false;
MOCK.imgui_calls, MOCK.record_imgui = {}, true;
preview.draw(s, 'normal', true);
MOCK.record_imgui = false;
local text_count, diagonal = 0, false;
local base;
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText') then text_count, base = text_count + 1, c[4]; end end
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'dl:AddText' and base and c[4][1] == base[1] - 2 and c[4][2] == base[2] - 2) then diagonal = true; end
end
check('sample outlines use all eight scaled edges, like live timer text', text_count == 9 and diagonal);

local y, points, calls = 0, {}, 0;
rawset(imgui, 'GetItemRectMin', function () return 0, y; end);
rawset(imgui, 'GetItemRectMax', function () return 100, y + 20; end);
local list = { AddRect = function (_, first, second)
    calls = calls + 1;
    points[first], points[second] = true, true;
end };
rawset(imgui, 'GetWindowDrawList', function () return list; end);
search.query('matched');
for _ = 1, 10 do
    search.begin_page('Timers');
    for i = 1, 3 do y = i * 24; search.mark('Matched', 'Readout'); end
    search.finish_page(); search.begin_page(nil);
end
local used = 0;
for _ in pairs(points) do used = used + 1; end
check('search highlights reuse their point tables across matches and frames', calls == 30 and used == 2, tostring(used));
out[#out + 1] = fails == 0 and 'ALL PASSED' or fails .. ' FAILED';
return table.concat(out, '\n');
