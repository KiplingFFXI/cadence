-- Renders every preset with both timers, plus rounded corners and the almost ready state.
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
SHOTS = {};

local settings = MOCK.settings.current;
local hud = require('ui.hud');
local presets = require('ui.presets');

local function dl_only()
    local out = {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1]:sub(1, 3) == 'dl:') then table.insert(out, c); end
    end
    return out;
end
local function capture(name, now)
    MOCK.now = now;
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    MOCK.frame(0);
    MOCK.record_imgui = false;
    SHOTS[name] = { calls = dl_only(), crop = { 740, 590, 1080, 720 } };
end

MOCK.fire('command', { command = '/cadence' });
for _, name in ipairs(presets.NAMES) do
    presets.apply(settings, name);
    hud.refresh(settings);
    capture(name:gsub(' ', '_'), 1.9);
end

presets.apply(settings, 'Phoenix');
settings.style.rounding = 6;
hud.refresh(settings);
capture('Phoenix_rounded', 1.9);
capture('Phoenix_almost', 3.5);
capture('Phoenix_flash', 10.05);
return 'ok';
