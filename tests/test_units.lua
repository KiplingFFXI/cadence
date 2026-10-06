-- Packets, delay and the auto attack timer, each on its own.
local out = {};
local fails = 0;
local function check(name, cond, detail)
    if (cond) then
        table.insert(out, 'ok   ' .. name);
    else
        fails = fails + 1;
        table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or ''));
    end
end
local function near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 1e-6); end

local packets = require('core.packets');
local delay   = require('core.delay');
local attack  = require('core.attack');

-- packets --------------------------------------------------------------------------------------
do
    local e = MOCK.action_packet(1001, 1, 0x306B7461, 0x01000123, {
        { message = 1 }, { message = 15, add_effect = true }, { message = 67, reaction = true },
        { message = 31, add_effect = true, reaction = true }, { message = 70 },
    });
    local actor, category = packets.action_header(e);
    check('action actor', actor == 1001, actor);
    check('action category', category == 1, category);
    local msgs = {};
    local n = packets.action_messages(e, msgs);
    check('action result count', n == 5, n);
    check('action messages', msgs[1] == 1 and msgs[2] == 15 and msgs[3] == 67 and msgs[4] == 31 and msgs[5] == 70,
        table.concat(msgs, ','));

    local cast = MOCK.action_packet(1001, 8, 0x68776163, 0x01000123, { { message = 327 } });
    check('cast begin param', packets.action_param(cast) == packets.CAST_BEGIN, packets.action_param(cast));
    local stop = MOCK.action_packet(1001, 8, 0x68777073, 0x01000123, { { message = 16 } });
    check('cast interrupt param', packets.action_param(stop) == packets.CAST_INTERRUPT, packets.action_param(stop));

    -- A packet that's cut short isn't read past its end.
    local short = MOCK.action_packet(1001, 1, 0, 0x01000123, { { message = 1 }, { message = 1 } });
    short.size = 30;
    local m2 = {};
    local n2 = packets.action_messages(short, m2);
    check('short packet stops early', n2 < 2, n2);

    local msg = MOCK.message_packet(1001, 0x01000123, 42, 68, 4, 291);
    local a, m = packets.message(msg);
    check('message fields', a == 1001 and m == 4, tostring(a) .. ',' .. tostring(m));

    local v = MOCK.vitals_packet(1001, 800, 150, 1000);
    local hp, mp, tp = packets.vitals(v);
    check('vitals member', packets.vitals_member(v) == 1001, packets.vitals_member(v));
    check('vitals fields', hp == 800 and mp == 150 and tp == 1000);
end

-- delay --------------------------------------------------------------------------------------
do
    local function est(main, sub, mj, ml, sj, sl, buffs)
        local b = {};
        for _, id in ipairs(buffs or {}) do b[id] = true; end
        return delay.estimate({ main = main, sub = sub, main_job = mj, main_level = ml, sub_job = sj or 0, sub_level = sl or 0, buffs = b });
    end
    check('sword 240 = 4.000', near(est({ delay = 240, skill = 3 }, nil, 1, 75), 4.000), est({ delay = 240, skill = 3 }, nil, 1, 75));
    check('dagger 227 = 3.783', near(est({ delay = 227, skill = 2 }, nil, 6, 75), 3.783), est({ delay = 227, skill = 2 }, nil, 6, 75));
    check('MNK75 unarmed = 5.000', near(est(nil, nil, 2, 75), 5.000), est(nil, nil, 2, 75));
    check('MNK75 unarmed + Haste = 4.267', near(est(nil, nil, 2, 75, 0, 0, { 33 }), 4.267), est(nil, nil, 2, 75, 0, 0, { 33 }));
    check('MNK75 Destroyers (client 288) = 5.800', near(est({ delay = 288, skill = 1 }, nil, 2, 75), 5.800), est({ delay = 288, skill = 1 }, nil, 2, 75));
    check('NIN75 two 227 katanas = 5.296', near(est({ delay = 227, skill = 9 }, { delay = 227, skill = 9 }, 13, 75), 5.296),
        est({ delay = 227, skill = 9 }, { delay = 227, skill = 9 }, 13, 75));
    check('Hundred Fists MNK75 = 1.250', near(est(nil, nil, 2, 75, 0, 0, { 46 }), 1.250), est(nil, nil, 2, 75, 0, 0, { 46 }));
    check('WAR unarmed = 8.000', near(est(nil, nil, 1, 75), 8.000), est(nil, nil, 1, 75));
    check('WAR/MNK37 unarmed gets MA 120 from sub', near(est(nil, nil, 1, 75, 2, 37), (8000 - 2000) / 1000), est(nil, nil, 1, 75, 2, 37));
    check('Hasso only on two-handed', near(est({ delay = 240, skill = 3 }, nil, 12, 75, 0, 0, { 353 }), 4.000));
    check('Hasso great katana 450', near(est({ delay = 450, skill = 10 }, nil, 12, 75, 0, 0, { 353 }), math.floor(7500 * 0.9) / 1000),
        est({ delay = 450, skill = 10 }, nil, 12, 75, 0, 0, { 353 }));
    check('Shield in sub is not dual wield', near(est({ delay = 240, skill = 3 }, { delay = 0, skill = 0 }, 7, 75), 4.000));
    check('Weakness doubles delay', near(est({ delay = 240, skill = 3 }, nil, 1, 75, 0, 0, { 1 }), 8.000),
        est({ delay = 240, skill = 3 }, nil, 1, 75, 0, 0, { 1 }));
