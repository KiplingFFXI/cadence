-- A command for every on/off box and dropdown in the settings window, undo and the three resets, what each
-- one says back, and /cadence help.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

-- A few Windows fonts, and one of your own with a space and a dash in its name.
local WINDOWS = 'C:\\Windows\\Fonts\\';
for _, file in ipairs({ 'seguisb.ttf', 'tahomabd.ttf', 'verdanab.ttf' }) do
    MOCK.fs[WINDOWS .. file] = true;
end
local FOLDER = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\fonts\\';
MOCK.fs[FOLDER] = true;
MOCK.dirs = { [FOLDER] = { 'My Font-Regular.ttf' } };
MOCK.fs[FOLDER .. 'My Font-Regular.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

-- A shared layout left over from another test would turn One layout for all characters on.
local SHARED = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\shared_layout.json';
os.remove(SHARED);

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local defaults = require('ui.defaults');
local presets = require('ui.presets');
local history = require('ui.history');
local hud = require('ui.hud');
local shared_layout = require('core.shared_layout');
local json = require('json');
local DEFAULTS = defaults.make();
MOCK.now = 100;

-- Runs a command. Returns what it printed, without the [cadence] header, and whether it was blocked.
local function said(command)
    local before = #MOCK.printed;
    local e = { command = command };
    MOCK.fire('command', e);
    local lines = {};
    for i = before + 1, #MOCK.printed do
        table.insert(lines, (MOCK.printed[i]:gsub('^%[cadence%] ', '')));
    end
    return lines, e.blocked;
end

-- Runs a command that should answer with exactly `expected` and save once.
local function answers(command, expected)
    local saves = MOCK.saved;
    local lines, blocked = said(command);
    return #lines == 1 and lines[1] == expected and MOCK.saved == saves + 1 and blocked == true,
        table.concat(lines, ' / ') .. ' saves ' .. (MOCK.saved - saves);
end

-- Runs a command that should answer with exactly `expected` and change and save nothing.
local function refuses(command, expected)
    local saves = MOCK.saved;
    local before = json.encode(s);
    local lines = said(command);
    return #lines == 1 and lines[1] == expected and MOCK.saved == saves and json.encode(s) == before,
        table.concat(lines, ' / ') .. ' saves ' .. (MOCK.saved - saves);
end

-- Every on/off box, as what you type, its section and key, what the window calls it and its checkbox label.
local TIMER = { attack = ' for the auto attack timer', resting = ' for the resting timer',
    enemy = ' for the enemy attack timer', style = '' };
local SWITCHES = {
    { 'tips', 'style', 'hover_tips', 'Timer hover help', 'Timer hover help' },
    { 'attack seconds',    'attack',  'show_value',         'Seconds left',             'Seconds left##attack' },
    { 'attack delay',      'attack',  'show_delay',         'Weapon delay',             'Weapon delay##attack' },
    { 'attack hits', 'attack', 'show_tp_hits', 'Successful hits', 'Successful hits' },
    { 'attack time', 'attack', 'show_tp_time', 'Time to TP goal', 'Time to TP goal' },
    { 'resting ticks', 'resting', 'show_ticks', 'Ticks until full', 'Ticks until full' },
    { 'resting goal', 'resting', 'show_goal', 'Recovery goal', 'Recovery goal' },
    { 'record', 'style', 'record_diagnostics', 'Record timing details', 'Record timing details' },
    { 'guides', 'style', 'layout_guides', 'Alignment guides', 'Alignment guides' },
    { 'attack tp',         'attack',  'show_tp',            'Your TP',                  'Your TP' },
    { 'attack rounds',     'attack',  'show_tp_rounds',     'Rounds to goal',           'Rounds to goal' },
    { 'attack numbers',    'attack',  'numbers_only',       'Text only',                'Text only##attack' },
    { 'attack mark',       'attack',  'almost_mark',        'Ready mark',               'Ready mark##attack' },
    { 'attack almost',     'attack',  'almost_ready',       'Almost ready',             'Almost ready##attack' },
    { 'attack range',      'attack',  'show_reason',        'Range / facing',           'Range / facing' },
    { 'attack why',        'attack',  'show_why',           'Why it stopped',           'Why it stopped' },
    { 'attack label',      'attack',  'show_label',         'Show its name',            '##show_label_attack' },
    { 'resting seconds',   'resting', 'show_value',         'Seconds left',             'Seconds left##resting' },
    { 'resting gains',     'resting', 'show_gains',         'Last tick gains',          'Last tick gains##resting' },
    { 'resting nextgains', 'resting', 'show_next_gains',    'Next tick gains',          'Next tick gains##resting' },
    { 'resting untilfull', 'resting', 'show_until_full',    'Time until full',          'Time until full##resting' },
    { 'resting fulltimes', 'resting', 'show_each_full',     'Full times',               'Full times##resting' },
    { 'resting numbers',   'resting', 'numbers_only',       'Text only',                'Text only##resting' },
    { 'resting hidefull',  'resting', 'hide_when_full',     'Hide once full',           'Hide once full##resting' },
    { 'resting flash',     'resting', 'flash_on_tick',      'Flash on each tick',       'Flash on each tick' },
    { 'resting why',       'resting', 'show_why',           'Why it can\'t heal',       'Why it can\'t heal' },
    { 'resting sound',     'resting', 'sound',              'Sound',                    '##sound' },
    { 'resting label',     'resting', 'show_label',         'Show its name',            '##show_label_resting' },
    { 'hideevents',        'style',   'hide_during_events', 'Hide during events',       'Hide during events' },
    { 'hidemap',           'style',   'hide_on_map',        'Hide on the map',          'Hide on the map' },
    { 'hideui',            'style',   'hide_with_game_ui',  'Hide with the game UI',    'Hide with the game UI' },
    { 'enemy keeplast',    'enemy',   'keep_last',          'Keep the last monster',    'Keep the last monster' },
    { 'enemy attach',      'enemy',   'attached',           'Attach under auto attack', 'Attach under auto attack' },
    { 'enemy seconds',     'enemy',   'show_value',         'Seconds left',             'Seconds left##enemy' },
    { 'enemy name',        'enemy',   'show_name',          'Enemy name',               'Enemy name' },
    { 'enemy speed',       'enemy',   'show_delay',         'Attack speed',             'Attack speed##enemy' },
    { 'enemy effects',     'enemy',   'show_effects',       'Slow and haste',           'Slow and haste' },
    { 'enemy tpmove',      'enemy',   'show_holds',         'TP move / casting',        'TP move / casting' },
    { 'enemy onyou',       'enemy',   'show_on_you',        'On you',                   'On you' },
    { 'enemy numbers',     'enemy',   'numbers_only',       'Text only',                'Text only##enemy' },
    { 'enemy mark',        'enemy',   'almost_mark',        'Ready mark',               'Ready mark##enemy' },
    { 'enemy almost',      'enemy',   'almost_ready',       'Almost ready',             'Almost ready##enemy' },
    { 'enemy label',       'enemy',   'show_label',         'Show its name',            '##show_label_enemy' },
    { 'windowlook',        'style',   'window_matches_look', 'Window matches the look', 'Window matches the look' },
    { 'labels',            'style',   'show_labels',        'Show labels',              'Show labels' },
    { 'background',        'style',   'panel',              'Background',               'Background' },
    { 'border',            'style',   'border',             'Border',                   'Border' },
    { 'accent',            'style',   'accent',             'Accent stripe',            'Accent stripe' },
    { 'outline',           'style',   'text_outline',       'Text outline',             'Text outline' },
    { 'shadow',            'style',   'text_shadow',        'Text shadow',              'Text shadow' },
    { 'drain',             'style',   'bar_drains',         'Drain instead of fill',    'Drain instead of fill' },
    { 'onespot',           'style',   'shared_spot',        'Share one spot',           'Share one spot' },
    { 'peek',              'style',   'see_through',        'Peek with Shift',          'Peek with Shift' },
};

-- Every box in the window has a command --------------------------------------------------------------
-- The mock opens every tab at once, so one frame draws every box and dropdown.
local imgui = require('imgui');
MOCK.fire('command', { command = '/cadence' });
MOCK.imgui_calls = {};
MOCK.record_imgui = true;
MOCK.frame(1 / 60);
MOCK.record_imgui = false;
MOCK.fire('command', { command = '/cadence' });
local by_box = {
    ['Lock in place'] = 'lock|unlock',
    ['One layout for all characters'] = 'onelayout',
    ['Pause preview'] = 'preview pause|resume',
    ['Inline preview'] = 'preview inline',
    ['Enabled only##attack'] = 'temporary readout filter',
    ['Enabled only##resting'] = 'temporary readout filter',
    ['Enabled only##enemy'] = 'temporary readout filter',
};
for _, name in ipairs({ 'Timers', 'Enemy', 'Preview', 'Details', 'Profiles' }) do
    by_box[name .. '##visible_tab'] = 'tab ' .. name .. ' on|off';
end
for _, switch in ipairs(SWITCHES) do by_box[switch[5]] = switch[1]; end
local boxes, missing, combos = 0, {}, {};
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'Checkbox') then
        boxes = boxes + 1;
        if (by_box[c[2]] == nil) then table.insert(missing, c[2]); end
    elseif (c[1] == 'BeginCombo') then
        table.insert(combos, c[2]);
    end
