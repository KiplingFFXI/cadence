-- Unfinished edits and repeated sharing commands keep the right Undo boundaries.
local out, fails = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then fails = fails + 1; end
end
local root = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\';
os.remove(root .. 'shared_layout.json'); os.remove(root .. 'profiles.json');
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.watch_settings(); MOCK.fire('load');
local history, window = require('ui.history'), require('ui.settings_window');
local function command(text) MOCK.fire('command', { command = '/cadence ' .. text }); end
local function held_scale(value)
    window.set_open(true);
    local real_draw = window.draw;
    window.draw = function (s)
        s.style.scale = value;
        return { changed = true, save = false, label = 'Scale' };
    end;
    MOCK.frame();
    window.draw = real_draw;
end

for _, shared in ipairs({ false, true }) do
    command('onelayout ' .. (shared and 'on' or 'off'));
    local s = MOCK.in_use;
    history.clear(s);
    local width = s.attack.width;
    command('attack width 310');
    local entry = history.status(s);
    command('onelayout ' .. (shared and 'on' or 'off'));
    check('same-mode sharing keeps owner and Undo (' .. tostring(shared) .. ')', MOCK.in_use == s and history.status(s) == entry);
    command('undo');
    check('the retained change still restores its original value (' .. tostring(shared) .. ')', s.attack.width == width);

    local scale, tp = s.style.scale, s.attack.show_tp;
    held_scale(1.4);
    command('attack tp off');
    command('undo');
    check('Undo of a command leaves the preceding slider edit (' .. tostring(shared) .. ')', s.style.scale == 1.4 and s.attack.show_tp == tp);
    check('the slider keeps its own history label (' .. tostring(shared) .. ')', history.status(s) == 'Scale');
    command('undo');
    check('the next Undo restores the complete slider edit (' .. tostring(shared) .. ')', s.style.scale == scale and history.status(s) == nil);

    held_scale(1.6);
    local printed = #MOCK.printed;
    command('undo');
    check('Undo during a held edit restores its start (' .. tostring(shared) .. ')', s.style.scale == scale and history.status(s) == nil);
    check('held-edit Undo names the edited control (' .. tostring(shared) .. ')', #MOCK.printed == printed + 1 and MOCK.printed[#MOCK.printed]:find('Undid Scale.', 1, true));
end
local s = MOCK.in_use;
local scale = s.style.scale;
held_scale(1.7);
local real_draw = window.draw;
window.draw = function () return { editing = true }; end;
MOCK.frame();
check('a keyboard edit remains pending while its input is active', history.status(s) == nil);
window.draw = function () return { editing = false }; end;
MOCK.frame();
check('an edit completes when its original control is no longer active or submitted', history.status(s) == 'Scale');
MOCK.frame();
command('undo');
check('completion and later idle frames record exactly one Undo step', s.style.scale == scale and history.status(s) == nil);
window.draw = real_draw;
check('settings transactions send no game commands', #MOCK.commands == 0);
os.remove(root .. 'shared_layout.json'); os.remove(root .. 'profiles.json');
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
