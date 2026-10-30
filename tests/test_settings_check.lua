-- The settings check. A number outside its slider is pulled back in. A value of the wrong type gets its
-- default. Labels keep plain characters up to the box's length, and Follows keeps to its words. The
-- defaults, every preset and a normal file come through unchanged. cadence runs it on load, on login,
-- after the shared layout comes in and before each save. The window's sliders read the same ranges.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

addon.name = 'cadence';
local defaults = require('ui.defaults');
local presets  = require('ui.presets');
local R = defaults.RANGES;

local function copy(t)
    local c = {};
    for k, v in pairs(t) do c[k] = (type(v) == 'table') and copy(v) or v; end
    return c;
end

-- The first difference between two settings tables, as a path, or nil when they match.
local function differs(a, b, path)
    path = path or '';
    for k, v in pairs(b) do
        if (type(v) == 'table' and type(a[k]) == 'table') then
            local d = differs(a[k], v, path .. '.' .. tostring(k));
            if (d) then return d; end
        elseif (a[k] ~= v) then
            return path .. '.' .. tostring(k) .. ' ' .. tostring(a[k]) .. ' vs ' .. tostring(v);
        end
    end
    for k in pairs(a) do
        if (b[k] == nil) then return path .. '.' .. tostring(k) .. ' added'; end
    end
    return nil;
end

-- Every color table in `s`, so a test can tell the same tables are still there.
local function colors(s)
    local found = {};
    for name, section in pairs(s) do
        for key, value in pairs(section) do
            if (type(value) == 'table') then found[name .. '.' .. key] = value; end
        end
    end
    return found;
end

-- A label as the test output can show it, with anything outside plain ASCII as a ?.
local function printable(text)
    return (tostring(text):gsub('[^\32-\126]', '?'));
end

local function same_tables(s, before)
    for path, t in pairs(before) do
        local name, key = path:match('^([%w_]+)%.(.+)$');
        if (not rawequal(s[name][key], t)) then return path; end
    end
    return nil;
end

local function unchanged(name, s)
    local before, tables = copy(s), colors(s);
    defaults.tidy(s);
    local d = differs(s, before);
    check(name .. ' comes through unchanged', d == nil, d);
    local t = same_tables(s, tables);
    check(name .. ' keeps its own color tables', t == nil, t);
end

-- The ranges -----------------------------------------------------------------------------------
check('the timers share the drag limits', R.attack.width == defaults.WIDTH
    and R.enemy.bar_height == defaults.BAR_HEIGHT and R.recovery.width == defaults.WIDTH
    and R.recovery.bar_height == defaults.BAR_HEIGHT and R.recovery.height_scale == defaults.HEIGHT_SCALE
    and R.enemycast.width == defaults.WIDTH and R.enemycast.bar_height == defaults.BAR_HEIGHT
    and R.enemycast.height_scale == defaults.HEIGHT_SCALE);
check('Scale goes 0.5 to 2.5', R.style.scale[1] == 0.5 and R.style.scale[2] == 2.5);
check('Text size goes 10 to 28', R.style.font_size[1] == 10 and R.style.font_size[2] == 28);
check('Label and Detail size start at auto', R.style.label_size[1] == defaults.LABEL_SIZE[1] - 1
    and R.style.detail_size[1] == defaults.DETAIL_SIZE[1] - 1 and R.style.label_size[2] == 32);
check('Corner roundness goes 0 to 12', R.style.rounding[1] == 0 and R.style.rounding[2] == 12);
check('Almost ready at goes 0.1 to 2.0', R.attack.almost_seconds[1] == 0.1 and R.enemy.almost_seconds[2] == 2.0);
check('Flash length goes 0.2 to 1.5', R.resting.flash_seconds[1] == 0.2 and R.resting.flash_seconds[2] == 1.5);
check('a label is 23 at most', defaults.LABEL_LENGTH == 23);

-- What comes through unchanged ---------------------------------------------------------------------
unchanged('a fresh copy of the defaults', defaults.make());
for _, name in ipairs(presets.NAMES) do
    local s = defaults.make();
    presets.apply(s, name);
    unchanged(name, s);
