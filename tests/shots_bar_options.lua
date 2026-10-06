-- Renders filling and draining bars with the ready mark, numbers only, a custom label, the resting
-- line with HP and MP full times, and the resize grip while Shift is held.
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
SHOTS = {};

local settings = MOCK.settings.current;
local hud = require('ui.hud');
local imgui = require('imgui');
local tp_view = { tp = 640, goal = 1000, rounds = 3 };
local resting_view = { fill = 0.4, left = 5.4, gained_hp = 24, gained_mp = 31, full = false, until_full = 95, flash = 0,
    hp_full_in = 25, mp_full_in = 95, has_mp = true };

local function capture(name, draw)
    hud.refresh(settings);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    draw();
    hud.end_frame();
    MOCK.record_imgui = false;
    local calls = {};
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1]:sub(1, 3) == 'dl:') then table.insert(calls, c); end end
    SHOTS[name] = { calls = calls, crop = { 760, 600, 1060, 730 } };
end
local function attack(fill, left)
    return function () hud.draw_attack(fill, left, 3.78, true, tp_view); end;
end

settings.attack.almost_mark = true;
capture('bars_fill_mark', attack(0.55, 1.7));
settings.style.bar_drains = true;
capture('bars_drain_mark', attack(0.55, 1.7));
capture('bars_drain_ready', attack(1, 0));
settings.style.bar_drains = false;
settings.attack.almost_mark = false;

settings.attack.numbers_only = true;
capture('bars_numbers_only', attack(0.55, 1.7));
settings.attack.numbers_only = false;

settings.attack.label_text = 'AA';
settings.attack.bar_height = 12;
capture('bars_custom_label_thick', attack(0.55, 1.7));
settings.attack.label_text = '';
settings.attack.bar_height = 5;

settings.resting.show_each_full = true;
capture('bars_resting_full_times', function () hud.draw_resting(resting_view); end);
settings.resting.width = 150;
capture('bars_resting_full_times_narrow', function () hud.draw_resting(resting_view); end);
settings.resting.width = 240;
settings.resting.show_each_full = false;

settings.style.label_size = 20;
capture('bars_label_size_20', attack(0.55, 1.7));
settings.resting.show_each_full = true;
capture('bars_label_size_20_resting', function () hud.draw_resting(resting_view); end);
settings.resting.show_each_full = false;
settings.style.label_size = 0;

local presets = require('ui.presets');
presets.apply(settings, 'Minimal');
capture('bars_minimal_shadow', attack(0.55, 1.7));
settings.style.text_outline = true;
capture('bars_minimal_outline', attack(0.55, 1.7));
presets.reset(settings);
settings.style.detail_size = 16;
capture('bars_detail_size_16', attack(0.55, 1.7));
settings.style.detail_size = 0;

hud.set_movable(true);
rawset(imgui, 'IsWindowHovered', function () return true; end);
capture('bars_resize_grip', attack(0.55, 1.7));
rawset(imgui, 'IsWindowHovered', nil);
hud.set_movable(false);
