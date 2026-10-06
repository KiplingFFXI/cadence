-- Timers stay on screen in a small game window. Each one is drawn pulled in just enough to fit, and
-- the spot you saved stays as it is. Only a Shift drag, Reset positions or /cadence reset move it.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

--[[
    ImGui's window placement, modelled like test_api_shared_spot.lua. A position set with Always, or
    with Appearing on a window that wasn't drawn last frame, is used as is. ImGui keeps any other
    window at least 19 px on screen. A drag moves the window before Begin, like ImGui's NewFrame does.
]]
ImGuiCond_Appearing = 777;
local EDGE = 19;
local imgui = require('imgui');
local win, stack, drag, frame_no = {}, {}, {}, 0;
local next_pos, next_size = nil, nil;
imgui.SetNextWindowPos = function (pos, cond) next_pos = { pos[1], pos[2], cond }; end
imgui.SetNextWindowSize = function (size)
    next_size = { size[1], size[2] };
    MOCK.next_size = next_size;
end
imgui.Begin = function (name)
    local w = win[name] or { x = 60, y = 60, width = 0, height = 0, last = -10 };
    win[name] = w;
    if (next_size ~= nil) then
        w.width, w.height = next_size[1], next_size[2];
    end
    if (drag[name] ~= nil) then
        w.x, w.y = drag[name][1], drag[name][2];
    end
    local placed = false;
    if (next_pos ~= nil) then
        local cond = next_pos[3];
        if (cond == ImGuiCond_Always or (cond == ImGuiCond_Appearing and w.last < frame_no - 1)) then
            w.x, w.y, placed = next_pos[1], next_pos[2], true;
        end
    end
    if (not placed) then
        w.x = math.max(EDGE - w.width, math.min(w.x, MOCK.screen[1] - EDGE));
        w.y = math.max(EDGE - w.height, math.min(w.y, MOCK.screen[2] - EDGE));
    end
    next_pos, next_size = nil, nil;
    w.last = frame_no;
    table.insert(stack, name);
    return true;