end
do
    local s = defaults.make();
    s.style.scale, s.style.font_size = 0.75, 28;
    presets.reset(s);
    unchanged('Reset look', s);
end

-- A file with every slider at both ends, typed labels, each Follows word and colors at their edges.
for _, ends in ipairs({ 1, 2 }) do
    local s = defaults.make();
    for name, ranges in pairs(R) do
        for key, range in pairs(ranges) do s[name][key] = range[ends]; end
    end
    s.attack.label_text = (' !~%AA'):rep(4):sub(1, 23);
    s.resting.label_text = 'Heal';
    s.enemy.which = defaults.FOLLOWS[ends + 1][1];
    s.attack.fill_start = { 0, 1, 0.5, 0 };
    s.style.panel_color = { 0.123456789, 1, 0, 0.88 };
    s.attack.x, s.window.width, s.window.x = -40, 5000, 99999;
    s.style.font_name = 'My Font';
    s.style.unknown_key = 'kept';
    unchanged(ends == 1 and 'a file at the low ends' or 'a file at the high ends', s);
end
do
    local s = defaults.make();
    s.style.label_size, s.style.detail_size = 3, 0;
    unchanged('a file with auto label and detail sizes', s);
end

-- Numbers outside their range ----------------------------------------------------------------------
do
    local fresh = defaults.make();
    local high, low, mid = defaults.make(), defaults.make(), defaults.make();
    for name, ranges in pairs(R) do
        for key, range in pairs(ranges) do
            high[name][key], low[name][key] = range[2] + 1000, range[1] - 1000;
            mid[name][key] = (range[1] + range[2]) / 2;
        end
    end
    high.attack.width = 1 / 0;
    low.attack.width = -1 / 0;
    defaults.tidy(high);
    defaults.tidy(low);
    local before = copy(mid);
    defaults.tidy(mid);
    for name, ranges in pairs(R) do
        for key, range in pairs(ranges) do
            local floor = math.min(range[1], fresh[name][key]);
            check(name .. '.' .. key .. ' comes down to its largest', high[name][key] == range[2], high[name][key]);
            check(name .. '.' .. key .. ' comes up to its smallest', low[name][key] == floor, low[name][key]);
            check(name .. '.' .. key .. ' in range stays', mid[name][key] == before[name][key], mid[name][key]);
        end
    end
    check('a size of 0 stays auto', low.style.label_size == 0 and low.style.detail_size == 0);
end

-- Values of the wrong type -------------------------------------------------------------------------
do
    local OTHER = { boolean = 'yes', number = 'nope', string = 5, table = 7 };
    local s, fresh = defaults.make(), defaults.make();
    for _, section in pairs(s) do
        for key, value in pairs(section) do section[key] = OTHER[type(value)]; end
    end
    defaults.tidy(s);
    local d = differs(s, fresh);
    check('every value of the wrong type gets its default', d == nil, d);

    s = defaults.make();
    s.style.scale, s.attack.y, s.window.height = 0 / 0, 0 / 0, 0 / 0;
    s.attack.enabled, s.enemy.width = nil, { 300 };
    defaults.tidy(s);
    check('0/0 gets the default', s.style.scale == 1.0 and s.attack.y == fresh.attack.y
        and s.window.height == fresh.window.height);
    check('a missing value gets its default', s.attack.enabled == true);
    check('a table for a number gets the default', s.enemy.width == fresh.enemy.width);

    -- A spot or size with no range can't be endless either. json can't write it into the shared layout.
    s = defaults.make();
    s.attack.x, s.resting.y, s.window.width = math.huge, -math.huge, math.huge;
    s.enemy.x = -5000;
    defaults.tidy(s);
    check('an endless spot or size gets the default', s.attack.x == fresh.attack.x and s.resting.y == fresh.resting.y
        and s.window.width == fresh.window.width, s.attack.x .. ' ' .. s.resting.y .. ' ' .. s.window.width);
    check('a far away spot stays as it is', s.enemy.x == -5000);
    check('and the shared layout can save it', pcall(require('json').encode, s));
end

