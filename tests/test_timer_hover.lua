-- Hover explains existing evidence without taking the mouse or inventing preview observations.
local out, fails = {}, 0;
local function check(name, ok) out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name; if (not ok) then fails = fails + 1; end end
addon.name = 'cadence';
local imgui, hud, tips = require('imgui'), require('ui.hud'), require('ui.tips');
local s = require('ui.defaults').make(); s.attack.show_tp = false;
hud.refresh(s); hud.set_movable(false);
local details = { attack = { source = 'observed', samples = 3, rejected = 1, sample_age = 0.4, delay = 2.5 },
    tp = { per_hit = 65, source = 'observed' }, modifiers = { unknown = { 'March strength unavailable' }, evidence = { age = 0.2 } } };
MOCK.mouse = { s.attack.x + 5, s.attack.y + 5 };
local function draw(preview)
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    hud.begin_frame(); hud.draw_attack(0.5, 1, 2, true, nil, nil, nil, nil, preview);
    local wanted = hud.needs_details();
    hud.end_frame(details); MOCK.record_imgui = false;
    return wanted;
end
local function text()
    local words = {};
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'TextUnformatted') then words[#words + 1] = c[2]; end end
    return table.concat(words, ' ');
end
check('hovering a live timer requests its existing snapshot', draw(false));
check('tips wait briefly before appearing', text() == '');
MOCK.now = MOCK.now + 0.3; draw(false);
check('the tip names observed inputs and uncertainty', text():find('Accepted samples: 3', 1, true) and text():find('March strength unavailable', 1, true));
local flags;
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'Begin' and c[2] == '##cadence_attack') then flags = c[4]; end end
check('hover leaves the timer click-through', flags and bit.band(flags, ImGuiWindowFlags_NoInputs) ~= 0);
MOCK.mouse_down = true; check('dragging suppresses evidence demand and tips', not draw(false) and text() == ''); MOCK.mouse_down = false;
rawset(imgui, 'IsWindowHovered', function () return true; end);
check('another window over the timer suppresses its tip', not draw(false) and text() == ''); rawset(imgui, 'IsWindowHovered', nil);
hud.begin_frame(); check('a hidden timer leaves no stale hover target', not hud.needs_details()); hud.end_frame(details);
check('a preview needs no live snapshot', not draw(true)); MOCK.now = MOCK.now + 0.3; draw(true);
check('a preview tooltip cannot claim live observations', text():find('sample values', 1, true) and not text():find('Accepted samples', 1, true));
s.style.hover_tips = false; check('the hover setting disables tips and demand', not draw(false) and text() == '');
s.style.hover_tips = true; hud.set_movable(true); check('arranging timers does not open a tip', not draw(false) and text() == ''); hud.set_movable(false);
local attack_tip = tips.text('attack', { attack = { disabled = 'sleep', stalled = true, overdue = true } });
check('disabled status IDs have readable names', tips.text('attack', { attack = { disabled = 10 } }):find('stopped: Stun', 1, true));
check('attack tips explain stopped stalled and overdue states', attack_tip:find('stopped: sleep', 1, true)
    and attack_tip:find('stalled', 1, true) and attack_tip:find('overdue', 1, true));
local explain = tips.text('enemy', { enemy = { holding = 'observing', waiting = true, samples = 0 } });
check('an unresolved enemy resume is never called ready', explain:find('Waiting for the next observed attack', 1, true));
s.enemy.show_value, s.enemy.show_holds, s.enemy.show_label, s.enemy.show_name, s.enemy.show_effects, s.enemy.show_delay = false, false, false, false, false, false;
s.style.show_labels, s.enemy.attached = false, false; hud.refresh(s);
MOCK.imgui_calls, MOCK.record_imgui = {}, true; hud.begin_frame(); hud.draw_enemy({ fill = 0.5, left = 2, delay = 4, holding = 'sleep', name = 'Example' }); hud.end_frame(); MOCK.record_imgui = false;
local asleep = false;
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText' and c[#c] == 'asleep') then asleep = true; end end
check('an observed control hold stays visible with optional text off', asleep);
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED'); return table.concat(out, '\n');
