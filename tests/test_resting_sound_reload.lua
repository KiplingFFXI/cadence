-- Loading cadence or zoning while you're resting. Until cadence knows your HP and MP, getting a vitals packet at
-- full isn't "getting full", so the resting sound waits for a real fill.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

local OURS = 'C:\\Ashita\\addons\\cadence\\sounds\\';
local PLAY = 'play cadence_resting_sound from 0';
local ME = 1001;

addon.path = 'C:\\Ashita\\addons\\cadence\\';
MOCK.fs[OURS] = true;
MOCK.fs[OURS .. 'FF VII Save.mp3'] = true;
MOCK.settings_file = { resting = { sound = true } };
MOCK.player.hp_max, MOCK.player.mp_max = 1000, 400;
-- You're already resting at full when cadence loads.
MOCK.player.status = 33;

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');

local function frames(n) for _ = 1, n or 1 do MOCK.frame(1 / 60); end end
local function vitals(hp, mp) MOCK.fire('packet_in', MOCK.vitals_packet(ME, hp, mp, 0)); frames(1); end
local function plays()
    local n = 0;
    for _, command in ipairs(MOCK.mci) do if (command == PLAY) then n = n + 1; end end
    return n;
end

frames(60);
-- A resting tick that only takes TP still sends your HP and MP, both full.
vitals(1000, 400);
frames(30);
vitals(1000, 400);
check('loading while you\'re resting at full plays nothing', plays() == 0, table.concat(MOCK.mci, ' | '));

vitals(800, 400);
vitals(1000, 400);
check('a real fill after that plays once', plays() == 1, table.concat(MOCK.mci, ' | '));

-- Zoning forgets your HP and MP. If your status still reads resting for a moment after, the first vitals
-- packet at full doesn't count as getting full.
vitals(800, 400);
MOCK.fire('packet_in', MOCK.zone_packet(ME));
frames(2);
vitals(1000, 400);
frames(30);
check('the first vitals packet after zoning plays nothing', plays() == 1, table.concat(MOCK.mci, ' | '));

local broke = nil;
for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped', 1, true)) then broke = line; end end
check('nothing breaks', broke == nil, broke);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
