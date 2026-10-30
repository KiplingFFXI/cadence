-- The Window and Window colors sections in Appearance. The settings window's font, font size, corners and spacing on the
-- Window section, and every window color as rows of swatches on the Window colors section. Then the commands that
-- set them, windowfont, windowfontsize, windowcorners, windowspacing and windowcolor, what each one says
-- back, and /cadence help window and windowcolors.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

-- Segoe UI and Consolas are in the fonts folder. Verdana isn't, so it doesn't load.
local FONTS = 'C:\\Windows\\Fonts\\';
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
for _, file in ipairs({ 'seguisb.ttf', 'segoeui.ttf', 'consola.ttf' }) do MOCK.fs[FONTS .. file] = true; end
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
-- A shared layout left over from another test would turn One layout for all characters on.
os.remove(MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\shared_layout.json');

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local imgui = require('imgui');
local theme = require('ui.theme');
local presets = require('ui.presets');
local defaults = require('ui.defaults');
local json = require('json');
MOCK.now = 100;

local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n or 1 do MOCK.frame(1 / 60); end
    MOCK.record_imgui = false;
end
local function find(name, label, from)
    for i = from or 1, #MOCK.imgui_calls do
        local c = MOCK.imgui_calls[i];
        if (c[1] == name and (label == nil or c[2] == label or c[3] == label)) then return i, c; end
    end
    return nil;
end
-- The width set for the next control before the call at `at`.
local function width_before(at)
    for i = at - 1, 1, -1 do
        if (MOCK.imgui_calls[i][1] == 'SetNextItemWidth') then return MOCK.imgui_calls[i][2]; end
    end
    return nil;
end
local function drawing_error()
    for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped', 1, true)) then return line; end end
    return nil;
end

MOCK.fire('command', { command = '/cadence' });

-- The window colors, laid out ---------------------------------------------------------------------------
-- Typed out again, so a color moved, dropped or put in twice shows up. Each heading, then each row's name
-- and the keys of its swatches in order.
local LAYOUT = {
    'TEXT', 'Text: text faded_text', 'Headings: headings heading_lines', 'Notes: notes',
    'Messages: done_messages problem_messages', 'Text boxes: selected_text text_cursor',
    'WINDOW', 'Window: background border', 'Title bar: title_bar title_bar_unfocused',
    'Resize corner: resize_corner resize_corner_hovered resize_corner_held',
    'Resize edges: resize_edges_hovered resize_edges_held',
    'Scrollbar: scrollbar_track scrollbar scrollbar_hovered scrollbar_held',
    'BOXES AND BUTTONS', 'Boxes: boxes boxes_hovered boxes_clicked', 'Check marks: check_marks',
    'Slider handles: slider_handles slider_handles_held', 'Buttons: buttons buttons_hovered buttons_pressed',
    'ON chips: on_chips on_chip_text', 'Dropdowns: dropdowns row_picked row_hovered row_clicked',
    'TABS', 'Tabs: tabs tabs_hovered open_tab open_tab_line',
    'Unfocused tabs: tabs_unfocused open_tab_unfocused open_tab_line_unfocused',
};
-- What each swatch says when you point at it.
local NAMES = {
    text = 'Text', faded_text = 'Faded text', headings = 'Headings', heading_lines = 'Heading lines', notes = 'Notes',
    done_messages = 'Done messages', problem_messages = 'Problem messages',
    selected_text = 'Text highlight', text_cursor = 'Text cursor', background = 'Background', border = 'Border',
    title_bar = 'Title bar', title_bar_unfocused = 'Title bar, unfocused', resize_corner = 'Resize corner',
    resize_corner_hovered = 'Resize corner, hovered', resize_corner_held = 'Resize corner, held',
    resize_edges_hovered = 'Resize edges, hovered', resize_edges_held = 'Resize edges, held',
    scrollbar_track = 'Scrollbar track', scrollbar = 'Scrollbar', scrollbar_hovered = 'Scrollbar, hovered',
    scrollbar_held = 'Scrollbar, held', boxes = 'Boxes', boxes_hovered = 'Boxes, hovered',
    boxes_clicked = 'Boxes, clicked', check_marks = 'Check marks', slider_handles = 'Slider handles',
    slider_handles_held = 'Slider handles, held', buttons = 'Buttons', buttons_hovered = 'Buttons, hovered',
    buttons_pressed = 'Buttons, pressed', on_chips = 'ON chips', on_chip_text = 'ON chip words',
    dropdowns = 'Open dropdowns', row_picked = 'Picked row', row_hovered = 'Row, hovered', row_clicked = 'Row, clicked',
    tabs = 'Tabs', tabs_hovered = 'Tabs, hovered', open_tab = 'Open tab', open_tab_line = 'Open tab line',
    tabs_unfocused = 'Tabs, unfocused', open_tab_unfocused = 'Open tab, unfocused',
    open_tab_line_unfocused = 'Open tab line, unfocused',
};

local laid_out, flat = {}, {};
for _, group in ipairs(theme.WINDOW_COLOR_GROUPS) do
    table.insert(laid_out, group.name);
    for _, row in ipairs(group.rows) do
        local keys = {};
        for _, entry in ipairs(row.colors) do
            table.insert(keys, entry.key);
            table.insert(flat, entry);
        end
        table.insert(laid_out, row.name .. ': ' .. table.concat(keys, ' '));
    end
end
check('the window colors sit under their headings in rows', table.concat(laid_out, ' | ') == table.concat(LAYOUT, ' | '),
    table.concat(laid_out, ' | '));
local same_list = #flat == #theme.WINDOW_COLORS;
for i, entry in ipairs(flat) do same_list = same_list and rawequal(theme.WINDOW_COLORS[i], entry); end
check('WINDOW_COLORS is every one of them in that order', same_list and #flat == 44, #theme.WINDOW_COLORS);
local wrong_name = nil;
for _, entry in ipairs(flat) do
    if (entry.name ~= NAMES[entry.key]) then wrong_name = entry.key .. ' says ' .. tostring(entry.name); end
end
check('each swatch has its own name', wrong_name == nil, wrong_name);

-- The Window section --------------------------------------------------------------------------------------------
s.window_style.font, s.window_style.font_size = 'consolas', 18;
frames(1);
local font_at, font_combo = find('BeginCombo', 'Font##window');
local size_at, size_slider = find('SliderInt', 'Font size##window');
local corners_at, corners = find('SliderInt', 'Corner roundness##window');
local spacing_at, spacing = find('SliderInt', 'Spacing##window');
local font_heading, shape_heading = find('TextColored', 'FONT'), find('TextColored', 'SHAPE');
check('FONT has the Font list and Font size, and SHAPE the corners and spacing', font_heading and font_at and size_at
    and shape_heading and corners_at and spacing_at and font_heading < font_at and font_at < size_at
    and size_at < shape_heading and shape_heading < corners_at and corners_at < spacing_at);
local second = find('TableNextColumn', nil, size_at);
check('SHAPE is the second section', second ~= nil and second < shape_heading, tostring(second));
check('the Font list shows the font you have', font_combo and font_combo[3] == 'Consolas', font_combo and font_combo[3]);
local R = defaults.RANGES.window_style;
check('the sliders go as far as their ranges', size_slider[4] == 12 and size_slider[5] == 24 and corners[4] == 0
    and corners[5] == 12 and spacing[4] == 2 and spacing[5] == 14 and R.font_size[1] == 12 and R.spacing[2] == 14);
check('and show pixels', size_slider[6] == '%d px' and corners[6] == '%d px' and spacing[6] == '%d px');
check('the controls are 190 wide at 18 px', width_before(font_at) == 190 and width_before(size_at) == 190
    and width_before(corners_at) == 190, width_before(corners_at));
s.window_style.font_size = 24;
frames(1);
font_at, size_at, corners_at = find('BeginCombo', 'Font##window'), find('SliderInt', 'Font size##window'),
    find('SliderInt', 'Corner roundness##window');
check('at 24 px the others grow and Font size keeps its 18 px width, so dragging it never moves its handle',
    width_before(font_at) == 253 and width_before(corners_at) == 253 and width_before(size_at) == 190,
    width_before(font_at) .. ' ' .. width_before(size_at));
s.window_style.font_size = 18;

-- Each (?) on the Window section says what its control does, and whether a preset changes it.
rawset(imgui, 'IsItemHovered', function () return true; end);
frames(1);
rawset(imgui, 'IsItemHovered', nil);
local window_tips, control = {}, nil;
for _, c in ipairs(MOCK.imgui_calls) do
    if ((c[1] == 'BeginCombo' or c[1] == 'SliderInt') and tostring(c[2]):find('##window$')) then control = c[2]; end
    -- The Appearance tab's slider of the same name, for the timers.
    if (c[1] == 'SliderInt' and c[2] == 'Corner roundness') then control = c[2]; end
    if (c[1] == 'TextUnformatted' and control ~= nil and window_tips[control] == nil
        and tostring(c[2]):find(' ', 1, true)) then
        window_tips[control] = c[2];
        control = nil;
    end
end
local function tip_says(label, ...)
    local tip = window_tips[label] or '';
    for _, words in ipairs({ ... }) do if (not tip:find(words, 1, true)) then return false; end end
    return true;
end
check('the Font tip names the timers\' own font and says presets leave it', tip_says('Font##window',
    'This window\'s font', 'Appearance tab', 'A preset never changes it'), window_tips['Font##window']);
check('and that a wide font stacks the sections and may scroll', tip_says('Font##window',
    'A wide one like Consolas stacks the sections, so the window may scroll'), window_tips['Font##window']);
check('the Font size tip says the layout grows', tip_says('Font size##window', 'How big this window\'s text is',
    'layout grows', 'A preset never changes it'), window_tips['Font size##window']);
check('the corners and spacing tips say a preset sets them', tip_says('Corner roundness##window', 'How round the corners',
    'Window matches the look') and tip_says('Spacing##window', 'The space between this window\'s rows',
    'Window matches the look'), window_tips['Spacing##window']);
check('the Appearance tab\'s Corner roundness tip says it\'s for the timers, so the two can\'t be mixed up',
    tip_says('Corner roundness', 'The timers\' corners'), window_tips['Corner roundness']);

-- The Font list lists every font, Ashita's first, and marks the one you have.
local listed, marked = {}, nil;
rawset(imgui, 'BeginCombo', function (label) return label == 'Font##window'; end);
rawset(imgui, 'Selectable', function (label, picked)
    table.insert(listed, label);
    if (picked) then marked = label; end
    return false;
end);
frames(1);
check('the Font list has every font in order', table.concat(listed, ', ')
    == 'Ashita, Segoe UI, Arial, Tahoma, Verdana, Calibri, Consolas', table.concat(listed, ', '));
check('with yours picked', marked == 'Consolas', marked);
local saves = MOCK.saved;
rawset(imgui, 'Selectable', function (label) return label == 'Segoe UI'; end);
frames(1);
check('picking one sets it and saves', s.window_style.font == 'segoeui' and MOCK.saved == saves + 1,
    s.window_style.font .. ' ' .. (MOCK.saved - saves));
rawset(imgui, 'BeginCombo', nil);
rawset(imgui, 'Selectable', nil);

-- A slider reaches the window on the next frame.
rawset(imgui, 'SliderInt', function (label, value)
    if (label == 'Spacing##window') then value[1] = 11; return true; end
    if (label == 'Corner roundness##window') then value[1] = 5; return true; end
    return false;
end);
frames(1);
rawset(imgui, 'SliderInt', nil);
frames(1);
-- The timers push corners of their own first. The window pushes its corners just before its spacing.
local pushed_spacing, pushed_rounding, last_rounding = nil, nil, nil;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'PushStyleVar' and c[2] == ImGuiStyleVar_WindowRounding) then last_rounding = c[3]; end
    if (c[1] == 'PushStyleVar' and c[2] == ImGuiStyleVar_ItemSpacing and pushed_spacing == nil) then
        pushed_spacing, pushed_rounding = c[3][2], last_rounding;
    end
end
check('Spacing and Corner roundness set the window\'s', s.window_style.spacing == 11 and s.window_style.rounding == 5
    and pushed_spacing == 11 and pushed_rounding == 5, tostring(pushed_spacing) .. ' ' .. tostring(pushed_rounding));
check('which makes the Preset list say Custom', presets.current(s) == nil, presets.current(s));
presets.apply(s, 'Phoenix');
check('and picking the preset puts them back', s.window_style.spacing == 7 and s.window_style.rounding == 0
    and presets.current(s) == 'Phoenix');

-- The Window colors section ---------------------------------------------------------------------------------------
-- Every swatch, with the table and flags it was given.
local swatches = {};
rawset(imgui, 'ColorEdit4', function (label, value, flags)
    table.insert(swatches, { label = label, value = value, flags = flags });
    if (MOCK.record_imgui) then table.insert(MOCK.imgui_calls, { 'ColorEdit4', label }); end
    return false;
end);
frames(1);
local by_key, twice = {}, nil;
for _, sw in ipairs(swatches) do
    local key = sw.label:match('^##(.+)$');
    if (key ~= nil and NAMES[key] ~= nil) then
        if (by_key[key]) then twice = key; end
        by_key[key] = sw;
    end
end
local missing, wrong_table, wrong_flags = nil, nil, nil;
local SWATCH = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_AlphaPreviewHalf,
    ImGuiColorEditFlags_NoTooltip);
