addon.name    = 'cadence';
addon.author  = 'Kipling';
addon.version = '1.0.0';
addon.desc    = 'Auto attack, resting tick and enemy attack timers for Phoenix.';
addon.link    = 'https://github.com/KiplingFFXI/cadence';

--[[
    cadence only reads the game. It listens to packets the server already sent you, reads values
    already in game memory, checks whether Shift is held, and draws what it finds. It never sends
    anything to the server, hides anything the server sends, writes to game memory or sends commands
    to the game. If you turn the resting sound on, Windows plays the sound file you picked once
    resting fills your HP and MP.
]]

require('common');

local ffi      = require('ffi');
local settings = require('settings');

local packets  = require('core.packets');
local player   = require('core.player');
local delay    = require('core.delay');
local attack   = require('core.attack');
local reach    = require('core.reach');
local resting  = require('core.resting');
local enemy    = require('core.enemy');
local monster_effects = require('core.monster_effects');
local tp       = require('core.tp');
local shared_layout = require('core.shared_layout');
local defaults = require('ui.defaults');
local theme    = require('ui.theme');
local hud      = require('ui.hud');
local presets  = require('ui.presets');
local window_font = require('ui.window_font');
local chat_colors = require('ui.chat_colors');
local profiles = require('ui.profiles');
local sound    = require('ui.sound');
local settings_window = require('ui.settings_window');

ffi.cdef[[
    short __stdcall GetAsyncKeyState(int vKey);
]];

-- Entity status values (LSB data/enums/animation.yaml).
local STATUS_ENGAGED = 1;
local STATUS_DEAD    = { [2] = true, [3] = true };
local STATUS_RESTING = 33;

-- Monsters, pets and NPC fighters have server ids from here up. Player ids are all below it.
local FIRST_MONSTER_ID = 0x1000000;

-- A monster's entity index is the low 12 bits of its server id. Monsters a script spawns mid-game,
-- like the treant event, sit at indexes 0x700 to 0x8FF. Their id carries the index plus 0x100.
local MONSTER_INDEX_MASK = 0xFFF;
local SPAWNED_ID_START   = 0x800;
local SPAWNED_ID_OFFSET  = 0x100;

-- How often monsters that went quiet are dropped.
local SWEEP_SECONDS = 5;

-- The TP a weapon skill needs, and how much the sample TP gains each round while the settings
-- window is open.
local TP_GOAL        = 1000;
local SAMPLE_TP_STEP = 128;

-- 0x029 messages for an attack that can't happen, and what the bar says for them. The server checks
-- facing first (5), then range (4). Losing sight of the monster (36) disengages you, so there's no
-- bar left.
local CANT_ATTACK = { [4] = 'too far', [5] = 'not facing', [36] = false };

-- The first result message of a spell finish with no spell id says what went wrong. 78 is a weapon
-- skill used out of range, 84 is paralysis and 106 is intimidation.
local WEAPONSKILL_TOO_FAR = 78;
local PARALYZED_OR_INTIMIDATED = { [84] = true, [106] = true };

-- A monster's TP move that found no one to hit ends with 78 when its target is too far away, or 76
-- when no one is in its area. It still plays out. Its timer picks up 2 s later, like after any TP move.
local TP_MOVE_MISSED = { [76] = true, [78] = true };

-- Sleep, petrification, stun, Sleep II, terror, penalty and Lullaby stop your attacks. They're checked
-- five times a second, so the auto attack bar stops and starts close to when the server does. The bar
-- names the first one found.
local DISABLED_BY = { 2, 7, 10, 19, 28, 159, 193 };
local BUFF_CHECK_SECONDS = 0.2;

local VK_SHIFT = 0x10;

-- Timers from top to bottom in the default layout.
local ELEMENTS = { 'resting', 'attack', 'enemy' };
local TIMER_NAMES = {
    attack  = 'The auto attack timer',
    resting = 'The resting timer',
    enemy   = 'The enemy attack timer',
};
local STACK_GAP = 6;

--[[
    Ashita fills a section or color missing from your file with the same table it keeps as defaults
    for the next character to log in. Each of those gets its own table from a fresh copy, so editing
    it can't change the defaults.
]]
local function unshare(loaded, kept, fresh)
    for key, value in pairs(kept) do
        if (type(value) == 'table') then
            if (rawequal(loaded[key], value)) then
                loaded[key] = fresh[key];
            elseif (type(loaded[key]) == 'table') then
                unshare(loaded[key], value, fresh[key]);
            end
        end
    end
end

local kept_defaults = defaults.make();
local loaded_settings = settings.load(kept_defaults);
unshare(loaded_settings, kept_defaults, defaults.make());

local cadence = {
    settings    = loaded_settings,   -- The settings in use. While one layout is shared, that's the shared copy.
    own         = loaded_settings,   -- This character's own settings, which Ashita writes to their file.
    my_id       = 0,       -- Your server id, which picks your own packets out of everyone's.
    last_status = nil,
    messages    = {},      -- Reused list of result messages from one action.
    results     = {},      -- Reused list of every result in one action.
    buffs       = {},      -- Reused set of your buffs.
    buffs_at    = -1,
    broken      = false,   -- Set when drawing failed, so the error isn't repeated every frame.
    unsaved     = false,   -- A slider or color picker is being dragged and hasn't saved yet.
    hidden      = false,   -- True after /cadence hide, until it's typed again. Not saved.
    enemy_id      = nil,   -- The monster the enemy timer follows, its status and its name.
    enemy_status  = nil,
    enemy_name    = nil,
    target_id     = nil,   -- Your target when it's a monster, and its status, so a pull can be seen.
    target_status = nil,
    battle_id     = nil,   -- The monster your attacks go to. You can target another one while you fight.
    swept_at      = 0,
    job_check     = true,  -- Set after zoning, until your main job has been read.
    last_job      = nil,   -- Your main job when last read. A change loads that job's linked profile.
    filling       = false, -- True while you're resting below full HP or MP, so getting full plays the sound.
    sound_on      = nil,   -- Whether the sound was on the last time settings changed. Nil until load.
};

-- Prints one line in chat, in your chat colors.
local function say(text)
    print(chat_colors.line(cadence.settings.chat, addon.name, text));
end

-- Writes your settings. While one layout is shared, that's only the shared file. Your own file keeps
-- your own layout.
local function save_settings()
    defaults.tidy(cadence.settings);
    if (shared_layout.is_on()) then
        shared_layout.save();
    else
        settings.save();
    end
end

-- Writes this character's own file, where its job links live even while one layout is shared. With
-- sharing off, that's the same as save_settings.
local function save_own()
    defaults.tidy(cadence.own);
    settings.save();
end

-- Your current weapon delay estimate, a key that changes with the gear or buffs behind it, and the
-- loadout they came from.
local function current_delay()
    local loadout = player.read_loadout();
    return delay.estimate(loadout), delay.key(loadout), loadout;
end

-- True while the TP line is on screen, so its packets are worth reading.
local function tracking_tp()
    local element = cadence.settings.attack;
    return element.enabled and element.show_tp;
end

--[[
    Settings actions.
]]

-- Stacks the timers at their default spot, spaced by their real size at the current scale. On a
-- screen too short for that, the stack starts higher so all of it fits.
local function reset_positions()
    local fresh = defaults.make();
    local gap = math.floor(STACK_GAP * cadence.settings.style.scale + 0.5);
    local stack_height = 0;
    for _, key in ipairs(ELEMENTS) do
        local _, height = hud.element_size(key);
        stack_height = stack_height + height + gap;
    end
    local y = fresh[ELEMENTS[1]].y;
    -- Before ImGui's first frame it doesn't know the screen's size yet.
    local _, screen_height = hud.screen_size();
    if (screen_height > 0) then
        y = math.min(y, screen_height - stack_height);
    end
    for _, key in ipairs(ELEMENTS) do
        local element = cadence.settings[key];
        element.x, element.y = fresh[key].x, y;
        local _, height = hud.element_size(key);
        y = y + height + gap;
    end
    hud.place_all();
end

-- What chat says about a sound file that won't open or play.
local SOUND_PROBLEM = '%s won\'t play. Check that it\'s a working .mp3 or .wav file, or pick another one.';

--[[
    Opens the sound file you picked, unless it's open already. Any other file closes. A file that
    wouldn't open is only tried again when `picked` is true, for when you pick it, turn the sound on or
    press Play. Then chat says so if it still won't open. True when the file is open or none is picked.
]]
local function open_sound(picked)
    local name = cadence.settings.resting.sound_file;
    local ok = sound.use(name, picked);
    if (not ok and picked) then
        say(SOUND_PROBLEM:format(name));
    end
    return ok;
end

-- Plays the sound you picked now, the same as Play. It plays with the sound turned off too. Chat says
-- when it can't. True when it played.
local function play_sound()
    local element = cadence.settings.resting;
    if (element.sound_file == '') then
        say('Pick a sound first, with /cadence resting soundfile <name> or the Sound list on the Timers tab.');
        return false;
    end
    if (not open_sound(true)) then
        return false;
    end
    if (not sound.play(element.sound_volume)) then
        say(SOUND_PROBLEM:format(element.sound_file));
        return false;
    end
    return true;
end

--[[
    The sound file only opens while the sound is on, so with it off cadence never opens one on its own.
    Turning it on tries the file again, and chat says if it won't play. On load nothing is said. Turning
    it off closes the file. With the sound off, a file Play opened stays open until you pick another one.
]]
local function apply_sound()
    local element = cadence.settings.resting;
    if (element.sound) then
        open_sound(cadence.sound_on == false);
    elseif (cadence.sound_on or not sound.is_open(element.sound_file)) then
        sound.close();
    end
    cadence.sound_on = element.sound;
end

-- Runs on every change to the settings, so a profile, a reset or another character's settings open
-- or close their own sound file.
local function apply_settings()
    hud.refresh(cadence.settings);
    apply_sound();
end

-- Redraws the timers with what changed and saves it.
local function apply_and_save()
    apply_settings();
    save_settings();
end

-- On load and on every login. The timers use your own settings, or the shared copy while one layout
-- is shared. Both get the settings check.
local function pick_settings()
    defaults.tidy(cadence.own);
    cadence.settings = shared_layout.apply(cadence.own);
    defaults.tidy(cadence.settings);
    apply_settings();
end

-- Turns one layout for all characters on or off. Nothing on screen changes. The timers switch to the
-- shared copy, or back to your own settings.
local function share_layout(on)
    if (on) then
        cadence.settings = shared_layout.turn_on(cadence.own);
    else
        cadence.settings = shared_layout.turn_off(cadence.own);
    end
    apply_and_save();
end

--[[
    Game state.
]]

-- Starts and stops the timers when your status changes. Polling the status each frame catches
-- every way in and out of combat or resting, including loading the addon mid-fight.
local function track_status(now, status)
    if (status == cadence.last_status) then
        return;
    end

    if (status == STATUS_ENGAGED) then
        local estimate, key, loadout = current_delay();
        -- With no status seen yet, the fight started before cadence was watching.
        attack.engage(now, estimate, key, cadence.last_status == nil);
        tp.on_engage(loadout);
        reach.forget();
        -- You engage what you have targeted. After that, the server says when your attacks move to
        -- another monster, and each round says where they went.
        local index = player.target_index();
        cadence.battle_id = index and player.monster_id(index);
    elseif (cadence.last_status == STATUS_ENGAGED) then
        attack.disengage();
        cadence.battle_id = nil;
    end

    if (status == STATUS_RESTING) then
        resting.start(now);
    elseif (cadence.last_status == STATUS_RESTING) then
        resting.stop();
    end

    cadence.last_status = status;
