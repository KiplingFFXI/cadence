-- Shared spot with ImGuiCond_Appearing modelled like real ImGui. A window that was Begin()'d last
-- frame ignores an Appearing position.
local out = {};
local function log(s) table.insert(out, s); end

ImGuiCond_Appearing = 777;
MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;

local imgui = require('imgui');
local win, stack, pending, frame_no, drag = {}, {}, nil, 0, {};
imgui.SetNextWindowPos = function (pos, cond) pending = { pos[1], pos[2], cond }; end
imgui.Begin = function (name)
    local w = win[name] or { x = 0, y = 0, last = -10 };
    win[name] = w;
    local appearing = w.last < frame_no - 1;
    if (pending) then
        local c = pending[3];
        if (c == ImGuiCond_Always or (c == ImGuiCond_Appearing and appearing)) then
            w.x, w.y = pending[1], pending[2];
        end
        pending = nil;
    end
    if (drag[name]) then w.x, w.y = drag[name][1], drag[name][2]; end
    w.last = frame_no;
    table.insert(stack, name);
    return true;
end
imgui.End = function () table.remove(stack); end
imgui.GetWindowPos = function () local w = win[stack[#stack]]; return w.x, w.y; end

local function frames(n)
    for _ = 1, n do frame_no = frame_no + 1; MOCK.frame(); end
end

dofile(ADDON_DIR .. '/cadence.lua');
local s = MOCK.settings.current;
s.style.shared_spot = true;
MOCK.fire('load');
MOCK.now = 100;

-- Resting, settings window closed.
MOCK.player.status = 33;
frames(5);
log(('resting: resting window at %d,%d'):format(win['##cadence_resting'].x, win['##cadence_resting'].y));

-- Open the settings window while resting.
MOCK.fire('command', { command = '/cadence' });
frames(5);
local rw, sw = win['##cadence_resting'], win['##cadence_attack'];
log(('settings open while resting: resting drawn=%s at %d,%d  auto attack drawn=%s'):format(
    tostring(rw.last == frame_no), rw.x, rw.y, tostring(sw ~= nil and sw.last == frame_no)));
assert(rw.last == frame_no, 'live resting timer should show');
assert(sw == nil or sw.last ~= frame_no, 'the auto attack sample should not sit on a live resting timer');

-- Stand up. The resting timer ends and the auto attack sample takes the shared spot.
MOCK.player.status = 0;
MOCK.now = 101;
frames(5);
sw = win['##cadence_attack'];
log(('stood up: resting drawn=%s  auto attack drawn=%s at %d,%d'):format(
    tostring(rw.last == frame_no), tostring(sw ~= nil and sw.last == frame_no), sw and sw.x or -1, sw and sw.y or -1));
assert(rw.last ~= frame_no, 'resting sample should not show at a shared spot');
assert(sw ~= nil and sw.last == frame_no and sw.x == rw.x and sw.y == rw.y, 'the auto attack sample should be at the shared spot');
return table.concat(out, "\n");
