-- Hiding with the game UI and on the map. The interface flag, the focused menu's name, the two
-- options, and how the addresses are found.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local player = require('core.player');

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
local HIDDEN_FLAG = MOCK.ui_object + 0xB4;
local FOCUS_SLOT = MOCK.ui_object + 0x54;
local function reads(addr) return MOCK.reads_at[addr] or 0; end

-- Found the way XIUI finds them, once at load.
local ui, menu = MOCK.finds.ui_check, MOCK.finds.menu_check;
check('interface pattern matches XIUI', ui and ui.name == 'FFXiMain.dll' and ui.offset == 0
    and ui.pattern == '8B4424046A016A0050B9????????E8????????F6D81BC040C3');
check('menu pattern matches XIUI', menu and menu.name == 'FFXiMain.dll' and menu.offset == 16
    and menu.pattern == '8B480C85C974??8B510885D274??3B05');
check('both can be checked', player.can_check_interface() and player.can_check_map());
check('both on by default', s.style.hide_with_game_ui == true and s.style.hide_on_map == true);

-- Engaged, the auto attack timer shows.
MOCK.now = 100;
MOCK.player.status = 1;
frames(3);
check('engaged shows the timer', windows_named('##cadence_attack') == 3);

-- Scroll Lock hides the interface, and cadence with it.
MOCK.ui_hidden = true;
frames(3);
check('hidden interface hides everything', #MOCK.imgui_calls == 0, #MOCK.imgui_calls);
MOCK.ui_hidden = false;
frames(3);
check('back with the interface', windows_named('##cadence_attack') == 3);

-- Every map view hides it. Other menus don't, the widescan list included.
for _, name in ipairs({ 'map0    ', 'mapv2   ', 'mapframe', 'maplist ', 'mapscan ' }) do
    MOCK.menu_name = name;
    frames(2);
    check(('%s hides everything'):format(name:gsub(' ', '')), #MOCK.imgui_calls == 0, #MOCK.imgui_calls);
end
for _, name in ipairs({ 'scanlist', 'inline  ', 'equip   ', 'ma      ' }) do
    MOCK.menu_name = name;
    frames(2);
    check(('%s leaves it up'):format(name:gsub(' ', '')), windows_named('##cadence_attack') == 2, windows_named('##cadence_attack'));
end
MOCK.menu_name = nil;
frames(2);
check('no menu leaves it up', windows_named('##cadence_attack') == 2);

-- The settings window hides with the map and comes back after.
MOCK.fire('command', { command = '/cadence' });
MOCK.menu_name = 'map0    ';
frames(2);
check('settings window hides on the map', windows_named('cadence##cadence_settings') == 0);
MOCK.menu_name = nil;
frames(2);
check('settings window back after the map', windows_named('cadence##cadence_settings') == 2);

-- Its checkboxes are live, since both can be checked.
local function disabled_before(label)
    for i, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'Checkbox' and c[2] == label) then
            local before = MOCK.imgui_calls[i - 1];
            return before and before[1] == 'BeginDisabled' and before[2] == true;
        end
    end
    return nil;
end
check('game UI checkbox live', disabled_before('Hide with the game UI') == false);
check('map checkbox live', disabled_before('Hide on the map') == false);
MOCK.fire('command', { command = '/cadence' });

-- Turned off, each one stays up and reads nothing.
s.style.hide_with_game_ui = false;
MOCK.ui_hidden = true;
local flag_reads = reads(HIDDEN_FLAG);
frames(3);
check('game UI option off keeps it up', windows_named('##cadence_attack') == 3);
check('game UI option off reads nothing', reads(HIDDEN_FLAG) == flag_reads, reads(HIDDEN_FLAG) - flag_reads);
MOCK.ui_hidden = false;
s.style.hide_with_game_ui = true;

s.style.hide_on_map = false;
MOCK.menu_name = 'map0    ';
local slot_reads = reads(FOCUS_SLOT);
frames(3);
check('map option off keeps it up', windows_named('##cadence_attack') == 3);
check('map option off reads nothing', reads(FOCUS_SLOT) == slot_reads, reads(FOCUS_SLOT) - slot_reads);
MOCK.menu_name = nil;
s.style.hide_on_map = true;

-- Once something hides it, the others aren't read that frame.
MOCK.in_event = true;
flag_reads, slot_reads = reads(HIDDEN_FLAG), reads(FOCUS_SLOT);
frames(3);
check('an event stops the other reads', reads(HIDDEN_FLAG) == flag_reads and reads(FOCUS_SLOT) == slot_reads);
MOCK.in_event = false;

-- A stun while the map is open still keeps its long gap out of the learned delay.
local attack = require('core.attack');
local function attack_round()
    MOCK.fire('packet_in', MOCK.action_packet(1001, 1, 0, 0x01000200, { { message = 1 } }));
end
local function run_to(t)
    while (MOCK.now < t) do MOCK.frame(1 / 60); end
end
attack.reset();
MOCK.player.status = 0;
MOCK.frame(1 / 60);
local t0 = MOCK.now;
MOCK.player.status = 1;
MOCK.frame(1 / 60);
run_to(t0 + 1.6); attack_round();
run_to(t0 + 5.6); attack_round();
MOCK.menu_name = 'map0    ';
run_to(t0 + 7.0);
MOCK.player.buffs = { 10 };
run_to(t0 + 9.0);
MOCK.player.buffs = {};
run_to(t0 + 9.5);
MOCK.menu_name = nil;
for i = 0, 3 do run_to(t0 + 10.8 + 4 * i); attack_round(); end
local _, _, in_use = attack.progress(MOCK.now);
check('a stun on the map is never learned as a slow attack', math.abs(in_use - 4.0) < 0.001, in_use);

-- Reset look leaves both alone.
s.style.hide_with_game_ui, s.style.hide_on_map = false, false;
require('ui.presets').reset(s);
check('reset look keeps both options', s.style.hide_with_game_ui == false and s.style.hide_on_map == false);
s.style.hide_with_game_ui, s.style.hide_on_map = true, true;

-- How the addresses are found. The player module is loaded fresh against each layout.
local function fresh_player()
    package.loaded['core.player'] = nil;
    return require('core.player');
end
MOCK.menu_check = 0;
local p = fresh_player();
check('no menu pattern turns off only the map', p.can_check_interface() and not p.can_check_map());
check('no menu pattern never says map', p.map_open() == false);
MOCK.menu_check = 0x1015FDF2;
MOCK.ui_check = 0;
p = fresh_player();
check('no interface pattern turns off both', not p.can_check_interface() and not p.can_check_map());
MOCK.ui_hidden, MOCK.menu_name = true, 'map0    ';
check('turned off never hides', p.interface_hidden() == false and p.map_open() == false);
MOCK.ui_hidden, MOCK.menu_name = false, nil;
MOCK.ui_check = 0x10160740;
MOCK.focus_slot = MOCK.ui_object + 0x58;
p = fresh_player();
check('a focus slot that doesn\'t line up turns off both', not p.can_check_interface() and not p.can_check_map());
MOCK.focus_slot = nil;
p = fresh_player();
check('lined up again, both are back', p.can_check_interface() and p.can_check_map());

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