end

-- Checks your buffs five times a second.
local function check_buffs(now)
    if (now - cadence.buffs_at < BUFF_CHECK_SECONDS) then
        return;
    end
    cadence.buffs_at = now;

    local buffs = player.read_buffs(cadence.buffs);
    attack.on_buffs(buffs);
    resting.on_buffs(now, buffs);
    for _, id in ipairs(DISABLED_BY) do
        if (buffs[id]) then
            attack.on_disabled(now, id);
            return;
        end
    end
    attack.on_enabled(now);
end

local function shift_held()
    return bit.band(ffi.C.GetAsyncKeyState(VK_SHIFT), 0x8000) ~= 0;
end

-- True while the game's chat line or another of its text boxes is open. Shift there is just typing.
local function typing_in_game()
    return bit.band(AshitaCore:GetChatManager():IsInputOpen(), 1) ~= 0;
end

--[[
    Drawing.
]]

-- What the TP line under the auto attack bar shows. One table is reused so drawing makes no garbage.
local tp_view = { goal = TP_GOAL };

local function read_tp(sample_tp)
    local element = cadence.settings.attack;
    if (not element.show_tp) then
        return nil;
    end
    local value = sample_tp or player.tp();
    tp_view.tp, tp_view.rounds = value, nil;
    if (element.show_tp_rounds and value < TP_GOAL) then
        if (sample_tp) then
            tp_view.rounds = math.ceil((TP_GOAL - value) / SAMPLE_TP_STEP);
        else
            tp_view.rounds = tp.rounds_to(TP_GOAL, value);
        end
    end
    return tp_view;
end

-- The entity index of the monster with server id `id`, or nil once it's gone from around you.
local function monster_index(id)
    local index = bit.band(id, MONSTER_INDEX_MASK);
    if (index >= SPAWNED_ID_START) then
        index = index - SPAWNED_ID_OFFSET;
    end
    if (player.monster_id(index) ~= id) then
        return nil;
    end
    return index;
end

-- Where you and the monster you're fighting stand. Two tables are reused so checking makes no garbage.
local my_body, target_body = {}, {};

-- "too far" or "not facing" from where you and the monster you're fighting stand, or nil. Only checked
-- with Range / facing on, while that monster is alive and around you.
local function reach_word()
    if (not cadence.settings.attack.show_reason) then
        return nil;
    end
    local id = cadence.battle_id;
    local index = id and monster_index(id);
    if (index == nil or STATUS_DEAD[player.entity_status(index)]) then
        reach.forget();
        return nil;
    end
    local message = reach.check(id, player.body(player.my_index(), my_body), player.body(index, target_body));
    return message and CANT_ATTACK[message];
end

local function draw_attack(now, sample)
    local fill, left, attack_delay, reason, why = attack.progress(now);
    if (fill ~= nil) then
        hud.draw_attack(fill, left, attack_delay, attack.is_learned(), read_tp(), reason, why, reach_word());
    elseif (sample) then
        -- The sample bar fills in 3.8 s and shows ready for a moment before the next round.
        local cycle = now % 4.2;
        -- The sample TP climbs each round past 1000, then starts over, so both of its colors show.
        local sample_tp = 512 + SAMPLE_TP_STEP * (math.floor(now / 4.2) % 6);
        hud.draw_attack(math.min(cycle / 3.8, 1), math.max(3.8 - cycle, 0), 3.78, true, read_tp(sample_tp));
    end
end

--[[
    True during a cutscene or NPC conversation, when the interface is hidden with Scroll Lock, or
    when the map is open. Each one has its own setting. The game is only read for the ones turned on.
]]
local function hidden_by_game(style, entity)
    return (style.hide_during_events and player.in_event(entity))
        or (style.hide_with_game_ui and player.interface_hidden())
        or (style.hide_on_map and player.map_open());
end

-- What the resting timer shows this frame. One table is reused so drawing makes no garbage.
local resting_view = {};

-- How strong the tick flash is right now, from 1 when a tick lands down to 0.
local function flash_strength(now, tick_at)
    local length = cadence.settings.resting.flash_seconds;
    if (tick_at == nil or length <= 0) then
        return 0;
    end
    return math.max(0, 1 - (now - tick_at) / length);
end

local function draw_resting(now, sample)
    local view = resting_view;
    local fill, left, _, gained_hp, gained_mp, full = resting.progress(now);
    if (fill ~= nil) then
        local element = cadence.settings.resting;
        view.fill, view.left, view.gained_hp, view.gained_mp, view.full = fill, left, gained_hp, gained_mp, full;
        -- The full times are only worked out when they show.
        view.until_full = element.show_until_full and resting.until_full(now) or nil;
        if (element.show_each_full) then
            view.hp_full_in, view.mp_full_in, view.has_mp = resting.until_each_full(now);
        end
        view.flash = flash_strength(now, resting.seen_at());
        view.why = resting.blocked_by();
    elseif (sample) then
        local cycle = now % 10;
        view.fill, view.left, view.gained_hp, view.gained_mp, view.full = cycle / 10, 10 - cycle, 24, 31, false;
        view.why = nil;
        view.until_full = 10 - cycle + 20;
        view.hp_full_in, view.mp_full_in, view.has_mp = 10 - cycle, 10 - cycle + 20, true;
        view.flash = flash_strength(now, now - cycle);
    else
        return;
    end
    hud.draw_resting(view);
end

--[[
    Plays your sound once each time resting fills your HP and MP, the moment the resting timer turns
    "full". It plays even when the timer isn't drawn, like with Hide once full or on the map. Sitting
    down already full doesn't count, and neither does loading cadence while you're resting at full,
    since it waits until it knows your HP and MP. Standing up, or HP or MP dropping while you're
    resting, lets it play again the next time you fill up.
]]
local function play_when_full()
    if (not resting.is_active() or not resting.knows_vitals()) then
        cadence.filling = false;
        return;
    end
    if (not resting.is_full()) then
        cadence.filling = true;
        return;
    end
    if (cadence.filling) then
        cadence.filling = false;
        local element = cadence.settings.resting;
        if (element.enabled and element.sound) then
            sound.play(element.sound_volume);
        end
    end
end

-- Your target is watched even before it fights, so pulling it starts its first round's countdown.
local function watch_target(now, id, status)
    if (id == cadence.target_id and status == STATUS_ENGAGED and cadence.target_status ~= STATUS_ENGAGED) then
        enemy.on_engage(now, id);
    end
    cadence.target_id, cadence.target_status = id, status;
end

--[[
    Which monster the enemy timer follows, as its server id and entity index, or nil. Your target
    counts when it's a monster that's fighting. With a party member, an NPC or nothing targeted, "Keep
    the last monster" stays on the one already followed while it's active. It lets go once that monster
    dies or gives up the fight, since either one drops its clock. "My target first" falls back to
    whoever is hitting you when your target isn't.
]]
local function pick_enemy(now)
    local which = cadence.settings.enemy.which;
    if (which ~= 'attacker') then
        local index = player.target_index();
        local id = index and player.monster_id(index);
        local status = id and player.entity_status(index);
        watch_target(now, id, status);
        if (id ~= nil and (enemy.has(id) or status == STATUS_ENGAGED)) then
            return id, index;
        end
        local kept = cadence.enemy_id;
        if (id == nil and kept ~= nil and cadence.settings.enemy.keep_last and enemy.active(now, kept)) then
            local kept_index = monster_index(kept);
            if (kept_index ~= nil) then
                return kept, kept_index;
            end
        end
        if (which == 'target') then
            return nil;
        end
    end

    local id = enemy.attacking(now, cadence.my_id, cadence.enemy_id);
    local index = id and monster_index(id);
    if (index == nil) then
        return nil;
    end
    return id, index;
end

--[[
    Watches the followed monster's status. Dying or giving up the fight drops its clock. Its name is
    read once, when it's first followed. When the timer lets go of a monster, its speed is kept under
    its name and zone. The next one with that name in that zone starts from it.
]]
local function follow_enemy(now, id, index)
    if (id ~= cadence.enemy_id) then
        enemy.remember(cadence.enemy_id, cadence.enemy_name);
        cadence.enemy_id = id;
        cadence.enemy_status = id and player.entity_status(index);
        cadence.enemy_name = id and player.entity_name(index);
        -- A monster can die while another one is followed. Its clock goes as soon as it's picked.
        if (STATUS_DEAD[cadence.enemy_status]) then
            enemy.forget(id);
        elseif (id ~= nil) then
            enemy.recall(now, id, cadence.enemy_name);
        end
        return;
    end
    if (id == nil) then
        return;
    end

    local status = player.entity_status(index);
    if (status == cadence.enemy_status) then
        return;
    end
    if (STATUS_DEAD[status] or cadence.enemy_status == STATUS_ENGAGED) then
        enemy.remember(id, cadence.enemy_name);
        enemy.forget(id);
    end
    cadence.enemy_status = status;
end

-- What the enemy timer shows this frame. One table is reused so drawing makes no garbage.
local enemy_view = {};

-- Fills enemy_view for the followed monster. Returns true when there's something to show.
local function update_enemy(now)
    local id, index = pick_enemy(now);
    follow_enemy(now, id, index);
    if (id == nil) then
        return false;
    end

    local fill, left, enemy_delay, learned, waiting, tag, holding = enemy.progress(now, id);
    if (fill == nil) then
        return false;
    end
    local view = enemy_view;
    view.fill, view.left, view.delay, view.learned, view.waiting = fill, left, enemy_delay, learned, waiting;
    view.tag, view.holding = tag, holding;
    view.on_you = enemy.last_target(id) == cadence.my_id;
    view.name = cadence.enemy_name;
    return true;
end

local function sample_enemy(now)
    -- The sample runs 1.3 s out of step with the auto attack sample, so the two don't move together.
    local time = now + 1.3;
    local cycle = time % 4.4;
    local view = enemy_view;
    view.fill, view.left = math.min(cycle / 4.0, 1), math.max(4.0 - cycle, 0);
    view.delay, view.learned, view.waiting, view.name, view.tag = 4.0, true, false, 'Goblin Thug', nil;
    view.holding = nil;
    -- Every other round the sample is on you, so the mark's color shows while you pick it.
    view.on_you = math.floor(time / 4.4) % 2 == 1;
end

--[[
    Reads your main job once you're back in the world after zoning. Jobs change in your Mog House, so
    this sees every change. A change loads the profile linked to the new job. The first read after
    cadence loads or another character logs in only notes the job.
]]
local function check_job()
    local job = player.main_job();
    if (job == 0) then
        return;
    end
    cadence.job_check = false;
    local changed = cadence.last_job ~= nil and job ~= cadence.last_job;
    cadence.last_job = job;
    if (not changed) then
        return;
    end
    local job_name = defaults.JOBS[job];
    local name = job_name and cadence.settings.job_links[job_name];
    if (not name) then
        return;
    end
    if (profiles.load(cadence.settings, name)) then
        apply_and_save();
        say(('Your settings now come from the profile "%s", since it\'s linked to %s.'):format(name, job_name));
    elseif (profiles.file_ok()) then
        say(('%s is linked to the profile "%s", but it isn\'t there anymore.'):format(job_name, name));
    else
        say(profiles.problem());
    end
