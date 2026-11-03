-- Timing events are opt-in. The last drawing fault stays in memory. Reports are written on request.
local json = require('json');
local diagnostics = {};
local LIMIT = 256;
local enabled, events, first, count = false, {}, 1, 0;
local drawing_error;

-- Keep only loaded module names. Absolute paths and dynamic chunk text never enter a report.
local function frame_source(info)
    if (info.what == 'C') then return '[C]'; end
    if (type(info.source) ~= 'string' or info.source:sub(1, 1) ~= '@') then return '[string]'; end
    local path = info.source:sub(2):gsub('\\', '/');
    local file = path:match('^.*/cadence/(.+)$') or path:match('^cadence/(.+)$');
    if (file == 'cadence.lua') then return 'cadence/cadence.lua'; end
    if (file) then
        local group, name = file:match('^(%a+)/([%w_]+)%.lua$');
        if ((group == 'core' or group == 'ui' or group == 'data') and package.loaded[group .. '.' .. name]) then
            return 'cadence/' .. file;
        end
    end
    file = path:match('^.*/addons/libs/([%w_/]+%.lua)$');
    if (file and package.loaded[(file:gsub('%.lua$', ''):gsub('/', '.'))]) then return 'libs/' .. file; end
    return '[external]';
end

local HUD_TIMERS = { attack = true, resting = true, enemy = true, recovery = true, enemycast = true };
local HUD_SCALARS = { height_scale = true, width = true, height = true, row = true, header = true, bar = true,
    next_line = true, ticks_line = true, goal_line = true, tp_time_line = true, hits_line = true,
    footer = true, rows = true, gaps = true, scale = true, size_revision = true };
local HUD_METRICS = { 'scale', 'revision', 'value_px', 'label_px', 'name_px', 'detail_px', 'pad_y',
    'strip_pad_y', 'strip_top', 'gap', 'strip_gap' };
local HUD_SIZE = { 'value_px', 'label_px', 'name_px', 'detail_px', 'width_scale', 'pad_x', 'pad_y',
    'strip_pad_y', 'strip_top', 'accent', 'gap', 'strip_gap', 'spacing', 'rounding', 'overlap' };
local HUD_ELEMENT = { 'width', 'height_scale', 'bar_height' };
local HUD_FUNCTIONS = { vertical_size = true, fill_vertical = true, header_px = true, bar_px = true,
    element_height = true, element_size = true, draw_timer = true, draw_attack = true, draw_resting = true,
    draw_enemy = true, draw_reengage = true, draw_recovery = true, draw_enemycast = true };

-- Missing numeric fields stay explicit without storing free text from a corrupted value.
local function numeric_field(value)
    local result = { kind = type(value) };
    if (type(value) == 'number') then
        if (value == value and value > -math.huge and value < math.huge) then result.value = value;
        else result.nonfinite = true; end
    end
    return result;
end

local function numeric_table(value, fields)
    if (type(value) ~= 'table') then return numeric_field(value); end
    local result = {};
    for _, field in ipairs(fields) do result[field] = numeric_field(rawget(value, field)); end
    return result;
end

