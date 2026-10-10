-- The enemy attack timer's clocks on their own, then the whole addon with monsters attacking.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end
local function near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 1e-6); end

local enemy   = require('core.enemy');
local packets = require('core.packets');

local ME = 1001;
local MOB, MOB2 = 0x01000200, 0x01000201;

-- Clocks ------------------------------------------------------------------------------------------
do
    enemy.reset();
    enemy.on_engage(100, MOB);
    local _, left = enemy.progress(100.4, MOB);
    check('first round 2.8 s after engage', near(left, 2.4), left);

    -- A default 240 monster: rounds every 4.0 s.
    enemy.on_round(101.6, MOB, ME);
    local fill, left2, delay, learned = enemy.progress(101.6, MOB);
    check('starts from the 4.0 s guess', near(delay, 4.0) and near(left2, 4.0) and not learned, delay);
    for _, t in ipairs({ 105.6, 109.6, 113.6 }) do enemy.on_round(t, MOB, ME); end
    _, _, delay, learned = enemy.progress(113.6, MOB);
    check('learned after three clean gaps', near(delay, 4.0) and learned, tostring(delay) .. ' ' .. tostring(learned));
    fill, left2 = enemy.progress(115.6, MOB);
    check('bar half full halfway through', near(fill, 0.5) and near(left2, 2.0), fill);

    -- An 8 s monster learned from the 4 s first guess.
    enemy.on_round(200, MOB2, ME);
    enemy.on_round(208, MOB2, ME);
    _, left2, delay = enemy.progress(208, MOB2);
    check('an 8 s monster is learned from one gap', near(delay, 8.0) and near(left2, 8.0), delay);

    -- A 280 monster alternates 4.8 and 4.4 s gaps. The average is its real delay.
    enemy.reset();
    local t = 0;
    enemy.on_round(t, MOB, ME);
    for _, gap in ipairs({ 4.8, 4.8, 4.4, 4.8, 4.8, 4.4 }) do t = t + gap; enemy.on_round(t, MOB, ME); end
    _, _, delay = enemy.progress(t, MOB);
    check('uneven gaps average to the real delay', near(delay, 4.6667, 0.001), delay);

    -- A long pause cadence couldn't see isn't learned.
    enemy.reset();
    enemy.on_round(0, MOB, ME);
    enemy.on_round(4, MOB, ME);
    enemy.on_round(8, MOB, ME);
    enemy.on_round(30, MOB, ME);
    _, _, delay = enemy.progress(30, MOB);
    check('a long pause is not learned', near(delay, 4.0), delay);

    enemy.reset();
    for _ = 1, 4 do enemy.on_round(4, MOB, ME); end
    local batched = enemy.info(4, MOB);
    check('batched enemy rounds cannot teach zero delay', batched.delay == 4 and batched.samples == 0 and not batched.learned);
    for _, at in ipairs({ 8, 12, 16 }) do enemy.on_round(at, MOB, ME); end
    check('clean enemy gaps still learn after a packet batch', enemy.info(16, MOB).learned and enemy.info(16, MOB).delay == 4);

    -- A TP move readied 1 s in and finished 2 s later. The timer runs again 2 s after that.
    enemy.reset();
    enemy.on_round(0, MOB, ME);
    enemy.on_hold_begin(1.0, MOB);
    local _, left_held = enemy.progress(2.5, MOB);
    check('the bar stops while a TP move readies', near(left_held, 3.0), left_held);
    enemy.on_hold_end(3.0, MOB, false);
    _, left2 = enemy.progress(3.0, MOB);
    check('TP move adds its 2 s after finishing', near(left2, 3.0 + 2.0), left2);

    -- A TP move with no ready time finishes without starting.
    enemy.reset();
    enemy.on_round(0, MOB, ME);
    enemy.on_hold_end(1.0, MOB, false);
    _, left2 = enemy.progress(1.0, MOB);
    check('an instant TP move holds too', near(left2, 3.0 + 2.0), left2);

    -- A TP move cut off by a stun or sleep adds no tail. It goes to waiting after a whole delay.
    enemy.reset();
    enemy.on_round(0, MOB, ME);
    enemy.on_hold_begin(1.0, MOB);
    enemy.on_hold_end(1.5, MOB, true);
    _, left2 = enemy.progress(1.5, MOB);
    check('an interrupted TP move adds no tail', near(left2, 3.0), left2);
    local waiting;
    _, left2, _, _, waiting = enemy.progress(5.0, MOB);
    check('ready once it runs out', near(left2, 0) and not waiting);
    _, _, _, _, waiting = enemy.progress(8.6, MOB);
    check('waiting a whole delay later', waiting == true);
    enemy.on_round(9.0, MOB, ME);
    _, left2, _, _, waiting = enemy.progress(9.0, MOB);
    check('the next round puts it back in step', near(left2, 4.0) and not waiting, left2);

    -- A paralyzed round uses up the timer, but its gap isn't learned.
    enemy.reset();
    enemy.on_round(0, MOB, ME);
    enemy.on_paralyzed(4.0, MOB);
    enemy.on_round(8.0, MOB, ME);
    _, left2 = enemy.progress(8.0, MOB);
    check('a paralyzed round counts as a round', near(left2, 4.0), left2);

    -- Who is attacking you, and forgetting monsters.
    enemy.reset();
    enemy.on_round(0, MOB, 2002);
    enemy.on_round(1, MOB2, ME);
    check('finds who is hitting me', enemy.attacking(2, ME) == MOB2, enemy.attacking(2, ME));
    check('not after 10 s', enemy.attacking(12, ME) == nil);
    enemy.on_round(3, MOB, ME);
    check('stays on the one it follows', enemy.attacking(4, ME, MOB2) == MOB2, enemy.attacking(4, ME, MOB2));
    check('moves on when that one goes quiet', enemy.attacking(11.5, ME, MOB2) == MOB, enemy.attacking(11.5, ME, MOB2));
    enemy.sweep(20);
    check('kept while fresh', enemy.has(MOB) and enemy.has(MOB2));
    enemy.sweep(40, MOB);
    check('the followed one is kept while it sleeps', enemy.has(MOB) and not enemy.has(MOB2));
    enemy.sweep(40);
    check('dropped after 30 s quiet', not enemy.has(MOB) and not enemy.has(MOB2));

    -- Only so many clocks at once. The quietest one goes.
    enemy.reset();
    for i = 1, 65 do enemy.on_round(i, 0x01000000 + i, ME); end
    check('at most 64 clocks', not enemy.has(0x01000000 + 1) and enemy.has(0x01000000 + 65));

    -- A monster slowed to 12 s is learned from the 4 s first guess.
    enemy.reset();
    for _, t in ipairs({ 0, 12, 24, 36 }) do enemy.on_round(t, MOB, ME); end
    _, _, delay, learned = enemy.progress(36, MOB);
    check('a slowed 12 s monster is learned', near(delay, 12.0) and learned, delay);

    check('a learned slow attacker stays followed after10s', enemy.attacking(47, ME, MOB) == MOB);
    check('a slow attacker is released after its delay-scaled quiet window', enemy.attacking(55, ME, MOB) == nil);
    enemy.on_hold_begin(40, MOB, 'spell');
    check('an active casting hold keeps the attacker through a long spell', enemy.attacking(80, ME, MOB) == MOB);
    enemy.on_hold_end(81, MOB, false);
    check('a completed hold gets its own fresh activity window', enemy.attacking(92, ME, MOB) == MOB);
    local info = enemy.info(92, MOB);
    check('enemy diagnostics expose learned delay and bounded sample count',
        info.delay == 12 and info.samples == 3 and info.source == 'observed');

    -- An interrupted spell still waits out its 2 s, and a paralyzed spell's interrupt adds nothing more.
    enemy.reset();
    enemy.on_round(0, MOB, ME);
    enemy.on_hold_begin(1.0, MOB);
    enemy.on_interrupt(4.0, MOB, true);
    _, left2 = enemy.progress(4.0, MOB);
    check('an interrupted spell adds its 2 s', near(left2, 5.0), left2);
    enemy.reset();
    enemy.on_round(0, MOB, ME);
    enemy.on_hold_begin(1.0, MOB);
    enemy.on_hold_end(4.0, MOB, false);
    enemy.on_interrupt(4.0, MOB, true);
    _, left2 = enemy.progress(4.0, MOB);
    check('no second tail after a paralyzed spell', near(left2, 5.0), left2);

    -- A monster that attacks with TP moves, like a flying wyrm. The move used up its delay.
    enemy.reset();
    enemy.on_round(0, MOB, ME);
    enemy.on_hold_end(4.0, MOB, false);
    _, left2 = enemy.progress(4.0, MOB);
    check('a TP move used as an attack uses up the delay', near(left2, 6.0), left2);

    -- Engaging again restarts from 2.8 s, but not for a monster that's already attacking.
    enemy.reset();
    enemy.on_round(0, MOB, ME);
    enemy.on_engage(1, MOB);
    _, left2 = enemy.progress(1, MOB);
    check('engage leaves an attacking monster alone', near(left2, 3.0), left2);

    -- The packet reader.
    local round = MOCK.action_packet(MOB, 1, 0, ME, { { message = 1 } });
    check('reads who got attacked', packets.action_target(round) == ME, packets.action_target(round));
    enemy.reset();
