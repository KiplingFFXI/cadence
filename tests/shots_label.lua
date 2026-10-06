-- Renders the AUTO ATTACK label at three widths, counting down and ready.
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
SHOTS = {};
local settings = MOCK.settings.current;
local hud = require('ui.hud');
local function capture(name, ready)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.draw_attack(ready and 1 or 0.55, ready and 0 or 1.7, 3.78, true);
    hud.end_frame();
    MOCK.record_imgui = false;
    local calls = {};
    for _, c in ipairs(MOCK.imgui_calls) do if (c[1]:sub(1, 3) == 'dl:') then table.insert(calls, c); end end
    SHOTS[name] = { calls = calls, crop = { 760, 650, 1040, 700 } };
end
for _, w in ipairs({ 240, 160, 120 }) do
    settings.attack.width = w;
    hud.refresh(settings);
    capture('w' .. w, false);
    capture('w' .. w .. '_ready', true);
end
return 'ok';
