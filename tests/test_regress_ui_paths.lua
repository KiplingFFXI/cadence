-- Settings window paths the integration test doesn't reach. Every greyed out block is closed, Reset
-- look and Reset positions work from the window, and the hover outline shows while Shift is held.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

-- No font files, so the Font list only has Ashita's own.
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.items[16535] = { Delay = 240, Skill = 3 };
MOCK.player.equipment[0] = 16535;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');

local imgui = require('imgui');
local mt = getmetatable(imgui);
local press = {};
local hovered = false;
local old_index = mt.__index;
mt.__index = function (t, name)
    if (name == 'Button' or name == 'SmallButton') then
        return function (label, ...)
            if (MOCK.record_imgui) then table.insert(MOCK.imgui_calls, { name, label }); end
            if (press[label]) then press[label] = nil; return true; end
            return false;
        end;
    end
    if (name == 'IsWindowHovered') then
        return function () return hovered; end;
    end
    return old_index(t, name);
end;

local function frames(n)
    MOCK.imgui_calls = {};
    MOCK.record_imgui = true;
    for _ = 1, n do MOCK.frame(); end
    MOCK.record_imgui = false;
    local c = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        local k = call[1];
        local n_ = 1;
        if (k == 'PopStyleVar' or k == 'PopStyleColor') then n_ = call[2] or 1; end
        c[k] = (c[k] or 0) + n_;
    end
    return c;
end
local function errors() for _, l in ipairs(MOCK.printed) do if (l:find('Drawing stopped')) then return l; end end end

MOCK.now = 5;
MOCK.fire('command', { command = '/cadence' });
local c = frames(3);
-- Every page and each workflow action closes its disabled block.
check('BeginDisabled balanced', (c.BeginDisabled or 0) == (c.EndDisabled or 0) and (c.BeginDisabled or 0) > 0, tostring(c.BeginDisabled) .. '/' .. tostring(c.EndDisabled));

-- Reset look from the window.
local s = MOCK.settings.current;
s.style.scale = 2.0; s.attack.width = 400;
press['Reset look'] = true;
frames(2);
check('reset look ran without error', errors() == nil, errors());
check('reset look restored scale and width', s.style.scale == 1.0 and s.attack.width == 240, s.style.scale .. ' ' .. s.attack.width);

-- Reset positions at scale 2.
s.style.scale = 2.0;
MOCK.settings.callbacks.cadence_settings_update(s);
press['Reset positions'] = true;
frames(2);
check('reset positions ran without error', errors() == nil, errors());
table.insert(out, ('     stacked at scale 2, resting at y %d and auto attack at y %d'):format(s.resting.y, s.attack.y));

-- Hover outline while Shift is held.
MOCK.key_shift = true; hovered = true;
MOCK.player.status = 1;
local outline = 0;
frames(1);
for _, call in ipairs(MOCK.imgui_calls) do if (call[1] == 'dl:AddRect') then outline = outline + 1; end end
check('hover outline drawn inside', outline >= 1, outline);
MOCK.key_shift = false; hovered = false;

check('no drawing errors at all', errors() == nil, errors());
table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
