--[[
    Lua half of the preview's imgui bridge. Run after ../mock_ashita.lua.

    Called as a chunk with one argument, PY, a table the Python side fills in:
      PY.functions      Ashita GuiManager functions (imgui_bridge.py), name -> python callable
      PY.draw_list      ImDrawList methods, name -> python callable taking the draw list first
      PY.get_attr, PY.set_attr, PY.call_attr   field access for GetIO/GetStyle/GetMainViewport
      PY.enums          ImGui constants with imgui_bundle values, C name -> number
      PY.imgui_lua      path of Ashita's libs/imgui.lua, or nil
      PY.warn           records a warning

    It builds the GuiManager stand-in (unknown names raise an error naming the function), then makes
    require('imgui') return Ashita's real libs/imgui.lua on top of it, the same way the game does
    (imgui.col32, ShowHelp, FLT_MAX and the ICON_FA globals come from that file). Enum globals are then
    set to imgui_bundle's values, so a flag means the same thing to the ImGui that draws the preview.
    Constants imgui_bundle has but Ashita's file doesn't define still resolve, with a warning, because
    they would be nil in the game.
]]

local PY = ...;

local gui = {};
for name, f in pairs(PY.functions) do
    gui[name] = f;
end

local function missing(kind, name)
    error(('imgui bridge: %s%s is not implemented by the preview bridge (add it to imgui_bridge.py)')
        :format(kind, tostring(name)), 3);
end

-- A draw list call like list:AddRectFilled(...) passes the wrapper as self, so methods drop it.
local draw_list_mt = {};
draw_list_mt.__index = function (self, name)
    local f = PY.draw_list[name];
    if (f == nil) then
        missing('ImDrawList:', name);
    end
    return function (this, ...)
        return f(rawget(this, '__dl'), ...);
    end;
end;
local function wrap_draw_list(dl)
    return setmetatable({ __dl = dl }, draw_list_mt);
end
local get_window_draw_list = gui.GetWindowDrawList;
local get_background_draw_list = gui.GetBackgroundDrawList;
local get_foreground_draw_list = gui.GetForegroundDrawList;
gui.GetWindowDrawList = function () return wrap_draw_list(get_window_draw_list()); end;
gui.GetBackgroundDrawList = function (vp) return wrap_draw_list(get_background_draw_list()); end;
gui.GetForegroundDrawList = function (vp) return wrap_draw_list(get_foreground_draw_list()); end;

-- GetIO(), GetStyle() and GetMainViewport() give Ashita-style CamelCase fields over imgui_bundle objects.
local proxy_mt = {};
proxy_mt.__index = function (self, key)
    local obj = rawget(self, '__obj');
    local value, kind = PY.get_attr(obj, key);
    if (kind == 'callable') then
        return function (first, ...)
            if (first == self) then
                return PY.call_attr(obj, key, ...);
            end
            return PY.call_attr(obj, key, first, ...);
        end;
    elseif (kind == 'vec') then
        -- style.WindowPadding.x = 4 writes through, like Ashita's ImVec2 userdata.
        return setmetatable({}, {
            __index = function (_, comp) return PY.vec_get(obj, key, comp); end,
            __newindex = function (_, comp, v) PY.vec_set(obj, key, comp, v); end,
        });
    end
    return value;
end;
proxy_mt.__newindex = function (self, key, value)
    PY.set_attr(rawget(self, '__obj'), key, value);
end;
local function proxy(obj)
    return setmetatable({ __obj = obj }, proxy_mt);
end
for _, name in ipairs({ 'GetIO', 'GetStyle', 'GetMainViewport' }) do
    local f = gui[name];
    gui[name] = function () return proxy(f()); end;
end

setmetatable(gui, { __index = function (_, name) missing('imgui.', name); end });

BRIDGE_GUI = gui;
AshitaCore.GetGuiManager = function () return gui; end;

-- require('imgui') gives Ashita's own libs/imgui.lua over the bridge, like the game.
local module;
if (PY.imgui_lua ~= nil) then
    local chunk = assert(loadfile(PY.imgui_lua));
    module = chunk();
else
    module = setmetatable({}, { __index = gui });
    FLT_MAX = 3.402823466e+38;
    function module.col32(a, r, g, b)
        return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r);
    end
end
package.preload['imgui'] = function () return module; end;
package.loaded['imgui'] = nil;

-- Enum names Ashita defines take imgui_bundle's value. Names only imgui_bundle has are served
-- through _G's __index with a warning, and so is any other undefined Im* name (nil, like the game).
local extra = {};
for name, value in pairs(PY.enums) do
    if (PY.imgui_lua == nil or rawget(_G, name) ~= nil) then
        rawset(_G, name, value);
    else
        extra[name] = value;
    end
end
local warned = {};
setmetatable(_G, { __index = function (_, name)
    -- Constant-shaped names only (ImGuiCol_Text, ImDrawFlags_None), so an unset global like Image isn't flagged.
    if (type(name) == 'string' and name:match('^Im%w+_') ~= nil) then
        local where = debug.getinfo(2, 'Sl');
        local at = where and (where.short_src .. ':' .. tostring(where.currentline)) or '?';
        if (not warned[name .. at]) then
            warned[name .. at] = true;
            if (extra[name] ~= nil) then
                PY.warn(('%s is not defined by Ashita\'s libs/imgui.lua (nil in game), read at %s'):format(name, at));
            else
                PY.warn(('%s is not an ImGui constant (nil), read at %s'):format(name, at));
            end
        end
        return extra[name];
    end
    return nil;
end });

-- The real preview uses the real tab navigation instead of the unit-test traversal.
package.preload['ui.navigation'], package.loaded['ui.navigation'] = nil, nil;
return module;
