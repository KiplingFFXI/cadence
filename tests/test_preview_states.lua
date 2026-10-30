-- New timer states and their naming controls stay discoverable without altering live evidence.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
addon.name = 'cadence';
local window, preview, imgui = require('ui.settings_window'), require('ui.preview'), require('imgui');
local s = require('ui.defaults').make();
check('recovery offers only Normal and Unknown', #window.preview_states('recovery') == 2
    and window.valid_preview_state('recovery', 'normal') and window.valid_preview_state('recovery', 'unknown')
    and not window.valid_preview_state('recovery', 'full'));
check('casting offers only Normal and Waiting', #window.preview_states('enemycast') == 2
    and window.valid_preview_state('enemycast', 'normal') and window.valid_preview_state('enemycast', 'waiting')
    and not window.valid_preview_state('enemycast', 'blocked'));
window.set_open(true); window.select_tab('Preview');
local result = window.draw(s, '1.4.0', false, false, { timer = 'recovery', state = 'waiting', paused = false });
check('switching to a timer normalizes an incompatible old state', result.preview and result.preview.state == 'normal');
local clicked = nil;
rawset(imgui, 'SmallButton', function(label) return label == clicked; end);
for _, choice in ipairs({ { 'Timers', 'recovery', 'Recovery##label' }, { 'Enemy', 'enemycast', 'Enemy cast##label' } }) do
    window.select_tab(choice[1]); clicked = 'Edit label##' .. choice[2];
    window.draw(s, '1.4.0', false, false); clicked = nil;
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    window.draw(s, '1.4.0', false, false); MOCK.record_imgui = false;
    local found = false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'InputTextWithHint' and call[2] == choice[3]) then found = true; end
    end
    check(choice[2] .. ' label shortcut opens its Appearance field', found);
end
rawset(imgui, 'SmallButton', nil);
s.attack.enabled, s.resting.enabled, s.enemy.enabled = false, false, false;
s.recovery.enabled, s.enemycast.enabled = true, true;
s.recovery.show_value, s.recovery.show_source, s.recovery.show_label = false, false, false;
s.enemycast.show_value, s.enemycast.show_spell, s.enemycast.show_label = false, false, false;
s.style.show_labels, s.style.text_shadow, s.style.text_outline = false, false, false;
MOCK.imgui_calls, MOCK.record_imgui = {}, true;
preview.draw(s, 'unknown', true); MOCK.record_imgui = false;
local words, fills = {}, {};
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'dl:AddText') then words[#words + 1] = call[6]; end
    if (call[1] == 'dl:AddRectFilledMultiColor') then fills[#fills + 1] = call[3][1] - call[2][1]; end
end
check('inline unknown and waiting samples survive hidden ordinary readouts', table.concat(words, '|') == 'Unknown|waiting', table.concat(words, '|'));
check('unknown recovery is empty while overdue casting has completed its estimate', fills[1] == 0 and fills[2] == s.enemycast.width - 16);
s.style.bar_drains = true;
MOCK.imgui_calls, MOCK.record_imgui = {}, true;
preview.draw(s, 'unknown', true); MOCK.record_imgui = false;
fills = {};
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'dl:AddRectFilledMultiColor') then fills[#fills + 1] = call[3][1] - call[2][1]; end
end
check('unknown and waiting fills follow the live timers in drain mode', fills[1] == s.recovery.width - 16 and fills[2] == 0);
check('preview and label navigation send no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
