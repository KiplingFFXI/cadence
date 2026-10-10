-- Search keeps a place on each page without pulling the scroll back every frame.
local out, failed = {}, 0;
local function check(name, value)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name;
    if (not value) then failed = failed + 1; end
end
local imgui, search = require('imgui'), require('ui.search');
local position, jumps, marks = 0, 0, 0;
rawset(imgui, 'GetItemRectMin', function () return 0, position; end);
rawset(imgui, 'GetItemRectMax', function () return 100, position + 20; end);
rawset(imgui, 'SetScrollHereY', function () jumps = jumps + 1; end);
rawset(imgui, 'GetWindowDrawList', function () return { AddRect = function () marks = marks + 1; end }; end);
local function draw(name, count, duplicate)
    jumps, marks = 0, 0;
    search.begin_page(name);
    for index = 1, count or 3 do
        position = index * 24;
        search.mark('Critical ' .. index, 'Rate +10');
        if (duplicate) then search.mark('Critical ' .. index, 'Rate +10'); end
    end
    search.finish_page();
    search.begin_page(nil);
end
search.query('critical');
draw('Timers', 3, true);
local index, count = search.status('Timers');
check('first match is selected and duplicate marks count once', index == 1 and count == 3 and marks == 3 and jumps == 1);
draw('Timers');
check('unchanged frames preserve the scroll position', jumps == 0);
check('Next selects an existing match', search.step(1, 'Timers'));
draw('Timers');
check('Next scrolls once to the second match', search.status('Timers') == 2 and jumps == 1);
search.step(-1, 'Timers'); search.step(-1, 'Timers');
draw('Timers');
check('Previous wraps from first to last', search.status('Timers') == 3 and jumps == 1);
draw('Appearance', 2);
check('another page starts at its first match', search.status('Appearance') == 1 and jumps == 1);
draw('Timers');
check('returning keeps the selected match and existing scroll', search.status('Timers') == 3 and jumps == 0);
draw('Timers', 1);
index, count = search.status('Timers');
check('removing controls clamps the selected match', index == 1 and count == 1);
draw('Timers', 1);
check('a clamped match scrolls once after it becomes available', jumps == 1);
search.query('missing'); draw('Timers');
index, count = search.status('Timers');
check('a query without matches has no selection or movement', index == 0 and count == 0 and not search.step(1, 'Timers'));
search.query('critical +10'); draw('Timers');
check('literal query words match across label and help', select(2, search.status('Timers')) == 3);
search.query(''); draw('Timers');
index, count = search.status('Timers');
check('clearing search resets its count without scrolling', index == 0 and count == 0 and jumps == 0 and not search.active());
search.query('  '); draw('Timers');
check('a whitespace-only search is inactive', not search.active() and select(2, search.status('Timers')) == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
