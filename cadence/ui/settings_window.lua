--[[
    The settings window, opened with /cadence.

    Changes show up right away. Sliders, color pickers and text boxes save when you let go of them.
    Dragging one doesn't write the settings file every frame. You can move and resize the window,
    and it opens where you left it. Its sections sit in two columns when there's room and stack into
    one when there isn't. Every setting has a (?) that explains it. The window draws in its own font
    at its own size, and its layout grows with a font bigger or wider than Ashita's at 18 px. Its
    font, corners, spacing and colors are in the Window and Window colors sections of Appearance. cadence's chat colors
    are in the Window section too. The Profiles tab saves and loads named copies of your settings, and
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
local search        = require('ui.search');
local navigation    = require('ui.navigation');
local workflow = { history = require('ui.history'), layouts = require('ui.layouts'), preview = require('ui.preview') };
local ui_state = { inline = true, sample = 'normal', enabled = {}, options = {}, search_options = {}, layout = 'minimal' };

local settings_window = {};
local query, details_query = { '' }, { '' };
local page_name, page_width, folded, detail_folded, copied = nil, nil, {}, {}, nil;
local page_size, current_settings = { 0, 0 }, nil;
local matched_query, matched_tabs;

local ASHITA_FONT = hud.ASHITA_FONT;

local WINDOW_FLAGS = bit.bor(ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoSavedSettings);
-- While you hold Shift to see through the window, clicks go through it to the timers under it.
local PEEK_FLAGS = bit.bor(WINDOW_FLAGS, ImGuiWindowFlags_NoInputs);
local COLOR_FLAGS = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar,
    ImGuiColorEditFlags_AlphaPreviewHalf);
-- A swatch on the Window colors section names its color when you point at it, instead of ImGui's own tip.
local SWATCH_FLAGS = bit.bor(COLOR_FLAGS, ImGuiColorEditFlags_NoTooltip);
-- A chat color's swatch only shows the color. It has no tip and can't be dragged onto another swatch.
local CHAT_SWATCH_FLAGS = bit.bor(ImGuiColorEditFlags_NoTooltip, ImGuiColorEditFlags_NoDragDrop);

-- Layout in pixels at Ashita's 18 px font. px() grows each one with a bigger or wider window font. A
-- column of settings needs 420, and the second control on a line starts 228 in. A tip wraps at 300. The
-- list of profiles is 130 tall. Each job link's list starts 48 in from its job's name. The window can
-- shrink to 440 tall, leaving room below the fixed controls.
local BASE_FONT_SIZE = 18;
local COLUMN_WIDTH   = 420;
local SECOND_COLUMN  = 228;
local CONTROL_WIDTH  = 190;
local CHIP_WIDTH     = 52;
local TIP_WIDTH      = 300;
local LIST_HEIGHT    = 130;
local JOB_LIST_AT    = 48;
local MIN_HEIGHT     = 440;

-- Words from the left column of the Timers and Appearance tabs. A font that draws them wider than Ashita's
-- font does at 18 px grows the layout by that much, like a bigger font would.
local WIDTH_SAMPLE = 'Almost ready Time until full Text outline';

-- Pixels that stay the same at every font size. Columns sit 24 apart, from the theme's cell padding.
-- The theme pads a button or dropdown 8 on each side and puts 8 between the things on a line. ImGui puts
-- 4 between a checkbox or dropdown and its label. A chat color's swatch sits that close to its dropdown.
local COLUMN_GAP     = 24;
local BUTTON_PADDING = 16;
local ITEM_GAP       = 8;
local BOX_GAP        = 4;

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
    attack_timer   = 'Turns the auto attack timer on or off. Show re-engage timer can also show the estimated cooldown between fights.',
    attack_value   = 'Shows the seconds until your next attack, then "ready" once you can attack.',
    attack_delay   = 'Shows the weapon delay the timer is using. Until your own attacks show the real one, it\'s a '
        .. 'guess marked est.',
    linger         = 'Keeps the estimated re-engage cooldown visible after combat, then briefly shows Estimate elapsed. '
        .. 'If timing is unknown, it says so for five seconds. Re-engaging starts a new attack delay.',
    tp             = 'Shows your TP under the bar. Your TP turns this color at your selected goal.',
    tp_rounds      = 'Shows about how many rounds until your selected TP goal. It counts the TP your hits give you and what being '
        .. 'hit or Regain has been adding lately.',
    tp_hits        = 'Shows the successful hits your own attacks need to reach the TP goal. Misses, being hit and Regain are separate. est. means the TP per hit is uncertain.',
    tp_goal        = 'The actual TP target used for the color, successful hits and approximate rounds: 1000, 2000 or 3000.',
    tp_time        = 'Shows an approximate time to your TP goal using your recent rounds and attack speed. Pauses and changing hit rates can move it.',
    recovery_goal  = 'Shows how long until HP, MP or both reach your chosen amount or percent. The goal does not change when the full recovery sound plays.',
    goal_stat      = 'Which resource the recovery goal follows. Both waits for HP and MP to reach the goal.',
    goal_mode      = 'Choose a percent of maximum HP or MP, or a fixed amount.',
    goal_value     = 'The amount or percent you want to reach. A fixed amount above your maximum stops at that maximum.',
    layout_guides  = 'Shows alignment guides and helps timer edges line up while you hold Shift and drag. Turn it off for free movement.',
    preview_timer  = 'Chooses the timer sample shown while settings are open. Auto uses the usual samples. These controls are not saved.',
    preview_state  = 'Shows a sample state supported by the selected timer, including unknown recovery or a waiting cast. It does not change your live timers.',
    preview_pause  = 'Freezes the sample so you can compare its text, colors and layout. Your live timers keep running.',
    relearn_attack = 'Forgets learned attack intervals and starts from the current model. The pending attack countdown keeps its place.',
    relearn_tp     = 'Forgets observed TP per hit and recent round gains. The next clean hits teach it again.',
    relearn_enemy  = 'Forgets the selected monster\'s learned speed. The timer keeps its place and starts learning again.',
    ticks          = 'Shows how many resting ticks remain until full. Regen and Refresh can finish between ticks. A ~ marks an estimated amount or timing.',
    hover_tips     = 'Rest the mouse over a timer to see its estimate source, samples and missing inputs. Clicks still reach the game. Tips stay hidden while you drag or another window covers the timer.',
    record         = 'Keeps a small local history of recent timing decisions while on. Off by default. It records no chat.',
    save_report    = 'Saves a local timing report with the current estimates and any recent recorded timing decisions. It records no chat.',
    numbers_only   = 'Hides the bar and keeps the timer\'s text.',
    width          = 'How wide the timer is. You can also hold Shift and drag its right edge.',
    height         = 'How tall the whole timer is, including its text and spacing. Width stays the same. You can also hold Shift and drag its bottom edge.',
    bar_height     = 'How thick the bar is before the timer height is applied. Height changes the whole timer.',
    fill           = 'The bar\'s colors, from empty to full.',
    attack_ready   = 'The bar\'s color once you can attack.',
    attack_almost  = 'The bar turns this color just before your next attack, so you can line up a weapon skill.',
    almost_mark    = 'Puts a small mark on the bar where the almost ready color starts.',
    attack_at      = 'How many seconds before your attack the almost ready color starts.',
    reason         = 'Says "too far" or "not facing" and dims the bar as soon as you step out of reach or turn '
        .. 'away from the monster you\'re fighting. Once the bar is full, the server\'s own message wins.',
    why            = 'While a spell, ranged attack or item holds your auto attack, the bar dims and says why instead '
        .. 'of the seconds, like "casting" for a spell. Sleep, stun and so on do the same, like "asleep" for sleep.',

    recovery_timer = 'Shows estimated recovery after spells, weapon skills, job abilities, items and ranged attacks. Unavailable timing shows unknown briefly. Works while idle or engaged.',
    recovery_value = 'Shows estimated seconds left with a ~. Other recasts or action locks can still prevent casting after this estimate ends.',
    recovery_source = 'Names the action that started recovery. Not every job ability creates a recovery delay. Unavailable timing has a short unknown notice, not a countdown.',
    recovery_attached = 'Matches auto attack\'s width and moves with it, above an attached enemy timer. Recovery still shows while idle. '
        .. 'With auto attack off, it uses its own spot.',
    recovery_label = 'Rename the action recovery timer. Leave it empty for ACTION RECOVERY. Untick the box to hide its name.',
    enemycast_timer = 'Shows the followed monster\'s observed spell cast. Base cast time is an estimate. Waiting never confirms completion. Uses Follows and Keep the last monster even when enemy attack is off.',
    enemycast_attached = 'Matches the enemy attack timer\'s width and follows beneath it, including when enemy attack is attached to auto attack. With enemy attack off, it uses its saved separate position and width.',
    enemycast_spell = 'Shows the spell named in the observed cast start. An unavailable name is shown by spell ID.',
    enemycast_value = 'Shows estimated seconds left with a ~. After the estimate ends, waiting stays until an observed finish or interruption. Stale observations are eventually discarded.',
    enemycast_label = 'Rename the enemy cast timer. Leave it empty for ENEMY CAST. Untick the box to hide its name.',
    resting_timer  = 'Turns the resting timer on or off. It shows up while you /heal.',
    resting_value  = 'Shows the seconds until your next resting tick.',
    gains          = 'Shows what your last tick restored, like +24 HP +31 MP.',
    next_gains     = 'Shows what your next resting tick should restore, before Regen or Refresh. est. means some bonuses are not known yet.',
    until_full     = 'Shows how long until your HP and MP are both full, like "full in 28s" on the timer. A ~ marks uncertain amounts or timing. It includes separate Regen and Refresh passes.',
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
    hide_chat_log  = 'Hides all timers or selected timers while the full-screen chat log is open. Ordinary chat typing does not count. Cadence settings stay available.',
    hide_menus     = 'Hides all timers or selected timers while other game menus are open. Maps use Hide on the map. Ordinary chat typing does not count. Cadence settings stay available.',
    chat_timer    = 'Hides this timer while the full-screen chat log is open. Used only with Selected timers. Ordinary chat typing does not count.',
    menu_timer    = 'Hides this timer while other menus are open. Used only with Selected timers. Maps and ordinary chat typing do not count.',
    cant_see_chat_log = 'Full-screen chat log detection is unavailable on this game version. Your choice stays saved but has no effect until detection is available.',
    cant_see_menus = 'Menu detection is unavailable on this game version. Your choice stays saved but has no effect until detection is available.',
    reset_visibility = 'Restores All timers for both menu choices and selects every timer. Undo restores the previous choices.',
    drains         = 'Bars start full and empty out, instead of filling up.',
    show_timers    = 'Brings the timers back. Typing /cadence hide again or /cadence show does the same.',

    enemy_timer    = 'Shows when the monster you\'re fighting will attack next. It can\'t see a TP move coming.',
    follows        = 'Which monster the timer follows. "My target first" follows your target, and whoever is '
        .. 'hitting you when your target isn\'t fighting.',
    keep_last      = 'Keeps the timer on the monster it was following while you target a party member, an NPC or '
        .. 'nothing. It lets go once that monster dies, stops fighting or goes quiet for 10 s, longer for a slow one.',
    attached       = 'Puts the enemy timer right under your auto attack timer as a slim strip that moves with it. '
        .. 'With the auto attack timer off, it uses its own position and width.',
    enemy_value    = 'Shows the seconds until the monster\'s next attack, then "ready" when it can attack. It shows '
        .. '"waiting" once it\'s overdue by a whole attack, like while the monster is asleep or chasing you.',
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
    enemy_height   = 'How tall the whole enemy timer is, including its text and spacing. Width stays the same. Hold Shift and drag its bottom edge, including while attached.',
    enemy_bar      = 'How thick the bar is before the timer height is applied. Height changes the whole timer.',
    enemy_ready    = 'The bar\'s color once the monster can attack.',
    enemy_almost   = 'The bar turns this color just before the monster attacks.',
    enemy_at       = 'How many seconds before the monster\'s attack the almost ready color starts.',

    undo           = 'Takes back the last settings change. Up to eight changes stay available during this session.',
    preset         = 'Sets the timer and chat colors, card, text shadow and corners. Change one and it says Custom and '
        .. 'the preset you started from. Colorblind safe stays clear for red-green and blue-yellow colorblindness.',
    window_look    = 'Picking a preset also sets this window\'s colors, corners and spacing, the ones in the Window '
        .. 'and Window colors sections of Appearance. Off, presets leave this window as it is.',
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
        .. 'Text only, Ready mark, Drain instead of fill and this window\'s look and font back to default.',

    window_font    = 'This window\'s font. The timer font is on the Appearance tab. A wide one like Consolas stacks the '
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

    profiles       = 'Profiles are shared by every character. They hold your settings and timer positions, but leave '
        .. 'this window\'s position, size, hidden tabs and job links alone. Pick one to use its buttons.',
    profile_name   = 'Type a name here for Save as new or Rename. Picking a profile in the list puts its name here.',
    save_new       = 'Saves your settings as a new profile with the name in the box.',
    overwrite      = 'Saves your settings over the profile you picked.',
    load           = 'Loads the profile you picked. Undo restores the setup you had before loading it.',
    rename         = 'Gives the profile you picked the name in the box. Your job links to it follow.',
    delete         = 'Deletes the profile you picked, and your job links to it. Undo delete can bring back the last one until cadence unloads.',
    job_links      = 'Pick a profile for a main job, and it loads each time you change to that job and zone. Each '
        .. 'character has its own links. Profiles don\'t hold them, and /cadence reset all clears them.',
};