-- Colors ----------------------------------------------------------------------------------------
do
    local s, fresh = defaults.make(), defaults.make();
    local kept = s.attack.tp_color;
    kept[1], kept[2], kept[3], kept[4] = 1.5, -0.2, 0.3, 7;
    s.attack.fill_start = { 'a', 0, 0, 1 };
    s.resting.full_color = { 0.2, 0.2, 0 / 0, 1 };
    s.enemy.on_you_color = { 0.1, 0.2, 0.3 };
    s.style.border_color = { 0.1, 0.2, 0.3, 0.4, 'extra' };
    defaults.tidy(s);
    local c = s.attack.tp_color;
    check('each part is pulled into 0 to 1', c[1] == 1 and c[2] == 0 and c[3] == 0.3 and c[4] == 1,
        table.concat(c, ' '));
    check('in its own table', rawequal(c, kept));
    check('a part that isn\'t a number gets the default color',
        differs(s.attack.fill_start, fresh.attack.fill_start) == nil);
    check('so does 0/0', differs(s.resting.full_color, fresh.resting.full_color) == nil);
    check('so does a missing part', differs(s.enemy.on_you_color, fresh.enemy.on_you_color) == nil);
    check('a fifth part is left alone', s.style.border_color[4] == 0.4 and s.style.border_color[5] == 'extra');
    check('a default color is a new table', not rawequal(s.attack.fill_start, s.resting.fill_start));
end

