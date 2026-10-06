--[[
    The settings window, opened with /cadence.

    Changes show up right away. Sliders, color pickers and text boxes save when you let go of them.
    Dragging one doesn't write the settings file every frame. You can move and resize the window,
    and it opens where you left it. Its sections sit in two columns when there's room and stack into
    one when there isn't. Every setting has a (?) that explains it. The window draws in its own font
    at its own size, and its layout grows with a font bigger or wider than Ashita's at 18 px. Its
    font, corners, spacing and colors are on its Window and Window colors tabs. cadence's chat colors
    are on the Window tab too. The Profiles tab saves and loads named copies of your settings, and
    links them to your main jobs.
]]

local imgui         = require('imgui');
local theme         = require('ui.theme');
local hud           = require('ui.hud');
local presets       = require('ui.presets');
local defaults      = require('ui.defaults');
local window_font   = require('ui.window_font');
local chat_colors   = require('ui.chat_colors');
local profiles      = require('ui.profiles');
local sound         = require('ui.sound');
local shared_layout = require('core.shared_layout');
local player        = require('core.player');

local settings_window = {};

local ASHITA_FONT = hud.ASHITA_FONT;

local WINDOW_FLAGS = bit.bor(ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoSavedSettings);
-- While you hold Shift to see through the window, clicks go through it to the timers under it.
local PEEK_FLAGS = bit.bor(WINDOW_FLAGS, ImGuiWindowFlags_NoInputs);
local COLOR_FLAGS = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar,
    ImGuiColorEditFlags_AlphaPreviewHalf);
-- A swatch on the Window colors tab names its color when you point at it, instead of ImGui's own tip.
local SWATCH_FLAGS = bit.bor(COLOR_FLAGS, ImGuiColorEditFlags_NoTooltip);
-- A chat color's swatch only shows the color. It has no tip and can't be dragged onto another swatch.
local CHAT_SWATCH_FLAGS = bit.bor(ImGuiColorEditFlags_NoTooltip, ImGuiColorEditFlags_NoDragDrop);

-- Layout in pixels at Ashita's 18 px font. px() grows each one with a bigger or wider window font. A
-- column of settings needs 420, and the second control on a line starts 228 in. A tip wraps at 300. The
-- list of profiles is 130 tall. Each job link's list starts 48 in from its job's name. The window can
-- shrink to 240 tall.
local BASE_FONT_SIZE = 18;
local COLUMN_WIDTH   = 420;
local SECOND_COLUMN  = 228;
local CONTROL_WIDTH  = 190;
local CHIP_WIDTH     = 52;
local TIP_WIDTH      = 300;
local LIST_HEIGHT    = 130;
local JOB_LIST_AT    = 48;
local MIN_HEIGHT     = 240;

-- Words from the left column of the Timers and Look tabs. A font that draws them wider than Ashita's
-- font does at 18 px grows the layout by that much, like a bigger font would.
local WIDTH_SAMPLE = 'Almost ready Time until full Text outline';

-- Pixels that stay the same at every font size. Columns sit 24 apart, from the theme's cell padding.
-- The theme pads a button or dropdown 8 on each side and puts 8 between the things on a line. ImGui puts
-- 4 between a checkbox or dropdown and its label. A chat color's swatch sits that close to its dropdown.
local COLUMN_GAP     = 24;
local BUTTON_PADDING = 16;
local ITEM_GAP       = 8;
local BOX_GAP        = 4;

-- The tabs take 5 either side of their names instead of 8, so more of them fit across the window. ImGui
-- makes each tab 1 wider than its name and padding, and puts 4 between tabs.
local TAB_PADDING = { 5, 4 };
local TAB_EXTRA   = 1;
local TAB_GAP     = 4;

-- How strong a timer's settings are drawn while the timer is off.
local OFF_ALPHA = 0.5;

-- How strong the whole window is drawn while you hold Shift to see through it.
local PEEK_ALPHA = 0.25;

-- Around its columns the window needs 28 for its padding and 14 for ImGui's scrollbar, with 2 more
-- to spare. It gets two columns once it's wide enough for both.
local WINDOW_EDGES = 44;
local MAX_SIZE = { FLT_MAX, FLT_MAX };
local SECTION_FLAGS = ImGuiTableFlags_SizingStretchSame;

local RANGES = defaults.RANGES;

-- A label box has room for one more, the zero ImGui puts after the text.
local LABEL_BUFFER = defaults.LABEL_LENGTH + 1;

