-- Repeated timer queries keep their results separate without rebuilding private scratch tables.
local out, failed = {}, 0;
local function check(name, yes, detail)
    out[#out + 1] = (yes and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. detail) or '');
    if (not yes) then failed = failed + 1; end
end
if (jit) then jit.off(); end
local function bytes_per_call(draw)
    for _ = 1, 20 do draw(); end
    collectgarbage('collect'); collectgarbage('stop');
    local before = collectgarbage('count');
    for _ = 1, 1 do draw(); end
    before = collectgarbage('count');
    for _ = 1, 500 do draw(); end
    local made = (collectgarbage('count') - before) * 1024 / 500;
    collectgarbage('restart');
    return made;
end
local resting, tp = require('core.resting'), require('core.tp');
local function sit(model, hp, mp, maximum_hp, maximum_mp)
    resting.reset(); resting.on_buffs(0, {});
    resting.on_vitals(0, hp or 100, mp or 20, 0, maximum_hp or 1800, maximum_mp or 800);
    resting.on_model(model); resting.start(0);
end
local model = { resting_key = 'performance', hp_base = 30, hp_step = 4, mp_base = 28, mp_step = 3,
    hp_known = true, mp_known = true, regen = 2, refresh = 3, regen_known = true, refresh_known = true };
sit(model);
local hp, mp, _, meta = resting.until_each_full(10);
local full, hp_ticks, mp_ticks = meta.full_in, meta.hp_ticks, meta.mp_ticks;
local goal = resting.goal_progress(10, 'hp', 'percent', 60);
local hp_again, mp_again, _, another = resting.until_each_full(10);
check('different recovery queries cannot change earlier metadata', meta ~= another and meta.full_in == full
    and meta.hp_ticks == hp_ticks and meta.mp_ticks == mp_ticks and goal.seconds < full);
check('a goal query leaves the next full simulation unchanged', hp_again == hp and mp_again == mp
    and another.full_in == full and another.ticks == meta.ticks);
local made = bytes_per_call(function () resting.until_each_full(10); end);
check('full recovery queries allocate only their returned metadata', made < 400, ('%.1f bytes/call'):format(made));
made = bytes_per_call(function () resting.goal_progress(10, 'both', 'percent', 80); end);
check('goal queries keep bounded result allocation', made < 800, ('%.1f bytes/call'):format(made));
made = bytes_per_call(function () tp.time_to(1000, 100, 10, nil); end);
check('unavailable TP times allocate no per-query helper', made < 8, ('%.1f bytes/call'):format(made));
sit({ resting_key = 'partial', hp_base = 30, hp_step = 4, hp_known = true });
local known_hp, unknown_mp, _, partial = resting.until_each_full(10);
check('an unknown stat cannot reuse a previous query rate or full time', known_hp ~= nil and unknown_mp == nil
    and partial.mp_ticks == nil and partial.mp_confidence == 'unknown' and partial.full_in == nil);
resting.on_buffs(10, { [8] = true });
local blocked_hp, blocked_mp, _, blocked = resting.until_each_full(10);
check('blocked queries cannot retain previous full times', blocked_hp == nil and blocked_mp == nil
    and blocked.full_in == nil and blocked.confidence == 'blocked');
sit(model, 1800, 800);
local full_hp, full_mp, _, already = resting.until_each_full(10);
check('full vitals clear earlier unknown and blocked results', full_hp == 0 and full_mp == 0
    and already.full_in == 0 and already.ticks == 0 and already.confidence == 'known');

local modifiers = require('core.modifiers');
local inputs = { main_job = 1, main_level = 75, sub_job = 13, sub_level = 37,
    equipment = {}, buffs = {}, merits = {}, max_hp = 1000, max_mp = 0, region = 0 };
made = bytes_per_call(function () modifiers.calculate(inputs); end);
check('modifier rebuilds reuse fixed effect routes', made < 12000, ('%.1f bytes/call'):format(made));

-- Stable client objects keep allocation in the observer separate from the test mock.
local lookup_fails, method_fails = false, false;
local stats = setmetatable({
    GetHPMax = function () if (method_fails) then error('unavailable'); end return 1000; end,
    GetMPMax = function () return 100; end,
}, { __index = function (_, key)
    if (key == 'GetNation') then
        if (lookup_fails) then error('unavailable'); end
        return nil;
    end
end });
local item = { Index = 0 };
local group = {
    GetMemberIsActive = function (_, index) return index == 0; end,
    GetMemberServerId = function (_, index) return index == 0 and 1001 or 0; end,
    GetMemberZone = function () return 100; end,
    GetMemberMainJob = function () return 1; end,
    GetMemberHP = function () return 500; end,
    GetMemberMP = function () return 50; end,
    GetMemberTP = function () return 0; end,
    GetMemberHPPercent = function () return 50; end,
};
local inventory = { GetEquippedItem = function () return item; end };
local manager = { GetPlayer = function () return stats; end, GetParty = function () return group; end,
    GetInventory = function () return inventory; end };
AshitaCore.GetMemoryManager = function () return manager; end;
local observer = require('core.stat_state');
local loadout = { main_job = 1, main_level = 75, sub_job = 13, sub_level = 37,
    buffs = {}, buffs_known = true, engaged = false, resting = false };
local now, original = 0, observer.update(0, loadout);
made = bytes_per_call(function () now = now + 0.21; observer.update(now, loadout); end);
check('steady stat polls avoid per-method protected-read closures', made < 1500, ('%.1f bytes/call'):format(made));
check('steady polling still reuses unchanged arithmetic', observer.info() == original);
lookup_fails, method_fails = true, true;
local safe = pcall(observer.update, now + 1, loadout, true);
local snapshot = observer.snapshot();
check('unavailable member lookups and methods stay safely unknown', safe and snapshot.nation == nil
    and snapshot.max_hp == nil);
method_fails = false;
safe = pcall(observer.update, now + 2, loadout, true);
check('a recovered method is read again without replacing the client object', safe and observer.snapshot().max_hp == 1000);
check('the core checks send no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
