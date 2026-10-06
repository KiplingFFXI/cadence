-- Renders the enemy attack timer on its own and attached under the auto attack timer, in a few looks.
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

local function capture(name)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.join_below(settings.enemy.attached);
    hud.draw_attack(0.55, 1.7, 3.78, true);
    hud.draw_enemy(enemy_view);
    hud.end_frame();
    MOCK.record_imgui = false;
    local calls = {};
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1]:sub(1, 3) == 'dl:') then table.insert(calls, c); end end
    SHOTS[name] = { calls = calls, crop = { 760, 650, 1060, 760 } };
end

settings.enemy.enabled = true;
for _, look in ipairs({ 'Phoenix', 'Classic FFXI', 'Minimal' }) do
    presets.apply(settings, look);
    for _, attached in ipairs({ false, true }) do
        settings.enemy.attached = attached;
        hud.refresh(settings);
        capture(look:gsub(' ', '_') .. (attached and '_attached' or '_own'));
    end
end

presets.apply(settings, 'Phoenix');
settings.style.rounding = 6;
settings.enemy.attached = true;
hud.refresh(settings);
capture('Phoenix_rounded_attached');

settings.style.rounding = 0;
enemy_view.left, enemy_view.fill = 0, 1;
capture('Phoenix_attached_ready');
enemy_view.waiting = true;
capture('Phoenix_attached_waiting');
-- On you, on its own and attached.
settings.enemy.enabled = true;
enemy_view.on_you, enemy_view.waiting = true, false;
enemy_view.left, enemy_view.fill = 2.6, 0.35;
for _, attached in ipairs({ false, true }) do
    settings.enemy.attached = attached;
    hud.refresh(settings);
    capture('on_you_' .. (attached and 'attached' or 'own'));
end
enemy_view.on_you = false;
settings.enemy.attached = false;
hud.refresh(settings);
return 'ok';