-- What each (?) says. ImGui can break a tip's line right after a period, comma, ! or ? or a double quote.
-- So none of those sits right between two other characters, or the next line could start with a lone period.
local TIPS = {
    attack_timer   = 'Turns the auto attack timer on or off. It shows up while you\'re engaged.',
    attack_value   = 'Shows the seconds until your next attack, then "ready" once you can attack.',
    attack_delay   = 'Shows the weapon delay the timer is using. Until your own attacks show the real one, it\'s a '
        .. 'guess marked est.',
    tp             = 'Shows your TP under the bar. Your TP turns this color at 1000.',
    tp_rounds      = 'Shows about how many rounds until 1000 TP. It counts the TP your hits give you and what being '
        .. 'hit or Regain has been adding lately.',
    numbers_only   = 'Hides the bar and shows just the numbers.',
    width          = 'How wide the timer is. You can also hold Shift and drag its right edge.',
    bar_height     = 'How thick the bar is. You can also hold Shift and drag its bottom edge.',
    fill           = 'The bar\'s colors, from empty to full.',
    attack_ready   = 'The bar\'s color once you can attack.',
    attack_almost  = 'The bar turns this color just before your next attack, so you can line up a weapon skill.',
    almost_mark    = 'Puts a small mark on the bar where the almost ready color starts.',
    attack_at      = 'How many seconds before your attack the almost ready color starts.',
    reason         = 'Says "too far" or "not facing" and dims the bar as soon as you step out of reach or turn '
        .. 'away from the monster you\'re fighting. Once the bar is full, the server\'s own message wins.',
    why            = 'While a spell, ranged attack or item holds your auto attack, the bar dims and says why instead '
        .. 'of the seconds, like "casting" for a spell. Sleep, stun and so on do the same, like "asleep" for sleep.',

    resting_timer  = 'Turns the resting timer on or off. It shows up while you /heal.',
    resting_value  = 'Shows the seconds until your next resting tick.',
    gains          = 'Shows what your last tick restored, like +24 HP +31 MP.',
    until_full     = 'Shows how long until your HP and MP are both full, like "full in 28s" on the timer.',
    each_full      = 'Adds a line under the bar that says when your HP and your MP will each be full.',
    hide_when_full = 'Hides the resting timer once your HP and MP are full.',
    full_color     = 'The bar\'s color once your HP and MP are full.',
    flash          = 'Flashes the timer in this color when a tick lands.',
    flash_length   = 'How long the flash lasts.',
    cant_heal      = 'While disease, plague or a curse stops your ticks healing, the bar dims and says '
        .. '"diseased" or "plagued" or "cursed" instead of the seconds. The gains and full times hide until ticks '
        .. 'heal you again.',
    sound          = 'Plays a sound once resting fills your HP and MP. Tick the box to turn it on. Two sounds come '
        .. 'with cadence. To add your own, put .mp3 or .wav files in config\\addons\\cadence\\sounds.',
    sound_refresh  = 'Looks in the sounds folder again, so a file you just put there shows up in the list.',
    sound_volume   = 'How loud the sound plays, from silent at 0 to full at 100.',
    play_sound     = 'Plays the sound now, at this volume, so you can hear it. It works with the box off too.',

    hide_on_map    = 'Hides the timers and this window while the map is open. The widescan list doesn\'t count.',
    hide_events    = 'Hides the timers and this window during cutscenes and NPC conversations.',
    hide_ui        = 'Hides the timers and this window while the game\'s interface is hidden with Scroll Lock.',
    drains         = 'Bars start full and empty out, instead of filling up.',
    show_timers    = 'Brings the timers back. Typing /cadence hide again or /cadence show does the same.',

    enemy_timer    = 'Shows when the monster you\'re fighting will attack next. It can\'t see a TP move coming.',
    follows        = 'Which monster the timer follows. "My target first" follows your target, and whoever is '
        .. 'hitting you when your target isn\'t fighting.',
    keep_last      = 'Keeps the timer on the monster it was following while you target a party member, an NPC or '
        .. 'nothing. It lets go once that monster dies, stops fighting or goes quiet for 10 s, longer for a slow one.',
    attached       = 'Puts the enemy timer right under your auto attack timer as a slim strip that moves with it. '
        .. 'With the auto attack timer off, it sits at its own spot.',
    enemy_value    = 'Shows the seconds until the monster\'s next attack, then "ready" when it can attack. It shows '
        .. '"--" once it\'s overdue by a whole attack, like while the monster is asleep or chasing you.',
    enemy_name     = 'Shows the monster\'s name.',
    enemy_delay    = 'Shows the monster\'s delay between attacks. Until it has attacked a few times, it\'s a guess '
        .. 'marked est.',
    enemy_holds    = 'While the monster readies a TP move or casts a spell, the timer says "TP move" or '
        .. '"casting" instead of the seconds. It counts down again about 2 s after the move or spell ends.',
    on_you         = 'The enemy timer\'s name and its left stripe turn this color when the monster\'s last attack '
        .. 'was on you. It\'s greyed out following "Whoever hits me" or with neither the name nor the stripe showing.',
    enemy_effects  = 'Shows slow, elegy, haste or hundred fists while one is on the monster. The timer counts them '
        .. 'either way. Someone else\'s effect gets a question mark once it might have worn off.',
    enemy_width    = 'How wide the timer is. You can also hold Shift and drag its right edge. Attached, it\'s '
        .. 'as wide as the auto attack timer.',
    enemy_bar      = 'How thick the bar is. You can also hold Shift and drag its bottom edge, except while it '
        .. 'hangs right under the auto attack timer.',
    enemy_ready    = 'The bar\'s color once the monster can attack.',
    enemy_almost   = 'The bar turns this color just before the monster attacks.',
    enemy_at       = 'How many seconds before the monster\'s attack the almost ready color starts.',

    undo           = 'Puts back the look you had before your last preset or Reset look. It goes back one step.',
    preset         = 'Sets the timer and chat colors, card, text shadow and corners. Change one and it says Custom and '
        .. 'the preset you started from. Colorblind safe stays clear for red-green and blue-yellow colorblindness.',
    window_look    = 'Picking a preset also sets this window\'s colors, corners and spacing, the ones on the Window '
        .. 'and Window colors tabs. Off, presets leave this window as it is.',
    scale          = 'Makes the timers bigger or smaller.',
    text_size      = 'The size of the numbers. At auto, the names and the small text are a little smaller.',
    detail_size    = 'How big the small text is, like the delay next to AUTO ATTACK, the gains next to RESTING and '
        .. 'the lines under the bars. At auto it\'s a little smaller than the numbers and grows with Text size.',
    font           = 'The font the timers use. Ashita is the game\'s own pixel font. A .ttf or .otf you put in '
        .. 'config\\addons\\cadence\\fonts shows up here the next time cadence loads.',
    rounding       = 'The timers\' corners. At 0 they\'re square, like the Phoenix site. Higher numbers round them '
        .. 'off.',
    show_labels    = 'Shows the name of each timer, like AUTO ATTACK. The box in front of each label below hides '
        .. 'just that one.',
    label_size     = 'How big the timer names are. At auto they\'re a little smaller than the numbers and grow '
        .. 'with Text size. Scale makes them bigger or smaller on top of this.',
    attack_label   = 'Your own name for the auto attack timer, like AA. Leave it empty for AUTO ATTACK. Untick the '
        .. 'box in front to hide the name.',
    resting_label  = 'Your own name for the resting timer. Leave it empty for RESTING. Untick the box in front to '
        .. 'hide the name.',
    enemy_label    = 'Your own name for the enemy timer. Leave it empty for ENEMY ATTACK, or ENEMY when '
        .. 'it\'s attached. Untick the box in front to hide the name. It\'s the timer\'s name, not the monster\'s.',
    background     = 'The card behind each timer.',
    border         = 'A thin line around each card.',
    accent         = 'The stripe down the left side of each card.',
    label_color    = 'The color of the timer names.',
    value_color    = 'The color of the seconds on the right.',
    detail_color   = 'The color of the small text next to the names.',
    track_color    = 'The color of the empty part of each bar.',
    text_shadow    = 'A dark shadow behind the text, so it reads on bright backgrounds.',
    text_outline   = 'A dark edge all the way around the text, so it reads on snow, sand and other bright ground. '
        .. 'You can pick its color. It works with or without the shadow.',
    locked         = 'Stops Shift and drag from moving or resizing the timers.',
    see_through    = 'While you hold Shift, this window goes see-through and clicks pass through it, so you can drag '
        .. 'a timer under it. Shift and drag doesn\'t move the window then. It stays solid while you type.',
    shared_spot    = 'The auto attack and resting timers share one spot, since you can\'t fight while you\'re resting.',
    one_layout     = 'Every character uses this setup. Turning it off keeps this one\'s layout, and the others go '
        .. 'back to their own.',
    reset_spots    = 'Puts the timers back where they started. On a screen too short for them, they start higher up.',
    reset_look     = 'Puts sizes, timer and chat colors, the card, corners, text shadow and outline, labels, font, '
        .. 'Numbers only, Ready mark, Drain instead of fill and this window\'s look and font back to default.',

    window_font    = 'This window\'s font. The timers\' font is on the Look tab. A wide one like Consolas stacks the '
        .. 'sections, so the window may scroll. A preset never changes it. No addon can change the chat log\'s font.',
    window_size    = 'How big this window\'s text is. Its layout grows with a bigger font, so its sections may stack '
        .. 'into one column. A preset never changes it.',
    window_corners = 'How round the corners of this window and its boxes are. At 0 they\'re square. A preset sets it '
        .. 'while Window matches the look is on.',
    window_spacing = 'The space between this window\'s rows. A preset sets it while Window matches the look is on.',

    tag_brackets   = 'The brackets of the [cadence] tag at the start of each line cadence prints in chat. A preset '
        .. 'sets all three chat colors.',
    tag_word       = 'The word cadence inside the tag.',
    replies        = 'cadence\'s answers to your commands, after the tag.',
    chat_sample    = 'Prints a line in chat in your chat colors. The swatches here only come close to the shades the '
        .. 'game shows.',

    profiles       = 'Every character shares your profiles. A profile holds every setting, the timers\' spots too, '
        .. 'but not where this window sits, its size or your job links. Pick one in the list to use the buttons on it.',
    profile_name   = 'Type a name here for Save as new or Rename. Picking a profile in the list puts its name here.',
    save_new       = 'Saves your settings as a new profile with the name in the box.',
    overwrite      = 'Saves your settings over the profile you picked.',
    load           = 'Loads the profile you picked. Undo can\'t take it back, so save your settings first if you want '
        .. 'to keep them.',
    rename         = 'Gives the profile you picked the name in the box. Your job links to it follow.',
    delete         = 'Deletes the profile you picked, and your job links to it. It can\'t be brought back.',
    job_links      = 'Pick a profile for a main job, and it loads each time you change to that job and zone. Each '
        .. 'character has its own links. Profiles don\'t hold them, and /cadence reset all clears them.',
};

-- What each row of the Window colors tab paints, by the row's name. Its swatches go in the same order.
local WINDOW_COLOR_TIPS = {
    ['Text']           = 'Most of this window\'s text, then the faded text, like the subtitle and the question mark after '
        .. 'each setting.',
    ['Headings']       = 'The section headings, like SIZE, then the line under each one.',
    ['Notes']          = 'The short notes some sections show, like when a timer is off.',
    ['Messages']       = 'What the Profiles tab says after something works, then when something doesn\'t. The note '
        .. 'about a font that won\'t load takes the second color too.',
    ['Text boxes']     = 'The highlight behind text you select in a text box, like a timer\'s label, then the text '
        .. 'cursor.',
    ['Window']         = 'This window\'s background, then the line around it.',
    ['Title bar']      = 'The title bar while you\'re using this window, then while you\'re using another one.',
    ['Resize corner']  = 'The corner at the bottom right you drag to resize this window. Normally, under the mouse and '
        .. 'while you drag it.',
    ['Resize edges']   = 'This window\'s edges under the mouse, then while you drag one to resize the window.',
    ['Scrollbar']      = 'The scrollbar\'s track, then the bar normally, under the mouse and while you drag it. It '
        .. 'only shows when a tab doesn\'t fit.',
    ['Boxes']          = 'Checkboxes, text boxes, sliders and dropdowns. Normally, under the mouse and while you click '
        .. 'one.',
    ['Check marks']    = 'The tick in a checkbox. It also outlines a swatch while you drag a color onto it.',
    ['Slider handles'] = 'The handle you drag on a slider, normally and while you drag it.',
    ['Buttons']        = 'The buttons, like Reset positions. Normally, under the mouse and while you press one. An OFF '
        .. 'chip you press takes the pressed color too.',
    ['ON chips']       = 'A timer\'s ON chip, then its words. Under the mouse it lights up a little toward Resize '
        .. 'edges, hovered. An OFF chip under the mouse shows this color faint.',
    ['Dropdowns']      = 'An open dropdown and these tips, then the row you have, the row under the mouse and the row '
        .. 'you click.',
    ['Tabs']           = 'The tabs normally and under the mouse, then the tab you\'re on and the line over it.',
    ['Unfocused tabs'] = 'The tabs normally, the tab you\'re on and the line over it, while you\'re using another window.',
};

