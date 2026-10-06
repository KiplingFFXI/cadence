--[[
    Every preset stays readable for colorblind players. Each color change a player has to notice is
    looked at the way protanopia, deuteranopia and tritanopia see it (Machado, Oliveira and Fernandes
    2009, full strength), and the two colors have to stay at least 12 apart by CIEDE2000. About 10
    reads as clearly different on a thin bar, so 12 leaves a little room.
]]
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local presets = require('ui.presets');

local CLOSEST = 12;

-- How each kind of colorblindness changes a color, as a matrix on linear RGB.
local MATRICES = {
    protanopia   = { { 0.152286, 1.052583, -0.204868 }, { 0.114503, 0.786281, 0.099216 }, { -0.003882, -0.048116, 1.051998 } },
    deuteranopia = { { 0.367322, 0.860646, -0.227968 }, { 0.280085, 0.672501, 0.047413 }, { -0.011820, 0.042940, 0.968881 } },
    tritanopia   = { { 1.255528, -0.076749, -0.178779 }, { -0.078411, 0.930809, 0.147602 }, { 0.004733, 0.691367, 0.303900 } },
};

-- A dark grey stands in for the game behind the timers.
local SCENE = { 64 / 255, 64 / 255, 64 / 255, 1 };

local function to_linear(c)
    if (c <= 0.04045) then
        return c / 12.92;
    end
    return ((c + 0.055) / 1.055) ^ 2.4;
end

-- A see-through color over what's behind it.
local function over(color, under)
    local a = color[4];
    return { color[1] * a + under[1] * (1 - a), color[2] * a + under[2] * (1 - a), color[3] * a + under[3] * (1 - a), 1 };
end

-- The bar's gradient part way along, the way the timers draw it.
local function blend(from, to, t)
    return { from[1] + (to[1] - from[1]) * t, from[2] + (to[2] - from[2]) * t, from[3] + (to[3] - from[3]) * t, 1 };
end

-- The color as someone with that kind of colorblindness sees it, as CIELAB.
local function seen(color, m)
    local r, g, b = to_linear(color[1]), to_linear(color[2]), to_linear(color[3]);
    local function clamp(v) return math.min(math.max(v, 0), 1); end
    r, g, b = clamp(m[1][1] * r + m[1][2] * g + m[1][3] * b), clamp(m[2][1] * r + m[2][2] * g + m[2][3] * b),
        clamp(m[3][1] * r + m[3][2] * g + m[3][3] * b);

    local function f(t)
        if (t > 0.008856) then
            return t ^ (1 / 3);
        end
        return 7.787 * t + 16 / 116;
    end
    local fx = f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047);
    local fy = f(0.2126 * r + 0.7152 * g + 0.0722 * b);
    local fz = f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883);
    return { 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz) };
end

-- CIEDE2000, how different two CIELAB colors look.
local function ciede2000(one, two)
    local rad = math.rad;
    local L1, a1, b1 = one[1], one[2], one[3];
    local L2, a2, b2 = two[1], two[2], two[3];
    local C7 = ((math.sqrt(a1 * a1 + b1 * b1) + math.sqrt(a2 * a2 + b2 * b2)) / 2) ^ 7;
    local G = 0.5 * (1 - math.sqrt(C7 / (C7 + 25 ^ 7)));
    local a1p, a2p = (1 + G) * a1, (1 + G) * a2;
    local C1p, C2p = math.sqrt(a1p * a1p + b1 * b1), math.sqrt(a2p * a2p + b2 * b2);
    local h1p = math.deg(math.atan2(b1, a1p)) % 360;
    local h2p = math.deg(math.atan2(b2, a2p)) % 360;

    local dhp = 0;
    if (C1p * C2p ~= 0) then
        dhp = h2p - h1p;
        if (dhp > 180) then
            dhp = dhp - 360;
        elseif (dhp < -180) then
            dhp = dhp + 360;
        end
    end
    local dLp, dCp = L2 - L1, C2p - C1p;
    local dHp = 2 * math.sqrt(C1p * C2p) * math.sin(rad(dhp / 2));

    local Lbp, Cbp = (L1 + L2) / 2, (C1p + C2p) / 2;
    local hbp = h1p + h2p;
    if (C1p * C2p ~= 0) then
        if (math.abs(h1p - h2p) <= 180) then
            hbp = (h1p + h2p) / 2;
        elseif (h1p + h2p < 360) then
            hbp = (h1p + h2p + 360) / 2;
        else
            hbp = (h1p + h2p - 360) / 2;
        end
    end
    local T = 1 - 0.17 * math.cos(rad(hbp - 30)) + 0.24 * math.cos(rad(2 * hbp))
        + 0.32 * math.cos(rad(3 * hbp + 6)) - 0.20 * math.cos(rad(4 * hbp - 63));
    local dtheta = 30 * math.exp(-((hbp - 275) / 25) ^ 2);
    local Cbp7 = Cbp ^ 7;
    local Rt = -math.sin(rad(2 * dtheta)) * 2 * math.sqrt(Cbp7 / (Cbp7 + 25 ^ 7));
    local l = dLp / (1 + 0.015 * (Lbp - 50) ^ 2 / math.sqrt(20 + (Lbp - 50) ^ 2));
    local c = dCp / (1 + 0.045 * Cbp);
    local h = dHp / (1 + 0.015 * Cbp * T);
    return math.sqrt(l * l + c * c + h * h + Rt * c * h);