-- xpcall calls this before the failing stack unwinds. Successful frames never inspect the stack.
function diagnostics.capture_drawing_error(err)
    local frames = {};
    for level = 2, 33 do
        local info = debug.getinfo(level, 'Slnf');
        if (not info) then break; end
        local frame = { source = frame_source(info), line = info.currentline, defined = info.linedefined };
        frames[#frames + 1] = frame;
        if (frame.source == 'cadence/ui/hud.lua') then
            frame.symbol = HUD_FUNCTIONS[info.name] and info.name or nil;
            local values = {};
            local key;
            for index = 1, 64 do
                local name, value = debug.getlocal(level, index);
                if (not name) then break; end
                if (name == 'key' and HUD_TIMERS[value]) then key, values.timer = value, value;
                elseif (HUD_SCALARS[name]) then values[name] = numeric_field(value);
                elseif (name == 'metrics') then values.metrics = numeric_table(value, HUD_METRICS); end
            end
            for index = 1, 64 do
                local name, value = debug.getupvalue(info.func, index);
                if (not name) then break; end
                if (name == 'size') then values.size = numeric_table(value, HUD_SIZE);
                elseif (name == 'size_revision') then values.size_revision = numeric_field(value);
                elseif (name == 'settings' and key and type(value) == 'table') then
                    values.element = numeric_table(rawget(value, key), HUD_ELEMENT);
                end
            end
            frame.hud = values;
        end
    end
    -- Error text can contain player names or paths. Reports keep locations and selected numeric fields.
    drawing_error = { at = os.clock(), value_type = type(err), frames = frames };
    return err;
end

-- JSON arrays must be dense. Buff ids, equipment slots and merit ids are object keys.
local function json_keys(value)
    local entries, maximum, array = 0, 0, true;
    for key in pairs(value) do
        entries = entries + 1;
        if (type(key) ~= 'number' or key < 1 or key % 1 ~= 0) then
            array = false;
        else
            maximum = math.max(maximum, key);
        end
    end
    if (array and maximum == entries) then return value; end
    local object = {};
    for key, part in pairs(value) do
        local name = tostring(key);
        if (type(key) == 'number') then
            -- Keep both entries if a table also has the same id written as a string.
            while (value[name] ~= nil or object[name] ~= nil) do name = '[' .. name .. ']'; end
        end
        object[name] = part;
    end
    return object;
end

local function copy(value, depth)
    if (type(value) == 'number') then
        return value == value and math.abs(value) < math.huge and value or nil;
    elseif (type(value) == 'string') then
        return value:sub(1, 2000);
    elseif (type(value) == 'boolean') then
        return value;
    elseif (type(value) ~= 'table' or depth >= 8) then
        return nil;
    end
    local result, seen = {}, 0;
    for key, part in pairs(value) do
        local internal = type(key) == 'string' and (key == 'extra' or key == 'key' or key:match('_key$'));
        if (not internal and (type(key) == 'string' or type(key) == 'number')) then
            seen = seen + 1;
            if (seen > 512) then break; end
            result[key] = copy(part, depth + 1);
        end
    end
    return json_keys(result);
end

function diagnostics.reset()
    events, first, count = {}, 1, 0;
    drawing_error = nil;
end

function diagnostics.enable(on)
    on = on == true;
    if (on and not enabled) then events, first, count = {}, 1, 0; end
    enabled = on;
end

function diagnostics.is_enabled()
    return enabled;
end

function diagnostics.record(kind, now, values)
    if (not enabled) then return; end
    local event = { kind = kind, at = now, values = copy(values, 0) };
    if (count < LIMIT) then
        events[(first + count - 1) % LIMIT + 1] = event;
        count = count + 1;
    else
        events[first] = event;
        first = first % LIMIT + 1;
    end
end

function diagnostics.report(snapshot)
    local rows = {};
    for i = 0, count - 1 do rows[#rows + 1] = copy(events[(first + i - 1) % LIMIT + 1], 0); end
    return { schema = 1, recorded_events = count, recording = enabled, snapshot = copy(snapshot, 0), events = rows,
        drawing_error = copy(drawing_error, 0) };
end

function diagnostics.save(snapshot)
    local folder = ('%s\\config\\addons\\%s\\reports\\'):format(AshitaCore:GetInstallPath(), addon.name);
    local ok, encoded = pcall(json.encode, diagnostics.report(snapshot));
    if (not ok) then return nil, 'The timing report could not be prepared.'; end
    local made, created = pcall(ashita.fs.create_dir, folder);
    if (not made or (not created and not ashita.fs.exists(folder))) then
        return nil, 'The reports folder could not be opened.';
    end
    local stem = folder .. os.date('!%Y%m%d-%H%M%S');
    for suffix = 1, 100 do
        local path = ('%s-%02d.json'):format(stem, suffix);
        local existing = io.open(path, 'rb');
        if (existing) then
            existing:close();
        else
            local file = io.open(path, 'wb');
            if (not file) then return nil, 'The timing report could not be saved.'; end
            local written, result = pcall(file.write, file, encoded);
            local closed, close_result = pcall(file.close, file);
            if (not written or result == nil or not closed or close_result == nil) then
                os.remove(path);
                return nil, 'The timing report could not be saved.';
            end
            return path;
        end
    end
    return nil, 'There are already too many reports with that time.';
end

return diagnostics;
