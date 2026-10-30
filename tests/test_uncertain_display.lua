-- Unknown timing stays readable even when ordinary timer labels and seconds are hidden.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
addon.name = 'cadence';
local hud, imgui = require('ui.hud'), require('imgui');
local s = require('ui.defaults').make();
s.style.show_labels, s.style.text_shadow, s.style.text_outline = false, false, false;
s.attack.show_value, s.attack.show_delay, s.attack.show_tp, s.attack.show_why, s.attack.show_reason = false, false, false, false, false;
s.resting.show_value, s.resting.show_gains, s.resting.show_until_full, s.resting.show_each_full = false, false, false, false;
MOCK.screen, MOCK.mouse = { 1600, 1200 }, { -1, -1 };
MOCK.measure = function(text, px) return #text * px * 0.5; end;
local function capture(draw)
    hud.refresh(s);
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    hud.begin_frame(); hud.join_below(false); draw(); hud.end_frame();
    MOCK.record_imgui = false;
    local words, left, position, size, value = {}, nil, nil, nil, nil;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'SetNextWindowPos') then position = call[2]; end
        if (call[1] == 'SetNextWindowSize') then size = call[2]; end
        if (call[1] == 'dl:AddText') then words[#words + 1] = call[6]; left, value = call[4][1], call[3]; end
    end
    return table.concat(words, '|'), left, position, size, value;
end
local text = capture(function() hud.draw_attack(0, nil, 4, false, nil, nil, 'recovery'); end);
check('unknown attack recovery overrides hidden seconds and why toggles', text == 'recovery unknown', text);
s.attack.width, s.attack.height_scale = 120, 2.5;
local left, position, size, value;
text, left, position, size, value = capture(function() hud.draw_attack(0, nil, 4, false, nil, nil, 'recovery'); end);
check('a long unknown status fits a narrow vertically enlarged card', left >= position[1] and value < 35, value);
s.attack.show_value = true;
text, left, position, size, value = capture(function() hud.draw_attack(0.5, 2, 4, false); end);
check('an ordinary countdown keeps its requested size after unknown timing', text == '2.0' and value == 35, value);
local rest = { fill = 0, left = nil, gained_hp = 0, gained_mp = 0, full = false, phase_unknown = true, flash = 0, full_meta = {} };
text = capture(function() hud.draw_resting(rest); end);
check('cold resting phase forces Observing without a false countdown', text == 'Observing', text);
rest.phase_unknown, rest.left, s.resting.show_value = false, 6, true;
text = capture(function() hud.draw_resting(rest); end);
check('an observed resting phase returns to ordinary timing', text == '6.0', text);
rest.phase_unknown, rest.left, rest.full = true, nil, true;
text = capture(function() hud.draw_resting(rest); end);
check('actual full vitals take precedence over an unobserved phase', text == 'full', text);
check('uncertain displays send no game commands', #MOCK.commands == 0);
MOCK.measure = nil;
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
