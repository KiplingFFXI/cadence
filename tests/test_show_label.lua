-- Each timer's own switch for its name. It hides just that name, and the seconds and small text stay.
-- Show labels still hides all three. A row with nothing left goes away like it does with Show labels
-- off. Reset look turns the switch back on, and the settings window has a box in front of each label.
-- Show labels itself sits at the right end of the LABELS heading.
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
local hud = require('ui.hud');
local presets = require('ui.presets');
local defaults = require('ui.defaults');
local imgui = require('imgui');

local d = defaults.make();
check('on for all three by default', d.attack.show_label == true and d.resting.show_label == true
    and d.enemy.show_label == true);
check('Show labels is still on by default', d.style.show_labels == true);

-- Draws one timer and returns where each piece of text went. With no shadow, each text is drawn once.
s.style.text_shadow = false;
local RESTING = { fill = 0.5, left = 4.0, gained_hp = 24, gained_mp = 0, full = false, has_mp = true, flash = 0 };
local ENEMY = { fill = 0.3, left = 2.0, delay = 4.0, learned = true, waiting = false, name = 'Goblin' };
local function texts(draw)
    hud.refresh(s);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    draw();
    hud.end_frame();
    MOCK.record_imgui = false;
    local at = {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddText') then at[c[6]] = c[4][1]; end
    end
    return at;
end
local function attack() hud.draw_attack(0.5, 1.5, 3.0, true, nil); end
local function resting() hud.draw_resting(RESTING); end
local function enemy() hud.draw_enemy(ENEMY); end

local a, r, e = texts(attack), texts(resting), texts(enemy);
check('every name shows at first', a['AUTO ATTACK'] and r['RESTING'] and e['ENEMY ATTACK']);
check('the small text sits after the name', r['+24 HP'] ~= nil and r['+24 HP'] > s.resting.x + 12, r['+24 HP']);

-- Turning off the resting name keeps the other two, and its seconds and small text.
s.resting.show_label = false;
a, r, e = texts(attack), texts(resting), texts(enemy);
check('the resting name goes', r['RESTING'] == nil);
check('its seconds and small text stay', r['4.0'] ~= nil and r['+24 HP'] ~= nil);
check('the small text moves to the left edge', r['+24 HP'] == s.resting.x + 12, r['+24 HP']);
check('the other names stay', a['AUTO ATTACK'] ~= nil and e['ENEMY ATTACK'] ~= nil);
s.resting.show_label = true;

s.attack.show_label = false;
a = texts(attack);
check('the auto attack name goes on its own', a['AUTO ATTACK'] == nil and a['1.5'] ~= nil
    and a['3.00s'] == s.attack.x + 12, a['3.00s']);
s.attack.label_text = 'AA';
check('your own name goes too', texts(attack)['AA'] == nil);
s.attack.label_text = '';
s.attack.show_label = true;

-- The enemy timer's name and the monster's name are two different switches.
s.enemy.show_label = false;
e = texts(enemy);
check('the enemy timer\'s name goes', e['ENEMY ATTACK'] == nil);
check('the monster\'s name stays', e['Goblin  4.00s'] ~= nil and e['2.0'] ~= nil);
s.enemy.show_label, s.enemy.show_name = true, false;
e = texts(enemy);
check('Enemy name only hides the monster', e['ENEMY ATTACK'] ~= nil and e['Goblin  4.00s'] == nil and e['4.00s'] ~= nil);
s.enemy.show_name = true;
s.enemy.attached, s.enemy.show_label = true, false;
check('the attached strip loses ENEMY too', texts(enemy)['ENEMY'] == nil);
s.enemy.attached, s.enemy.show_label = false, true;

-- Show labels off hides every name, whatever each timer's switch says.
s.style.show_labels = false;
a, r, e = texts(attack), texts(resting), texts(enemy);
check('Show labels off hides all three', a['AUTO ATTACK'] == nil and r['RESTING'] == nil and e['ENEMY ATTACK'] == nil);
s.style.show_labels = true;

-- A row with only the name in it goes away when the name does, the same as with Show labels off.
local function height(key)
    hud.refresh(s);
    local _, h = hud.element_size(key);
    return h;
end
local function row_goes(key, parts)
    for _, part in ipairs(parts) do s[key][part] = false; end
    local named = height(key);
    s[key].show_label = false;
    local unnamed = height(key);
    s[key].show_label = true;
    s.style.show_labels = false;
    local labels_off = height(key);
    s.style.show_labels = true;
    for _, part in ipairs(parts) do s[key][part] = true; end
    return unnamed < named and unnamed == labels_off, named .. ' ' .. unnamed .. ' ' .. labels_off;
end
s.attack.show_tp = false;
check('the auto attack row goes', row_goes('attack', { 'show_value', 'show_delay' }));
check('the resting row goes', row_goes('resting', { 'show_value', 'show_gains', 'show_until_full' }));
check('the enemy row goes', row_goes('enemy', { 'show_value', 'show_name', 'show_delay', 'show_effects', 'show_holds' }));
s.enemy.attached = true;
check('the strip\'s row goes too', row_goes('enemy', { 'show_value', 'show_name', 'show_delay', 'show_effects', 'show_holds' }));
s.enemy.attached = false;
s.attack.numbers_only, s.attack.show_value, s.attack.show_delay = true, false, false;
local with_name = height('attack');
s.attack.show_label = false;
check('numbers only keeps its row without the name', height('attack') == with_name, height('attack') .. ' vs ' .. with_name);
s.attack.numbers_only, s.attack.show_value, s.attack.show_delay, s.attack.show_label = false, true, true, true;

-- A name bigger than the numbers only makes its own row taller.
s.style.label_size = 0;
local auto_attack, auto_resting = height('attack'), height('resting');
s.style.label_size = 20;
check('a big name makes the row taller', height('attack') > auto_attack);
s.attack.show_label = false;
check('without the name the row goes back', height('attack') == auto_attack, height('attack') .. ' vs ' .. auto_attack);
check('the resting row keeps its big name', height('resting') > auto_resting);
s.attack.show_label = true;
s.style.label_size = 0;
s.attack.show_tp = true;

-- Reset look turns them back on, and Undo puts them back off.
s.attack.show_label, s.resting.show_label, s.enemy.show_label = false, false, false;
presets.reset(s);
check('Reset look turns all three back on', s.attack.show_label and s.resting.show_label and s.enemy.show_label);
presets.undo(s);
check('Undo puts them back off', not s.attack.show_label and not s.resting.show_label and not s.enemy.show_label);
s.attack.show_label, s.resting.show_label, s.enemy.show_label = true, true, true;
presets.apply(s, 'Minimal');
s.resting.show_label = false;
presets.apply(s, 'Phoenix');
check('a preset leaves them alone', s.resting.show_label == false);
s.resting.show_label = true;

-- The settings window. A box in front of each label box, then the box, then one (?).
local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do MOCK.frame(1 / 60); end
    MOCK.record_imgui = false;
    return MOCK.imgui_calls;
end
local function index_of(calls, name, label)
    for i, c in ipairs(calls) do
        if (c[1] == name and c[2] == label) then return i; end
    end
end
-- True when the switch is greyed out, by the BeginDisabled around it.
local function greyed(calls, i)
    local depth, off = {}, false;
    for j = 1, i do
        if (calls[j][1] == 'BeginDisabled') then table.insert(depth, calls[j][2] == true); end
        if (calls[j][1] == 'EndDisabled') then table.remove(depth); end
    end
    for _, v in ipairs(depth) do off = off or v; end
    return off;
end
MOCK.now = 100;
MOCK.fire('command', { command = '/cadence' });
local LINES = {
    { '##show_label_attack', 'Auto attack##label', 'attack' },
    { '##show_label_resting', 'Resting##label', 'resting' },
    { '##show_label_enemy', 'Enemy##label', 'enemy' },
};
s.resting.show_label = false;
local calls = frames(1);
for _, line in ipairs(LINES) do
    local switch, box = index_of(calls, 'Checkbox', line[1]), index_of(calls, 'InputTextWithHint', line[2]);
    local ok = switch ~= nil and box ~= nil and calls[switch + 2][1] == 'SameLine' and box > switch;
    for j = (switch or 1) + 1, (box or 1) - 1 do
        if (calls[j][1] == 'TextDisabled' or calls[j][1] == 'Checkbox') then ok = false; end
    end
    check(line[3] .. ' has its box right in front of its label box', ok, tostring(switch) .. ' ' .. tostring(box));
    check(line[3] .. '\'s box shows the setting', switch and calls[switch][3][1] == s[line[3]].show_label);
    check(line[3] .. '\'s box is live', switch and not greyed(calls, switch));
end
s.resting.show_label = true;
local look_tab, enemy_tab = index_of(calls, 'BeginTabItem', 'Appearance'), index_of(calls, 'BeginTabItem', 'Enemy');
local enemy_name, enemy_switch = index_of(calls, 'Checkbox', 'Enemy name'), index_of(calls, 'Checkbox', '##show_label_enemy');
check('the enemy one is on the Appearance tab, away from Enemy name', look_tab and enemy_tab and enemy_name and enemy_switch
    and enemy_name > enemy_tab and enemy_name < look_tab and enemy_switch > look_tab);

s.style.show_labels = false;
calls = frames(1);
for _, line in ipairs(LINES) do
    local switch = index_of(calls, 'Checkbox', line[1]);
    check(line[3] .. '\'s box greys out with Show labels off', switch and greyed(calls, switch));
    check('its label box doesn\'t', not greyed(calls, index_of(calls, 'InputTextWithHint', line[2])));
end
s.style.show_labels = true;

-- Show labels sits at the right end of the LABELS heading with its (?), above the line under it. In the
-- mock a letter is 7 wide, a box is 26 and the column is 792. So the box, 4, its words, 8 and the (?)
-- take 136 and it starts at 656.
calls = frames(1);
local title, switch_at, line_at, hint_at = nil, index_of(calls, 'Checkbox', 'Show labels'), nil, nil;
for i, c in ipairs(calls) do
    if (c[1] == 'TextColored' and c[3] == 'LABELS') then title = i; end
    if (title ~= nil and line_at == nil and i > title and c[1] == 'Separator') then line_at = i; end
    if (switch_at ~= nil and hint_at == nil and i > switch_at and c[1] == 'TextDisabled') then hint_at = i; end
end
check('Show labels is on the LABELS heading line', title and switch_at and line_at and title < switch_at
    and switch_at < line_at and calls[switch_at - 1][1] == 'SameLine' and hint_at and hint_at < line_at,
    tostring(title) .. ' ' .. tostring(switch_at) .. ' ' .. tostring(line_at));
check('at the right end of the column', switch_at and calls[switch_at - 1][2] == 792 - 136,
    switch_at and tostring(calls[switch_at - 1][2]));
check('and the heading lines up with its words', title and calls[title - 1][1] == 'AlignTextToFramePadding');

-- The label box gives up the room the box in front takes.
local cursor = 0;
rawset(imgui, 'GetCursorPosX', function () cursor = cursor + 34; return cursor; end);
calls = frames(1);
rawset(imgui, 'GetCursorPosX', nil);
local box = index_of(calls, 'InputTextWithHint', 'Resting##label');
check('the label box is narrower by the box in front', calls[box - 1][1] == 'SetNextItemWidth' and calls[box - 1][2] == 190 - 34,
    tostring(calls[box - 1][2]));

-- Ticking one changes just that timer and saves.
local saves = MOCK.saved;
rawset(imgui, 'Checkbox', function (label, value)
    if (label == '##show_label_resting') then value[1] = not value[1]; return true; end
    return false;
end);
frames(1);
rawset(imgui, 'Checkbox', nil);
check('unticking hides that name', s.resting.show_label == false and s.attack.show_label and s.enemy.show_label);
check('and saves', MOCK.saved > saves, MOCK.saved - saves);
s.resting.show_label = true;

-- The enemy line's tip says it's the timer's name, not the monster's.
rawset(imgui, 'IsItemHovered', function () return true; end);
calls = frames(1);
rawset(imgui, 'IsItemHovered', nil);
local tip = nil;
local from = index_of(calls, 'InputTextWithHint', 'Enemy##label');
for j = from, #calls do
    if (calls[j][1] == 'BeginTooltip') then tip = calls[j + 2] and calls[j + 2][2]; break; end
end
check('the enemy tip points away from the monster\'s name', tip and tip:find('not the monster', 1, true) ~= nil, tip);
check('and says how to hide it', tip and tip:find('box in front', 1, true) ~= nil, tip);

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
