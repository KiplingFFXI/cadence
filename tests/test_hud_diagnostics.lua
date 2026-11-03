-- Fault-only HUD evidence identifies missing geometry without retaining private strings.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local diagnostics, hud = require('core.diagnostics'), require('ui.hud');
local s = require('ui.defaults').make();
hud.refresh(s); hud.set_movable(false);
local function upvalue(func, wanted)
    for index = 1, 64 do
        local name, value = debug.getupvalue(func, index);
        if (not name) then break; end
        if (name == wanted) then return value; end
    end
    error('No upvalue ' .. wanted);
end
local size = upvalue(hud.element_size, 'size');
local vertical = upvalue(upvalue(hud.element_size, 'vertical_size'), 'vertical');
local function fault(draw, matches)
    diagnostics.reset();
    local ok = xpcall(draw, diagnostics.capture_drawing_error);
    for _, frame in ipairs(diagnostics.report({}).drawing_error.frames) do
        if (not ok and matches(frame)) then return true; end
    end
    return false;
end
local function attack_size() hud.element_size('attack'); end
local original = size.width_scale;
size.width_scale = nil;
check('missing width scale is retained from the failing function upvalue', fault(attack_size,
    function(f) return f.hud and f.hud.timer == 'attack' and f.hud.size
        and f.hud.size.width_scale.kind == 'nil' and f.symbol == 'element_size'; end));
size.width_scale = original;

hud.element_size('attack');
original = vertical.attack.pad_y;
vertical.attack.pad_y = nil;
check('missing cached padding is retained from the failing metrics local', fault(attack_size,
    function(f) return f.hud and f.hud.timer == 'attack' and f.hud.metrics
        and f.hud.metrics.pad_y.kind == 'nil'; end));
vertical.attack.pad_y = original;

original = s.attack.bar_height;
s.attack.bar_height = nil;
check('missing bar thickness is retained from the owning settings upvalue', fault(attack_size,
    function(f) return f.hud and f.hud.timer == 'attack' and f.hud.element
        and f.hud.element.bar_height.kind == 'nil'; end));
s.attack.bar_height = original;

original = size.value_px;
size.value_px, vertical.attack.revision = nil, nil;
check('a partially initialized cache retains the missing source pixels', fault(attack_size,
    function(f) return f.hud and f.hud.size and f.hud.size.value_px.kind == 'nil'; end));
size.value_px = original;
hud.element_size('attack');

local getinfo = debug.getinfo;
debug.getinfo = function(level, fields)
    local info = getinfo(level + 1, fields);
    if (info and info.source and info.source:gsub('\\', '/'):find('/cadence/ui/hud.lua', 1, true)) then info.currentline = 0; end
    return info;
end;
original = size.width_scale;
size.width_scale = nil;
check('line-zero faults still identify the function and missing geometry', fault(attack_size,
    function(f) return f.line == 0 and f.defined and f.defined > 0 and f.hud and f.hud.timer == 'attack'
        and f.hud.size and f.hud.size.width_scale.kind == 'nil' and f.symbol == 'element_size'; end));
size.width_scale, debug.getinfo = original, getinfo;

local private = assert(loadstring([[
local settings = { attack = { width = 'Private Player C:/Secret/password', bar_height = 5, height_scale = 1,
    unrelated = 'Private Player C:/Secret/password' } };
local size = { width_scale = 'Private Player C:/Secret/password' };
return function()
    local key = 'attack'; local width = settings[key].width;
    return width * size.width_scale;
end
]], '@C:/Safe/addons/cadence/ui/hud.lua'))();
check('corrupted numeric fields retain their types without their string contents', fault(private,
    function(f) return f.hud and f.hud.timer == 'attack' and f.hud.size
        and f.hud.size.width_scale.kind == 'string'; end));
local json = require('json');
local encoded = json.encode(diagnostics.report({}));
local decoded = json.decode(encoded);
check('numeric evidence survives JSON while private strings and paths stay excluded', decoded.drawing_error.frames[1].hud
    and not encoded:find('Private Player', 1, true) and not encoded:find('password', 1, true) and not encoded:find('C:', 1, true));

local getlocal, getupvalue, reads = debug.getlocal, debug.getupvalue, 0;
debug.getinfo = function(...) reads = reads + 1; return getinfo(...); end;
debug.getlocal = function(...) reads = reads + 1; return getlocal(...); end;
debug.getupvalue = function(...) reads = reads + 1; return getupvalue(...); end;
for _ = 1, 10 do
    hud.begin_frame(); hud.join_below(false, false, false); hud.draw_attack(0.5, 2, 4, false); hud.end_frame();
end
debug.getinfo, debug.getlocal, debug.getupvalue = getinfo, getlocal, getupvalue;
check('successful HUD frames perform no diagnostic stack reads', reads == 0);
check('HUD diagnostics send no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
