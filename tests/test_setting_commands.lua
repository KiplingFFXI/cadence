-- A command for every slider, color and label in the settings window. Each slider's command and the
-- slider set the same setting over the same range. Each command goes through its range and past both
-- ends, with decimal places and auto where its slider has them. Then each timer color by its word, each
-- timer's own label, what each one says back, and the help lines that list them.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

-- A shared layout left over from another test would turn One layout for all characters on.
os.remove(MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\shared_layout.json');

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local imgui = require('imgui');
local hud = require('ui.hud');
local theme = require('ui.theme');
local presets = require('ui.presets');
local json = require('json');
MOCK.now = 100;

-- Runs a command. Returns what it printed, without the [cadence] header, and an error as a line of its own.
local function said(command)
    local before = #MOCK.printed;
    local ran, err = pcall(MOCK.fire, 'command', { command = command });
    local lines = {};
    for i = before + 1, #MOCK.printed do table.insert(lines, (MOCK.printed[i]:gsub('^%[cadence%] ', ''))); end
    if (not ran) then table.insert(lines, 'error ' .. tostring(err)); end
    return lines;
end
-- Runs a command that should answer with exactly `expected` and save once.
local function answers(command, expected)
    local saves = MOCK.saved;
    local lines = said(command);
    return #lines == 1 and lines[1] == expected and MOCK.saved == saves + 1,
        table.concat(lines, ' / ') .. ' saves ' .. (MOCK.saved - saves);
end
-- Runs a command that should answer with exactly `expected` and change and save nothing.
local function refuses(command, expected)
    local saves, state = MOCK.saved, json.encode(s);
    local lines = said(command);
    return #lines == 1 and lines[1] == expected and MOCK.saved == saves and json.encode(s) == state,
        table.concat(lines, ' / ') .. ' saves ' .. (MOCK.saved - saves);
end
-- Draws frames with the settings window open, recording what ImGui was asked to draw.
local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n or 1 do MOCK.frame(1 / 60); end
    MOCK.record_imgui = false;
end
-- The last call to `name` with `label` in the frames just drawn.
local function last(name, label)
    local found = nil;
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == name and c[2] == label) then found = c; end end
    return found;
end

MOCK.fire('command', { command = '/cadence' });

