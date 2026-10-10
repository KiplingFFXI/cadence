-- The user controls change presentation without feeding samples back into live timing.
local out, fails = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then fails = fails + 1; end
end
local function copy(value)
    if (type(value) ~= 'table') then return value; end
    local result = {}; for k, v in pairs(value) do result[k] = copy(v); end; return result;
end
MOCK.player.main_job, MOCK.player.sub_job, MOCK.player.sub_level = 4, 0, 0;
MOCK.player.hp_max, MOCK.player.mp_max = 1000, 500;
MOCK.player.hp, MOCK.player.mp = 200, 250;
MOCK.player.status = 33;
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local s = MOCK.settings.current;
local hud, window = require('ui.hud'), require('ui.settings_window');
local attack, resting = require('core.attack'), require('core.resting');
local presets, profiles = require('ui.presets'), require('ui.profiles');
local draw_rest, draw_attack, draw_window = hud.draw_resting, hud.draw_attack, window.draw;
local seen_rest, seen_attack, seen_preview, seen_details;
hud.draw_resting = function(v) seen_rest = copy(v); return draw_rest(v); end;
hud.draw_attack = function(fill,left,delay,learned,tp,reason,why,cant,preview)
    seen_attack = { fill=fill,left=left,tp=copy(tp),preview=preview };
    return draw_attack(fill,left,delay,learned,tp,reason,why,cant,preview);
end;
window.draw = function(a,b,c,d,preview,details)
    seen_preview, seen_details = copy(preview), details;
    return draw_window(a,b,c,d,preview,details);
end;
local function command(words) MOCK.fire('command', {command='/cadence ' .. words}); end
local function frame(dt) seen_rest,seen_attack=nil,nil; MOCK.frame(dt or 0); end
frame(); resting.on_vitals(MOCK.now,200,250,0,1000,500);
command('resting goal mp amount 300'); frame();
check('absolute recovery goal is enabled and wired to live data', s.resting.show_goal and s.resting.goal_value==300
    and seen_rest.goal.label=='MP 300' and not seen_rest.goal.reached);
command('resting goal hp percent 75'); frame();
check('percentage goals carry resource and percent in the readout',seen_rest.goal.label=='HP 75%' and seen_rest.goal.target_hp==750);
local saves = MOCK.saved;
command('resting goal hp percent 101');
check('invalid goals do not change or save settings',s.resting.goal_value==75 and MOCK.saved==saves);
command('resting goal mp amount 5000'); frame();
check('an absolute goal above max shows the reachable target',seen_rest.goal.target_mp==500 and seen_rest.goal.label=='MP 500');
command('resting goal mp amount 200'); frame();
check('partial goal reached does not mark actual full',seen_rest.goal.reached and not seen_rest.full and not resting.is_full());
command('attack time on'); command('guides on');
check('new persistent controls have command equivalents',s.attack.show_tp_time and s.style.layout_guides);
local before = resting.info(MOCK.now); saves=MOCK.saved;
command('preview resting full'); frame();
check('full preview has consistent zero future recovery',seen_rest.preview and seen_rest.full and seen_rest.until_full==nil
    and seen_rest.next_hp==0 and seen_rest.next_mp==0 and seen_rest.hp_full_in==0 and seen_rest.mp_full_in==0);
check('preview leaves live recovery and settings alone',not resting.is_full() and resting.info(MOCK.now).next_tick==before.next_tick
    and MOCK.saved==saves);
check('unrelated pages do not collect the heavy Details snapshot',seen_details==nil);
window.select_tab('Details'); frame(0.3);
check('live Details receives model and timing evidence',seen_details and seen_details.modifiers and seen_details.resting
    and seen_details.tp and seen_details.attack);
window.select_tab('Timers');
local prior_details=seen_details; frame(0.3);
check('leaving Details stops rebuilding its snapshot',seen_details==prior_details);
command('preview attack full'); frame();
check('ready preview agrees with its bar and TP goal',seen_attack.preview and seen_attack.fill==1 and seen_attack.left==0
    and seen_attack.tp.tp==s.attack.tp_goal and seen_rest==nil);
