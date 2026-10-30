-- The focused native menu distinguishes the full-screen log from typing and other menus.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
local player = require('core.player');
local function state(name, want_chat, want_menus, want_map)
    MOCK.menu_name = name;
    return player.menu_visibility(want_chat, want_menus, want_map);
end
local function expect(name, chat_expected, menu_expected, map_expected, want_chat, want_menus, want_map)
    local chat, menus, map = state(name, want_chat, want_menus, want_map);
    check(('menu %q -> %s/%s/%s'):format(tostring(name), tostring(chat_expected), tostring(menu_expected), tostring(map_expected)),
        chat == chat_expected and menus == menu_expected and map == map_expected,
        ('%s/%s/%s'):format(tostring(chat), tostring(menus), tostring(map)));
end
check('all menu capabilities use the already-validated focus signature', player.can_check_chat()
    and player.can_check_menus() and player.can_check_map() and MOCK.memory_calls.find == 3);
expect(nil, false, false, false);
expect('fulllog ', true, false, false);
expect('fulllog\0', true, false, false);
expect('fulllog ', false, false, false, false, true, true);
for _, name in ipairs({ 'inline  ', 'inline\0\0', 'chatctrl', 'mcr1pall', 'mcr2pall', 'mcr1long', 'mcr2long' }) do
    expect(name, false, false, false);
end
for _, name in ipairs({ 'equip   ', 'scanlist', 'magic   ', 'magselec', 'ability ', 'abiselec', 'playermo', 'mount   ', 'newmenu ' }) do
    expect(name, false, true, false);
end
expect('equip   ', false, false, false, true, false, true);
for _, name in ipairs({ 'map0    ', 'mapv2   ', 'mapframe', 'mapscan ' }) do
    expect(name, false, false, true);
    expect(name, false, false, false, true, true, false);
end
expect('        ', false, false, false);
expect('\0\0\0\0\0\0\0\0', false, false, false);
expect('bad\1name', false, false, false);
MOCK.menu_prefix = 'notmenu ';
expect('fulllog ', false, false, false);
expect('equip   ', false, false, false);
MOCK.menu_prefix = nil;
MOCK.chat_input, MOCK.player.subtargeting = 1, true;
expect(nil, false, false, false);
expect('inline  ', false, false, false);
MOCK.chat_input, MOCK.player.subtargeting = 0, false;
local before = MOCK.memory_calls.read_uint32;
expect('equip   ', false, false, false, false, false, false);
check('disabled checks do not touch memory', MOCK.memory_calls.read_uint32 == before);
MOCK.menu_name = 'equip   ';
local slot = MOCK.ui_object + 0x54;
local slot_reads = MOCK.reads_at[slot];
local signatures = MOCK.memory_calls.find;
player.menu_visibility(true, true, true);
check('all three checks traverse focused menu only once', MOCK.reads_at[slot] == slot_reads + 1);
MOCK.menu_name = 'map0    ';
before = MOCK.memory_calls.read_uint32;
check('legacy map_open uses the same detector', player.map_open());
check('map-only checks retain their three memory reads', MOCK.memory_calls.read_uint32 == before + 3);
check('menu changes do not scan signatures again', MOCK.memory_calls.find == signatures);

local read = ashita.memory.read_uint32;
for _, bad in ipairs({ 0, 1, -1, math.huge, 0 / 0, 0xFFFFFFFE }) do
    ashita.memory.read_uint32 = function(addr) if (addr == slot) then return bad; end return read(addr); end;
    local chat, menus, map = player.menu_visibility();
    check('an invalid focused pointer leaves every timer visible: ' .. tostring(bad), not chat and not menus and not map);
end
ashita.memory.read_uint32 = function(addr) if (addr == MOCK.menu_object + 4) then return nil; end return read(addr); end;
local chat, menus, map = player.menu_visibility();
check('a missing menu header leaves every timer visible', not chat and not menus and not map);
ashita.memory.read_uint32 = function() error('unreadable menu memory'); end;
chat, menus, map = player.menu_visibility();
check('an unreadable focus chain fails open', not chat and not menus and not map);
ashita.memory.read_uint32 = read;
expect('fulllog ', true, false, false);

-- Reopening player under a changed client layout must disable detection, not guess from target state.
local check_address, ui_check, focus = MOCK.menu_check, MOCK.ui_check, MOCK.focus_slot;
MOCK.menu_check = 0;
local missing = dofile(ADDON_DIR .. '/core/player.lua');
check('missing menu signature disables chat and menu capabilities', not missing.can_check_chat() and not missing.can_check_menus());
chat, menus, map = missing.menu_visibility();
check('missing menu signature does not claim any menu is open', not chat and not menus and not map);
MOCK.menu_check, MOCK.ui_check = check_address, 0;
missing = dofile(ADDON_DIR .. '/core/player.lua');
check('missing interface signature disables chat and menu capabilities', not missing.can_check_chat() and not missing.can_check_menus());
MOCK.ui_check, MOCK.focus_slot = ui_check, MOCK.ui_object + 0x58;
missing = dofile(ADDON_DIR .. '/core/player.lua');
check('a mismatched interface layout disables chat and menu capabilities', not missing.can_check_chat() and not missing.can_check_menus());
MOCK.focus_slot = focus;

if (jit) then jit.off(); end
MOCK.menu_name = 'equip   ';
for _ = 1, 100 do player.menu_visibility(); end
collectgarbage('collect'); collectgarbage('stop');
local memory_before = collectgarbage('count');
for _ = 1, 1000 do player.menu_visibility(); end
local bytes = (collectgarbage('count') - memory_before) * 1024 / 1000;
collectgarbage('restart');
check('steady menu checks allocate no per-frame tables or strings', bytes < 1, ('%.2f bytes/frame'):format(bytes));

-- Exercise the actual main callback and native name reader together, without a detector override.
MOCK.now, MOCK.player.status, MOCK.menu_name = 100, 1, nil;
MOCK.player.equipment[0], MOCK.items[16535] = 16535, { Delay = 240, Skill = 3 };
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local function attack_windows(name)
    MOCK.menu_name, MOCK.imgui_calls, MOCK.record_imgui = name, {}, true;
    MOCK.frame(1 / 60); MOCK.record_imgui = false;
    local count = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'Begin' and call[2] == '##cadence_attack') then count = count + 1; end
    end
    return count;
end
check('the real main callback hides full-screen chat and returns after typing or closing',
    attack_windows(nil) == 1 and attack_windows('fulllog') == 0 and attack_windows('inline') == 1 and attack_windows(nil) == 1);
check('the real main callback hides equipment while leaving macro palettes visible',
    attack_windows('equip') == 0 and attack_windows('mcr1pall') == 1);
MOCK.settings.current.visibility.chat, MOCK.settings.current.visibility.chat_attack = 'selected', false;
check('a timer excluded from the real full-screen-chat rule stays visible', attack_windows('fulllog') == 1);
local errors = false;
for _, line in ipairs(MOCK.printed) do errors = errors or line:find('Drawing stopped', 1, true) ~= nil; end
check('native menu transitions add no drawing errors', not errors);
check('the detector sends no game commands', #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
