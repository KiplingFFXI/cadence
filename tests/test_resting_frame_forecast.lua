-- The live HUD shares one recovery forecast across its full-time readouts.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
MOCK.player.status = 33;
MOCK.player.hp, MOCK.player.hp_max = 100, 900;
MOCK.player.mp, MOCK.player.mp_max = 0, 100;
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load'); MOCK.frame(0);
local resting, hud = require('core.resting'), require('ui.hud');
local s = MOCK.settings.current;
s.resting.show_goal, s.resting.show_next_gains, s.resting.hide_full = false, false, false;
local calls, view = 0, nil;
local each, both = resting.until_each_full, resting.until_full;
resting.until_each_full = function (...)
    calls = calls + 1;
    return each(...);
end;
resting.until_full = function (...)
    calls = calls + 1;
    return both(...);
end;
hud.draw_resting = function (value) view = value; end;
local function sit(hp, mp, mp_max, model)
    resting.reset(); resting.on_buffs(MOCK.now, {});
    resting.on_vitals(MOCK.now, hp, mp, 0, 900, mp_max);
    if (model) then resting.on_model(model); end
    resting.start(MOCK.now);
end
local function frame()
    calls, view = 0, nil;
    MOCK.frame(0);
end
local model = { resting_key = 'frame-full', hp_base = 30, hp_step = 2, hp_known = true,
    mp_base = 12, mp_step = 1, mp_known = true };
sit(100, 0, 100, model);
local expected, meta = both(MOCK.now);
s.resting.show_until_full, s.resting.show_ticks, s.resting.show_each_full = true, true, true;
frame();
check('all full-time readouts share one forecast per frame', calls == 1);
check('combined full time and tick count retain their forecast', view and view.until_full == expected
    and view.full_meta.ticks == meta.ticks and view.hp_full_in ~= nil and view.mp_full_in ~= nil);
s.resting.show_each_full = false;
frame();
check('combined-only display makes one forecast', calls == 1 and view.until_full == expected);
s.resting.show_until_full, s.resting.show_ticks, s.resting.show_each_full = false, false, true;
frame();
check('separate-only display makes one forecast', calls == 1 and view.hp_full_in ~= nil and view.mp_full_in ~= nil);
s.resting.show_each_full = false;
frame();
check('hidden forecasts do no recovery simulation', calls == 0 and view.until_full == nil and view.full_meta == nil);
s.resting.show_until_full, s.resting.show_ticks, s.resting.show_each_full = true, true, true;
sit(100, 0, 100, { resting_key = 'frame-hp-only', hp_base = 30, hp_step = 2, hp_known = true });
frame();
check('unknown MP preserves HP time without inventing a combined time', calls == 1 and view.hp_full_in ~= nil
    and view.mp_full_in == nil and view.until_full == nil and view.full_meta.confidence == 'unknown');
sit(100, 0, 0, model);
frame();
check('jobs without MP retain their HP full time', calls == 1 and not view.has_mp and view.mp_full_in == 0
    and view.until_full == view.hp_full_in);
sit(900, 100, 100, model);
frame();
check('already full keeps zero separate times and no combined countdown', calls == 1 and view.full
    and view.hp_full_in == 0 and view.mp_full_in == 0 and view.until_full == nil);
sit(890, 100, 100, { resting_key = 'frame-drain', hp_base = 10, hp_step = 1, hp_known = true, refresh_down = 2 });
frame();
check('MP that drains cannot produce a false combined full time', calls == 1 and view.hp_full_in ~= nil
    and view.mp_full_in == 0 and view.until_full == nil);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
