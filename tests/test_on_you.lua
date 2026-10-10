-- The On you mark. The enemy timer's name and stripe turn their own color while the monster's last
-- attack was on you.
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
local enemy = require('core.enemy');
local theme = require('ui.theme');
local imgui = require('imgui');

local ME, TANK, MOB = 1001, 2001, 0x01000200;
local function packet(p) MOCK.fire('packet_in', p); end
local function round_on(target) packet(MOCK.action_packet(MOB, 1, 0, target, { { message = 1 } })); end

-- Who it attacked last.
s.enemy.enabled = true;
MOCK.now = 100;
check('nothing before its first attack', enemy.last_target(MOB) == nil);
round_on(TANK);
check('on the tank', enemy.last_target(MOB) == TANK);
MOCK.now = MOCK.now + 4.0;
round_on(ME);
check('then on you', enemy.last_target(MOB) == ME);

-- A paralyzed round still shows who it's attacking.
MOCK.now = MOCK.now + 4.0;
round_on(TANK);
packet(MOCK.action_packet(MOB, 4, 0, ME, { { message = 84 } }));
check('a paralyzed round on you counts', enemy.last_target(MOB) == ME, enemy.last_target(MOB));

-- Following it as your target. The label and the stripe show the mark while its last attack was on you.
MOCK.entities[0x200] = { ServerId = MOB, Name = 'Goblin Thug', Status = 1, SpawnFlags = 0x10 };
MOCK.player.target_index = 0x200;
local mark = theme.u32(s.enemy.on_you_color);
local function drawn()
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    local label_color, stripe = nil, false;
    local in_enemy = false;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'Begin') then in_enemy = c[2] == '##cadence_enemy'; end
        if (in_enemy and c[1] == 'dl:AddText' and c[6] == 'ENEMY ATTACK') then label_color = c[5]; end
        if (in_enemy and c[1] == 'dl:AddRectFilled' and c[4] == mark) then stripe = true; end
    end
    return label_color, stripe;
end
local label_color, stripe = drawn();
check('the name takes the mark', label_color == mark, label_color);
check('and so does the stripe', stripe);

MOCK.now = MOCK.now + 4.0;
round_on(TANK);
label_color, stripe = drawn();
check('back to normal once it attacks someone else', label_color == theme.u32(s.style.label_color) and not stripe,
    label_color);

MOCK.now = MOCK.now + 4.0;
round_on(ME);
s.enemy.show_on_you = false;
label_color, stripe = drawn();
check('turned off, no mark', label_color ~= mark and not stripe);
s.enemy.show_on_you = true;
s.enemy.which = 'attacker';
label_color, stripe = drawn();
check('following whoever hits you, no mark', label_color ~= mark and not stripe);
s.enemy.which = 'target_first';
s.style.accent = false;
label_color, stripe = drawn();
check('with no stripe, the name still shows it', label_color == mark and not stripe);
s.style.accent = true;

-- The setting in the settings window is greyed out following whoever hits you.
local function disabled_before(label)
    for i, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'Checkbox' and c[2] == label) then
            local before = MOCK.imgui_calls[i - 1];
            return before and before[1] == 'BeginDisabled' and before[2] == true;
        end
    end
    return nil;
end
MOCK.fire('command', { command = '/cadence' });
drawn();
check('On you is live following your target', disabled_before('On you') == false);
s.enemy.which = 'attacker';
drawn();
check('and greyed out following whoever hits you', disabled_before('On you') == true);
s.enemy.which = 'target_first';

-- With the timer's name and the accent stripe both hidden, there's nothing left to color.
s.enemy.show_label, s.style.accent = false, false;
drawn();
check('greyed out with no name and no stripe', disabled_before('On you') == true);
s.style.accent = true;
drawn();
check('live again with the stripe back', disabled_before('On you') == false);
s.enemy.show_label, s.style.show_labels, s.style.accent = true, false, false;
drawn();
check('Show labels off counts as no name', disabled_before('On you') == true);
s.style.show_labels, s.style.accent = true, true;
MOCK.fire('command', { command = '/cadence' });

-- Every look has its own mark color, and Reset look puts the default back.
local presets = require('ui.presets');
local seen, distinct = {}, 0;
for _, name in ipairs(presets.NAMES) do
    presets.apply(s, name);
    local packed = theme.u32(s.enemy.on_you_color);
    if (not seen[packed]) then seen[packed], distinct = true, distinct + 1; end
end
check('all eight looks have their own mark color', #presets.NAMES == 8 and distinct == #presets.NAMES, distinct);
presets.reset(s);
check('reset look puts the default back', theme.u32(s.enemy.on_you_color) == theme.u32(theme.palette.ember));

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