end

-- Does what the settings window asked for this frame. With the sound on, a file picked in the Sound list
-- opens before the settings are applied, so a file that won't open is tried once and chat says so once.
local function handle_window(result)
    if (result.show_timers) then
        cadence.hidden = false;
    end
    if (result.sound_picked and cadence.settings.resting.sound) then
        open_sound(true);
    end
    if (result.sample) then
        say('This is how cadence\'s answers look in your chat colors.');
    end
    if (result.reset_positions) then
        reset_positions();
        result.save = true;
    end
    if (result.reset_look) then
        presets.reset(cadence.settings);
        result.changed, result.save = true, true;
    end
    if (result.share_layout ~= nil) then
        share_layout(result.share_layout);
    end
    if (result.changed) then
        apply_settings();
    end
    if (result.save) then
        save_settings();
    end
    if (result.links) then
        save_own();
    end
    if (result.changed or result.save) then
        cadence.unsaved = not result.save;
    end
    if (result.play_sound) then
        play_sound();
    end
end

local function render()
    local now = os.clock();
    local entity = player.entity();
    if (entity == nil) then
        return;
    end

    -- Your job is read after zoning even with nothing on screen, so its profile loads right away.
    if (cadence.job_check) then
        check_job();
    end
    track_status(now, entity.Status);
    resting.update(now);
    play_when_full();

    -- Nothing to draw means nothing else to do this frame. With the settings window open, a timer with
    -- nothing live shows a sample. At a shared spot only one shows, and a live timer beats a sample.
    local s = cadence.settings;
    local window_open    = settings_window.is_open();
    local resting_sample = window_open and not (s.style.shared_spot and s.attack.enabled);
    local resting_live   = resting.is_active() and not (s.resting.hide_when_full and resting.is_full());
    local show_resting   = s.resting.enabled and (resting_live or resting_sample);
    local attack_sample  = window_open and not (s.style.shared_spot and show_resting);
    local show_attack    = s.attack.enabled and (attack.is_active() or attack_sample);
    local enemy_live     = s.enemy.enabled and update_enemy(now);
    local show_enemy     = s.enemy.enabled and (enemy_live or window_open);
    if (s.enemy.enabled and now - cadence.swept_at > SWEEP_SECONDS) then
        cadence.swept_at = now;
        enemy.sweep(now, cadence.enemy_id);
    end
    if (not (show_resting or show_attack or show_enemy or window_open)) then
        -- With nothing on screen, your buffs are only read to see a March, Slow or Elegy wear off.
        if (attack.watching_buffs()) then
            check_buffs(now);
        end
        return;
    end

    -- Buffs are checked even while the game hides, so a stun then isn't learned as a slow attack.
    check_buffs(now);

    -- /cadence hide keeps everything running but draws no timers. The settings window still opens.
    if (cadence.hidden) then
        show_resting, show_attack, show_enemy = false, false, false;
    end

    -- Nothing is drawn while the game hides, the settings window included. It comes back with the
    -- game. A slider held as hiding starts never gets let go, so it saves here.
    if (hidden_by_game(s.style, entity)) then
        if (cadence.unsaved) then
            save_settings();
            cadence.unsaved = false;
        end
        return;
    end

    local shift = shift_held() and not typing_in_game();
    hud.set_movable(shift);
    hud.begin_frame();
    hud.join_below(show_enemy and s.enemy.attached and s.attack.enabled);
    if (show_resting) then
        draw_resting(now, resting_sample);
    end
    if (show_attack) then
        draw_attack(now, attack_sample);
    end
    if (show_enemy) then
        if (not enemy_live) then
            sample_enemy(now);
        end
        hud.draw_enemy(enemy_view);
    end
    if (hud.end_frame()) then
        save_settings();
    end

    handle_window(settings_window.draw(s, addon.version, cadence.hidden, shift));
end

--[[
    Commands.
]]

local ON_WORDS = { on = true, off = false };

-- How long a first /cadence reset all waits for the second one.
local RESET_ALL_SECONDS = 10;

--[[
    Every box and dropdown in the settings window that has a command, in the order help lists them.
    `tab` is where it sits in the window and `name` is what the window calls it. A timer's row hangs
    off that timer's word, like /cadence attack tp off. A style row has a word of its own, like
    /cadence shadow off. A row is an on/off switch unless it has `choices`. Each choice is the value
    saved, its name in the window and the word you type. The `layout` row is One layout for all
    characters, which lives in its own file. Preset and Font have commands of their own.
]]
local SETTINGS = {
    { tab = 'Timers', section = 'attack',  word = 'seconds',    key = 'show_value',         name = 'Seconds left' },
    { tab = 'Timers', section = 'attack',  word = 'delay',      key = 'show_delay',         name = 'Weapon delay' },
    { tab = 'Timers', section = 'attack',  word = 'tp',         key = 'show_tp',            name = 'Your TP' },
    { tab = 'Timers', section = 'attack',  word = 'rounds',     key = 'show_tp_rounds',     name = 'Rounds to 1000' },
    { tab = 'Timers', section = 'attack',  word = 'numbers',    key = 'numbers_only',       name = 'Numbers only' },
    { tab = 'Timers', section = 'attack',  word = 'mark',       key = 'almost_mark',        name = 'Ready mark' },
    { tab = 'Timers', section = 'attack',  word = 'almost',     key = 'almost_ready',       name = 'Almost ready' },
    { tab = 'Timers', section = 'attack',  word = 'range',      key = 'show_reason',        name = 'Range / facing' },
    { tab = 'Timers', section = 'attack',  word = 'why',        key = 'show_why',           name = 'Why it stopped' },
    { tab = 'Timers', section = 'resting', word = 'seconds',    key = 'show_value',         name = 'Seconds left' },
    { tab = 'Timers', section = 'resting', word = 'gains',      key = 'show_gains',         name = 'Last tick gains' },
    { tab = 'Timers', section = 'resting', word = 'untilfull',  key = 'show_until_full',    name = 'Time until full' },
    { tab = 'Timers', section = 'resting', word = 'fulltimes',  key = 'show_each_full',     name = 'Full times' },
    { tab = 'Timers', section = 'resting', word = 'numbers',    key = 'numbers_only',       name = 'Numbers only' },
    { tab = 'Timers', section = 'resting', word = 'hidefull',   key = 'hide_when_full',     name = 'Hide once full' },
    { tab = 'Timers', section = 'resting', word = 'flash',      key = 'flash_on_tick',      name = 'Flash on each tick' },
    { tab = 'Timers', section = 'resting', word = 'why',        key = 'show_why',           name = 'Why it can\'t heal' },
    { tab = 'Timers', section = 'resting', word = 'sound',      key = 'sound',              name = 'Sound' },
    { tab = 'Timers', section = 'style',   word = 'hideevents', key = 'hide_during_events', name = 'Hide during events' },
    { tab = 'Timers', section = 'style',   word = 'hidemap',    key = 'hide_on_map',        name = 'Hide on the map' },
    { tab = 'Timers', section = 'style',   word = 'hideui',     key = 'hide_with_game_ui',  name = 'Hide with the game UI' },
    { tab = 'Enemy',  section = 'enemy',   word = 'follow',     key = 'which',              name = 'Follows',
        choices = defaults.FOLLOWS },
    { tab = 'Enemy',  section = 'enemy',   word = 'keeplast',   key = 'keep_last',          name = 'Keep the last monster' },
    { tab = 'Enemy',  section = 'enemy',   word = 'attach',     key = 'attached',           name = 'Attach under auto attack' },
    { tab = 'Enemy',  section = 'enemy',   word = 'seconds',    key = 'show_value',         name = 'Seconds left' },
    { tab = 'Enemy',  section = 'enemy',   word = 'name',       key = 'show_name',          name = 'Enemy name' },
    { tab = 'Enemy',  section = 'enemy',   word = 'speed',      key = 'show_delay',         name = 'Attack speed' },
    { tab = 'Enemy',  section = 'enemy',   word = 'effects',    key = 'show_effects',       name = 'Slow and haste' },
    { tab = 'Enemy',  section = 'enemy',   word = 'tpmove',     key = 'show_holds',         name = 'TP move / casting' },
    { tab = 'Enemy',  section = 'enemy',   word = 'onyou',      key = 'show_on_you',        name = 'On you' },
    { tab = 'Enemy',  section = 'enemy',   word = 'numbers',    key = 'numbers_only',       name = 'Numbers only' },
    { tab = 'Enemy',  section = 'enemy',   word = 'mark',       key = 'almost_mark',        name = 'Ready mark' },
    { tab = 'Enemy',  section = 'enemy',   word = 'almost',     key = 'almost_ready',       name = 'Almost ready' },
    { tab = 'Look',   section = 'style',   word = 'windowlook', key = 'window_matches_look', name = 'Window matches the look' },
    { tab = 'Look',   section = 'style',   word = 'labels',     key = 'show_labels',        name = 'Show labels' },
    { tab = 'Look',   section = 'attack',  word = 'label',      key = 'show_label',         name = 'Show its name' },
    { tab = 'Look',   section = 'resting', word = 'label',      key = 'show_label',         name = 'Show its name' },
    { tab = 'Look',   section = 'enemy',   word = 'label',      key = 'show_label',         name = 'Show its name' },
    { tab = 'Look',   section = 'style',   word = 'background', key = 'panel',              name = 'Background' },
    { tab = 'Look',   section = 'style',   word = 'border',     key = 'border',             name = 'Border' },
    { tab = 'Look',   section = 'style',   word = 'accent',     key = 'accent',             name = 'Accent stripe' },
    { tab = 'Look',   section = 'style',   word = 'outline',    key = 'text_outline',       name = 'Text outline' },
    { tab = 'Look',   section = 'style',   word = 'shadow',     key = 'text_shadow',        name = 'Text shadow' },
    { tab = 'Look',   section = 'style',   word = 'drain',      key = 'bar_drains',         name = 'Drain instead of fill' },
    { tab = 'Look',   section = 'style',   word = 'onespot',    key = 'shared_spot',        name = 'Share one spot' },
    { tab = 'Look',   section = 'style',   word = 'onelayout',  layout = true,              name = 'One layout for all characters' },
    { tab = 'Look',   section = 'style',   word = 'peek',       key = 'see_through',        name = 'Peek with Shift' },
};

