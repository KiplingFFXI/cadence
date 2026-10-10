-- Workflow controls return actions; samples and navigation do not edit saved choices.
local out, fails = {}, 0;
local function check(name, ok) out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name; if (not ok) then fails = fails + 1; end end
addon.name = 'cadence';
local imgui = require('imgui');
local window, nav = require('ui.settings_window'), require('ui.navigation');
local history, profiles = require('ui.history'), require('ui.profiles');
local s = require('ui.defaults').make();
nav.draw = MOCK.real_navigation_draw;
window.set_open(true);
local before = history.capture(s);
local pressed, toggled;
local button, small, checkbox = imgui.Button, imgui.SmallButton, imgui.Checkbox;
rawset(imgui, 'Button', function (name, ...) if (pressed == name) then pressed = nil; return true; end return button(name, ...); end);
rawset(imgui, 'SmallButton', function (name, ...) if (pressed == name) then pressed = nil; return true; end return small(name, ...); end);
rawset(imgui, 'Checkbox', function (name, value, ...) if (toggled == name) then toggled = nil; value[1] = not value[1]; return true; end return checkbox(name, value, ...); end);
local function draw(tab)
    if (tab) then window.select_tab(tab); end
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    local result = window.draw(s, '1.2.0', false, false, nil, {
        attack = { delay = 3, source = 'observed' }, tp = { per_hit = 80, source = 'modeled' },
        resting = { next_hp = 20, next_mp = 30 }, enemy = { delay = 4 },
    });
    MOCK.record_imgui = false;
    return result;
end
local function seen(kind, text)
    for _, call in ipairs(MOCK.imgui_calls) do if (call[1] == kind and call[2] == text) then return true; end end
    return false;
end
local r = draw('Appearance');
check('Appearance includes static timer and chat samples', seen('BeginCombo', 'State##inline_preview') and seen('Checkbox', 'Inline preview'));
check('opening samples does not mutate settings or return a save', history.equal(before, s) and not r.save and not r.edited);
pressed = 'Restore all tabs'; draw();
check('restoring tabs already shown is not an edit', not r.edited);
window.set_inline_preview(false); draw();
check('inline preview can hide without changing saved settings', not seen('BeginCombo', 'State##inline_preview') and history.equal(before, s));
window.set_inline_preview(true);
check('layout command rejects unknown names', not window.preview_layout('no such layout'));
check('layout preview opens Profiles', window.preview_layout('resting') and nav.current() == 'Profiles');
r = draw();
check('layout preview lists changes and uses samples', seen('Button', 'Apply layout') and seen('BeginCombo', 'State##inline_preview'));
check('previewed layout stays separate from current settings', history.equal(before, s) and not r.edited and not r.apply_layout);
pressed = 'Apply layout'; r = draw();
check('Apply returns the chosen layout for main', r.apply_layout == 'resting' and history.equal(before, s));
pressed = 'Undo overwrite'; r = draw();
check('profile overwrite recovery returns an action', r.undo_overwrite == true);
pressed = 'Reset this section'; r = draw('Enemy');
check('section reset identifies the current tab without changing it', r.reset_section == 'enemy' and history.equal(before, s));
pressed = 'Undo last change'; r = draw();
check('general Undo returns an action', r.undo_settings == true);

s.attack.show_delay = false;
window.invalidate_preview();
draw('Timers');
check('compact readouts retain their original checkbox IDs', seen('Checkbox', 'Seconds left##attack') and seen('Checkbox', 'Weapon delay##attack'));
toggled = 'Enabled only##attack'; r = draw();
check('Enabled only filters unchecked readouts without editing them', not seen('Checkbox', 'Weapon delay##attack') and not r.edited and not s.attack.show_delay);
toggled = 'Enabled only##attack'; draw();
pressed = 'Options##readout_attack_show_tp'; draw();
check('narrow row options reveal the contextual Details link', seen('SmallButton', 'Details##readout_attack_show_tp'));
pressed = 'Details##readout_attack_show_tp'; draw();
check('a readout Details action opens the correct page', nav.current() == 'Details' and window.needs_details());
draw();
check('TP details show the TP section only', seen('CollapsingHeader', 'TP') and not seen('CollapsingHeader', 'ENEMY'));
pressed = 'Clear##details'; draw();
check('clearing a contextual jump restores every section', seen('CollapsingHeader', 'ENEMY'));
check('details reject unsupported section names', not window.open_details('unknown'));
window.open_details('attack'); draw();
check('attack Details includes its source and applied speed sections', seen('CollapsingHeader', 'AUTO ATTACK'));
toggled = 'Weapon delay##attack'; r = draw('Timers');
check('a readout edit returns its visible label for history', r.edited and r.save and r.label == 'Weapon delay' and s.attack.show_delay);

local header = imgui.CollapsingHeader;
rawset(imgui, 'CollapsingHeader', function (name, ...) if (name == 'TEXT##window_colors##section') then return false; end return header(name, ...); end);
draw('Appearance');
check('a window color subgroup folds without closing the others', not seen('ColorEdit4', '##text') and seen('ColorEdit4', '##buttons'));
rawset(imgui, 'CollapsingHeader', header);

profiles.save(s, 'UI baseline'); draw('Appearance');
check('the toolbar identifies the loaded or saved profile', seen('TextUnformatted', 'Using UI baseline'));
s.attack.show_value = not s.attack.show_value; profiles.invalidate_status(s); draw();
check('the toolbar identifies changes from that profile', seen('TextUnformatted', 'Modified from UI baseline'));
profiles.delete(s, 'UI baseline');
rawset(imgui, 'Button', button); rawset(imgui, 'SmallButton', small); rawset(imgui, 'Checkbox', checkbox);
out[#out + 1] = fails == 0 and 'ALL PASSED' or fails .. ' FAILED';
return table.concat(out, '\n');
