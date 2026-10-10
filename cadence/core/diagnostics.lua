-- Local timing details are kept only while you ask for them. A report is written only on request.
local json = require('json');
local diagnostics = {};
local LIMIT = 256;
local enabled, events, first, count = false, {}, 1, 0;

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
end

function diagnostics.enable(on)
    on = on == true;
    if (on and not enabled) then diagnostics.reset(); end
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
    return { schema = 1, recorded_events = count, recording = enabled, snapshot = copy(snapshot, 0), events = rows };
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