--[[
    The commands that take a number, in the order help lists them. Each one sets a slider in the
    settings window, so it takes the slider's range from defaults.RANGES. `tab` is where the slider
    sits and `name` is what the window calls it. A timer's slider hangs off that timer's word, like
    /cadence attack width 300. Any other slider has a word of its own, like /cadence scale 1.5. A number
    is rounded to as many decimal places as `places` says, the same as its slider shows. `what` is what
    help says the command sets, and `said` is the answer, with the number in it. A slider whose left end
    is auto takes the word auto too. That saves `auto`, and `said_auto` is the answer. Its numbers start
    one above that end.
]]
local NUMBERS = {
    { tab = 'Timers', section = 'attack', word = 'width', key = 'width', name = 'Width',
        what = 'how wide the timer is',
        said = 'The auto attack timer\'s width is set to %s px.' },
    { tab = 'Timers', section = 'attack', word = 'barheight', key = 'bar_height', name = 'Bar height',
        what = 'how thick its bar is',
        said = 'The auto attack timer\'s bar height is set to %s px.' },
    { tab = 'Timers', section = 'attack', word = 'almostat', key = 'almost_seconds', name = 'Almost ready at',
        places = 1,
        what = 'how many seconds before your attack the almost ready color starts',
        said = 'The auto attack bar turns the almost ready color %s s before your attack.' },
    { tab = 'Timers', section = 'resting', word = 'width', key = 'width', name = 'Width',
        what = 'how wide the timer is',
        said = 'The resting timer\'s width is set to %s px.' },
    { tab = 'Timers', section = 'resting', word = 'barheight', key = 'bar_height', name = 'Bar height',
        what = 'how thick its bar is',
        said = 'The resting timer\'s bar height is set to %s px.' },
    { tab = 'Timers', section = 'resting', word = 'flashlength', key = 'flash_seconds', name = 'Flash length',
        places = 1,
        what = 'how many seconds the flash on each tick lasts',
        said = 'The flash on each resting tick lasts %s s.' },
    { tab = 'Timers', section = 'resting', word = 'soundvolume', key = 'sound_volume', name = 'Volume',
        what = 'how loud the sound is, from silent to full',
        said = 'The resting sound\'s volume is set to %s%%.' },
    { tab = 'Enemy', section = 'enemy', word = 'width', key = 'width', name = 'Width',
        what = 'how wide the timer is',
        said = 'The enemy attack timer\'s width is set to %s px.' },
    { tab = 'Enemy', section = 'enemy', word = 'barheight', key = 'bar_height', name = 'Bar height',
        what = 'how thick its bar is',
        said = 'The enemy attack timer\'s bar height is set to %s px.' },
    { tab = 'Enemy', section = 'enemy', word = 'almostat', key = 'almost_seconds', name = 'Almost ready at',
        places = 1,
        what = 'how many seconds before the monster\'s attack the almost ready color starts',
        said = 'The enemy bar turns the almost ready color %s s before the monster attacks.' },
    { tab = 'Look', section = 'style', word = 'scale', key = 'scale', name = 'Scale', places = 2,
        what = 'how big the timers are',
        said = 'The timers\' scale is set to %sx.' },
    { tab = 'Look', section = 'style', word = 'textsize', key = 'font_size', name = 'Text size',
        what = 'how big the numbers are',
        said = 'The timers\' text size is set to %s px.' },
    { tab = 'Look', section = 'style', word = 'detailsize', key = 'detail_size', name = 'Detail size', auto = 0,
        what = 'how big the small text is. Auto follows Text size',
        said = 'The timers\' detail size is set to %s px.', said_auto = 'The timers\' detail size is set to auto.' },
    { tab = 'Look', section = 'style', word = 'labelsize', key = 'label_size', name = 'Label size', auto = 0,
        what = 'how big the timer names are. Auto follows Text size',
        said = 'The timers\' label size is set to %s px.', said_auto = 'The timers\' label size is set to auto.' },
    { tab = 'Look', section = 'style', word = 'corners', key = 'rounding', name = 'Corner roundness',
        what = 'how round the timers\' corners are',
        said = 'The timers\' corner roundness is set to %s px.' },
    { tab = 'Window', section = 'window_style', word = 'windowfontsize', key = 'font_size', name = 'Font size',
        what = 'the settings window\'s font size',
        said = 'The settings window\'s font size is set to %s px.' },
    { tab = 'Window', section = 'window_style', word = 'windowcorners', key = 'rounding', name = 'Corner roundness',
        what = 'how round the settings window\'s corners are',
        said = 'The settings window\'s corner roundness is set to %s px.' },
    { tab = 'Window', section = 'window_style', word = 'windowspacing', key = 'spacing', name = 'Spacing',
        what = 'the space between the settings window\'s rows',
        said = 'The space between the settings window\'s rows is set to %s px.' },
};

--[[
    The timers' colors /cadence color sets, under the heading each one has in the settings window, in
    the order help lists them. `word` is what you type, and `section` and `key` are where it's saved.
]]
local COLOR_GROUPS = {
    { name = 'AUTO ATTACK TIMER', colors = {
        { word = 'attack_tp',          section = 'attack',  key = 'tp_color' },
        { word = 'attack_fill_start',  section = 'attack',  key = 'fill_start' },
        { word = 'attack_fill_end',    section = 'attack',  key = 'fill_end' },
        { word = 'attack_ready',       section = 'attack',  key = 'ready_color' },
        { word = 'attack_almost',      section = 'attack',  key = 'almost_color' },
    } },
    { name = 'RESTING TIMER', colors = {
        { word = 'resting_fill_start', section = 'resting', key = 'fill_start' },
        { word = 'resting_fill_end',   section = 'resting', key = 'fill_end' },
        { word = 'resting_full',       section = 'resting', key = 'full_color' },
        { word = 'resting_flash',      section = 'resting', key = 'flash_color' },
    } },
    { name = 'ENEMY ATTACK TIMER', colors = {
        { word = 'enemy_on_you',       section = 'enemy',   key = 'on_you_color' },
    } },
    { name = 'ENEMY BAR', colors = {
        { word = 'enemy_fill_start',   section = 'enemy',   key = 'fill_start' },
        { word = 'enemy_fill_end',     section = 'enemy',   key = 'fill_end' },
        { word = 'enemy_ready',        section = 'enemy',   key = 'ready_color' },
        { word = 'enemy_almost',       section = 'enemy',   key = 'almost_color' },
    } },
    { name = 'CARD', colors = {
        { word = 'background',         section = 'style',   key = 'panel_color' },
        { word = 'border',             section = 'style',   key = 'border_color' },
        { word = 'accent',             section = 'style',   key = 'accent_color' },
    } },
    { name = 'TEXT AND BAR', colors = {
        { word = 'labels',             section = 'style',   key = 'label_color' },
        { word = 'values',             section = 'style',   key = 'value_color' },
        { word = 'details',            section = 'style',   key = 'detail_color' },
        { word = 'bar_track',          section = 'style',   key = 'track_color' },
        { word = 'outline',            section = 'style',   key = 'outline_color' },
    } },
};

-- The name each timer shows while its label is empty. Attached under the auto attack timer, the enemy
-- timer shows ENEMY.
local OWN_NAMES = { attack = 'AUTO ATTACK', resting = 'RESTING', enemy = 'ENEMY ATTACK' };

-- How a color is typed, for help.
local HEX_HELP = 'The color is six hex digits like c55151. Two more, from 00 to ff, set how solid it is, like '
    .. 'c55151cc.';

-- The settings window's font names, for chat.
local WINDOW_FONT_NAMES = {};
for i, entry in ipairs(window_font.LIST) do
    WINDOW_FONT_NAMES[i] = entry.name;
end

-- Lowercase letters and digits only, so a name matches with or without its spaces.
local function squash(text)
    return (text:lower():gsub('[^%w]', ''));
end

