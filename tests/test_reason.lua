-- When the bar is full but you don't attack, it says why instead of "ready", from the server's
-- "out of range" and "unable to see" messages.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };   -- 4.0 s
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;

local ME, MOB = 1001, 0x01000200;
local function run_to(t) while (MOCK.now + 1 / 60 < t) do MOCK.frame(1 / 60); end MOCK.now = t; end
local function round() MOCK.fire('packet_in', MOCK.action_packet(ME, 1, 0, MOB, { { message = 1 } })); end
local function says(message) MOCK.fire('packet_in', MOCK.message_packet(ME, MOB, 0, 0, message, 0x200)); end
local function value()
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    local all = '|';
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1] == 'dl:AddText') then all = all .. c[6] .. '|'; end end
    return all;
end

MOCK.now = 100;
MOCK.player.status = 1;
MOCK.frame(1 / 60);
run_to(101.6);
round();
run_to(105.8);
check('ready once the bar fills', value():find('|ready|', 1, true) ~= nil);

says(5);
check('not facing', value():find('|not facing|', 1, true) ~= nil, value());
says(4);
check('too far', value():find('|too far|', 1, true) ~= nil, value());

round();
local text = value();
check('an attack clears it', text:find('too far', 1, true) == nil and text:find('|4.0|', 1, true) ~= nil, text);

-- A message while the bar is still filling only shows once it's full.
run_to(107.0);
says(4);
check('not shown while the bar fills', value():find('too far', 1, true) == nil);
run_to(110.0);
check('shown once it\'s full', value():find('|too far|', 1, true) ~= nil);

-- A job ability moves the timer on, so the old reason goes.
MOCK.fire('packet_in', MOCK.action_packet(ME, 6, 35, ME, { { message = 100, animation = 3 } }));
run_to(112.2);
check('an ability clears it', value():find('|ready|', 1, true) ~= nil);

-- Turned off, a full bar just says "ready".
says(5);
s.attack.show_reason = false;
check('turned off, it says ready', value():find('|ready|', 1, true) ~= nil);
s.attack.show_reason = true;
check('turned back on, it says why', value():find('|not facing|', 1, true) ~= nil);

-- An attack clears it for good, so the next full bar says ready until the server says otherwise.
round();
run_to(MOCK.now + 4.1);
check('the next full bar after an attack says ready', value():find('|ready|', 1, true) ~= nil);

-- Disengaging forgets it.
MOCK.player.status = 0;
MOCK.frame(1 / 60);
MOCK.player.status = 1;
MOCK.frame(1 / 60);
run_to(MOCK.now + 2.9);
check('a new fight starts without it', value():find('|ready|', 1, true) ~= nil);

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
