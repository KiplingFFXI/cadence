-- Last tick gains stay actual. Next tick gains have their own switch and identify uncertain amounts.
local out, fails = {}, 0;
local function check(name, condition, detail)
    if (condition) then out[#out + 1] = 'ok   ' .. name;
    else
        fails = fails + 1;
        out[#out + 1] = 'FAIL ' .. name .. ' ' .. tostring(detail or '');
    end
end

MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
os.getenv = function (key) if (key == 'WINDIR') then return 'C:\\Windows'; end end;
MOCK.player.main_job, MOCK.player.sub_job, MOCK.player.sub_level = 4, 0, 0;
MOCK.player.hp_max, MOCK.player.mp_max = 900, 500;
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local hud, resting = require('ui.hud'), require('core.resting');
local imgui = require('imgui');
local function command(words) MOCK.fire('command', { command = '/cadence ' .. words }); end
local function capture(draw)
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    draw();
    MOCK.record_imgui = false;
    local text, positions = {}, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'dl:AddText') then
            text[#text + 1], positions[call[6]] = call[6], call[4];
        end
    end
    return table.concat(text, '|'), positions;
end
local function frame() return capture(function () MOCK.frame(0); end); end

check('next gains default off while last gains stay on', s.resting.show_next_gains == false and s.resting.show_gains);
local saves = MOCK.saved;
command('resting nextgains on');
check('the command enables and saves next gains independently', s.resting.show_next_gains and s.resting.show_gains
    and MOCK.saved > saves and MOCK.printed[#MOCK.printed] == '[cadence] Next tick gains is on for the resting timer.');
command('resting nextgains');
check('the command without a value toggles it', not s.resting.show_next_gains);
command('help resting');
check('help names the command and setting', table.concat(MOCK.printed, '|'):find('nextgains (Next tick gains)', 1, true));

command('');
frame();
local checkbox;
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'Checkbox' and call[2] == 'Next tick gains##resting') then checkbox = call; end
end
check('settings show the separate unchecked box', checkbox and checkbox[3][1] == false);
rawset(imgui, 'Checkbox', function (label, value)
    if (label == 'Next tick gains##resting') then value[1] = true; return true; end
    return false;
end);
saves = MOCK.saved;
frame();
rawset(imgui, 'Checkbox', nil);
check('the settings box enables and saves it', s.resting.show_next_gains and MOCK.saved > saves);
command('');

s.style.text_shadow = false;
s.resting.width = 640;
s.resting.show_label, s.resting.show_value = false, false;
s.resting.show_gains, s.resting.show_until_full, s.resting.show_each_full = false, false, false;
local view = { fill = 0.3, left = 5, gained_hp = 24, gained_mp = 30, next_hp = 25, next_mp = 33,
    next_estimated = false, full = false, has_mp = true, flash = 0 };
local function draw()
    hud.refresh(s);
    return capture(function () hud.begin_frame(); hud.draw_resting(view); hud.end_frame(); end);
end
local text, positions = draw();
local _, with_next = hud.element_size('resting');
check('next gains can be the only text in the card', text == 'next +25 HP +33 MP', text);
check('next-only text starts at the left padding', positions[text] and positions[text][1] == s.resting.x + 12);
local track_top;
local track_color = require('ui.theme').u32(s.style.track_color);
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'dl:AddRectFilled' and call[4] == track_color) then track_top = call[2][2]; end
end
check('next-only layout puts the bar first without an empty header', track_top == s.resting.y + 7
    and positions[text][2] > track_top);
s.resting.numbers_only = true;
text, positions = draw();
check('next-only numbers use one row with no empty header', positions[text][2] == s.resting.y + 7);
s.resting.numbers_only = false;
s.resting.show_next_gains = false;
text = draw();
local _, bar_only = hud.element_size('resting');
check('turning the only text off removes its row', text == '' and bar_only < with_next);
s.resting.show_next_gains, view.next_estimated = true, true;
text = draw();
check('uncertain gains carry est.', text == 'next +25 HP +33 MP est.', text);
s.resting.show_gains = true;
text, positions = draw();
check('last actual and next estimated amounts use separate rows', text == '+24 HP  +30 MP|next +25 HP +33 MP est.'
    and positions['next +25 HP +33 MP est.'][2] > positions['+24 HP  +30 MP'][2], text);
local _, both_height = hud.element_size('resting');
view.why = 8;
text = draw();
check('blocked healing hides gains and keeps the rows stable', text == ''
    and select(2, hud.element_size('resting')) == both_height, text);
view.why, view.next_hp, view.next_mp = nil, nil, nil;
text = draw();
check('unavailable next amounts preserve actual gains and row height', text == '+24 HP  +30 MP'
    and select(2, hud.element_size('resting')) == both_height, text);
view.full, view.next_hp, view.next_mp = true, 0, 0;
text = draw();
check('full vitals hide next gains without shrinking the card', text == '+24 HP  +30 MP'
    and select(2, hud.element_size('resting')) == both_height, text);
view.full, view.next_hp, view.next_mp = false, 25, 33;
s.resting.show_each_full = true;
view.hp_full_in, view.mp_full_in = 40, 60;
text, positions = draw();
check('individual full times sit below next gains', positions['HP full in 40s']
    and positions['HP full in 40s'][2] > positions['next +25 HP +33 MP est.'][2], text);
s.resting.show_each_full = false;

-- Exercise the full addon path before and after the first actual tick.
s.resting.show_gains, s.resting.show_next_gains = true, true;
MOCK.now = 100;
MOCK.fire('packet_in', MOCK.vitals_packet(1001, 900, 100, 0));
MOCK.player.status = 33;
MOCK.frame(0);
text = frame();
check('the model draws the first BLM75 gain before any tick', text == 'next +27 MP', text);
MOCK.now = 121;
MOCK.fire('packet_in', MOCK.vitals_packet(1001, 900, 127, 0));
text = frame();
check('the real tick displays27 actual and30 next', text == '+27 MP|next +30 MP', text);
check('the progress API still returns the actual gain', select(5, resting.progress(MOCK.now)) == 27);
MOCK.player.buffs = { 251 };
MOCK.frame(0.3);
text = frame();
check('unidentified food makes the integrated next gain estimated', text == '+27 MP|next +30 MP est.', text);
MOCK.player.buffs = { 8 };
MOCK.frame(0.3);
text = frame();
check('a real blocked effect hides predicted gains', text == '', text);

local error_message;
for _, line in ipairs(MOCK.printed) do
    if (line:find('Drawing stopped', 1, true)) then error_message = line; end
end
check('no drawing errors', error_message == nil, error_message);
out[#out + 1] = fails == 0 and 'ALL OK' or (fails .. ' FAILED');
return table.concat(out, '\n');
