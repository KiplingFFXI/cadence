-- Only observed monster casts feed the selected enemy bar, including when attack tracking is hidden.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
local resources = AshitaCore.GetResourceManager;
local reads = 0;
AshitaCore.GetResourceManager = function(...)
    local manager = resources(...);
    manager.GetSpellById = function(_, id) reads = reads + 1; return { Name = { id == 144 and 'Fire' or 'Fire II' }, CastTime = 400 }; end;
    return manager;
end;
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local cast, hud = require('core.enemy_cast'), require('ui.hud');
local base = require('data.phoenix_recovery').spell_casts[144];
local MOB, OTHER, PET = 0x01000200, 0x01000201, 0x01000202;
MOCK.entities[0x200] = { ServerId = MOB, Name = 'Goblin', Status = 1, SpawnFlags = 0x10 };
MOCK.entities[0x201] = { ServerId = OTHER, Name = 'Orc', Status = 1, SpawnFlags = 0x10 };
MOCK.entities[0x202] = { ServerId = PET, Name = 'Pet', Status = 1, SpawnFlags = 0x100 };
MOCK.player.target_index = 0x200;
local sequence, view = 0, {};
local function action(actor, category, param, value)
    local event = MOCK.action_packet(actor, category, param, MOCK.player.server_id, { { message = 327, damage = value or 144 } });
    sequence = sequence + 1;
    event.data_raw[2], event.data_raw[3] = sequence % 256, math.floor(sequence / 256);
    event.data = MOCK.to_string(event.data_raw);
    return event;
end
local function incoming(event, now) MOCK.now = now; MOCK.fire('packet_in', event); end
local function command(words) MOCK.fire('command', { command = '/cadence ' .. words }); end
local function frame(now) MOCK.now = now; MOCK.frame(0); end
incoming(action(MOB, 8, 0x6163, 144), 1);
check('casting starts off and ignores earlier observations', not MOCK.settings.current.enemycast.enabled and not cast.progress(1, MOB, view));
command('enemycast on'); command('enemy off');
incoming(action(MOB, 8, 0x6163, 144), 2);
check('accepted monster starts use result spell ID and Phoenix base time', cast.progress(2.1, MOB, view)
    and view.spell_id == 144 and view.spell == 'Fire' and view.duration == base and view.duration ~= 100);
local draws, shown, original = 0, {}, hud.draw_enemycast;
hud.draw_enemycast = function(value)
    draws = draws + 1; shown.spell, shown.waiting = value.spell, value.waiting; return original(value);
end;
frame(2.2);
check('the cast bar follows the selected monster with enemy attack disabled', draws == 1 and shown.spell == 'Fire');
local resource_reads = reads;
for _ = 1, 10 do frame(2.3); end
check('steady frames do not reread spell resources', reads == resource_reads);
frame(2 + base + 0.1);
check('estimated expiry keeps the observed spell waiting', shown.waiting and cast.progress(2 + base + 0.1, MOB, view));
incoming(action(MOB, 4, 145), 10);
check('a different spell finish cannot clear the active cast', cast.progress(10, MOB, view));
local finish = action(MOB, 4, 144);
incoming(finish, 11);
check('a matching observed finish ends the cast', not cast.progress(11, MOB, view));
incoming(action(MOB, 8, 0x6163, 144), 12); incoming(finish, 12.2);
check('replayed old completion cannot end a same-spell recast', cast.progress(12.2, MOB, view));
incoming(action(MOB, 8, 0x7073, 144), 12.3);
check('an observed interruption clears the cast', not cast.progress(12.3, MOB, view));
for _, actor in ipairs({ MOCK.player.server_id, 2002, PET }) do incoming(action(actor, 8, 0x6163, 144), 13); end
incoming(action(MOB, 7, 0x6163, 144), 13);
check('player party pet and TP starts cannot create enemy spell bars', not cast.progress(13, MOCK.player.server_id, view)
    and not cast.progress(13, 2002, view) and not cast.progress(13, PET, view) and not cast.progress(13, MOB, view));
for _, flag in ipairs({ 'blocked', 'injected' }) do
    local event = action(MOB, 8, 0x6163, 144); event[flag] = true; incoming(event, 14);
    check(flag .. ' cast is ignored', not cast.progress(14, MOB, view));