--[[
    Every slider on the Timers, Enemy and Appearance tabs. Its label, what you type, its section and key, its
    lowest and highest number, one in between, its decimal places, whether its left end is auto, and the
    answer with %s for the number. The Window section's sliders are tested in test_window_tabs.lua, so they
    only come into the check that every slider has a command.
]]
local SLIDERS = {
    { 'Width##enemycast', 'enemycast width', 'enemycast', 'width', 120, 640, 320, 0, false,
        'The enemy cast timer\'s width is set to %s px.' },
    { 'Height##enemycast', 'enemycast height', 'enemycast', 'height_scale', 0.5, 2.5, 1.25, 2, false,
        'The enemy cast timer\'s height is set to %sx.' },
    { 'Bar height##enemycast', 'enemycast barheight', 'enemycast', 'bar_height', 2, 32, 8, 0, false,
        'The enemy cast timer\'s bar height is set to %s px.' },
    { 'Width##recovery', 'recovery width', 'recovery', 'width', 120, 640, 320, 0, false,
        'The action recovery timer\'s width is set to %s px.' },
    { 'Height##recovery', 'recovery height', 'recovery', 'height_scale', 0.5, 2.5, 1.25, 2, false,
        'The action recovery timer\'s height is set to %sx.' },
    { 'Bar height##recovery', 'recovery barheight', 'recovery', 'bar_height', 2, 32, 8, 0, false,
        'The action recovery timer\'s bar height is set to %s px.' },
    { 'Width##attack', 'attack width', 'attack', 'width', 120, 640, 300, 0, false,
        'The auto attack timer\'s width is set to %s px.' },
    { 'Height##attack', 'attack height', 'attack', 'height_scale', 0.5, 2.5, 1.25, 2, false,
        'The auto attack timer\'s height is set to %sx.' },
    { 'Bar height##attack', 'attack barheight', 'attack', 'bar_height', 2, 32, 9, 0, false,
        'The auto attack timer\'s bar height is set to %s px.' },
    { 'Almost ready at##attack', 'attack almostat', 'attack', 'almost_seconds', 0.1, 2.0, 1.3, 1, false,
        'The auto attack bar turns the almost ready color %s s before your attack.' },
    { 'Width##resting', 'resting width', 'resting', 'width', 120, 640, 333, 0, false,
        'The resting timer\'s width is set to %s px.' },
    { 'Height##resting', 'resting height', 'resting', 'height_scale', 0.5, 2.5, 1.5, 2, false,
        'The resting timer\'s height is set to %sx.' },
    { 'Bar height##resting', 'resting barheight', 'resting', 'bar_height', 2, 32, 12, 0, false,
        'The resting timer\'s bar height is set to %s px.' },
    { 'Flash length', 'resting flashlength', 'resting', 'flash_seconds', 0.2, 1.5, 0.8, 1, false,
        'The flash on each resting tick lasts %s s.' },
    { 'Volume##sound', 'resting soundvolume', 'resting', 'sound_volume', 0, 100, 40, 0, false,
        'The resting sound\'s volume is set to %s%%.' },
    { 'Width##enemy', 'enemy width', 'enemy', 'width', 120, 640, 280, 0, false,
        'The enemy attack timer\'s width is set to %s px.' },
    { 'Height##enemy', 'enemy height', 'enemy', 'height_scale', 0.5, 2.5, 0.75, 2, false,
        'The enemy attack timer\'s height is set to %sx.' },
    { 'Bar height##enemy', 'enemy barheight', 'enemy', 'bar_height', 2, 32, 7, 0, false,
        'The enemy attack timer\'s bar height is set to %s px.' },
    { 'Almost ready at##enemy', 'enemy almostat', 'enemy', 'almost_seconds', 0.1, 2.0, 0.7, 1, false,
        'The enemy bar turns the almost ready color %s s before the monster attacks.' },
    { 'Scale', 'scale', 'style', 'scale', 0.5, 2.5, 1.25, 2, false, 'The timers\' scale is set to %sx.' },
    { 'Text size', 'textsize', 'style', 'font_size', 10, 28, 16, 0, false,
        'The timers\' text size is set to %s px.' },
    { 'Detail size', 'detailsize', 'style', 'detail_size', 8, 32, 11, 0, true,
        'The timers\' detail size is set to %s px.' },
    { 'Label size', 'labelsize', 'style', 'label_size', 8, 32, 13, 0, true,
        'The timers\' label size is set to %s px.' },
    { 'Corner roundness', 'corners', 'style', 'rounding', 0, 12, 5, 0, false,
        'The timers\' corner roundness is set to %s px.' },
};
local COMMAND_OF = { ['Font size##window'] = 'windowfontsize', ['Corner roundness##window'] = 'windowcorners',
    ['Spacing##window'] = 'windowspacing', ['Goal##recovery'] = 'resting goal mp percent' };
for _, row in ipairs(SLIDERS) do COMMAND_OF[row[1]] = row[2]; end

