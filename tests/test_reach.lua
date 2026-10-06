-- "too far" and "not facing" worked out from where you and the monster you fight stand, before the
-- attack is due, the way the server checks before each attack. First the check on its own, against a
-- port of the server's own math, then the whole addon.
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
local reach = require('core.reach');
local theme = require('ui.theme');

--[[
    The check on its own. You stand at the middle with a 0.4 hitbox. The target has a 1.0 hitbox, so
    your reach is 3.4. Headings are in radians, 0 east and turning clockwise, so a quarter turn faces
    -z.
]]
local me = { x = 0, y = 0, z = 0, heading = 0, hitbox = 0.4 };
local mob = { x = 0, y = 0, z = 0, heading = 0, hitbox = 1.0 };
-- Puts the target `d` yalms away, `degrees` clockwise from east, `up` yalms higher.
local function put(d, degrees, up)
    local a = math.rad(degrees or 0);
    mob.x, mob.z, mob.y = d * math.cos(a), -d * math.sin(a), up or 0;
end
local function at(d, degrees, up, id)
    put(d, degrees, up);
    return reach.check(id or 1, me, mob);
end

reach.forget();
check('in reach and in front, nothing', at(3.3) == nil);
check('past your reach is too far', at(3.5) == 4);
check('a little way back in stays too far', at(3.3) == 4);
check('back inside by the margin, nothing', at(3.15) == nil);
check('inside the margin from in reach, still nothing', at(3.35) == nil);
check('height counts toward the distance', at(3.0, 0, 2.0) == 4);
reach.forget();
check('straight through, not only across the ground', at(3.0, 0, 1.2) == nil and at(3.0, 0, 1.8) == 4);
reach.forget();
check('your hitbox and the target\'s both count', (function ()
    me.hitbox, mob.hitbox = 0.8, 2.5;
    local near = at(5.2) == nil;
    local far = at(5.4) == 4;
    me.hitbox, mob.hitbox = 0.4, 1.0;
    reach.forget();
    return near and far;
end)());

check('44 degrees off is facing', at(3, 44) == nil and at(3, -44) == nil);
check('46 degrees off is not facing', at(3, 46) == 5);
check('a little way back is still not facing', at(3, 42) == 5);
check('back past the margin, facing', at(3, 39) == nil);
check('the other side too', at(3, -46) == 5 and at(3, -42) == 5 and at(3, -39) == nil);
check('behind you is not facing', at(3, 180) == 5);
reach.forget();
check('not facing comes before too far, like the server', at(8, 120) == 5);
reach.forget();

me.heading = math.pi / 2;
check('a quarter turn clockwise faces -z', at(3, 90) == nil and mob.z < 0);
check('and +z is behind it', at(3, -90) == 5);
reach.forget();
me.heading = -math.pi / 2;
check('a heading below zero faces +z', at(3, -90) == nil and mob.z > 0);
me.heading = 3 * math.pi / 2;
check('the same heading a whole turn up faces the same way', at(3, -90) == nil);
me.heading = 3.1;
check('facing west, a target just past west is in front', at(3, 182) == nil and at(3, 178) == nil);
me.heading = 0;
reach.forget();

check('standing on top of it counts as facing', (function ()
    me.heading = math.pi;
    local on_top = at(0.05, 0) == nil;
    local beside = at(0.2, 0) == 5;
    me.heading = 0;
    reach.forget();
    return on_top and beside;
end)());

-- A new target starts the checks over.
at(3.5, 0, 0, 1);
check('the old target was too far', at(3.3, 0, 0, 1) == 4);
check('a new one at the same spot is in reach', at(3.3, 0, 0, 2) == nil);
at(3.5, 0, 0, 2);
reach.forget();
check('forgetting starts over too', at(3.3, 0, 0, 2) == nil);