end
local short = action(MOB, 8, 0x6163, 144); short.size, short.data = 20, short.data:sub(1, 20); incoming(short, 14);
check('truncated starts are ignored', not cast.progress(14, MOB, view));
incoming(action(MOB, 8, 0x6163, 144), 15);
incoming(action(OTHER, 8, 0x6163, 145), 15);
MOCK.player.target_index = 0x201; frame(15.1);
check('target switching shows the other observed cast', shown.spell == 'Fire II');
MOCK.player.target_index = 0x200; frame(15.2);
check('switching back retains the original cast', shown.spell == 'Fire');
command('enemycast off'); command('enemycast on');
check('off then on does not restore old observations', not cast.progress(15.3, MOB, view) and not cast.progress(15.3, OTHER, view));
incoming(action(MOB, 8, 0x6163, 144), 16);
local leave = MOCK.message_packet(MOB, 0, 0, 0, 0, 0); leave.id = 0x00E;
leave.data_raw[8], leave.data_raw[9], leave.data_raw[10] = 0, 2, 0x20; leave.data = MOCK.to_string(leave.data_raw);
incoming(leave, 16.1);
check('despawn immediately clears cast identity', not cast.progress(16.1, MOB, view));
incoming(action(MOB, 8, 0x6163, 144), 17); incoming(MOCK.status_packet(1001, 2), 17.1);
check('player death clears tracked enemy casts', not cast.progress(17.1, MOB, view));
incoming(action(MOB, 8, 0x6163, 144), 17.2);
check('late cast packets while dead cannot rebuild stale observations', not cast.progress(17.2, MOB, view));
incoming(MOCK.status_packet(1001, 0), 18);
incoming(action(MOB, 8, 0x6163, 144), 19); incoming(MOCK.zone_packet(1001), 19.1);
check('zoning clears all casts', not cast.progress(19.1, MOB, view));
incoming(action(MOB, 8, 0x6163, 144), 20);
MOCK.settings.callbacks.cadence_settings_update(MOCK.settings.current);
check('character settings reload clears all casts', not cast.progress(20, MOB, view));
incoming(action(MOB, 8, 0x6163, 144), 30);
incoming(MOCK.action_packet(MOB, 4, 144, nil, nil), 30.1);
check('an empty finish cannot clear a cast', cast.progress(30.1, MOB, view));
incoming(action(MOB, 4, 0), 30.2);
check('a zero-id finish cannot become a wildcard completion', cast.progress(30.2, MOB, view));
incoming(MOCK.action_packet(MOB, 8, 0x7073, nil, nil), 30.3);
incoming(MOCK.action_packet(MOB, 1, 0, nil, nil), 30.4);
check('empty interrupt and attack evidence cannot clear a cast', cast.progress(30.4, MOB, view));
incoming(action(MOB, 8, 0x6163, 145), 31);
incoming(action(MOB, 8, 0x7073, 144), 31.1);
check('a different spell interruption cannot clear a newer cast', cast.progress(31.1, MOB, view) and view.spell_id == 145);
incoming(action(MOB, 8, 0x7073, 145), 31.2);
check('an identified matching interruption still clears its cast', not cast.progress(31.2, MOB, view));
require('core.enemy').reset();
MOCK.entities[0x200].Status, MOCK.player.target_index = 0, 0x200;
local previous_draws = draws;
incoming(action(MOB, 8, 0x6163, 144), 39); frame(39.1);
check('an idle monster cast displays without a melee clock', draws == previous_draws + 1 and shown.spell == 'Fire');
MOCK.player.target_index = 0; previous_draws = draws; frame(40);
check('keep-last retains an observed cast without an attack clock', draws == previous_draws + 1 and shown.spell == 'Fire');
previous_draws = draws; frame(52);
check('keep-last retains a long unresolved cast beyond the attack activity window', draws == previous_draws + 1 and shown.waiting);
MOCK.player.target_index, MOCK.entities[0x200].Status = 0x200, 1;
incoming(action(MOB, 8, 0x6163, 144), 53); frame(53.1);
MOCK.entities[0x200].Status = 0; previous_draws = draws; frame(53.2);
check('an engaged-to-idle transition alone does not invent cast completion', draws == previous_draws + 1 and cast.progress(53.2, MOB, view));
check('the feature sends no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