end

-- How close two colors get for the kind of colorblindness that sees them closest, and which kind.
local function closest(one, two)
    local best, kind = math.huge, nil;
    for name, m in pairs(MATRICES) do
        local d = ciede2000(seen(one, m), seen(two, m));
        if (d < best) then
            best, kind = d, name;
        end
    end
    return best, kind;
end

local function hex(v) return { tonumber(v:sub(1, 2), 16) / 255, tonumber(v:sub(3, 4), 16) / 255, tonumber(v:sub(5, 6), 16) / 255, 1 }; end

-- A salmon bar and a green "full" that protanopia sees as close. The math has to give the known answer.
local d, kind = closest(hex('ff8d79'), hex('63ba8a'));
check('the math matches the reference check', math.abs(d - 4.7975) < 0.001 and kind == 'protanopia', d .. ' ' .. kind);

-- Every change a player has to notice, as the two colors before and after.
local function changes(look)
    local attack, resting, enemy, style = look.attack, look.resting, look.enemy, look.style;
    local card = style.panel and over(style.panel_color, SCENE) or SCENE;
    local track, label = over(style.track_color, card), over(style.label_color, card);
    -- With the default 0.5 s, almost ready starts with the bar about 87% full on a 3.8 s delay.
    local attack_near = blend(attack.fill_start, attack.fill_end, 0.87);
    local enemy_near = blend(enemy.fill_start, enemy.fill_end, 0.87);
    local list = {
        { 'the bar turning almost ready', attack_near, attack.almost_color },
        { 'almost ready turning ready', attack.almost_color, attack.ready_color },
        { 'the bar turning ready with almost ready off', attack.fill_end, attack.ready_color },
        { 'the seconds turning almost ready', style.value_color, attack.almost_color },
        { 'the almost ready mark on the track', attack.almost_color, track },
        { 'the bar on its track', attack.fill_start, track },
        { 'TP turning its 1000 color', style.value_color, attack.tp_color },
        { 'the enemy bar turning almost ready', enemy_near, enemy.almost_color },
        { 'the enemy turning ready', enemy.almost_color, enemy.ready_color },
        { 'the enemy bar turning ready with almost ready off', enemy.fill_end, enemy.ready_color },
        { 'the seconds turning TP move or casting', style.value_color, enemy.almost_color },
        { 'the enemy bar on its track', enemy.fill_start, track },
        { 'the enemy label turning on you', label, enemy.on_you_color },
    };
    if (style.accent) then
        table.insert(list, { 'the enemy stripe turning on you', over(style.accent_color, card), enemy.on_you_color });
    end
    -- A resting bar can turn full anywhere along its fill.
    for step = 0, 10 do
        table.insert(list, { ('the resting bar turning full at %d%%'):format(step * 10),
            blend(resting.fill_start, resting.fill_end, step / 10), resting.full_color });
    end
    return list;
end

for _, name in ipairs(presets.NAMES) do
    presets.apply(s, name);
    local worst, what, how = math.huge, nil, nil;
    for _, change in ipairs(changes(s)) do
        local d, kind = closest(change[2], change[3]);
        if (d < worst) then
            worst, what, how = d, change[1], kind;
        end
    end
    check(name .. ' stays clear for colorblind players', worst >= CLOSEST,
        ('%s is only %.1f apart with %s'):format(what, worst, how));
end

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
