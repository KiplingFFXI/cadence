-- Loading cadence with the resting sound already on. Its file opens on load, and one that won't open says
-- nothing in chat until you turn the sound on again, pick it or press Play.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

local FOLDER = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\sounds\\';
local OURS = 'C:\\Ashita\\addons\\cadence\\sounds\\';
local OPEN = 'open "' .. FOLDER .. 'bell.mp3" type mpegvideo alias cadence_resting_sound';
local PROBLEM = 'bell.mp3 won\'t play. Check that it\'s a working .mp3 or .wav file, or pick another one.';

addon.path = 'C:\\Ashita\\addons\\cadence\\';
MOCK.fs[OURS] = true;
MOCK.settings_file = { resting = { sound = true, sound_file = 'bell.mp3' } };
MOCK.mci_code = function (command) return command:find('^open') and 263 or 0; end

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');

local function opens()
    local n = 0;
    for _, command in ipairs(MOCK.mci) do if (command == OPEN) then n = n + 1; end end
    return n;
end
local function told()
    local n = 0;
    for _, line in ipairs(MOCK.printed) do if (line:find(PROBLEM, 1, true)) then n = n + 1; end end
    return n;
end

check('loading with the sound on tries its file once', opens() == 1, table.concat(MOCK.mci, ' | '));
check('and says nothing in chat when it won\'t open', told() == 0, table.concat(MOCK.printed, ' / '));
for _ = 1, 60 do MOCK.frame(1 / 60); end
MOCK.fire('command', { command = '/cadence resting width 300' });
check('frames and other changes don\'t try it again', opens() == 1 and told() == 0);
MOCK.fire('command', { command = '/cadence resting sound off' });
MOCK.fire('command', { command = '/cadence resting sound on' });
check('turning the sound off and on tries it again, and chat says so once', opens() == 2 and told() == 1,
    table.concat(MOCK.printed, ' / '));

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
