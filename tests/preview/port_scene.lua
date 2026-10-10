-- Populated evidence for visual checks. These are synthetic inputs, not a live gameplay capture.
local imgui = require('imgui');
local settings = PREVIEW.settings;
local evidence = {
    attack = { source = 'observed', delay = 2.8, modeled_delay = 3, samples = 5, rejected = 1,
        sample_age = 0.2, last_rejection = 'Action hold overlapped the sample' },
    tp = { source = 'observed', per_hit = 78, modeled_per_hit = 76, hits_per_round = 1.6, samples = 6 },
    resting = { next_hp = 34, next_mp = 42, accepted = 3, rejected = 1, pattern_known = true },
    enemy = { source = 'known effects', delay = 4.2, waiting = true, holding = 'sleep', samples = 3,
        effects = { { id = 2, control = 'sleep', uncertain = true, duration_estimate = 90,
            duration_basis = 'spell data with captured cast inputs', inputs_known = false,
            cast_inputs = { equipment_known = true, buffs_known = true, merits_known = false,
                equipment = { { slot = 2, id = 17836, augment = 3, duration_percent = 5 } }, buffs = {}, merits = {} } } } },
    modifiers = { evidence = { age = 0.2 }, unknown = { 'March strength unavailable' }, contributions = {
        { kind = 'equipment', name = 'Speed belt', field = 'haste_gear', value = 400 },
        { kind = 'trait', name = 'Store TP II', field = 'store_tp', value = 15 },
    } },
};
local mode = SCENE_MODE or 'details';
if (mode == 'hover') then
    PREVIEW.window.set_open(false);
    settings.attack.x, settings.attack.y, settings.attack.show_tp = 80, 80, false;
    PREVIEW.hud.refresh(settings); PREVIEW.hud.set_movable(false);
    imgui.GetMousePos = function () return 100, 100; end;
    imgui.IsWindowHovered = function () return false; end;
    return function ()
        MOCK.now = MOCK.now + 0.1;
        PREVIEW.hud.begin_frame(); PREVIEW.hud.draw_attack(0.6, 1.4, 2.8, true);
        imgui.SetNextWindowPos({ 350, 80 }, ImGuiCond_Always);
        PREVIEW.hud.end_frame(evidence);
    end;
end
local input = imgui.InputText;
imgui.InputText = function (label, value, ...)
    if (label == 'Find details' and mode == 'details') then value[1] = 'enemy'; end
    if (label == 'Find settings' and mode == 'search') then value[1] = SCENE_QUERY or 'successful hits'; end
    return input(label, value, ...);
end;
PREVIEW.window.select_tab(mode == 'details' and 'Details' or (SCENE_TAB or 'Timers'));
return function () PREVIEW.window.draw(settings, PREVIEW.version, false, false, nil, evidence); end;
