-- One layout for all characters, with two characters and Ashita's own save rules. Sharing never
-- touches a character's own settings. Turning it off keeps the shared layout on the character who
-- turned it off, and every other character goes back to their own.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;

--[[
    Ashita's settings library the way addons\libs\settings.lua works. Each character has a file.
    Ashita writes the table it handed out to that file on every save and before every character
    switch. Each file holds a copy, like a real save and load would leave it.
]]
local lib = MOCK.settings;
local files, playing = {}, 'Alice';
local function copy(t)
    local result = {};
    for k, v in pairs(t) do result[k] = (type(v) == 'table') and copy(v) or v; end
    return result;
end
-- Fills in what a file is missing with the defaults' own tables, like Ashita's merge.
local function merge(into, from)
    for k, v in pairs(from) do
        if (rawget(into, k) == nil) then into[k] = v;
        elseif (type(v) == 'table') then merge(into[k], v); end
    end
    return into;
end
local function load_file()
    local loaded = merge(copy(files[playing] or lib.defaults), lib.defaults);
    files[playing] = copy(loaded);
    return loaded;
end
function lib.load(defaults)
    lib.defaults = defaults;
    lib.current = load_file();
    return lib.current;
end
function lib.save()
    MOCK.saved = MOCK.saved + 1;
    files[playing] = copy(lib.current);
    return true;
end
local function log_in(name)
    files[playing] = copy(lib.current);
    playing = name;
    lib.current = load_file();
    for _, fn in pairs(lib.callbacks) do fn(lib.current); end
end

files.Alice  = { attack = { x = 1374, y = 600 }, style = { rounding = 2 } };
files.Bob = { attack = { x = 1483, y = 640 }, style = { rounding = 4, scale = 1.25 } };

local json = require('json');
local imgui = require('imgui');
local SHARED = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\shared_layout.json';
os.remove(SHARED);

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.watch_settings();
MOCK.fire('load');
local shared_layout = require('core.shared_layout');
MOCK.now = 100;

-- A character's file or settings, as their auto attack timer's x and their corner roundness.
local function layout(t)
    return t and ('x %d, rounding %d'):format(t.attack.x, t.style.rounding) or 'none';
end
local function shared_file()
    local file = io.open(SHARED, 'r');
    if (file == nil) then return nil; end
    local text = file:read('*a');
    file:close();
    return json.decode(text).settings;
end
local function command(text) MOCK.fire('command', { command = text }); end
local function frames(n) for _ = 1, n do MOCK.frame(1 / 60); end end

-- Ticks or clears a box in the settings window on the next frame.
local function click(label)
    rawset(imgui, 'Checkbox', function (name, flag)
        if (name ~= label) then return false; end
        rawset(imgui, 'Checkbox', nil);
        flag[1] = not flag[1];
        return true;
    end);
    frames(1);
end

local function run()
    check('Alice starts on their own layout', layout(MOCK.in_use) == 'x 1374, rounding 2', layout(MOCK.in_use));
    log_in('Bob');
    check('Bob has their own layout', layout(MOCK.in_use) == 'x 1483, rounding 4', layout(MOCK.in_use));

    log_in('Alice');
    command('/cadence onelayout on');
    check('Alice turns it on and the timers use a copy of their layout', shared_layout.is_on()
        and MOCK.in_use ~= lib.current and layout(MOCK.in_use) == 'x 1374, rounding 2'
        and layout(shared_file()) == 'x 1374, rounding 2', layout(shared_file()));

    -- Every way to change the layout while it's shared changes only the shared copy.
    local own, saves = json.encode(lib.current), MOCK.saved;
    command('/cadence attack tp off');
    command('/cadence preset minimal');
    command('/cadence undo');
    command('/cadence preset minimal');
    command('/cadence');
    MOCK.key_shift, MOCK.mouse_down = true, true;
    MOCK.window_pos['##cadence_attack'] = { 1000, 500 };
    frames(3);
    MOCK.mouse_down = false;
    frames(1);
    MOCK.window_pos['##cadence_attack'], MOCK.key_shift = nil, false;
    click('Lock in place');
    local shared = shared_file();
    check('a command, a preset, Undo, a drag and a box all reach the shared file',
        layout(shared) == 'x 1000, rounding 3' and shared.attack.show_tp == false and shared.style.locked == true,
        layout(shared));
    check('the timers show them', layout(MOCK.in_use) == 'x 1000, rounding 3' and MOCK.in_use.style.locked == true);
    check('Alice\'s own settings stay as they were', json.encode(lib.current) == own and MOCK.saved == saves,
        layout(lib.current) .. ', saves ' .. (MOCK.saved - saves));

    log_in('Bob');
    check('Alice\'s file still has their own layout when they log out', layout(files.Alice) == 'x 1374, rounding 2'
        and files.Alice.attack.show_tp == true and files.Alice.style.locked == false, layout(files.Alice));
    check('Bob logs in to the shared layout', layout(MOCK.in_use) == 'x 1000, rounding 3'
        and MOCK.in_use ~= lib.current, layout(MOCK.in_use));
    check('Bob\'s own settings stay as they were', layout(lib.current) == 'x 1483, rounding 4', layout(lib.current));
    command('/cadence reset');
    check('Reset positions on Bob moves the shared copy', shared_file().attack.x == 780
        and lib.current.attack.x == 1483, shared_file().attack.x);

    log_in('Alice');
    check('Bob\'s file still has their own layout', layout(files.Bob) == 'x 1483, rounding 4', layout(files.Bob));
    check('Alice logs in to the shared layout', layout(MOCK.in_use) == 'x 780, rounding 3', layout(MOCK.in_use));
    click('One layout for all characters');
    check('Alice turns it off in the settings window and the shared file is gone',
        not shared_layout.is_on() and shared_file() == nil);
    check('Alice keeps the layout they see as their own', MOCK.in_use == lib.current
        and layout(lib.current) == 'x 780, rounding 3' and lib.current.style.locked == true, layout(lib.current));
    check('and it\'s in their file', layout(files.Alice) == 'x 780, rounding 3', layout(files.Alice));

    log_in('Bob');
    check('Bob is back on their own layout', MOCK.in_use == lib.current and layout(MOCK.in_use) == 'x 1483, rounding 4'
        and MOCK.in_use.style.scale == 1.25 and MOCK.in_use.attack.show_tp == true, layout(MOCK.in_use));

    -- Turning it on while it's already on keeps what's shared.
    command('/cadence onelayout on');
    command('/cadence preset contrast');
    command('/cadence onelayout on');
    check('on a second time keeps the shared changes', MOCK.in_use.style.rounding == 0
        and shared_file().style.rounding == 0 and lib.current.style.rounding == 4, MOCK.in_use.style.rounding);

    MOCK.fire('unload');
    check('unloading while it\'s shared writes Bob\'s own layout to their file',
        layout(files.Bob) == 'x 1483, rounding 4', layout(files.Bob));
end

-- A crash still takes the shared layout away, so it can't reach the tests after this one.
local ok, err = pcall(run);
os.remove(SHARED);
check('the test ran to the end', ok, err);

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
