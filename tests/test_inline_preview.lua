-- Samples stay inside their cards and never change live or saved timer state.
local preview, history = require('ui.preview'), require('ui.history');
local s = require('ui.defaults').make();
local out, fails = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then fails = fails + 1; end
end
local function draw(state)
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    preview.draw(s, state, true);
    MOCK.record_imgui = false;
    local words, fill, clips, balance, lowest = {}, {}, 0, 0, 0;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'dl:AddText') then words[#words + 1] = c[6]; end
        if (c[1] == 'dl:AddRectFilledMultiColor') then fill[#fill + 1] = c[3][1] - c[2][1]; end
        if (c[1] == 'dl:PushClipRect') then clips, balance = clips + 1, balance + 1; end
        if (c[1] == 'dl:PopClipRect') then balance = balance - 1; lowest = math.min(lowest, balance); end
    end
    return table.concat(words, '|'), fill, clips, balance == 0 and lowest == 0;
end
s.style.text_shadow, s.style.text_outline = false, false;
s.attack.label_text = string.rep('A very long timer label ', 5);
local saved = history.capture(s);
local text, fill, clips, balanced = draw('normal');
check('timer labels and values are clipped inside the sample cards', clips == 4 and balanced);
check('sample rendering leaves every saved value unchanged', history.equal(saved, s));
check('the normal sample includes enabled TP and recovery readouts', text:find('640 TP', 1, true) and text:find('+24 HP', 1, true));
s.attack.show_tp = false;
text = draw('normal');
check('hiding TP also hides its dependent sample lines', not text:find('640 TP', 1, true) and not text:find('rounds', 1, true));
s.resting.show_next_gains, s.resting.show_goal = true, true;
text = draw('blocked');
check('blocked resting samples show their reason without predicted recovery', text:find('diseased', 1, true)
    and not text:find('HP', 1, true) and not text:find('Next:', 1, true) and not text:find('until full', 1, true));
s.style.bar_drains = false;
local _, filled = draw('full');
s.style.bar_drains = true;
text, fill = draw('full');
check('ready and full sample bars stay full in drain mode', fill[1] == filled[1] and fill[2] == filled[2]);
s.attack.numbers_only, s.resting.numbers_only = true, true;
local _, no_bars = draw('normal');
check('text-only samples omit both timer bars', #no_bars == 0);

local height_settings = require('ui.defaults').make();
height_settings.style.scale = 1;
height_settings.style.text_outline, height_settings.style.text_shadow = false, false;
height_settings.attack.bar_height, height_settings.resting.bar_height = 2, 2;
local function dimensions()
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    preview.draw(height_settings, 'normal', true);
    MOCK.record_imgui = false;
    local cards, fonts = {}, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'Dummy') then cards[#cards + 1] = call[2]; end
        if (call[1] == 'dl:AddText') then fonts[call[6]] = call[3]; end
    end
    return cards, fonts;
end
local normal_cards, normal_fonts = dimensions();
height_settings.resting.height_scale = 0.5;
local short_cards, short_fonts = dimensions();
check('sample height changes only the selected timer', short_cards[1][2] == normal_cards[1][2]
    and short_cards[2][2] == normal_cards[2][2] * 0.5);
check('sample vertical resizing keeps both card widths', short_cards[1][1] == normal_cards[1][1]
    and short_cards[2][1] == normal_cards[2][1]);
check('sample text follows its own timer height', short_fonts.RESTING == normal_fonts.RESTING * 0.5
    and short_fonts['AUTO ATTACK'] == normal_fonts['AUTO ATTACK']);
check('sample resizing keeps the saved bar thickness', height_settings.resting.bar_height == 2);
height_settings.resting.numbers_only = true;
height_settings.resting.height_scale = 1;
normal_cards = dimensions();
height_settings.resting.height_scale = 2;
local tall_cards = dimensions();
check('text-only samples resize vertically too', tall_cards[2][2] == normal_cards[2][2] * 2);

s.attack.enabled, s.resting.enabled = false, false;
draw('normal');
local off = false;
for _, c in ipairs(MOCK.imgui_calls) do
    if (c[1] == 'TextUnformatted' and c[2] == 'All timers are off in this sample.') then off = true; end
end
check('a layout with no timers explains its empty sample', off);
out[#out + 1] = fails == 0 and 'ALL PASSED' or fails .. ' FAILED';
return table.concat(out, '\n');
