-- Renders the Colorblind safe look in each state that has to look different. That's filling, almost
-- ready with its mark, ready, resting full, and the enemy strip on you.
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
SHOTS = {};

local settings = MOCK.settings.current;
local hud = require('ui.hud');
require('ui.presets').apply(settings, 'Colorblind safe');
settings.attack.almost_mark = true;
settings.enemy.enabled, settings.enemy.attached = true, true;
hud.refresh(settings);

local tp_view = { tp = 640, goal = 1000, rounds = 3 };
local enemy_view = { fill = 0.35, left = 2.6, delay = 4.42, learned = true, waiting = false, name = 'Young Quadav' };

local function capture(name, fill, left, on_you, tp)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.join_below(true);
    hud.draw_attack(fill, left, 3.78, true, tp or tp_view);
    enemy_view.on_you = on_you;
    hud.draw_enemy(enemy_view);
    hud.end_frame();
    MOCK.record_imgui = false;
    local calls = {};
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1]:sub(1, 3) == 'dl:') then table.insert(calls, c); end end
    SHOTS[name] = { calls = calls, crop = { 760, 650, 1060, 760 } };
end

capture('cb_filling', 0.5, 1.9, false);
capture('cb_almost', 0.9, 0.3, false);
capture('cb_ready_on_you', 1, 0, true, { tp = 1040, goal = 1000, rounds = nil });

settings.enemy.enabled = false;
hud.refresh(settings);
MOCK.imgui_calls = {};
MOCK.record_imgui = true;
hud.begin_frame();
hud.draw_resting({ fill = 0.6, left = 4, gained_hp = 24, gained_mp = 31, full = true, until_full = nil, flash = 0 });
hud.end_frame();
MOCK.record_imgui = false;
local calls = {};
for _, c in ipairs(MOCK.imgui_calls) do if (c[1]:sub(1, 3) == 'dl:') then table.insert(calls, c); end end
SHOTS['cb_resting_full'] = { calls = calls, crop = { 760, 600, 1060, 700 } };
