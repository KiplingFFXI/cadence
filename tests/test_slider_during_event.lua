-- An event that starts while a settings slider is being dragged. The mouse comes up during the event
-- or after it ends, and the new value is saved either way.
-- ImGui reports IsItemDeactivatedAfterEdit only on the frame right after the drag ends, and only
-- to an item that is submitted that frame. The mock below models just that for the Scale slider.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;

local imgui = require('imgui');
local fc = 0;
local holding, active, alive_at, deact_until, last_label = false, false, -10, nil, nil;
rawset(imgui, 'SliderFloat', function (label, number)
    last_label = label;
    if (label ~= 'Scale') then return false; end
    if (holding) then
        active, alive_at = true, fc;
        number[1] = math.min(number[1] + 0.01, 2.5);
        return true;
    end
    if (active) then
        -- Released this frame while the slider was on screen.
        active, deact_until = false, fc;
    end
    return false;
end);
rawset(imgui, 'IsItemDeactivatedAfterEdit', function ()
    if (last_label == 'Scale' and deact_until ~= nil and fc <= deact_until) then
        deact_until = nil;
        return true;
    end
    return false;
end);
local function frame()
    fc = fc + 1;
    -- ImGui's NewFrame drops an active item that wasn't submitted last frame.
    if (active and alive_at < fc - 1) then
        active, deact_until = false, fc + 1;
    end
    MOCK.frame(1 / 60);
end
local function frames(n) for _ = 1, n do frame(); end end

dofile(ADDON_DIR .. '/cadence.lua');
MOCK.watch_settings();
MOCK.fire('load');
local shared_layout = require('core.shared_layout');
local json = require('json');
local FILE = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\shared_layout.json';
local function shared_scale()
    local f = io.open(FILE, 'r'); if (f == nil) then return nil; end
    local data = json.decode(f:read('*a')); f:close();
    return data.settings.style.scale;
end

-- Counts the shared file's writes.
local shared_saves = 0;
local save_shared = shared_layout.save;
shared_layout.save = function ()
    shared_saves = shared_saves + 1;
    return save_shared();
end

MOCK.now = 100;
MOCK.fire('command', { command = '/cadence onelayout on' });
MOCK.fire('command', { command = '/cadence' });
frames(3);

-- First a drag and let go with no event. One save, and the shared file gets the new scale.
local base = shared_saves;
holding = true; frames(20); holding = false; frames(5);
check('with no event, one save after the drag', shared_saves - base == 1, shared_saves - base);
check('with no event, the shared file has the new scale',
    math.abs((shared_scale() or 0) - MOCK.in_use.style.scale) < 1e-6,
    tostring(shared_scale()) .. ' vs ' .. MOCK.in_use.style.scale);

--[[
    An NPC conversation or cutscene starts halfway through a drag. `let_go` runs the frames from when
    the event starts. The new scale has to show, be saved to the shared file and reach the next
    character to log in.
]]
local function drag_through_event(case, let_go)
    local before = MOCK.in_use.style.scale;
    base = shared_saves;
    holding = true; frames(20);
    let_go();
    local after = MOCK.in_use.style.scale;
    check(case .. ', the scale changed on screen', after > before, before .. ' -> ' .. after);
    check(case .. ', the edit was saved', shared_saves - base >= 1, 'saves=' .. (shared_saves - base));
    check(case .. ', the shared file has the new scale', math.abs((shared_scale() or 0) - after) < 1e-6,
        'file=' .. tostring(shared_scale()) .. ' memory=' .. after);

    -- The next character to log in takes the shared file.
    MOCK.settings.switch_character(nil);
    check(case .. ', the scale survives the next login', math.abs(MOCK.in_use.style.scale - after) < 1e-6,
        'after login=' .. MOCK.in_use.style.scale .. ' expected ' .. after);
end

drag_through_event('let go during the event', function ()
    MOCK.in_event = true; frames(10);
    holding = false; frames(30);
    MOCK.in_event = false; frames(300);
end);

drag_through_event('let go after the event', function ()
    MOCK.in_event = true; frames(40);
    MOCK.in_event = false; frames(5);
    holding = false; frames(300);
end);

-- The shared file can't be left for the tests after this one.
os.remove(FILE);
table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
