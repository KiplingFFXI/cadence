-- Simulates LSB's resting schedule and measures how well core/resting.lua predicts each tick.
--
-- The server side follows LSB's source. Zone ticks run every 0.4 s at a random phase. The 3 s effect
-- grid fires on the first zone tick after E, then E = max(E + 3, tick + 3) when late. Healing starts
-- at S. Tick n runs on the first grid firing where floor((F - S) / 10) > n - 1. Ticks 2 and up
-- restore HP and MP.
-- Server packets only go out when the client sends one, about every 0.405 s, plus 50 ms of latency.

local resting = require('core.resting');

local LATENCY = 0.05;
local CLIENT_PERIOD = 0.405;

local function quantile(list, q)
    table.sort(list);
    if (#list == 0) then return 0; end
    local i = math.max(1, math.min(#list, math.floor(q * #list + 0.5)));
    return list[i];
end

-- Returns the heal tick server times, the status flip server time and the grid firing times.
local function server_schedule(S, zone_phase, grid_start, horizon)
    local firings = {};
    local E = grid_start;
    local t = zone_phase;
    local status_time = nil;
    while (t < horizon) do
        if (status_time == nil and t >= S) then status_time = t; end
        if (t > E) then
            table.insert(firings, t);
            if (E + 3 > t) then E = E + 3; else E = t + 3; end
        end
        t = t + 0.4;
    end
    local heals, count = {}, 0;
    for _, F in ipairs(firings) do
        if (F > S and math.floor((F - S) / 10 + 1e-9) > count) then
            count = count + 1;
            if (count > 1) then table.insert(heals, F); end
        end
    end
    return heals, status_time, firings;
end

local function arrival(server_time, client_phase)
    local k = math.ceil((server_time - client_phase) / CLIENT_PERIOD);
    return client_phase + k * CLIENT_PERIOD + LATENCY;
end

--[[
    scenario = {
        mp_job, signet, tp, full, regen (HP per grid firing), cures (per minute), name
    }
]]
local function run(scenario, trials)
    local err_first, err_second, err_later = {}, {}, {};
    local base_first, base_later = {}, {};
    local false_ticks = 0;

    for trial = 1, trials do
        local S = 100 + math.random() * 10;
        local zone_phase = math.random() * 0.4;
        local grid_start = math.random() * 3;
        local client_phase = math.random() * CLIENT_PERIOD;
        local heals, status_time, firings = server_schedule(S, zone_phase, grid_start, S + 130);

        -- Build the client-side event list.
        local events = {};
        local status_arrives = arrival(status_time, client_phase);
        table.insert(events, { t = status_arrives, kind = 'status' });
        table.insert(events, { t = status_arrives, kind = 'vitals', heal = false, change = 'none' });

        local heal_set = {};
        for i, F in ipairs(heals) do heal_set[F] = i; end
        for _, F in ipairs(firings) do
            if (F > S) then
                local is_heal = heal_set[F] ~= nil;
                local visible;
                if (is_heal) then
                    visible = not (scenario.signet and scenario.full);
                else
                    visible = scenario.regen > 0 and not scenario.full;
                end
                if (visible) then
                    table.insert(events, { t = arrival(F, client_phase), kind = 'vitals', heal = is_heal, tick = heal_set[F], server = F });
                end
            end
        end
        -- Invisible heal ticks still count for error measurement.
        local heal_arrivals = {};
        for i, F in ipairs(heals) do heal_arrivals[i] = arrival(F, client_phase); end

        if (scenario.cures > 0) then
            local t = status_arrives + math.random() * 60 / scenario.cures;
            while (t < S + 125) do
                table.insert(events, { t = t, kind = 'vitals', heal = false, cure = true });
                t = t + math.random() * 120 / scenario.cures;
            end
        end
        table.sort(events, function (a, b) return a.t < b.t; end);

        -- Replay. Vitals move like the server would move them.
        resting.reset();
        local hp, mp, tp = 500, 100, scenario.tp;
        local hp_max = scenario.full and 500 or 5000;
        local mp_max = scenario.mp_job and (scenario.full and 100 or 5000) or 0;
        if (not scenario.mp_job) then mp = 0; end
        resting.on_vitals(status_arrives - 5, hp, mp, tp, hp_max, mp_max);

        local next_event = 1;
        local tick_index = 1;
        local now = status_arrives - 0.01;
        local predicted_at_tick = {};
        local started = false;
        while (now < S + 125) do
            now = now + 1 / 30;
            while (next_event <= #events and events[next_event].t <= now) do
                local ev = events[next_event];
                if (ev.kind == 'status') then
                    resting.start(ev.t);
                    started = true;
                elseif (ev.kind == 'vitals' and started) then
                    if (ev.heal) then
                        local k = ev.tick - 1;
                        hp = math.min(hp_max, hp + 10 + k + (scenario.regen or 0));
                        if (scenario.mp_job) then mp = math.min(mp_max, mp + 12 + k); end
                        if (not scenario.signet) then tp = math.max(0, tp - 100); end
                    elseif (ev.cure) then
                        hp = math.min(hp_max, hp + 150);
                    elseif (ev.change ~= 'none') then
                        hp = math.min(hp_max, hp + (scenario.regen or 0));
                    end
                    local ticks_before = select(3, resting.progress(ev.t)) or 0;
                    resting.on_vitals(ev.t, hp, mp, tp, hp_max, mp_max);
                    local ticks_after = select(3, resting.progress(ev.t)) or 0;
                    if (ticks_after > ticks_before) then
                        if (not ev.heal) then false_ticks = false_ticks + 1; end
                    end
                end
                next_event = next_event + 1;
            end
            if (started) then
                resting.update(now);
                -- Record the prediction the player sees just before each real tick arrives.
                local target = heal_arrivals[tick_index];
                if (target ~= nil and now >= target - 1 / 30 and predicted_at_tick[tick_index] == nil) then
                    local _, left = resting.progress(now);
                    predicted_at_tick[tick_index] = now + left;
                    tick_index = tick_index + 1;
                end
            end
        end

        for i, predicted in pairs(predicted_at_tick) do
            local e = math.abs(predicted - heal_arrivals[i]);
            if (i == 1) then table.insert(err_first, e);
            elseif (i == 2) then table.insert(err_second, e);
            else table.insert(err_later, e); end
        end
        -- For comparison, the hticks addon puts the first tick 21 s after the status change, then one
        -- every 10 s.
        for i, a in ipairs(heal_arrivals) do
            local guess = status_arrives + 21 + 10 * (i - 1);
            if (i == 1) then table.insert(base_first, math.abs(guess - a)); else table.insert(base_later, math.abs(guess - a)); end
        end
    end

    return ('%-34s first p50 %.2f p90 %.2f | second p50 %.2f p90 %.2f | later p50 %.2f p90 %.2f max %.2f | false %d | hticks first p90 %.2f later p90 %.2f max %.2f'):format(
        scenario.name,
        quantile(err_first, 0.5), quantile(err_first, 0.9),
        quantile(err_second, 0.5), quantile(err_second, 0.9),
        quantile(err_later, 0.5), quantile(err_later, 0.9), quantile(err_later, 1.0),
        false_ticks,
        quantile(base_first, 0.9), quantile(base_later, 0.9), quantile(base_later, 1.0));
end

math.randomseed(12345);
local scenarios = {
    { name = 'BLM, MP not full',          mp_job = true,  signet = false, tp = 0,   full = false, regen = 0, cures = 0 },
    { name = 'WAR, no Signet, TP 0',      mp_job = false, signet = false, tp = 0,   full = false, regen = 0, cures = 0 },
    { name = 'WAR, no Signet, TP 300',    mp_job = false, signet = false, tp = 300, full = false, regen = 0, cures = 0 },
    { name = 'WAR, Signet',               mp_job = false, signet = true,  tp = 0,   full = false, regen = 0, cures = 0 },
    { name = 'full HP/MP, no Signet',     mp_job = true,  signet = false, tp = 0,   full = true,  regen = 0, cures = 0 },
    { name = 'full HP/MP, Signet',        mp_job = true,  signet = true,  tp = 0,   full = true,  regen = 0, cures = 0 },
    { name = 'WHM regen 1, MP not full',  mp_job = true,  signet = true,  tp = 0,   full = false, regen = 1, cures = 0 },
    { name = 'WAR Signet, Regen 5',       mp_job = false, signet = true,  tp = 0,   full = false, regen = 5, cures = 0 },
    { name = 'WAR Signet, cures 3/min',   mp_job = false, signet = true,  tp = 0,   full = false, regen = 0, cures = 3 },
    { name = 'BLM, cures 3/min',          mp_job = true,  signet = true,  tp = 0,   full = false, regen = 0, cures = 3 },
};
local lines = {};
for _, s in ipairs(scenarios) do
    table.insert(lines, run(s, 400));
end
return table.concat(lines, '\n');
