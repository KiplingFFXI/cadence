-- Prints the bar draw calls for a short fill with tall rounded bars, and what ImGui 1.92's PathRect
-- clamp turns each requested rounding into.
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
ImDrawFlags_RoundCornersLeft = 16 + 64;
ImDrawFlags_RoundCornersRight = 32 + 128;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local hud = require('ui.hud');

-- ImGui 1.92 PathRect clamp.
local function clamp(w, h, r, flags)
    flags = (flags == nil or flags == 0) and 240 or flags;
    local top = bit.band(flags, 48) == 48;
    local bottom = bit.band(flags, 192) == 192;
    local left = bit.band(flags, 80) == 80;
    local right = bit.band(flags, 160) == 160;
    r = math.min(r, math.abs(w) * ((top or bottom) and 0.5 or 1.0) - 1);
    r = math.min(r, math.abs(h) * ((left or right) and 0.5 or 1.0) - 1);
    return r;
end

local out = {};
local function shot(label, bar_height, rounding, fill)
    s.resting.bar_height, s.style.rounding = bar_height, rounding;
    hud.refresh(s);
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    hud.begin_frame();
    hud.draw_resting({ fill = fill, left = 5, gained_hp = 0, gained_mp = 0, full = false, flash = 0 });
    hud.end_frame();
    MOCK.record_imgui = false;
    table.insert(out, ('-- %s (bar %d px, rounding %d, fill %.3f)'):format(label, bar_height, rounding, fill));
    local n = 0;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddRectFilled' or c[1] == 'dl:AddRectFilledMultiColor') then
            n = n + 1;
            if (n >= 3) then  -- skip card and stripe
                local w, h = c[3][1] - c[2][1], c[3][2] - c[2][2];
                local r = (c[1] == 'dl:AddRectFilled') and (c[5] or 0) or 0;
                table.insert(out, ('%s x %d..%d w=%d h=%d rounding=%s flags=%s -> imgui radius %.2f'):format(
                    c[1], c[2][1], c[3][1], w, h, tostring(c[5]), tostring(c[6]), r > 0 and clamp(w, h, r, c[6]) or 0));
            end
        end
    end
end

shot('default bar, rounding 6', 5, 6, 0.5);
shot('tall bar, short fill', 16, 12, 0.04);
shot('tall bar, fill just past 2 caps', 16, 12, 0.08);
return table.concat(out, '\n');