-- What each row of the Window colors section paints, by the row's name. Its swatches go in the same order.
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

-- The Window colors section's second column starts at this heading.
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
local current_preview, current_details;
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

local function mark_changed(save_now, label)
    result.changed, result.edited = true, true;
    result.label = label and label:gsub('##.*$', '') or result.label or 'Settings change';
    ui_state.layout_cache = nil;
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

function settings_window.search_width(label, limit, clear)
    local help_width = ITEM_GAP + imgui.CalcTextSize('(?)');
    local reserved = BOX_GAP + imgui.CalcTextSize(label) + help_width;
    if (clear) then reserved = reserved + ITEM_GAP + imgui.CalcTextSize('Clear') + BUTTON_PADDING + help_width; end
    return math.max(px(60), math.min(px(limit), imgui.GetContentRegionAvail() - reserved));
end

-- A (?) after a setting. Hovering it shows what the setting does, even when the setting is greyed out.
local function help(tip, label)
    search.mark(label, tip);
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
        help(tip, title);
    end
    imgui.Separator();
end

-- Searching opens a folded group temporarily, then restores its previous state.
local function section_open(title, default_open)
    local key = tostring(page_name) .. '/' .. title;
    local searching = search.active();
    if (searching or folded[key] ~= nil) then imgui.SetNextItemOpen(searching or folded[key], ImGuiCond_Always); end
    imgui.PushStyleColor(ImGuiCol_Text, look.headings);
    local shown = imgui.CollapsingHeader(title .. '##section', default_open == false and 0 or ImGuiTreeNodeFlags_DefaultOpen);
    imgui.PopStyleColor(1);
    search.mark(title);
    if (not searching) then folded[key] = shown; end
    return shown;
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
    help(tip, title);
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
    stacked = (page_width or imgui.GetWindowSize()) < two_columns_at;
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
        mark_changed(true, label);
    end
end

local function checkbox(label, table_, key, tip)
    tick_box(label, table_, key);
    help(tip, label);
end

-- A checkbox that's greyed out while `off` is true. Its (?) still works.
local function checkbox_unless(off, label, table_, key, tip)
    imgui.BeginDisabled(off);
    tick_box(label, table_, key);
    imgui.EndDisabled();
    help(tip, label);
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
        mark_changed(false, label);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        result.save = true;
    end
    imgui.EndDisabled();
    help(tip, label);
end

local function whole_slider(label, table_, key, range, format, tip, off, width)
    slider(imgui.SliderInt, label, table_, key, range, format, tip, off, width);
end

local function float_slider(label, table_, key, range, format, tip, off, width)
    slider(imgui.SliderFloat, label, table_, key, range, format, tip, off, width);
end

-- A color swatch that opens a picker. The settings color table is edited in place. A color dragged onto
-- the swatch never holds it the way the picker does, so it saves right away.
local function color(label, table_, key, flags)
    if (imgui.ColorEdit4(label, table_[key], flags or COLOR_FLAGS)) then
        mark_changed(not imgui.IsItemActive(), label);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        result.save = true;
    end
end

local function color_with_help(label, table_, key, tip)
    color(label, table_, key);
    help(tip, label);
end

-- A checkbox with its color swatch right after the label.
local function checkbox_with_color(label, table_, flag_key, color_key, tip, off)
    imgui.BeginDisabled(off == true);
    tick_box(label, table_, flag_key);
    imgui.SameLine();
    color('##' .. color_key .. label, table_, color_key);
    imgui.EndDisabled();
    help(tip, label);
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
        mark_changed(false, label);
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        result.save = true;
    end
    help(tip, label);
end

-- The timer size and bar thickness sliders. Bar height is greyed out while
-- it shows just numbers.
local function size_sliders(id, element, width_disabled)
    whole_slider('Width##' .. id, element, 'width', RANGES[id].width, '%d px', TIPS.width, width_disabled);
    float_slider('Height##' .. id, element, 'height_scale', RANGES[id].height_scale, '%.2fx', TIPS.height);
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
    help(TIPS.fill, 'Fill');
    imgui.SameLine(px(SECOND_COLUMN));
    color_with_help(end_label .. '##' .. id, element, end_key, end_tip);
end

-- Text only, and the mark on the bar where the almost ready color starts.
local function bar_toggles(id, element)
    checkbox('Text only##' .. id, element, 'numbers_only', TIPS.numbers_only);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox_unless(not element.almost_ready or element.numbers_only, 'Ready mark##' .. id, element, 'almost_mark',
        TIPS.almost_mark);
end

local function tp_goal_picker(attack)
    imgui.SetNextItemWidth(px(78));
    if (imgui.BeginCombo('TP goal##attack', tostring(attack.tp_goal))) then
        for _, goal in ipairs(defaults.TP_GOALS) do
            if (imgui.Selectable(tostring(goal), goal == attack.tp_goal)) then
                attack.tp_goal = goal;
                mark_changed(true);
            end
        end
        imgui.EndCombo();
    end
    help(TIPS.tp_goal, 'TP goal');
end


-- Button rows wrap at their available width.
function settings_window.flow(label, tip)
    local width = imgui.CalcTextSize(label:gsub('##.*$', '')) + BUTTON_PADDING;
    if (tip) then width = width + ITEM_GAP + imgui.CalcTextSize('(?)'); end
    local available = ui_state.flow_width or imgui.GetContentRegionAvail();
    if (ui_state.flow_used and ui_state.flow_used > 0 and ui_state.flow_used + ITEM_GAP + width <= available) then
        imgui.SameLine(); ui_state.flow_used = ui_state.flow_used + ITEM_GAP + width;
    else ui_state.flow_used = width; end
end
function settings_window.begin_buttons()
    ui_state.flow_width, ui_state.flow_used = imgui.GetContentRegionAvail(), 0;
end
function settings_window.open_details(section)
    local names = { attack = 'AUTO ATTACK', tp = 'TP', resting = 'RESTING', enemy = 'ENEMY' };
    if (section ~= nil and names[section] == nil) then return false; end
    query[1], details_query[1], copied = '', '', nil;
    ui_state.details_target = section and names[section] or nil;
    navigation.select('Details');
    return true;
end
function settings_window.set_inline_preview(value) ui_state.inline = value == true; end
function settings_window.inline_preview_enabled() return ui_state.inline; end
function settings_window.invalidate_preview()
    ui_state.layout_cache, ui_state.preview_dirty = nil, true;
end
function settings_window.preview_layout(id)
    if (workflow.layouts.find(id) == nil) then return false; end
    ui_state.layout, ui_state.preview_layout, ui_state.layout_cache = id, id, nil;
    query[1] = ''; navigation.select('Profiles');
    return true;
end
function settings_window.action_message(ok, message)
    status_ok, status = ok, message;
    ui_state.layout_cache = nil;