-- Each Window colors swatch's id, made once. The ## keeps ImGui from writing anything next to it.
local SWATCH_IDS = {};
for _, entry in ipairs(theme.WINDOW_COLORS) do
    SWATCH_IDS[entry.key] = '##' .. entry.key;
end

-- The swatch of each chat color, and its id in a dropdown, by its code. The swatch in front of each
-- chat color's dropdown has an id by the part's key. All made once.
local CHAT_SWATCHES, CHAT_SWATCH_IDS, CHAT_PART_IDS = {}, {}, {};
for _, entry in ipairs(chat_colors.PALETTE) do
    CHAT_SWATCHES[entry.code] = theme.hex(entry.swatch);
    CHAT_SWATCH_IDS[entry.code] = '##chat' .. entry.code;
end
for _, part in ipairs(chat_colors.PARTS) do
    CHAT_PART_IDS[part.key] = '##chat_' .. part.key;
end

-- Each job link's list id, made once.
local JOB_IDS = {};
for i, job in ipairs(defaults.JOBS) do
    JOB_IDS[i] = '##' .. job;
end

-- The job link choice that loads nothing.
local NO_LINK = '(none)';

-- What the Sound list shows before you pick a file, and in its open list when the folder has none.
local NO_SOUND = '(none)';
local NO_SOUND_FILES = 'No .mp3 or .wav files in the sounds folder yet.';

-- The hide tips for a game version that doesn't let cadence see the map or the interface.
TIPS.cant_see_map = TIPS.hide_on_map .. ' This game version doesn\'t let cadence see the map, so it\'s greyed out.';
TIPS.cant_see_ui  = TIPS.hide_ui .. ' This game version doesn\'t let cadence see the interface, so it\'s greyed out.';

local FOOTER = 'Hold Shift and drag a timer to move it, or drag its edge to resize it. While this window is open, '
    .. 'a timer with nothing going on shows sample values. Ctrl+click a slider to type a value.';

local WINDOW_COLORS_NOTE = 'Point at a swatch to see which color it is, and click it to pick a new one. While Window '
    .. 'matches the look is on, a preset sets all of them.';

-- The Window colors tab's second column starts at this heading.
local SECOND_COLORS = 'BOXES AND BUTTONS';

local open = { false };
local place_now = false;  -- True when the next frame moves the window to its saved spot and size.
local stacked = false;    -- True while a tab's sections are in one column.
local window_alpha = 1;   -- How strong the window is drawn this frame.
local busy = false;       -- True while you're using something in the window, like a slider or a text box.
local look = nil;         -- The window's look this frame, your window_style settings.
local scale = 1;          -- How much the layout grows this frame, never under 1.
local wider = 1;          -- How much wider the window's font draws than Ashita's font at 18 px.
local wider_font = nil;   -- The window font and size `wider` was measured at.
local wider_size = nil;
local two_columns_at = 0; -- How wide the window has to be this frame for two columns.
local result = { changed = false, save = false, reset_positions = false, reset_look = false, share_layout = nil,
    show_timers = false, sample = false, links = false, sound_picked = false, play_sound = false };

-- Reused tables for ImGui widgets that edit a value in place, and sizes and spots set each frame.
local number = { 0 };
local flag = { false };
local text = { '' };
local spot = { 0, 0 };
local extent = { 0, 0 };
local min_size = { 0, 0 };

-- An ON/OFF chip's size. Its width follows the font size, and a height of 0 lets ImGui pick it.
local chip_size = { CHIP_WIDTH, 0 };

-- A chat color's swatch in front of its dropdown is as tall as the dropdown, which ImGui picks with a
-- size of 0. In the open list each swatch is as tall as a line of text, so it sits level with its name.
local CHAT_SWATCH_SIZE = { 0, 0 };
local line_swatch = { 0, 0 };

-- What the window says about a font that didn't load, made once for each font.
local font_notes = {};

-- The Profiles tab's name box, the profile picked in its list, and what its last button said and
-- whether that worked. The list is as wide as its column, and its height follows the font.
local profile_name = { '' };
local picked = nil;
local status = nil;
local status_ok = true;
local list_size = { -1, 0 };

-- What a job link's list shows for a profile that isn't there anymore, made once for each name.
local gone_names = {};

-- The ON and OFF chips under the mouse, worked out from your window colors each frame. An OFF chip has
-- no fill.
local chip_lit = { 0, 0, 0, 1 };
local chip_faint = { 0, 0, 0, 0 };
local CLEAR = { 0, 0, 0, 0 };

function settings_window.is_open()
    return open[1];
end

-- Opening the window reads profiles.json again, since another character can change it. It looks in the
-- sounds folders again too.
function settings_window.set_open(value)
    local opening = value and not open[1];
    open[1] = value;
    if (opening) then
        profiles.refresh();
        sound.refresh();
        status = nil;
    end
end

local function mark_changed(save_now)
    result.changed = true;
    if (save_now) then
        result.save = true;
    end
end

local function round(value)
    return math.floor(value + 0.5);
end

-- A layout size in pixels, grown with the window's font size.
local function px(size)
    return round(size * scale);
end

-- A (?) after a setting. Hovering it shows what the setting does, even when the setting is greyed out.
local function help(tip)
    imgui.SameLine();
    imgui.TextDisabled('(?)');
    if (imgui.IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled)) then
        -- The tip is drawn at full strength, even over a timer that's off.
        imgui.PushStyleVar(ImGuiStyleVar_Alpha, 1);
        imgui.BeginTooltip();
        imgui.PushTextWrapPos(px(TIP_WIDTH));
        imgui.TextUnformatted(tip);
        imgui.PopTextWrapPos();
        imgui.EndTooltip();
        imgui.PopStyleVar(1);
    end
end

-- Section heading with a hairline under it, like the headings on phoenix-xi.com. With a tip, a (?)
-- follows it.
local function heading(title, tip)
    imgui.Spacing();
    imgui.TextColored(look.headings, title);
    if (tip ~= nil) then
        help(tip);
    end
    imgui.Separator();
end

-- Text that wraps at the edge of its column, or of the window outside the columns. It's in the notes
-- color unless you give it a color.
local function note(words, color)
    imgui.PushStyleColor(ImGuiCol_Text, color or look.notes);
    imgui.PushTextWrapPos(0);
    imgui.TextUnformatted(words);
    imgui.PopTextWrapPos();
    imgui.PopStyleColor(1);
end

-- The ON/OFF chip that turns a timer on or off. Filled when on, outlined when off, like the site's filter
-- chips. Pressing an OFF chip fills it like any pressed button, so its words still read.
local function toggle_chip(id, timer)
    local on = timer.enabled;
    imgui.PushStyleColor(ImGuiCol_Button, on and look.on_chips or CLEAR);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, on and chip_lit or chip_faint);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, on and look.on_chips or look.buttons_pressed);
    imgui.PushStyleColor(ImGuiCol_Text, on and look.on_chip_text or look.headings);
    imgui.PushStyleColor(ImGuiCol_Border, on and look.on_chips or look.border);
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);
    if (imgui.Button((on and 'ON' or 'OFF') .. '##' .. id, chip_size)) then
        timer.enabled = not on;
        mark_changed(true);
    end
    imgui.PopStyleVar(1);
    imgui.PopStyleColor(5);
end

-- A timer's heading with its (?) and its ON/OFF chip at the right edge of the column. While the timer
-- is off, a line under it says so.
local function heading_with_toggle(title, id, timer, tip)
    imgui.Spacing();
    local x = imgui.GetCursorPosX();
    local width = imgui.GetContentRegionAvail();
    -- Lines the heading up with the text inside the chip next to it.
    imgui.AlignTextToFramePadding();
    imgui.TextColored(look.headings, title);
    help(tip);
    imgui.SameLine();
    imgui.SetCursorPosX(x + width - chip_size[1]);
    toggle_chip(id, timer);
    imgui.Separator();
    if (not timer.enabled) then
        note('This timer is off, so it isn\'t on screen.');
    end
end

--[[
    While a timer is off, its other settings are drawn faint. They still work, so you can set it
    up before turning it on. A color picker or dropdown opened from them would be faint too, so they're
    drawn at full strength while one is open. Returns true when it faded them, for end_fade.
]]
local function fade_if_off(timer)
    if (timer.enabled or imgui.IsPopupOpen('', ImGuiPopupFlags_AnyPopupId)) then
        return false;
    end
    imgui.PushStyleVar(ImGuiStyleVar_Alpha, window_alpha * OFF_ALPHA);
    return true;
end

local function end_fade(faded)
    if (faded) then
        imgui.PopStyleVar(1);
    end