-- Each slider and its command set the same thing --------------------------------------------------------
frames(1);
local drawn = {};
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'SliderInt' or c[1] == 'SliderFloat') then table.insert(drawn, c); end
end
check('the window drew every slider', #drawn == #SLIDERS + 4, #drawn);
-- A command takes a slider's highest number with the decimal places the slider shows, and its lowest, or
-- auto when that end is auto. Its answer shows the number the same way. One step past either end is
-- refused. The next frame's slider shows what the command set.
local function says_number(line, number)
    return line:find(' ' .. number:gsub('%.', '%%.') .. '%D') ~= nil;
end
local uncommanded, unequal = {}, {};
for _, c in ipairs(drawn) do
    local label, low, high, format = c[2], c[4], c[5], c[6];
    local command = COMMAND_OF[label];
    if (command == nil) then
        table.insert(uncommanded, label);
    else
        local places = tonumber(format:match('%%%.(%d)f')) or 0;
        local step = 10 ^ -places;
        local function typed(value) return ('%.' .. places .. 'f'):format(value); end
        local auto = format == 'auto';
        local top = said('/cadence ' .. command .. ' ' .. typed(high))[1] or '';
        frames(1);
        local shown_high = last(c[1], label)[3][1];
        local bottom = said('/cadence ' .. command .. ' ' .. (auto and 'auto' or typed(low)))[1] or '';
        frames(1);
        local shown_low = last(c[1], label)[3][1];
        local past_low = #said('/cadence ' .. command .. ' ' .. typed(auto and low or low - step));
        local past_high = #said('/cadence ' .. command .. ' ' .. typed(high + step));
        frames(1);
        local refused = last(c[1], label)[3][1] == shown_low;
        local low_ok = auto and (shown_low < low + 1 and bottom:find(' auto.', 1, true) ~= nil)
            or (shown_low == low and says_number(bottom, typed(low)));
        if (not (shown_high == high and says_number(top, typed(high)) and low_ok and past_low == 1
            and past_high == 1 and refused)) then
            table.insert(unequal, ('%s: %s, %s'):format(label, top, bottom));
        end
    end
end
check('every slider in the window has a command', #uncommanded == 0, table.concat(uncommanded, ', '));
check('which sets it over the same range with the same decimal places', #unequal == 0, table.concat(unequal, ' | '));
MOCK.fire('command', { command = '/cadence resting goal mp amount 99999' });
frames(1);
local goal_slider = last('SliderInt', 'Goal##recovery');
check('an amount goal uses its separate slider range and command', goal_slider and goal_slider[3][1] == 99999
    and goal_slider[4] == 1 and goal_slider[5] == 99999);
presets.reset(s);
presets.forget_undo();

-- The number commands, each through its whole range and past both ends ------------------------------------
local wrong = {};
local function note(ok, what) if (not ok) then table.insert(wrong, what); end end
for _, row in ipairs(SLIDERS) do
    local command, section, key, low, high, mid, places, auto, answer = row[2], row[3], row[4], row[5], row[6], row[7],
        row[8], row[9], row[10];
    local step = 10 ^ -places;
    local function typed(value) return ('%.' .. places .. 'f'):format(value); end
    for _, value in ipairs({ low, high, mid }) do
        local ok, detail = answers(('/cadence %s %s'):format(command, typed(value)), answer:format(typed(value)));
        note(ok and s[section][key] == value, command .. ' ' .. typed(value) .. ': ' .. detail);
    end
    local usage = ('Type /cadence %s <%s-%s>%s.'):format(command, typed(low), typed(high), auto and '|auto' or '');
    local bad = { typed(low - step), typed(high + step), 'big', '' };
    if (places == 0) then table.insert(bad, mid .. '.5'); end
    for _, word in ipairs(bad) do
        local ok, detail = refuses(('/cadence %s %s'):format(command, word), usage);
        note(ok and s[section][key] == mid, ('%s "%s": %s'):format(command, word, detail));
    end
    if (places > 0) then
        -- More decimal places than the slider shows get rounded to what it shows.
        local more = ('%.' .. (places + 1) .. 'f'):format(mid + step * 0.4);
        local ok, detail = answers(('/cadence %s %s'):format(command, more), answer:format(typed(mid)));
        note(ok and s[section][key] == mid, command .. ' ' .. more .. ': ' .. detail);
    end
    if (auto) then
        local ok, detail = answers(('/cadence %s AUTO'):format(command), (answer:gsub('%%s px', 'auto')));
        note(ok and s[section][key] == 0, command .. ' auto: ' .. detail);
        ok, detail = refuses(('/cadence %s %d'):format(command, low - 1), usage);
        note(ok, command .. ' below its smallest number: ' .. detail);
        MOCK.fire('command', { command = ('/cadence %s %s'):format(command, mid) });
    end
end
check('every number command sets its number, says what it did and refuses what its slider can\'t take', #wrong == 0,
    table.concat(wrong, ' | '));

check('any case works', answers('/CADENCE Attack WIDTH 410', 'The auto attack timer\'s width is set to 410 px.')
    and s.attack.width == 410);
check('so does /cad', answers('/cad Scale 1.5', 'The timers\' scale is set to 1.50x.') and s.style.scale == 1.5);
-- A whole number written with a decimal point is still whole. The guide says what's refused.
local guide_file = assert(io.open(ADDON_DIR .. '/../docs/GUIDE.md'));
local guide = guide_file:read('*a');
guide_file:close();
check('a whole-number slider takes 300.0, and the guide refuses only a number that isn\'t whole',
    answers('/cadence attack width 300.0', 'The auto attack timer\'s width is set to 300 px.') and s.attack.width == 300
    and guide:find('or a number that isn\'t whole for a slider that only takes whole numbers', 1, true) ~= nil
    and not guide:find('decimal point', 1, true));
check('a timer\'s slider works while the timer is off', (function ()
    MOCK.fire('command', { command = '/cadence enemy off' });
    local ok = answers('/cadence enemy barheight 20', 'The enemy attack timer\'s bar height is set to 20 px.');
    return ok and s.enemy.bar_height == 20 and s.enemy.enabled == false;
end)());

-- A slider word needs its timer's word, and a timer only takes its own sliders.
local RESTING_USAGE = 'Type /cadence resting on|off, /cadence resting <part> on|off, /cadence resting <slider> '
    .. '<number>, /cadence resting labeltext <text>, /cadence resting soundfile <name> or /cadence resting playsound. '
    .. 'The parts are goal, seconds, gains, ticks, nextgains, untilfull, fulltimes, numbers, hidefull, flash, why, sound and label. The '
    .. 'sliders are width, height, barheight, flashlength and soundvolume.';
local ok, detail = refuses('/cadence resting almostat 1', RESTING_USAGE);
check('resting has no almostat', ok, detail);
ok, detail = refuses('/cadence attack flashlength 1', 'Type /cadence attack on|off, /cadence attack goal 1000|2000|3000, /cadence attack <part> on|off, '
    .. '/cadence attack <slider> <number> or /cadence attack labeltext <text>. The parts are seconds, delay, reengage, tp, time, hits, rounds, '
    .. 'numbers, mark, almost, range, why and label. The sliders are width, height, barheight and almostat.');
check('and attack has no flashlength', ok, detail);
ok, detail = refuses('/cadence width 300', 'Didn\'t recognize "width". Type /cadence help to see the commands.');
check('width needs a timer\'s word', ok, detail);
ok, detail = refuses('/cadence resting scale 2', RESTING_USAGE);
check('and scale isn\'t a timer\'s', ok, detail);

-- A number reaches the timers right away.
MOCK.fire('command', { command = '/cadence scale 1' });
local small = hud.element_size('attack');
MOCK.fire('command', { command = '/cadence scale 2' });
local big = hud.element_size('attack');
check('a scale command redraws the timers at that size', big > small * 1.8, small .. ' to ' .. big);
-- Corner roundness is part of a preset. Scale isn't.
presets.apply(s, 'Phoenix');
MOCK.fire('command', { command = '/cadence scale 1.5' });
check('a size command keeps the preset', presets.current(s) == 'Phoenix', presets.current(s));
MOCK.fire('command', { command = '/cadence corners 5' });
check('a corners command makes the look Custom', presets.current(s) == nil, presets.current(s));
presets.reset(s);
presets.forget_undo();

-- Colors ----------------------------------------------------------------------------------------------------
-- Every timer color, as its word, its section and key, and its swatch's label in the window.
local COLORS = {
    { 'enemycast_fill_start', 'enemycast', 'fill_start', '##enemycast_start' },
    { 'enemycast_fill_end', 'enemycast', 'fill_end', '##enemycast_end' },
    { 'recovery_fill_start', 'recovery', 'fill_start', '##recovery_start' },
    { 'recovery_fill_end', 'recovery', 'fill_end', '##recovery_end' },
    { 'attack_tp',          'attack',  'tp_color',      '##tp_colorYour TP' },
    { 'attack_fill_start',  'attack',  'fill_start',    '##attack_start' },
    { 'attack_fill_end',    'attack',  'fill_end',      '##attack_end' },
    { 'attack_ready',       'attack',  'ready_color',   'Ready##attack' },
    { 'attack_almost',      'attack',  'almost_color',  '##almost_colorAlmost ready##attack' },
    { 'resting_fill_start', 'resting', 'fill_start',    '##resting_start' },
    { 'resting_fill_end',   'resting', 'fill_end',      '##resting_end' },
    { 'resting_full',       'resting', 'full_color',    'Full HP/MP##resting' },
    { 'resting_flash',      'resting', 'flash_color',   '##flash_colorFlash on each tick' },
    { 'enemy_on_you',       'enemy',   'on_you_color',  '##on_you_colorOn you' },
    { 'enemy_fill_start',   'enemy',   'fill_start',    '##enemy_start' },
    { 'enemy_fill_end',     'enemy',   'fill_end',      '##enemy_end' },
    { 'enemy_ready',        'enemy',   'ready_color',   'Ready##enemy' },
    { 'enemy_almost',       'enemy',   'almost_color',  '##almost_colorAlmost ready##enemy' },
    { 'background',         'style',   'panel_color',   '##panel_colorBackground' },
    { 'border',             'style',   'border_color',  '##border_colorBorder' },
    { 'accent',             'style',   'accent_color',  '##accent_colorAccent stripe' },
    { 'labels',             'style',   'label_color',   'Labels##text' },
    { 'values',             'style',   'value_color',   'Values##text' },
    { 'details',            'style',   'detail_color',  'Details##text' },
    { 'bar_track',          'style',   'track_color',   'Bar track##text' },
    { 'outline',            'style',   'outline_color', '##outline_colorText outline' },
};
-- The settings window's own colors have swatches named ## and their key, on the Window colors section.
local WINDOW_SWATCH = {};
for _, entry in ipairs(theme.WINDOW_COLORS) do WINDOW_SWATCH['##' .. entry.key] = true; end
-- Each timer color swatch drawn this frame, by its label, with the table it edits.
local swatches = {};
rawset(imgui, 'ColorEdit4', function (label, value)
    if (not WINDOW_SWATCH[label]) then swatches[label] = value; end
    return false;
end);
local function swatch_frame()
    swatches = {};
    frames(1);
    return swatches;
end
swatch_frame();
local by_label, count, odd = {}, 0, {};
for _, color in ipairs(COLORS) do by_label[color[4]] = color; end
for label, value in pairs(swatches) do
    count = count + 1;
    local color = by_label[label];
    if (color == nil or not rawequal(value, s[color[2]][color[3]])) then table.insert(odd, label); end
end
check('every timer color swatch has a color word for the setting it edits', #odd == 0 and count == #COLORS,
    table.concat(odd, ', ') .. ' of ' .. count);

local unset = {};
for _, color in ipairs(COLORS) do
    local word, section, key = color[1], color[2], color[3];
    local said_ok = answers('/cadence color ' .. word .. ' 336699', ('The %s color is set to 336699.'):format(word));
    local c = s[section][key];
    local shown = swatch_frame()[color[4]];
    if (not said_ok or c[1] ~= 0x33 / 255 or c[2] ~= 0x66 / 255 or c[3] ~= 0x99 / 255 or c[4] ~= 1
        or not rawequal(shown, c)) then
        table.insert(unset, word);
    end
end
check('color sets every one, says so and its swatch shows it', #unset == 0, table.concat(unset, ', '));
rawset(imgui, 'ColorEdit4', nil);

ok, detail = answers('/cadence color ATTACK_TP #FFCC0080', 'The attack_tp color is set to ffcc0080.');
local tp = s.attack.tp_color;
check('in any case, with a # and how solid it is', ok and tp[1] == 1 and tp[2] == 0xcc / 255 and tp[3] == 0
    and tp[4] == 0x80 / 255, detail);
-- A color reaches the timers right away. The sample values draw while the window is open.
MOCK.fire('command', { command = '/cadence color values ff0000' });
frames(1);
local red_text = false;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'dl:AddText' and c[5] == theme.u32(theme.hex('ff0000'))) then red_text = true; end
end
check('and the timers draw in it', red_text);
check('a color command makes the look Custom', presets.current(s) == nil, presets.current(s));
local COLOR_USAGE = 'Type /cadence color <what> <rrggbb>. /cadence help colors lists the colors.';
for _, command in ipairs({ '/cadence color', '/cadence color attack_tp' }) do
    ok, detail = refuses(command, COLOR_USAGE);
    check('"' .. command .. '" gets the usage line', ok, detail);
end
for _, word in ipairs({ 'tp', 'buttons', 'attack' }) do
    ok, detail = refuses('/cadence color ' .. word .. ' 336699', ('There\'s no color called "%s". /cadence help colors '
        .. 'lists them.'):format(word));
    check('"' .. word .. '" isn\'t a timer color', ok, detail);
end
for _, bad in ipairs({ '33669', '3366991', 'zz6699', '#', '336699ccc' }) do
    ok, detail = refuses('/cadence color values ' .. bad, ('"%s" isn\'t a color. Type six hex digits like c55151, or '
        .. 'eight like c55151cc to make it see-through.'):format(bad));
    check('"' .. bad .. '" isn\'t a color', ok, detail);
end
presets.reset(s);
presets.forget_undo();

-- Labels ----------------------------------------------------------------------------------------------------
-- Optional timers start off, and only a timer that's on draws its sample.
MOCK.fire('command', { command = '/cadence enemy on' });
MOCK.fire('command', { command = '/cadence recovery on' });
MOCK.fire('command', { command = '/cadence enemycast on' });
-- Each label box in the window, by the timer it names.
-- Leave room for the preview marker as well as the custom label and live detail fields.
for _, timer in ipairs({ 'attack', 'resting', 'enemy', 'recovery', 'enemycast' }) do
    MOCK.fire('command', { command = '/cadence ' .. timer .. ' width 640' });
end
local BOXES = { attack = 'Auto attack##label', resting = 'Resting##label', enemy = 'Enemy##label',
    recovery = 'Recovery##label', enemycast = 'Enemy cast##label' };
local function box_text(key)
    frames(1);
    local c = last('InputTextWithHint', BOXES[key]);
    return c and c[4][1];
end
-- True when the timers draw `text` this frame.
local function drawn_text(text)
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddText' and c[6] == text .. ' (preview)') then return true; end
    end
    return false;
end
frames(1);
local boxes = 0;
for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'InputTextWithHint') then boxes = boxes + 1; end end
check('the window has a label box for each timer', boxes == 5, boxes);
for _, case in ipairs({ { 'attack', 'Aa', 'The auto attack timer' }, { 'resting', 'Heal Me', 'The resting timer' },
        { 'enemy', 'Big Mob', 'The enemy attack timer' }, { 'recovery', 'Next cast', 'The action recovery timer' },
        { 'enemycast', 'Casting', 'The enemy cast timer' } }) do
    local key, label, timer = case[1], case[2], case[3];
    ok, detail = answers(('/cadence %s labeltext %s'):format(key, label), ('%s\'s label is set to "%s".')
        :format(timer, label));
    check(key .. ' labeltext keeps its capitals and needs no quotes', ok and s[key].label_text == label, detail);
    check('its box shows it and the timer draws it', box_text(key) == label and drawn_text(label), box_text(key));
end
ok, detail = answers('/cadence attack labeltext "My AA"', 'The auto attack timer\'s label is set to "My AA".');
check('quotes work too', ok and s.attack.label_text == 'My AA', detail);
for _, case in ipairs({ { 'attack', 'The auto attack timer', 'AUTO ATTACK' }, { 'resting', 'The resting timer', 'RESTING' },
        { 'enemy', 'The enemy attack timer', 'ENEMY ATTACK' },
        { 'recovery', 'The action recovery timer', 'ACTION RECOVERY' },
        { 'enemycast', 'The enemy cast timer', 'ENEMY CAST' } }) do
    ok, detail = answers(('/cadence %s labeltext ""'):format(case[1]), ('%s\'s label is back to %s.')
        :format(case[2], case[3]));
    check(case[1] .. ' labeltext "" puts its own name back', ok and s[case[1]].label_text == '' and box_text(case[1]) == ''
        and drawn_text(case[3]), detail);
end
MOCK.fire('command', { command = '/cadence enemy attach on' });
ok, detail = answers('/cadence enemy labeltext ""', 'The enemy attack timer\'s label is back to ENEMY.');
check('attached, the enemy timer\'s own name is ENEMY', ok, detail);
MOCK.fire('command', { command = '/cadence enemy attach off' });
ok, detail = answers('/cadence attack labeltext ' .. ('x'):rep(30), ('The auto attack timer\'s label is set to "%s".')
    :format(('x'):rep(23)));
check('a long label is cut to the 23 the box takes', ok and s.attack.label_text == ('x'):rep(23), detail);
-- The chat line sends Shift-JIS. A two-byte character or an auto-translate phrase goes whole, even when
-- one of its bytes is a letter.
ok, detail = answers('/cadence attack labeltext A\131\66A\253\2\2\65\66\253B', 'The auto attack timer\'s label is set to '
    .. '"AAB".');
check('Shift-JIS and auto-translate leave nothing behind', ok and s.attack.label_text == 'AAB', detail);
local NOTHING = 'That label has nothing cadence can use. Use plain English letters, numbers or symbols.';
ok, detail = refuses('/cadence attack labeltext \131\66\253\2\2\65\66\253', NOTHING);
check('a label with nothing left is refused', ok, detail);
ok, detail = refuses('/cadence resting labeltext', 'Type /cadence resting labeltext <text>, or /cadence resting '
    .. 'labeltext "" for its own name.');
check('labeltext with nothing after it gets the usage line', ok, detail);
ok, detail = refuses('/cadence labeltext AA', 'Didn\'t recognize "labeltext". Type /cadence help to see the commands.');
check('labeltext needs a timer\'s word', ok, detail);
presets.reset(s);
presets.forget_undo();

-- Help ------------------------------------------------------------------------------------------------------
-- What each timer's help says after its parts, and the whole of help look and help colors.
local function help_lines(word, from)
    local lines = said('/cadence help ' .. word);
    return table.concat(lines, '\n', from or 1), #lines;
end
local HELP = {
    attack = { 4, 9, {
        '/cadence attack width <120-640>  sets how wide the timer is.',
        '/cadence attack height <0.50-2.50>  sets how tall the whole timer is, including text and spacing.',
        '/cadence attack barheight <2-32>  sets how thick its bar is.',
        '/cadence attack almostat <0.1-2.0>  sets how many seconds before your attack the almost ready color starts.',
        '/cadence attack labeltext <text>  gives it a name of your own, like AA. "" puts its own name back.',
        '/cadence color attack_tp|attack_fill_start|attack_fill_end|attack_ready|attack_almost <rrggbb>  sets one of its '
            .. 'colors.',
    } },
    resting = { 3, 11, {
        '/cadence resting width <120-640>  sets how wide the timer is.',
        '/cadence resting height <0.50-2.50>  sets how tall the whole timer is, including text and spacing.',
        '/cadence resting barheight <2-32>  sets how thick its bar is.',
        '/cadence resting flashlength <0.2-1.5>  sets how many seconds the flash on each tick lasts.',
        '/cadence resting soundvolume <0-100>  sets how loud the sound is, from silent to full.',
        '/cadence resting labeltext <text>  gives it a name of your own, like AA. "" puts its own name back.',
        '/cadence resting soundfile <name>  picks the sound that plays once you\'re full. Two come with cadence, and '
            .. 'you can add your own .mp3 and .wav files to config\\addons\\cadence\\sounds. You can leave off .mp3 or '
            .. '.wav.',
        '/cadence resting playsound  plays the sound now, so you can hear it.',
        '/cadence color resting_fill_start|resting_fill_end|resting_full|resting_flash <rrggbb>  sets one of its colors.',
    } },
    enemy = { 4, 9, {
        '/cadence enemy width <120-640>  sets how wide the timer is.',
        '/cadence enemy height <0.50-2.50>  sets how tall the whole timer is, including text and spacing.',
        '/cadence enemy barheight <2-32>  sets how thick its bar is.',
        '/cadence enemy almostat <0.1-2.0>  sets how many seconds before the monster\'s attack the almost ready color '
            .. 'starts.',
        '/cadence enemy labeltext <text>  gives it a name of your own, like AA. "" puts its own name back.',
        '/cadence color enemy_on_you|enemy_fill_start|enemy_fill_end|enemy_ready|enemy_almost <rrggbb>  sets one of its '
            .. 'colors.',
    } },
    look = { 1, 7, {
        '/cadence scale <0.50-2.50>  sets how big the timers are.',
        '/cadence textsize <10-28>  sets how big the numbers are.',
        '/cadence detailsize <8-32>|auto  sets how big the small text is. Auto follows Text size.',
        '/cadence labelsize <8-32>|auto  sets how big the timer names are. Auto follows Text size.',
        '/cadence corners <0-12>  sets how round the timers\' corners are.',
        '/cadence attack|resting|enemy|recovery|enemycast labeltext <text>  gives that timer a name of your own, like AA. "" puts its own '
            .. 'name back.',
        '/cadence color background|border|accent|labels|values|details|bar_track|outline <rrggbb>  sets one of the Appearance '
            .. 'tab\'s colors. /cadence help colors lists every color.',
    } },
    recovery = { 3, 7, {
        '/cadence recovery width <120-640>  sets how wide the action recovery timer is.',
        '/cadence recovery height <0.50-2.50>  sets its overall height.',
        '/cadence recovery barheight <2-32>  sets how thick its bar is.',
        '/cadence recovery labeltext <text>  gives it a name of your own, like AA. "" puts its own name back.',
        '/cadence color recovery_fill_start|recovery_fill_end <rrggbb>  sets one of its colors.',
    } },
    enemycast = { 3, 7, {
        '/cadence enemycast width <120-640>  sets how wide the enemy cast timer is.',
        '/cadence enemycast height <0.50-2.50>  sets its overall height.',
        '/cadence enemycast barheight <2-32>  sets how thick its bar is.',
        '/cadence enemycast labeltext <text>  gives it a name of your own, like AA. "" puts its own name back.',
        '/cadence color enemycast_fill_start|enemycast_fill_end <rrggbb>  sets one of its colors.',
    } },
    colors = { 1, 10, {
        '/cadence color <what> <rrggbb>  sets one of the timers\' colors. <what> is one of these, under its heading in '
            .. 'the settings window.',
        'ENEMY CAST  enemycast_fill_start, enemycast_fill_end',
        'ACTION RECOVERY  recovery_fill_start, recovery_fill_end',
        'AUTO ATTACK TIMER  attack_tp, attack_fill_start, attack_fill_end, attack_ready, attack_almost',
        'RESTING TIMER  resting_fill_start, resting_fill_end, resting_full, resting_flash',
        'ENEMY ATTACK TIMER  enemy_on_you',
        'ENEMY BAR  enemy_fill_start, enemy_fill_end, enemy_ready, enemy_almost',
        'CARD  background, border, accent',
        'TEXT AND BAR  labels, values, details, bar_track, outline',
        'The color is six hex digits like c55151. Two more, from 00 to ff, set how solid it is, like c55151cc.',
    } },
};
for _, word in ipairs({ 'attack', 'resting', 'enemy', 'recovery', 'enemycast', 'look', 'colors' }) do
    local from, total, lines = HELP[word][1], HELP[word][2], HELP[word][3];
    local text, count_now = help_lines(word, from);
    check('help ' .. word, count_now == total and text == table.concat(lines, '\n'), text:gsub('\n', ' / '));
end
check('help color is the same as help colors', help_lines('color') == help_lines('colors'));
check('recovery help includes its attachment switch', help_lines('recovery'):find('attach (Attach under auto attack)', 1, true) ~= nil);
-- The whole help has the Appearance tab's sliders and the color command under the Appearance tab.
local help = said('/cadence help');
local look_at, numbers_at, colors_at = nil, nil, nil;
for i, line in ipairs(help) do
    if (line == 'Appearance tab') then look_at = i; end
    if (line == '/cadence scale|textsize|detailsize|labelsize|corners|windowfontsize|windowcorners|windowspacing <number>  '
        .. 'sets Scale, Text size, Detail size, Label size, Corner roundness, Font size, Corner roundness or Spacing.') then
        numbers_at = i;
    end
    if (line == '/cadence color <what> <rrggbb>  sets one of the timers\' colors. /cadence help colors lists them.') then
        colors_at = i;
    end
end
check('the whole help lists the Appearance tab\'s sliders and the color command under the Appearance tab', look_at and numbers_at
    and colors_at and look_at < numbers_at and look_at < colors_at, tostring(numbers_at) .. ' ' .. tostring(colors_at));
check('and says a timer\'s slider takes a number', table.concat(help, ' '):find('A slider takes a number, like /cadence '
    .. 'attack width 300.', 1, true) ~= nil and table.concat(help, ' '):find('A slider takes a number, like /cadence '
    .. 'enemy width 300.', 1, true) ~= nil);

-- What chat says reads like everything else in cadence.
local odd_line = nil;
for _, line in ipairs(MOCK.printed) do
    if (line:find(';', 1, true) or line:find('[\128-\255]')) then odd_line = line; end
end
check('no semicolons or odd characters in anything said', odd_line == nil, odd_line);
local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped', 1, true)) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
