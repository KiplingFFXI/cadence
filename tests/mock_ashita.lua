-- Minimal stand-in for Ashita v4 so cadence can run outside the game.
-- Only what cadence touches is mocked. Calls to imgui are recorded so the tests can check them.

MOCK = {
    now = 0,
    events = {},
    printed = {},
    printed_raw = {},
    imgui_calls = {},
    record_imgui = false,
    player = {
        server_id = 1001, zone = 102, status = 0, name = 'Tester',
        main_job = 1, main_level = 75, sub_job = 13, sub_level = 37,
        hp_max = 1200, mp_max = 0, tp = 0, buffs = {},
        equipment = {},   -- [slot] = item id
        target_index = 0,
        index = 0x400,    -- Your own entity index.
    },
    items = {},           -- [id] = { Delay =, Skill = }
    entities = {},        -- [index] = { ServerId, Name, Status }
    fs = {},
    saved = 0,
    commands = {},
    key_shift = false,
    mouse_down = false,
    window_pos = {},      -- [name] = {x, y} forced positions to simulate dragging
};

-- os.clock is driven by the tests.
os.clock = function () return MOCK.now; end

-- common.lua bits cadence uses.
T = function (t) return t or {}; end
-- Splits a command at its spaces the way Ashita's sugar/string.lua does. Words in double quotes stay
-- together without the quotes, "" is an empty word, and a quote that never closes drops everything after it.
function string.args(s)
    local out, state, start = {}, 'none', 1;
    for i = 1, #s do
        local ch = s:sub(i, i);
        if (state == 'none' and ch == '"') then
            state, start = 'quote', i + 1;
        elseif (state == 'none' and ch ~= ' ') then
            state, start = 'word', i;
        elseif ((state == 'quote' and ch == '"') or (state == 'word' and ch == ' ')) then
            out[#out + 1] = s:sub(start, i - 1);
            state = 'none';
        end
    end
    if (state == 'word') then out[#out + 1] = s:sub(start); end
    return out;
end

addon = { path = '.' };

-- struct.unpack for the little-endian formats cadence uses.
struct = {};
function struct.unpack(fmt, data, pos)
    local function byte(i) return data:byte(pos + i) or 0; end
    if (fmt == 'L') then
        return byte(0) + byte(1) * 256 + byte(2) * 65536 + byte(3) * 16777216;
    elseif (fmt == 'H') then
        return byte(0) + byte(1) * 256;
    end
    error('unsupported struct format ' .. fmt);
end

-- ashita.bits.unpack_be reads bits least significant first, the same as LSB's unpackBitsBE.
ashita = { events = {}, bits = {}, fs = {} };

--[[
    Game memory, laid out the way XIUI finds it. MOCK.event_check, MOCK.ui_check and MOCK.menu_check
    are where each pattern is found, or 0 for not found. MOCK.menu_check is already past its offset.
    The event flag lives at MOCK.event_flag_address, set by MOCK.in_event. The interface object is at
    MOCK.ui_object. Its byte at +0xB4 is MOCK.ui_hidden. Its focus slot at +0x54 holds the menu named
    MOCK.menu_name, or nothing while that's nil. MOCK.focus_slot overrides what the menu pattern
    points at. Every find and read is counted, and reads per address too. A read anywhere else is an
    error.
]]
MOCK.event_check = 0x10087030;
MOCK.ui_check = 0x10160740;
MOCK.menu_check = 0x1015FDF2;
MOCK.event_flag_address = 0x10487E48;
MOCK.ui_object = 0x10621838;
MOCK.menu_object = 0x0A1B2C30;
MOCK.menu_header = 0x0A1B3000;
MOCK.in_event = false;
MOCK.ui_hidden = false;
MOCK.menu_name = nil;
MOCK.focus_slot = nil;
MOCK.memory_calls = { find = 0, read_uint32 = 0, read_uint8 = 0 };
MOCK.reads_at = {};
MOCK.finds = {};
local PATTERNS = {
    ['A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3'] = 'event_check',
    ['8B4424046A016A0050B9????????E8????????F6D81BC040C3'] = 'ui_check',
    ['8B480C85C974??8B510885D274??3B05'] = 'menu_check',
};
local function count_read(kind, addr)
    MOCK.memory_calls[kind] = MOCK.memory_calls[kind] + 1;
    MOCK.reads_at[addr] = (MOCK.reads_at[addr] or 0) + 1;
end
local function name_word(name)
    local b1, b2, b3, b4 = name:byte(1, 4);
    return (b1 or 32) + (b2 or 32) * 0x100 + (b3 or 32) * 0x10000 + (b4 or 32) * 0x1000000;
end
ashita.memory = {
    find = function (name, size, pattern, offset, usage)
        MOCK.memory_calls.find = MOCK.memory_calls.find + 1;
        local key = PATTERNS[pattern];
        if (key == nil) then error('find with an unknown pattern ' .. tostring(pattern)); end
        MOCK.finds[key] = { name = name, size = size, pattern = pattern, offset = offset, usage = usage };
        return MOCK[key];
    end,
    read_uint32 = function (addr)
        count_read('read_uint32', addr);
        if (MOCK.event_check ~= 0 and addr == MOCK.event_check + 1) then return MOCK.event_flag_address; end
        if (MOCK.ui_check ~= 0 and addr == MOCK.ui_check + 10) then return MOCK.ui_object; end
        if (MOCK.menu_check ~= 0 and addr == MOCK.menu_check) then return MOCK.focus_slot or (MOCK.ui_object + 0x54); end
        if (addr == MOCK.ui_object + 0x54) then return MOCK.menu_name and MOCK.menu_object or 0; end
        if (addr == MOCK.menu_object + 4) then return MOCK.menu_header; end
        if (addr == MOCK.menu_header + 0x46) then return name_word((MOCK.menu_prefix or 'menu    '):sub(1, 4)); end
        if (addr == MOCK.menu_header + 0x4A) then return name_word((MOCK.menu_prefix or 'menu    '):sub(5, 8)); end
        if (addr == MOCK.menu_header + 0x4E) then return name_word(MOCK.menu_name or ''); end
        if (addr == MOCK.menu_header + 0x52) then return name_word((MOCK.menu_name or ''):sub(5, 8)); end
        error(('read_uint32 at a wrong address 0x%X'):format(addr));
    end,
    read_uint8 = function (addr)
        count_read('read_uint8', addr);
        if (addr == MOCK.event_flag_address) then return MOCK.in_event and 1 or 0; end
        if (addr == MOCK.ui_object + 0xB4) then return MOCK.ui_hidden and 1 or 0; end
        error(('read_uint8 at a wrong address 0x%X'):format(addr));
    end,
};
function ashita.bits.unpack_be(data, byte_offset, bit_offset, length)
    local start = byte_offset * 8 + bit_offset;
    local value = 0;
    for i = 0, length - 1 do
        local k = start + i;
        local byte = data[math.floor(k / 8)] or 0;
        local b = math.floor(byte / 2 ^ (k % 8)) % 2;
        value = value + b * 2 ^ i;
    end
    return value;
end
function ashita.events.register(name, alias, fn)
    MOCK.events[name] = MOCK.events[name] or {};
    MOCK.events[name][alias] = fn;
end
function ashita.fs.exists(path) return MOCK.fs[path] == true; end
-- Files in a folder, from MOCK.dirs[path]. The real one also takes a regex mask. The mock ignores it.
function ashita.fs.get_directory(path) return MOCK.dirs and MOCK.dirs[path] or nil; end
function ashita.fs.create_dir() return true; end

function MOCK.fire(name, e)
    for _, fn in pairs(MOCK.events[name] or {}) do fn(e or {}); end
end

-- Game memory.
local function party()
    return {
        GetMemberServerId = function (_, i) return MOCK.player.server_id; end,
        GetMemberTargetIndex = function (_, i) return MOCK.player.index; end,
        GetMemberTP = function (_, i) return MOCK.player.tp; end,
    };
end
local function player_mem()
    return {
        GetMainJob = function () return MOCK.player.main_job; end,
        GetMainJobLevel = function () return MOCK.player.main_level; end,
        GetSubJob = function () return MOCK.player.sub_job; end,
        GetSubJobLevel = function () return MOCK.player.sub_level; end,
        GetHPMax = function () return MOCK.player.hp_max; end,
        GetMPMax = function () return MOCK.player.mp_max; end,
        GetBuffs = function ()
            local b = {};
            for i = 0, 31 do b[i] = MOCK.player.buffs[i + 1] or 255; end
            return b;
        end,
    };
end
local function inventory()
    return {
        GetEquippedItem = function (_, slot)
            local id = MOCK.player.equipment[slot];
            if (id == nil) then return { Slot = slot, Index = 0 }; end
            return { Slot = slot, Index = 0 * 256 + (slot + 10) };
        end,
        GetContainerItem = function (_, container, index)
            local slot = index - 10;
            return { Id = MOCK.player.equipment[slot] or 0, Extra = string.rep('\0', 24) };
        end,
    };
end
-- Your target. MOCK.player.held_target_index stands in for the target you had before picking one
-- for a spell, while MOCK.player.subtargeting is true.
local function target()
    return {
        GetIsSubTargetActive = function () return MOCK.player.subtargeting and 1 or 0; end,
        GetTargetIndex = function (_, i)
            if (i == 1) then return MOCK.player.held_target_index or 0; end
            return MOCK.player.target_index;
        end,
    };
end

-- Every entity by index, from MOCK.entities[index] = { ServerId, Name, Status, SpawnFlags }. Where it
-- stands is X, Y, Z, Yaw and Hitbox, named the way Ashita names them, so Z is height. Each position
-- read is counted in MOCK.position_reads.
MOCK.position_reads = 0;
local function entity_manager()
    local function field(index, name, default)
        local entity = MOCK.entities[index];
        if (entity == nil or entity[name] == nil) then return default; end
        return entity[name];
    end
    return {
        GetSpawnFlags = function (_, i) return field(i, 'SpawnFlags', 0); end,
        GetServerId = function (_, i) return field(i, 'ServerId', 0); end,
        GetStatus = function (_, i) return field(i, 'Status', 0); end,
        GetName = function (_, i) return field(i, 'Name', ''); end,
        GetLocalPositionX = function (_, i) MOCK.position_reads = MOCK.position_reads + 1; return field(i, 'X', 0); end,
        GetLocalPositionY = function (_, i) return field(i, 'Y', 0); end,
        GetLocalPositionZ = function (_, i) return field(i, 'Z', 0); end,
        GetLocalPositionYaw = function (_, i) return field(i, 'Yaw', 0); end,
        GetModelHitboxSize = function (_, i) return field(i, 'Hitbox', 0); end,
    };
end

AshitaCore = {
    GetMemoryManager = function ()
        return {
            GetParty = party, GetPlayer = player_mem, GetInventory = inventory, GetTarget = target,
            GetEntity = entity_manager,
        };
    end,
    GetChatManager = function ()
        return {
            QueueCommand = function (_, mode, command) table.insert(MOCK.commands, { mode = mode, command = command }); end,
            IsInputOpen = function () return MOCK.chat_input or 0; end,
        };
    end,
    GetResourceManager = function ()
        return { GetItemById = function (_, id) return MOCK.items[id]; end };
    end,
    GetInstallPath = function () return MOCK_INSTALL_PATH or 'C:/mock'; end,
};

function GetPlayerEntity()
    if (MOCK.zoning) then return nil; end
    return { Status = MOCK.player.status, StatusServer = MOCK.player.status_server or MOCK.player.status,
        ServerId = MOCK.player.server_id, Name = MOCK.player.name };
end

--[[
    Chat lines. MOCK.printed gets each line with its color codes taken out, so a test can match the
    words alone. MOCK.printed_raw gets the same line as it was printed, codes and all. A code is \30 or
    \31 and the byte after it, the way Ashita's chat.lua builds them. A test can empty either list.
]]
function MOCK.plain(line)
    return (line:gsub('[\30\31].', ''));
end
print = function (x)
    local line = tostring(x);
    table.insert(MOCK.printed_raw, line);
    table.insert(MOCK.printed, MOCK.plain(line));
end

-- Libraries loaded with require().
package.preload['common'] = function () return {}; end

--[[
    winmm for the resting sound. Nothing plays. Each MCI command string goes into MOCK.mci in order.
    MOCK.mci_code(command), when set, picks what each one returns, like 263 for a file MCI can't open.
    Without it every command works and returns 0. MOCK.no_winmm makes loading winmm fail.
]]
MOCK.mci = {};
local winmm = {
    mciSendStringA = function (command, answer, size, window)
        table.insert(MOCK.mci, command);
        return MOCK.mci_code and MOCK.mci_code(command) or 0;
    end,
};

-- ffi stand-in so tests can press Shift and hear nothing. cadence uses cdef, GetAsyncKeyState and winmm.
package.loaded['ffi'] = {
    os = 'Windows',
    cdef = function () end,
    cast = function (_, value) return value; end,
    C = {
        GetAsyncKeyState = function (vk) if (vk == 0x10 and MOCK.key_shift) then return -32768; end return 0; end,
        GetCurrentProcessId = function () return 1234; end,
        CreateFileA = function (path)
            MOCK.file_locks = MOCK.file_locks or {};
            if (MOCK.file_locks[path] or MOCK.file_lock_error) then MOCK.file_lock_last_error = 32; return -1; end
            MOCK.file_locks[path] = true;
            return path;
        end,
        GetLastError = function () return MOCK.file_lock_last_error or 0; end,
        CloseHandle = function (handle) MOCK.file_locks[handle] = nil; return 1; end,
        MoveFileExA = function (temp, path)
            if (MOCK.file_replace_error) then return 0; end
            os.remove(path);
            return os.rename(temp, path) and 1 or 0;
        end,
    },
    load = function (name)
        if (name ~= 'winmm' or MOCK.no_winmm) then error('cannot load module ' .. tostring(name)); end
        return winmm;
    end,
};

local settings_lib = { current = nil, callbacks = {} };
-- Loads the way Ashita's lib does. The file's table is merged with the defaults. With no file
-- (MOCK.settings_file = nil), a copy of the defaults is used. The merge fills anything missing with
-- the defaults' own tables, like sugar/table.lua does. The defaults are kept for the next character.
local function deep_copy(t)
    local copy = {};
    for k, v in pairs(t) do copy[k] = (type(v) == 'table') and deep_copy(v) or v; end
    return copy;
end
local function merge(into, from)
    for k, v in pairs(from) do
        if (rawget(into, k) == nil) then into[k] = v;
        elseif (type(v) == 'table') then merge(into[k], v); end
    end
    return into;
end
function settings_lib.load(defaults)
    settings_lib.defaults = defaults;
    settings_lib.current = merge(MOCK.settings_file or deep_copy(defaults), defaults);
    return settings_lib.current;
end
-- Another character logs in, with `file` as their settings file or nil for none.
function settings_lib.switch_character(file)
    settings_lib.current = merge(file or deep_copy(settings_lib.defaults), settings_lib.defaults);
    for _, fn in pairs(settings_lib.callbacks) do fn(settings_lib.current); end
end
function settings_lib.save() MOCK.saved = MOCK.saved + 1; return true; end
function settings_lib.register(_, alias, fn) settings_lib.callbacks[alias] = fn; end
package.preload['settings'] = function () return settings_lib; end
MOCK.settings = settings_lib;

-- Keeps MOCK.in_use on the settings the timers are drawn with. While one layout is shared, that's
-- the shared copy, not MOCK.settings.current. Call it after loading cadence.lua and before its load event.
function MOCK.watch_settings()
    local hud = require('ui.hud');
    local refresh = hud.refresh;
    hud.refresh = function (settings)
        MOCK.in_use = settings;
        refresh(settings);
    end
end

-- Every imgui function is recorded. The few that return values return plausible ones.
local imgui = {};

-- GetFontSize is the size of the font pushed last, or Ashita's 18 with none pushed. GetFrameHeight, the
-- height of a button or slider, adds the theme's 4 of padding above and below. CalcTextSize measures 14
-- high with no font pushed.
local ASHITA_FONT_SIZE = 18;
local FRAME_PADDING = 4;
local function font_size()
    return MOCK.font_stack[#MOCK.font_stack] or ASHITA_FONT_SIZE;
end

local window_stack = {};
local draw_list = setmetatable({}, { __index = function (list, name)
    local method = function (self, ...)
        if (MOCK.record_imgui) then
            local args = { 'dl:' .. name };
            for _, v in ipairs({ ... }) do
                if (type(v) == 'table') then v = { v[1], v[2] }; end
                table.insert(args, v);
            end
            table.insert(MOCK.imgui_calls, args);
        end
    end;
    rawset(list, name, method);
    return method;
end });
local specials = {
    Begin = function (name)
        table.insert(window_stack, name);
        MOCK.positions = MOCK.positions or {};
        if (MOCK.next_pos) then MOCK.positions[name] = MOCK.next_pos; MOCK.next_pos = nil; end
        if (MOCK.window_pos[name]) then MOCK.positions[name] = MOCK.window_pos[name]; end
        return true;
    end,
    End = function () table.remove(window_stack); end,
    GetWindowPos = function ()
        local name = window_stack[#window_stack];
        local p = MOCK.positions[name] or { 0, 0 };
        return p[1], p[2];
    end,
    SetNextWindowPos = function (pos) MOCK.next_pos = { pos[1], pos[2] }; end,
    GetWindowDrawList = function () return draw_list; end,
    GetFont = function () return 'default_font'; end,
    CalcTextSize = function (text)
        local px = MOCK.font_stack[#MOCK.font_stack] or 14;
        if (MOCK.measure) then return MOCK.measure(text, px), px; end
        return #text * 7, 14;
    end,
    -- With no size, PushFont keeps the size you had, like ImGui 1.92.
    PushFont = function (font, px)
        if (px == nil or px <= 0) then px = font_size(); end
        table.insert(MOCK.font_stack, px);
    end,
    PopFont = function () table.remove(MOCK.font_stack); end,
    GetFontSize = function () return font_size(); end,
    GetFrameHeight = function () return font_size() + FRAME_PADDING * 2; end,
    IsMouseDown = function () return MOCK.mouse_down; end,
    IsWindowHovered = function () return false; end,
    IsItemDeactivatedAfterEdit = function () return false; end,
    BeginTooltip = function () return true; end,
    BeginChild = function () return true; end,
    CollapsingHeader = function () return true; end,
    GetItemRectMin = function () return 0, 0; end,
    GetItemRectMax = function () return 100, 24; end,
    GetMousePos = function () return (MOCK.mouse or {})[1] or -1, (MOCK.mouse or {})[2] or -1; end,
    IsAnyMouseDown = function () return MOCK.mouse_down; end,
    SetClipboardText = function (value) MOCK.clipboard = value; end,
    BeginTabBar = function () return true; end,
    BeginTabItem = function () return true; end,
    Button = function () return false; end,
    Checkbox = function () return false; end,
    SliderInt = function () return false; end,
    SliderFloat = function () return false; end,
    ColorEdit4 = function () return false; end,
    GetCursorPosX = function () return 0; end,
    -- The settings window's size and room. MOCK.window_size stands in for a window the user resized.
    SetNextWindowSize = function (size) MOCK.next_size = { size[1], size[2] }; end,
    GetWindowSize = function () local w = MOCK.window_size or MOCK.next_size or { 920, 680 }; return w[1], w[2]; end,
    GetContentRegionAvail = function () return MOCK.content_width or 792, 400; end,
    BeginTable = function () return true; end,
    GetIO = function () return { DisplaySize = { x = MOCK.screen and MOCK.screen[1] or 1600, y = MOCK.screen and MOCK.screen[2] or 1200 } }; end,
    -- Each font file loads as its own font, named after its path.
    AddFontFromFileTTF = function (path) return 'font:' .. tostring(path); end,
    col32 = function (a, r, g, b) return ((a * 256 + b) * 256 + g) * 256 + r; end,
};
setmetatable(imgui, { __index = function (_, name)
    local special = specials[name];
    return function (...)
        if (MOCK.record_imgui) then
            local args = { name };
            for _, v in ipairs({ ... }) do
                if (type(v) == 'table') then v = { v[1], v[2] }; end
                table.insert(args, v);
            end
            table.insert(MOCK.imgui_calls, args);
        end
        if (special) then return special(...); end
    end;
end });
MOCK.font_stack = {};
package.preload['imgui'] = function () return imgui; end
package.preload['ui.navigation'] = function ()
    local module = assert(package.loaders[2]('ui.navigation'))('ui.navigation');
    MOCK.real_navigation_draw = module.draw;
    module.draw = function (tabs, look, matches, draw_page)
        imgui.BeginTabBar('##cadence_tabs');
        for _, tab in ipairs(tabs) do
            if (matches[tab[1]] and imgui.BeginTabItem(tab[1])) then
                module.select(tab[1]);
                draw_page(tab);
                imgui.EndTabItem();
            end
        end
        imgui.EndTabBar();
    end;
    return module;
end


-- ImGui constants cadence references. Real values don't matter to the tests.
local constant_names = {
    'ImGuiWindowFlags_NoDecoration', 'ImGuiWindowFlags_NoBackground', 'ImGuiWindowFlags_NoSavedSettings',
    'ImGuiWindowFlags_NoFocusOnAppearing', 'ImGuiWindowFlags_NoBringToFrontOnFocus', 'ImGuiWindowFlags_NoNav',
    'ImGuiWindowFlags_NoDocking', 'ImGuiWindowFlags_NoInputs', 'ImGuiWindowFlags_NoMove',
    'ImGuiHoveredFlags_AllowWhenBlockedByActiveItem', 'ImGuiFocusedFlags_RootAndChildWindows',
    'ImGuiWindowFlags_NoCollapse', 'ImGuiCond_Always',
    'ImGuiStyleVar_WindowPadding', 'ImGuiStyleVar_WindowMinSize', 'ImGuiStyleVar_WindowBorderSize',
    'ImGuiStyleVar_WindowRounding', 'ImGuiStyleVar_ChildRounding', 'ImGuiStyleVar_FrameRounding',
    'ImGuiStyleVar_PopupRounding', 'ImGuiStyleVar_GrabRounding', 'ImGuiStyleVar_TabRounding',
    'ImGuiStyleVar_FramePadding', 'ImGuiStyleVar_ItemSpacing', 'ImGuiStyleVar_GrabMinSize',
    'ImGuiStyleVar_FrameBorderSize', 'ImGuiMouseButton_Left', 'ImGuiSliderFlags_AlwaysClamp',
    'ImGuiColorEditFlags_NoInputs', 'ImGuiColorEditFlags_AlphaBar', 'ImGuiColorEditFlags_AlphaPreviewHalf',
    'ImGuiCol_WindowBg', 'ImGuiCol_ChildBg', 'ImGuiCol_PopupBg', 'ImGuiCol_Border', 'ImGuiCol_Separator',
    'ImGuiCol_Text', 'ImGuiCol_TextDisabled', 'ImGuiCol_TitleBg', 'ImGuiCol_TitleBgActive',
    'ImGuiCol_TitleBgCollapsed', 'ImGuiCol_FrameBg', 'ImGuiCol_FrameBgHovered', 'ImGuiCol_FrameBgActive',
    'ImGuiCol_Button', 'ImGuiCol_ButtonHovered', 'ImGuiCol_ButtonActive', 'ImGuiCol_CheckMark',
    'ImGuiCol_SliderGrab', 'ImGuiCol_SliderGrabActive', 'ImGuiCol_Header', 'ImGuiCol_HeaderHovered',
    'ImGuiCol_HeaderActive', 'ImGuiCol_Tab', 'ImGuiCol_TabHovered', 'ImGuiCol_TabSelected',
    'ImGuiCol_TabSelectedOverline', 'ImGuiCol_ScrollbarBg', 'ImGuiCol_ScrollbarGrab',
    'ImGuiCol_ScrollbarGrabHovered', 'ImGuiCol_ResizeGrip', 'ImGuiCol_ResizeGripHovered', 'ImGuiCol_ResizeGripActive',
    'ImGuiColorEditFlags_NoTooltip', 'ImGuiColorEditFlags_NoDragDrop',
};
for i, name in ipairs(constant_names) do _G[name] = 2 ^ (i % 20); end

-- Corner flags keep ImGui's real values, so render.py can tell which corners are rounded.
ImDrawFlags_RoundCornersTop    = 16 + 32;
ImDrawFlags_RoundCornersBottom = 64 + 128;
ImDrawFlags_RoundCornersLeft   = 16 + 64;
ImDrawFlags_RoundCornersRight  = 32 + 128;

-- The Alpha style var keeps its real value, 0, which no other constant here has, so a test can pick it
-- out of the style pushes.
ImGuiStyleVar_Alpha        = 0;
ImGuiPopupFlags_AnyPopupId = 1024;

-- Packet builders ------------------------------------------------------------------------------

-- A byte array (0-based) plus helpers to pack bits least significant first.
function MOCK.bytes(size)
    local b = { n = size };
    for i = 0, size - 1 do b[i] = 0; end
    return b;
end
function MOCK.pack_bits(b, bit_offset, length, value)
    for i = 0, length - 1 do
        local k = bit_offset + i;
        local byte_index = math.floor(k / 8);
        local bitv = math.floor(value / 2 ^ i) % 2;
        local mask = 2 ^ (k % 8);
        local cur = b[byte_index] or 0;
        local has = math.floor(cur / mask) % 2;
        if (bitv == 1 and has == 0) then cur = cur + mask; end
        if (bitv == 0 and has == 1) then cur = cur - mask; end
        b[byte_index] = cur;
    end
    return bit_offset + length;
end
function MOCK.to_string(b)
    local chars = {};
    for i = 0, b.n - 1 do chars[#chars + 1] = string.char(b[i]); end
    return table.concat(chars);
end

-- Builds a 0x028 action packet the way LSB's GP_SERV_COMMAND_BATTLE2::pack does.
-- results = list of { message =, add_effect = bool, reaction = bool }
function MOCK.action_packet(actor, category, param, target, results)
    return MOCK.action_packet_multi(actor, category, param, target and { { id = target, results = results } } or {});
end

-- An action packet with several targets, each { id =, results = { ... } }.
function MOCK.action_packet_multi(actor, category, param, targets)
    local b = MOCK.bytes(512);
    local o = 40;
    o = MOCK.pack_bits(b, o, 32, actor);
    o = MOCK.pack_bits(b, o, 6, #targets);
    o = MOCK.pack_bits(b, o, 4, 0);
    o = MOCK.pack_bits(b, o, 4, category);
    o = MOCK.pack_bits(b, o, 32, param or 0);
    o = MOCK.pack_bits(b, o, 32, 0);
    for _, target in ipairs(targets) do
        local results = target.results;
        o = MOCK.pack_bits(b, o, 32, target.id);
        o = MOCK.pack_bits(b, o, 4, #results);
        for _, r in ipairs(results) do
            o = MOCK.pack_bits(b, o, 3, r.resolution or 0);
            o = MOCK.pack_bits(b, o, 2, 1);
            o = MOCK.pack_bits(b, o, 12, r.animation or 0);
            o = MOCK.pack_bits(b, o, 5, 0);
            o = MOCK.pack_bits(b, o, 2, 0);
            o = MOCK.pack_bits(b, o, 3, 0);
            o = MOCK.pack_bits(b, o, 17, r.damage or 55);
            o = MOCK.pack_bits(b, o, 10, r.message);
            o = MOCK.pack_bits(b, o, 31, 0x12345);
            o = MOCK.pack_bits(b, o, 1, r.add_effect and 1 or 0);
            if (r.add_effect) then
                o = MOCK.pack_bits(b, o, 6, 5); o = MOCK.pack_bits(b, o, 4, 1);
                o = MOCK.pack_bits(b, o, 17, r.added_param or 9999); o = MOCK.pack_bits(b, o, 10, r.added_message or 163);
            end
            -- `reaction` is the reaction's kind, like 63 for a counter. True means 1, which is Blaze Spikes.
            o = MOCK.pack_bits(b, o, 1, r.reaction and 1 or 0);
            if (r.reaction) then
                local kind = (r.reaction == true) and 1 or r.reaction;
                o = MOCK.pack_bits(b, o, 6, kind); o = MOCK.pack_bits(b, o, 4, 1);
                o = MOCK.pack_bits(b, o, 14, r.reaction_param or 1234);
                o = MOCK.pack_bits(b, o, 10, r.reaction_message or ((kind == 63) and 33 or 44));
            end
        end
    end
    local size = math.floor((o + 7) / 8);
    size = size + (4 - size % 4) % 4;
    b.n = size;
    return { id = 0x028, size = size, data_raw = b, data = MOCK.to_string(b) };
end

local function put32(b, off, v)
    for i = 0, 3 do b[off + i] = math.floor(v / 256 ^ i) % 256; end
end
local function put16(b, off, v)
    for i = 0, 1 do b[off + i] = math.floor(v / 256 ^ i) % 256; end
end

function MOCK.message_packet(actor, target, param1, param2, message, target_index)
    local b = MOCK.bytes(0x1C);
    put32(b, 0x04, actor); put32(b, 0x08, target);
    put32(b, 0x0C, param1 % 4294967296); put32(b, 0x10, param2);
    put16(b, 0x14, 0); put16(b, 0x16, target_index or 0); put16(b, 0x18, message);
    return { id = 0x029, size = 0x1C, data_raw = b, data = MOCK.to_string(b) };
end

function MOCK.vitals_packet(id, hp, mp, tp)
    local b = MOCK.bytes(0x24);
    put32(b, 0x04, id); put32(b, 0x08, hp); put32(b, 0x0C, mp); put32(b, 0x10, tp);
    return { id = 0x0DF, size = 0x24, data_raw = b, data = MOCK.to_string(b) };
end

function MOCK.status_packet(id, status)
    local b = MOCK.bytes(0x64);
    put32(b, 0x24, id);
    b[0x30] = status;
    return { id = 0x037, size = b.n, data_raw = b, data = MOCK.to_string(b) };
end

-- A 0x058 assist packet the way Phoenix's GP_SERV_COMMAND_ASSIST builds it. `id` is whose it is and
-- `monster` the one their attacks are on. The last field is their own entity index.
function MOCK.assist_packet(id, monster)
    local b = MOCK.bytes(0x10);
    put32(b, 0x04, id); put32(b, 0x08, monster); put16(b, 0x0C, MOCK.player.index);
    return { id = 0x058, size = 0x10, data_raw = b, data = MOCK.to_string(b) };
end

-- A 0x00A zone in packet the way Phoenix's GP_SERV_COMMAND_LOGIN builds it, with your server id and
-- the zone. The zone is MOCK.player.zone unless `zone` is given.
function MOCK.zone_packet(id, zone)
    local b = MOCK.bytes(0x100);
    put32(b, 0x04, id);
    put32(b, 0x30, zone or MOCK.player.zone);
    return { id = 0x00A, size = 0x100, data_raw = b, data = MOCK.to_string(b) };
end

function MOCK.frame(dt)
    MOCK.now = MOCK.now + (dt or 1 / 60);
    MOCK.fire('d3d_present');
end
