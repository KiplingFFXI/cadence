-- Starter layouts choose timer readouts. Personal styling, targets and positions stay yours.
local history = require('ui.history');
local layouts = {};
local KEEP = 'Keeps positions, sizes, colors, fonts, labels, sounds, TP and recovery targets, enemy following and attachment, and saved profiles.';
local LIST = {
    { id = 'minimal', name = 'Minimal', description = 'Attack and resting countdowns with fewer extra readouts.',
        changes = { 'Enables attack and resting timers and turns the enemy timer off.',
            'Shows countdowns and reasons for waiting, without TP or recovery detail rows.', KEEP } },
    { id = 'melee', name = 'Melee / TP', description = 'Attack timing and progress toward your current TP goal.',
        changes = { 'Enables attack and resting timers and turns the enemy timer off.',
            'Shows attack delay, TP, approximate rounds, successful hits and time to your current TP goal.',
            'Shows resting countdown and time until full.', KEEP } },
    { id = 'resting', name = 'Resting', description = 'Recovery gains, full times and your current recovery goal.',
        changes = { 'Enables the resting timer and turns attack and enemy timers off.',
            'Shows last and next gains, ticks until full, separate HP/MP full times and the recovery goal.', KEEP } },
    { id = 'enemy', name = 'Enemy tracking', description = 'Enemy timing alongside your attack and resting countdowns.',
        changes = { 'Enables all three timers.',
            'Shows enemy name, attack interval, speed effects, action holds and attacks on you.',
            'Keeps your chosen enemy-following and attachment behavior.', KEEP } },
};
local BASE = {
    attack = { enabled = true, show_value = true, show_delay = false, show_tp = false, show_tp_rounds = false,
        show_tp_hits = false, show_tp_time = false, show_reason = true, show_why = true },
    resting = { enabled = true, show_value = true, show_gains = false, show_next_gains = false, show_ticks = false,
        show_until_full = false, show_each_full = false, show_goal = false, show_why = true },
    enemy = { enabled = false, show_value = true, show_name = true, show_delay = true, show_effects = true,
        show_holds = true, show_on_you = true },
};
local CHOICES = {
    minimal = {},
    melee = { attack = { show_delay = true, show_tp = true, show_tp_rounds = true, show_tp_hits = true, show_tp_time = true },
        resting = { show_until_full = true } },
    resting = { attack = { enabled = false },
        resting = { show_gains = true, show_next_gains = true, show_ticks = true, show_until_full = true,
            show_each_full = true, show_goal = true } },
    enemy = { attack = { show_delay = true }, resting = { show_until_full = true }, enemy = { enabled = true } },
};
local function find(id)
    local key = tostring(id or ''):lower():gsub('[%s_/%-]+', '');
    if (key == 'meleetp') then key = 'melee'; end
    if (key == 'enemytracking') then key = 'enemy'; end
    for _, entry in ipairs(LIST) do if (entry.id == key) then return entry; end end
end

function layouts.list()
    return history.copy(LIST);
end

function layouts.find(id)
    local entry = find(id);
    return entry and history.copy(entry);
end

local function configure(settings, id)
    local choices = CHOICES[id];
    for section, keys in pairs(BASE) do
        for key, value in pairs(keys) do
            local custom = choices[section] and choices[section][key];
            if (custom ~= nil) then value = custom; end
            settings[section][key] = value;
        end
    end
end

function layouts.preview(settings, id)
    local entry = find(id);
    if (entry == nil) then return nil; end
    local copy = history.copy(settings);
    configure(copy, entry.id);
    return copy, history.copy(entry);
end

function layouts.apply(settings, id)
    local entry = find(id);
    if (entry == nil) then return false; end
    configure(settings, entry.id);
    return true, history.copy(entry);
end

-- Only the display choices this layout owns affect its modified indicator.
function layouts.matches(settings, id)
    local entry = find(id);
    if (entry == nil) then return false; end
    local choices = CHOICES[entry.id];
    for section, keys in pairs(BASE) do
        for key, value in pairs(keys) do
            local custom = choices[section] and choices[section][key];
            if (custom ~= nil) then value = custom; end
            if (settings[section][key] ~= value) then return false; end
        end
    end
    return true;
end

return layouts;
