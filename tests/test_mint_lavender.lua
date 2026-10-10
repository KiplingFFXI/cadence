-- The new palettes change only the look and retain the optional window match.
local out, failed = {}, 0;
local function check(name, value)
    out[#out + 1] = (value and 'ok   ' or 'FAIL ') .. name;
    if (not value) then failed = failed + 1; end
end
local presets, defaults, theme = require('ui.presets'), require('ui.defaults'), require('ui.theme');
local function same(a, b)
    for index = 1, 4 do if (math.abs(a[index] - b[index]) > 0.002) then return false; end end
    return true;
end
for _, row in ipairs({ { 'Mint', 'mint', 88 }, { 'Lavender', 'lavender', 105 } }) do
    local name, id, word = row[1], row[2], row[3];
    local s = defaults.make();
    s.attack.enabled, s.attack.width, s.attack.tp_goal = false, 444, 2000;
    s.resting.enabled, s.resting.goal_value = false, 65;
    s.enemy.enabled, s.style.locked = false, true;
    local before = s.style.panel_color;
    presets.apply(s, name);
    check(name .. ' is recognized by name and short ID', presets.current(s) == name and s.style.window_look == id);
    check(name .. ' leaves timer choices and dimensions alone', not s.attack.enabled and s.attack.width == 444
        and s.attack.tp_goal == 2000 and not s.resting.enabled and s.resting.goal_value == 65 and not s.enemy.enabled and s.style.locked);
    check(name .. ' uses matching Checkmate chat colors', s.chat.tag_brackets == 102 and s.chat.tag_word == word and s.chat.replies == 90);
    check(name .. ' distinguishes ready and almost from filling', not same(s.attack.ready_color, s.attack.fill_end)
        and not same(s.attack.almost_color, s.attack.fill_end) and not same(s.attack.almost_color, s.attack.ready_color));
    check(name .. ' keeps enemy warnings coral and full recovery bright', same(s.enemy.ready_color, theme.hex('f07868'))
        and same(s.resting.full_color, s.style.value_color) and not same(s.attack.tp_color, s.style.value_color));
    check(name .. ' applies its window palette while matching is on', same(s.window_style.background, theme.window_palettes[id].background));
    presets.undo(s);
    check(name .. ' remains reversible', same(s.style.panel_color, before));
    s.style.window_matches_look = false;
    s.window_style.text[1] = 0.125;
    presets.apply(s, name);
    check(name .. ' leaves a separately styled window alone', s.window_style.text[1] == 0.125 and presets.current(s) == name);
    presets.undo(s);
    check(name .. ' undo also leaves that window alone', s.window_style.text[1] == 0.125);
    local first, second = theme.window_style(id), theme.window_style(id);
    first.text[1] = 0;
    check(name .. ' window colors are independent copies', second.text[1] ~= 0 and theme.window_palettes[id].text[1] ~= 0);
end
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
