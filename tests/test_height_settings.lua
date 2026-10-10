-- Timer height has its own saved value; older files keep their original size.
local out, fails = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then fails = fails + 1; end
end
local folder = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\';
os.remove(folder .. 'profiles.json');
os.remove(folder .. 'shared_layout.json');
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.watch_settings();
MOCK.fire('load');
local defaults, history = require('ui.defaults'), require('ui.history');
local profiles, presets = require('ui.profiles'), require('ui.presets');
local shared, layouts = require('core.shared_layout'), require('ui.layouts');
local json = require('json');
local s = MOCK.in_use;
local names = { 'attack', 'resting', 'enemy' };
local function command(words) MOCK.fire('command', { command = '/cadence ' .. words }); end
local function heights(settings, a, r, e)
    return settings.attack.height_scale == a and settings.resting.height_scale == r
        and settings.enemy.height_scale == e;
end
check('new and older character settings keep the original height', heights(s, 1, 1, 1));
for _, name in ipairs(names) do
    local width, bar = s[name].width, s[name].bar_height;
    command(name .. ' height 1.37');
    check(name .. ' height command keeps width and bar thickness', s[name].height_scale == 1.37
        and s[name].width == width and s[name].bar_height == bar);
    command('undo');
    check(name .. ' height command has one Undo', s[name].height_scale == 1 and history.status(s) == nil);
end

local old = defaults.make();
old.attack.height_scale, old.resting.height_scale, old.enemy.height_scale = nil, nil, nil;
defaults.tidy(old);
check('missing values in old layouts become 1', heights(old, 1, 1, 1));
old.attack.height_scale, old.resting.height_scale, old.enemy.height_scale = 0.1, 9, '2';
defaults.tidy(old);
check('hand-edited heights clamp to the range and reject strings', heights(old, 0.5, 2.5, 1));
old.attack.height_scale, old.resting.height_scale, old.enemy.height_scale = 0 / 0, math.huge, -math.huge;
defaults.tidy(old);
check('non-finite heights have safe values', heights(old, 1, 2.5, 0.5));

command('attack height 1.25'); command('resting height 1.5'); command('enemy height 0.75');
profiles.refresh();
check('saving a profile includes each timer height', profiles.save(s, 'Tall'));
local file = assert(io.open(folder .. 'profiles.json', 'r'));
local saved = json.decode(file:read('*a')); file:close();
check('profile file contains independent heights', heights(saved.Tall, 1.25, 1.5, 0.75));
s.attack.height_scale = 2; profiles.invalidate_status(s);
check('height edits mark the saved profile modified', profiles.status(s).modified);
check('loading a profile restores all heights', profiles.load(s, 'Tall') and heights(s, 1.25, 1.5, 0.75));
saved.Legacy = { attack = { width = 310 }, resting = {}, enemy = {} };
file = assert(io.open(folder .. 'profiles.json', 'w')); file:write(json.encode(saved)); file:close();
s.attack.height_scale, s.resting.height_scale, s.enemy.height_scale = 2, 2, 2;
check('loading an older profile replaces current heights with 1', profiles.load(s, 'Legacy') and heights(s, 1, 1, 1));
profiles.load(s, 'Tall');

presets.apply(s, 'Mint');
check('a color preset preserves timer heights', heights(s, 1.25, 1.5, 0.75));
layouts.apply(s, 'resting');
check('a starter layout preserves timer heights', heights(s, 1.25, 1.5, 0.75));
history.reset_section(s, 'appearance');
check('Appearance reset restores original timer heights', heights(s, 1, 1, 1));
history.undo(s);
check('Undo restores heights after Appearance reset', heights(s, 1.25, 1.5, 0.75));
presets.reset(s);
check('Reset look restores original timer heights', heights(s, 1, 1, 1));
presets.undo(s);
check('Reset look Undo restores independent heights', heights(s, 1.25, 1.5, 0.75));
history.reset_section(s, 'attack');
check('a timer reset leaves other timer heights alone', heights(s, 1, 1.5, 0.75));
history.undo(s);
check('Undo restores a timer height reset', heights(s, 1.25, 1.5, 0.75));

local active = shared.turn_on(s);
check('sharing begins with all timer heights', active and heights(active, 1.25, 1.5, 0.75));
active.resting.height_scale = 1.75;
check('shared height edits save', shared.save());
local other = defaults.make();
active = shared.apply(other);
check('another character loads the shared heights', active ~= other and heights(active, 1.25, 1.75, 0.75)
    and heights(other, 1, 1, 1));
check('turning sharing off keeps the displayed heights', shared.turn_off(other) == other and heights(other, 1.25, 1.75, 0.75));
os.remove(folder .. 'profiles.json'); profiles.refresh();
out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