for key in pairs(NAMES) do
    local sw = by_key[key];
    if (sw == nil) then missing = key;
    elseif (not rawequal(sw.value, s.window_style[key])) then wrong_table = key;
    elseif (sw.flags ~= SWATCH) then wrong_flags = key .. ' ' .. tostring(sw.flags); end
end
check('every window color has one swatch, named ## and its key', missing == nil and twice == nil,
    tostring(missing) .. ' ' .. tostring(twice));
check('each edits your setting in place', wrong_table == nil, wrong_table);
check('and names itself instead of showing ImGui\'s own tip', wrong_flags == nil, wrong_flags);

-- The tab, from its note to its last row.
local start = find('TextUnformatted', 'Point at a swatch to see which color it is, and click it to pick a new one. While '
    .. 'Window matches the look is on, a preset sets all of them.');
check('the tab starts with a note on how the swatches work', start ~= nil);
local rows, headings, columns, lefts, gaps = {}, {}, 0, {}, {};
local calls = MOCK.imgui_calls;
local i = start and find('BeginTable', '##window_color_sections', start) or #calls + 1;
local row = nil;
while (i <= #calls and not (calls[i][1] == 'EndTable')) do
    local c = calls[i];
    if (c[1] == 'CollapsingHeader') then table.insert(headings, (c[2]:gsub('##.*', ''))); end
    if (c[1] == 'TableNextColumn') then columns = columns + 1; table.insert(headings, '|'); end
    if (c[1] == 'TextUnformatted' and calls[i - 1][1] == 'AlignTextToFramePadding') then
        row = { name = c[2], keys = {} };
        table.insert(rows, row);
        -- Where the first swatch starts, from the row's start. The mock makes text 7 per letter. Measuring
        -- the name comes between it and the SameLine.
        local after = calls[i + 1];
        if (after[1] == 'CalcTextSize') then after = calls[i + 2]; end
        table.insert(lefts, #c[2] * 7 + ((after[1] == 'SameLine' and after[2] == 0) and after[3] or -1000));
    elseif (c[1] == 'ColorEdit4' and row ~= nil) then
        local gap = calls[i - 1][1] == 'SameLine';
        if (#row.keys > 0 and not gap) then table.insert(gaps, c[2]); end
        table.insert(row.keys, (c[2]:gsub('^##', '')));
    elseif (c[1] == 'TextDisabled' and row ~= nil) then
        row.helped = calls[i - 1][1] == 'SameLine';
        row = nil;
    end
    i = i + 1;
end
check('two columns with independently folded color groups', columns == 2
    and table.concat(headings, ' ') == '| TEXT WINDOW | BOXES AND BUTTONS TABS', table.concat(headings, ' '));
local drawn = {};
for _, r in ipairs(rows) do table.insert(drawn, r.name .. ': ' .. table.concat(r.keys, ' ')); end
local expected_rows = {};
for _, line in ipairs(LAYOUT) do if (line:find(':', 1, true)) then table.insert(expected_rows, line); end end
check('each row is its name, then its swatches', table.concat(drawn, ' | ') == table.concat(expected_rows, ' | '),
    table.concat(drawn, ' | '));
local unhelped = nil;
for _, r in ipairs(rows) do if (not r.helped) then unhelped = r.name; end end
check('then its (?) on the same line', unhelped == nil and #rows == 18, unhelped or #rows);
check('the swatches in a row sit side by side', #gaps == 0, table.concat(gaps, ' '));
-- Unfocused tabs and Slider handles are the longest names, 14 letters, so every row's swatches start
-- 14 * 7 and the 8 between things on a line past its start.
local odd_left = nil;
for n, left in ipairs(lefts) do if (left ~= 14 * 7 + 8) then odd_left = rows[n].name .. ' ' .. left; end end
check('every row\'s swatches start at the same spot', odd_left == nil and #lefts == 18, odd_left);
-- The widest name sets that spot wherever its row is. Here the last row's name is the narrowest.
MOCK.measure = function (words) return (words == 'Unfocused tabs') and 20 or #words * 7; end
frames(1);
MOCK.measure = nil;
local gap_after = {};
for n, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'TextUnformatted' and MOCK.imgui_calls[n - 1][1] == 'AlignTextToFramePadding') then
        for m = n + 1, n + 3 do
            if (MOCK.imgui_calls[m][1] == 'SameLine') then gap_after[c[2]] = MOCK.imgui_calls[m][3]; break; end
        end
    end
end
check('by the widest name, wherever its row is', gap_after['Unfocused tabs'] == 14 * 7 + 8 - 20
    and gap_after['Slider handles'] == 8 and gap_after['Text'] == 14 * 7 + 8 - 4 * 7,
    tostring(gap_after['Unfocused tabs']) .. ' ' .. tostring(gap_after['Slider handles']));

-- Pointing at a swatch names it, and each row's (?) says what the row paints.
rawset(imgui, 'IsItemHovered', function () return true; end);
frames(1);
rawset(imgui, 'IsItemHovered', nil);
calls = MOCK.imgui_calls;
local unnamed, tips, inside, tip_row = nil, {}, false, nil;
for n, c in ipairs(calls) do
    if (c[1] == 'ColorEdit4' and NAMES[(c[2]:gsub('^##', ''))] ~= nil) then
        local key = c[2]:gsub('^##', '');
        -- Its tip comes before the next swatch or the row's (?).
        local named = false;
        for m = n + 1, #calls do
            local after = calls[m];
            if (after[1] == 'ColorEdit4' or after[1] == 'TextDisabled') then break; end
            if (after[1] == 'SetTooltip' and after[2] == NAMES[key]) then named = true; end
        end
        if (not named) then unnamed = key; end
    end
    if (c[1] == 'TextUnformatted' and calls[n - 1][1] == 'AlignTextToFramePadding') then tip_row = c[2]; end
    if (c[1] == 'BeginTooltip') then inside = true; end
    if (c[1] == 'EndTooltip') then inside = false; end
    if (inside and c[1] == 'TextUnformatted' and tip_row ~= nil and tips[tip_row] == nil) then tips[tip_row] = c[2]; end
    if (c[1] == 'EndTable' and tip_row ~= nil) then tip_row = nil; end
end
check('pointing at a swatch names its color', unnamed == nil, unnamed);
local bad_tip = nil;
for _, r in ipairs(rows) do
    local tip = tips[r.name];
    if (type(tip) ~= 'string' or #tip > 200 or tip:find(';', 1, true) or tip:find('[\128-\255]')) then
        bad_tip = r.name .. ': ' .. tostring(tip);
    end
end
check('each row has a short plain tip', bad_tip == nil, bad_tip);
check('the ON chips tip says where its color under the mouse comes from',
    (tips['ON chips'] or ''):find('Resize edges, hovered', 1, true) ~= nil, tips['ON chips']);
check('and the Dropdowns tip that it colors these tips too', (tips['Dropdowns'] or ''):find('these tips', 1, true) ~= nil,
    tips['Dropdowns']);
check('and the Messages tip that they\'re what the Profiles tab says', (tips['Messages'] or ''):find('Profiles tab says',
    1, true) ~= nil, tips['Messages']);

-- Picking a color in a swatch.
saves = MOCK.saved;
rawset(imgui, 'ColorEdit4', function (label, value)
    if (label == '##buttons_hovered') then value[1], value[2], value[3], value[4] = 0.2, 0.4, 0.6, 1; return true; end
    return false;
end);
frames(1);
rawset(imgui, 'ColorEdit4', nil);
local pushed_button = nil;
rawset(imgui, 'PushStyleColor', function (slot, c)
    if (slot == ImGuiCol_ButtonHovered and pushed_button == nil) then pushed_button = { c[1], c[2], c[3], c[4] }; end
end);
frames(1);
rawset(imgui, 'PushStyleColor', nil);
check('picking a color in a swatch sets it and saves', s.window_style.buttons_hovered[3] == 0.6 and MOCK.saved == saves + 1,
    MOCK.saved - saves);
check('and the window takes it', pushed_button and pushed_button[1] == 0.2 and pushed_button[3] == 0.6,
    pushed_button and table.concat(pushed_button, ' '));
check('which makes the Preset list say Custom', presets.current(s) == nil);
presets.apply(s, 'Phoenix');

-- Commands --------------------------------------------------------------------------------------------------
local function said(command)
    local before = #MOCK.printed;
    MOCK.fire('command', { command = command });
    local lines = {};
    for n = before + 1, #MOCK.printed do table.insert(lines, (MOCK.printed[n]:gsub('^%[cadence%] ', ''))); end
    return lines;
end
local function answers(command, expected)
    local saves_now = MOCK.saved;
    local lines = said(command);
    return #lines == 1 and lines[1] == expected and MOCK.saved == saves_now + 1,
        table.concat(lines, ' / ') .. ' saves ' .. (MOCK.saved - saves_now);
end
local function refuses(command, expected)
    local saves_now, state = MOCK.saved, json.encode(s);
    local lines = said(command);
    return #lines == 1 and lines[1] == expected and MOCK.saved == saves_now and json.encode(s) == state,
        table.concat(lines, ' / ') .. ' saves ' .. (MOCK.saved - saves_now);
end

-- windowfont.
for _, case in ipairs({ { 'segoe ui', 'segoeui', 'Segoe UI' }, { 'CONSOLAS', 'consolas', 'Consolas' },
        { '"Segoe UI"', 'segoeui', 'Segoe UI' }, { 'ashita', 'ashita', 'Ashita' } }) do
    local ok, detail = answers('/cadence windowfont ' .. case[1], ('The settings window uses the %s font now.')
        :format(case[3]));
    check('windowfont ' .. case[1], ok and s.window_style.font == case[2], detail);
end
local ok, detail = answers('/cadence windowfont Verdana', 'Verdana isn\'t in C:\\Windows\\Fonts\\ or won\'t load, so the '
    .. 'settings window uses Ashita\'s font.');
check('a font that won\'t load is still picked, and the answer says so', ok and s.window_style.font == 'verdana', detail);
local FONT_USAGE = 'Type /cadence windowfont <name>. The fonts are Ashita, Segoe UI, Arial, Tahoma, Verdana, Calibri '
    .. 'and Consolas.';
ok, detail = refuses('/cadence windowfont comic sans', FONT_USAGE);
check('a font that isn\'t in the list gets its own line', ok, detail);
ok, detail = refuses('/cadence windowfont', FONT_USAGE);
check('so does no name', ok, detail);
MOCK.fire('command', { command = '/cadence windowfont ashita' });

-- The number commands, each through its whole range and past both ends.
local NUMBER_COMMANDS = {
    { 'windowfontsize', 'font_size', 12, 24, 20, 'The settings window\'s font size is set to %d px.' },
    { 'windowcorners',  'rounding',  0,  12, 5,  'The settings window\'s corner roundness is set to %d px.' },
    { 'windowspacing',  'spacing',   2,  14, 9,  'The space between the settings window\'s rows is set to %d px.' },
};
for _, case in ipairs(NUMBER_COMMANDS) do
    local word, key, low, high, mid, answer = case[1], case[2], case[3], case[4], case[5], case[6];
    for _, value in ipairs({ low, high, mid }) do
        ok, detail = answers(('/cadence %s %d'):format(word, value), answer:format(value));
        check(('%s %d'):format(word, value), ok and s.window_style[key] == value, detail);
    end
    local usage = ('Type /cadence %s <%d-%d>.'):format(word, low, high);
    for _, bad in ipairs({ tostring(low - 1), tostring(high + 1), mid .. '.5', 'big', '' }) do
        ok, detail = refuses(('/cadence %s %s'):format(word, bad), usage);
        check(('%s "%s" is refused with its range'):format(word, bad), ok and s.window_style[key] == mid, detail);
    end
end
check('a number command reaches the window', (function ()
    frames(1);
    local _, c = find('PushStyleVar', nil);
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'PushStyleVar' and call[2] == ImGuiStyleVar_ItemSpacing) then c = call; break; end
    end
    return c ~= nil and c[3][2] == 9;
end)());
check('and the Preset list says Custom', presets.current(s) == nil);
presets.apply(s, 'Phoenix');

-- Every slider on the Window section has its command.
frames(1);
local COMMAND_OF = { ['Font size##window'] = 'windowfontsize', ['Corner roundness##window'] = 'windowcorners',
    ['Spacing##window'] = 'windowspacing' };
local sliders, uncommanded = 0, nil;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'SliderInt' and tostring(c[2]):find('##window$')) then
        sliders = sliders + 1;
        local word = COMMAND_OF[c[2]];
        if (word == nil or #said('/cadence ' .. word .. ' 13') ~= 1) then uncommanded = c[2]; end
    end
end
check('every slider on the Window section has a command', sliders == 3 and uncommanded == nil, uncommanded or sliders);
presets.apply(s, 'Phoenix');
s.window_style.font_size = 18;

-- windowcolor, for every window color.
local unset = nil;
for _, entry in ipairs(theme.WINDOW_COLORS) do
    ok = answers('/cadence windowcolor ' .. entry.key .. ' 336699', ('The %s window color is set to 336699.')
        :format(entry.key));
    local c = s.window_style[entry.key];
    if (not ok or c[1] ~= 0x33 / 255 or c[2] ~= 0x66 / 255 or c[3] ~= 0x99 / 255 or c[4] ~= 1) then unset = entry.key; end
end
check('windowcolor sets every window color', unset == nil, unset);
ok, detail = answers('/cadence windowcolor BUTTONS #C5515180', 'The buttons window color is set to c5515180.');
local c = s.window_style.buttons;
check('in any case, with a # and how solid it is', ok and c[1] == 0xc5 / 255 and c[4] == 0x80 / 255, detail);
frames(1);
local pushed = nil;
rawset(imgui, 'PushStyleColor', function (slot, color)
    if (slot == ImGuiCol_Button and pushed == nil) then pushed = color[4]; end
end);
frames(1);
rawset(imgui, 'PushStyleColor', nil);
check('and the window takes it', pushed == 0x80 / 255, pushed);
local COLOR_USAGE = 'Type /cadence windowcolor <what> <rrggbb>. /cadence help windowcolors lists the window colors.';
for _, command in ipairs({ '/cadence windowcolor', '/cadence windowcolor buttons' }) do
    ok, detail = refuses(command, COLOR_USAGE);
    check('"' .. command .. '" gets the usage line', ok, detail);
end
ok, detail = refuses('/cadence windowcolor buttonz 336699', 'There\'s no window color called "buttonz". /cadence help '
    .. 'windowcolors lists them.');
check('a window color that isn\'t there', ok, detail);
for _, bad in ipairs({ '33669', '3366991', 'zz6699', '#', '336699ccc' }) do
    ok, detail = refuses('/cadence windowcolor buttons ' .. bad, ('"%s" isn\'t a color. Type six hex digits like '
        .. 'c55151, or eight like c55151cc to make it see-through.'):format(bad));
    check('"' .. bad .. '" isn\'t a color', ok, detail);
end
presets.apply(s, 'Phoenix');

-- Help ---------------------------------------------------------------------------------------------------
local lines = said('/cadence help window');
local WINDOW_HELP = {
    '/cadence tips [on|off]  sets Timer hover help.',
    '/cadence windowfont <name>  picks the settings window\'s font, with or without its spaces. The fonts are Ashita, '
        .. 'Segoe UI, Arial, Tahoma, Verdana, Calibri and Consolas.',
    '/cadence windowfontsize <12-24>  sets the settings window\'s font size.',
    '/cadence windowcorners <0-12>  sets how round the settings window\'s corners are.',
    '/cadence windowspacing <2-14>  sets the space between the settings window\'s rows.',
    '/cadence windowcolor <what> <rrggbb>  sets one of the settings window\'s colors. /cadence help windowcolors lists '
        .. 'them.',
    '/cadence chatcolor <what> <color>  sets one of cadence\'s chat colors. /cadence help chatcolors lists them.',
};
check('help window', table.concat(lines, '\n') == table.concat(WINDOW_HELP, '\n'), table.concat(lines, ' / '));
lines = said('/cadence help windowcolors');
local COLORS_HELP = {
    '/cadence windowcolor <what> <rrggbb>  sets one of the settings window\'s colors. <what> is one of these, under the '
        .. 'Window colors section in Appearance.',
    'TEXT  text, faded_text, headings, heading_lines, notes, done_messages, problem_messages, selected_text, '
        .. 'text_cursor',
    'WINDOW  background, border, title_bar, title_bar_unfocused, resize_corner, resize_corner_hovered, '
        .. 'resize_corner_held, resize_edges_hovered, resize_edges_held, scrollbar_track, scrollbar, scrollbar_hovered, '
        .. 'scrollbar_held',
    'BOXES AND BUTTONS  boxes, boxes_hovered, boxes_clicked, check_marks, slider_handles, slider_handles_held, buttons, '
        .. 'buttons_hovered, buttons_pressed, on_chips, on_chip_text, dropdowns, row_picked, row_hovered, row_clicked',
    'TABS  tabs, tabs_hovered, open_tab, open_tab_line, tabs_unfocused, open_tab_unfocused, open_tab_line_unfocused',
    'The color is six hex digits like c55151. Two more, from 00 to ff, set how solid it is, like c55151cc.',
};
check('help windowcolors lists every window color under its heading', table.concat(lines, '\n')
    == table.concat(COLORS_HELP, '\n'), table.concat(lines, ' / '));
local appearance = said('/cadence help appearance');
local look = said('/cadence help look');
check('help appearance joins timer style, window and window colors, and the old help aliases still work',
    table.concat(appearance, '\n') == table.concat(look, '\n') .. '\n'
        .. table.concat(WINDOW_HELP, '\n') .. '\n' .. table.concat(COLORS_HELP, '\n'));
lines = said('/cadence help');
local pointer, timers_at = nil, nil;
for n, line in ipairs(lines) do
    if (line == '/cadence help attack|resting|enemy|recovery|enemycast|appearance|colors|preset|font|reset|chatcolors|profiles|preview|details|ui  '
        .. 'tells you more about one of them.') then
        pointer = n;
    end
    if (line == 'Timers tab') then timers_at = n; end
end
check('the whole help points to them, before the tabs', pointer ~= nil and timers_at ~= nil and pointer < timers_at,
    tostring(pointer));

-- What chat says reads like everything else in cadence.
local odd = nil;
for _, line in ipairs(MOCK.printed) do
    if (line:find(';', 1, true) or line:find('[\128-\255]')) then odd = line; end
end
check('no semicolons or odd characters in anything said', odd == nil, odd);
check('no drawing errors', drawing_error() == nil, drawing_error());

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
