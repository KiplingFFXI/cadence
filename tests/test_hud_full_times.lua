-- A job with no MP still gets the compact HP full time when its resting card is narrow.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
addon.name = 'cadence';
local hud = require('ui.hud');
local s = require('ui.defaults').make();
s.style.text_shadow, s.style.text_outline = false, false;
s.resting.show_gains, s.resting.show_until_full, s.resting.show_each_full = false, false, true;
s.resting.width, s.resting.height_scale = 120, 2.5;
MOCK.measure = function(text, px) return #text * px / 2; end;
local view = { fill = 0.5, left = 5, flash = 0, gained_hp = 24, gained_mp = 0,
    hp_full_in = 28, has_mp = false, full_meta = {} };
local function draw()
    hud.refresh(s); hud.set_movable(false);
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    hud.begin_frame(); hud.join_below(false, false, false); hud.draw_resting(view); hud.end_frame();
    MOCK.record_imgui = false;
    local lines = {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddText' and (c[6]:find('^HP ') or c[6]:find('^MP '))) then
            lines[#lines + 1] = { text = c[6], width = MOCK.measure(c[6], c[3]) };
        end
    end
    return lines;
end
local lines = draw();
check('HP-only full time uses its compact form when the long form exceeds the content width',
    #lines == 1 and lines[1].text == 'HP 28s' and lines[1].width <= 120);
view.full_meta.hp_confidence = 'estimated';
lines = draw();
check('compact HP time keeps its estimate marker', #lines == 1 and lines[1].text == 'HP ~28s' and lines[1].width <= 120);
view.hp_full_in = nil;
lines = draw();
check('an unknown HP full time stays unknown in its compact form', #lines == 1 and lines[1].text == 'HP --');
view.hp_full_in = 0;
lines = draw();
check('full HP keeps its full label', #lines == 1 and lines[1].text == 'HP full');
view.hp_full_in, view.full_meta.hp_confidence = 28, 'known';
s.resting.width = 400;
lines = draw();
check('HP-only full time keeps its long form when it fits', #lines == 1 and lines[1].text == 'HP full in 28s');
s.resting.width, s.resting.height_scale = 120, 1;
view.has_mp, view.mp_full_in = true, 48;
lines = draw();
check('HP and MP still both use compact forms when their long forms collide',
    #lines == 2 and lines[1].text == 'HP 28s' and lines[2].text == 'MP 48s');
s.resting.height_scale = 2.5;
lines = draw();
check('dual-resource cards still keep HP and omit MP when both compact forms cannot fit',
    #lines == 1 and lines[1].text == 'HP 28s');
s.resting.width = 400;
lines = draw();
check('wide cards keep both long full times', #lines == 2
    and lines[1].text == 'HP full in 28s' and lines[2].text == 'MP full in 48s');
check('full-time rendering sends no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or failed .. ' FAILED';
return table.concat(out, '\n');
