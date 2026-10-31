-- Server maximum vitals must win while the native stats view still holds the weakened caps.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local function dword(value)
    return string.char(value % 256, math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256);
end
local function stats(hp, mp)
    return { id = 0x061, size = 0x84,
        data = string.rep('\0', 4) .. dword(hp) .. dword(mp) .. string.rep('\0', 0x78) };
end
local function native(fields)
    local e = newproxy(true);
    getmetatable(e).__index = function (_, key) return fields[key]; end;
    return e;
end
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local resting, player, observer = require('core.resting'), require('core.player'), require('core.stat_state');
local hud, sound = require('ui.hud'), require('ui.sound');
local s, view, plays = MOCK.settings.current, nil, 0;
s.attack.enabled, s.enemy.enabled = false, false;
s.resting.enabled, s.resting.hide_when_full, s.resting.sound = true, true, true;
s.resting.show_each_full, s.resting.show_until_full = true, true;
hud.draw_resting = function (v) view = v; end;
sound.play = function () plays = plays + 1; return true; end;
local function frame(dt) view = nil; MOCK.frame(dt or 0.25); end
local function incoming(e) MOCK.fire('packet_in', native(e)); end
local function vitals(hp, mp, hpp, mpp)
    local e = MOCK.vitals_packet(MOCK.player.server_id, hp, mp, 0);
    if (hpp ~= nil and mpp ~= nil) then
        e.data = e.data:sub(1, 22) .. string.char(hpp, mpp) .. e.data:sub(25);
    end
    incoming(e);
end
for _, case in ipairs({
    { name = 'HP-only job', hp = 300, mp = 0, max_hp = 1200, max_mp = 0 },
    { name = 'HP and MP', hp = 300, mp = 100, max_hp = 1200, max_mp = 400 },
    { name = 'MP only changes', hp = 300, mp = 100, max_hp = 300, max_mp = 400 },
}) do
    MOCK.player.status = 0; frame();
    incoming(MOCK.zone_packet(MOCK.player.server_id));
    MOCK.player.hp_max, MOCK.player.mp_max = case.hp, case.mp;
    MOCK.player.buffs = { 1 };
    incoming(stats(case.hp, case.mp)); vitals(case.hp, case.mp);
    frame();
    MOCK.player.status = 33; frame(); frame(24);
    local before, sounds = resting.info(MOCK.now), plays;
    check(case.name .. ': weakened full state is hidden', resting.is_full() and view == nil);
    MOCK.player.buffs = {};
    incoming(stats(case.max_hp, case.max_mp));
    check(case.name .. ': restored server caps clear full immediately', not resting.is_full());
    -- No current-vitals packet and no native stats update; also wait beyond the normal input cache.
    for _ = 1, 8 do frame(); end
    local hp, mp = resting.until_each_full(MOCK.now);
    check(case.name .. ': restored HP and MP forecasts remain visible', view ~= nil and not view.full
        and (case.max_hp == case.hp and hp == 0 or case.max_hp > case.hp and hp ~= nil and hp > 0)
        and (case.max_mp == case.mp and mp == 0 or case.max_mp > case.mp and mp ~= nil and mp > 0));
    local after = resting.info(MOCK.now);
    check(case.name .. ': caps do not invent a tick or completion sound', after.accepted == before.accepted
        and after.ticks == before.ticks and after.next_tick == before.next_tick and plays == sounds);
    check(case.name .. ': the recovery model uses the same authoritative caps',
        observer.snapshot().max_hp == case.max_hp and observer.snapshot().max_mp == case.max_mp);
    vitals(case.hp, case.mp); frame();
    check(case.name .. ': a following current-vitals packet cannot restore stale caps', not resting.is_full());
    MOCK.player.hp_max, MOCK.player.mp_max = case.max_hp, case.max_mp; frame();
    check(case.name .. ': native memory catching up leaves timing unchanged', resting.info(MOCK.now).next_tick == before.next_tick);
    vitals(case.max_hp, case.max_mp); frame();
    check(case.name .. ': filling the restored caps hides and sounds once', resting.is_full() and view == nil and plays == sounds + 1);
end