command('preview attack waiting'); frame();
check('waiting preview leaves timing unknown',seen_attack.left==nil and seen_attack.tp.time_to_goal==nil);
command('preview resting blocked'); frame();
check('blocked preview uses the real disease explanation',seen_rest.why==8 and seen_rest.preview);
command('preview resting normal'); command('preview pause'); frame();
local paused = seen_rest.left; frame(1);
check('selected preview animation freezes',seen_rest.left==paused);
MOCK.player.status=0; command('preview auto'); frame();
local auto_left=seen_attack and seen_attack.left or seen_rest.left; frame(1);
check('automatic idle preview also freezes',auto_left==(seen_attack and seen_attack.left or seen_rest.left));
command('preview resume'); frame(1);
check('resume continues sample animation',auto_left~=(seen_attack and seen_attack.left or seen_rest.left));
window.set_open(false); frame();
check('closing settings removes all idle previews',seen_rest==nil and seen_attack==nil);
-- Profile loads and moves use the same history, leaving the settings window alone.
s.attack.x=130; s.resting.goal_value=222; profiles.save(s,'Workflow');
s.attack.x=410; s.resting.goal_value=333; s.window.x=76;
command('shadow on');
command('profile load Workflow');
check('profile load applies the chosen settings',s.attack.x==130 and s.resting.goal_value==222);
command('undo');
check('profile undo restores all prior settings but not the window',s.attack.x==410 and s.resting.goal_value==333 and s.window.x==76);
local first={attack={x=410,y=s.attack.y,width=s.attack.width,bar_height=s.attack.bar_height}};
local history=require('ui.history');
s.attack.x=500; history.record_patch(s,first,'Move timers'); first.attack.x=999; command('undo');
check('layout undo uses an independent original snapshot',s.attack.x==410 and not presets.can_undo());
attack.engage(MOCK.now,4,'key'); attack.on_round(MOCK.now+3,4,'key');
local due=attack.info(MOCK.now+4).next_in;
command('relearn attack');
check('relearn command preserves the scheduled countdown',attack.info(MOCK.now+4).next_in==due and attack.info(MOCK.now+4).samples==0);

-- A gear packet can land between modifier polls, before TP receives the next snapshot.
local tp, observer = require('core.tp'), require('core.stat_state');
attack.reset(); tp.forget(); tp.on_zone(); observer.reset();
MOCK.player.main_job, MOCK.player.sub_job, MOCK.player.sub_level = 1, 0, 0;
MOCK.items[16535] = { Delay=240, Skill=3 }; MOCK.player.equipment[0] = 16535;
s.attack.enabled, s.attack.show_tp, s.attack.show_tp_time = true, true, true;
MOCK.player.status = 0; frame(1);
MOCK.player.status = 1; frame(0.3);
local began = MOCK.now;
MOCK.player.tp = 0;
MOCK.fire('packet_in', MOCK.vitals_packet(1001,1000,0,0));
for i = 1, 4 do
    MOCK.now = began + 2.8 + (i - 1) * 4;
    MOCK.fire('packet_in', MOCK.action_packet(1001,1,0,0x01000200,{{message=1}}));
    MOCK.now, MOCK.player.tp = MOCK.now + 0.1, i * 64;
    MOCK.fire('packet_in', MOCK.vitals_packet(1001,1000,0,i * 64));
end
frame(0.02);
check('clean live rounds make the optional TP time available', seen_attack and seen_attack.tp.time_to_goal ~= nil);
local bytes = string.rep(string.char(0),8);
MOCK.fire('packet_in', {id=0x050,size=8,data=bytes,data_raw=bytes});
frame(0.02);
check('pending gear suppresses TP time before the next modifier poll', observer.info().transition
    and not tp.info(MOCK.now).transition and seen_attack and seen_attack.tp.time_to_goal == nil);
local errors={}; for _,line in ipairs(MOCK.printed) do if line:find('Drawing stopped',1,true) then errors[#errors+1]=line; end end
check('all controls render without errors or game commands',#errors==0 and #MOCK.commands==0,table.concat(errors,'|'));
out[#out+1]=fails==0 and 'ALL PASSED' or (fails..' FAILED'); return table.concat(out,'\n');
