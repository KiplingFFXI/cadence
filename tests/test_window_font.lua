-- The settings window's font and font size. The fonts load once on the load event, the window draws in
-- the one you have at your size, and a font that didn't load leaves it in Ashita's font with a note.
-- Its layout grows with a bigger font, its smallest size has room for one column with wrapping tabs, and it moves to another character's spot when they log in. Presets leave the font
-- alone, Reset look puts it back, Undo takes that back, and the settings check keeps it sane.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

--[[
    ImGui's window placement, like test_on_screen.lua. A spot or size set with Always, or with Appearing
    on a window that wasn't drawn last frame, is used. An open window keeps where it is otherwise.
]]
ImGuiCond_Appearing = 777;
local imgui = require('imgui');
local WINDOW = 'cadence##cadence_settings';
local win, stack, frame_no = {}, {}, 0;
local next_pos, next_size = nil, nil;
local function applies(cond, w)
    return cond == ImGuiCond_Always or (cond == ImGuiCond_Appearing and w.last < frame_no - 1);
end
-- Each call here goes in MOCK.imgui_calls too, the way the mock records them.
local function record(...)
    if (MOCK.record_imgui) then
        local args = { ... };
        for i, v in ipairs(args) do
            if (type(v) == 'table') then args[i] = { v[1], v[2] }; end
        end
        table.insert(MOCK.imgui_calls, args);
    end