end

-- Starts a tab's columns. Two side by side when the window is wide enough. Otherwise one, and the
-- sections stack. The check goes by the whole window's width. The room left inside shrinks when a
-- scrollbar shows up, and that would flip it back and forth. Each imgui.TableNextColumn() moves on
-- to the next section.
local function begin_sections(id)
    stacked = imgui.GetWindowSize() < two_columns_at;
    return imgui.BeginTable(id, stacked and 1 or 2, SECTION_FLAGS);
end

-- Moves on to a tab's second section. Stacked, that starts a new table row. A table row skips the gap
-- an item gets outside a table, so the gap goes back in here.
local function next_section()
    imgui.TableNextColumn();
    if (stacked) then
        imgui.Spacing();
    end
end

-- The box for an on/off setting, with no (?) after it.
local function tick_box(label, table_, key)
    flag[1] = table_[key];
    if (imgui.Checkbox(label, flag)) then
        table_[key] = flag[1];
        mark_changed(true);
    end
end

local function checkbox(label, table_, key, tip)
    tick_box(label, table_, key);
    help(tip);
end

-- A checkbox that's greyed out while `off` is true. Its (?) still works.
local function checkbox_unless(off, label, table_, key, tip)
    imgui.BeginDisabled(off);
    tick_box(label, table_, key);
    imgui.EndDisabled();
    help(tip);
end

-- Runs a slider on one setting, from its range in defaults.RANGES. `draw` is imgui.SliderInt or
-- imgui.SliderFloat. It's greyed out while `off` is true. Its (?) still works. It's as wide as the
-- other controls unless `width` says otherwise.
local function slider(draw, label, table_, key, range, format, tip, off, width)
    imgui.BeginDisabled(off == true);
    number[1] = table_[key];
    imgui.SetNextItemWidth(width or px(CONTROL_WIDTH));
    if (draw(label, number, range[1], range[2], format, ImGuiSliderFlags_AlwaysClamp)) then
        table_[key] = number[1];
        mark_changed(false);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        result.save = true;
    end
    imgui.EndDisabled();
    help(tip);
end

local function whole_slider(label, table_, key, range, format, tip, off, width)
    slider(imgui.SliderInt, label, table_, key, range, format, tip, off, width);
end

local function float_slider(label, table_, key, range, format, tip, off)
    slider(imgui.SliderFloat, label, table_, key, range, format, tip, off);
end

-- A color swatch that opens a picker. The settings color table is edited in place. A color dragged onto
-- the swatch never holds it the way the picker does, so it saves right away.
local function color(label, table_, key, flags)
    if (imgui.ColorEdit4(label, table_[key], flags or COLOR_FLAGS)) then
        mark_changed(not imgui.IsItemActive());
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        result.save = true;
    end
end

local function color_with_help(label, table_, key, tip)
    color(label, table_, key);
    help(tip);
end

-- A checkbox with its color swatch right after the label.
local function checkbox_with_color(label, table_, flag_key, color_key, tip, off)
    imgui.BeginDisabled(off == true);
    tick_box(label, table_, flag_key);
    imgui.SameLine();
    color('##' .. color_key .. label, table_, color_key);
    imgui.EndDisabled();
    help(tip);
end

--[[
    A timer's label. The box in front shows or hides its name, and is greyed out while Show labels is
    off. The text box is narrower by that much, so the words after it line up with the sliders above.
    Empty shows the default, greyed out.
]]
local function label_box(label, switch_id, element, default, tip, labels_off)
    local x = imgui.GetCursorPosX();
    imgui.BeginDisabled(labels_off);
    tick_box(switch_id, element, 'show_label');
    imgui.EndDisabled();
    imgui.SameLine();
    text[1] = element.label_text;
    imgui.SetNextItemWidth(px(CONTROL_WIDTH) - (imgui.GetCursorPosX() - x));
    if (imgui.InputTextWithHint(label, default, text, LABEL_BUFFER)) then
        element.label_text = text[1];
        mark_changed(false);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        result.save = true;
    end
    help(tip);
end

-- The width and bar height sliders for the auto attack or resting timer. Bar height is greyed out while
-- it shows just numbers.
local function size_sliders(id, element)
    whole_slider('Width##' .. id, element, 'width', RANGES[id].width, '%d px', TIPS.width);
    whole_slider('Bar height##' .. id, element, 'bar_height', RANGES[id].bar_height, '%d px', TIPS.bar_height,
        element.numbers_only);
end

-- Two color swatches for a bar's gradient, then a picker for its end state.
local function bar_colors(id, element, end_key, end_label, end_tip)
    color('##' .. id .. '_start', element, 'fill_start');
    imgui.SameLine();
    color('##' .. id .. '_end', element, 'fill_end');
    imgui.SameLine();
    imgui.TextUnformatted('Fill');
    help(TIPS.fill);
    imgui.SameLine(px(SECOND_COLUMN));
    color_with_help(end_label .. '##' .. id, element, end_key, end_tip);
end

-- Numbers only, and the mark on the bar where the almost ready color starts.
local function bar_toggles(id, element)
    checkbox('Numbers only##' .. id, element, 'numbers_only', TIPS.numbers_only);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox_unless(not element.almost_ready or element.numbers_only, 'Ready mark##' .. id, element, 'almost_mark',
        TIPS.almost_mark);
end

local function draw_attack_section(attack)
    heading_with_toggle('AUTO ATTACK TIMER', 'attack', attack, TIPS.attack_timer);
    local faded = fade_if_off(attack);
    checkbox('Seconds left##attack', attack, 'show_value', TIPS.attack_value);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Weapon delay##attack', attack, 'show_delay', TIPS.attack_delay);
    checkbox_with_color('Your TP', attack, 'show_tp', 'tp_color', TIPS.tp);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox_unless(not attack.show_tp, 'Rounds to 1000', attack, 'show_tp_rounds', TIPS.tp_rounds);
    bar_toggles('attack', attack);
    size_sliders('attack', attack);
    bar_colors('attack', attack, 'ready_color', 'Ready', TIPS.attack_ready);
    checkbox_with_color('Almost ready##attack', attack, 'almost_ready', 'almost_color', TIPS.attack_almost);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Range / facing', attack, 'show_reason', TIPS.reason);
    float_slider('Almost ready at##attack', attack, 'almost_seconds', RANGES.attack.almost_seconds, '%.1f s left',
        TIPS.attack_at, not attack.almost_ready);
    checkbox('Why it stopped', attack, 'show_why', TIPS.why);
    end_fade(faded);
end

-- A dropdown wide enough for its widest choice, `widest` px, plus its padding and its arrow. ImGui cuts
-- off a choice that doesn't fit. It never takes more of `room` than is left next to its name and its
-- (?), and it's never narrower than the other controls.
local function list_width(widest, name, room)
    local spare = room - BOX_GAP - imgui.CalcTextSize(name) - ITEM_GAP - imgui.CalcTextSize('(?)');
    return math.max(px(CONTROL_WIDTH), math.min(widest + BUTTON_PADDING + imgui.GetFrameHeight(), spare));
end

