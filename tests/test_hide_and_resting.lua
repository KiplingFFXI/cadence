-- /cadence hide, when HP and MP will each be full, and hiding the resting timer once you're full.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1e-6; end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local resting = require('core.resting');
local attack = require('core.attack');
local hud = require('ui.hud');

local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do MOCK.frame(1 / 60); end
    MOCK.record_imgui = false;
end
local function windows_named(name)
    local n = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'Begin' and call[2] == name) then n = n + 1; end
    end
    return n;
end
local function said(text)
    for _, line in ipairs(MOCK.printed) do if (line:find(text, 1, true)) then return true; end end
    return false;
end

-- /cadence hide ---------------------------------------------------------------------------------
MOCK.now = 100;
MOCK.player.status = 1;
frames(2);
check('engaged shows the timer', windows_named('##cadence_attack') == 2);
MOCK.fire('command', { command = '/cadence hide' });
frames(2);
check('hide hides the timer', windows_named('##cadence_attack') == 0);
check('hide says how to bring it back', said('/cadence hide again'));
check('the timer keeps running while hidden', attack.is_active());
MOCK.fire('command', { command = '/cadence' });
frames(2);
check('the settings window still opens', windows_named('cadence##cadence_settings') == 2);
check('with no samples', windows_named('##cadence_attack') == 0 and windows_named('##cadence_resting') == 0);
local noted = false;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'TextUnformatted' and tostring(c[2]):find('timers are hidden', 1, true)) then noted = true; end
end
check('the window says they are hidden', noted);
MOCK.fire('command', { command = '/cadence' });
MOCK.fire('command', { command = '/cadence hide' });
frames(2);
check('hide again brings it back', windows_named('##cadence_attack') == 2);
MOCK.fire('command', { command = '/cadence hide' });
MOCK.fire('command', { command = '/cadence show' });
frames(2);
check('show brings it back', windows_named('##cadence_attack') == 2);
MOCK.fire('command', { command = '/cadence show' });
frames(2);
check('show when already shown keeps it', windows_named('##cadence_attack') == 2);
local saves = MOCK.saved;
MOCK.fire('command', { command = '/cadence hide' });
check('hide isn\'t saved', MOCK.saved == saves);
MOCK.fire('command', { command = '/cadence show' });
MOCK.player.status = 0;
frames(1);

-- When HP and MP will each be full ---------------------------------------------------------------
-- HP steps 1 a tick and needs 22 more ticks. MP steps 2 a tick and needs 11.
resting.reset();
resting.on_vitals(-1, 500, 100, 0, 1000, 400);
check('nothing before resting', resting.until_each_full(0) == nil);
resting.start(0);
resting.on_vitals(21.0, 510, 112, 0, 1000, 400);
local hp, mp, has_mp = resting.until_each_full(21.0);
check('unknown after one tick', hp == nil and mp == nil and has_mp == true);
resting.on_vitals(30.2, 521, 126, 0, 1000, 400);
local _, left = resting.progress(30.2);
hp, mp = resting.until_each_full(30.2);
check('HP full time', near(hp, left + 21 * 10), hp);
check('MP full time', near(mp, left + 10 * 10), mp);
check('both full is the later one', near(resting.until_full(30.2), hp));
resting.on_vitals(31.0, 1000, 400, 0, 1000, 400);
hp, mp = resting.until_each_full(31.0);
check('0 once full', hp == 0 and mp == 0 and resting.is_full());
-- One tick from full HP, with that tick running late. It's still owed, so HP isn't full yet.
resting.reset();
resting.on_vitals(-1, 970, 380, 0, 1000, 400);
resting.start(0);
resting.on_vitals(21.0, 980, 392, 0, 1000, 400);
resting.on_vitals(30.2, 991, 400, 0, 1000, 400);
local _, owed = resting.progress(30.2);
hp, mp = resting.until_each_full(30.2 + owed + 0.3);
check('a tick running late is still owed', hp ~= nil and hp > 0 and mp == 0, tostring(hp) .. ' ' .. tostring(mp));
resting.reset();
resting.on_vitals(-1, 500, 0, 0, 1000, 0);
resting.start(0);
check('a job with no MP', select(3, resting.until_each_full(0)) == false);
resting.stop();

-- The line under the resting bar.
local function line(view, width)
    s.resting.width = width or 240;
    hud.refresh(s);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.draw_resting(view);
    hud.end_frame();
    MOCK.record_imgui = false;
    local all = '|';
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText') then all = all .. c[6] .. '|'; end end
    return all;
end
local view = { fill = 0.5, left = 5, gained_hp = 24, gained_mp = 31, full = false, until_full = 95, flash = 0,
    hp_full_in = 20, mp_full_in = 95, has_mp = true };
check('off by default', not line(view):find('HP full', 1, true));
s.resting.show_each_full = true;
local _, taller = hud.element_size('resting');
local text = line(view);
check('HP and MP each get a time', text:find('|HP full in 20s|', 1, true) and text:find('|MP full in 1:35|', 1, true), text);
view.hp_full_in, view.mp_full_in = 0, nil;
text = line(view);
check('full and unknown', text:find('|HP full|', 1, true) and text:find('|MP full in --|', 1, true), text);
view.has_mp = false;
check('no MP, no MP time', not line(view):find('MP full', 1, true));
view.has_mp, view.hp_full_in, view.mp_full_in = true, 20, 95;
text = line(view, 120);
check('a narrow card gets the short times', text:find('|HP 20s|', 1, true) and text:find('|MP 1:35|', 1, true)
    and not text:find('full in 20s', 1, true), text);
MOCK.measure = function (t) return #t * 20; end
text = line(view, 120);
MOCK.measure = nil;
check('too narrow for both leaves MP off', text:find('|HP 20s|', 1, true) and not text:find('MP 1:35', 1, true), text);
s.resting.show_each_full = false;
hud.refresh(s);
check('the line makes the card taller', taller > select(2, hud.element_size('resting')));

-- Hide once full ----------------------------------------------------------------------------------
MOCK.player.status = 33;
MOCK.player.mp_max = 400;
MOCK.fire('packet_in', MOCK.vitals_packet(1001, 500, 100, 0));
frames(2);
check('resting shows', windows_named('##cadence_resting') == 2);
MOCK.fire('packet_in', MOCK.vitals_packet(1001, 1200, 400, 0));
frames(2);
check('full still shows by default', windows_named('##cadence_resting') == 2);
s.resting.hide_when_full = true;
frames(2);
check('hide once full hides it', windows_named('##cadence_resting') == 0);
MOCK.fire('packet_in', MOCK.vitals_packet(1001, 1100, 400, 0));
frames(2);
check('it comes back below full', windows_named('##cadence_resting') == 2);

local errors = nil;
for _, l in ipairs(MOCK.printed) do if (l:find('Drawing stopped')) then errors = l; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