for _, e in ipairs({ stats(0, 400), stats(0xFFFFFFFF, 400), stats(1200, 0xFFFFFFFF),
    { id = 0x061, size = 8, data = stats(999, 999).data },
    { id = 0x061, size = 0x84, data = string.rep('\0', 11) } }) do
    incoming(e);
end
for _, flag in ipairs({ 'blocked', 'injected' }) do
    local e = stats(999, 999); e[flag] = true; incoming(e);
end
local hp, mp = player.max_vitals();
check('malformed, blocked and injected stats cannot replace caps', hp == 300 and mp == 400);
MOCK.player.hp_max, MOCK.player.mp_max = 800, 0;
incoming(MOCK.zone_packet(MOCK.player.server_id));
hp, mp = player.max_vitals();
check('zoning drops the old character caps and restores memory fallback', hp == 800 and mp == 0);

-- Weakness expiry sends updated percentages without necessarily sending exact maximums.
for _, no_mp in ipairs({ true, false }) do
    MOCK.player.status = 0; frame();
    incoming(MOCK.zone_packet(MOCK.player.server_id));
    MOCK.player.hp_max, MOCK.player.mp_max = 300, no_mp and 0 or 100;
    incoming(stats(300, MOCK.player.mp_max)); vitals(300, MOCK.player.mp_max, 100, no_mp and 0 or 100);
    frame(); MOCK.player.status = 33; frame(); frame(24);
    local before, sounds = resting.info(MOCK.now), plays;
    vitals(300, MOCK.player.mp_max, 25, no_mp and 0 or 25); frame();
    local hp_full, mp_full, _, meta = resting.until_each_full(MOCK.now);
    local _, _, hp_quality, mp_quality = player.max_vitals();
    check('percent-only expiry reveals recovery with ' .. (no_mp and 'no MP' or 'MP'), view ~= nil
        and not resting.is_full() and hp_full ~= nil and hp_full > 0
        and (no_mp and mp_full == 0 or not no_mp and mp_full ~= nil and mp_full > 0));
    check('inferred caps and full times remain explicitly estimated', hp_quality == true
        and (no_mp or mp_quality == true) and meta.hp_confidence == 'estimated'
        and meta.confidence == 'estimated' and (no_mp or meta.mp_confidence == 'estimated'));
    for _ = 1, 8 do frame(); end
    local after = resting.info(MOCK.now);
    check('stale memory cannot undo a percent-only maximum correction', not resting.is_full()
        and after.ticks == before.ticks and after.accepted == before.accepted
        and after.next_tick == before.next_tick and plays == sounds);
    -- A rounded 25% snapshot does not prove that the cap is exactly 1200.
    vitals(1199, no_mp and 0 or 399, 100, no_mp and 0 or 100); frame();
    hp, mp, hp_quality, mp_quality = player.max_vitals();
    check('100 percent confirms the real caps and completes once', hp == 1199
        and mp == (no_mp and 0 or 399) and not hp_quality and not mp_quality
        and resting.is_full() and view == nil and plays == sounds + 1);
end

-- Learned recovery must not turn an inferred cap into an exact full-time promise.
resting.reset(); resting.on_vitals(-1, 100, 10, 0, 1200, 400, true, true);
resting.on_model({ resting_key = 'quality', hp_base = 10, hp_step = 1, hp_known = true,
    mp_base = 12, mp_step = 1, mp_known = true, regen_known = true, refresh_known = true });
resting.start(0);
resting.on_vitals(21, 110, 22, 0, 1200, 400, true, true);
resting.on_vitals(30, 121, 35, 0, 1200, 400, true, true);
resting.on_vitals(42, 133, 49, 0, 1200, 400, true, true);
local _, _, _, meta = resting.until_each_full(42);
check('observed ticks cannot erase uncertainty in maximums', resting.pattern_known()
    and meta.hp_confidence == 'estimated' and meta.mp_confidence == 'estimated' and meta.confidence == 'estimated');
resting.on_vitals(42.1, 1, 49, 0, 51, 400, 'unknown', true);
local hp_full, mp_full;
hp_full, mp_full, _, meta = resting.until_each_full(42.1);
check('unbounded one-percent HP suppresses its full time independently of MP', hp_full == nil
    and mp_full ~= nil and mp_full > 0 and meta.hp_confidence == 'unknown' and not resting.is_full());
check('new stat observation sends no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
