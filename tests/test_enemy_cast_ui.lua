-- Enemy cast settings stay independent and never turn a sample deadline into a completion claim.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
addon.name = 'cadence';
local defaults, window, preview = require('ui.defaults'), require('ui.settings_window'), require('ui.preview');
local presets, history, layouts = require('ui.presets'), require('ui.history'), require('ui.layouts');
local tips = require('ui.tips');
local s = defaults.make();
check('enemy casting starts off and unattached', not s.enemycast.enabled and not s.enemycast.attached);
check('spell and time readouts start enabled with independent colors', s.enemycast.show_spell and s.enemycast.show_value
    and s.enemycast.fill_start ~= s.enemy.fill_start and s.enemycast.fill_start ~= s.recovery.fill_start);
local old_enemy = s.enemy;
s.enemycast = nil;
defaults.tidy(s);
check('older settings gain the optional card without changing enemy settings', not s.enemycast.enabled and s.enemy == old_enemy);
s.enemycast.width, s.enemycast.height_scale, s.enemycast.label_text = 999, 9, 'Cast\n' .. string.rep('x', 25);
defaults.tidy(s);
check('cast dimensions and labels use the normal limits', s.enemycast.width == 640 and s.enemycast.height_scale == 2.5
    and #s.enemycast.label_text == 23 and not s.enemycast.label_text:find('\n'));
s = defaults.make();
s.enemycast.enabled, s.enemycast.attached, s.enemycast.width = true, true, 311;
s.enemycast.x, s.enemycast.y, s.enemycast.label_text = 14, 28, 'Casting';
for _, name in ipairs(presets.NAMES) do
    presets.apply(s, name);
    check(name .. ' styles casting without changing its layout or attachment', presets.current(s) == name
        and s.enemycast.enabled and s.enemycast.attached and s.enemycast.width == 311
        and s.enemycast.fill_start ~= s.recovery.fill_start);
end
history.reset_section(s, 'enemycast');
check('cast reset keeps its saved position and custom label', not s.enemycast.enabled and not s.enemycast.attached
    and s.enemycast.x == 14 and s.enemycast.y == 28 and s.enemycast.label_text == 'Casting');
history.undo(s);
check('cast reset has one undo for all its choices', s.enemycast.enabled and s.enemycast.attached and s.enemycast.width == 311);
history.reset_section(s, 'enemy');
check('Enemy page reset includes its casting section', not s.enemy.enabled and not s.enemycast.enabled);
history.undo(s);
layouts.apply(s, 'minimal');
check('starter layouts preserve optional casting choices', s.enemycast.enabled and s.enemycast.attached and s.enemycast.width == 311);
local snapshot = history.capture(s);
check('profile snapshots carry casting settings independently', snapshot.enemycast.enabled and snapshot.enemycast ~= s.enemycast
    and snapshot.enemycast.fill_start ~= s.enemycast.fill_start);

window.set_open(true); window.select_tab('Enemy');
MOCK.imgui_calls, MOCK.record_imgui = {}, true;
window.draw(s, '1.4.0', false, false);
MOCK.record_imgui = false;
local toggle, attach, spell, value, height = false, false, false, false, false;
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'Button' and call[2] == 'ON##enemycast') then toggle = true; end
    if (call[1] == 'Checkbox' and call[2] == 'Attach under enemy attack##enemycast') then attach = true; end
    if (call[1] == 'Checkbox' and call[2] == 'Spell name##enemycast') then spell = true; end
    if (call[1] == 'Checkbox' and call[2] == 'Seconds left##enemycast') then value = true; end
    if (call[1] == 'SliderFloat' and call[2] == 'Height##enemycast') then height = true; end
end
check('Enemy exposes casting and independent readout/attachment/height controls', toggle and attach and spell and value and height);
MOCK.window_size = { 560, 760 };
MOCK.imgui_calls, MOCK.record_imgui = {}, true;
window.draw(s, '1.4.0', false, false);
MOCK.record_imgui, MOCK.window_size = false, nil;
local headings = {};
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'TextColored' and (call[3] == 'ENEMY ATTACK TIMER' or call[3] == 'ENEMY BAR' or call[3] == 'ENEMY CAST')) then
        headings[#headings + 1] = call[3];
    end
end
check('narrow settings keep all enemy attack controls before enemy casting', table.concat(headings, '|') == 'ENEMY ATTACK TIMER|ENEMY BAR|ENEMY CAST');
check('search finds casting controls and its label', window.search_tabs('Enemy cast').Enemy
    and window.search_tabs('Attach under enemy attack').Enemy and window.search_tabs('Enemy cast label').Appearance);
local help = tips.text('enemycast');
check('static hover help explains unknown timing and observed completion', help:find('base cast time', 1, true)
    and help:find('Waiting', 1, true) and help:find('does not confirm', 1, true));

s.attack.enabled, s.resting.enabled, s.enemy.enabled, s.recovery.enabled = false, false, false, false;
s.style.text_shadow, s.style.text_outline = false, false;
for _, state in ipairs({ 'normal', 'waiting', 'full', 'blocked' }) do
    MOCK.imgui_calls, MOCK.record_imgui = {}, true;
    preview.draw(s, state, true);
    MOCK.record_imgui = false;
    local words = {};
    for _, call in ipairs(MOCK.imgui_calls) do if (call[1] == 'dl:AddText') then words[#words + 1] = call[6]; end end
    local text = table.concat(words, '|');
    check(state .. ' casting sample never claims completion', text:find('Firaga III', 1, true) and not text:find('ready', 1, true)
        and not text:find('full', 1, true) and text:find((state == 'waiting' or state == 'full') and 'waiting' or '~2.4s', 1, true), text);
end
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