-- The sounds from the last look, cadence's first and then yours, or a line saying there are none. It opens
-- scrolled to the one you have.
local function sound_list(resting)
    local files = sound.files();
    if (#files == 0) then
        note(NO_SOUND_FILES, look.faded_text);
    end
    for _, name in ipairs(files) do
        if (imgui.Selectable(name, name == resting.sound_file)) then
            resting.sound_file = name;
            result.sound_picked = true;
            mark_changed(true);
        end
        if (name == resting.sound_file) then
            imgui.SetItemDefaultFocus();
        end
    end
end

--[[
    The sound for when resting fills your HP and MP. The box in front of the list turns it on, like the
    boxes in front of the labels, and the list is narrower by that much. A long name makes the list grow,
    like the other dropdowns, as far as the room left of Refresh lets it. Refresh looks in the sounds
    folders again. Play is greyed out with no file picked. A file that won't play gets a note under them.
]]
local function sound_rows(resting)
    local x = imgui.GetCursorPosX();
    tick_box('##sound', resting, 'sound');
    imgui.SameLine();
    local shown = resting.sound_file ~= '' and resting.sound_file or NO_SOUND;
    local widest = imgui.CalcTextSize(shown);
    for _, name in ipairs(sound.files()) do
        widest = math.max(widest, imgui.CalcTextSize(name));
    end
    local box = imgui.GetCursorPosX() - x;
    local refresh = ITEM_GAP + BUTTON_PADDING + imgui.CalcTextSize('Refresh') + ITEM_GAP + imgui.CalcTextSize('(?)');
    imgui.SetNextItemWidth(list_width(widest + box, 'Sound', box + imgui.GetContentRegionAvail() - refresh) - box);
    if (imgui.BeginCombo('Sound##resting', shown)) then
        sound_list(resting);
        imgui.EndCombo();
    end
    help(TIPS.sound);
    imgui.SameLine();
    if (imgui.Button('Refresh##sound')) then
        sound.refresh();
    end
    help(TIPS.sound_refresh);
    whole_slider('Volume##sound', resting, 'sound_volume', RANGES.resting.sound_volume, '%d%%', TIPS.sound_volume);
    imgui.SameLine();
    imgui.BeginDisabled(resting.sound_file == '');
    if (imgui.Button('Play##sound')) then
        result.play_sound = true;
    end
    imgui.EndDisabled();
    help(TIPS.play_sound);
    local problem = sound.problem(resting.sound_file);
    if (problem ~= nil) then
        note(problem, look.problem_messages);
    end
end

local function draw_resting_section(resting)
    heading_with_toggle('RESTING TIMER', 'resting', resting, TIPS.resting_timer);
    local faded = fade_if_off(resting);
    checkbox('Seconds left##resting', resting, 'show_value', TIPS.resting_value);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Last tick gains##resting', resting, 'show_gains', TIPS.gains);
    checkbox('Time until full##resting', resting, 'show_until_full', TIPS.until_full);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Full times##resting', resting, 'show_each_full', TIPS.each_full);
    checkbox('Numbers only##resting', resting, 'numbers_only', TIPS.numbers_only);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Hide once full##resting', resting, 'hide_when_full', TIPS.hide_when_full);
    size_sliders('resting', resting);
    bar_colors('resting', resting, 'full_color', 'Full HP/MP', TIPS.full_color);
    checkbox_with_color('Flash on each tick', resting, 'flash_on_tick', 'flash_color', TIPS.flash);
    float_slider('Flash length', resting, 'flash_seconds', RANGES.resting.flash_seconds, '%.1f s', TIPS.flash_length,
        not resting.flash_on_tick);
    checkbox('Why it can\'t heal', resting, 'show_why', TIPS.cant_heal);
    sound_rows(resting);
    end_fade(faded);
end

-- Hide during events, Hide on the map and Hide with the game UI. Under the auto attack timer, the first two
-- share a line. Stacked, each one gets a line.
local function draw_all_timers(style)
    heading('ALL TIMERS');
    checkbox('Hide during events', style, 'hide_during_events', TIPS.hide_events);
    if (not stacked) then
        imgui.SameLine();
    end
    local see_map = player.can_check_map();
    checkbox_unless(not see_map, 'Hide on the map', style, 'hide_on_map',
        see_map and TIPS.hide_on_map or TIPS.cant_see_map);
    local see_ui = player.can_check_interface();
    checkbox_unless(not see_ui, 'Hide with the game UI', style, 'hide_with_game_ui',
        see_ui and TIPS.hide_ui or TIPS.cant_see_ui);
end

-- Side by side, ALL TIMERS sits under the auto attack timer, in the room the longer resting timer leaves
-- there. Stacked, it comes last.
local function draw_timers_tab(settings)
    if (begin_sections('##timer_sections')) then
        imgui.TableNextColumn();
        draw_attack_section(settings.attack);
        if (not stacked) then
            draw_all_timers(settings.style);
        end
        next_section();
        draw_resting_section(settings.resting);
        imgui.EndTable();
    end
    if (stacked) then
        draw_all_timers(settings.style);
    end
end

-- Which monster the enemy timer follows, picked from defaults.FOLLOWS.
local function which_enemy_picker(enemy)
    local shown = defaults.FOLLOWS[1][2];
    for _, choice in ipairs(defaults.FOLLOWS) do
        if (choice[1] == enemy.which) then
            shown = choice[2];
        end
    end

    imgui.SetNextItemWidth(px(CONTROL_WIDTH));
    if (imgui.BeginCombo('Follows##enemy', shown)) then
        for _, choice in ipairs(defaults.FOLLOWS) do
            if (imgui.Selectable(choice[2], choice[1] == enemy.which)) then
                enemy.which = choice[1];
                mark_changed(true);
            end
        end
        imgui.EndCombo();
    end
    help(TIPS.follows);
end

local function draw_enemy_section(enemy, style)
    heading_with_toggle('ENEMY ATTACK TIMER', 'enemy', enemy, TIPS.enemy_timer);
    local faded = fade_if_off(enemy);
    which_enemy_picker(enemy);
    checkbox_unless(enemy.which == 'attacker', 'Keep the last monster', enemy, 'keep_last', TIPS.keep_last);
    checkbox('Attach under auto attack', enemy, 'attached', TIPS.attached);
    checkbox('Seconds left##enemy', enemy, 'show_value', TIPS.enemy_value);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Enemy name', enemy, 'show_name', TIPS.enemy_name);
    checkbox('Attack speed##enemy', enemy, 'show_delay', TIPS.enemy_delay);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Slow and haste', enemy, 'show_effects', TIPS.enemy_effects);
    checkbox('TP move / casting', enemy, 'show_holds', TIPS.enemy_holds);
    -- On you shows on the name and the stripe. With neither on screen it has nothing to color.
    local nothing_to_color = not (style.show_labels and enemy.show_label) and not style.accent;
    checkbox_with_color('On you', enemy, 'show_on_you', 'on_you_color', TIPS.on_you,
        enemy.which == 'attacker' or nothing_to_color);
    end_fade(faded);
end

local function draw_enemy_look(enemy)
    heading('ENEMY BAR');
    local faded = fade_if_off(enemy);
    bar_toggles('enemy', enemy);
    whole_slider('Width##enemy', enemy, 'width', RANGES.enemy.width, '%d px', TIPS.enemy_width, enemy.attached);
    whole_slider('Bar height##enemy', enemy, 'bar_height', RANGES.enemy.bar_height, '%d px', TIPS.enemy_bar,
        enemy.numbers_only);
    bar_colors('enemy', enemy, 'ready_color', 'Ready', TIPS.enemy_ready);
    checkbox_with_color('Almost ready##enemy', enemy, 'almost_ready', 'almost_color', TIPS.enemy_almost);
    float_slider('Almost ready at##enemy', enemy, 'almost_seconds', RANGES.enemy.almost_seconds, '%.1f s left',
        TIPS.enemy_at, not enemy.almost_ready);
    end_fade(faded);
end

local function draw_enemy_tab(settings)
    if (begin_sections('##enemy_sections')) then
        imgui.TableNextColumn();
        draw_enemy_section(settings.enemy, settings.style);
        next_section();
        draw_enemy_look(settings.enemy);
        imgui.EndTable();
    end
end

-- The Preset list fits its longest name, like "Custom (from Colorblind safe)".
local function preset_width()
    local widest = 0;
    for _, id in ipairs(presets.IDS) do
        widest = math.max(widest, imgui.CalcTextSize(presets.custom_name(id)));
    end
    return list_width(widest, 'Preset', imgui.GetContentRegionAvail());
end

-- A dropdown of the preset looks. It shows the one you have. Once you change it, it says Custom and
-- names the last preset you picked, like "Custom (from Phoenix)". Picking one applies it right away, so
-- picking that one puts its look back. Picking the one you already have does nothing, so it can't
-- replace what Undo would put back.
local function preset_picker(settings)
    local current = presets.current(settings);
    imgui.SetNextItemWidth(preset_width());
    if (imgui.BeginCombo('Preset', current or presets.custom_name(settings.style.window_look))) then
        for _, name in ipairs(presets.NAMES) do
            if (imgui.Selectable(name, name == current) and name ~= current) then
                presets.apply(settings, name);
                mark_changed(true);
            end
        end
        imgui.EndCombo();
    end
    help(TIPS.preset);
end

-- The PRESET heading, with Undo and Reset look at its right end like a timer's ON/OFF chip. They're
-- small buttons, so the heading stays one line of text tall. The Look tab has no room for another row.
local function preset_heading(settings)
    imgui.Spacing();
    local x = imgui.GetCursorPosX();
    local width = imgui.GetContentRegionAvail();
    local help_width = ITEM_GAP + imgui.CalcTextSize('(?)');
    local buttons_width = imgui.CalcTextSize('Undo') + imgui.CalcTextSize('Reset look') + BUTTON_PADDING * 2
        + ITEM_GAP + help_width * 2;
    imgui.TextColored(look.headings, 'PRESET');
    imgui.SameLine(x + width - buttons_width);
    imgui.BeginDisabled(not presets.can_undo());
    if (imgui.SmallButton('Undo')) then
        presets.undo(settings);
        mark_changed(true);
    end
    imgui.EndDisabled();
    help(TIPS.undo);
    imgui.SameLine();
    if (imgui.SmallButton('Reset look')) then
        result.reset_look = true;
    end
    help(TIPS.reset_look);
    imgui.Separator();
end

-- The LABELS heading, with Show labels at its right end like a timer's ON/OFF chip, since it turns the
-- whole section on or off. The Look tab has no room for it on a row of its own.
local function labels_heading(style)
    imgui.Spacing();
    local x = imgui.GetCursorPosX();
    local width = imgui.GetContentRegionAvail();
    local box_width = imgui.GetFrameHeight() + BOX_GAP + imgui.CalcTextSize('Show labels') + ITEM_GAP
        + imgui.CalcTextSize('(?)');
    -- Lines the heading up with the words of the box next to it.
    imgui.AlignTextToFramePadding();
    imgui.TextColored(look.headings, 'LABELS');
    imgui.SameLine(x + width - box_width);
    checkbox('Show labels', style, 'show_labels', TIPS.show_labels);
    imgui.Separator();
end

-- The preset, sizes and labels, the left column of the Look tab.
local function draw_size_sections(settings)
    local style = settings.style;
    preset_heading(settings);
    preset_picker(settings);
    checkbox('Window matches the look', style, 'window_matches_look', TIPS.window_look);

    heading('SIZE');
    float_slider('Scale', style, 'scale', RANGES.style.scale, '%.2fx', TIPS.scale);
    whole_slider('Text size', style, 'font_size', RANGES.style.font_size, '%d px', TIPS.text_size);
    -- The slider's left end is auto.
    local detail_format = (style.detail_size < defaults.DETAIL_SIZE[1]) and 'auto' or '%d px';
    whole_slider('Detail size', style, 'detail_size', RANGES.style.detail_size, detail_format, TIPS.detail_size);
    whole_slider('Corner roundness', style, 'rounding', RANGES.style.rounding, '%d px', TIPS.rounding);

    labels_heading(style);
    local labels_off = not style.show_labels;
    -- The slider's left end is auto.
    local label_format = (style.label_size < defaults.LABEL_SIZE[1]) and 'auto' or '%d px';
    whole_slider('Label size', style, 'label_size', RANGES.style.label_size, label_format, TIPS.label_size,
        labels_off);
    label_box('Auto attack##label', '##show_label_attack', settings.attack, 'AUTO ATTACK', TIPS.attack_label,
        labels_off);
    label_box('Resting##label', '##show_label_resting', settings.resting, 'RESTING', TIPS.resting_label,
        labels_off);
    label_box('Enemy##label', '##show_label_enemy', settings.enemy, settings.enemy.attached and 'ENEMY'
        or 'ENEMY ATTACK', TIPS.enemy_label, labels_off);
end

-- A dropdown of the fonts that loaded, with Ashita's own pixel font first. It fits the longest name, like
-- Segoe UI Semibold.
local function font_picker(style)
    local shown = hud.font_in_use() or ASHITA_FONT;
    local widest = imgui.CalcTextSize(ASHITA_FONT);
    for _, name in ipairs(hud.font_names()) do
        widest = math.max(widest, imgui.CalcTextSize(name));
    end
    imgui.SetNextItemWidth(list_width(widest, 'Font', imgui.GetContentRegionAvail()));
    if (imgui.BeginCombo('Font', shown)) then
        if (imgui.Selectable(ASHITA_FONT, shown == ASHITA_FONT)) then
            style.system_font = false;
            mark_changed(true);
        end
        for _, name in ipairs(hud.font_names()) do
            if (imgui.Selectable(name, name == shown)) then
                style.system_font, style.font_name = true, name;
                mark_changed(true);
            end
        end
        imgui.EndCombo();
    end
    help(TIPS.font);
end

-- Colors and where the timers sit, the right column of the Look tab.
local function draw_color_sections(style)
    heading('CARD');
    checkbox_with_color('Background', style, 'panel', 'panel_color', TIPS.background);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox_with_color('Border', style, 'border', 'border_color', TIPS.border);
    checkbox_with_color('Accent stripe', style, 'accent', 'accent_color', TIPS.accent);

    heading('TEXT AND BAR');
    color_with_help('Labels##text', style, 'label_color', TIPS.label_color);
    imgui.SameLine(px(SECOND_COLUMN));
    color_with_help('Values##text', style, 'value_color', TIPS.value_color);
    color_with_help('Details##text', style, 'detail_color', TIPS.detail_color);
    imgui.SameLine(px(SECOND_COLUMN));
    color_with_help('Bar track##text', style, 'track_color', TIPS.track_color);
    checkbox_with_color('Text outline', style, 'text_outline', 'outline_color', TIPS.text_outline);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Text shadow', style, 'text_shadow', TIPS.text_shadow);
    font_picker(style);
    checkbox('Drain instead of fill', style, 'bar_drains', TIPS.drains);

    heading('POSITION');
    checkbox('Lock in place', style, 'locked', TIPS.locked);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Share one spot', style, 'shared_spot', TIPS.shared_spot);
    flag[1] = shared_layout.is_on();
    if (imgui.Checkbox('One layout for all characters', flag)) then
        result.share_layout = flag[1];
    end
    help(TIPS.one_layout);
    if (imgui.Button('Reset positions')) then
        result.reset_positions = true;
    end
    help(TIPS.reset_spots);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Peek with Shift', style, 'see_through', TIPS.see_through);
end

local function draw_look_tab(settings)
    if (begin_sections('##look_sections')) then
        imgui.TableNextColumn();
        draw_size_sections(settings);
        next_section();
        draw_color_sections(settings.style);
        imgui.EndTable();
    end
end

-- What the window says when its font didn't load. It's made once for each font, not every frame.
local function font_note(id)
    local words = font_notes[id];
    if (words == nil) then
        words = ('%s isn\'t in %s or won\'t load, so this window uses Ashita\'s font.')
            :format(window_font.find(id).name, window_font.FOLDER);
        font_notes[id] = words;
    end
    return words;
end

-- A dropdown of this window's fonts. One that didn't load is still there, with a note under Font size.
local function window_font_picker()
    local shown = window_font.LIST[1].name;
    for _, entry in ipairs(window_font.LIST) do
        if (entry.id == look.font) then
            shown = entry.name;
        end
    end
    imgui.SetNextItemWidth(px(CONTROL_WIDTH));
    if (imgui.BeginCombo('Font##window', shown)) then
        for _, entry in ipairs(window_font.LIST) do
            if (imgui.Selectable(entry.name, entry.id == look.font)) then
                look.font = entry.id;
                mark_changed(true);
            end
        end
        imgui.EndCombo();
    end
    help(TIPS.window_font);
end

--[[
    One of cadence's chat colors, picked from the game's chat colors. A swatch in front shows about how it
    looks, and so does one in front of each name in the list. The list fits the longest name, `widest`
    px, in the `room` its row has. It opens scrolled to the color you have.
]]
local function chat_color(chat, part, widest, room)
    local current = chat_colors.entry(chat[part.key]);
    imgui.ColorButton(CHAT_PART_IDS[part.key], CHAT_SWATCHES[current.code], CHAT_SWATCH_FLAGS, CHAT_SWATCH_SIZE);
    imgui.SameLine(0, BOX_GAP);
    imgui.SetNextItemWidth(list_width(widest, part.name, room - imgui.GetFrameHeight() - BOX_GAP));
    if (imgui.BeginCombo(part.name, current.name)) then
        local line = imgui.GetFontSize();
        line_swatch[1], line_swatch[2] = line, line;
        for _, entry in ipairs(chat_colors.PALETTE) do
            imgui.ColorButton(CHAT_SWATCH_IDS[entry.code], CHAT_SWATCHES[entry.code], CHAT_SWATCH_FLAGS, line_swatch);
            imgui.SameLine();
            if (imgui.Selectable(entry.name, entry == current)) then
                chat[part.key] = entry.code;
                mark_changed(true);
            end
            if (entry == current) then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
    help(TIPS[part.key]);
end

-- cadence's chat colors and Print a sample, two to a line like ALL TIMERS, lined up with the columns
-- above when there are two.
local function draw_chat_section(chat)
    heading('CHAT');
    local width = imgui.GetContentRegionAvail();
    local second_column = imgui.GetCursorPosX() + (width + COLUMN_GAP) / 2;
    local room = stacked and width or (width - COLUMN_GAP) / 2;
    local widest = 0;
    for _, entry in ipairs(chat_colors.PALETTE) do
        widest = math.max(widest, imgui.CalcTextSize(entry.name));
    end
    local parts = chat_colors.PARTS;
    chat_color(chat, parts[1], widest, room);
    if (not stacked) then
        imgui.SameLine(second_column);
    end
    chat_color(chat, parts[2], widest, room);
    chat_color(chat, parts[3], widest, room);
    if (not stacked) then
        imgui.SameLine(second_column);
    end
    if (imgui.Button('Print a sample')) then
        result.sample = true;
    end
    help(TIPS.chat_sample);
end

-- This window's font, size, corners and spacing, then cadence's chat colors.
local function draw_window_tab(settings)
    local ranges = RANGES.window_style;
    if (begin_sections('##window_sections')) then
        imgui.TableNextColumn();
        heading('FONT');
        window_font_picker();
        -- Font size stays as wide as it is at 18 px, so dragging it never pulls the handle out from under
        -- the mouse.
        whole_slider('Font size##window', look, 'font_size', ranges.font_size, '%d px', TIPS.window_size, false,
            CONTROL_WIDTH);
        if (window_font.failed(look.font)) then
            note(font_note(look.font), look.problem_messages);
        end
        next_section();
        heading('SHAPE');
        whole_slider('Corner roundness##window', look, 'rounding', ranges.rounding, '%d px', TIPS.window_corners);
        whole_slider('Spacing##window', look, 'spacing', ranges.spacing, '%d px', TIPS.window_spacing);
        imgui.EndTable();
    end
    draw_chat_section(settings.chat);
end

-- One row of the Window colors tab. Its name, then a swatch for each of its colors, then its (?). The
-- swatches start `name_width` past the row's start, so they line up from row to row.
local function window_color_row(row, name_width)
    imgui.AlignTextToFramePadding();
    imgui.TextUnformatted(row.name);
    imgui.SameLine(0, name_width - imgui.CalcTextSize(row.name) + ITEM_GAP);
    for i, entry in ipairs(row.colors) do
        if (i > 1) then
            imgui.SameLine();
        end
        color(SWATCH_IDS[entry.key], look, entry.key, SWATCH_FLAGS);
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip(entry.name);
        end
    end
    help(WINDOW_COLOR_TIPS[row.name]);
end

-- Every color of this window, as rows of swatches under their headings.
local function draw_window_colors_tab()
    local name_width = 0;
    for _, group in ipairs(theme.WINDOW_COLOR_GROUPS) do
        for _, row in ipairs(group.rows) do
            local width = imgui.CalcTextSize(row.name);
            name_width = math.max(name_width, width);
        end
    end
    note(WINDOW_COLORS_NOTE);
    if (begin_sections('##window_color_sections')) then
        imgui.TableNextColumn();
        for _, group in ipairs(theme.WINDOW_COLOR_GROUPS) do
            if (group.name == SECOND_COLORS) then
                next_section();
            end
            heading(group.name);
            for _, row in ipairs(group.rows) do
                window_color_row(row, name_width);
            end
        end
        imgui.EndTable();
    end
end

--[[
    Profiles tab. Each button's action returns whether it worked and what to say under the buttons.
    The words are made when you press it, not every frame. ImGui can break a line right after a closing
    quote, so a quoted name is never followed by a period or comma. That would start a line on its own.
]]

local function save_as_new(settings)
    local name = profiles.clean_name(profile_name[1]);
    local taken = profiles.find(name);
    if (name == '') then
        return false, 'Type a name for the new profile first.';
    elseif (taken ~= nil) then
        return false, ('A profile called "%s" is already there. Pick it and use Overwrite.'):format(taken);
    elseif (profiles.no_link_word(name)) then
        return false, profiles.NO_LINK_NAME:format(name);
    elseif (not profiles.save(settings, name)) then
        return false, profiles.problem();
    end
    picked = name;
    return true, ('Saved "%s" as a new profile.'):format(name);
end

local function overwrite_picked(settings)
    if (not profiles.save(settings, picked)) then
        return false, profiles.problem();
    end
    return true, ('The profile "%s" has your settings now.'):format(picked);
end

local function load_picked(settings)
    profiles.load(settings, picked);
    mark_changed(true);
    return true, ('The profile "%s" is loaded.'):format(picked);
end

-- Your job links to it follow.
local function rename_picked(settings)
    local name = profiles.clean_name(profile_name[1]);
    local taken = profiles.find(name);
    if (name == '') then
        return false, 'Type the new name first.';
    elseif (name == picked) then
        return false, ('The profile "%s" already has that name.'):format(name);
    elseif (taken ~= nil and taken ~= picked) then
        return false, ('A profile called "%s" is already there.'):format(taken);
    elseif (profiles.no_link_word(name)) then
        return false, profiles.NO_LINK_NAME:format(name);
    end
    local ok, relinked = profiles.rename(settings, picked, name);
    if (not ok) then
        return false, profiles.problem();
    end
    if (relinked) then
        result.links = true;
    end
    local old = picked;
    picked = name;
    return true, ('The profile "%s" is called "%s" now.'):format(old, name);
end

-- Your job links to it go too.
local function delete_picked(settings)
    local ok, relinked = profiles.delete(settings, picked);
    if (not ok) then
        return false, profiles.problem();
    end
    if (relinked) then
        result.links = true;
    end
    return true, ('The profile "%s" is deleted.'):format(picked);
end

-- Runs a button's action. profiles.json is read again first, since another character can change it.
-- A file that can't be read stops every action. A picked profile that's gone stops the ones for it.
local function run_action(action, settings, for_picked)
    profiles.refresh();
    if (not profiles.file_ok()) then
        status_ok, status = false, profiles.problem();
    elseif (for_picked and not profiles.exists(picked)) then
        status_ok, status = false, 'The profile you picked isn\'t there anymore.';
    else
        status_ok, status = action(settings);
    end
end

-- A button for the profile picked in the list, greyed out until one is picked.
local function profile_button(label, tip, action, settings)
    imgui.BeginDisabled(picked == nil);
    if (imgui.Button(label)) then
        run_action(action, settings, true);
    end
    imgui.EndDisabled();
    help(tip);
end

-- The saved profiles. Picking one puts its name in the box. A picked profile that's gone stops being
-- picked, whether you deleted it or another character did.
local function draw_profile_list()
    local names = profiles.names();
    if (picked ~= nil and not profiles.exists(picked)) then
        picked = nil;
    end
    list_size[2] = px(LIST_HEIGHT);
    if (imgui.BeginListBox('##profiles', list_size)) then
        if (#names == 0) then
            note('No profiles yet.', look.faded_text);
        end
        for _, name in ipairs(names) do
            if (imgui.Selectable(name, name == picked)) then
                picked = name;
                profile_name[1] = name;
            end
        end
        imgui.EndListBox();
    end
end

-- The list, the name box, the buttons, then what the last button said. A file that can't be read gets
-- a note even before you press anything.
local function draw_profiles_section(settings)
    heading('PROFILES', TIPS.profiles);
    draw_profile_list();
    imgui.SetNextItemWidth(px(CONTROL_WIDTH));
    imgui.InputText('Name', profile_name, profiles.NAME_MAX + 1);
    help(TIPS.profile_name);
    if (imgui.Button('Save as new')) then
        run_action(save_as_new, settings, false);
    end
    help(TIPS.save_new);
    imgui.SameLine();
    profile_button('Overwrite', TIPS.overwrite, overwrite_picked, settings);
    profile_button('Load', TIPS.load, load_picked, settings);
    imgui.SameLine();
    profile_button('Rename', TIPS.rename, rename_picked, settings);
    imgui.SameLine();
    profile_button('Delete', TIPS.delete, delete_picked, settings);
    if (status ~= nil) then
        note(status, status_ok and look.done_messages or look.problem_messages);
    end
    local problem = not profiles.file_ok() and profiles.problem();
    if (problem and problem ~= status) then
        note(problem, look.problem_messages);
    end
end

-- The list of one job's link. It shows the profile linked to the job, (none), or the name with (gone)
-- in front when that profile isn't there anymore. A profiles.json that can't be read shows the plain
-- name, since the profile can still be in it. It lists (none) and every profile, and opens scrolled to
-- the one you have.
local function job_link(links, job, id, width)
    local linked = links[job];
    local shown = linked or NO_LINK;
    if (linked ~= nil and profiles.file_ok() and not profiles.exists(linked)) then
        shown = gone_names[linked] or ('(gone) %s'):format(linked);
        gone_names[linked] = shown;
    end
    imgui.SetNextItemWidth(width);
    if (imgui.BeginCombo(id, shown)) then
        if (imgui.Selectable(NO_LINK, linked == nil)) then
            links[job] = nil;
            result.links = true;
        end
        if (linked == nil) then
            imgui.SetItemDefaultFocus();
        end
        for _, name in ipairs(profiles.names()) do
            if (imgui.Selectable(name, name == linked)) then
                links[job] = name;
                result.links = true;
            end
            if (name == linked) then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
end

--[[
    Every main job with its link, two to a line like ALL TIMERS, with the window's spacing between
    lines. The second job on a line starts halfway across the section. A job's name sits level with
    the text in its list, and each list reaches the gap in the middle or the section's edge. Each spot
    is set with SetCursorPosX. A spot given to SameLine counts from the wrong place in the second
    column.
]]
local function draw_job_links(links)
    heading('JOB LINKS', TIPS.job_links);
    local x = imgui.GetCursorPosX();
    local half = (imgui.GetContentRegionAvail() + COLUMN_GAP) / 2;
    local list_width = half - COLUMN_GAP - px(JOB_LIST_AT);
    for i, job in ipairs(defaults.JOBS) do
        local start = x;
        if (i % 2 == 0) then
            start = x + half;
            imgui.SameLine();
            imgui.SetCursorPosX(start);
        end
        imgui.AlignTextToFramePadding();
        imgui.TextUnformatted(job);
        imgui.SameLine();
        imgui.SetCursorPosX(start + px(JOB_LIST_AT));
        job_link(links, job, JOB_IDS[i], list_width);
    end
end

local function draw_profiles_tab(settings)
    if (begin_sections('##profile_sections')) then
        imgui.TableNextColumn();
        draw_profiles_section(settings);
        next_section();
        draw_job_links(settings.job_links);
        imgui.EndTable();
    end
end

-- The tabs in order, each drawn by its function.
local TABS = {
    { 'Timers',        draw_timers_tab },
    { 'Enemy',         draw_enemy_tab },
    { 'Look',          draw_look_tab },
    { 'Window',        draw_window_tab },
    { 'Window colors', draw_window_colors_tab },
    { 'Profiles',      draw_profiles_tab },
};

-- Another character logged in. The open window moves to their spot and size on the next frame. ImGui
-- would leave it where it is, and its old spot would save over theirs.
function settings_window.place_again()
    place_now = true;
end

-- How wide the tab bar is with every tab's name in full, in this frame's font.
local function tabs_width()
    local width = -TAB_GAP;
    for _, tab in ipairs(TABS) do
        width = width + math.ceil(imgui.CalcTextSize(tab[1])) + TAB_PADDING[1] * 2 + TAB_EXTRA + TAB_GAP;
    end
    return width;
end

--[[
    Where the window opens. It's where you left it, at the size you left it. On a smaller screen the
    size gets cut down to fit. A window left hanging off an edge gets pulled back so all of it shows.
    The smallest size has room for one column and every tab's name. It grows with the font size, and
    gets cut down to fit a small screen too.
]]
local function place_window(window)
    local screen = imgui.GetIO().DisplaySize;
    min_size[1] = math.min(math.max(px(COLUMN_WIDTH), tabs_width()) + WINDOW_EDGES, screen.x);
    min_size[2] = math.min(px(MIN_HEIGHT), screen.y);
    extent[1] = math.max(min_size[1], math.min(window.width, screen.x));
    extent[2] = math.max(min_size[2], math.min(window.height, screen.y));
    spot[1] = math.max(0, math.min(window.x, screen.x - extent[1]));
    spot[2] = math.max(0, math.min(window.y, screen.y - extent[2]));
    local when = place_now and ImGuiCond_Always or ImGuiCond_Appearing;
    imgui.SetNextWindowPos(spot, when);
    imgui.SetNextWindowSize(extent, when);
    imgui.SetNextWindowSizeConstraints(min_size, MAX_SIZE);
    place_now = false;
end

--[[
    How much wider the window's font draws WIDTH_SAMPLE than Ashita's font does at 18 px. Consolas at 18
    is as wide as Ashita's font at 20, so its layout grows the way it would at 20. It's measured again
    only when you change the font or its size. Call it before the window's font is pushed, while
    imgui.GetFont() is still Ashita's.
]]
local function measure_width(face, size)
    imgui.PushFont(imgui.GetFont(), BASE_FONT_SIZE);
    local ashita = imgui.CalcTextSize(WIDTH_SAMPLE);
    imgui.PopFont();
    imgui.PushFont(face, size);
    local width = imgui.CalcTextSize(WIDTH_SAMPLE);
    imgui.PopFont();
    wider = ashita > 0 and width / ashita or 1;
end

-- Keeps where you moved the window and the size you gave it, and saves them once you let go.
local function remember_window(window)
    local x, y = imgui.GetWindowPos();
    local width, height = imgui.GetWindowSize();
    x, y, width, height = round(x), round(y), round(width), round(height);
    local moved = x ~= window.x or y ~= window.y or width ~= window.width or height ~= window.height;
    if (moved and not imgui.IsMouseDown(ImGuiMouseButton_Left)) then
        window.x, window.y, window.width, window.height = x, y, width, height;
        result.save = true;
    end
end

--[[
    Draws the window when it's open. Returns flags that tell the caller what to do next. `changed`
    means redraw with the new settings. `save` means write the settings file. `reset_positions` and
    `reset_look` mean a reset button was pressed. `share_layout` is true or false when the
    "One layout for all characters" box was ticked or cleared, and nil otherwise. `timers_hidden` is
    true while /cadence hide has the timers hidden, and `show_timers` means Show them was pressed.
    `sample` means Print a sample was pressed. `links` means a job link changed, so this character's
    own settings file needs writing, even while one layout is shared. `sound_picked` means a file was
    picked in the Sound list, and `play_sound` means Play was pressed. `shift` is true while you hold
    Shift and aren't typing in the game's chat line.
]]
function settings_window.draw(settings, version, timers_hidden, shift)
    result.changed, result.save, result.reset_positions, result.reset_look = false, false, false, false;
    result.share_layout, result.show_timers, result.sample, result.links = nil, false, false, false;
    result.sound_picked, result.play_sound = false, false;
    if (not open[1]) then
        return result;
    end

    -- Holding Shift makes the window see-through, and clicks reach the timers under it. It stays solid
    -- while you use something in it, or while a dropdown or color picker is open.
    local peek = shift and settings.style.see_through and not busy
        and not imgui.IsPopupOpen('', ImGuiPopupFlags_AnyPopupId);
    window_alpha = peek and PEEK_ALPHA or 1;
    look = settings.window_style;
    theme.chip_hover(look, chip_lit, chip_faint);
    local color_count, var_count = theme.push_window_style(look);
    if (peek) then
        imgui.PushStyleVar(ImGuiStyleVar_Alpha, PEEK_ALPHA);
        var_count = var_count + 1;
    end
    -- A font that didn't load draws in Ashita's own font at your size.
    local face = window_font.face(look.font) or imgui.GetFont();
    if (look.font ~= wider_font or look.font_size ~= wider_size) then
        measure_width(face, look.font_size);
        wider_font, wider_size = look.font, look.font_size;
    end
    imgui.PushFont(face, look.font_size);
    -- A font smaller than 18 px keeps the layout it has at 18. The gaps between things don't shrink
    -- with the font, so a smaller layout would run a box into the one beside it.
    scale = math.max(1, imgui.GetFontSize() / BASE_FONT_SIZE, wider);
    chip_size[1] = px(CHIP_WIDTH);
    two_columns_at = 2 * px(COLUMN_WIDTH) + COLUMN_GAP + WINDOW_EDGES;
    place_window(settings.window);
    if (imgui.Begin('cadence##cadence_settings', open, peek and PEEK_FLAGS or WINDOW_FLAGS)) then
        remember_window(settings.window);
        -- The version goes on its own line when the subtitle doesn't fit, so it never breaks at a dot.
        local subtitle = ('Auto attack, resting and enemy timers for Phoenix  |  v%s'):format(version);
        if (imgui.CalcTextSize(subtitle) > imgui.GetContentRegionAvail()) then
            subtitle = ('Auto attack, resting and enemy timers for Phoenix\nv%s'):format(version);
        end
        note(subtitle, look.faded_text);
        if (timers_hidden) then
            imgui.AlignTextToFramePadding();
            note('The timers are hidden.');
            imgui.SameLine();
            if (imgui.Button('Show them')) then
                result.show_timers = true;
            end
            help(TIPS.show_timers);
        end

        -- The tab bar lays its tabs out with the tab padding, and each tab's page draws with the usual one.
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, TAB_PADDING);
        if (imgui.BeginTabBar('##cadence_tabs', ImGuiTabBarFlags_DrawSelectedOverline)) then
            for _, tab in ipairs(TABS) do
                if (imgui.BeginTabItem(tab[1])) then
                    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, theme.FRAME_PADDING);
                    tab[2](settings);
                    imgui.PopStyleVar(1);
                    imgui.EndTabItem();
                end
            end
            imgui.EndTabBar();
        end
        imgui.PopStyleVar(1);

        imgui.Spacing();
        imgui.Separator();
        note(FOOTER);
        -- The next frame's Shift check reads this. A timer you're dragging is in its own window, so it doesn't count.
        busy = imgui.IsAnyItemActive() and imgui.IsWindowFocused();
    end
    imgui.End();
    imgui.PopFont();
    theme.pop_window_style(color_count, var_count);

    return result;
end

return settings_window;
