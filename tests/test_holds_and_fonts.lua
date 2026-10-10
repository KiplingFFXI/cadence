-- The enemy timer's "TP move" and "casting", and picking a font.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

-- A few Windows fonts, and two of your own in cadence's fonts folder.
local WINDOWS = 'C:\\Windows\\Fonts\\';
for _, file in ipairs({ 'seguisb.ttf', 'tahomabd.ttf', 'verdanab.ttf', 'calibrib.ttf' }) do
    MOCK.fs[WINDOWS .. file] = true;
end
local FOLDER = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\fonts\\';
MOCK.fs[FOLDER] = true;
MOCK.dirs = { [FOLDER] = { 'Zed.otf', 'Alpha.ttf' } };
MOCK.fs[FOLDER .. 'Zed.otf'] = true;
MOCK.fs[FOLDER .. 'Alpha.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local hud = require('ui.hud');
local enemy = require('core.enemy');
local theme = require('ui.theme');
local imgui = require('imgui');

-- TP move and casting ---------------------------------------------------------------------------------
local ME, MOB = 1001, 0x01000200;
s.enemy.enabled = true;
MOCK.now = 100;
local function packet(p) MOCK.fire('packet_in', p); end
for _ = 1, 4 do MOCK.now = MOCK.now + 4.0; packet(MOCK.action_packet(MOB, 1, 0, ME, { { message = 1 } })); end

MOCK.now = MOCK.now + 1.0;
packet(MOCK.action_packet(MOB, 7, 0x6163, ME, { { message = 0 } }));
check('a monster readying a TP move', select(7, enemy.progress(MOCK.now, MOB)) == 'tp_move');
packet(MOCK.action_packet(MOB, 11, 569, ME, { { message = 0 } }));
check('gone once it finishes', select(7, enemy.progress(MOCK.now, MOB)) == nil);
MOCK.now = MOCK.now + 4.0;
packet(MOCK.action_packet(MOB, 1, 0, ME, { { message = 1 } }));
MOCK.now = MOCK.now + 1.0;
packet(MOCK.action_packet(MOB, 8, 0x6163, ME, { { message = 0 } }));
check('a monster casting', select(7, enemy.progress(MOCK.now, MOB)) == 'spell');
packet(MOCK.action_packet(MOB, 8, 0x7073, ME, { { message = 0 } }));
check('gone once it\'s cut off', select(7, enemy.progress(MOCK.now, MOB)) == nil);

local function enemy_value(holding)
    hud.refresh(s);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.draw_enemy({ fill = 0.4, left = 2.3, delay = 4.0, learned = true, waiting = false, name = 'Goblin',
        holding = holding });
    hud.end_frame();
    MOCK.record_imgui = false;
    -- The last copy is the text itself. A shadow comes before it.
    local found, found_color = nil, nil;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddText' and (c[6] == 'TP move' or c[6] == 'casting' or c[6] == '2.3')) then
            found, found_color = c[6], c[5];
        end
    end
    return found, found_color;
end
local almost = theme.u32(s.enemy.almost_color);
local text, color = enemy_value('tp_move');
check('the timer says TP move', text == 'TP move' and color == almost, tostring(text));
check('or casting', enemy_value('spell') == 'casting');
check('and the seconds otherwise', enemy_value(nil) == '2.3');
s.enemy.show_holds = false;
check('turned off, it keeps the seconds', enemy_value('tp_move') == '2.3');
s.enemy.show_holds = true;

-- Holds still show when every other part of the text row is off.
local saved = {};
for _, key in ipairs({ 'show_label', 'show_value', 'show_name', 'show_delay', 'show_effects' }) do
    saved[key] = s.enemy[key];
    s.enemy[key] = false;
end
check('TP move can show by itself', enemy_value('tp_move') == 'TP move');
local _, holding_height = hud.element_size('enemy');
check('casting can show by itself', enemy_value('spell') == 'casting');
check('no seconds with only holds on', enemy_value(nil) == nil);
local _, quiet_height = hud.element_size('enemy');
check('the hold row keeps its height', holding_height == quiet_height);
s.enemy.show_holds = false;
check('holds off leaves just the bar', enemy_value('spell') == nil);
local _, bar_height = hud.element_size('enemy');
check('holds alone reserve the text row', holding_height > bar_height);
for key, value in pairs(saved) do s.enemy[key] = value; end
s.enemy.show_holds = true;
s.enemy.enabled = false;

-- Fonts -----------------------------------------------------------------------------------------------
local names = table.concat(hud.font_names(), ', ');
check('the fonts found, in list order, then your own sorted',
    names == 'Segoe UI Semibold, Tahoma Bold, Verdana Bold, Calibri Bold, Alpha, Zed', names);
check('a font that isn\'t installed isn\'t listed', not names:find('Arial', 1, true));

local function face()
    hud.refresh(s);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.draw_attack(0.5, 1.5, 3.0, true, nil);
    hud.end_frame();
    MOCK.record_imgui = false;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddText' and c[6] == 'AUTO ATTACK') then return c[2]; end
    end
end
check('Segoe UI Semibold by default', face() == 'font:' .. WINDOWS .. 'seguisb.ttf', face());
s.style.font_name = 'Verdana Bold';
check('a font you pick', face() == 'font:' .. WINDOWS .. 'verdanab.ttf' and hud.font_in_use() == 'Verdana Bold', face());
s.style.font_name = 'Alpha';
check('one of your own', face() == 'font:' .. FOLDER .. 'Alpha.ttf', face());
s.style.font_name = 'Gone Font';
check('a font that\'s gone falls back to the first', face() == 'font:' .. WINDOWS .. 'seguisb.ttf'
    and hud.font_in_use() == 'Segoe UI Semibold', face());
s.style.system_font = false;
check('Ashita\'s own font', face() == 'default_font' and hud.font_in_use() == nil, face());
s.style.system_font = true;

-- Picking from the dropdown in the settings window.
local pick = nil;
rawset(imgui, 'BeginCombo', function (label) return label == 'Font'; end);
rawset(imgui, 'Selectable', function (label) return label == pick; end);
MOCK.fire('command', { command = '/cadence' });
pick = 'Ashita';
MOCK.frame(1 / 60);
check('picking Ashita', s.style.system_font == false);
pick = 'Calibri Bold';
MOCK.frame(1 / 60);
check('picking a font from the list turns them back on', s.style.system_font and s.style.font_name == 'Calibri Bold',
    s.style.font_name);
pick = nil;
rawset(imgui, 'BeginCombo', nil);
rawset(imgui, 'Selectable', nil);

-- The list fits its longest name, so ImGui doesn't cut it off. The width set just before it.
local function font_list_width()
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    local width = nil;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'SetNextItemWidth') then width = c[2]; end
        if (c[1] == 'BeginCombo' and c[2] == 'Font') then return width; end
    end
    return nil;
end
check('the Font list is as wide as the other controls while every name fits', font_list_width() == 190,
    font_list_width());
-- Every letter 10 wide. Segoe UI Semibold is the longest at 170, and the list adds 16 of padding and its
-- 26 wide arrow.
MOCK.measure = function (words) return #words * 10; end
check('it grows to fit the longest name', font_list_width() == 170 + 16 + 26, font_list_width());
-- The column has 280 - 4 - 40 - 8 - 30 left next to the word Font and the (?).
MOCK.content_width = 280;
check('but never past the room its column has', font_list_width() == 198, font_list_width());
MOCK.content_width, MOCK.measure = nil, nil;
MOCK.fire('command', { command = '/cadence' });

require('ui.presets').reset(s);
check('reset look puts the default font back', s.style.system_font and s.style.font_name == 'Segoe UI Semibold');

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