end
check('the window drew its boxes', boxes == #SWITCHES + 12, boxes);
check('every saved box has a command and temporary filters are accounted for', #missing == 0, table.concat(missing, ', '));
-- Each job link's list is named by its job after ##, like ##BLM. /cadence joblink sets them.
local job_lists = {};
for _, job in ipairs(defaults.JOBS) do table.insert(job_lists, '##' .. job); end
check('the dropdowns cover timer goals, appearance, preview state and each job link', table.concat(combos, ',')
    == 'TP goal##attack,Sound##resting,Follows##enemy,State##inline_preview,Preset,Font,Font##window,Tag brackets,Tag word,Replies,'
    .. 'Timer##preview,State##preview,Resource##goal,Measure##goal,Starter layout,' .. table.concat(job_lists, ','), table.concat(combos, ','));

-- Switches ---------------------------------------------------------------------------------------------
local wrong = {};
local function note(ok, what) if (not ok) then table.insert(wrong, what); end end
for _, switch in ipairs(SWITCHES) do
    local command, section, key, name = switch[1], switch[2], switch[3], switch[4];
    local default = DEFAULTS[section][key];
    local first, second = default and 'off' or 'on', default and 'on' or 'off';
    local ok, detail = answers('/cadence ' .. command .. ' ' .. first, ('%s is %s%s.'):format(name, first, TIMER[section]));
    note(ok and s[section][key] == not default, command .. ' ' .. first .. ': ' .. detail);
    ok, detail = answers('/cadence ' .. command .. ' ' .. first, ('%s is %s%s.'):format(name, first, TIMER[section]));
    note(ok and s[section][key] == not default, command .. ' ' .. first .. ' twice: ' .. detail);
    ok, detail = answers('/cadence ' .. command .. ' ' .. second, ('%s is %s%s.'):format(name, second, TIMER[section]));
    note(ok and s[section][key] == default, command .. ' ' .. second .. ': ' .. detail);
    ok, detail = answers('/cadence ' .. command, ('%s is %s%s.'):format(name, first, TIMER[section]));
    note(ok and s[section][key] == not default, command .. ' with no word flips it: ' .. detail);
    ok, detail = answers('/cadence ' .. command, ('%s is %s%s.'):format(name, second, TIMER[section]));
    note(ok and s[section][key] == default, command .. ' flips back: ' .. detail);
    local usage = command == 'resting goal'
        and 'Type /cadence resting goal hp|mp|both percent|amount <whole number>. Percent is 1 to 100.'
        or ('Type /cadence %s on|off.'):format(command);
    ok, detail = refuses('/cadence ' .. command .. ' maybe', usage);
    note(ok and s[section][key] == default, command .. ' maybe: ' .. detail);
end
check('every switch sets, flips and says what it did, and a wrong word gets its own line', #wrong == 0,
    table.concat(wrong, ' | '));

check('a timer\'s part works while the timer is off', (function ()
    MOCK.fire('command', { command = '/cadence attack off' });
    local ok = answers('/cadence attack why off', 'Why it stopped is off for the auto attack timer.');
    local result = ok and s.attack.show_why == false and s.attack.enabled == false;
    MOCK.fire('command', { command = '/cadence attack on' });
    MOCK.fire('command', { command = '/cadence attack why on' });
    return result;
end)());
check('any case works', answers('/CADENCE Attack TP Off', 'Your TP is off for the auto attack timer.')
    and s.attack.show_tp == false);
check('so does /cad', answers('/cad attack tp ON', 'Your TP is on for the auto attack timer.') and s.attack.show_tp);
check('extra words after on|off are ignored', answers('/cadence shadow off please', 'Text shadow is off.')
    and s.style.text_shadow == false);
MOCK.fire('command', { command = '/cadence shadow on' });

-- A change reaches the timers right away.
local _, height = hud.element_size('attack');
MOCK.fire('command', { command = '/cadence background off' });
local _, bare = hud.element_size('attack');
check('Background off redraws the timers without the card', bare < height, height .. ' to ' .. bare);
MOCK.fire('command', { command = '/cadence background on' });
local _, back = hud.element_size('attack');
check('and on puts it back', back == height, back);

-- The timer words themselves ----------------------------------------------------------------------------
check('/cadence attack off still turns the timer off', answers('/cadence attack off', 'The auto attack timer is off.')
    and s.attack.enabled == false);
check('/cadence attack on', answers('/cadence attack on', 'The auto attack timer is on.') and s.attack.enabled);
check('/cadence attack flips it', answers('/cadence attack', 'The auto attack timer is off.') and not s.attack.enabled);
MOCK.fire('command', { command = '/cadence attack on' });
local ATTACK_USAGE = 'Type /cadence attack on|off, /cadence attack goal 1000|2000|3000, /cadence attack <part> on|off, /cadence attack <slider> <number> '
    .. 'or /cadence attack labeltext <text>. The parts are seconds, delay, tp, time, hits, rounds, numbers, mark, almost, range, '
    .. 'why and label. The sliders are width, height, barheight and almostat.';
local ok, detail = refuses('/cadence attack wat', ATTACK_USAGE);
check('a wrong part gets the attack usage line and doesn\'t flip the timer', ok and s.attack.enabled, detail);
ok, detail = refuses('/cadence resting gain on', 'Type /cadence resting on|off, /cadence resting <part> on|off, '
    .. '/cadence resting <slider> <number>, /cadence resting labeltext <text>, /cadence resting soundfile <name> or '
    .. '/cadence resting playsound. The parts are goal, seconds, gains, ticks, nextgains, untilfull, fulltimes, numbers, hidefull, flash, why, '
    .. 'sound and label. The sliders are width, height, barheight, flashlength and soundvolume.');
check('a wrong resting part', ok, detail);
ok, detail = refuses('/cadence enemy follows hits', 'Type /cadence enemy on|off, /cadence enemy follow '
    .. 'first|target|hits, /cadence enemy <part> on|off, /cadence enemy <slider> <number> or /cadence enemy '
    .. 'labeltext <text>. The parts are keeplast, attach, seconds, name, speed, effects, tpmove, onyou, numbers, mark, '
    .. 'almost and label. The sliders are width, height, barheight and almostat.');
check('a wrong enemy part names follow too', ok, detail);
ok, detail = refuses('/cadence wat', 'Didn\'t recognize "wat". Type /cadence help to see the commands.');
check('an unknown word gets one line, not the whole help', ok, detail);
ok, detail = refuses('/cadence tp off', 'Didn\'t recognize "tp". Type /cadence help to see the commands.');
check('a timer\'s part needs its timer\'s word', ok, detail);
ok, detail = refuses('/cadence attack shadow off', ATTACK_USAGE);
check('and a style word isn\'t a timer\'s part', ok, detail);

-- Follows -----------------------------------------------------------------------------------------------
for _, case in ipairs({ { 'hits', 'attacker', 'Whoever hits me' }, { 'target', 'target', 'My target only' },
        { 'FIRST', 'target_first', 'My target first' } }) do
    check('follow ' .. case[1], answers('/cadence enemy follow ' .. case[1], 'Follows is set to ' .. case[3] .. '.')
        and s.enemy.which == case[2], s.enemy.which);
end
ok, detail = refuses('/cadence enemy follow attacker', 'Type /cadence enemy follow first|target|hits.');
check('a wrong Follows word gets its own line', ok, detail);
ok, detail = refuses('/cadence enemy follow', 'Type /cadence enemy follow first|target|hits.');
check('so does no word', ok, detail);

-- Goal and preview commands keep display choices separate from temporary sample state.
check('a percent recovery goal saves its resource and value', answers('/cadence resting goal mp percent 75',
    'Your recovery goal is MP 75%.') and s.resting.goal_stat == 'mp' and s.resting.goal_mode == 'percent'
    and s.resting.goal_value == 75 and s.resting.show_goal);
check('a fixed recovery goal can follow both resources', answers('/cadence resting goal both amount 500',
    'Your recovery goal is HP/MP 500.') and s.resting.goal_stat == 'both' and s.resting.goal_mode == 'amount'
    and s.resting.goal_value == 500);
for _, words in ipairs({ 'hp percent 101', 'mp amount 0', 'mp amount 100000', 'mp percent 33.5', 'tp percent 50' }) do
    ok, detail = refuses('/cadence resting goal ' .. words,
        'Type /cadence resting goal hp|mp|both percent|amount <whole number>. Percent is 1 to 100.');
    check('invalid recovery goal ' .. words .. ' preserves the saved choice', ok, detail);
end
for _, words in ipairs({ 'enemy waiting', 'pause', 'resume', 'resting full', 'auto normal' }) do
    local before, saves = json.encode(s), MOCK.saved;
    local lines, blocked = said('/cadence preview ' .. words);
    check('preview ' .. words .. ' stays temporary', #lines == 0 and blocked and MOCK.saved == saves
        and json.encode(s) == before and require('ui.settings_window').is_open());
end
ok, detail = refuses('/cadence preview enemy invalid', 'Preview states are normal, blocked, waiting and full.');
check('an invalid preview state keeps settings intact', ok, detail);
require('ui.settings_window').set_open(false);

-- Presets and Undo ----------------------------------------------------------------------------------------
history.clear(s);
check('Phoenix to start', presets.current(s) == 'Phoenix');
ok, detail = refuses('/cadence undo', 'There is no settings change to undo in this session.');
check('nothing to undo yet', ok, detail);
check('/cadence preset minimal', answers('/cadence preset minimal', 'The Minimal preset is on. /cadence undo takes it back.')
    and presets.current(s) == 'Minimal', presets.current(s));
ok, detail = refuses('/cadence preset Minimal', 'You already have the Minimal preset.');
check('the preset you already have does nothing', ok, detail);
check('so Undo still goes back past it', answers('/cadence undo',
    'Undid Command: preset minimal.') and presets.current(s) == 'Phoenix',
    presets.current(s));
ok, detail = refuses('/cadence undo', 'There is no settings change to undo in this session.');
check('Undo consumes the one change made since clearing history', ok, detail);
-- A changed look is Custom from the preset it came from, and naming that preset puts its look back.
MOCK.fire('command', { command = '/cadence preset minimal' });
s.style.value_color[1] = 0.25;
MOCK.fire('command', { command = '/cadence shadow on' });
check('naming the preset your look came from puts its look back', answers('/cadence preset minimal',
    'The Minimal preset is on. /cadence undo takes it back.') and presets.current(s) == 'Minimal'
    and s.style.value_color[1] == 1, presets.current(s));
check('and Undo brings back your change', answers('/cadence undo',
    'Undid Command: preset minimal.') and presets.current(s) == nil
    and s.style.value_color[1] == 0.25 and s.style.window_look == 'minimal', s.style.window_look);
for _, case in ipairs({ { 'classic', 'Classic FFXI' }, { 'contrast', 'High contrast' }, { 'ember', 'Ember' },
        { 'colorblind', 'Colorblind safe' }, { 'phoenix', 'Phoenix' }, { 'High Contrast', 'High contrast' },
        { 'classicffxi', 'Classic FFXI' }, { 'EMBER', 'Ember' }, { 'COLORBLIND SAFE', 'Colorblind safe' } }) do
    check('preset ' .. case[1], answers('/cadence preset ' .. case[1], ('The %s preset is on. /cadence undo takes it back.')
        :format(case[2])) and presets.current(s) == case[2], presets.current(s));
end
check('each preset goes through Undo', presets.can_undo());
MOCK.fire('command', { command = '/cadence preset phoenix' });
for _, words in ipairs({ 'nope', '', 'high' }) do
    ok, detail = refuses('/cadence preset ' .. words,
        'Type /cadence preset phoenix|classic|minimal|contrast|ember|mint|lavender|colorblind.');
    check('preset "' .. words .. '" gets its own line', ok, detail);
end

-- Fonts -------------------------------------------------------------------------------------------------
for _, case in ipairs({ { 'tahoma bold', 'Tahoma Bold' }, { 'verdanabold', 'Verdana Bold' },
        { 'SEGOE UI SEMIBOLD', 'Segoe UI Semibold' }, { 'my font regular', 'My Font-Regular' },
        { '"Tahoma Bold"', 'Tahoma Bold' } }) do
    check('font ' .. case[1], answers('/cadence font ' .. case[1], ('The timers use the %s font now.'):format(case[2]))
        and s.style.system_font and s.style.font_name == case[2] and hud.font_in_use() == case[2], hud.font_in_use());
end
check('font ashita', answers('/cadence font ashita', 'The timers use the Ashita font now.')
    and s.style.system_font == false and s.style.font_name == 'Tahoma Bold' and hud.font_in_use() == nil);
check('a font after Ashita turns the list back on', answers('/cadence font verdana bold',
    'The timers use the Verdana Bold font now.') and s.style.system_font and hud.font_in_use() == 'Verdana Bold');
local FONT_USAGE = 'Type /cadence font <name>. The fonts are Ashita, Segoe UI Semibold, Tahoma Bold, Verdana Bold '
    .. 'and My Font-Regular.';
ok, detail = refuses('/cadence font comic sans', FONT_USAGE);
check('a font that isn\'t there gets its own line with the list', ok, detail);
ok, detail = refuses('/cadence font', FONT_USAGE);
check('so does no name', ok, detail);
MOCK.fire('command', { command = '/cadence font segoe ui semibold' });

-- With no fonts found, like on Linux without Tahoma, Ashita's own is the only one.
local found = hud.font_names();
local kept_fonts = { unpack(found) };
for i = #found, 1, -1 do found[i] = nil; end
ok, detail = refuses('/cadence font tahoma', 'Type /cadence font <name>. The fonts are Ashita.');
check('with no fonts found the list is just Ashita', ok, detail);
for i, name in ipairs(kept_fonts) do found[i] = name; end

-- Resets ------------------------------------------------------------------------------------------------
s.style.scale = 1.5;
s.attack.show_tp = false;
s.attack.x, s.attack.y = 300, 200;
MOCK.fire('command', { command = '/cadence shadow off' });
check('plain reset puts back positions only', answers('/cadence reset', 'The timers are back at their default positions.')
    and s.attack.x == DEFAULTS.attack.x and s.style.scale == 1.5 and s.style.text_shadow == false
    and s.attack.show_tp == false, s.attack.x .. ' ' .. s.style.scale);
s.attack.x = 300;
check('reset look', answers('/cadence reset look', 'The look is back to default. /cadence undo takes it back.')
    and s.style.scale == 1.0 and s.style.text_shadow == true and s.attack.x == 300 and s.attack.show_tp == false,
    s.style.scale);
check('Undo takes back reset look', answers('/cadence undo',
    'Undid Command: reset look.') and s.style.scale == 1.5
    and s.style.text_shadow == false);
ok, detail = refuses('/cadence reset everything', 'Type /cadence reset, /cadence reset look or /cadence reset all.');
check('a wrong reset word gets its own line', ok, detail);

-- A screen too short for the default spots, so the timers have to stack higher up.
MOCK.screen = { 1024, 700 };
MOCK.fire('command', { command = '/cadence preset minimal' });
s.enemy.enabled, s.enemy.which, s.window.x = true, 'attacker', 333;
local before = json.encode(s);
local saves = MOCK.saved;
local lines = said('/cadence reset all');
check('reset all asks first and changes nothing', #lines == 1 and lines[1] == 'This puts every setting back to its '
    .. 'default, including where the timers sit and which ones are on, and clears your job links. Your saved profiles '
    .. 'stay. Type /cadence reset all again within 10 seconds to go ahead.' and json.encode(s) == before
    and MOCK.saved == saves, lines[1]);
MOCK.now = MOCK.now + 11;
lines = said('/cadence reset all');
check('after 10 seconds it asks again', #lines == 1 and lines[1]:find('again within 10 seconds', 1, true) ~= nil
    and json.encode(s) == before, lines[1]);
MOCK.now = MOCK.now + 9;
check('a second one within 10 seconds does it', answers('/cadence reset all',
    'Every setting is back to its default and your job links are cleared. Your saved profiles are still there.'));
local differ = {};
for name, section in pairs(DEFAULTS) do
    for key, value in pairs(section) do
        local mine = s[name][key];
        local same = mine == value;
        if (type(value) == 'table') then same = json.encode(mine) == json.encode(value) and mine ~= value; end
        if (not same and key ~= 'x' and key ~= 'y' and name ~= 'window') then table.insert(differ, name .. '.' .. key); end
    end
end
check('every setting is its default, in tables of its own', #differ == 0, table.concat(differ, ', '));
check('the settings window keeps its spot', s.window.x == 333, s.window.x);
local spots = json.encode({ s.attack.x, s.attack.y, s.resting.x, s.resting.y, s.enemy.x, s.enemy.y });
check('the timers start higher on the short screen', s.resting.y < DEFAULTS.resting.y, s.resting.y);
MOCK.fire('command', { command = '/cadence reset' });
check('the timers are stacked like Reset positions', json.encode({ s.attack.x, s.attack.y, s.resting.x, s.resting.y,
    s.enemy.x, s.enemy.y }) == spots, spots);
MOCK.screen = nil;
check('the look is Phoenix again', presets.current(s) == 'Phoenix');
ok, detail = refuses('/cadence undo', 'There is no settings change to undo in this session.');
check('and Undo has nothing left from before', ok, detail);
lines = said('/cadence reset all');
check('the next reset all asks again', #lines == 1 and lines[1]:find('again within 10 seconds', 1, true) ~= nil, lines[1]);

-- One layout for all characters -----------------------------------------------------------------------
local function shared_file()
    local file = io.open(SHARED, 'r');
    if (file == nil) then return nil; end
    local text = file:read('*a');
    file:close();
    return json.decode(text);
end
local layout_ok, layout_err = pcall(function ()
    saves = MOCK.saved;
    lines = said('/cadence onelayout on');
    check('onelayout on', #lines == 1 and lines[1] == 'One layout for all characters is on.' and shared_layout.is_on()
        and shared_file() ~= nil, lines[1]);
    check('it writes the shared file like the box does, not your own', MOCK.saved == saves);
    MOCK.fire('command', { command = '/cadence enemy speed off' });
    local data = shared_file();
    check('a command then saves the shared copy too', data and data.settings.enemy.show_delay == false);
    MOCK.fire('command', { command = '/cadence enemy speed on' });
    check('reset all keeps it on', (function ()
        MOCK.now = MOCK.now + 11;
        MOCK.fire('command', { command = '/cadence reset all' });
        MOCK.fire('command', { command = '/cadence reset all' });
        return shared_layout.is_on() and shared_file() ~= nil;
    end)());
    ok, detail = refuses('/cadence onelayout yes', 'Type /cadence onelayout on|off.');
    check('a wrong word', ok and shared_layout.is_on(), detail);
    lines = said('/cadence onelayout');
    check('no word flips it off and deletes the file', #lines == 1 and lines[1] == 'One layout for all characters is off.'
        and not shared_layout.is_on() and shared_file() == nil, lines[1]);
    lines = said('/cadence onelayout');
    check('and on again', lines[1] == 'One layout for all characters is on.' and shared_layout.is_on());
    lines = said('/cadence onelayout off');
    check('onelayout off', lines[1] == 'One layout for all characters is off.' and shared_file() == nil);
end);
os.remove(SHARED);
check('the shared layout part ran', layout_ok, layout_err);

-- Help --------------------------------------------------------------------------------------------------
local help = said('/cadence help');
local where = {};
for i, line in ipairs(help) do where[line] = i; end
local function line_with(text)
    for i, line in ipairs(help) do if (line:find(text, 1, true)) then return i; end end
    return nil;
end
local timers, enemy, look = where['Timers tab'], where['Enemy tab'], where['Appearance tab'];
check('help is grouped by tab', timers ~= nil and enemy ~= nil and look ~= nil and timers < enemy and enemy < look,
    tostring(timers) .. ' ' .. tostring(enemy) .. ' ' .. tostring(look));
check('it starts with the window', (help[1] or ''):find('/cadence  opens or closes the settings window.', 1, true) == 1);
check('and says a switch flips without on|off', (help[1] or ''):find('Leave out on|off and a switch flips.', 1, true));
local function under(text, from, to)
    local at = line_with(text);
    return at ~= nil and at > from and at < (to or #help + 1);
end
check('Timers tab lines', under('/cadence attack|resting <part> [on|off]', timers, enemy)
    and under('/cadence hideevents|hidemap|hideui [on|off]  sets Hide during events, Hide on the map or Hide with '
        .. 'the game UI.', timers, enemy));
check('Enemy tab lines', under('/cadence enemy follow first|target|hits  sets Follows to My target first, My target '
    .. 'only or Whoever hits me.', enemy, look) and under('/cadence enemy <part> [on|off]', enemy, look));
check('Appearance tab lines', under('/cadence preset phoenix|classic|minimal|contrast|ember|mint|lavender|colorblind', look)
    and under('/cadence font <name>', look) and under('/cadence attack|resting|enemy label [on|off]', look)
    and under('/cadence tips|record|windowlook|labels|background|border|accent|outline|shadow|drain|onespot|onelayout|peek [on|off]  '
        .. 'sets Timer hover help, Record timing details, Window matches the look, Show labels, Background, Border, '
        .. 'Accent stripe, Text outline, Text shadow, '
        .. 'Drain instead of fill, Share one spot, One layout for all characters or Peek with Shift.', look));
check('commands that aren\'t on a tab come before the tabs', line_with('/cadence hide|show') < timers
    and line_with('/cadence info') < timers and line_with('/cadence help attack') < timers);
check('so does turning a timer on or off, since each timer\'s chip is on its own tab',
    line_with('/cadence attack|resting|enemy [on|off]  turns a timer on or off.') < timers);
check('the name switch says what it does', under('/cadence attack|resting|enemy label [on|off]  shows or hides that '
    .. 'timer\'s name.', look));
check('help lists lock, hide and reset', line_with('/cadence lock|unlock') and line_with('/cadence hide|show')
    and line_with('/cadence reset [look|all]  puts every timer back at its default position'));
check('it says where to find more', line_with('/cadence help attack|resting|enemy|appearance|colors|preset|font|reset|'
    .. 'chatcolors|profiles|preview|details|ui  tells you more about one of them.'));
check('it stays short enough to read in the chat log', #help <= 20, #help);

-- Each timer's help names every part, with its name in the window when that's a different word.
local missing_parts = {};
for _, switch in ipairs(SWITCHES) do
    local timer, part = switch[1]:match('^(%a+) (%a+)$');
    if (timer ~= nil) then
        local text = table.concat(said('/cadence help ' .. timer), ' ');
        local named = part:lower() == switch[4]:lower():gsub('[^%w]', '') and part or (part .. ' (' .. switch[4] .. ')');
        if (not text:find(named, 1, true)) then table.insert(missing_parts, named); end
    elseif (switch[1] == 'tips') then
        local text = table.concat(said('/cadence help window'), ' ');
        if (not text:find('/cadence tips [on|off]', 1, true)) then table.insert(missing_parts, switch[1]); end
    elseif (not table.concat(help, ' '):find(switch[1], 1, true)) then
        table.insert(missing_parts, switch[1]);
    end
end
check('every switch is in the help', #missing_parts == 0, table.concat(missing_parts, ', '));
-- The lines after the parts, for the sliders, the label and the colors, are in test_setting_commands.lua.
lines = said('/cadence help attack');
check('help attack', #lines == 9 and lines[1] == '/cadence attack [on|off]  turns the auto attack timer on or off.'
    and lines[2] == '/cadence attack goal 1000|2000|3000  sets TP goal to 1000, 2000 or 3000.'
    and lines[3]:find('/cadence attack <part> [on|off]  sets one of its boxes. The parts are seconds (Seconds left), '
        .. 'delay (Weapon delay), tp (Your TP), time (Time to TP goal), hits (Successful hits), rounds (Rounds to goal)', 1, true) == 1, lines[2]);
lines = said('/cadence help enemy');
check('help enemy has Follows', #lines == 9 and lines[2]:find('/cadence enemy follow first|target|hits', 1, true) == 1);
lines = said('/cadence help preview');
check('preview help explains temporary samples and goal controls', #lines == 7
    and lines[1]:find('/cadence preview auto|attack|resting|enemy', 1, true) == 1
    and lines[5]:find('/cadence resting goal hp|mp|both percent|amount', 1, true) == 1
    and lines[7]:find('/cadence relearn attack|tp|enemy', 1, true) == 1);
check('Details help includes the same relearning controls', table.concat(said('/cadence help details'), '|') == table.concat(lines, '|'));
lines = said('/cadence help preset');
check('help preset', #lines == 2 and lines[1] == '/cadence preset <name>  picks a preset, the same as the Preset list. '
    .. 'The presets are phoenix, classic (Classic FFXI), minimal, contrast (High contrast), ember, mint, lavender and colorblind '
    .. '(Colorblind safe).' and lines[2]:find('/cadence undo', 1, true) == 1, lines[1]);
check('help undo is the same', table.concat(said('/cadence help undo'), '|') == table.concat(lines, '|'));
lines = said('/cadence help font');
check('help font lists the fonts', #lines == 1 and lines[1] == '/cadence font <name>  picks the font, with or without its '
    .. 'spaces. The fonts are Ashita, Segoe UI Semibold, Tahoma Bold, Verdana Bold and My Font-Regular.', lines[1]);
lines = said('/cadence help reset');
check('help reset', #lines == 3 and lines[1]:find('/cadence reset  ', 1, true) == 1
    and lines[2]:find('/cadence reset look  ', 1, true) == 1
    and lines[3] == '/cadence reset all  puts every setting back to its default and clears your job links. Your saved '
        .. 'profiles stay. Type it twice within 10 seconds.', lines[3]);
check('help with another word is the whole help', table.concat(said('/cadence help lock'), '|') == table.concat(help, '|'));
check('help changes and saves nothing', (function ()
    local saves_now, state = MOCK.saved, json.encode(s);
    said('/cadence help');
    said('/cadence help attack');
    return MOCK.saved == saves_now and json.encode(s) == state;
end)());

-- What chat says reads like everything else in cadence.
local odd = nil;
for _, line in ipairs(MOCK.printed) do
    if (line:find(';', 1, true) or line:find('\226\128\148', 1, true) or line:find('\226\128\147', 1, true)
        or line:lower():find('element', 1, true)) then
        odd = line;
    end
end
check('no semicolons, dashes or "element" in anything said', odd == nil, odd);

-- Nothing broke while drawing with the window open.
MOCK.fire('command', { command = '/cadence' });
for _ = 1, 3 do MOCK.frame(1 / 60); end
MOCK.fire('command', { command = '/cadence' });
local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
