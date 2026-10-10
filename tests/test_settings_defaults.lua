-- A settings file with a section or color missing. Ashita fills each one from the defaults' own table,
-- and editing it must never change the defaults kept for the next character.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

-- A file with no TP line settings and no resting timer section.
MOCK.settings_file = { attack = { enabled = true, x = 500, y = 600 }, style = { scale = 1.0 } };

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local kept = MOCK.settings.defaults;
local default_x = kept.resting.x;

check('saved values kept', s.attack.x == 500 and s.attack.y == 600);
check('a missing color is filled', type(s.attack.tp_color) == 'table' and s.attack.show_tp == true);
check('a missing color gets its own table', not rawequal(s.attack.tp_color, kept.attack.tp_color));
check('a missing section gets its own table', not rawequal(s.resting, kept.resting));
check('colors inside a missing section get their own tables', not rawequal(s.resting.fill_start, kept.resting.fill_start));
check('new goals and alignment guides start off in older files', not s.attack.show_tp_time and not s.resting.show_goal and not s.style.layout_guides);
check('older settings keep the original timer heights', s.attack.height_scale == 1 and s.resting.height_scale == 1
    and s.enemy.height_scale == 1);
check('the recovery goal starts at full MP', s.resting.goal_stat == 'mp' and s.resting.goal_mode == 'percent' and s.resting.goal_value == 100);

-- Edits the way the color picker and Shift+drag make them, in place.
s.attack.tp_color[1] = 0.123;
s.resting.x = 1;
check('editing never changes the defaults', kept.attack.tp_color[1] ~= 0.123 and kept.resting.x == default_x,
    kept.attack.tp_color[1] .. ' ' .. kept.resting.x);

-- Another character whose own file has parts missing, then one with no file at all.
MOCK.settings.switch_character({ attack = { enabled = false } });
local second = MOCK.settings.current;
check('the next character gets its own tables', not rawequal(second.resting, kept.resting));
second.resting.x = 7;
MOCK.settings.switch_character(nil);
check('a character with no file starts from the real defaults', MOCK.settings.current.resting.x == default_x,
    MOCK.settings.current.resting.x);
check('and from the default TP color', MOCK.settings.current.attack.tp_color[1] ~= 0.123);

MOCK.now = 100;
MOCK.player.status = 1;
for _ = 1, 3 do MOCK.frame(1 / 60); end
local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