end
imgui.End = function () table.remove(stack); end
imgui.GetWindowPos = function () local w = win[stack[#stack]]; return w.x, w.y; end

MOCK.screen = { 1280, 720 };
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.watch_settings();
MOCK.fire('load');
local s = MOCK.settings.current;
local hud = require('ui.hud');
local enemy = require('core.enemy');
local shared_layout = require('core.shared_layout');

local ATTACK, RESTING, ENEMY = '##cadence_attack', '##cadence_resting', '##cadence_enemy';
local ME, MOB = 1001, 0x01000200;

local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do
        frame_no = frame_no + 1;
        MOCK.frame();
    end
    MOCK.record_imgui = false;
end
local function drawn(name) return win[name] ~= nil and win[name].last == frame_no; end
local function fits(name)
    local w = win[name];
    return w ~= nil and w.x >= 0 and w.y >= 0 and w.x + w.width <= MOCK.screen[1] and w.y + w.height <= MOCK.screen[2];
end
local function at(name)
    local w = win[name];
    return w and ('%s %d,%d %dx%d'):format(name:sub(11), w.x, w.y, w.width, w.height) or (name .. ' never drawn');
end
local function spots()
    return ('%d,%d %d,%d %d,%d'):format(s.resting.x, s.resting.y, s.attack.x, s.attack.y, s.enemy.x, s.enemy.y);
end
local function round_on(actor, target) MOCK.fire('packet_in', MOCK.action_packet(actor, 1, 0, target, { { message = 1 } })); end

-- Everything written for one layout for all characters.
local shared = {};
local save_shared = shared_layout.save;
shared_layout.save = function ()
    local layout = MOCK.in_use;
    table.insert(shared, ('%d,%d %d,%d %d,%d'):format(layout.resting.x, layout.resting.y, layout.attack.x,
        layout.attack.y, layout.enemy.x, layout.enemy.y));
    save_shared();
end

-- 1280x720 with the default spots. The enemy timer's spot is under the bottom edge, so it's drawn
-- pulled up. Its saved spot doesn't change.
s.enemy.enabled = true;
MOCK.fire('command', { command = '/cadence onelayout on' });
s = MOCK.in_use;
local saves, shared_saves = MOCK.saved, #shared;
MOCK.now = 100;
MOCK.fire('command', { command = '/cadence' });
frames(10);
local _, enemy_height = hud.element_size('enemy');
check('every timer is all on screen at 1280x720', fits(RESTING) and fits(ATTACK) and fits(ENEMY),
    at(RESTING) .. '  ' .. at(ATTACK) .. '  ' .. at(ENEMY));
check('the enemy timer is pulled up to the bottom edge', drawn(ENEMY) and win[ENEMY].y == 720 - enemy_height
    and win[ENEMY].x == 780, at(ENEMY));
check('the timers that fit are drawn at their spots', drawn(RESTING) and drawn(ATTACK) and win[RESTING].y == 620
    and win[ATTACK].y == 664, at(ATTACK));
check('the saved spots stay as they are', spots() == '780,620 780,664 780,724', spots());
check('drawing saves nothing', MOCK.saved == saves, MOCK.saved - saves);
check('one layout for all characters gets nothing either', #shared == shared_saves and shared[#shared] == '780,620 780,664 780,724',
    tostring(shared[#shared]));
MOCK.fire('command', { command = '/cadence onelayout off' });
s, saves = MOCK.in_use, MOCK.saved;

-- Hidden, then back. It comes back pulled in, and its spot still isn't touched.
MOCK.fire('command', { command = '/cadence' });
frames(3);
check('nothing shows with the window closed', not drawn(ENEMY) and not drawn(ATTACK));
MOCK.fire('command', { command = '/cadence' });
frames(5);
check('back again, still pulled in', fits(ENEMY) and win[ENEMY].y == 720 - enemy_height, at(ENEMY));
check('back again, still not saved', spots() == '780,620 780,664 780,724' and MOCK.saved == saves, spots());

-- 1024x768. The auto attack card at x 780 would run 18 px past the right edge and cut off its seconds.
MOCK.screen = { 1024, 768 };
-- The settings window pulls itself in on the first of these. Only the last frame's drawing is checked.
frames(3);
frames(1);
local attack_width = hud.element_size('attack');
check('the auto attack card is pulled in from the right edge', win[ATTACK].x == 1024 - attack_width and fits(ATTACK),
    at(ATTACK));
local past = {};
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1]:find('^dl:AddRect') and c[3][1] > 1024) then
        table.insert(past, c[1] .. ' to ' .. c[3][1]);
    end
    if (c[1] == 'dl:AddText' and c[4][1] + #c[6] * 7 > 1024 + 1) then
        table.insert(past, '"' .. c[6] .. '" to ' .. (c[4][1] + #c[6] * 7));
    end
end
check('nothing is drawn past the right edge, the seconds included', #past == 0, table.concat(past, ', '));
check('the spot stays at 780', s.attack.x == 780 and s.resting.x == 780 and s.enemy.x == 780, spots());
MOCK.fire('command', { command = '/cadence' });

-- The attached strip hangs under the auto attack card where it's drawn, not under its saved spot.
MOCK.screen = { 1280, 720 };
s.enemy.attached = true;
s.attack.x, s.attack.y = 1200, 700;
hud.refresh(s);
MOCK.entities[0x200] = { ServerId = MOB, Name = 'Young Quadav', Status = 1, SpawnFlags = 0x10 };
MOCK.player.target_index = 0x200;
MOCK.player.status = 1;
round_on(MOB, ME);
frames(3);
local _, attack_height = hud.element_size('attack');
local _, strip_height = hud.element_size('enemy');
check('the card and the strip under it are all on screen', fits(ATTACK) and fits(ENEMY)
    and win[ATTACK].x == 1280 - attack_width and win[ATTACK].y + attack_height + strip_height - 1 == 720,
    at(ATTACK) .. '  ' .. at(ENEMY));
check('the strip hangs under where the card is drawn', win[ENEMY].x == win[ATTACK].x
    and win[ENEMY].y == win[ATTACK].y + attack_height - 1, at(ATTACK) .. '  ' .. at(ENEMY));
local fighting_x, fighting_y = win[ENEMY].x, win[ENEMY].y;
local card_y = win[ATTACK].y;

-- Near the bottom edge the card leaves room for the strip even while there's none, so it doesn't jump
-- when the strip comes and goes.
enemy.reset();
frames(3);
check('with no strip yet the card stays where it was', drawn(ATTACK) and not drawn(ENEMY) and win[ATTACK].y == card_y,
    at(ATTACK) .. ' vs y ' .. card_y);
round_on(MOB, ME);
frames(3);
check('and the strip comes back under it', drawn(ENEMY) and win[ATTACK].y == card_y and win[ENEMY].y == fighting_y,
    at(ATTACK) .. '  ' .. at(ENEMY));
MOCK.player.status = 0;
round_on(MOB, ME);
frames(3);
check('between fights only the strip shows', drawn(ENEMY) and not drawn(ATTACK));
check('and it stays where it hung', win[ENEMY].x == fighting_x and win[ENEMY].y == fighting_y,
    at(ENEMY) .. ' vs ' .. fighting_x .. ',' .. fighting_y);
check('the auto attack spot stays as it is', s.attack.x == 1200 and s.attack.y == 700, spots());

-- With the auto attack timer turned off, the strip goes to its own spot. Even with Shift and the mouse
-- button held, that move isn't taken for a drag.
MOCK.player.status = 1;
round_on(MOB, ME);
frames(2);
MOCK.key_shift, MOCK.mouse_down = true, true;
s.attack.enabled = false;
frames(1);
check('let go of the card mid drag, the strip goes to its own spot', win[ENEMY].x == 780
    and win[ENEMY].y == 720 - strip_height, at(ENEMY));
check('and its spot stays as it is', s.enemy.x == 780 and s.enemy.y == 724, spots());
MOCK.key_shift, MOCK.mouse_down = false, false;
s.attack.enabled = true;
enemy.reset();
MOCK.player.target_index = 0;
MOCK.entities[0x200] = nil;
s.enemy.attached = false;
s.enemy.enabled = false;

-- At a shared spot, each card that shows there is pulled in, and the one spot they share stays put.
s.style.shared_spot = true;
hud.refresh(s);
MOCK.player.status = 33;
frames(3);
local resting_width, resting_height = hud.element_size('resting');
check('resting at the shared spot is all on screen', drawn(RESTING) and fits(RESTING)
    and win[RESTING].x == 1280 - resting_width and win[RESTING].y == 720 - resting_height, at(RESTING));
MOCK.player.status = 1;
frames(3);
check('then the auto attack card there too', drawn(ATTACK) and fits(ATTACK)
    and win[ATTACK].x == 1280 - attack_width and win[ATTACK].y == 720 - attack_height, at(ATTACK));
check('the shared spot stays as it is', s.attack.x == 1200 and s.attack.y == 700 and s.resting.y == 620, spots());
s.style.shared_spot = false;
hud.refresh(s);

-- A real Shift drag saves where the card was dragged to, even partly off screen. Once you let go it's
-- drawn all on screen again.
frames(1);
saves = MOCK.saved;
MOCK.key_shift, MOCK.mouse_down = true, true;
drag[ATTACK] = { -100, -20 };
frames(2);
check('a drag off the top left saves where it went', s.attack.x == -100 and s.attack.y == -20, spots());
MOCK.mouse_down = false;
drag[ATTACK] = nil;
frames(1);
check('let go, it is drawn in the corner', win[ATTACK].x == 0 and win[ATTACK].y == 0, at(ATTACK));
MOCK.mouse_down = true;
drag[ATTACK] = { 600, 400 };
frames(2);
check('a drag moves the saved spot', s.attack.x == 600 and s.attack.y == 400, spots());
drag[ATTACK] = { 1250, 700 };
frames(2);
check('a drag partly off screen saves where it went', s.attack.x == 1250 and s.attack.y == 700, spots());
saves = MOCK.saved;
frames(1);
check('nothing saves while the button is down', MOCK.saved == saves, MOCK.saved - saves);
MOCK.mouse_down = false;
drag[ATTACK] = nil;
frames(1);
check('it saves once on letting go', MOCK.saved == saves + 1, MOCK.saved - saves);
check('and it is drawn all on screen again, with Shift still held', fits(ATTACK)
    and win[ATTACK].x == 1280 - attack_width and win[ATTACK].y == 720 - attack_height, at(ATTACK));
check('its spot keeps the drag', s.attack.x == 1250 and s.attack.y == 700, spots());

-- Resizing a pulled in card from its edge is no drag. The spot it's drawn at isn't saved.
MOCK.mouse_down = true;
s.attack.width = 300;
frames(2);
check('a resize at the edge keeps the saved spot', s.attack.x == 1250 and s.attack.y == 700, spots());
MOCK.mouse_down = false;
frames(1);
local wider = hud.element_size('attack');
check('let go, it is pulled in at its new width', win[ATTACK].x == 1280 - wider and fits(ATTACK), at(ATTACK));
MOCK.key_shift = false;
s.attack.width = 240;

-- A timer that shows up while Shift and the mouse button are held comes in at its pulled in spot.
-- That isn't taken for a drag.
s.enemy.enabled = true;
s.enemy.x, s.enemy.y = 1200, 700;
MOCK.screen = { 1600, 1200 };
MOCK.fire('command', { command = '/cadence' });
frames(2);
check('on a big screen it is drawn at its spot', win[ENEMY].x == 1200 and win[ENEMY].y == 700, at(ENEMY));
MOCK.fire('command', { command = '/cadence' });
frames(2);
check('then it hides', not drawn(ENEMY));
MOCK.screen = { 1280, 720 };
MOCK.key_shift, MOCK.mouse_down = true, true;
MOCK.fire('command', { command = '/cadence' });
frames(1);
check('shown mid drag, it comes in all on screen', drawn(ENEMY) and fits(ENEMY), at(ENEMY));
check('and its spot stays as it is', s.enemy.x == 1200 and s.enemy.y == 700 and s.attack.x == 1250, spots());
MOCK.key_shift, MOCK.mouse_down = false, false;
MOCK.fire('command', { command = '/cadence' });

-- Reset positions stacks the timers from their default spot. On a screen too short for that, the
-- stack starts higher so all of it fits. Bigger screens get the default stack.
MOCK.screen = { 1600, 1200 };
MOCK.fire('command', { command = '/cadence reset' });
check('reset on a big screen gives the default stack', spots() == '780,620 780,664 780,724', spots());
MOCK.screen = { 1024, 768 };
MOCK.fire('command', { command = '/cadence reset' });
check('and at 1024x768 too, where it just fits', spots() == '780,620 780,664 780,724', spots());
-- ImGui's display size is -1 by -1 until its first frame.
MOCK.screen = { -1, -1 };
MOCK.fire('command', { command = '/cadence reset' });
check('before ImGui knows the screen, the default stack', spots() == '780,620 780,664 780,724', spots());
MOCK.screen = { 1280, 720 };
MOCK.fire('command', { command = '/cadence reset' });
check('at 1280x720 the stack starts higher', s.enemy.y + enemy_height + 6 == 720
    and s.attack.y == s.resting.y + resting_height + 6 and s.enemy.y == s.attack.y + attack_height + 6, spots());
MOCK.fire('command', { command = '/cadence' });
frames(2);
check('and each timer is drawn right at its spot', win[RESTING].y == s.resting.y and win[ATTACK].y == s.attack.y
    and win[ENEMY].y == s.enemy.y and fits(ENEMY), at(RESTING) .. '  ' .. at(ATTACK) .. '  ' .. at(ENEMY));

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