end
-- The font pushed last, and the one pushed just before the settings window began. The mock's record
-- of a call keeps only a table's first two values, so a font face is kept here as it is.
local last_push, window_push = nil, nil;
local mock_push = imgui.PushFont;
rawset(imgui, 'PushFont', function (font, size)
    last_push = { font = font, size = size };
    mock_push(font, size);
end);
rawset(imgui, 'SetNextWindowPos', function (pos, cond)
    record('SetNextWindowPos', pos, cond);
    next_pos = { pos[1], pos[2], cond };
end);
rawset(imgui, 'SetNextWindowSize', function (size, cond)
    record('SetNextWindowSize', size, cond);
    next_size = { size[1], size[2], cond };
end);
rawset(imgui, 'Begin', function (name)
    record('Begin', name);
    if (name == WINDOW) then window_push = last_push; end
    local w = win[name] or { x = 0, y = 0, width = 920, height = 680, last = -10 };
    win[name] = w;
    if (next_pos ~= nil and applies(next_pos[3], w)) then w.x, w.y = next_pos[1], next_pos[2]; end
    if (next_size ~= nil and applies(next_size[3], w)) then w.width, w.height = next_size[1], next_size[2]; end
    if (MOCK.window_size ~= nil and name:find('settings', 1, true)) then
        w.width, w.height = MOCK.window_size[1], MOCK.window_size[2];
    end
    next_pos, next_size = nil, nil;
    w.last = frame_no;
    table.insert(stack, name);
    return true;
end);
rawset(imgui, 'End', function () record('End'); table.remove(stack); end);
rawset(imgui, 'GetWindowPos', function () local w = win[stack[#stack]]; return w.x, w.y; end);
rawset(imgui, 'GetWindowSize', function () local w = win[stack[#stack]]; return w.width, w.height; end);

-- Windows fonts. Segoe UI and Consolas load. Tahoma raises an error and Calibri loads as nothing. Verdana
-- and Arial aren't there. Each font that loads is a table naming its file and size.
local FOLDER = 'C:\\Windows\\Fonts\\';
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
for _, file in ipairs({ 'seguisb.ttf', 'segoeui.ttf', 'consola.ttf', 'tahoma.ttf', 'calibri.ttf' }) do
    MOCK.fs[FOLDER .. file] = true;
end
local font_calls = {};
rawset(imgui, 'AddFontFromFileTTF', function (path, size)
    table.insert(font_calls, path);
    if (path:find('tahoma.ttf', 1, true)) then error('bad font file'); end
    if (path:find('calibri.ttf', 1, true)) then return nil; end
    return { path = path, size = size };
end);

MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
local window_font = require('ui.window_font');
local defaults = require('ui.defaults');
local presets = require('ui.presets');
local before_load = #font_calls;
local loaded_ok, load_error = pcall(MOCK.fire, 'load');
check('the load event gets past a font that raises an error', loaded_ok, load_error);
local s = MOCK.settings.current;

local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n or 1 do
        frame_no = frame_no + 1;
        MOCK.frame(1 / 60);
    end
    MOCK.record_imgui = false;
end
local function calls(name, match)
    local found = {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == name and (match == nil or match(c))) then table.insert(found, c); end
    end
    return found;
end
-- The settings window's last call named `name` before it began last frame, or with `after_end`, the
-- call right after its End.
local function window_call(name, after_end)
    local began, ended = nil, nil;
    for i, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'Begin' and c[2] == WINDOW) then began, ended = i, nil; end
        if (began and not ended and c[1] == 'End') then ended = i; end
    end
    if (began == nil) then return nil; end
    if (after_end) then return ended and MOCK.imgui_calls[ended + 1]; end
    for i = began - 1, 1, -1 do
        local c = MOCK.imgui_calls[i];
        if (c[1] == 'End') then return nil; end
        if (c[1] == name) then return c; end
    end
    return nil;
end
local function pushed_font()
    return window_push and window_push.font, window_push and window_push.size;
end
local function drawing_error()
    for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped', 1, true)) then return line; end end
    return nil;
end

-- The list --------------------------------------------------------------------------------------------
local ids = {};
for _, entry in ipairs(window_font.LIST) do table.insert(ids, entry.id); end
check('the fonts are checkmate\'s, Ashita\'s first', table.concat(ids, ' ')
    == 'ashita segoeui arial tahoma verdana calibri consolas', table.concat(ids, ' '));
check('sizes go 12 to 24, 18 by default', window_font.SIZE_MIN == 12 and window_font.SIZE_MAX == 24
    and window_font.SIZE_DEFAULT == 18);
local odd = nil;
for _, entry in ipairs(window_font.LIST) do
    if (entry.name:lower():gsub('[^%w]', '') ~= entry.id) then odd = entry.id; end
end
check('each id is its name in lowercase with the spaces taken out', odd == nil, odd);
local function found(word)
    local entry = window_font.find(word);
    return entry and entry.id or 'nothing';
end
local finds = ('%s %s %s %s %s'):format(found('Segoe UI'), found('SEGOE-UI'), found('Consolas'), found('Comic Sans'),
    found(nil));
check('a font is found by its name in any case, with or without spaces',
    finds == 'segoeui segoeui consolas nothing nothing', finds);
check('an unknown id becomes Ashita\'s', window_font.clean_id('comic') == 'ashita' and window_font.clean_id(nil) == 'ashita'
    and window_font.clean_id('tahoma') == 'tahoma');
check('Ashita\'s font has no file', window_font.path('ashita') == nil
    and window_font.path('consolas') == FOLDER .. 'consola.ttf', window_font.path('consolas'));

-- Loading ---------------------------------------------------------------------------------------------
local mine = {};
for i = before_load + 1, #font_calls do
    local file = font_calls[i]:match('([^\\]+)$');
    if (file == 'segoeui.ttf' or file == 'consola.ttf' or file == 'tahoma.ttf' or file == 'calibri.ttf'
        or file == 'arial.ttf' or file == 'verdana.ttf') then
        mine[file] = (mine[file] or 0) + 1;
    end
end
check('the load event tries each window font that\'s there, once', mine['consola.ttf'] == 1 and mine['tahoma.ttf'] == 1
    and mine['calibri.ttf'] == 1 and mine['arial.ttf'] == nil and mine['verdana.ttf'] == nil);
check('Segoe UI is in the timers\' list and the window\'s, and loads once', mine['segoeui.ttf'] == 1, mine['segoeui.ttf']);
local segoe, consolas = window_font.face('segoeui'), window_font.face('consolas');
check('each font loads at 18 px from the fonts folder', type(segoe) == 'table' and segoe.path == FOLDER .. 'segoeui.ttf'
    and segoe.size == 18 and type(consolas) == 'table' and consolas.path == FOLDER .. 'consola.ttf');
local hud = require('ui.hud');
local timer_font = { s.style.system_font, s.style.font_name };
s.style.system_font, s.style.font_name = true, 'Segoe UI';
hud.refresh(s);
hud.begin_frame();
hud.draw_attack(0.5, 1.5, 3.0, true, nil);
hud.end_frame();
check('the timers draw Segoe UI with the window\'s face', last_push ~= nil and last_push.font == segoe,
    last_push and tostring(last_push.font));
s.style.system_font, s.style.font_name = timer_font[1], timer_font[2];
hud.refresh(s);
check('Ashita\'s own has no face of its own', window_font.face('ashita') == nil and not window_font.failed('ashita'));
check('a font that\'s missing, raised an error or loaded as nothing failed', window_font.failed('verdana')
    and window_font.failed('arial') and window_font.failed('tahoma') and window_font.failed('calibri')
    and window_font.face('tahoma') == nil and window_font.face('calibri') == nil);
check('the ones that loaded didn\'t', not window_font.failed('segoeui') and not window_font.failed('consolas'));
check('an unknown font didn\'t fail, it\'s cleaned up by the settings check', not window_font.failed('comic'));

-- The window draws in your font -------------------------------------------------------------------------
MOCK.now = 100;
MOCK.fire('command', { command = '/cadence' });
frames(2);
local loaded_at_open = #font_calls;
local face, size = pushed_font();
check('by default it draws in Ashita\'s font at 18 px', face == 'default_font' and size == 18
    and window_call('PushFont') ~= nil, tostring(face) .. ' ' .. tostring(size));
local after = window_call(nil, true);
check('and pops it once the window ends', after ~= nil and after[1] == 'PopFont' and #MOCK.font_stack == 0,
    after and after[1]);

s.window_style.font, s.window_style.font_size = 'segoeui', 22;
frames(1);
face, size = pushed_font();
check('Segoe UI at 22 px draws with the face the load event made', face == segoe and size == 22, tostring(size));
local function said(words)
    for _, c in ipairs(calls('TextUnformatted')) do
        if (tostring(c[2]):find(words, 1, true)) then return true; end
    end
    return false;
end
check('with no note', not said('won\'t load'));

s.window_style.font = 'verdana';
frames(2);
face, size = pushed_font();
check('a missing font draws in Ashita\'s font at your size', face == 'default_font' and size == 22, tostring(face));
check('and says so', said('Verdana isn\'t in C:\\Windows\\Fonts\\ or won\'t load, so this window uses Ashita\'s font.'));
-- The note sits on the Window section, between Font size and the SHAPE heading, not above the tabs.
local note_at, size_at, shape_at, bar_at = nil, nil, nil, nil;
for i, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'TextUnformatted' and tostring(c[2]):find('Verdana isn\'t in', 1, true)) then note_at = i; end
    if (c[1] == 'SliderInt' and c[2] == 'Font size##window') then size_at = i; end
    if (c[1] == 'TextColored' and c[3] == 'SHAPE') then shape_at = i; end
    if (c[1] == 'BeginTabBar') then bar_at = i; end
end
check('under Font size on the Window section', note_at and size_at and shape_at and bar_at and bar_at < size_at
    and size_at < note_at and note_at < shape_at, ('%s %s %s %s'):format(tostring(bar_at), tostring(size_at),
    tostring(note_at), tostring(shape_at)));
check('with no error', drawing_error() == nil, drawing_error());
s.window_style.font = 'tahoma';
frames(1);
face = pushed_font();
check('a font that raised an error draws in Ashita\'s font too', face == 'default_font' and said('Tahoma isn\'t in'));
s.window_style.font = 'calibri';
frames(1);
face = pushed_font();
check('and so does one that loaded as nothing', face == 'default_font' and said('Calibri isn\'t in'));
s.window_style.font = 'consolas';
frames(1);
face = pushed_font();
check('Consolas draws in its own face', face == consolas and not said('won\'t load'));
check('none of that loaded a font', #font_calls == loaded_at_open, #font_calls - loaded_at_open);

-- The layout grows with the font -------------------------------------------------------------------------
local function width_before(label)
    local list_ = MOCK.imgui_calls;
    for i, c in ipairs(list_) do
        if (c[1] == 'SliderFloat' and c[2] == label) then
            for j = i - 1, 1, -1 do
                if (list_[j][1] == 'SetNextItemWidth') then return list_[j][2]; end
            end
        end
    end
    return nil;
end
local function chip_width()
    local c = calls('Button', function (c) return c[2] == 'ON##attack'; end)[1];
    return c and c[3] and c[3][1];
end
local function tip_width()
    rawset(imgui, 'IsItemHovered', function () return true; end);
    frames(1);
    rawset(imgui, 'IsItemHovered', nil);
    local c = calls('PushTextWrapPos', function (c) return (c[2] or 0) > 0; end)[1];
    return c and c[2];
end
local function second_column()
    local found = nil;
    local list_ = MOCK.imgui_calls;
    for i, c in ipairs(list_) do
        if (c[1] == 'Checkbox' and c[2] == 'Weapon delay##attack' and list_[i - 1][1] == 'SameLine') then
            found = list_[i - 1][2];
        end
    end
    return found;
end
local function chip_spot()
    local list_ = MOCK.imgui_calls;
    for i, c in ipairs(list_) do
        if (c[1] == 'Button' and c[2] == 'ON##attack') then
            for j = i - 1, 1, -1 do
                if (list_[j][1] == 'SetCursorPosX') then return list_[j][2]; end
            end
        end
    end
    return nil;
end
local function layout(font_size)
    s.window_style.font_size = font_size;
    frames(1);
    return { width_before('Scale'), chip_width(), second_column(), chip_spot(), tip_width() };
end
local function show(t)
    local words = {};
    for i = 1, 5 do words[i] = tostring(t[i]); end
    return table.concat(words, ' ');
end

local at18 = layout(18);
check('at 18 px controls keep base sizes and readouts have their own rows', show(at18) == '190 52 nil 740 300', show(at18));
local at24 = layout(24);
check('at 24 px controls, chips and tips are a third wider', show(at24) == '253 69 nil 723 400',
    show(at24));
local at12 = layout(12);
check('at 12 px they keep their 18 px sizes, so nothing runs into the next thing', show(at12) == show(at18), show(at12));
local at21 = layout(21);
check('at 21 px they round to whole pixels', show(at21) == '222 61 nil 731 350', show(at21));

local function constraints()
    local c = calls('SetNextWindowSizeConstraints')[1];
    return c and (c[2][1] .. 'x' .. c[2][2]) or 'none';
end
s.window_style.font_size = 18;
frames(1);
check('the smallest window fits one column with wrapping tabs at 18 px', constraints() == '464x440', constraints());
s.window_style.font_size = 24;
frames(1);
check('and grows with a bigger font', constraints() == '604x587', constraints());
s.window_style.font_size = 12;
frames(1);
check('but not smaller than at 18 px', constraints() == '464x440', constraints());
s.window_style.font_size = 24;
MOCK.screen = { 500, 300 };
frames(1);
check('on a screen too small for it, it\'s cut down to the screen', constraints() == '500x300', constraints());
MOCK.screen = nil;
-- Wide tab names wrap without forcing a window wider than its controls.
s.window_style.font_size = 18;
MOCK.screen = { 2200, 1200 };
MOCK.measure = function (words) return #words * 30; end
frames(1);
MOCK.measure = nil;
check('wide tab names do not widen the minimum window', constraints() == '464x440', constraints());
MOCK.measure = function (words) return #words * 30 - 0.5; end
frames(1);
MOCK.measure = nil;
check('fractional tab widths keep the same column minimum', constraints() == '464x440', constraints());
MOCK.screen = nil;

local function columns()
    local c = calls('BeginTable', function (c) return c[2] == '##timer_sections'; end)[1];
    return c and c[3];
end
local TWO_AT = 2 * 420 + 24 + 44;
MOCK.window_size = { 920, 680 };
frames(1);
check('at 18 px the default window has two columns', columns() == 2, columns());
MOCK.window_size = { TWO_AT - 1, 680 };
frames(1);
check(('and needs %d for them'):format(TWO_AT), columns() == 1, columns());
s.window_style.font_size = 24;
MOCK.window_size = { 920, 680 };
frames(1);
check('at 24 px the default window stacks them', columns() == 1, columns());
local two_at_24 = 2 * 560 + 24 + 44;
MOCK.window_size = { two_at_24, 680 };
frames(1);
check(('and gets two at %d'):format(two_at_24), columns() == 2, columns());
MOCK.window_size = { two_at_24 - 1, 680 };
frames(1);
check('but not a pixel before', columns() == 1, columns());
s.window_style.font_size = 12;
MOCK.window_size = { TWO_AT - 1, 680 };
frames(1);
check('a smaller font doesn\'t bring two columns sooner', columns() == 1, columns());
MOCK.window_size = { TWO_AT, 680 };
frames(1);
check('they come at the same width as at 18 px', columns() == 2, columns());
MOCK.window_size = nil;
s.window_style.font_size = 18;

-- A wider font grows the layout too ------------------------------------------------------------------------
-- Like the game at 18 px, Consolas draws each letter 10 wide, Ashita's font 9 and Segoe UI 8. CalcTextSize
-- measures in the face pushed last. Each face's pushes are counted.
local faces, pushed = {}, {};
local track_push, mock_pop = rawget(imgui, 'PushFont'), imgui.PopFont;
rawset(imgui, 'PushFont', function (font, size)
    pushed[font] = (pushed[font] or 0) + 1;
    table.insert(faces, font);
    track_push(font, size);
end);
rawset(imgui, 'PopFont', function () table.remove(faces); mock_pop(); end);
local LETTER = { [consolas] = 10, [segoe] = 8 };
MOCK.measure = function (words, size) return #words * (LETTER[faces[#faces]] or 9) * size / 18; end
s.window_style.font = 'ashita';
local ashita_layout = layout(18);
s.window_style.font = 'segoeui';
local narrow_layout = layout(18);
s.window_style.font = 'consolas';
local wide_layout = layout(18);
check('Ashita\'s font at 18 px keeps the 18 px layout', show(ashita_layout) == show(at18), show(ashita_layout));
check('so does a narrower font', show(narrow_layout) == show(at18), show(narrow_layout));
check('Consolas draws a ninth wider at 18 px, so its layout is a ninth wider', show(wide_layout)
    == '211 58 nil 734 333', show(wide_layout));
MOCK.window_size = { 920, 680 };
frames(1);
check('and the default window stacks its sections, like Ashita\'s font at 20 px', columns() == 1, columns());
MOCK.window_size = nil;
pushed = {};
frames(2);
check('the width is measured only when the font or its size changes, not every frame', pushed[consolas] == 2
    and pushed.default_font == nil, tostring(pushed[consolas]) .. ' ' .. tostring(pushed.default_font));
s.window_style.font_size = 20;
pushed = {};
frames(1);
check('a new size measures it again, in Consolas and in Ashita\'s font at 18 px', pushed[consolas] == 2
    and pushed.default_font == 1, tostring(pushed[consolas]) .. ' ' .. tostring(pushed.default_font));
check('at 20 px Consolas grows the layout by its width, more than the size alone would',
    width_before('Scale') == math.floor(190 * 200 / 162 + 0.5), width_before('Scale'));
rawset(imgui, 'PushFont', track_push);
rawset(imgui, 'PopFont', nil);
MOCK.measure = nil;
-- A new size measures it again with every letter as wide.
s.window_style.font_size = 18;
frames(1);
check('with every font as wide, Consolas has the 18 px layout', width_before('Scale') == 190, width_before('Scale'));

-- Pages keep a separate scrolling region below navigation.
frames(1);
local pages, all_usable = 0, true;
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'BeginChild' and tostring(call[2]):find('##page_', 1, true)) then
        pages = pages + 1;
        all_usable = all_usable and call[3][1] == 0 and call[3][2] > 0;
    end
end
check('every settings page has its own usable scrolling region', pages == 6 and all_usable, pages);

-- Another character logging in moves the open window ----------------------------------------------------------
-- Where ImGui has the settings window, or a blank one when it wasn't drawn.
local function placed() return win[WINDOW] or { x = 0, y = 0, width = 0, height = 0 }; end
MOCK.window_size = nil;
frames(2);
placed().x, placed().y = 300, 200;
frames(2);
check('the window was moved', s.window.x == 300 and s.window.y == 200, s.window.x .. ',' .. s.window.y);
local saves = MOCK.saved;
MOCK.settings.switch_character({ window = { x = 10, y = 20, width = 800, height = 600 } });
s = MOCK.settings.current;
frames(1);
local pos = window_call('SetNextWindowPos');
check('the next frame puts it at their spot at once', pos ~= nil and pos[2][1] == 10 and pos[2][2] == 20
    and pos[3] == ImGuiCond_Always, pos and pos[3]);
check('at their size', placed().width == 800 and placed().height == 600, placed().width .. 'x' .. placed().height);
frames(2);
check('and the old spot doesn\'t save over theirs', s.window.x == 10 and s.window.y == 20 and s.window.width == 800,
    s.window.x .. ',' .. s.window.y .. ' ' .. s.window.width);
check('it saved nothing for that', MOCK.saved == saves, MOCK.saved - saves);
pos = window_call('SetNextWindowPos');
check('after that it\'s back to placing it only as it opens', pos ~= nil and pos[3] == ImGuiCond_Appearing,
    pos and pos[3]);
MOCK.settings.switch_character({ window = { x = 40, y = 30, width = 840, height = 590 } });
s = MOCK.settings.current;
frames(2);
check('another character\'s window opens at its own spot and size', s.window.width == 840 and s.window.height == 590
    and placed().width == 840 and s.window.x == 40, s.window.width .. 'x' .. s.window.height);
MOCK.settings.switch_character({ window_style = { font = 'consolas', font_size = 20 } });
s = MOCK.settings.current;
frames(1);
face, size = pushed_font();
check('their own font and size draw at once', face == consolas and size == 20, tostring(size));

-- Presets, Reset look and Undo ------------------------------------------------------------------------------
s.window_style.font, s.window_style.font_size = 'segoeui', 22;
local kept = true;
for _, name in ipairs(presets.NAMES) do
    presets.apply(s, name);
    if (s.window_style.font ~= 'segoeui' or s.window_style.font_size ~= 22 or presets.current(s) ~= name) then
        kept = name;
    end
end
check('every preset leaves the font alone and still shows as itself', kept == true, kept);
s.style.window_matches_look = false;
presets.apply(s, 'Classic FFXI');
check('with Window matches the look off too', s.window_style.font == 'segoeui' and s.window_style.font_size == 22);
s.style.window_matches_look = true;
presets.undo(s);
check('and Undo of a preset leaves it', s.window_style.font == 'segoeui' and s.window_style.font_size == 22);
MOCK.settings.callbacks.cadence_settings_update(s);
MOCK.fire('command', { command = '/cadence reset look' });
check('Reset look puts Ashita\'s font back at 18 px', s.window_style.font == 'ashita' and s.window_style.font_size == 18,
    s.window_style.font .. ' ' .. s.window_style.font_size);
MOCK.fire('command', { command = '/cadence undo' });
check('Undo takes that back', s.window_style.font == 'segoeui' and s.window_style.font_size == 22,
    s.window_style.font .. ' ' .. s.window_style.font_size);
local help_line = nil;
local printed = #MOCK.printed;
MOCK.fire('command', { command = '/cadence help reset' });
for i = printed + 1, #MOCK.printed do
    if (MOCK.printed[i]:find('reset look', 1, true)) then help_line = MOCK.printed[i]; end
end
check('/cadence help reset says so', help_line ~= nil and help_line:find('the settings window\'s look and font back', 1, true)
    ~= nil, help_line);
MOCK.fire('command', { command = '/cadence reset all' });
MOCK.fire('command', { command = '/cadence reset all' });
check('Reset all puts it back too', s.window_style.font == 'ashita' and s.window_style.font_size == 18);

-- The settings check ---------------------------------------------------------------------------------------
local fresh = defaults.make();
check('the defaults are Ashita\'s font at 18 px', fresh.window_style.font == 'ashita' and fresh.window_style.font_size == 18);
local range = defaults.RANGES.window_style.font_size;
check('its size goes 12 to 24', range and range[1] == 12 and range[2] == 24);
local function tidied(font, font_size)
    local t = defaults.make();
    t.window_style.font, t.window_style.font_size = font, font_size;
    defaults.tidy(t);
    return t.window_style.font .. ' ' .. tostring(t.window_style.font_size);
end
check('a font it doesn\'t know becomes Ashita\'s', tidied('comic', 20) == 'ashita 20', tidied('comic', 20));
check('and so does one that isn\'t a word', tidied(5, 20) == 'ashita 20', tidied(5, 20));
check('a size past either end is pulled in', tidied('tahoma', 40) == 'tahoma 24' and tidied('tahoma', 3) == 'tahoma 12',
    tidied('tahoma', 40) .. ' / ' .. tidied('tahoma', 3));
check('a size that isn\'t a number gets 18', tidied('arial', 'big') == 'arial 18' and tidied('arial', 0 / 0) == 'arial 18',
    tidied('arial', 'big'));
check('a normal one comes through as it is', tidied('verdana', 13) == 'verdana 13', tidied('verdana', 13));
s.window_style.font, s.window_style.font_size = 'nope', 99;
MOCK.fire('command', { command = '/cadence lock' });
check('a save checks them first', s.window_style.font == 'ashita' and s.window_style.font_size == 24);
MOCK.fire('command', { command = '/cadence unlock' });

check('no drawing errors', drawing_error() == nil, drawing_error());

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