-- Labels and Follows --------------------------------------------------------------------------------
do
    local s = defaults.make();
    s.attack.label_text = 'A\195\132A\227\130\162';
    s.resting.label_text = 'R\tE\nS\127TING';
    s.enemy.label_text = ('x'):rep(30);
    s.enemy.which = 'nobody';
    defaults.tidy(s);
    check('a letter outside plain ASCII goes', s.attack.label_text == 'AA', printable(s.attack.label_text));
    check('so do tabs and line breaks', s.resting.label_text == 'RESTING', printable(s.resting.label_text));
    check('a long label is cut to what the box takes', s.enemy.label_text == ('x'):rep(23), #s.enemy.label_text);
    check('an unknown Follows word gets the default', s.enemy.which == 'target_first', s.enemy.which);

    s = defaults.make();
    s.attack.label_text = ('\195\132'):rep(12) .. ('y'):rep(23);
    s.enemy.which = 'TARGET';
    defaults.tidy(s);
    check('the length counts what\'s left', s.attack.label_text == ('y'):rep(23), printable(s.attack.label_text));
    check('Follows words have to match exactly', s.enemy.which == 'target_first');
    for _, choice in ipairs(defaults.FOLLOWS) do
        s.enemy.which = choice[1];
        defaults.tidy(s);
        check(choice[1] .. ' stays', s.enemy.which == choice[1]);
    end
end

-- Through the addon ---------------------------------------------------------------------------------
local SHARED = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\shared_layout.json';
local function write_shared(text)
    local file = io.open(SHARED, 'w');
    file:write(text);
    file:close();
end
local function read_shared()
    local file = io.open(SHARED, 'r');
    if (file == nil) then return nil; end
    local text = file:read('*a');
    file:close();
    return text;
end

local function through_the_addon()
    -- A hand-edited file, and a shared layout with a few more mistakes.
    MOCK.settings_file = {
        attack  = { width = 5000, label_text = 'A\195\132A', fill_start = { 'red', 0, 0, 1 }, x = 333,
            tp_color = { 0.1, 0.2, 0.3 } },
        resting = { flash_seconds = 0.2, label_text = 'Heal' },
        enemy   = { which = 'goblin', enabled = 'yes', almost_seconds = 0 / 0 },
        style   = { font_size = '14', label_size = 7, detail_size = 0 },
    };
    write_shared('{"enabled":true,"settings":{"style":{"scale":50,"rounding":-3},'
        .. '"resting":{"label_text":"R\\u00e9ST","bar_height":99}}}');

    dofile(ADDON_DIR .. '/cadence.lua');
    MOCK.watch_settings();
    MOCK.fire('load');
    -- The shared layout is on, so the timers use the shared copy.
    local s = MOCK.in_use;
    local kept = MOCK.settings.defaults;

    check('on load, a width too big comes down', s.attack.width == 640, s.attack.width);
    check('a label keeps only plain characters', s.attack.label_text == 'AA', printable(s.attack.label_text));
    check('a broken color gets the default', differs(s.attack.fill_start, defaults.make().attack.fill_start) == nil);
    check('in a table of its own', not rawequal(s.attack.fill_start, kept.attack.fill_start));
    check('a color missing its alpha gets it from the defaults', s.attack.tp_color[4] == kept.attack.tp_color[4]
        and s.attack.tp_color[1] == 0.1);
    check('an unknown Follows word gets the default', s.enemy.which == 'target_first');
    check('a word for on or off gets the default', s.enemy.enabled == false);
    check('0/0 gets the default', s.enemy.almost_seconds == 0.5, s.enemy.almost_seconds);
    check('a number written as text gets the default', s.style.font_size == 14);
    check('the good values stay', s.attack.x == 333 and s.resting.flash_seconds == 0.2 and s.resting.label_text ~= nil
        and s.style.label_size == 7 and s.style.detail_size == 0);
    check('the shared layout\'s scale comes down too', s.style.scale == 2.5, s.style.scale);
    check('and its roundness up', s.style.rounding == 0, s.style.rounding);
    check('and its bar height', s.resting.bar_height == 32, s.resting.bar_height);
    check('and its label', s.resting.label_text == 'RST', printable(s.resting.label_text));
    check('the defaults kept for the next character are untouched',
        kept.attack.width == 240 and kept.style.scale == 1.0);
    -- Ashita writes your own settings to your file, so they get the check too.
    local own = MOCK.settings.current;
    check('your own settings are checked too', own ~= s and own.attack.width == 640 and own.enemy.which == 'target_first'
        and own.style.scale == 1.0, own.attack.width);

    -- It draws with the timers and the settings window up.
    local settings_window = require('ui.settings_window');
    local imgui = require('imgui');
    settings_window.set_open(true);
    s.enemy.enabled = true;
    MOCK.now = 100;
    MOCK.player.status = 1;
    for _ = 1, 5 do MOCK.frame(1 / 60); end
    local function drawing_error()
        for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then return line; end end
        return nil;
    end
    check('no drawing errors after the fix', drawing_error() == nil, drawing_error());

    -- The settings window's sliders and label boxes read the same limits.
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    local shown, open_combo = nil, nil;
    rawset(imgui, 'BeginCombo', function (label, preview)
        if (label == 'Follows##enemy') then shown = preview; end
        return label == open_combo;
    end);
    open_combo = 'Follows##enemy';
    s.enemy.which = 'attacker';
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    rawset(imgui, 'BeginCombo', nil);

    local SLIDERS = {
        ['Width##enemycast'] = R.enemycast.width, ['Bar height##enemycast'] = R.enemycast.bar_height,
        ['Height##enemycast'] = R.enemycast.height_scale,
        ['Width##recovery'] = R.recovery.width, ['Bar height##recovery'] = R.recovery.bar_height,
        ['Height##recovery'] = R.recovery.height_scale,
        ['Width##attack'] = R.attack.width, ['Bar height##attack'] = R.attack.bar_height,
        ['Height##attack'] = R.attack.height_scale,
        ['Almost ready at##attack'] = R.attack.almost_seconds,
        ['Width##resting'] = R.resting.width, ['Bar height##resting'] = R.resting.bar_height,
        ['Height##resting'] = R.resting.height_scale,
        ['Flash length'] = R.resting.flash_seconds, ['Volume##sound'] = R.resting.sound_volume,
        ['Width##enemy'] = R.enemy.width, ['Bar height##enemy'] = R.enemy.bar_height,
        ['Height##enemy'] = R.enemy.height_scale,
        ['Almost ready at##enemy'] = R.enemy.almost_seconds,
        ['Scale'] = R.style.scale, ['Text size'] = R.style.font_size, ['Detail size'] = R.style.detail_size,
        ['Label size'] = R.style.label_size, ['Corner roundness'] = R.style.rounding,
        ['Font size##window'] = R.window_style.font_size, ['Corner roundness##window'] = R.window_style.rounding,
        ['Spacing##window'] = R.window_style.spacing,
    };
    local count = 0;
    for _, ranges in pairs(R) do
        for _ in pairs(ranges) do count = count + 1; end
    end
    local listed = 0;
    for _ in pairs(SLIDERS) do listed = listed + 1; end
    check('every range has its slider', count == listed, count .. ' vs ' .. listed);
    -- The resting recovery goal has a mode-dependent range instead of one fixed defaults.RANGES entry.
    SLIDERS['Goal##recovery'] = defaults.GOAL_PERCENT;

    local drawn, wrong, boxes, names = {}, nil, {}, {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'SliderInt' or c[1] == 'SliderFloat') then
            local range = SLIDERS[c[2]];
            drawn[c[2]] = true;
            if (range == nil or c[4] ~= range[1] or c[5] ~= range[2]) then
                wrong = wrong or (c[2] .. ' ' .. tostring(c[4]) .. ' to ' .. tostring(c[5]));
            end
        elseif (c[1] == 'InputTextWithHint') then
            table.insert(boxes, c[5]);
        elseif (c[1] == 'Selectable') then
            table.insert(names, c[2]);
        end
    end
    check('each slider goes as far as its range', wrong == nil, wrong);
    local missing = nil;
    for label in pairs(SLIDERS) do if (not drawn[label]) then missing = missing or label; end end
    check('every slider was drawn', missing == nil, missing);
    check('the label boxes take 23 and the zero after',
        #boxes == 5 and boxes[1] == 24 and boxes[2] == 24 and boxes[3] == 24 and boxes[4] == 24
        and boxes[5] == 24, table.concat(boxes, ' '));
    check('Follows shows the name for its word', shown == 'Whoever hits me', shown);
    check('and lists its words in order', names[1] == 'My target first' and names[2] == 'My target only'
        and names[3] == 'Whoever hits me' and #names == 3, table.concat(names, ', '));

    -- Before a save, from a command.
    s.style.scale = 9;
    s.attack.label_text = 'AA\195\132';
    local saves = MOCK.saved;
    MOCK.fire('command', { command = '/cadence lock' });
    check('a save checks first', s.style.scale == 2.5 and s.attack.label_text == 'AA', s.style.scale);
    check('and only the shared file is written', MOCK.saved == saves);
    local text = read_shared() or '';
    check('the shared copy is written checked too', text:find('"scale":2.5') ~= nil and not text:find('"scale":9'),
        printable(text:sub(1, 80)));

    -- Before the save when the addon unloads. That writes your own settings, even while the layout is shared.
    own.style.font_size = 99;
    MOCK.fire('unload');
    check('unloading checks first', own.style.font_size == 28, own.style.font_size);

    -- Another character logs in with its own mistakes, while the shared layout is off.
    MOCK.fire('command', { command = '/cadence onelayout off' });
    MOCK.settings.switch_character({ resting = { width = 10, label_text = ('z'):rep(40) }, enemy = { which = 7 } });
    s = MOCK.settings.current;
    check('on login, a width too small comes up', s.resting.width == 120, s.resting.width);
    check('a long label is cut', s.resting.label_text == ('z'):rep(23));
    check('a number for Follows gets the default', s.enemy.which == 'target_first');

    -- And with the shared layout on, its mistakes are fixed after it comes in.
    write_shared('{"enabled":true,"settings":{"style":{"scale":0.01}}}');
    MOCK.settings.switch_character(nil);
    s = MOCK.in_use;
    check('on login, the shared layout\'s scale comes up', s.style.scale == 0.5, s.style.scale);

    for _ = 1, 3 do MOCK.frame(1 / 60); end
    check('still no drawing errors', drawing_error() == nil, drawing_error());

    MOCK.fire('command', { command = '/cadence onelayout off' });
    check('the shared layout is gone after the test', read_shared() == nil);
end

-- A crash still takes the shared layout away, so it can't reach the tests after this one.
local ok, err = pcall(through_the_addon);
os.remove(SHARED);
check('the addon part runs to the end', ok, printable(err));

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