end
function settings_window.draw_toolbar(settings)
    local source = profiles.status(settings);
    if (source.name and source.name ~= '') then
        local prefix = source.modified and 'Modified from ' or 'Using ';
        local suffix = source.missing and ' (no longer available)' or '';
        local label = source.label or source.name;
        if (ui_state.source_label ~= label or ui_state.source_prefix ~= prefix or ui_state.source_suffix ~= suffix) then
            ui_state.source_label, ui_state.source_prefix, ui_state.source_suffix = label, prefix, suffix;
            ui_state.source_text = prefix .. label .. suffix;
        end
        note(ui_state.source_text);
    end
    settings_window.begin_buttons();
    settings_window.flow('Details##toolbar', true);
    if (imgui.Button('Details##toolbar')) then settings_window.open_details(); end
    help('Opens the inputs and sources behind the current estimates.', 'Details');
    settings_window.flow('Undo last change', true);
    imgui.BeginDisabled(workflow.history.status(settings) == nil);
    if (imgui.Button('Undo last change')) then result.undo_settings = true; end
    imgui.EndDisabled();
    help(workflow.history.status(settings) or 'No settings changes to undo in this session.', 'Undo last change');
    settings_window.flow('Reset this section', true);
    imgui.BeginDisabled(navigation.current() == 'Details');
    if (imgui.Button('Reset this section')) then result.reset_section = navigation.current():lower(); end
    imgui.EndDisabled();
    help('Resets this tab. Keeps positions, custom timer labels and saved profiles. Undo restores the previous choices.', 'Reset this section');
end

ui_state.rows = {
    attack = {
        { 'Seconds left##attack', 'show_value', 'attack_value', 'attack' },
        { 'Weapon delay##attack', 'show_delay', 'attack_delay', 'attack' },
        { 'Your TP', 'show_tp', 'tp', 'tp' },
        { 'Rounds to goal', 'show_tp_rounds', 'tp_rounds', 'tp', 'show_tp' },
        { 'Successful hits', 'show_tp_hits', 'tp_hits', 'tp', 'show_tp' },
        { 'Range / facing', 'show_reason', 'reason', 'attack' },
        { 'Why it stopped', 'show_why', 'why', 'attack' },
    },
    resting = {
        { 'Seconds left##resting', 'show_value', 'resting_value', 'resting' },
        { 'Last tick gains##resting', 'show_gains', 'gains', 'resting' },
        { 'Time until full##resting', 'show_until_full', 'until_full', 'resting' },
        { 'Full times##resting', 'show_each_full', 'each_full', 'resting' },
        { 'Ticks until full', 'show_ticks', 'ticks', 'resting' },
        { "Why it can't heal", 'show_why', 'cant_heal', 'resting' },
        { 'Next tick gains##resting', 'show_next_gains', 'next_gains', 'resting' },
    },
    enemy = {
        { 'Seconds left##enemy', 'show_value', 'enemy_value', 'enemy' },
        { 'Enemy name', 'show_name', 'enemy_name', 'enemy' },
        { 'Attack speed##enemy', 'show_delay', 'enemy_delay', 'enemy' },
        { 'Slow and haste', 'show_effects', 'enemy_effects', 'enemy' },
        { 'TP move / casting', 'show_holds', 'enemy_holds', 'enemy' },
    },
};
for id, rows in pairs(ui_state.rows) do
    for _, row in ipairs(rows) do
        row.options = 'Options##readout_' .. id .. '_' .. row[2];
        row.details = 'Details##readout_' .. id .. '_' .. row[2];
    end
end
function settings_window.draw_readouts(id, element)
    flag[1] = ui_state.enabled[id] == true;
    if (imgui.Checkbox('Enabled only##' .. id, flag)) then ui_state.enabled[id] = flag[1]; end
    help('Hides unchecked readouts from this list. Searching shows all matching controls. It changes no timer setting.', 'Enabled only');
    local wide = imgui.GetContentRegionAvail() >= px(560);
    local shown = 0;
    for _, row in ipairs(ui_state.rows[id]) do
        if (not ui_state.enabled[id] or element[row[2]] or search.active()) then
            shown = shown + 1;
            checkbox_unless(row[5] ~= nil and not element[row[5]], row[1], element, row[2], TIPS[row[3]]);
            local can_share = imgui.GetContentRegionAvail() > imgui.CalcTextSize(wide and 'Details' or 'Options') + BUTTON_PADDING + ITEM_GAP;
            if (can_share) then imgui.SameLine(); end
            if (wide) then
                if (imgui.SmallButton(row.details)) then settings_window.open_details(row[4]); end
                help('Shows the inputs and sources for this readout.', 'Details');
            else
                if (imgui.SmallButton(row.options)) then ui_state.options[row.options] = not ui_state.options[row.options]; end
                help('Opens the explanation and a link to this readout\'s inputs.', 'Options');
                if (ui_state.options[row.options]) then
                    note(TIPS[row[3]]);
                    if (imgui.SmallButton(row.details)) then settings_window.open_details(row[4]); end
                    help('Shows the inputs and sources for this readout.', 'Details');
                end
            end
        end
    end
    if (shown == 0) then note('No readouts enabled. Clear Enabled only to choose some.'); end
end

local function draw_attack_section(attack)
    heading_with_toggle('AUTO ATTACK TIMER', 'attack', attack, TIPS.attack_timer);
    local faded = fade_if_off(attack);
    flag[1] = attack.linger_seconds > 0;
    if (imgui.Checkbox('Show re-engage timer', flag)) then
        attack.linger_seconds = flag[1] and 1 or 0;
        mark_changed(true, 'Show re-engage timer');
    end
    help(TIPS.linger, 'Show re-engage timer');
    settings_window.draw_readouts('attack', attack);
    color('##tp_colorYour TP', attack, 'tp_color');
    imgui.SameLine(); imgui.TextUnformatted('TP color'); help(TIPS.tp, 'TP color');
    bar_toggles('attack', attack);
    whole_slider('Width##attack', attack, 'width', RANGES.attack.width, '%d px', TIPS.width);
    float_slider('Height##attack', attack, 'height_scale', RANGES.attack.height_scale, '%.2fx', TIPS.height);
    whole_slider('Bar height##attack', attack, 'bar_height', RANGES.attack.bar_height, '%d px', TIPS.bar_height,
        attack.numbers_only, px(78));
    bar_colors('attack', attack, 'ready_color', 'Ready', TIPS.attack_ready);
    checkbox_with_color('Almost ready##attack', attack, 'almost_ready', 'almost_color', TIPS.attack_almost);
    float_slider('Almost ready at##attack', attack, 'almost_seconds', RANGES.attack.almost_seconds, '%.1f s left',
        TIPS.attack_at, not attack.almost_ready);
    tp_goal_picker(attack);
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
    help(TIPS.sound, 'Sound');
    imgui.SameLine();
    if (imgui.Button('Refresh##sound')) then
        sound.refresh();
    end
    help(TIPS.sound_refresh, 'Refresh');
    whole_slider('Volume##sound', resting, 'sound_volume', RANGES.resting.sound_volume, '%d%%', TIPS.sound_volume);
    imgui.SameLine();
    imgui.BeginDisabled(resting.sound_file == '');
    if (imgui.Button('Play##sound')) then
        result.play_sound = true;
    end
    imgui.EndDisabled();
    help(TIPS.play_sound, 'Play');
    local problem = sound.problem(resting.sound_file);
    if (problem ~= nil) then
        note(problem, look.problem_messages);
    end
end

local function draw_resting_section(resting)
    heading_with_toggle('RESTING TIMER', 'resting', resting, TIPS.resting_timer);
    local faded = fade_if_off(resting);
    settings_window.draw_readouts('resting', resting);
    checkbox('Text only##resting', resting, 'numbers_only', TIPS.numbers_only);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Hide once full##resting', resting, 'hide_when_full', TIPS.hide_when_full);
    size_sliders('resting', resting);
    bar_colors('resting', resting, 'full_color', 'Full HP/MP', TIPS.full_color);
    checkbox_with_color('Flash on each tick', resting, 'flash_on_tick', 'flash_color', TIPS.flash);
    float_slider('Flash length', resting, 'flash_seconds', RANGES.resting.flash_seconds, '%.1f s', TIPS.flash_length,
        not resting.flash_on_tick, px(78));
    sound_rows(resting);
    end_fade(faded);
end