end

-- The whole addon -----------------------------------------------------------------------------------
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local hud = require('ui.hud');

local function frames(n, dt)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do MOCK.frame(dt); end
    MOCK.record_imgui = false;
end
local function windows_named(name)
    local n = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'Begin' and call[2] == name) then n = n + 1; end
    end
    return n;
end
local function texts()
    local found = {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddText') then table.insert(found, c[6]); end
    end
    return table.concat(found, '|');
end
local function round_on(actor, target) MOCK.fire('packet_in', MOCK.action_packet(actor, 1, 0, target, { { message = 1 } })); end

MOCK.entities[0x200] = { ServerId = MOB, Name = 'Young Quadav', Status = 1, SpawnFlags = 0x10 };
MOCK.entities[0x201] = { ServerId = MOB2, Name = 'Goblin Thug', Status = 1, SpawnFlags = 0x10 };

-- Off by default. Nothing is drawn and monster packets are ignored.
MOCK.now = 100;
MOCK.player.status = 1;
MOCK.player.target_index = 0x200;
frames(2);
round_on(MOB, ME);
frames(2);
check('off by default', s.enemy.enabled == false and windows_named('##cadence_enemy') == 0 and not enemy.has(MOB));

-- On, following the target.
MOCK.fire('command', { command = '/cadence enemy on' });
check('/cadence enemy on', s.enemy.enabled == true and (MOCK.printed[#MOCK.printed] or ''):find('The enemy attack timer is on') ~= nil,
    MOCK.printed[#MOCK.printed]);
round_on(MOB, ME);
frames(3);
check('draws the target\'s timer', windows_named('##cadence_enemy') == 3, windows_named('##cadence_enemy'));
local shown = texts();
check('label, name and speed', shown:find('ENEMY ATTACK', 1, true) and shown:find('Young Quadav  4.00s est.', 1, true), shown);

-- With nothing targeted, it stays on the monster it was following while that one keeps hitting you.
MOCK.player.target_index = 0;
round_on(MOB2, ME);
frames(1);
check('stays on the monster hitting me', texts():find('Young Quadav', 1, true) ~= nil, texts());

-- Once that one goes quiet, it moves on to the other one hitting you.
for _ = 1, 3 do
    MOCK.now = MOCK.now + 4;
    round_on(MOB2, ME);
    frames(1);
end
check('moves on to whoever is hitting me', texts():find('Goblin Thug', 1, true) ~= nil, texts());

-- On My target only with no target, nothing shows. Keep the last monster is off, or it would keep
-- the one it follows.
s.enemy.which = 'target';
s.enemy.keep_last = false;
frames(1);
check('target only shows nothing without a target', windows_named('##cadence_enemy') == 0);
s.enemy.keep_last = true;
s.enemy.which = 'attacker';
MOCK.player.target_index = 0x200;
frames(1);
check('attacker only ignores the target', texts():find('Goblin Thug', 1, true) ~= nil, texts());
s.enemy.which = 'target_first';

-- A player or NPC target isn't followed.
MOCK.entities[0x300] = { ServerId = 0x01000300, Name = 'Some NPC', Status = 0, SpawnFlags = 0x02 };
MOCK.player.target_index = 0x300;
frames(1);
check('an NPC target falls back to the attacker', texts():find('Some NPC', 1, true) == nil and texts():find('Goblin Thug', 1, true) ~= nil, texts());

-- A monster a script spawned mid-game has an id that isn't its index.
MOCK.entities[0x705] = { ServerId = 0x01000805, Name = 'Twinkling Treant', Status = 1, SpawnFlags = 0x10 };
MOCK.entities[0x201] = nil;
MOCK.player.target_index = 0;
MOCK.now = MOCK.now + 11;
round_on(0x01000805, ME);
frames(1);
check('a spawned monster hitting me is shown', texts():find('Twinkling Treant', 1, true) ~= nil, texts());
MOCK.entities[0x705] = nil;

-- Pulling your target starts its first round's countdown.
MOCK.entities[0x202] = { ServerId = 0x01000202, Name = 'Mad Sheep', Status = 0, SpawnFlags = 0x10 };
MOCK.player.target_index = 0x202;
frames(2);
check('an idle target shows nothing', windows_named('##cadence_enemy') == 0);
MOCK.entities[0x202].Status = 1;
frames(1);
local pulled_at = MOCK.now;
MOCK.now = MOCK.now + 0.5;
frames(1);
local _, pulled_left = enemy.progress(MOCK.now, 0x01000202);
check('a pulled target counts down to its first round', windows_named('##cadence_enemy') == 1 and near(pulled_left, 2.8 - (MOCK.now - pulled_at), 0.02),
    tostring(pulled_left));

-- A spell interrupted by a hit still waits out its 2 s. A TP move that misses for range ends its hold.
local SHEEP = 0x01000202;
round_on(SHEEP, ME);
local round_at = MOCK.now;
MOCK.now = round_at + 1;
MOCK.fire('packet_in', MOCK.action_packet(SHEEP, 8, 0x68776163, ME, { { message = 0 } }));
MOCK.now = round_at + 3;
MOCK.fire('packet_in', MOCK.action_packet(SHEEP, 8, 0x68777073, ME, { { message = 0 } }));
local _, spell_left = enemy.progress(MOCK.now, SHEEP);
check('an interrupted spell still holds 2 s', near(spell_left, 3.0 + 2.0, 0.001), spell_left);
round_on(SHEEP, ME);
round_at = MOCK.now;
MOCK.now = round_at + 1;
MOCK.fire('packet_in', MOCK.action_packet(SHEEP, 7, 0x65746163, ME, { { message = 0 } }));
MOCK.now = round_at + 2;
MOCK.fire('packet_in', MOCK.action_packet(SHEEP, 4, 0, ME, { { message = 78 } }));
local _, missed_left = enemy.progress(MOCK.now + 10, SHEEP);
check('a TP move that misses for range ends its hold', missed_left == 0, missed_left);

-- Attached under the auto attack timer.
MOCK.player.target_index = 0x200;
round_on(MOB, ME);
s.enemy.attached = true;
hud.refresh(s);
frames(1);
local attack_at = MOCK.positions['##cadence_attack'];
local enemy_at = MOCK.positions['##cadence_enemy'];
local _, attack_height = hud.element_size('attack');
check('attached sits under the auto attack timer', enemy_at[1] == attack_at[1] and enemy_at[2] == attack_at[2] + attack_height - 1,
    ('%d,%d under %d,%d+%d'):format(enemy_at[1], enemy_at[2], attack_at[1], attack_at[2], attack_height));
s.attack.show_tp = false;
hud.refresh(s);
frames(1);
local _, short_height = hud.element_size('attack');
enemy_at = MOCK.positions['##cadence_enemy'];
check('attached moves up without the TP line', short_height < attack_height and enemy_at[2] == attack_at[2] + short_height - 1,
    ('%d vs %d+%d'):format(enemy_at[2], attack_at[2], short_height));
s.attack.show_tp = true;
hud.refresh(s);
frames(1);
local attack_width = hud.element_size('attack');
local strip_width, strip_height = hud.element_size('enemy');
check('attached is as wide and shorter', strip_width == attack_width and strip_height < attack_height, strip_width .. 'x' .. strip_height);
check('attached says ENEMY', texts():find('ENEMY|', 1, true) ~= nil, texts());
local square = false;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'dl:AddRectFilled' and c[6] == ImDrawFlags_RoundCornersTop) then square = true; end
end
check('the auto attack card squares its bottom corners', square);
local reach = 0;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'SetNextWindowSize' and c[2][2] > attack_height) then reach = c[2][2]; end
end
check('the auto attack window reaches over the strip', reach == attack_height + strip_height - 1, reach);

-- Not engaged, the strip stays put so it doesn't jump when you engage.
MOCK.player.status = 0;
frames(2);
enemy_at = MOCK.positions['##cadence_enemy'];
check('strip stays put between fights', enemy_at[1] == s.attack.x and enemy_at[2] == s.attack.y + attack_height - 1,
    enemy_at[1] .. ',' .. enemy_at[2]);

-- Resting at a shared spot, the strip hangs under the resting card instead of covering it.
s.style.shared_spot = true;
hud.refresh(s);
MOCK.player.status = 33;
frames(2);
local resting_at = MOCK.positions['##cadence_resting'];
local _, resting_height = hud.element_size('resting');
enemy_at = MOCK.positions['##cadence_enemy'];
check('strip hangs under the resting card at a shared spot', enemy_at[2] == resting_at[2] + resting_height - 1,
    enemy_at[2] .. ' vs ' .. resting_at[2]);
s.style.shared_spot = false;
MOCK.player.status = 1;
hud.refresh(s);

-- With the auto attack timer off, it sits at its own spot.
s.attack.enabled = false;
frames(2);
enemy_at = MOCK.positions['##cadence_enemy'];
check('strip goes to its own spot with the auto attack timer off', enemy_at[1] == s.enemy.x and enemy_at[2] == s.enemy.y,
    enemy_at[1] .. ',' .. enemy_at[2]);
s.attack.enabled = true;
s.enemy.attached = false;
hud.refresh(s);

-- The monster dies. Its clock goes and the bar with it. The sheep leaves first, so nothing else is
-- hitting you to fall back to.
MOCK.entities[0x202] = nil;
MOCK.player.target_index = 0x200;
round_on(MOB, ME);
frames(1);
MOCK.entities[0x200].Status = 3;
frames(2);
check('a dead monster is forgotten', not enemy.has(MOB) and windows_named('##cadence_enemy') == 0);
MOCK.entities[0x200].Status = 1;

-- Hidden during events like the others.
round_on(MOB, ME);
MOCK.in_event = true;
frames(2);
check('hidden during events', windows_named('##cadence_enemy') == 0);
MOCK.in_event = false;

-- Zoning forgets every monster.
MOCK.fire('packet_in', MOCK.zone_packet(ME));
check('zoning forgets monsters', not enemy.has(MOB));

MOCK.fire('command', { command = '/cadence enemy off' });
check('/cadence enemy off', s.enemy.enabled == false);

local errors = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
check('no drawing errors', errors == nil, errors);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
