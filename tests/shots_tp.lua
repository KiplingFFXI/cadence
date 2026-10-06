-- Renders the TP line under the auto attack timer in each look, below and at 1000, narrow, and with
-- the enemy strip attached under it.
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

local enemy_view = { fill = 0.35, left = 2.6, delay = 4.42, learned = true, waiting = false, name = 'Young Quadav' };

local function capture(name, tp_view, with_enemy)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.join_below(with_enemy and settings.enemy.attached);
    hud.draw_attack(0.55, 1.7, 3.78, true, tp_view);
    if (with_enemy) then
        hud.draw_enemy(enemy_view);
    end
    hud.end_frame();
    MOCK.record_imgui = false;
    local calls = {};
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1]:sub(1, 3) == 'dl:') then table.insert(calls, c); end end
    SHOTS[name] = { calls = calls, crop = { 760, 650, 1060, 790 } };
end

local building = { tp = 640, goal = 1000, rounds = 3 };
local ready = { tp = 1240, goal = 1000, rounds = nil };

for _, look in ipairs(presets.NAMES) do
    presets.apply(settings, look);
    hud.refresh(settings);
    local name = look:gsub(' ', '_');
    capture(name .. '_building', building);
    capture(name .. '_ready', ready);
end

presets.apply(settings, 'Phoenix');
settings.enemy.enabled, settings.enemy.attached = true, true;
hud.refresh(settings);
capture('Phoenix_attached', building, true);
settings.enemy.enabled, settings.enemy.attached = false, false;

settings.attack.width = 120;
hud.refresh(settings);
capture('Phoenix_narrow', building);
settings.attack.width = 240;
hud.refresh(settings);