ui_state.visibility_modes = defaults.VISIBILITY_MODES;
ui_state.visibility_names = { off = 'Off', all = 'All timers', selected = 'Selected timers' };
ui_state.visibility_rows = {
    { key = 'chat', label = 'Full-screen chat log##visibility', tip = TIPS.hide_chat_log, unavailable = TIPS.cant_see_chat_log,
        timer_tip = TIPS.chat_timer, controls = {} },
    { key = 'menus', label = 'Other menus##visibility', tip = TIPS.hide_menus, unavailable = TIPS.cant_see_menus,
        timer_tip = TIPS.menu_timer, controls = {} },
};
for _, row in ipairs(ui_state.visibility_rows) do
    for _, timer in ipairs({ { 'attack', 'Auto attack' }, { 'resting', 'Resting' }, { 'enemy', 'Enemy attack' },
        { 'recovery', 'Action recovery' }, { 'enemycast', 'Enemy cast' } }) do
        row.controls[#row.controls + 1] = { label = timer[2] .. '##hide_' .. row.key .. '_' .. timer[1], key = row.key .. '_' .. timer[1] };
    end
end

function settings_window.draw_menu_visibility(visibility)
    if (not section_open('Menu visibility', false)) then return; end
    for _, row in ipairs(ui_state.visibility_rows) do
        local available = row.key == 'chat' and player.can_check_chat() or row.key == 'menus' and player.can_check_menus();
        imgui.BeginDisabled(not available);
        imgui.SetNextItemWidth(px(CONTROL_WIDTH));
        if (imgui.BeginCombo(row.label, ui_state.visibility_names[visibility[row.key]])) then
            for _, mode in ipairs(ui_state.visibility_modes) do
                if (imgui.Selectable(mode[2], visibility[row.key] == mode[1]) and visibility[row.key] ~= mode[1]) then
                    visibility[row.key] = mode[1];
                    mark_changed(true, row.label);
                end
            end
            imgui.EndCombo();
        end
        imgui.EndDisabled();
        help(available and row.tip or row.unavailable, row.label);
        if (visibility[row.key] == 'selected' or search.active()) then
            local any_selected = false;
            for i, control in ipairs(row.controls) do
                if (i % 2 == 0) then imgui.SameLine(px(SECOND_COLUMN)); end
                checkbox_unless(not available or visibility[row.key] ~= 'selected', control.label, visibility, control.key, row.timer_tip);
                any_selected = any_selected or visibility[control.key];
            end
            if (visibility[row.key] == 'selected' and not any_selected) then note('No timers selected.'); end
        end
    end
    if (imgui.SmallButton('Reset menu visibility')) then result.reset_section = 'visibility'; end
    help(TIPS.reset_visibility, 'Reset menu visibility');
end

-- Global game visibility choices, followed by menu rules for all or selected timers.
local function draw_all_timers(settings)
    local style = settings.style;
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
    settings_window.draw_menu_visibility(settings.visibility);
end

function settings_window.draw_recovery_section(recovery, attack)
    heading_with_toggle('ACTION RECOVERY', 'recovery', recovery, TIPS.recovery_timer);
    if (section_open('Recovery options', false)) then
        local faded = fade_if_off(recovery);
        checkbox('Attach under auto attack##recovery', recovery, 'attached', TIPS.recovery_attached);
        checkbox('Seconds left##recovery', recovery, 'show_value', TIPS.recovery_value);
        checkbox('Action source##recovery', recovery, 'show_source', TIPS.recovery_source);
        checkbox('Text only##recovery', recovery, 'numbers_only', TIPS.numbers_only);
        if (imgui.SmallButton('Edit label##recovery')) then query[1] = 'Recovery'; navigation.select('Appearance'); end
        help(TIPS.recovery_label, 'Edit recovery label');
        size_sliders('recovery', recovery, recovery.attached and attack and attack.enabled);
        color('##recovery_start', recovery, 'fill_start');
        imgui.SameLine();
        color('##recovery_end', recovery, 'fill_end');
        imgui.SameLine(); imgui.TextUnformatted('Fill'); help(TIPS.fill, 'Fill');
        end_fade(faded);
    end
end

-- Side by side, ALL TIMERS sits under the attack and recovery options. Stacked, it comes last.
local function draw_timers_tab(settings)
    if (begin_sections('##timer_sections')) then
        imgui.TableNextColumn();
        draw_attack_section(settings.attack);
        settings_window.draw_recovery_section(settings.recovery, settings.attack);
        if (not stacked) then
            draw_all_timers(settings);
        end
        next_section();
        draw_resting_section(settings.resting);
        imgui.EndTable();
    end
    if (stacked) then
        draw_all_timers(settings);
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
    help(TIPS.follows, 'Follows');
end

local function draw_enemy_section(enemy, style)
    heading_with_toggle('ENEMY ATTACK TIMER', 'enemy', enemy, TIPS.enemy_timer);
    local faded = fade_if_off(enemy);
    which_enemy_picker(enemy);
    checkbox_unless(enemy.which == 'attacker', 'Keep the last monster', enemy, 'keep_last', TIPS.keep_last);
    checkbox('Attach under auto attack', enemy, 'attached', TIPS.attached);
    settings_window.draw_readouts('enemy', enemy);
    -- On you shows on the name and the stripe. With neither on screen it has nothing to color.
    local nothing_to_color = not (style.show_labels and enemy.show_label) and not style.accent;
    checkbox_with_color('On you', enemy, 'show_on_you', 'on_you_color', TIPS.on_you,
        enemy.which == 'attacker' or nothing_to_color);
    end_fade(faded);
end

local function draw_enemy_look(enemy, attack)
    heading('ENEMY BAR');
    local faded = fade_if_off(enemy);
    bar_toggles('enemy', enemy);
    whole_slider('Width##enemy', enemy, 'width', RANGES.enemy.width, '%d px', TIPS.enemy_width, enemy.attached and attack.enabled);
    float_slider('Height##enemy', enemy, 'height_scale', RANGES.enemy.height_scale, '%.2fx', TIPS.enemy_height);
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
        if (not stacked) then settings_window.draw_enemycast_section(settings.enemycast, settings.enemy); end
        next_section();
        draw_enemy_look(settings.enemy, settings.attack);
        if (stacked) then
            next_section();
            settings_window.draw_enemycast_section(settings.enemycast, settings.enemy);
        end
        imgui.EndTable();
    end
end

function settings_window.draw_enemycast_section(cast, enemy)
    heading_with_toggle('ENEMY CAST', 'enemycast', cast, TIPS.enemycast_timer);
    if (section_open('Cast options', false)) then
        local faded = fade_if_off(cast);
        checkbox('Attach under enemy attack##enemycast', cast, 'attached', TIPS.enemycast_attached);
        checkbox('Spell name##enemycast', cast, 'show_spell', TIPS.enemycast_spell);
        checkbox('Seconds left##enemycast', cast, 'show_value', TIPS.enemycast_value);
        checkbox('Text only##enemycast', cast, 'numbers_only', TIPS.numbers_only);
        if (imgui.SmallButton('Edit label##enemycast')) then query[1] = 'Enemy cast'; navigation.select('Appearance'); end
        help(TIPS.enemycast_label, 'Edit enemy cast label');
        size_sliders('enemycast', cast, cast.attached and enemy and enemy.enabled);
        color('##enemycast_start', cast, 'fill_start');
        imgui.SameLine(); color('##enemycast_end', cast, 'fill_end');
        imgui.SameLine(); imgui.TextUnformatted('Fill'); help(TIPS.fill, 'Fill');
        end_fade(faded);
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
    help(TIPS.preset, 'Preset');
end

-- The PRESET heading, with Undo and Reset look at its right end like a timer's ON/OFF chip. They're
-- small buttons, so the heading stays one line of text tall.
local function preset_heading(settings)
    imgui.Spacing();
    local x = imgui.GetCursorPosX();
    local width = imgui.GetContentRegionAvail();
    local help_width = ITEM_GAP + imgui.CalcTextSize('(?)');
    local buttons_width = imgui.CalcTextSize('Undo') + imgui.CalcTextSize('Reset look') + BUTTON_PADDING * 2
        + ITEM_GAP + help_width * 2;
    imgui.TextColored(look.headings, 'PRESET');
    imgui.SameLine(x + width - buttons_width);
    imgui.BeginDisabled(workflow.history.status(settings) == nil);
    if (imgui.SmallButton('Undo')) then result.undo_settings = true; end
    imgui.EndDisabled();
    help(TIPS.undo, 'Undo');
    imgui.SameLine();
    if (imgui.SmallButton('Reset look')) then
        result.reset_look = true;
    end
    help(TIPS.reset_look, 'Reset look');
    imgui.Separator();
end

-- The LABELS heading, with Show labels at its right end like a timer's ON/OFF chip, since it turns the
-- whole section on or off.
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

-- The preset, sizes and labels, the left column of the Appearance tab.
local function draw_size_sections(settings)
    local style = settings.style;
    preset_heading(settings);
    preset_picker(settings);
    checkbox('Window matches the look', style, 'window_matches_look', TIPS.window_look);

    if (section_open('SIZE')) then
    float_slider('Scale', style, 'scale', RANGES.style.scale, '%.2fx', TIPS.scale);
    whole_slider('Text size', style, 'font_size', RANGES.style.font_size, '%d px', TIPS.text_size);
    -- The slider's left end is auto.
    local detail_format = (style.detail_size < defaults.DETAIL_SIZE[1]) and 'auto' or '%d px';
    whole_slider('Detail size', style, 'detail_size', RANGES.style.detail_size, detail_format, TIPS.detail_size);
    whole_slider('Corner roundness', style, 'rounding', RANGES.style.rounding, '%d px', TIPS.rounding);

    end
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
    label_box('Recovery##label', '##show_label_recovery', settings.recovery, 'ACTION RECOVERY', TIPS.recovery_label, labels_off);
    label_box('Enemy cast##label', '##show_label_enemycast', settings.enemycast, 'ENEMY CAST', TIPS.enemycast_label, labels_off);
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
    help(TIPS.font, 'Font');
end

-- Colors and where the timers sit, the right column of the Appearance tab.
local function draw_color_sections(style)
    if (section_open('CARD')) then
    checkbox_with_color('Background', style, 'panel', 'panel_color', TIPS.background);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox_with_color('Border', style, 'border', 'border_color', TIPS.border);
    checkbox_with_color('Accent stripe', style, 'accent', 'accent_color', TIPS.accent);

    end
    if (section_open('TEXT AND BAR')) then
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

    end
    if (section_open('POSITION')) then
    checkbox('Lock in place', style, 'locked', TIPS.locked);
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Share one spot', style, 'shared_spot', TIPS.shared_spot);
    flag[1] = shared_layout.is_on();
    if (imgui.Checkbox('One layout for all characters', flag)) then
        result.share_layout = flag[1];
    end
    help(TIPS.one_layout, 'One layout for all characters');
    if (imgui.Button('Reset positions')) then
        result.reset_positions = true;
    end
    help(TIPS.reset_spots, 'Reset positions');
    imgui.SameLine(px(SECOND_COLUMN));
    checkbox('Peek with Shift', style, 'see_through', TIPS.see_through);    end

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
    help(TIPS.window_font, 'Font');
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
    help(TIPS[part.key], part.name);
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
    help(TIPS.chat_sample, 'Print a sample');
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
    heading('TIMING DETAILS');
    checkbox('Timer hover help', settings.style, 'hover_tips', TIPS.hover_tips);
    checkbox('Record timing details', settings.style, 'record_diagnostics', TIPS.record);
    imgui.SameLine();
    if (imgui.Button('Save timing report')) then
        result.save_report = true;
    end
    help(TIPS.save_report, 'Save timing report');
end

-- One row of the Window colors section. Its name, then a swatch for each of its colors, then its (?). The
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
    help(WINDOW_COLOR_TIPS[row.name], row.name);
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
            if (section_open(group.name .. '##window_colors')) then
                for _, row in ipairs(group.rows) do window_color_row(row, name_width); end
            end
        end
        imgui.EndTable();
    end
end


ui_state.sample_choices = { { 'normal', 'Normal' }, { 'blocked', 'Blocked' }, { 'waiting', 'Waiting' }, { 'full', 'Full' }, { 'unknown', 'Unknown timing' } };
ui_state.sample_names = { normal = 'Normal', blocked = 'Blocked', waiting = 'Waiting', full = 'Full', unknown = 'Unknown timing' };
function settings_window.draw_inline_preview(settings, proposed)
    note(proposed and 'Starter layout sample. Apply it to use these choices.' or 'Sample timers. Your live timers keep running.');
    imgui.SetNextItemWidth(px(CONTROL_WIDTH));
    if (imgui.BeginCombo('State##inline_preview', ui_state.sample_names[ui_state.sample])) then
        for _, entry in ipairs(ui_state.sample_choices) do
            if (imgui.Selectable(entry[2], ui_state.sample == entry[1])) then ui_state.sample = entry[1]; end
        end
        imgui.EndCombo();
    end
    help('Shows a static sample of each enabled timer. It sends no actions and changes no live estimate.', 'Sample state');
    workflow.preview.draw(settings, ui_state.sample, result.edited or ui_state.preview_dirty);
    workflow.preview.chat(settings);
    ui_state.preview_dirty = false;
end
function settings_window.draw_tab_visibility(settings)
    if (not section_open('TABS', false)) then return; end
    note('Hide tabs you do not use. Their features keep working. Appearance always stays available.');
    settings_window.begin_buttons();
    for _, name in ipairs(navigation.TAB_NAMES) do
        if (name ~= 'Appearance') then
            flag[1] = navigation.visible(settings.window.tabs, name);
            settings_window.flow(name, true);
            if (imgui.Checkbox(name .. '##visible_tab', flag)) then
                if (navigation.set_visible(settings.window.tabs, name, flag[1])) then mark_changed(true, 'Show ' .. name); end
            end
            help('Shows this settings tab. Hiding it never disables its timers or features.', name);
        end
    end
    if (imgui.Button('Restore all tabs')) then
        if (navigation.restore(settings.window.tabs)) then mark_changed(true, 'Restore all tabs'); end
    end
    help('Shows every settings tab again.', 'Restore all tabs');
end
function settings_window.layout_metadata(id)
    ui_state.layout_list = ui_state.layout_list or workflow.layouts.list();
    for _, entry in ipairs(ui_state.layout_list) do if (entry.id == id) then return entry; end end
end
function settings_window.draw_starter_layouts(settings)
    heading('STARTER LAYOUTS');
    local selected = settings_window.layout_metadata(ui_state.layout);
    imgui.SetNextItemWidth(px(CONTROL_WIDTH));
    if (imgui.BeginCombo('Starter layout', selected.name)) then
        for _, entry in ipairs(ui_state.layout_list) do
            if (imgui.Selectable(entry.name, ui_state.layout == entry.id)) then
                ui_state.layout, ui_state.layout_cache = entry.id, nil;
                selected = entry;
            end
        end
        imgui.EndCombo();
    end
    help('Choose a set of timer readouts. Picking a name only changes this selection.', 'Starter layout');
    note(selected.description);
    for _, change in ipairs(selected.changes) do note(change); end
    settings_window.begin_buttons(); settings_window.flow('Preview layout', true);
    if (imgui.Button('Preview layout')) then ui_state.preview_layout, ui_state.layout_cache = selected.id, nil; end
    help('Shows sample timers with this layout before you apply it.', 'Preview layout');
    settings_window.flow('Apply layout', true);
    if (imgui.Button('Apply layout')) then result.apply_layout = selected.id; end
    help('Applies the listed choices. Keeps colors, fonts, positions and saved profiles. Undo restores your previous settings.', 'Apply layout');
    if (ui_state.preview_layout) then
        local cache = ui_state.layout_cache;
        if (cache == nil or cache.settings ~= settings or cache.id ~= ui_state.preview_layout) then
            local shown = workflow.layouts.preview(settings, ui_state.preview_layout);
            cache = { settings = settings, id = ui_state.preview_layout, shown = shown };
            ui_state.layout_cache = cache;
        end
        local shown = settings_window.layout_metadata(ui_state.preview_layout);
        note('Previewing ' .. shown.name .. '.');
        settings_window.draw_inline_preview(cache.shown, true);
        if (imgui.Button('Close layout preview')) then ui_state.preview_layout, ui_state.layout_cache = nil, nil; end
        help('Closes the sample without changing your setup.', 'Close layout preview');
    end
    imgui.Separator();
end

-- The window controls and colors stay together with the timers' appearance.
local function draw_appearance_tab(settings)
    flag[1] = ui_state.inline;
    if (imgui.Checkbox('Inline preview', flag)) then ui_state.inline = flag[1]; end
    help('Shows sample timers and chat here while you change their appearance. It changes no live timer or saved setting.', 'Inline preview');
    if (ui_state.inline and section_open('SAMPLE PREVIEW')) then settings_window.draw_inline_preview(settings); end
    settings_window.draw_tab_visibility(settings);
    draw_look_tab(settings);
    if (section_open('WINDOW')) then
        draw_window_tab(settings);
    end
    if (section_open('WINDOW COLORS')) then
        draw_window_colors_tab();
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
    elseif (not profiles.save(settings, name, true)) then
        return false, profiles.problem();
    end
    picked = name;
    mark_changed(true, 'Save as new');
    return true, ('Saved "%s" as a new profile.'):format(name);
end

local function overwrite_picked(settings)
    if (not profiles.save(settings, picked)) then
        return false, profiles.problem();
    end
    mark_changed(true, 'Overwrite');
    return true, ('The profile "%s" has your settings now.'):format(picked);
end

local function load_picked(settings)
    if (not profiles.load(settings, picked)) then
        return false, profiles.file_ok() and 'The profile you picked isn\'t there anymore.' or profiles.problem();
    end
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
    local ok, relinked, renamed_source = profiles.rename(settings, picked, name);
    if (not ok) then
        return false, profiles.problem();
    end
    if (relinked) then
        result.links = true;
    end
    if (renamed_source) then mark_changed(true, 'Rename'); end
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
    help(tip, label);
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
    help(TIPS.profile_name, 'Name');
    if (imgui.Button('Save as new')) then
        run_action(save_as_new, settings, false);
    end
    help(TIPS.save_new, 'Save as new');
    imgui.SameLine();
    profile_button('Overwrite', TIPS.overwrite, overwrite_picked, settings);
    profile_button('Load', TIPS.load, load_picked, settings);
    imgui.SameLine();
    profile_button('Rename', TIPS.rename, rename_picked, settings);
    imgui.SameLine();
    profile_button('Delete', TIPS.delete, delete_picked, settings);
    imgui.BeginDisabled(not profiles.can_undo_delete());
    if (imgui.Button('Undo delete')) then
        local ok, message, relinked = profiles.undo_delete(settings);
        status_ok = ok;
        if (ok) then status = ('Restored "%s".'):format(message);
        elseif (message == 'exists') then status = 'That profile name is already in use. Nothing was replaced.';
        elseif (message == 'none') then status = 'There is no deleted profile to restore.';
        else status = profiles.problem(); end
        if (ok) then result.changed, result.save = true, true; picked = nil; end
        if (relinked) then result.links = true; end
    end
    imgui.EndDisabled();
    help('Restores the last deleted profile without replacing a profile with the same name or a newer job link.', 'Undo delete');
    imgui.BeginDisabled(profiles.overwritten_name() == nil);
    if (imgui.Button('Undo overwrite')) then result.undo_overwrite = true; end
    imgui.EndDisabled();
    help('Restores the last overwritten profile only if nobody changed it afterward.', 'Undo overwrite');
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
    settings_window.draw_starter_layouts(settings);
    if (begin_sections('##profile_sections')) then
        imgui.TableNextColumn();
        draw_profiles_section(settings);
        next_section();
        draw_job_links(settings.job_links);
        imgui.EndTable();
    end
end

local PREVIEW_TIMERS = { { 'auto', 'Auto' }, { 'attack', 'Auto attack' }, { 'resting', 'Resting' }, { 'enemy', 'Enemy' },
    { 'recovery', 'Action recovery' }, { 'enemycast', 'Enemy cast' } };
local PREVIEW_STATES = { { 'normal', 'Normal' }, { 'blocked', 'Blocked' }, { 'waiting', 'Waiting' }, { 'full', 'Full' } };
ui_state.preview_states = {
    recovery = { { 'normal', 'Normal' }, { 'unknown', 'Unknown' } },
    enemycast = { { 'normal', 'Normal' }, { 'waiting', 'Waiting' } },
};
function settings_window.preview_states(timer)
    return ui_state.preview_states[timer] or PREVIEW_STATES;
end
function settings_window.valid_preview_state(timer, state)
    for _, entry in ipairs(settings_window.preview_states(timer)) do if (entry[1] == state) then return true; end end
    return false;
end
local GOAL_STATS = { { 'hp', 'HP' }, { 'mp', 'MP' }, { 'both', 'Both' } };
local GOAL_MODES = { { 'percent', 'Percent' }, { 'amount', 'Amount' } };
local EMPTY_DETAILS, DEFAULT_PREVIEW = {}, { timer = 'auto', state = 'normal', paused = false };
local RELEARN_ACTIONS = { { 'attack', 'Relearn attack', TIPS.relearn_attack },
    { 'tp', 'Relearn TP', TIPS.relearn_tp }, { 'enemy', 'Relearn enemy', TIPS.relearn_enemy } };
local details_size = { 0, 0 };
local cached_details, detail_lines;

local function choice(label, value, choices, tip)
    local selected, shown = value, choices[1][2];
    for _, entry in ipairs(choices) do if (entry[1] == value) then shown = entry[2]; end end
    imgui.SetNextItemWidth(px(CONTROL_WIDTH));
    if (imgui.BeginCombo(label, shown)) then
        for _, entry in ipairs(choices) do
            if (imgui.Selectable(entry[2], entry[1] == value)) then selected = entry[1]; end
        end
        imgui.EndCombo();
    end
    help(tip, label);
    return selected;
end

local function draw_preview_tab(settings)
    if (begin_sections('##preview_sections')) then
        imgui.TableNextColumn();
        heading('PREVIEW');
        note('Try the timers here. Your live timers keep running.');
        local previous = current_preview or DEFAULT_PREVIEW;
        local timer = choice('Timer##preview', previous.timer or 'auto', PREVIEW_TIMERS, TIPS.preview_timer);
        local previous_state = settings_window.valid_preview_state(timer, previous.state) and previous.state or 'normal';
        local state = choice('State##preview', previous_state, settings_window.preview_states(timer), TIPS.preview_state);
        local paused = previous.paused == true;
        flag[1] = paused;
        if (imgui.Checkbox('Pause preview', flag)) then paused = flag[1]; end
        help(TIPS.preview_pause, 'Pause preview');
        if (timer ~= (previous.timer or 'auto') or state ~= (previous.state or 'normal') or paused ~= (previous.paused == true)) then
            result.preview = { timer = timer, state = state, paused = paused };
        end
        heading('ALIGNMENT');
        checkbox('Alignment guides', settings.style, 'layout_guides', TIPS.layout_guides);
        note('Hold Shift and drag a timer to move it.');
        next_section();
        heading('GOALS');
        checkbox('Time to TP goal', settings.attack, 'show_tp_time', TIPS.tp_time);
        checkbox('Recovery goal', settings.resting, 'show_goal', TIPS.recovery_goal);
        imgui.BeginDisabled(not settings.resting.show_goal);
        local stat = choice('Resource##goal', settings.resting.goal_stat, GOAL_STATS, TIPS.goal_stat);
        local mode = choice('Measure##goal', settings.resting.goal_mode, GOAL_MODES, TIPS.goal_mode);
        if (stat ~= settings.resting.goal_stat or mode ~= settings.resting.goal_mode) then
            settings.resting.goal_stat, settings.resting.goal_mode = stat, mode;
            local range = mode == 'amount' and defaults.GOAL_AMOUNT or defaults.GOAL_PERCENT;
            settings.resting.goal_value = math.max(range[1], math.min(range[2], settings.resting.goal_value));
            mark_changed(true);
        end
        whole_slider('Goal##recovery', settings.resting, 'goal_value',
            mode == 'amount' and defaults.GOAL_AMOUNT or defaults.GOAL_PERCENT,
            mode == 'amount' and '%d' or '%d%%', TIPS.goal_value);
        imgui.EndDisabled();
        note('The usual time until full and full recovery sound keep their own settings.');
        imgui.EndTable();
    end
end

local EFFECT_NAMES = { [13] = 'Slow', [33] = 'Haste', [46] = 'Hundred Fists', [194] = 'Elegy' };
local FIELD_NAMES = {
    dexterity = 'DEX', store_tp = 'Store TP', hp_heal = 'HP while resting', mp_heal = 'MP while resting', clear_mind = 'Clear Mind',
    haste_gear = 'Gear haste', haste_magic = 'Magic haste', haste_ability = 'Ability haste',
    twohand_haste_ability = 'Two handed haste', desperate_blows = 'Desperate Blows',
    delay_flat = 'Delay', delay_percent = 'Delay percent', dual_wield = 'Dual Wield', martial_arts = 'Martial Arts',
    regen = 'Regen', refresh = 'Refresh', regen_down = 'HP drain', refresh_down = 'MP drain',
};
local function plain(value)
    return tostring(value or ''):gsub('[%c]', ' '):gsub('_', ' ');
end
local function amount(value, unit)
    if (type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge) then return 'waiting'; end
    return ('%.2f%s'):format(value, unit or '');
end
local function sample_note(entry, note)
    local count = entry.samples or entry.accepted or 0;
    local words = ('Samples: %d'):format(count);
    if (entry.rejected) then words = words .. ('  |  Not used: %d'):format(entry.rejected); end
    if (entry.sample_age) then words = words .. '  |  Last sample ' .. amount(entry.sample_age, ' s ago'); end
    note(words);
    if (entry.last_rejection) then note('Last sample not used: ' .. plain(entry.last_rejection)); end
end

local function contribution_text(entry)
    local value, unit = tonumber(entry.value) or 0, '';
    local field = tostring(entry.field);
    if (field:find('haste', 1, true) or field == 'desperate_blows') then value, unit = value / 100, '%';
    elseif (field == 'delay_flat') then value, unit = value / 1000, ' s';
    elseif (field == 'dual_wield' or field == 'delay_percent') then unit = '%';
    elseif (field == 'martial_arts') then unit = ' delay units'; end
    return (FIELD_NAMES[field] or plain(field)) .. ' ' .. ('%+.2f%s'):format(value, unit);
end

local function speed_details(speed, heading, note)
    heading('APPLIED ATTACK SPEED');
    if (speed == nil) then note('Waiting for speed inputs.'); return; end
    note(speed.known and 'Current speed inputs are known.' or 'Estimated: some speed inputs are unknown.');
    if (speed.hundred_fists) then
        note('Hundred Fists overrides haste, Dual Wield and percentage delay.');
    end
    for _, entry in ipairs({ { 'gear', 'Gear haste' }, { 'magic', 'Magic haste' },
        { 'ability', 'Ability haste' }, { 'combined', 'Combined haste' } }) do
        local part = speed[entry[1]];
        if (part) then
            local line = entry[2] .. ': ' .. amount(part.raw, '%') .. ' raw -> ' .. amount(part.effective, '%') .. ' applied';
            if (not speed.hundred_fists) then
                line = line .. ' | cap ' .. amount(part.cap, '%');
                if (part.minimum and part.raw and part.raw < part.minimum) then
                    line = line .. ', minimum ' .. amount(part.minimum, '%');
                end
            end
            note(line);
        end
    end
    note('Martial Arts: ' .. amount(speed.martial_arts, ' delay units') .. ' | Dual Wield: ' .. amount(speed.dual_wield, '%'));
    note('Flat delay: ' .. amount(speed.delay_flat and speed.delay_flat / 1000, ' s')
        .. ' | Percentage delay: ' .. amount(speed.delay_percent, '%'));
    note('Modeled interval: ' .. amount(speed.modeled_interval, ' s') .. (speed.known and '' or ' (estimated)'));
    if (speed.limit_adjustment and speed.limit_adjustment ~= 0) then
        note('Interval limit: ' .. amount(speed.before_limit, ' s') .. ' -> ' .. amount(speed.modeled_interval, ' s')
            .. ' | allowed ' .. amount(speed.minimum_interval, ' s') .. ' to ' .. amount(speed.maximum_interval, ' s'));
    end
    local unknown = speed.unknown or {};
    for i = 1, #unknown do note('Unknown speed input: ' .. plain(unknown[i])); end
end

local function blue_details(blue, heading, note)
    heading('BLUE MAGIC');
    if (blue == nil) then note('Waiting for BLU set evidence.'); return; end
    if (blue.active == false or blue.status == 'inactive') then
        note(blue.role == 'sub' and 'BLU subjob traits are inactive.' or 'BLU is not active for this job setup.');
        return;
    end
    local role = blue.role == 'sub' and 'sub' or 'main';
    note('BLU ' .. role .. ' Lv. ' .. tostring(blue.level or '?'));
    local confirmed = blue.status == 'confirmed';
    if (confirmed) then
        note('Confirmed set. Eligible spell bonuses and traits can apply.');
    elseif (blue.status == 'provisional') then
        note('Provisional set candidate. These spell bonuses and traits are not applied until the set is confirmed.');
    else
        note('The current spell set is unknown. BLU bonuses remain estimated until the set is confirmed.');
        return;
    end
    local traits = blue.traits or {};
    if (#traits == 0) then note('No relevant trait threshold is met by this set.'); end
    for _, trait in ipairs(traits) do
        local state = 'not applied';
        if (not confirmed) then state = 'candidate, not applied';
        elseif (trait.overridden) then state = 'native trait takes precedence';
        elseif (trait.applied) then state = 'applied'; end
        note(plain(trait.name or trait.id) .. ' rank ' .. tostring(trait.tier or trait.rank or '?')
            .. ': ' .. tostring(trait.points or '?') .. ' points / ' .. tostring(trait.required or '?')
            .. ' required | ' .. state);
        for _, entry in ipairs(trait.contributions or {}) do note('  Trait bonus: ' .. contribution_text(entry)); end
    end
    local spells = blue.spells or {};
    note(('Set spells: %d'):format(#spells));
    for _, spell in ipairs(spells) do
        local state = spell.eligible and 'eligible' or 'above current BLU level';
        if (spell.level == nil) then state = 'not in the current source profile'; end
        if (not confirmed) then state = 'candidate, ' .. state; end
        note(plain(spell.name or spell.id) .. ' (Lv. ' .. tostring(spell.level or '?') .. ') | ' .. state);
    end
    for _, entry in ipairs(blue.direct_contributions or {}) do
        local state = confirmed and entry.applied and 'applied' or 'not applied';
        note('Spell bonus: ' .. plain(entry.name or entry.id) .. ' | ' .. contribution_text(entry) .. ' | ' .. state);
    end
end

local function build_estimate_details(details)
    local lines = {};
    local function heading(text) lines[#lines + 1] = { heading = text }; end
    local function note(text) lines[#lines + 1] = { text = text }; end
    local a, t, r, e, m = details.attack, details.tp, details.resting, details.enemy, details.modifiers;
    heading('AUTO ATTACK');
    if (a and a.reengage) then
        local tips = require('ui.tips');
        for line in tips.text('attack', details):gmatch('[^\n]+') do note(line); end
        note('Sampled attack interval: ' .. amount(a.reengage.sampled_delay, ' s'));
    elseif (a) then
        note('In use: ' .. amount(a.delay, ' s') .. '  |  ' .. plain(a.source));
        note('Model: ' .. amount(a.modeled_delay, ' s'));
        if (a.next_interval_changed) then
            note('Following interval: ' .. amount(a.next_interval_model, ' s') .. '. The current countdown keeps its place.');
        end
        sample_note(a, note);
        if (a.holding or a.reason) then note('Paused: ' .. plain(a.holding or a.reason)); end
    else note('Waiting for your first attack.'); end
    speed_details(details.speed, heading, note);
    heading('TP');
    if (t) then
        note('TP per hit: ' .. amount(t.per_hit) .. '  |  ' .. plain(t.source));
        note('Model: ' .. amount(t.modeled_per_hit) .. '  |  Hits per round: ' .. amount(t.hits_per_round));
        sample_note(t, note);
        if (t.transition) then note('Waiting for a gear or effect change to settle.'); end
    else note('Waiting for TP data.'); end
    heading('RESTING');
    if (r) then
        note('Next tick: ' .. amount(r.next_hp) .. ' HP  |  ' .. amount(r.next_mp) .. ' MP');
        note(r.pattern_known and 'Recovery pattern observed.' or 'Recovery pattern still estimated.');
        sample_note(r, note);
        if (r.last_decision) then note('Last sample: ' .. plain(r.last_decision)); end
        if (r.blocked) then note('Recovery is currently blocked.'); end
    else note('Waiting for recovery data.'); end
    heading('ENEMY');
    if (e) then
        note('Interval: ' .. amount(e.delay, ' s') .. '  |  ' .. plain(e.source));
        sample_note(e, note);
        if (e.waiting) then note('Waiting for the next attack.'); end
        if (e.holding) then note('Observed hold: ' .. plain(e.holding)); end
        for _, effect in ipairs(e.effects or {}) do
            note((effect.control and plain(effect.control) or EFFECT_NAMES[effect.id] or ('Effect ' .. tostring(effect.id)))
                .. (effect.uncertain and ' | duration uncertain' or ''));
            if (effect.power ~= nil) then note('  Speed amount: ' .. amount(effect.power / 100, '%')
                .. (effect.exact and ' (known)' or ' (estimated)')); end
            if (effect.duration_estimate) then note('  Cast-time duration estimate: ' .. amount(effect.duration_estimate, ' s')
                .. ' before resists, not time remaining.'); end
            if (effect.duration_basis) then note('  Duration source: ' .. plain(effect.duration_basis)); end
            if (effect.inputs_known == false) then note('  Some cast inputs are unknown.'); end
            local inputs = effect.cast_inputs;
            if (inputs) then
                note('  Cast inputs: gear ' .. (inputs.equipment_known and 'read' or 'unknown')
                    .. ', buffs ' .. (inputs.buffs_known and 'read' or 'unknown')
                    .. ', merits ' .. (inputs.merits_known and 'read' or 'unknown'));
                for _, item in ipairs(inputs.equipment or {}) do
                    note('  Cast gear: item ' .. tostring(item.id) .. ', slot ' .. tostring(item.slot)
                        .. (item.augment and ', augment ' .. tostring(item.augment) or '')
                        .. (item.song_bonus and ', song bonus ' .. tostring(item.song_bonus) or '')
                        .. (item.duration_percent and ', duration ' .. tostring(item.duration_percent) .. '%' or ''));
                end
                if (inputs.buffs and inputs.buffs.troubadour) then note('  Troubadour was active at the cast.'); end
                if (inputs.merits) then
                    if (inputs.merits.slow_ii ~= nil) then note('  Slow II merits at cast: ' .. tostring(inputs.merits.slow_ii)); end
                    if (inputs.merits.enfeebling_duration ~= nil) then note('  Enfeebling duration merits at cast: ' .. tostring(inputs.merits.enfeebling_duration)); end
                end
            end
        end
    else note('No enemy timing data yet.'); end
    blue_details(m and m.blue_magic, heading, note);
    heading('UNKNOWN INPUTS');
    local unknown = m and m.unknown or {};
    if (#unknown == 0) then note(m and 'No missing modifier inputs in this model.' or 'Waiting for modifier data.'); end
    for i = 1, #unknown do note(plain(unknown[i])); end
    if (m and m.evidence) then
        if (m.evidence.age) then note('Inputs read ' .. amount(m.evidence.age, ' s ago')); end
        if (m.evidence.blue_status == 'provisional') then note('The BLU memory candidate is provisional. A normal job update confirms the set.'); end
    end
    heading('MODEL CONTRIBUTIONS');
    local contributions = m and m.contributions or {};
    if (#contributions == 0) then note('No separate contributions to show.'); end
    for i = 1, #contributions do
        local c = contributions[i];
        note(plain(c.kind) .. (c.name and ' / ' .. plain(c.name) or '') .. ': ' .. contribution_text(c)
            .. (c.estimated and ' (estimated)' or ''));
    end
    return lines;
end

function settings_window.detail_groups(details)
    local groups, group = {}, nil;
    for _, line in ipairs(build_estimate_details(details or EMPTY_DETAILS)) do
        if (line.heading) then
            group = { title = line.heading, lines = {} };
            groups[#groups + 1] = group;
        else group.lines[#group.lines + 1] = line.text; end
    end
    for _, entry in ipairs(groups) do entry.text = entry.title .. '\n' .. table.concat(entry.lines, '\n'); end
    return groups;
end

function settings_window.details_text(details, value, target)
    local out = {};
    for _, group in ipairs(settings_window.detail_groups(details)) do
        if (search.matches(group.text, value) and (target == nil or group.title == target
            or target == 'AUTO ATTACK' and group.title == 'APPLIED ATTACK SPEED')) then out[#out + 1] = group.text; end
    end
    return #out > 0 and table.concat(out, '\n\n') or 'No matching details.';
end

function settings_window.detail_matches(group)
    return search.matches(group.text, details_query[1]) and (ui_state.details_target == nil
        or group.title == ui_state.details_target
        or ui_state.details_target == 'AUTO ATTACK' and group.title == 'APPLIED ATTACK SPEED');
end

local function draw_details_tab()
    heading('WHY THIS ESTIMATE');
    local wide = imgui.GetContentRegionAvail() >= px(600);
    for i, action in ipairs(RELEARN_ACTIONS) do
        if (i > 1 and wide) then imgui.SameLine(); end
        if (imgui.Button(action[2])) then result.relearn = action[1]; end
        help(action[3], action[2]);
    end
    imgui.SetNextItemWidth(settings_window.search_width('Find details', 230, details_query[1] ~= '' or ui_state.details_target ~= nil));
    if (imgui.InputText('Find details', details_query, 128)) then copied, ui_state.details_target = nil, nil; end
    help('Finds matching sections by their names, inputs and source notes. Clear the search to show all sections.', 'Find details');
    if (details_query[1] ~= '' or ui_state.details_target ~= nil) then
        imgui.SameLine();
        if (imgui.Button('Clear##details')) then details_query[1], copied, ui_state.details_target = '', nil, nil; end
        help('Clears the details search.', 'Clear');
    end
    local details = current_details or EMPTY_DETAILS;
    if (imgui.Button('Copy shown')) then
        local ok = pcall(imgui.SetClipboardText, settings_window.details_text(details, details_query[1], ui_state.details_target));
        copied = ok and 'Copied shown details.' or 'Copy is unavailable. The details remain below.';
    end
    help('Copies every section matching the details search, including folded groups.', 'Copy shown');
    imgui.SameLine();
    if (imgui.Button('Copy all')) then
        local ok = pcall(imgui.SetClipboardText, settings_window.details_text(details, ''));
        copied = ok and 'Copied all details.' or 'Copy is unavailable. The details remain below.';
    end
    help('Copy shown includes every search match, even folded groups. Copy all ignores the search and includes every section and contribution.', 'Copy all');
    if (copied) then note(copied); end
    if (details ~= cached_details or detail_lines == nil) then
        cached_details, detail_lines = details, settings_window.detail_groups(details);
    end
    local matches = 0;
    for _, group in ipairs(detail_lines) do if (settings_window.detail_matches(group)) then matches = matches + 1; end end
    note(('Showing %d of %d sections.'):format(matches, #detail_lines));
    local _, room = imgui.GetContentRegionAvail();
    details_size[2] = math.max(1, room - px(8));
    local nested = room >= px(100);
    if (not nested or imgui.BeginChild('##estimate_details', details_size, 0)) then
        for _, group in ipairs(detail_lines) do
            if (settings_window.detail_matches(group)) then
                local searching = details_query[1]:find('%S') ~= nil or ui_state.details_target ~= nil;
                if (searching or detail_folded[group.title] ~= nil) then
                    imgui.SetNextItemOpen(searching or detail_folded[group.title], ImGuiCond_Always);
                end
                imgui.PushStyleColor(ImGuiCol_Text, look.headings);
                local shown = imgui.CollapsingHeader(group.title, ImGuiTreeNodeFlags_DefaultOpen);
                imgui.PopStyleColor(1);
                if (not searching) then detail_folded[group.title] = shown; end
                if (shown) then
                    for _, line in ipairs(group.lines) do note(line); end
                end
            end
        end
        if (matches == 0) then note('No matching details. Clear the search to show everything.'); end
    end
    if (nested) then imgui.EndChild(); end
end

-- The tabs in order, each drawn by its function.
local TABS = {
    { 'Timers',        draw_timers_tab },
    { 'Enemy',         draw_enemy_tab },
    { 'Appearance',    draw_appearance_tab },
    { 'Preview',       draw_preview_tab },
    { 'Details',       draw_details_tab },
    { 'Profiles',      draw_profiles_tab },
};

local SEARCH_WORDS = {
    ['Timers'] = table.concat({ 'Timers Seconds left attack Weapon delay attack Your TP Width attack Bar height attack Almost ready attack Range / facing Almost ready at attack Why it stopped  Text only  ALL TIMERS Hide during events Seconds left resting Last tick gains resting Time until full resting Full times resting Text only resting Hide once full resting Flash on each tick Flash length Ticks until full Why it can\'t heal Next tick gains resting Width  Bar height  Refresh sound Volume sound Play sound Rounds to goal Successful hits Ready mark TP goal Hide on the map Hide with the game UI Full HP/MP', TIPS.attack_timer, TIPS.attack_value, TIPS.attack_delay, TIPS.tp, TIPS.tp_rounds, TIPS.width, TIPS.height, TIPS.bar_height, TIPS.tp_hits, TIPS.attack_ready, TIPS.attack_almost, TIPS.reason, TIPS.attack_at, TIPS.why, TIPS.numbers_only, TIPS.almost_mark, TIPS.fill, TIPS.tp_goal, TIPS.hide_events, TIPS.hide_on_map, TIPS.cant_see_map, TIPS.hide_ui, TIPS.cant_see_ui, TIPS.resting_timer, TIPS.resting_value, TIPS.gains, TIPS.until_full, TIPS.each_full, TIPS.hide_when_full, TIPS.full_color, TIPS.flash, TIPS.flash_length, TIPS.ticks, TIPS.cant_heal, TIPS.next_gains, TIPS.sound, TIPS.sound_refresh, TIPS.sound_volume, TIPS.play_sound }, ' '),
    ['Enemy'] = table.concat({ 'Enemy Attach under auto attack Seconds left enemy Enemy name Attack speed enemy Slow and haste TP move / casting On you  ENEMY BAR Width enemy Bar height enemy Almost ready enemy Almost ready at enemy Text only ', TIPS.enemy_timer, TIPS.keep_last, TIPS.attached, TIPS.enemy_value, TIPS.enemy_name, TIPS.enemy_delay, TIPS.enemy_effects, TIPS.enemy_holds, TIPS.on_you, TIPS.follows, TIPS.enemy_width, TIPS.enemy_height, TIPS.enemy_bar, TIPS.enemy_ready, TIPS.enemy_almost, TIPS.enemy_at, TIPS.numbers_only, TIPS.almost_mark, TIPS.fill }, ' '),
    ['Appearance'] = table.concat({ 'Appearance Window matches the look SIZE Scale Text size Detail size Corner roundness Label size Auto attack label Resting label Enemy label Undo Reset look Show labels CARD Background Border Accent stripe TEXT AND BAR Labels text Values text Details text Bar track text Text outline Text shadow Drain instead of fill POSITION Lock in place Share one spot Reset positions Peek with Shift One layout for all characters Preset Font', TIPS.window_look, TIPS.scale, TIPS.text_size, TIPS.detail_size, TIPS.rounding, TIPS.label_size, TIPS.attack_label, TIPS.resting_label, TIPS.enemy_label, TIPS.undo, TIPS.reset_look, TIPS.preset, TIPS.show_labels, TIPS.background, TIPS.border, TIPS.accent, TIPS.label_color, TIPS.value_color, TIPS.detail_color, TIPS.track_color, TIPS.text_outline, TIPS.text_shadow, TIPS.drains, TIPS.locked, TIPS.shared_spot, TIPS.one_layout, TIPS.reset_spots, TIPS.see_through, TIPS.font }, ' '),
    ['Window'] = table.concat({ 'Window FONT Font size window SHAPE Corner roundness window Spacing window TIMING DETAILS Timer hover help Record timing details Save timing report CHAT Print a sample Tag brackets Tag word Replies', TIPS.window_size, TIPS.window_corners, TIPS.window_spacing, TIPS.hover_tips, TIPS.record, TIPS.save_report, TIPS.window_font, TIPS.chat_sample, TIPS.tag_brackets, TIPS.tag_word, TIPS.replies }, ' '),
    ['Window colors'] = table.concat({ 'Window colors ' }, ' '),
    ['Preview'] = table.concat({ 'Preview PREVIEW ALIGNMENT Alignment guides GOALS Time to TP goal Recovery goal Goal recovery Timer State Pause preview Resource Measure ', TIPS.preview_timer, TIPS.preview_state, TIPS.preview_pause, TIPS.layout_guides, TIPS.tp_time, TIPS.recovery_goal, TIPS.goal_stat, TIPS.goal_mode, TIPS.goal_value }, ' '),
    ['Details'] = table.concat({ 'Details WHY THIS ESTIMATE Relearn attack Relearn TP Relearn enemy Find details Clear details Copy shown Copy all AUTO ATTACK TP RESTING ENEMY UNKNOWN INPUTS MODEL CONTRIBUTIONS APPLIED ATTACK SPEED BLUE MAGIC', 'Store TP hHP hMP BLU Blue Magic spell trait set haste slow food equipment augments unknown inputs model samples copy contribution', TIPS.relearn_attack, TIPS.relearn_tp, TIPS.relearn_enemy }, ' '),
    ['Profiles'] = table.concat({ 'Profiles PROFILES Name Save as new Overwrite Undo delete JOB LINKS', TIPS.profiles, TIPS.profile_name, TIPS.save_new, TIPS.overwrite, TIPS.load, TIPS.rename, TIPS.delete, TIPS.job_links }, ' '),
};
for _, group in ipairs(theme.WINDOW_COLOR_GROUPS) do
    SEARCH_WORDS['Window colors'] = SEARCH_WORDS['Window colors'] .. ' ' .. group.name;
    for _, row in ipairs(group.rows) do
        SEARCH_WORDS['Window colors'] = SEARCH_WORDS['Window colors'] .. ' ' .. row.name .. ' ' .. (WINDOW_COLOR_TIPS[row.name] or '');
    end
end

SEARCH_WORDS.Appearance = table.concat({ SEARCH_WORDS.Appearance, SEARCH_WORDS.Window,
    SEARCH_WORDS['Window colors'] }, ' ');
SEARCH_WORDS.Window, SEARCH_WORDS['Window colors'] = nil, nil;
SEARCH_WORDS.Appearance = SEARCH_WORDS.Appearance .. ' Inline preview Sample state TABS Restore all tabs';
SEARCH_WORDS.Profiles = SEARCH_WORDS.Profiles .. ' STARTER LAYOUTS Starter layout Preview layout Apply layout Close layout preview Minimal Melee TP Resting Enemy tracking Undo overwrite Modified from';
SEARCH_WORDS.Timers = SEARCH_WORDS.Timers .. ' Enabled only Options TP color Details Show re-engage timer cooldown ' .. TIPS.linger;
SEARCH_WORDS.Timers = table.concat({ SEARCH_WORDS.Timers, ' Menu visibility Full-screen chat log Other menus Off All timers Selected timers Auto attack Resting Enemy attack Action recovery Enemy cast Reset menu visibility',
    TIPS.hide_chat_log, TIPS.hide_menus, TIPS.chat_timer, TIPS.menu_timer, TIPS.reset_visibility }, ' ');
SEARCH_WORDS.Timers = table.concat({ SEARCH_WORDS.Timers, ' ACTION RECOVERY Recovery options Action source recovery Attach under auto attack Width Height Bar height Text only',
    TIPS.recovery_timer, TIPS.recovery_value, TIPS.recovery_source, TIPS.recovery_attached }, ' ');
SEARCH_WORDS.Appearance = SEARCH_WORDS.Appearance .. ' Recovery label ' .. TIPS.recovery_label;
SEARCH_WORDS.Preview = SEARCH_WORDS.Preview .. ' Action recovery';
SEARCH_WORDS.Enemy = table.concat({ SEARCH_WORDS.Enemy, ' ENEMY CAST Cast options Attach under enemy attack Spell name Width Height Bar height Text only',
    TIPS.enemycast_timer, TIPS.enemycast_attached, TIPS.enemycast_spell, TIPS.enemycast_value }, ' ');
SEARCH_WORDS.Appearance = SEARCH_WORDS.Appearance .. ' Enemy cast label ' .. TIPS.enemycast_label;
SEARCH_WORDS.Preview = SEARCH_WORDS.Preview .. ' Enemy cast';
SEARCH_WORDS.Enemy = SEARCH_WORDS.Enemy .. ' Enabled only Options Details';
for name, words in pairs(SEARCH_WORDS) do SEARCH_WORDS[name] = words .. ' Undo last change Reset this section'; end

function settings_window.search_tabs(value)
    if (value == matched_query and matched_tabs ~= nil) then return matched_tabs; end
    local matches = {};
    for name, words in pairs(SEARCH_WORDS) do matches[name] = search.matches(words, value); end
    matched_query, matched_tabs = value, matches;
    return matches;
end
function settings_window.needs_details()
    return open[1] and navigation.current() == 'Details';
end
function settings_window.select_tab(name)
    query[1] = '';
    return navigation.select(name);
end
function settings_window.draw_page(tab, settings)
    page_name, page_width = tab[1], imgui.GetWindowSize();
    search.begin_page(page_name);
    local width, room = imgui.GetContentRegionAvail();
    local _, footer_height = imgui.CalcTextSize(FOOTER, false, width);
    local footer_room = footer_height + look.spacing * 3 + 4;
    local show_footer = room > footer_room + px(180);
    page_size[2] = math.max(1, room - (show_footer and footer_room or px(8)));
    if (imgui.BeginChild('##page_' .. page_name, page_size, 0,
        ImGuiWindowFlags_NoSavedSettings)) then tab[2](settings); search.finish_page(); end
    imgui.EndChild();
    search.begin_page(nil);
    if (show_footer) then imgui.Separator(); note(FOOTER); end
end

local function draw_current_page(tab) settings_window.draw_page(tab, current_settings); end

-- Another character logged in. The open window moves to their spot and size on the next frame. ImGui
-- would leave it where it is, and its old spot would save over theirs.
function settings_window.place_again()
    place_now = true;
end

--[[
    Where the window opens. It's where you left it, at the size you left it. On a smaller screen the
    size gets cut down to fit. A window left hanging off an edge gets pulled back so all of it shows.
    The smallest size has room for one column. Tabs wrap. It grows with the font size, and
    gets cut down to fit a small screen too.
]]
local function place_window(window, extra)
    local screen = imgui.GetIO().DisplaySize;
    min_size[1] = math.min(px(COLUMN_WIDTH) + WINDOW_EDGES, screen.x);
    min_size[2] = math.min(px(MIN_HEIGHT + extra), screen.y);
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
function settings_window.draw(settings, version, timers_hidden, shift, preview, details)
    result.changed, result.save, result.reset_positions, result.reset_look = false, false, false, false;
    result.share_layout, result.show_timers, result.sample, result.links = nil, false, false, false;
    result.sound_picked, result.play_sound, result.save_report = false, false, false;
    result.preview, result.relearn = nil, nil;
    result.undo_settings, result.reset_section, result.apply_layout, result.undo_overwrite = nil, nil, nil, nil;
    result.edited, result.label = false, nil;
    result.editing = false;
    current_preview, current_details = preview, details;
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
    local source = profiles.status(settings);
    local extra = (timers_hidden and 32 or 0) + (query[1]:find('%S') and 64 or 0)
        + (source.name and source.name ~= '' and 48 or 0);
    place_window(settings.window, extra);
    if (imgui.Begin('cadence##cadence_settings', open, peek and PEEK_FLAGS or WINDOW_FLAGS)) then
        remember_window(settings.window);
        -- The version goes on its own line when the subtitle doesn't fit, so it never breaks at a dot.
        local subtitle = ('Attack, resting, enemy and recovery timers for Phoenix  |  v%s'):format(version);
        if (imgui.CalcTextSize(subtitle) > imgui.GetContentRegionAvail()) then
            subtitle = ('Attack, resting, enemy and recovery timers for Phoenix\nv%s'):format(version);
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

        imgui.SetNextItemWidth(settings_window.search_width('Find settings', 260, query[1] ~= ''));
        imgui.InputText('Find settings', query, 128);
        help('Finds tabs by their controls and help, highlights matches, and scrolls to the first match. Every word must match.');
        if (query[1] ~= '') then
            imgui.SameLine();
            if (imgui.Button('Clear##settings')) then query[1] = ''; end
            help('Clears the settings search and shows every tab.');
        end
        settings_window.draw_toolbar(settings);
        search.query(query[1], look.headings);
        if (search.active()) then
            local at, count = search.status(navigation.current());
            settings_window.begin_buttons(); settings_window.flow('Previous match', false);
            imgui.BeginDisabled(count == 0);
            if (imgui.Button('Previous match')) then search.step(-1, navigation.current()); end
            settings_window.flow('Next match', false);
            if (imgui.Button('Next match')) then search.step(1, navigation.current()); end
            imgui.EndDisabled();
            local key = tostring(at) .. '/' .. tostring(count);
            if (ui_state.match_key ~= key) then ui_state.match_key, ui_state.match_text = key, ('%d of %d matches on this tab'):format(at, count); end
            note(ui_state.match_text);
        end
        local matches = settings_window.search_tabs(query[1]);
        current_settings = settings;
        ui_state.search_options.searching = search.active();
        if (navigation.draw(TABS, look, matches, draw_current_page, settings.window.tabs, ui_state.search_options)) then
            mark_changed(true, 'Show settings tab');
        end
        -- The next frame's Shift check reads this. A timer you're dragging is in its own window, so it doesn't count.
        result.editing = imgui.IsAnyItemActive();
        busy = result.editing and imgui.IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows);
    end
    imgui.End();
    imgui.PopFont();
    theme.pop_window_style(color_count, var_count);

    return result;
end

return settings_window;
