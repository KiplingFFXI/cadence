-- Menu visibility choices stay separate, searchable and safe when detection is unavailable.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
addon.name = 'cadence';
local window, imgui, player = require('ui.settings_window'), require('imgui'), require('core.player');
local history = require('ui.history');
local s = require('ui.defaults').make();
local available_chat, available_menus, capability_reads = true, true, 0;
player.can_check_chat = function() capability_reads = capability_reads + 1; return available_chat; end;
player.can_check_menus = function() capability_reads = capability_reads + 1; return available_menus; end;
local selected, toggle, pressed, wanted_query, collapse = nil, nil, nil, '', false;
local disabled, depth, states = {}, 0, {};
local begin_disabled, end_disabled = imgui.BeginDisabled, imgui.EndDisabled;
rawset(imgui, 'BeginDisabled', function(off) depth = depth + 1; states[depth] = off == true or states[depth - 1] == true; return begin_disabled(off); end);
rawset(imgui, 'EndDisabled', function() states[depth] = nil; depth = depth - 1; return end_disabled(); end);
local combo, selectable, box, input, header, small = imgui.BeginCombo, imgui.Selectable, imgui.Checkbox, imgui.InputText, imgui.CollapsingHeader, imgui.SmallButton;
rawset(imgui, 'BeginCombo', function(label, value)
    disabled[label] = states[depth] == true;
    combo(label, value);
    return not states[depth] and selected and selected[1] == label;
end);
rawset(imgui, 'Selectable', function(label, ...)
    selectable(label, ...);
    return selected and selected[2] == label;
end);
rawset(imgui, 'Checkbox', function(label, value, ...)
    disabled[label] = states[depth] == true;
    if (label == toggle and not states[depth]) then value[1] = not value[1]; box(label, value, ...); return true; end
    return box(label, value, ...);
end);
rawset(imgui, 'InputText', function(label, value, ...)
    if (label == 'Find settings') then value[1] = wanted_query; end
    return input(label, value, ...);
end);
rawset(imgui, 'CollapsingHeader', function(label, ...)
    if (label == 'Menu visibility##section' and collapse) then header(label, ...); return false; end
    return header(label, ...);
end);
rawset(imgui, 'SmallButton', function(label, ...) small(label, ...); return pressed == label; end);
window.set_open(true); window.select_tab('Timers');
local function draw()
    disabled, MOCK.imgui_calls, MOCK.record_imgui = {}, {}, true;
    local result = window.draw(s, '1.4.0', false, false);
    MOCK.record_imgui = false;
    return result;
end
local function count(kind, prefix)
    local found = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == kind and tostring(call[2]):find(prefix, 1, true)) then found = found + 1; end
    end
    return found;
end
local before = history.capture(s);
local result = draw();
check('both conditions start at All timers without selected checkboxes', s.visibility.chat == 'all' and s.visibility.menus == 'all'
    and count('BeginCombo', '##visibility') == 2 and count('Checkbox', '##hide_') == 0);
check('opening the controls does not edit or save settings', history.equal(s, before) and not result.edited and not result.save);
selected = { 'Full-screen chat log##visibility', 'Selected timers' }; result = draw(); selected = nil;
check('chat selection saves only its mode with a readable undo label', result.edited and result.save and result.label == 'Full-screen chat log'
    and s.visibility.chat == 'selected' and s.visibility.menus == 'all' and count('Checkbox', '##hide_chat_') == 5);
toggle = 'Auto attack##hide_chat_attack'; result = draw(); toggle = nil;
check('a selected timer changes only its own condition', result.edited and result.save and not s.visibility.chat_attack
    and s.visibility.menus_attack and s.attack.enabled);
selected = { 'Full-screen chat log##visibility', 'Off' }; draw(); selected = nil;
check('turning a condition off preserves its selection for later', s.visibility.chat == 'off' and not s.visibility.chat_attack
    and count('Checkbox', '##hide_chat_') == 0);
selected = { 'Other menus##visibility', 'Selected timers' }; draw(); selected = nil;
check('other menus have five separate selector IDs', count('Checkbox', '##hide_menus_') == 5 and count('Checkbox', '##hide_chat_') == 0);
for _, key in ipairs({ 'attack', 'resting', 'enemy', 'recovery', 'enemycast' }) do s.visibility['menus_' .. key] = false; end
draw();
check('an empty selection is explained', count('TextUnformatted', 'No timers selected.') == 1);
available_chat, available_menus = false, false;
local kept = history.capture(s);
selected = { 'Full-screen chat log##visibility', 'All timers' }; toggle = 'Enemy cast##hide_menus_enemycast'; result = draw(); selected, toggle = nil, nil;
check('unavailable sources disable choices and preserve saved values', disabled['Full-screen chat log##visibility']
    and disabled['Other menus##visibility'] and disabled['Enemy cast##hide_menus_enemycast'] and history.equal(s, kept) and not result.edited);
available_chat, available_menus = true, true;
wanted_query = 'chat log'; draw();
check('search reveals inactive selection without enabling its checkboxes', count('Checkbox', '##hide_chat_') == 5
    and disabled['Auto attack##hide_chat_attack'] and history.equal(s, kept));
check('menu and chat queries find the Timers page', window.search_tabs('full-screen chat log').Timers
    and window.search_tabs('other menus').Timers and window.search_tabs('selected recovery').Timers);
wanted_query, pressed = '', 'Reset menu visibility'; result = draw(); pressed = nil;
check('the dedicated reset returns a visibility action without directly editing', result.reset_section == 'visibility' and history.equal(s, kept));
collapse, capability_reads = true, 0; draw();
check('a collapsed section performs no capability checks or renders controls', capability_reads == 0 and count('BeginCombo', '##visibility') == 0);
check('UI changes leave existing game visibility flags intact', s.style.hide_on_map == before.style.hide_on_map
    and s.style.hide_during_events == before.style.hide_during_events and s.style.hide_with_game_ui == before.style.hide_with_game_ui);
check('menu controls send no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
