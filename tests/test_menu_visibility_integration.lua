-- Menu hiding changes drawing only, with separate per-timer choices and saved settings.
local out, failed = {}, 0;
local function check(name, yes)
    out[#out + 1] = (yes and 'ok   ' or 'FAIL ') .. name;
    if (not yes) then failed = failed + 1; end
end
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local s = MOCK.settings.current;
local player, attack = require('core.player'), require('core.attack');
local chat, menus, map = false, false, false;
player.menu_visibility = function (want_chat, want_menus, want_map)
    return want_chat and chat, want_menus and menus, want_map and map;
end;
local timers = { 'attack', 'resting', 'enemy', 'recovery', 'enemycast' };
for _, timer in ipairs(timers) do s[timer].enabled = true; end
local function command(words) MOCK.fire('command', { command = '/cadence ' .. words }); end
command('');
local function frame()
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    local shown = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'Begin') then shown[call[2]] = true; end
    end
    return shown;
end
local function visible_count(shown)
    local count = 0;
    for _, timer in ipairs(timers) do if (shown['##cadence_' .. timer]) then count = count + 1; end end
    return count;
end
check('both menu conditions default to all timers', s.visibility.chat == 'all' and s.visibility.menus == 'all');
check('all five samples show without a native menu', visible_count(frame()) == 5);
chat = true;
local shown = frame();
check('full-screen chat hides all five timers', visible_count(shown) == 0);
check('settings remain available to adjust menu hiding', shown['cadence##cadence_settings']);
chat, menus = false, true;
check('other menus hide all five timers', visible_count(frame()) == 0);
for _, context in ipairs({ 'chat', 'menus' }) do
    chat, menus = context == 'chat', context == 'menus';
    s.visibility[context] = 'selected';
    for _, selected in ipairs(timers) do
        for _, timer in ipairs(timers) do s.visibility[context .. '_' .. timer] = timer == selected; end
        shown = frame();
        check(context .. ' hides only ' .. selected, visible_count(shown) == 4 and not shown['##cadence_' .. selected]);
    end
    for _, timer in ipairs(timers) do s.visibility[context .. '_' .. timer] = false; end
    check(context .. ' selected with no choices hides nothing', visible_count(frame()) == 5);
    s.visibility[context] = 'off';
    check(context .. ' off leaves all timers visible', visible_count(frame()) == 5);
end
s.visibility.chat, s.visibility.menus = 'selected', 'selected';
s.visibility.chat_attack, s.visibility.menus_resting = true, true;
chat, menus = true, true;
shown = frame();
check('overlapping conditions combine selected timers', visible_count(shown) == 3
    and not shown['##cadence_attack'] and not shown['##cadence_resting']);
s.recovery.attached, s.enemy.attached, s.enemycast.attached = true, true, true;
menus = false;
shown = frame();
check('hiding an attachment parent keeps its unselected children visible', shown['##cadence_recovery']
    and shown['##cadence_enemy'] and shown['##cadence_enemycast'] and not shown['##cadence_attack']);
chat, menus = false, false;
check('closing the menu restores every sample', visible_count(frame()) == 5);
s.visibility.chat, s.visibility.menus = 'off', 'off'; map = true;
check('existing map hiding still applies independently', visible_count(frame()) == 0);
s.style.hide_on_map = false;
check('turning off map hiding restores the samples', visible_count(frame()) == 5);
map = false;

command('visibility chat off');
command('visibility chat attack on');
check('per-timer command selects its mask', s.visibility.chat == 'selected' and s.visibility.chat_attack);
command('undo');
check('visibility commands participate in Undo', s.visibility.chat == 'off');
command('visibility menus all'); command('visibility chat selected');
command('visibility chat resting off');
local profiles = require('ui.profiles');
check('profiles save menu modes and masks', profiles.save(s, 'Menu choices', true));
command('visibility chat all');
check('profile load restores the choices', profiles.load(s, 'Menu choices')
    and s.visibility.chat == 'selected' and not s.visibility.chat_resting);
command('visibility chat off'); command('visibility menus off');
command('resetsection visibility');
check('visibility reset restores both conditions', s.visibility.chat == 'all' and s.visibility.menus == 'all');
command('undo');
check('visibility reset can be undone', s.visibility.chat == 'off' and s.visibility.menus == 'off');
local saved = MOCK.saved;
command('visibility chat invalid'); command('visibility map all'); command('visibility menus attack invalid');
check('invalid visibility commands never save', MOCK.saved == saved);
local copy = require('ui.defaults').make();
copy.visibility.chat, copy.visibility.menus, copy.visibility.chat_attack = 'bad', {}, 'bad';
require('ui.defaults').tidy(copy);
check('invalid saved values return to safe defaults', copy.visibility.chat == 'all' and copy.visibility.menus == 'all'
    and copy.visibility.chat_attack == true);
local shared = require('core.shared_layout');
command('visibility menus selected'); command('visibility menus enemy off');
local shared_settings = shared.turn_on(s);
check('shared layouts carry menu choices', shared_settings.visibility.menus == 'selected'
    and not shared_settings.visibility.menus_enemy);
local restored = shared.apply(require('ui.defaults').make());
check('a fresh shared-layout load keeps menu choices', restored.visibility.menus == 'selected'
    and not restored.visibility.menus_enemy);
shared.turn_off(s);

require('ui.settings_window').set_open(false);
MOCK.player.status = 0; frame(); MOCK.player.status = 1; frame();
chat, s.visibility.chat = true, 'all';
MOCK.fire('packet_in', MOCK.action_packet(1001, 1, 0, 0x01000200, { { message = 1 } }));
local left = select(2, attack.progress(MOCK.now));
MOCK.frame(0.5);
check('hidden attack countdown keeps advancing', select(2, attack.progress(MOCK.now)) < left);
local errors = false;
for _, line in ipairs(MOCK.printed) do errors = errors or line:find('Drawing stopped', 1, true) ~= nil; end
check('menu visibility draws without errors or game commands', not errors and #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
