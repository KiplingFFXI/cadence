-- Replace a saved JSON file only after the new copy has been written and closed.
local json = require('json');
local ffi = require('ffi');
local store = {};
local serial = 0;
if (ffi.os == 'Windows') then
    pcall(ffi.cdef, [[
        unsigned long __stdcall GetCurrentProcessId(void);
        int __stdcall MoveFileExA(const char*, const char*, unsigned long);
        void* __stdcall CreateFileA(const char*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*);
        unsigned long __stdcall GetLastError(void);
        int __stdcall CloseHandle(void*);
    ]]);
end

-- Hold the profile file's lock through the whole read/change/write operation. Never wait in a frame.
function store.with_lock(path, action, ...)
    if (ffi.os ~= 'Windows') then return false, 'file'; end
    local opened, handle = pcall(ffi.C.CreateFileA, path .. '.lock', 0xC0000000, 0, nil, 4, 0x80, nil);
    if (not opened or handle == nil or handle == ffi.cast('void*', -1)) then
        local reason = opened and tonumber(ffi.C.GetLastError()) or 0;
        return false, (reason == 32 or reason == 33) and 'busy' or 'file';
    end
    local ok, first, second, third = pcall(action, ...);
    ffi.C.CloseHandle(handle);
    if (not ok) then return false, 'file'; end
    return first, second, third;
end

function store.write(path, value)
    local encoded, text = pcall(json.encode, value);
    if (not encoded) then return false; end
    serial = serial + 1;
    local process = ffi.os == 'Windows' and tonumber(ffi.C.GetCurrentProcessId()) or 0;
    local temp = ('%s.%d.%d.tmp'):format(path, process, serial);
    local file = io.open(temp, 'w');
    if (file == nil) then return false; end
    local wrote, written = pcall(file.write, file, text);
    local shut, closed = pcall(file.close, file);
    if (not wrote or not written or not shut or not closed) then
        os.remove(temp);
        return false;
    end
    local ok, replaced;
    if (ffi.os == 'Windows') then
        ok, replaced = pcall(ffi.C.MoveFileExA, temp, path, 9);
        replaced = ok and replaced ~= 0;
    else
        ok, replaced = pcall(os.rename, temp, path);
        replaced = ok and replaced ~= nil;
    end
    if (not replaced) then os.remove(temp); return false; end
    return true;
end

return store;