end

-- attack -------------------------------------------------------------------------------------
do
    attack.reset();
    attack.engage(100.0, 4.0, 'k1');
    local fill, left, d = attack.progress(100.0);
    check('engage first attack 2.8s', near(left, 2.8), left);
    check('engage delay shown', near(d, 4.0), d);
    fill, left = attack.progress(101.4);
    check('half way to first attack', near(fill, 0.5), fill);

    -- Rounds land on 0.4 s server ticks, with a real delay of 3.783 s.
    local t = 101.6;
    attack.on_round(t, 3.8, 'k1');   -- estimate a bit off, like unseen gear haste would cause
    local true_d = 3.783;
    local times = { t };
    for k = 1, 8 do
        local next_server = 0.4 * math.ceil((k * true_d) / 0.4 - 1e-9);
        times[#times + 1] = 101.6 + next_server;
    end
    for i = 2, #times do attack.on_round(times[i], 3.8, 'k1'); end
    local _, _, learned = attack.progress(times[#times]);
    check('learned delay near 3.783', near(learned, 3.783, 0.08), learned);
    check('is_learned', attack.is_learned());

    -- A new loadout key forgets what was learned.
    attack.on_round(times[#times] + 3.8, 5.0, 'k2');
    check('new loadout forgets learning', not attack.is_learned());

    -- Job ability pushes the next attack back 2 s.
    attack.reset();
    attack.engage(0, 4.0, 'a');
    attack.on_round(1.6, 4.0, 'a');
    attack.on_ability(3.0);
    local _, left2 = attack.progress(3.0);
    check('ability adds 2 s', near(left2, 2.6 + 2.0), left2);

    -- Spell holds the bar and adds 2 s after it ends.
    attack.reset();
    attack.engage(0, 4.0, 'a');
    attack.on_round(1.6, 4.0, 'a');
    attack.on_cast_begin(2.6, 'spell');
    local f1 = attack.progress(2.6);
    local f2 = attack.progress(4.0);
    check('bar frozen while casting', near(f1, f2), tostring(f1) .. ' vs ' .. tostring(f2));
    attack.on_cast_end(5.0);
    local _, left3 = attack.progress(5.0);
    check('cast end adds remaining + 2 s', near(left3, 3.0 + 2.0), left3);

    -- Ready bar waits at zero when out of range, then resets on the round.
    attack.reset();
    attack.engage(0, 4.0, 'a');
    attack.on_round(1.6, 4.0, 'a');
    local fr, lr = attack.progress(9.0);
    check('ready bar full', near(fr, 1) and near(lr, 0), tostring(fr) .. ' ' .. tostring(lr));

    -- Disengage hides the bar.
    attack.disengage();
    check('disengaged returns nil', attack.progress(10) == nil);
end

-- attack holds and gaps it doesn't learn ------------------------------------------------------
do
    -- Items hold one tick, ranged 0.8 s, spells 2 s.
    attack.reset();
    attack.engage(0, 4.0, 'a');
    attack.on_round(1.6, 4.0, 'a');
    attack.on_cast_begin(2.0, 'item');
    attack.on_cast_end(3.0);
    local _, left = attack.progress(3.0);
    check('item hold is one tick', near(left, 3.6 + 0.4), left);
    attack.on_round(7.0, 4.0, 'a');
    attack.on_cast_begin(8.0, 'ranged');
    attack.on_cast_end(10.0);
    _, left = attack.progress(10.0);
    check('ranged hold is 0.8 s', near(left, 3.0 + 0.8), left);
    attack.on_paralyzed(10.05);
    _, left = attack.progress(10.05);
    check('paralysis right after a ranged interrupt is ignored', near(left, 3.75), left);

    -- A paralyzed job ability long before the attack is due holds 2 s. Near the time it's due, it counts as the attack.
    attack.reset();
    attack.engage(0, 4.0, 'a');
    attack.on_round(1.6, 4.0, 'a');
    attack.on_paralyzed(2.6);
    _, left = attack.progress(2.6);
    check('paralyzed job ability holds 2 s', near(left, 3.0 + 2.0), left);
    attack.reset();
    attack.engage(0, 4.0, 'a');
    attack.on_round(1.6, 4.0, 'a');
    attack.on_paralyzed(5.5);
    _, left = attack.progress(5.5);
    check('paralyzed attack restarts the timer', near(left, 4.0), left);
    attack.on_cast_begin(6.0, 'item');
    attack.on_paralyzed(9.5);
    local _, held_left = attack.progress(9.5);
    check('paralysis while an item holds is ignored', near(held_left, 3.5), held_left);

    -- After a stall out of range, the gap to the first attack back is not learned.
    attack.reset();
    attack.engage(0, 4.0, 'a');
    attack.on_round(1.6, 4.0, 'a');
    attack.on_out_of_reach();
    attack.on_round(8.0, 4.0, 'a');
    attack.on_round(11.6, 4.0, 'a');
    attack.on_round(15.6, 4.0, 'a');
    attack.on_round(19.6, 4.0, 'a');
    attack.on_round(23.6, 4.0, 'a');
    local _, _, learned = attack.progress(23.6);
    check('stall gap not learned', near(learned, 4.0), learned);

    -- A stun between rounds is not learned.
    attack.reset();
    attack.engage(0, 4.0, 'a');
    attack.on_round(1.6, 4.0, 'a');
    attack.on_round(5.6, 4.0, 'a');
    attack.on_disabled();
    attack.on_round(11.6, 4.0, 'a');
    attack.on_round(15.6, 4.0, 'a');
    attack.on_round(19.6, 4.0, 'a');
    attack.on_round(23.6, 4.0, 'a');
    _, _, learned = attack.progress(23.6);
    check('stun gap not learned', near(learned, 4.0), learned);

    -- A slower real delay than the estimate is still learned.
    attack.reset();
    attack.engage(0, 4.0, 'a');
    local t = 1.6;
    attack.on_round(t, 4.0, 'a');
    for _ = 1, 6 do t = t + 4.8; attack.on_round(t, 4.0, 'a'); end
    _, _, learned = attack.progress(t);
    check('learns a slower delay', near(learned, 4.8, 0.01), learned);
end

-- delay key --------------------------------------------------------------------------------------
do
    local lo = { main = { id = 1, delay = 240, skill = 3 }, main_job = 1, main_level = 75, sub_job = 13, sub_level = 37,
        buffs = { [33] = true, [253] = true, [40] = true } };
    local key = delay.key(lo);
    check('delay key has haste buffs only', key == '1:0:1/75:13/37:33', key);
end

-- Elegy on you slows your own attacks, and adds to Slow.
do
    local delay = require('core.delay');
    local loadout = { main = { id = 16535, delay = 240, skill = 3 }, sub = nil, sub_used = false,
        main_job = 1, main_level = 75, sub_job = 13, sub_level = 37, buffs = { [194] = true } };
    check('Elegy on you slows your attacks', math.abs(delay.estimate(loadout) - 5.0) < 0.01, delay.estimate(loadout));
    loadout.buffs[13] = true;
    check('Elegy and Slow on you add up', math.abs(delay.estimate(loadout) - 4.0 * 1.43) < 0.01, delay.estimate(loadout));
end

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