--[[
    Against the server's own facing check, LSB utils.cpp worldAngle, angleDifference and infront with a
    64 step cone, and CCharEntity::CanAttack's range. The server works in whole rotation steps, so
    only spots more than two steps from the edge have to agree. The client's heading is taken as the
    rotation over 128 times pi.
]]
local function truncate(v) return (v >= 0) and math.floor(v) or math.ceil(v); end
local function server_facing(rotation, dx, dz)
    if (dx * dx + dz * dz <= 0.1 * 0.1) then
        return true;
    end
    local world = truncate(math.atan2(dz, dx) * -(128 / math.pi)) % 256;
    local diff = world - rotation;
    if (diff > 128) then diff = diff - 256; elseif (diff < -128) then diff = diff + 256; end
    return math.abs(diff) < 32;
end
local disagree, compared = {}, 0;
for rotation = 0, 255, 7 do
    for step = 0, 359, 3 do
        local a = math.rad(step);
        local dx, dz = 3 * math.cos(a), 3 * math.sin(a);
        local exact = (-math.atan2(dz, dx) * 128 / math.pi - rotation) % 256;
        exact = math.min(exact, 256 - exact);
        if (math.abs(exact - 32) > 2) then
            compared = compared + 1;
            me.heading = rotation * math.pi / 128;
            mob.x, mob.z, mob.y = dx, dz, 0;
            reach.forget();
            local facing = reach.check(1, me, mob) ~= 5;
            if (facing ~= server_facing(rotation, dx, dz)) then
                table.insert(disagree, rotation .. '@' .. step);
            end
        end
    end
end
me.heading = 0;
check('facing agrees with the server all the way round', #disagree == 0 and compared > 2000,
    compared .. ' compared, off at ' .. table.concat(disagree, ' '));

-- Each spot is your hitbox, the target's, how far across the ground and how far up.
local range_off = {};
for _, spot in ipairs({ { 0.3, 0.4, 3.0, 0.5 }, { 0.8, 1.0, 1.5, 3.0 }, { 0.3, 4.5, 6.0, 1.2 }, { 0.4, 0.4, 2.0, 2.5 },
    { 0.4, 0.4, 0.5, 0.0 } }) do
    local mine, theirs, dx, dy = spot[1], spot[2], spot[3], spot[4];
    local d = math.sqrt(dx * dx + dy * dy);
    local server_far = d > mine + 2.0 + theirs;
    me.hitbox, mob.hitbox = mine, theirs;
    mob.x, mob.y, mob.z = dx, dy, 0;
    reach.forget();
    if ((reach.check(1, me, mob) == 4) ~= server_far) then table.insert(range_off, table.concat(spot, ',')); end
