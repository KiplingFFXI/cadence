-- Timer commands refresh warm inline and starter-layout samples without applying the sample.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local window, navigation = require('ui.settings_window'), require('ui.navigation');
navigation.draw = MOCK.real_navigation_draw;
local s = MOCK.settings.current;
local function command(words) MOCK.fire('command', { command = '/cadence ' .. words }); end
command('shadow off');
window.set_open(true); window.select_tab('Appearance'); window.set_inline_preview(true);
local function sample_labels()
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    local found = {};
    for _, c in ipairs(MOCK.imgui_calls) do
        -- Live samples include "(preview)"; only the embedded samples use these bare labels.
        if (c[1] == 'dl:AddText') then found[c[6]] = true; end
    end
    return found;
end
local labels = sample_labels();
check('inline samples start with attack and resting enabled', labels['AUTO ATTACK'] and labels.RESTING);
command('attack off'); labels = sample_labels();
check('disabling attack removes it from the warm inline sample', not s.attack.enabled and not labels['AUTO ATTACK'] and labels.RESTING);
command('attack on'); labels = sample_labels();
check('enabling attack restores it in the warm inline sample', s.attack.enabled and labels['AUTO ATTACK']);
command('resting'); labels = sample_labels();
check('bare timer toggles also refresh the sample', not s.resting.enabled and not labels.RESTING);
command('resting on'); sample_labels();
command('layout preview minimal'); labels = sample_labels();
check('a starter preview begins without recovery or enemy cast', not labels['ACTION RECOVERY'] and not labels['ENEMY CAST']);
command('recovery on'); labels = sample_labels();
check('enabling recovery refreshes the cached starter copy it preserves', s.recovery.enabled and labels['ACTION RECOVERY']);
command('enemycast on'); labels = sample_labels();
check('enabling enemy cast refreshes the cached starter copy it preserves', s.enemycast.enabled and labels['ENEMY CAST']);
command('recovery off'); labels = sample_labels();
check('disabling recovery removes it from the cached starter copy', not s.recovery.enabled and not labels['ACTION RECOVERY'] and labels['ENEMY CAST']);
command('enemycast off'); labels = sample_labels();
check('disabling enemy cast removes it from the cached starter copy', not s.enemycast.enabled and not labels['ENEMY CAST']);
command('attack off'); labels = sample_labels();
check('refreshing a starter preview retains that layout\'s proposed attack setting without applying it',
    not s.attack.enabled and labels['AUTO ATTACK']);
local error_seen = false;
for _, line in ipairs(MOCK.printed) do error_seen = error_seen or line:find('Drawing stopped', 1, true) ~= nil; end
check('command preview refresh raises no drawing error or game command', not error_seen and #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or failed .. ' FAILED';
return table.concat(out, '\n');