-- "a, b and c" for chat, or "a, b or c" with `last` set to 'or'.
local function listed(items, last)
    if (#items < 2) then
        return items[1] or '';
    end
    return ('%s %s %s'):format(table.concat(items, ', ', 1, #items - 1), last or 'and', items[#items]);
end

local function find_setting(section, word)
    for _, row in ipairs(SETTINGS) do
        if (row.section == section and row.word == word) then
            return row;
        end
    end
    return nil;
end

-- The row of NUMBERS for a timer's slider, like attack width, or with no timer, for a slider with a
-- word of its own, like scale.
local function find_number(timer, word)
    for _, row in ipairs(NUMBERS) do
        local owner = TIMER_NAMES[row.section] and row.section or nil;
        if (owner == timer and row.word == word) then
            return row;
        end
    end
    return nil;
end

local function find_window_color(word)
    for _, entry in ipairs(theme.WINDOW_COLORS) do
        if (entry.key == word) then
            return entry;
        end
    end
    return nil;
end

local function find_color(word)
    for _, group in ipairs(COLOR_GROUPS) do
        for _, entry in ipairs(group.colors) do
            if (entry.word == word) then
                return entry;
            end
        end
    end
    return nil;
end

-- What you type for a row, before its on|off or number. A timer's row starts with the timer's word.
local function command_of(row)
    if (TIMER_NAMES[row.section] == nil) then
        return row.word;
    end
    return row.section .. ' ' .. row.word;
end

-- The lowest and highest number a row of NUMBERS takes. A slider with an auto end starts one below
-- its smallest number, at auto.
local function number_range(row)
    local range = defaults.RANGES[row.section][row.key];
    if (row.auto ~= nil) then
        return range[1] + 1, range[2];
    end
    return range[1], range[2];
end

-- A number for chat, with as many decimal places as its slider shows.
local function number_text(row, value)
    return ('%.' .. (row.places or 0) .. 'f'):format(value);
end

-- What a row of NUMBERS takes, like <120-640>, or <8-32>|auto.
local function range_text(row)
    local low, high = number_range(row);
    return ('<%s-%s>%s'):format(number_text(row, low), number_text(row, high), row.auto and '|auto' or '');
end

-- A row of NUMBERS in help, like /cadence attack width <120-640>  sets how wide the timer is.
local function say_number(row)
    say(('/cadence %s %s  sets %s.'):format(command_of(row), range_text(row), row.what));
end

-- The words for one section's colors, like attack_tp|attack_fill_start, for help.
local function color_words(section)
    local words = {};
    for _, group in ipairs(COLOR_GROUPS) do
        for _, entry in ipairs(group.colors) do
            if (entry.section == section) then
                words[#words + 1] = entry.word;
            end
        end
    end
    return table.concat(words, '|');
end

local function choice_words(row)
    local words = {};
    for _, choice in ipairs(row.choices) do
        words[#words + 1] = choice[3];
    end
    return table.concat(words, '|');
end

local function choice_help(row)
    local names = {};
    for _, choice in ipairs(row.choices) do
        names[#names + 1] = choice[2];
    end
    return ('/cadence %s %s  sets %s to %s.'):format(command_of(row), choice_words(row), row.name, listed(names, 'or'));
end

-- A timer's on/off parts. With `names`, each one has its name in the settings window after it, unless
-- that's the same word.
local function parts_of(key, names)
    local parts = {};
    for _, row in ipairs(SETTINGS) do
        if (row.section == key and row.choices == nil) then
            local part = row.word;
            if (names and squash(row.name) ~= part) then
                part = ('%s (%s)'):format(part, row.name);
            end
            parts[#parts + 1] = part;
        end
    end
    return listed(parts);
end

-- A timer's slider words, like width, barheight and almostat.
local function sliders_of(key)
    local words = {};
    for _, row in ipairs(NUMBERS) do
        if (row.section == key) then
            words[#words + 1] = row.word;
        end
    end
    return listed(words);
end

-- Ashita's own font, then every font that loaded, the same as the Font list.
local function font_list()
    local fonts = { hud.ASHITA_FONT };
    for _, name in ipairs(hud.font_names()) do
        fonts[#fonts + 1] = name;
    end
    return fonts;
end

-- The name in `names` that `words` stands for, with or without its spaces, or by its short name in `ids`.
local function find_name(words, names, ids)
    local wanted = squash(words);
    for i, name in ipairs(names) do
        if (wanted == squash(name) or (ids ~= nil and wanted == ids[i])) then
            return name;
        end
    end
    return nil;
end

--[[
    The help lines a tab gets from SETTINGS and NUMBERS. Each dropdown gets its own line, the style
    words share one and the sliders with words of their own share another. A timer's sliders are in
    that timer's help.
]]
local function say_tab(tab)
    local words, names = {}, {};
    for _, row in ipairs(SETTINGS) do
        if (row.tab == tab and row.choices ~= nil) then
            say(choice_help(row));
        elseif (row.tab == tab and row.section == 'style') then
            words[#words + 1] = row.word;
            names[#names + 1] = row.name;
        end
    end
    if (#words > 0) then
        say(('/cadence %s [on|off]  sets %s.'):format(table.concat(words, '|'), listed(names, 'or')));
    end
    words, names = {}, {};
    for _, row in ipairs(NUMBERS) do
        if (row.tab == tab and TIMER_NAMES[row.section] == nil) then
            words[#words + 1] = row.word;
            names[#names + 1] = row.name;
        end
    end
    if (#words > 0) then
        say(('/cadence %s <number>  sets %s.'):format(table.concat(words, '|'), listed(names, 'or')));
    end
end

-- Everything that follows a timer's word. Its switch, Follows for the enemy timer, its boxes, its sliders
-- with their ranges, its label and its colors.
local function print_timer_help(key)
    say(('/cadence %s [on|off]  turns %s on or off.'):format(key, TIMER_NAMES[key]:lower()));
    for _, row in ipairs(SETTINGS) do
        if (row.section == key and row.choices ~= nil) then
            say(choice_help(row));
        end
    end
    say(('/cadence %s <part> [on|off]  sets one of its boxes. The parts are %s.'):format(key, parts_of(key, true)));
    for _, row in ipairs(NUMBERS) do
        if (row.section == key) then
            say_number(row);
        end
    end
    say(('/cadence %s labeltext <text>  gives it a name of your own, like AA. "" puts its own name back.')
        :format(key));
    if (key == 'resting') then
        say('/cadence resting soundfile <name>  picks the sound that plays once you\'re full. Two come with cadence, '
            .. 'and you can add your own .mp3 and .wav files to config\\addons\\cadence\\sounds. You can leave off .mp3 '
            .. 'or .wav.');
        say('/cadence resting playsound  plays the sound now, so you can hear it.');
    end
    say(('/cadence color %s <rrggbb>  sets one of its colors.'):format(color_words(key)));
end

-- The Look tab's sliders with their ranges, the labels you can type and the colors on the Look tab.
local function print_look_help()
    for _, row in ipairs(NUMBERS) do
        if (row.tab == 'Look') then
            say_number(row);
        end
    end
    say('/cadence attack|resting|enemy labeltext <text>  gives that timer a name of your own, like AA. "" puts its '
        .. 'own name back.');
    say(('/cadence color %s <rrggbb>  sets one of the Look tab\'s colors. /cadence help colors lists every color.')
        :format(color_words('style')));
end

-- The color command, and every color it takes under its heading in the settings window.
local function print_color_help()
    say('/cadence color <what> <rrggbb>  sets one of the timers\' colors. <what> is one of these, under its heading '
        .. 'in the settings window.');
    for _, group in ipairs(COLOR_GROUPS) do
        local words = {};
        for _, entry in ipairs(group.colors) do
            words[#words + 1] = entry.word;
        end
        say(('%s  %s'):format(group.name, table.concat(words, ', ')));
    end
    say(HEX_HELP);
end

local function print_preset_help()
    local names = {};
    for i, name in ipairs(presets.NAMES) do
        local id = presets.IDS[i];
        names[i] = (squash(name) == id) and id or ('%s (%s)'):format(id, name);
    end
    say(('/cadence preset <name>  picks a preset, the same as the Preset list. The presets are %s.')
        :format(listed(names)));
    say('/cadence undo  puts back the look you had before your last preset or Reset look. It goes back one step.');
end

-- The Window tab's commands.
local function print_window_help()
    say(('/cadence windowfont <name>  picks the settings window\'s font, with or without its spaces. The fonts are '
        .. '%s.'):format(listed(WINDOW_FONT_NAMES)));
    for _, row in ipairs(NUMBERS) do
        if (row.tab == 'Window') then
            say_number(row);
        end
    end
    say('/cadence windowcolor <what> <rrggbb>  sets one of the settings window\'s colors. /cadence help windowcolors '
        .. 'lists them.');
    say('/cadence chatcolor <what> <color>  sets one of cadence\'s chat colors. /cadence help chatcolors lists them.');
end

-- The Window colors tab's command, and every color it takes under its heading on that tab.
local function print_window_color_help()
    say('/cadence windowcolor <what> <rrggbb>  sets one of the settings window\'s colors. <what> is one of these, '
        .. 'under the headings on the Window colors tab.');
    for _, group in ipairs(theme.WINDOW_COLOR_GROUPS) do
        local keys = {};
        for _, row in ipairs(group.rows) do
            for _, entry in ipairs(row.colors) do
                keys[#keys + 1] = entry.key;
            end
        end
        say(('%s  %s'):format(group.name, table.concat(keys, ', ')));
    end
    say(HEX_HELP);
end

-- The word /cadence chatcolor takes for each part of a line, for chat.
local CHAT_PARTS = {};
for i, part in ipairs(chat_colors.PARTS) do
    CHAT_PARTS[i] = part.key;
end

-- Chat colors per line in /cadence help chatcolors, so no line runs too long.
local CHAT_COLORS_PER_LINE = 8;

-- The chat color command, the parts of a line it colors, and every chat color by name and number.
local function print_chat_color_help()
    say(('/cadence chatcolor <what> <color>  sets one of cadence\'s chat colors, the same as the CHAT section of the '
        .. 'Window tab. <what> is %s.'):format(listed(CHAT_PARTS, 'or')));
    say('<color> is one of these names or its number. A name works with or without its spaces, like lawngreen.');
    local names = {};
    for i, entry in ipairs(chat_colors.PALETTE) do
        names[#names + 1] = ('%s %d'):format(entry.name, entry.code);
        if (#names == CHAT_COLORS_PER_LINE or i == #chat_colors.PALETTE) then
            say(table.concat(names, ', '));
            names = {};
        end
    end
end

-- Your profiles' names for chat, after reading profiles.json again.
local function profile_list()
    profiles.refresh();
    if (not profiles.file_ok()) then
        return profiles.problem();
    end
    local quoted = {};
    for i, name in ipairs(profiles.names()) do
        quoted[i] = ('"%s"'):format(name);
    end
    if (#quoted == 0) then
        return 'You have no profiles yet.';
    end
    return ((#quoted == 1) and 'Your profile is %s.' or 'Your profiles are %s.'):format(listed(quoted));
end

-- The main jobs a job link can name, for chat.
local JOB_LIST = listed(defaults.JOBS);

-- This character's job links for chat, in job order. A link to a profile that isn't there anymore says
-- so. Run profile_list first, since it reads profiles.json again.
local function job_link_list()
    local links = {};
    for _, job in ipairs(defaults.JOBS) do
        local name = cadence.settings.job_links[job];
        if (name ~= nil) then
            local gone = profiles.file_ok() and not profiles.exists(name);
            links[#links + 1] = ('%s to "%s"%s'):format(job, name, gone and ' (gone)' or '');
        end
    end
    if (#links == 0) then
        return 'You have no job links.';
    end
    return ((#links == 1) and 'Your job link is %s.' or 'Your job links are %s.'):format(listed(links));
end

-- The Profiles tab's commands, then the names of your profiles and your job links.
local function print_profile_help()
    say('/cadence profile save <name>  saves your settings as a new profile. Every character shares your profiles.');
    say('/cadence profile overwrite <name>  saves your settings over that profile.');
    say('/cadence profile load <name>  loads a profile. It holds every setting but where the settings window sits, '
        .. 'its size and your job links.');
    say('/cadence profile rename <old> <new>  gives a profile a new name. Your job links to it follow.');
    say('/cadence profile delete <name>  deletes a profile and your job links to it.');
    say(('/cadence joblink <job> <profile>  loads that profile when you change to that main job and zone. Each '
        .. 'character has its own job links. The jobs are %s.'):format(JOB_LIST));
    say('/cadence joblink <job> none  stops that job loading a profile.');
    say('Capital letters don\'t matter in a name. Put a name with spaces in quotes, like /cadence profile load '
        .. '"Solo BLM".');
    say(profile_list());
    say(job_link_list());
end

local function print_reset_help()
    say('/cadence reset  puts every timer back at its default position. On a screen too short for them, they '
        .. 'start higher up.');
    say('/cadence reset look  puts sizes, colors, the card, corner roundness, text shadow and outline, labels, '
        .. 'font, Numbers only, Ready mark, Drain instead of fill, the chat colors and the settings window\'s look '
        .. 'and font back to default. /cadence undo takes it back.');
    say(('/cadence reset all  puts every setting back to its default and clears your job links. Your saved '
        .. 'profiles stay. Type it twice within %d seconds.'):format(RESET_ALL_SECONDS));
end

-- Every command, grouped by the settings window's tabs. /cadence help <word> says more about some.
local function print_help(word)
    if (TIMER_NAMES[word] ~= nil) then
        print_timer_help(word);
        return;
    elseif (word == 'preset' or word == 'undo') then
        print_preset_help();
        return;
    elseif (word == 'font') then
        say(('/cadence font <name>  picks the font, with or without its spaces. The fonts are %s.')
            :format(listed(font_list())));
        return;
    elseif (word == 'reset') then
        print_reset_help();
        return;
    elseif (word == 'look') then
        print_look_help();
        return;
    elseif (word == 'colors' or word == 'color') then
        print_color_help();
        return;
    elseif (word == 'window') then
        print_window_help();
        return;
    elseif (word == 'windowcolors') then
        print_window_color_help();
        return;
    elseif (word == 'chatcolors') then
        print_chat_color_help();
        return;
    elseif (word == 'profiles' or word == 'profile') then
        print_profile_help();
        return;
    end

    say('/cadence  opens or closes the settings window. Leave out on|off and a switch flips.');
    say('/cadence hide|show  hides the timers until you type it again, or brings them back.');
    say('/cadence info  says what cadence has worked out about you, like your delay and TP per hit.');
    say('/cadence help attack|resting|enemy|look|colors|preset|font|reset|window|windowcolors|chatcolors|profiles  '
        .. 'tells you more about one of them.');
    say('/cadence attack|resting|enemy [on|off]  turns a timer on or off.');
    say('Timers tab');
    say('/cadence attack|resting <part> [on|off]  sets one of its boxes, like /cadence attack tp off. A slider takes '
        .. 'a number, like /cadence attack width 300.');
    say_tab('Timers');
    say('Enemy tab');
    say_tab('Enemy');
    say('/cadence enemy <part> [on|off]  sets one of its boxes, like /cadence enemy attach on. A slider takes a '
        .. 'number, like /cadence enemy width 300.');
    say('Look tab');
    say(('/cadence preset %s  picks a preset. /cadence undo takes it back.'):format(table.concat(presets.IDS, '|')));
    say('/cadence font <name>  picks the font, with or without its spaces.');
    say('/cadence attack|resting|enemy label [on|off]  shows or hides that timer\'s name. Type your own with '
        .. 'labeltext, like /cadence attack labeltext AA.');
    say_tab('Look');
    say('/cadence color <what> <rrggbb>  sets one of the timers\' colors. /cadence help colors lists them.');
    say('/cadence lock|unlock  stops or allows moving with Shift + drag.');
    say('/cadence reset [look|all]  puts every timer back at its default position, or the look, or every setting.');
end

-- What cadence has worked out about you, to check in game or paste into a bug report. Nothing about monsters.
local function print_info()
    local estimate, key, loadout = current_delay();
    local attack_delay, learned, estimated = attack.delay_in_use(estimate, key);
    local kept = attack.kept_count();
    -- Out of a fight it's the TP per hit your next fight starts from, like the delay above.
    local per_hit, locked, guess = tp.per_hit();
    if (per_hit == nil or not attack.is_active()) then
        per_hit, locked, guess = tp.per_hit_for(loadout);
    end

    say(('This is what cadence %s has worked out about you right now.'):format(addon.version));
    if (learned) then
        say(('Your auto attack delay is %.2f s, learned from your attacks.'):format(attack_delay));
    else
        say(('Your auto attack delay is %.2f s est. It isn\'t learned from your attacks yet.'):format(attack_delay));
    end
    say(('Your weapons, job and buffs alone say %.2f s.'):format(estimated));
    if (kept == 0) then
        say('cadence has no learned delays saved yet.');
    else
        local one = kept == 1;
        say(('cadence has %s saved for %d %s of weapons, jobs and buffs.')
            :format(one and 'a learned delay' or 'learned delays', kept, one and 'mix' or 'mixes'));
    end

    if (locked) then
        say(('Your TP per hit is %d and it\'s locked in. It started from %d.'):format(per_hit, guess));
    elseif (tracking_tp()) then
        say(('Your TP per hit is %d. It isn\'t locked in yet.'):format(per_hit));
    else
        say(('Your TP per hit is %d. It\'s only learned while the auto attack timer and Your TP are on.')
            :format(per_hit));
    end
    -- Each fight starts this over, so it's only said in one.
    local other = tp.other_per_round();
    if (other >= 1 and attack.is_active() and tracking_tp()) then
        say(('Lately about %d more TP a round has come from other things, like being hit or Regain.')
            :format(math.floor(other + 0.5)));
    end

    if (not resting.is_active()) then
        say('You aren\'t resting. The resting timer learns the 9, 9, 12 pattern again each time you start resting.');
    elseif (resting.pattern_known()) then
        say('The resting timer has seen enough ticks to know the 9, 9, 12 pattern.');
    else
        say('The resting timer hasn\'t seen enough ticks to know the 9, 9, 12 pattern yet.');
    end
end

local function set_choice(row, value)
    for _, choice in ipairs(row.choices) do
        if (choice[3] == value) then
            cadence.settings[row.section][row.key] = choice[1];
            apply_and_save();
            say(('%s is set to %s.'):format(row.name, choice[2]));
            return;
        end
    end
    say(('Type /cadence %s %s.'):format(command_of(row), choice_words(row)));
end

-- Sets a row of SETTINGS from the word typed after it. With no word, a switch flips.
local function run_setting(row, value)
    if (row.choices ~= nil) then
        set_choice(row, value);
        return;
    end

    local current;
    if (row.layout) then
        current = shared_layout.is_on();
    else
        current = cadence.settings[row.section][row.key];
    end
    local on = ON_WORDS[value];
    if (value == nil) then
        on = not current;
    elseif (on == nil) then
        say(('Type /cadence %s on|off.'):format(command_of(row)));
        return;
    end

    local timer = TIMER_NAMES[row.section];
    local line = ('%s is %s%s.'):format(row.name, on and 'on' or 'off', timer and (' for ' .. timer:lower()) or '');
    if (row.layout) then
        share_layout(on);
        say(line);
        return;
    end
    cadence.settings[row.section][row.key] = on;
    -- Said first, so a warning from the change, like a sound that won't play, is the last thing you read.
    say(line);
    apply_and_save();
end

-- Lists what can follow a timer's word, when the word after it isn't one of its parts.
local function say_part_usage(key)
    local forms = { ('/cadence %s on|off'):format(key) };
    for _, row in ipairs(SETTINGS) do
        if (row.section == key and row.choices ~= nil) then
            forms[#forms + 1] = ('/cadence %s %s'):format(command_of(row), choice_words(row));
        end
    end
    forms[#forms + 1] = ('/cadence %s <part> on|off'):format(key);
    forms[#forms + 1] = ('/cadence %s <slider> <number>'):format(key);
    forms[#forms + 1] = ('/cadence %s labeltext <text>'):format(key);
    if (key == 'resting') then
        forms[#forms + 1] = '/cadence resting soundfile <name>';
        forms[#forms + 1] = '/cadence resting playsound';
    end
    say(('Type %s. The parts are %s. The sliders are %s.'):format(listed(forms, 'or'), parts_of(key), sliders_of(key)));
end

local function set_preset(words)
    local name = find_name(words, presets.NAMES, presets.IDS);
    if (name == nil) then
        say(('Type /cadence preset %s.'):format(table.concat(presets.IDS, '|')));
        return;
    end
    -- Like the Preset list, the one you already have does nothing, so it can't replace what Undo puts back.
    if (name == presets.current(cadence.settings)) then
        say(('You already have the %s preset.'):format(name));
        return;
    end
    presets.apply(cadence.settings, name);
    apply_and_save();
    say(('The %s preset is on. /cadence undo takes it back.'):format(name));
end

local function undo_look()
    if (not presets.undo(cadence.settings)) then
        say('There\'s nothing to undo. Undo only takes back your last preset or Reset look.');
        return;
    end
    apply_and_save();
    say('Your look is back to how it was before your last preset or Reset look.');
end

local function set_font(words)
    local fonts = font_list();
    local name = find_name(words, fonts);
    if (name == nil) then
        say(('Type /cadence font <name>. The fonts are %s.'):format(listed(fonts)));
        return;
    end
    local style = cadence.settings.style;
    style.system_font = name ~= hud.ASHITA_FONT;
    if (style.system_font) then
        style.font_name = name;
    end
    apply_and_save();
    say(('The timers use the %s font now.'):format(name));
end

-- `words` names one of the settings window's fonts, with or without its spaces. A font that won't load
-- is still picked, the same as in the Font list, and the answer says so.
local function set_window_font(words)
    local entry = window_font.find(words);
    if (entry == nil) then
        say(('Type /cadence windowfont <name>. The fonts are %s.'):format(listed(WINDOW_FONT_NAMES)));
        return;
    end
    cadence.settings.window_style.font = entry.id;
    apply_and_save();
    if (window_font.failed(entry.id)) then
        say(('%s isn\'t in %s or won\'t load, so the settings window uses Ashita\'s font.')
            :format(entry.name, window_font.FOLDER));
        return;
    end
    say(('The settings window uses the %s font now.'):format(entry.name));
end

--[[
    `word` as a number from `low` to `high`, or nil. It's rounded to `places` decimal places, the same
    as its slider shows, so it has to be whole when `places` is nil.
]]
local function read_number(word, low, high, places)
    local value = tonumber(word);
    if (value == nil) then
        return nil;
    end
    local step = 10 ^ (places or 0);
    local rounded = math.floor(value * step + 0.5) / step;
    if ((places == nil and rounded ~= value) or not (rounded >= low and rounded <= high)) then
        return nil;
    end
    return rounded;
end

-- Sets a row of NUMBERS from the word typed after it, or to auto.
local function set_number(row, word)
    local low, high = number_range(row);
    local value = read_number(word, low, high, row.places);
    if (row.auto ~= nil and word == 'auto') then
        value = row.auto;
    end
    if (value == nil) then
        say(('Type /cadence %s %s.'):format(command_of(row), range_text(row)));
        return;
    end
    cadence.settings[row.section][row.key] = value;
    apply_and_save();
    if (value == row.auto) then
        say(row.said_auto);
        return;
    end
    say(row.said:format(number_text(row, value)));
end

-- The color `word` stands for as six hex digits, or eight with how solid it is last, and its digits in
-- lowercase. A # in front is fine. Nil after saying it isn't a color.
local function read_color(word)
    local digits = word:match('^#?(%x+)$');
    if (digits == nil or (#digits ~= 6 and #digits ~= 8)) then
        say(('"%s" isn\'t a color. Type six hex digits like c55151, or eight like c55151cc to make it see-through.')
            :format(word));
        return nil;
    end
    local alpha = (#digits == 8) and tonumber(digits:sub(7, 8), 16) / 255 or 1;
    return theme.hex(digits, alpha), digits:lower();
end

-- `what` names one of the settings window's colors, and `word` is the color as six hex digits, or
-- eight with how solid it is last.
local function set_window_color(what, word)
    if (what == nil or word == nil) then
        say('Type /cadence windowcolor <what> <rrggbb>. /cadence help windowcolors lists the window colors.');
        return;
    end
    local entry = find_window_color(what);
    if (entry == nil) then
        say(('There\'s no window color called "%s". /cadence help windowcolors lists them.'):format(what));
        return;
    end
    local color, digits = read_color(word);
    if (color == nil) then
        return;
    end
    cadence.settings.window_style[entry.key] = color;
    apply_and_save();
    say(('The %s window color is set to %s.'):format(entry.key, digits));
end

-- `what` names one of the timers' colors, and `word` is the color the same way as for a window color.
local function set_color(what, word)
    if (what == nil or word == nil) then
        say('Type /cadence color <what> <rrggbb>. /cadence help colors lists the colors.');
        return;
    end
    local entry = find_color(what);
    if (entry == nil) then
        say(('There\'s no color called "%s". /cadence help colors lists them.'):format(what));
        return;
    end
    local color, digits = read_color(word);
    if (color == nil) then
        return;
    end
    cadence.settings[entry.section][entry.key] = color;
    apply_and_save();
    say(('The %s color is set to %s.'):format(entry.word, digits));
end

-- Text typed after a command, in printable ASCII. The chat line sends Shift-JIS, so each auto-translate
-- phrase and two-byte character goes whole, and none of its bytes stay behind as letters.
local function clean_typed(text)
    return (text:gsub('\253[^\253]*\253?', ''):gsub('[\129-\159\224-\252].', ''):gsub('[^\32-\126]', ''));
end

--[[
    Types a timer's label, the same as its box under LABELS on the Look tab. `text` is everything after
    labeltext, so it needs no quotes, or nil when nothing follows labeltext. Empty quotes put the
    timer's own name back. Like the box, it keeps up to 23 plain characters.
]]
local function set_label(key, text)
    if (text == nil) then
        say(('Type /cadence %s labeltext <text>, or /cadence %s labeltext "" for its own name.'):format(key, key));
        return;
    end
    local label = clean_typed(text):sub(1, defaults.LABEL_LENGTH);
    if (label == '' and text ~= '') then
        say('That label has nothing cadence can use. Use plain English letters, numbers or symbols.');
        return;
    end
    local element = cadence.settings[key];
    element.label_text = label;
    apply_and_save();
    if (label ~= '') then
        say(('%s\'s label is set to "%s".'):format(TIMER_NAMES[key], label));
        return;
    end
    local own = (key == 'enemy' and element.attached) and 'ENEMY' or OWN_NAMES[key];
    say(('%s\'s label is back to %s.'):format(TIMER_NAMES[key], own));
end

-- The sounds you can pick for chat, from the last look, or a line saying there are none.
local function sound_list()
    local files = sound.files();
    if (#files == 0) then
        return 'There are no .mp3 or .wav files in config\\addons\\cadence\\sounds yet.';
    end
    return ((#files == 1) and 'The sound you can pick is %s.' or 'The sounds you can pick are %s.')
        :format(listed(files));
end

--[[
    Picks the sound, the same as the Sound list on the Timers tab. `words` is everything after
    soundfile, so a name with spaces needs no quotes, and it can leave off .mp3 or .wav. The sounds
    folders are read again first, since you may have just put a file there. With the sound on, the
    file opens now. One that won't open is still picked, and chat says so.
]]
local function set_sound_file(words)
    sound.refresh();
    if (words == '') then
        say('Type /cadence resting soundfile <name>. ' .. sound_list());
        return;
    end
    local name = sound.find(words);
    if (name == nil) then
        say(('There\'s no sound called "%s". %s'):format(words, sound_list()));
        return;
    end
    local element = cadence.settings.resting;
    element.sound_file = name;
    local ok = not element.sound or open_sound(true);
    apply_and_save();
    if (ok) then
        say(('%s is the resting sound now.%s'):format(name,
            element.sound and '' or ' It plays once you turn it on with /cadence resting sound on.'));
    end
end

-- Plays the sound, the same as Play, and says what it played.
local function say_play_sound()
    local element = cadence.settings.resting;
    if (play_sound()) then
        say(('Playing %s at %d%% volume.'):format(element.sound_file, element.sound_volume));
    end
end

-- `what` names a part of cadence's chat lines, and `words` a chat color by its name or number.
local function set_chat_color(what, words)
    if (what == nil or words == '') then
        say('Type /cadence chatcolor <what> <color>. /cadence help chatcolors lists the choices.');
        return;
    end
    local part = chat_colors.part(what);
    if (part == nil) then
        say(('There\'s no chat color called "%s". The chat colors are %s.'):format(what, listed(CHAT_PARTS)));
        return;
    end
    local entry = chat_colors.find(words);
    if (entry == nil) then
        say(('"%s" isn\'t a chat color. /cadence help chatcolors lists them.'):format(words));
        return;
    end
    cadence.settings.chat[part.key] = entry.code;
    save_settings();
    say(('The %s chat color is set to %s.'):format(part.key, entry.name));
end

--[[
    Profile commands. ui\profiles.lua keeps the profiles. A name matches in any case, and one with
    spaces can go in quotes. Each one reads profiles.json again first, since another character can
    change it.
]]
local PROFILE_USAGE = 'Type /cadence profile save|overwrite|load|delete <name>, or /cadence profile rename <old> '
    .. '<new>. Put a name with spaces in quotes.';
local NO_PROFILE = 'There\'s no profile called "%s". /cadence help profiles lists yours.';

-- A profile name typed after a command, cleaned. Nil after saying there's nothing in it to use.
local function typed_profile_name(words)
    local name = profiles.clean_name(clean_typed(words));
    if (name == '') then
        say('That name has nothing cadence can use. Use plain English letters, numbers or symbols.');
        return nil;
    end
    return name;
end

-- The saved profile a typed name stands for. Nil after saying there isn't one.
local function typed_profile(words)
    local name = typed_profile_name(words);
    if (name == nil) then
        return nil;
    end
    local found = profiles.find(name);
    if (found == nil) then
        say(NO_PROFILE:format(name));
    end
    return found;
end

-- Like Save as new, a name that's taken in any case is refused. Overwrite saves over it. None and (none)
-- are refused too, since job links use them.
local function save_profile(words)
    local name = typed_profile_name(words);
    if (name == nil) then
        return;
    end
    local taken = profiles.find(name);
    if (taken ~= nil) then
        say(('There\'s already a profile called "%s". /cadence profile overwrite saves over it.'):format(taken));
    elseif (profiles.no_link_word(name)) then
        say(profiles.NO_LINK_NAME:format(name));
    elseif (not profiles.save(cadence.settings, name)) then
        say(profiles.problem());
    else
        say(('Your settings are saved as the profile "%s".'):format(name));
    end
end

local function overwrite_profile(words)
    local name = typed_profile(words);
    if (name == nil) then
        return;
    end
    if (not profiles.save(cadence.settings, name)) then
        say(profiles.problem());
        return;
    end
    say(('Your settings are saved over the profile "%s".'):format(name));
end

-- While one layout is shared, the profile goes into the shared layout.
local function load_profile(words)
    local name = typed_profile(words);
    if (name == nil) then
        return;
    end
    profiles.load(cadence.settings, name);
    apply_and_save();
    say(('Your settings now come from the profile "%s".'):format(name));
end

-- Your job links to it go too.
local function delete_profile(words)
    local name = typed_profile(words);
    if (name == nil) then
        return;
    end
    local ok, relinked = profiles.delete(cadence.settings, name);
    if (not ok) then
        say(profiles.problem());
        return;
    end
    if (relinked) then
        save_own();
    end
    say(('The profile "%s" is deleted.'):format(name));
end

-- A change of case alone is fine, like solo to Solo. Your job links to it follow.
local function rename_profile(old_words, new_words)
    local old = typed_profile(old_words);
    local new = old and typed_profile_name(new_words);
    if (new == nil) then
        return;
    end
    local taken = profiles.find(new);
    if (new == old) then
        say(('The profile is already called "%s".'):format(new));
        return;
    elseif (taken ~= nil and taken ~= old) then
        say(('There\'s already a profile called "%s".'):format(taken));
        return;
    elseif (profiles.no_link_word(new)) then
        say(profiles.NO_LINK_NAME:format(new));
        return;
    end
    local ok, relinked = profiles.rename(cadence.settings, old, new);
    if (not ok) then
        say(profiles.problem());
        return;
    end
    if (relinked) then
        save_own();
    end
    say(('The profile "%s" is now called "%s".'):format(old, new));
end

-- Each profile action by its word.
local PROFILE_ACTIONS = {
    save = save_profile, overwrite = overwrite_profile, load = load_profile, delete = delete_profile,
    rename = rename_profile,
};

-- Rename takes two names. The others take everything after the action word as one name.
local function run_profile(args)
    local action = args[3] and PROFILE_ACTIONS[args[3]:lower()];
    local rename = action == rename_profile;
    local words = table.concat(args, ' ', 4);
    if (action == nil or words == '' or (rename and #args ~= 5)) then
        say(PROFILE_USAGE);
        return;
    end
    profiles.refresh();
    if (not profiles.file_ok()) then
        say(profiles.problem());
        return;
    end
    if (rename) then
        rename_profile(args[4], args[5]);
    else
        action(words);
    end
end

local JOB_LINK_USAGE = 'Type /cadence joblink <job> <profile>, or /cadence joblink <job> none to stop that job loading '
    .. 'one.';

-- The main job with this short name in any case, like blm for BLM, or nil.
local function find_job(word)
    local wanted = word:upper();
    for _, job in ipairs(defaults.JOBS) do
        if (job == wanted) then
            return job;
        end
    end
    return nil;
end

--[[
    Links a profile to a main job, the same as that job's list on the Profiles tab. `words` is
    everything after the job, so a name with spaces needs no quotes. None stops the job loading a
    profile. Only a profile that's there can be linked. Job links go into this character's own file,
    even while one layout is shared.
]]
local function set_job_link(word, words)
    if (word == nil or words == '') then
        say(JOB_LINK_USAGE);
        return;
    end
    local job = find_job(word);
    if (job == nil) then
        say(('There\'s no job called "%s". The jobs are %s.'):format(word, JOB_LIST));
        return;
    end
    -- The list shows (none), so that clears a link too.
    if (profiles.no_link_word(words)) then
        cadence.settings.job_links[job] = nil;
        save_own();
        say(('Changing to %s no longer loads a profile.'):format(job));
        return;
    end
    profiles.refresh();
    if (not profiles.file_ok()) then
        say(profiles.problem());
        return;
    end
    local name = typed_profile(words);
    if (name == nil) then
        return;
    end
    cadence.settings.job_links[job] = name;
    save_own();
    say(('The profile "%s" now loads when you change to %s and zone.'):format(name, job));
end

-- When /cadence reset all was first typed. A second one within RESET_ALL_SECONDS does it.
local reset_asked = nil;

-- Every setting back to its default, then the timers stacked at their default spot like Reset positions.
-- Your job links are cleared. Undo has nothing left to put back.
local function reset_all()
    local now = os.clock();
    if (reset_asked == nil or now - reset_asked > RESET_ALL_SECONDS) then
        reset_asked = now;
        say(('This puts every setting back to its default, including where the timers sit and which ones are on, '
            .. 'and clears your job links. Your saved profiles stay. Type /cadence reset all again within %d seconds '
            .. 'to go ahead.'):format(RESET_ALL_SECONDS));
        return;
    end
    reset_asked = nil;
    -- The settings window keeps its spot and size. While it's open it would save them right back anyway.
    for name, section in pairs(defaults.make()) do
        if (name ~= 'window') then
            for key, value in pairs(section) do
                cadence.settings[name][key] = value;
            end
        end
    end
    -- Emptied in place, since a shared layout uses this character's own table.
    local links = cadence.settings.job_links;
    for job in pairs(links) do
        links[job] = nil;
    end
    presets.forget_undo();
    apply_settings();
    reset_positions();
    save_settings();
    if (shared_layout.is_on()) then
        save_own();
    end
    say('Every setting is back to its default and your job links are cleared. Your saved profiles are still there.');
end

-- Plain /cadence reset puts back positions only.
local function reset(word)
    if (word == nil) then
        reset_positions();
        save_settings();
        say('The timers are back at their default positions.');
    elseif (word == 'look') then
        presets.reset(cadence.settings);
        apply_and_save();
        say('The look is back to default. /cadence undo takes it back.');
    elseif (word == 'all') then
        reset_all();
    else
        say('Type /cadence reset, /cadence reset look or /cadence reset all.');
    end
end

local function set_timer(key, word)
    local timer = cadence.settings[key];
    if (word == 'on') then
        timer.enabled = true;
    elseif (word == 'off') then
        timer.enabled = false;
    else
        timer.enabled = not timer.enabled;
    end
    save_settings();
    say(('%s is %s.'):format(TIMER_NAMES[key], timer.enabled and 'on' or 'off'));
end

ashita.events.register('command', 'cadence_command', function (e)
    local args = e.command:args();
    if (#args == 0) then
        return;
    end
    local command = args[1]:lower();
    if (command ~= '/cadence' and command ~= '/cad') then
        return;
    end
    e.blocked = true;

    local sub = args[2] and args[2]:lower() or nil;
    local word = args[3] and args[3]:lower() or nil;
    -- A timer's part or slider comes after the timer's word. Any other setting is the word itself.
    local timer = TIMER_NAMES[sub] ~= nil;
    local row = timer and find_setting(sub, word) or find_setting('style', sub);
    local number_row = timer and find_number(sub, word) or find_number(nil, sub);
    if (sub == nil) then
        settings_window.set_open(not settings_window.is_open());
        cadence.broken = false;
    elseif (timer and (word == nil or ON_WORDS[word] ~= nil)) then
        set_timer(sub, word);
    elseif (timer and row ~= nil) then
        run_setting(row, args[4] and args[4]:lower());
    elseif (timer and number_row ~= nil) then
        set_number(number_row, args[4] and args[4]:lower());
    elseif (timer and word == 'labeltext') then
        set_label(sub, args[4] and table.concat(args, ' ', 4));
    elseif (sub == 'resting' and word == 'soundfile') then
        set_sound_file(table.concat(args, ' ', 4));
    elseif (sub == 'resting' and word == 'playsound') then
        say_play_sound();
    elseif (timer) then
        say_part_usage(sub);
    elseif (row ~= nil) then
        run_setting(row, word);
    elseif (number_row ~= nil) then
        set_number(number_row, word);
    elseif (sub == 'color') then
        set_color(word, args[4]);
    elseif (sub == 'windowfont') then
        set_window_font(table.concat(args, ' ', 3));
    elseif (sub == 'windowcolor') then
        set_window_color(word, args[4]);
    elseif (sub == 'chatcolor') then
        set_chat_color(word, table.concat(args, ' ', 4));
    elseif (sub == 'profile') then
        run_profile(args);
    elseif (sub == 'joblink') then
        set_job_link(args[3], table.concat(args, ' ', 4));
    elseif (sub == 'preset') then
        set_preset(table.concat(args, ' ', 3));
    elseif (sub == 'undo') then
        undo_look();
    elseif (sub == 'font') then
        set_font(table.concat(args, ' ', 3));
    elseif (sub == 'lock' or sub == 'unlock') then
        cadence.settings.style.locked = sub == 'lock';
        save_settings();
        say(sub == 'lock' and 'The timers are locked in place.' or 'Hold Shift and drag a timer to move it.');
    elseif (sub == 'reset') then
        reset(word);
    elseif (sub == 'hide' or sub == 'show') then
        cadence.hidden = sub == 'hide' and not cadence.hidden;
        say(cadence.hidden and 'The timers are hidden. Type /cadence hide again to bring them back.'
            or 'The timers are back.');
    elseif (sub == 'info') then
        print_info();
    elseif (sub == 'help') then
        print_help(word);
    else
        say(('Didn\'t recognize "%s". Type /cadence help to see the commands.'):format(args[2]));
    end
end);

--[[
    Packets.
]]

-- A spell finish with no spell id is a paralyzed or intimidated auto attack, job ability, item or
-- ranged attack, or a weapon skill used out of range. The message picks out the weapon skill.
-- attack.on_paralyzed tells the others apart by timing.
local function on_failed_action(e, now)
    if (packets.action_messages(e, cadence.messages) == 0) then
        return;
    end
    local message = cadence.messages[1];
    if (message == WEAPONSKILL_TOO_FAR) then
        attack.on_ability(now);
    elseif (PARALYZED_OR_INTIMIDATED[message]) then
        attack.on_paralyzed(now);
    end
end

local CATEGORY = packets.CATEGORY;

-- What each kind of start packet is holding the auto attack timer for.
local CAST_KIND = {
    [CATEGORY.SPELL_START]  = 'spell',
    [CATEGORY.ITEM_START]   = 'item',
    [CATEGORY.RANGED_START] = 'ranged',
};

local function on_my_action(e, category, now)
    if (category == CATEGORY.MELEE) then
        local estimate, key, loadout = current_delay();
        attack.on_round(now, estimate, key);
        -- A round means the server let you attack, so any range or facing word starts over from here.
        cadence.battle_id = packets.action_target(e);
        reach.forget();
        if (tracking_tp()) then
            local hits, hit_back, clean_start = packets.melee_hits(e);
            tp.on_round(now, hits, hit_back, clean_start, loadout);
        end
        return;
    end

    -- Anything else you do can change your TP, like a weapon skill using it up. Meditate is told apart
    -- by its job ability id.
    tp.on_own_action(now, category == CATEGORY.ABILITY and packets.action_param(e) or nil);
    if (category == CATEGORY.WEAPONSKILL or category == CATEGORY.ABILITY) then
        attack.on_ability(now);
    elseif (CAST_KIND[category] ~= nil) then
        local param = packets.action_param(e);
        if (param == packets.CAST_BEGIN) then
            attack.on_cast_begin(now, CAST_KIND[category]);
        elseif (param == packets.CAST_INTERRUPT) then
            attack.on_cast_end(now);
        end
    elseif (category == CATEGORY.SPELL_FINISH) then
        if (packets.action_param(e) == 0) then
            on_failed_action(e, now);
        else
            attack.on_cast_end(now);
        end
    elseif (category == CATEGORY.ITEM_FINISH or category == CATEGORY.RANGED_FINISH) then
        attack.on_cast_end(now);
    end
end

-- What a monster did. Its attack rounds set its clock, and its TP moves and spells pause it.
local function on_enemy_action(e, actor, category, now)
    if (category == CATEGORY.MELEE) then
        enemy.on_round(now, actor, packets.action_target(e));
    elseif (category == CATEGORY.MOBSKILL_START or category == CATEGORY.SPELL_START) then
        local param = packets.action_param(e);
        if (param == packets.CAST_BEGIN) then
            enemy.on_hold_begin(now, actor, (category == CATEGORY.MOBSKILL_START) and 'tp_move' or 'spell');
        elseif (param == packets.CAST_INTERRUPT) then
            enemy.on_interrupt(now, actor, category == CATEGORY.SPELL_START);
        end
    elseif (category == CATEGORY.MOBSKILL_FINISH or category == CATEGORY.WEAPONSKILL) then
        -- A monster using a player weapon skill finishes it with category 3, not 11.
        enemy.on_hold_end(now, actor);
    elseif (category == CATEGORY.SPELL_FINISH) then
        if (packets.action_param(e) ~= 0) then
            enemy.on_hold_end(now, actor);
        elseif (packets.action_messages(e, cadence.messages) > 0) then
            local message = cadence.messages[1];
            if (PARALYZED_OR_INTIMIDATED[message]) then
                enemy.on_paralyzed(now, actor, packets.action_target(e));
            elseif (TP_MOVE_MISSED[message]) then
                enemy.on_hold_end(now, actor);
            end
        end
    end
end

-- Slow, Elegy, Haste or Hundred Fists landing on a monster, or coming off it, from anyone's action.
local function watch_effects(e, actor, category, now)
    local count = packets.action_results(e, cadence.results);
    local id = packets.action_param(e);
    for i = 1, count do
        local result = cadence.results[i];
        if (result.target >= FIRST_MONSTER_ID) then
            local info = monster_effects.landed(category, id, result.message, result.param);
            if (info ~= nil) then
                enemy.on_effect(now, result.target, info, actor == cadence.my_id);
            elseif (monster_effects.removed(result.message)) then
                enemy.on_effect_gone(now, result.target, result.param);
            end
        end
    end
end

local function on_action(e)
    local actor, category = packets.action_header(e);
    local now = os.clock();
    if (actor == cadence.my_id) then
        on_my_action(e, category, now);
    elseif (actor >= FIRST_MONSTER_ID) then
        -- A monster's action on you can give you TP too.
        if (tracking_tp() and packets.action_has_target(e, cadence.my_id)) then
            tp.on_stir();
        end
        if (cadence.settings.enemy.enabled) then
            on_enemy_action(e, actor, category, now);
        end
    end
    if (cadence.settings.enemy.enabled and monster_effects.can_land(category)) then
        watch_effects(e, actor, category, now);
    end
end

-- Why you can't attack, an effect wearing off a monster, or a monster being defeated. Only whoever
-- cast an effect hears it wear off. A defeated monster's clock goes with it. When the timer follows
-- that one, its speed is kept first.
local function on_message(e)
    local actor, message, target, param = packets.message(e);
    if (actor == cadence.my_id and CANT_ATTACK[message] ~= nil) then
        attack.on_out_of_reach(CANT_ATTACK[message] or nil);
    elseif (target >= FIRST_MONSTER_ID and cadence.settings.enemy.enabled) then
        if (actor == cadence.my_id and monster_effects.WEARS_OFF[message]) then
            enemy.on_effect_gone(os.clock(), target, param);
        elseif (monster_effects.DEFEATED[message]) then
            if (target == cadence.enemy_id) then
                enemy.remember(target, cadence.enemy_name);
            end
            enemy.forget(target);
        end
    end
end

-- The server moved your attacks to another monster, like after /attack on a new one mid-fight. Range /
-- facing checks that one from now on. /assist sends the same packet. After one, the check follows the
-- assisted monster until your next round.
local function on_assist(e)
    local who, monster = packets.assist(e);
    if (who == cadence.my_id and monster >= FIRST_MONSTER_ID) then
        cadence.battle_id = monster;
    end
end

-- Your HP, MP and TP. A party member's packet is only read as far as whose it is.
local function on_vitals(e)
    if (packets.vitals_member(e) ~= cadence.my_id) then
        return;
    end
    local now = os.clock();
    local hp, mp, tp_value = packets.vitals(e);
    local hp_max, mp_max = player.max_vitals();
    resting.on_vitals(now, hp, mp, tp_value, hp_max, mp_max);
    tp.on_vitals(now, tp_value);
end

-- You zoned or logged in. The packet carries your server id.
local function on_zone_in(e)
    cadence.my_id = packets.zone_in(e);
    cadence.last_status = nil;
    attack.reset();
    resting.reset();
    enemy.reset();
    cadence.enemy_id = nil;
    cadence.battle_id = nil;
    tp.on_zone();
    cadence.job_check = true;
end

ashita.events.register('packet_in', 'cadence_packet_in', function (e)
    local id = e.id;
    if (id == packets.ID.ACTION) then
        on_action(e);
    elseif (id == packets.ID.MESSAGE) then
        on_message(e);
    elseif (id == packets.ID.ASSIST) then
        on_assist(e);
    elseif (id == packets.ID.VITALS) then
        on_vitals(e);
    elseif (id == packets.ID.ZONE_IN) then
        on_zone_in(e);
    end
end);

--[[
    Frame. A drawing error stops the drawing and says so once, rather than every frame.
]]

ashita.events.register('d3d_present', 'cadence_present', function ()
    if (cadence.broken) then
        return;
    end
    local ok, err = pcall(render);
    if (not ok) then
        cadence.broken = true;
        say(('Drawing stopped after an error: %s. Type /cadence to try again.'):format(tostring(err)));
    end
end);

-- Picking the settings opens your sound file, if the sound is on.
ashita.events.register('load', 'cadence_load', function ()
    hud.load_fonts();
    window_font.load_all();
    sound.make_folder();
    cadence.my_id = player.server_id() or 0;
    pick_settings();
end);

-- Only this character's own file. The shared layout is written when something changes, so a character
-- logging out can't undo a change made on another one. The sound file closes.
ashita.events.register('unload', 'cadence_unload', function ()
    defaults.tidy(cadence.own);
    settings.save();
    sound.close();
end);

-- Another character logged in. Their own settings replace the current ones, unless every character
-- shares one layout. The delays, TP per hit and monster speeds learned on the last one are dropped.
-- Their id comes from the 0x00A packet. Party memory can still hold the last character's here. An
-- open settings window moves to their spot and size. Their job is read after the 0x00A, and that
-- first read only notes it.
settings.register('settings', 'cadence_settings_update', function (s)
    if (s ~= nil) then
        unshare(s, kept_defaults, defaults.make());
        cadence.own = s;
    end
    presets.forget_undo();
    attack.forget_learned();
    tp.forget();
    enemy.forget_speeds();
    pick_settings();
    settings_window.place_again();
    cadence.last_job = nil;
end);
