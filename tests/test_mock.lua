-- The mock itself. Its font size and frame height, chat lines with their color codes taken out, and a
-- command split into words the way Ashita splits it.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

local imgui = require('imgui');

-- Font size and frame height ------------------------------------------------------------------------
local function sizes()
    return ('%s %s'):format(tostring(imgui.GetFontSize()), tostring(imgui.GetFrameHeight()));
end

check('with no font pushed it is Ashita\'s 18, and a frame is 26', sizes() == '18 26', sizes());
imgui.PushFont('font', 24);
check('a font pushed at 24 is 24, and a frame is 32', sizes() == '24 32', sizes());
imgui.PushFont('font');
check('a font pushed with no size keeps 24', sizes() == '24 32', sizes());
imgui.PushFont('font', 0);
check('a size of 0 keeps 24 too', sizes() == '24 32', sizes());
imgui.PushFont('font', 12);
check('a font pushed at 12 is 12, and a frame is 20', sizes() == '12 20', sizes());
imgui.PopFont();
imgui.PopFont();
imgui.PopFont();
check('popping back gives 24', sizes() == '24 32', sizes());
imgui.PopFont();
check('popping them all gives 18 again', sizes() == '18 26', sizes());
check('the stack is empty after', #MOCK.font_stack == 0, #MOCK.font_stack);

-- CalcTextSize measures 14 high with no font pushed, the way the other tests expect.
local _, height = imgui.CalcTextSize('abc');
check('CalcTextSize with no font pushed is 14 high', height == 14, height);

-- Chat lines ----------------------------------------------------------------------------------------
-- A line colored the way Ashita's chat.lua does it. 81, 6 and 106 are its header and message colors,
-- and 1 goes back to the normal color. \31 picks from the second color table.
local colored = '\30\81[\30\6cadence\30\81]\30\1 \30\106The timers are back. \31\200Done.';
local plain = '[cadence] The timers are back. Done.';

-- A line with its control and high bytes written as numbers, so a failed check prints it readably.
local function shown(line)
    return line and (line:gsub('[%c\128-\255]', function (c) return ('\\%d'):format(c:byte()); end));
end

local printed, raw = #MOCK.printed, #MOCK.printed_raw;
print(colored);
check('one line goes in each list', #MOCK.printed == printed + 1 and #MOCK.printed_raw == raw + 1,
    ('%d %d'):format(#MOCK.printed - printed, #MOCK.printed_raw - raw));
check('the printed line has no color codes', MOCK.printed[#MOCK.printed] == plain, shown(MOCK.printed[#MOCK.printed]));
check('the raw line keeps them all', MOCK.printed_raw[#MOCK.printed_raw] == colored,
    shown(MOCK.printed_raw[#MOCK.printed_raw]));
check('MOCK.plain does the same', MOCK.plain(colored) == plain, shown(MOCK.plain(colored)));

print('[cadence] No colors here, 30 and 31 are just numbers.');
check('a line with no codes comes through as it is',
    MOCK.printed[#MOCK.printed] == '[cadence] No colors here, 30 and 31 are just numbers.', MOCK.printed[#MOCK.printed]);

-- A test can empty MOCK.printed. The raw lines keep coming in their own list.
MOCK.printed = {};
raw = #MOCK.printed_raw;
print('\30\81after');
check('printing goes on into an emptied list', #MOCK.printed == 1 and MOCK.printed[1] == 'after', shown(MOCK.printed[1]));
check('and into the raw list too', #MOCK.printed_raw == raw + 1 and MOCK.printed_raw[raw + 1] == '\30\81after',
    shown(MOCK.printed_raw[raw + 1]));

-- The raw list can be emptied too.
MOCK.printed_raw = {};
print('\30\81again');
check('printing goes on into an emptied raw list', #MOCK.printed_raw == 1 and MOCK.printed_raw[1] == '\30\81again',
    shown(MOCK.printed_raw[1]));

-- Splitting a command -------------------------------------------------------------------------------
-- The same as Ashita's sugar/string.lua. Words in quotes stay together, without the quotes.
local function split(command) return table.concat(command:args(), '|'); end
check('words split at spaces, however many', split('/cadence  attack tp off ') == '/cadence|attack|tp|off',
    split('/cadence  attack tp off '));
check('words in quotes stay together', split('/cadence profile rename "Solo BLM" "Nuker 2"')
    == '/cadence|profile|rename|Solo BLM|Nuker 2', split('/cadence profile rename "Solo BLM" "Nuker 2"'));
check('a quote right after a word is part of it', split('/cadence a"b c') == '/cadence|a"b|c', split('/cadence a"b c'));
check('"" is an empty word', #('/cadence profile save ""'):args() == 4 and ('/cadence profile save ""'):args()[4] == '');
check('a quote that never closes drops everything after it',
    split('/cadence profile load "Solo BLM') == '/cadence|profile|load', split('/cadence profile load "Solo BLM'));
check('the last word is kept', split('x y') == 'x|y' and split('x') == 'x' and split('') == '', split('x y'));

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
