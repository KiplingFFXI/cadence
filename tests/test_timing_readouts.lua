-- New readouts keep confidence visible and preserve the existing compact cards.
local out, fails = {}, 0;
local function check(name, ok, detail)
    if ok then out[#out + 1] = 'ok   ' .. name;
    else fails = fails + 1; out[#out + 1] = 'FAIL ' .. name .. ' ' .. tostring(detail or ''); end
end
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
local s = MOCK.settings.current;
local hud, imgui = require('ui.hud'), require('imgui');
local defaults, profiles, window = require('ui.defaults'), require('ui.profiles'), require('ui.settings_window');
s.style.text_shadow, s.style.text_outline = false, false;
local function capture(draw)
    hud.refresh(s);
    MOCK.record_imgui, MOCK.imgui_calls = true, {};
    hud.begin_frame(); draw(); hud.end_frame();
    MOCK.record_imgui = false;
    local text, positions = {}, {};
    for _, c in ipairs(MOCK.imgui_calls) do
        if c[1] == 'dl:AddText' then text[#text + 1], positions[c[6]] = c[6], c[4]; end
    end
    return table.concat(text, '|'), positions;
end
check('new readouts and recording are opt in', not s.attack.show_tp_hits and not s.resting.show_ticks
    and not s.style.record_diagnostics and s.attack.tp_goal == 1000);
s.resting.width = 640;
s.resting.show_label, s.resting.show_value, s.resting.show_gains = false, false, false;
s.resting.show_next_gains, s.resting.show_ticks, s.resting.show_each_full = true, true, true;
local view = { fill=.3, left=5, gained_hp=24, gained_mp=31, next_hp=28, next_mp=34, next_estimated=true,
    full=false, has_mp=true, flash=0, until_full=42, hp_full_in=30, mp_full_in=42,
    full_meta={ticks=4,hp_ticks=3,mp_ticks=4,confidence='estimated',hp_confidence='known',mp_confidence='estimated'} };
local function rest() return capture(function() hud.draw_resting(view); end); end
local text, positions = rest();
check('estimated combined ETA has a visible tilde', text:find('full in ~42s',1,true), text);
check('each full time uses its own confidence', text:find('HP full in 30s',1,true)
    and text:find('MP full in ~42s',1,true), text);
check('ticks use a separate row between next gains and full times', positions['~4 ticks to full']
    and positions['~4 ticks to full'][2] > positions['next +28 HP +34 MP est.'][2]
    and positions['~4 ticks to full'][2] < positions['HP full in 30s'][2], text);
local height = select(2,hud.element_size('resting'));
view.full_meta.confidence, view.full_meta.mp_confidence = 'observed', 'observed';
text = rest();
check('confidence changes refresh text even when the seconds stay unchanged',
    text:find('full in 42s',1,true) and text:find('4 ticks to full',1,true)
    and not text:find('~',1,true), text);
view.why = 8;
text = rest();
check('blocked healing hides all estimated amounts without changing card size',
    text == '' and select(2,hud.element_size('resting')) == height, text);
view.why, view.full = nil, true;
view.until_full, view.hp_full_in, view.mp_full_in = nil, 0, 0;
view.next_hp, view.next_mp = 0, 0;
text = rest();
check('full vitals hide ticks and next gains without changing card size',
    text == 'HP full|MP full' and select(2,hud.element_size('resting')) == height, text);
s.attack.width, s.attack.show_tp_hits = 240, true;
s.attack.show_label, s.attack.show_value, s.attack.show_delay = false, false, false;
local tp = {tp=1234, goal=2000, hits=7, rounds=4, estimated=true};
local function attack() return capture(function() hud.draw_attack(.5,2,4,true,tp); end); end
text, positions = attack();
check('successful hits are separate from approximate rounds', text:find('7 successful hits est.',1,true)
    and text:find('~4 rounds',1,true)
    and positions['7 successful hits est.'][2] > positions['TP 1234'][2], text);
tp.hits_estimated = false;
text = attack();
check('known hit potency does not inherit uncertain rounds', text:find('7 successful hits',1,true)
    and not text:find('7 successful hits est.',1,true) and text:find('rounds est.',1,true),text);
tp.estimated, tp.hits = false, 1;
text = attack();
check('known successful hits have singular wording without est.', text:find('1 successful hit',1,true)
    and not text:find('est.',1,true), text);
tp.hits, tp.rounds = nil, nil;
local attack_height = select(2,hud.element_size('attack'));
text = attack();
check('reaching the goal hides remaining hits without jumping', text == 'TP 1234'
    and select(2,hud.element_size('attack')) == attack_height, text);
s.enemy.attached, s.enemy.show_label, s.enemy.show_name, s.enemy.show_delay, s.enemy.show_effects = false,false,false,false,false;
text = capture(function() hud.draw_enemy({fill=0,left=0,delay=4,learned=true,waiting=true}); end);
check('an overdue enemy explicitly says waiting', text == 'waiting', text);

-- The UI actions and saved profiles use the actual target, not just its displayed label.
window.set_open(true);
rawset(imgui,'BeginCombo',function(label) return label == 'TP goal##attack'; end);
rawset(imgui,'Selectable',function(label) return label == '3000'; end);
local result = window.draw(s,'test',false,false);
rawset(imgui,'BeginCombo',nil);rawset(imgui,'Selectable',nil);
check('the TP goal picker changes the real setting and requests a save', s.attack.tp_goal == 3000
    and result.changed and result.save);
s.attack.show_tp_hits, s.resting.show_ticks = true,true;
check('the new target and readouts save into profiles', profiles.save(s,'Timing readouts'));
s.attack.tp_goal,s.attack.show_tp_hits,s.resting.show_ticks = 1000,false,false;
profiles.load(s,'Timing readouts');
check('loading a profile restores the TP goal and readout switches', s.attack.tp_goal==3000
    and s.attack.show_tp_hits and s.resting.show_ticks);
s.attack.tp_goal=1500;defaults.tidy(s);
check('unsupported saved TP targets return to1000',s.attack.tp_goal==1000);
rawset(imgui,'Checkbox',function(label,value)
    if label=='Record timing details' then value[1]=true;return true;end
    return false;
end);
result=window.draw(s,'test',false,false);
rawset(imgui,'Checkbox',nil);
check('the recording box changes and saves the opt-in setting',s.style.record_diagnostics and result.save);
rawset(imgui,'Button',function(label)return label=='Save timing report';end);
result=window.draw(s,'test',false,false);
check('the report button returns an explicit action',result.save_report);
rawset(imgui,'Button',nil);
result=window.draw(s,'test',false,false);
check('the report action resets on the next frame',not result.save_report);
out[#out+1]=fails==0 and 'ALL OK' or (fails..' FAILED');
return table.concat(out,'\n');