end
me.hitbox, mob.hitbox = 0.4, 1.0;
check('range agrees with the server', #range_off == 0, table.concat(range_off, ' | '));
reach.forget();

--[[
    The whole addon. You're at index 0x400 and the monster at 0x200, named the way Ashita names
    things, so Z is height and X and Y run across the ground.
]]
local ME, MOB = 1001, 0x01000200;
local MOB_INDEX, OTHER_INDEX, FRIEND_INDEX = 0x200, 0x201, 0x401;
MOCK.entities[0x400] = { ServerId = ME, Name = 'Tester', Status = 0, X = 0, Y = 0, Z = 0, Yaw = 0, Hitbox = 0.4 };
MOCK.entities[MOB_INDEX] = { ServerId = MOB, Name = 'Goblin Thug', Status = 1, SpawnFlags = 0x10, X = 3.0, Y = 0, Z = 0,
    Yaw = math.pi, Hitbox = 1.0 };
MOCK.entities[OTHER_INDEX] = { ServerId = MOB + 1, Name = 'Goblin Weaver', Status = 1, SpawnFlags = 0x10, X = 3.3, Y = 0,
    Z = 0, Hitbox = 1.0 };
MOCK.entities[FRIEND_INDEX] = { ServerId = 1002, Name = 'Friend', Status = 1, SpawnFlags = 0x01, X = 20, Y = 0, Z = 0,
    Hitbox = 0.4 };
local you, goblin = MOCK.entities[0x400], MOCK.entities[MOB_INDEX];

local function run_to(t) while (MOCK.now + 1 / 60 < t) do MOCK.frame(1 / 60); end MOCK.now = t; end
local function round() MOCK.fire('packet_in', MOCK.action_packet(ME, 1, 0, MOB, { { message = 1 } })); end
local function says(message) MOCK.fire('packet_in', MOCK.message_packet(ME, MOB, 0, 0, message, MOB_INDEX)); end
local function frame()
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(1 / 60);
    MOCK.record_imgui = false;
    return MOCK.imgui_calls;
end
local function texts(calls)
    local all = '|';
    for _, c in ipairs(calls or frame()) do if (c[1] == 'dl:AddText') then all = all .. c[6] .. '|'; end end
    return all;
end
local function shows(word, calls) return texts(calls):find('|' .. word .. '|', 1, true) ~= nil; end
local function seconds_shown(calls) return texts(calls):match('|%d+%.%d|') ~= nil; end
local function word_colors(calls, word)
    local found = {};
    for _, c in ipairs(calls) do if (c[1] == 'dl:AddText' and c[6] == word) then found[c[5]] = true; end end
    return found;
end
-- The draw calls for the auto attack bar's fill, the ones after its track.
local function fill_calls(calls)
    local track, list = theme.u32(s.style.track_color), nil;
    for _, c in ipairs(calls) do
        if (list ~= nil and (c[1] == 'dl:AddRectFilled' or c[1] == 'dl:AddRectFilledMultiColor')) then
            table.insert(list, c);
        elseif (c[1] == 'dl:AddRectFilled' and c[4] == track) then
            list = {};
        end
    end
    return list or {};
end
local function alpha(c) return math.floor((c % 2 ^ 32) / 2 ^ 24); end
local function rgb(c) return (c % 2 ^ 32) % 2 ^ 24; end
local function dimmed_from(c, color)
    local full = theme.u32(color);
    return c ~= nil and rgb(c) == rgb(full) and alpha(c) > 0 and alpha(c) < alpha(full);
end
local function gradient_dimmed(calls)
    local bar = fill_calls(calls);
    return bar[1] ~= nil and bar[1][1] == 'dl:AddRectFilledMultiColor' and dimmed_from(bar[1][4], s.attack.fill_start);
end
local function gradient_bright(calls)
    local bar = fill_calls(calls);
    return bar[1] ~= nil and bar[1][1] == 'dl:AddRectFilledMultiColor' and bar[1][4] == theme.u32(s.attack.fill_start);
end

-- Not engaged, nothing is read.
MOCK.now = 100;
MOCK.player.status = 0;
MOCK.player.target_index = MOB_INDEX;
MOCK.frame(1 / 60);
local reads = MOCK.position_reads;
run_to(101);
check('nothing is read before you engage', MOCK.position_reads == reads, MOCK.position_reads - reads);

-- Engaged, with the last round at 110 and the next due at 114.
local function engaged_at(t0)
    MOCK.player.buffs = {};
    MOCK.player.status = 0;
    MOCK.now = t0;
    MOCK.frame(1 / 60);
    MOCK.player.status = 1;
    MOCK.frame(1 / 60);
    run_to(t0 + 1.6);
    round();
end
goblin.X, goblin.Y, goblin.Z, you.Yaw = 3.0, 0, 0, 0;
engaged_at(108.4);
run_to(111.0);
local calls = frame();
check('in reach and facing, the seconds show', shows('3.0', calls), texts(calls));
check('and the bar is bright', gradient_bright(calls));

goblin.X = 3.6;
calls = frame();
check('stepping out of reach says too far before the attack is due', shows('too far', calls) and not seconds_shown(calls),
    texts(calls));
check('in the detail color', word_colors(calls, 'too far')[theme.u32(s.style.detail_color)]);
check('and dims the bar', gradient_dimmed(calls), fill_calls(calls)[1] and fill_calls(calls)[1][4]);
goblin.X = 3.3;
check('a little way back in, it stays', shows('too far'));
goblin.X = 3.1;
calls = frame();
check('back in reach, the seconds come back', seconds_shown(calls) and not shows('too far', calls), texts(calls));
check('and the bar brightens', gradient_bright(calls));

-- Height is Z.
goblin.Z = 2.0;
check('a target up a slope is further away', shows('too far'));
goblin.Z = 0;
MOCK.frame(1 / 60);
goblin.Y = 2.0;
check('Y runs across the ground', shows('too far'));
goblin.Y = 0;
MOCK.frame(1 / 60);

-- Turning away. A quarter turn clockwise from east faces -Y.
you.Yaw = math.pi / 2;
check('turned away says not facing', shows('not facing'));
goblin.X, goblin.Y = 0, -3.0;
check('facing it again, the seconds', seconds_shown());
goblin.Y = 3.0;
check('with it behind you, not facing', shows('not facing'));
goblin.Y = 6.0;
check('behind and too far says not facing first', shows('not facing') and not shows('too far'));
you.Yaw, goblin.X, goblin.Y = 0, 3.0, 0;
check('turned back, the seconds', seconds_shown());

-- Just before the attack it isn't in the almost ready color.
run_to(113.7);
goblin.X = 3.6;
calls = frame();
check('almost ready and too far, not in the almost ready color', shows('too far', calls)
    and not word_colors(calls, 'too far')[theme.u32(s.attack.almost_color)], texts(calls));

-- Once it's due, the word keeps the ready color, as the server's message does.
run_to(114.2);
calls = frame();
check('due and too far says too far', shows('too far', calls), texts(calls));
check('in the ready color', word_colors(calls, 'too far')[theme.u32(s.attack.ready_color)]);
local bar = fill_calls(calls);
check('with its ready fill dimmed', bar[1] and dimmed_from(bar[1][4], s.attack.ready_color), bar[1] and bar[1][4]);

-- The server's message wins once it arrives.
says(5);
check('the server saying not facing wins', shows('not facing') and not shows('too far'));
goblin.X = 3.0;
calls = frame();
check('it stays until your next attack', shows('not facing', calls), texts(calls));
bar = fill_calls(calls);
check('and dims the bar too', bar[1] and dimmed_from(bar[1][4], s.attack.ready_color), bar[1] and bar[1][4]);
round();
check('your attack clears it', seconds_shown());

-- A message from the server while the bar still fills only shows once the attack is due.
run_to(115.0);
says(4);
check('an early server message isn\'t shown while you can attack', seconds_shown());

-- Asleep comes first.
goblin.X = 3.6;
MOCK.player.buffs = { 2 };
run_to(115.4);
check('asleep comes before too far', shows('asleep') and not shows('too far'));
MOCK.player.buffs = {};
run_to(115.8);
check('awake again, too far', shows('too far'));

-- Turned off, nothing is read, and the bar shows its seconds without dimming.
s.attack.show_reason = false;
reads = MOCK.position_reads;
calls = frame();
check('turned off, the seconds', seconds_shown(calls) and not shows('too far', calls), texts(calls));
check('and no dimming', gradient_bright(calls));
check('and nothing is read', MOCK.position_reads == reads, MOCK.position_reads - reads);
s.attack.show_reason = true;
check('turned back on, too far', shows('too far'));

-- With a party member targeted, the monster you fight is still checked.
MOCK.player.target_index = FRIEND_INDEX;
check('with a party member targeted, still too far', shows('too far'));
MOCK.player.target_index = MOB_INDEX;
check('back on the monster, too far', shows('too far'));

-- A dead target isn't checked.
goblin.Status = 3;
check('a dead target isn\'t too far', seconds_shown());
goblin.Status = 1;

-- Targeting another monster doesn't change which one is checked. Your rounds and the server's 0x058 do.
MOCK.frame(1 / 60);
goblin.X = 3.3;
check('the sticky too far', shows('too far'));
local weaver = MOCK.entities[OTHER_INDEX];
weaver.X = 12;
MOCK.player.target_index = OTHER_INDEX;
check('another monster targeted, the one you fight is still checked', shows('too far'));
goblin.X = 3.0;
check('back in reach of the one you fight, the seconds', seconds_shown());

-- A round that lands clears the word, even a little way in where it would stick.
goblin.X = 3.6;
MOCK.frame(1 / 60);
goblin.X = 3.3;
check('too far a little way in', shows('too far'));
round();
check('a round that lands clears it', seconds_shown());

-- A round on another monster means your attacks went to it, so that one is checked.
MOCK.fire('packet_in', MOCK.action_packet(ME, 1, 0, MOB + 1, { { message = 1 } }));
check('your attacks moved to the far one, too far', shows('too far'));
MOCK.player.target_index = MOB_INDEX;
round();
check('and back to the near one, the seconds', seconds_shown());

-- /attack on another monster mid-fight. The server's 0x058 moves the check there before any round on it.
local function moved_to(id, who) MOCK.fire('packet_in', MOCK.assist_packet(who or ME, id)); end
moved_to(MOB + 1);
check('0x058 moves the check to the far one', shows('too far'));
moved_to(MOB, 1002);
check('another player\'s 0x058 changes nothing', shows('too far'));
moved_to(1002);
check('a 0x058 naming a player changes nothing', shows('too far'));
moved_to(0);
check('a 0x058 naming no one changes nothing', shows('too far'));
moved_to(MOB);
check('0x058 back to the near one, the seconds', seconds_shown());

-- Turned round to face the monster you switched to, it isn't "not facing".
weaver.X = -3.0;
moved_to(MOB + 1);
you.Yaw = math.pi;
calls = frame();
check('facing the one you switched to, the seconds', seconds_shown(calls) and not shows('not facing', calls),
    texts(calls));
you.Yaw = 0;
moved_to(MOB);
weaver.X = 3.3;

-- A new fight starts over, even after a 0x058 between fights, like from /assist.
goblin.X = 3.6;
MOCK.frame(1 / 60);
goblin.X = 3.3;
check('too far again', shows('too far'));
MOCK.player.status = 0;
MOCK.frame(1 / 60);
weaver.X = 12;
moved_to(MOB + 1);
MOCK.player.status = 1;
check('a 0x058 between fights doesn\'t outlast the engage', seconds_shown());
engaged_at(120);
run_to(122.0);
check('a new fight at the same distance is in reach', seconds_shown());

-- Loaded mid-fight, too far shows instead of --.
MOCK.fire('packet_in', MOCK.zone_packet(ME));
MOCK.player.status = 1;
goblin.X = 3.6;
calls = frame();
check('joined late and too far says too far', shows('too far', calls) and not shows('--', calls), texts(calls));
check('in the detail color', word_colors(calls, 'too far')[theme.u32(s.style.detail_color)]);
goblin.X = 3.0;
check('in reach, it says --', shows('--'));

-- The server only says it once an attack is due, so its word is in the ready color, like on a full bar.
goblin.X = 3.6;
says(4);
calls = frame();
check('the server saying too far puts it in the ready color', word_colors(calls, 'too far')[theme.u32(s.attack.ready_color)],
    texts(calls));

--[[
    The setting's (?).
]]
MOCK.fire('command', { command = '/cadence' });
rawset(require('imgui'), 'IsItemHovered', function () return true; end);
calls = frame();
rawset(require('imgui'), 'IsItemHovered', nil);
local tip, after = nil, false;
for _, c in ipairs(calls) do
    if (c[1] == 'Checkbox') then after = c[2] == 'Range / facing'; end
    if (after and tip == nil and c[1] == 'TextUnformatted') then tip = tostring(c[2]); end
end
check('its tip names the words and the dimming', tip ~= nil and tip:find('"too far"', 1, true) ~= nil
    and tip:find('"not facing"', 1, true) ~= nil and tip:find('dims', 1, true) ~= nil, tip);
MOCK.fire('command', { command = '/cadence' });

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
