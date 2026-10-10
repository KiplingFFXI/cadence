-- Additional estimates and previews stay readable without changing live timer state.
local defaults,hud,imgui=require('ui.defaults'),require('ui.hud'),require('imgui');
local s=defaults.make();
s.style.text_shadow,s.style.text_outline,s.style.shared_spot=false,false,false;
s.attack.x,s.attack.y,s.resting.x,s.resting.y=40,40,400,40;
s.attack.show_tp_time,s.attack.show_tp_hits=true,true;
s.resting.show_goal,s.resting.show_ticks,s.resting.show_next_gains=true,true,true;
local out,fails={},0;
local function check(name,ok,detail)
 out[#out+1]=(ok and 'ok   ' or 'FAIL ')..name..(detail and (' '..detail) or '');
 if not ok then fails=fails+1;end
end
local function capture(draw)
 hud.refresh(s);MOCK.imgui_calls,MOCK.record_imgui={},true;
 hud.begin_frame();draw();hud.end_frame();MOCK.record_imgui=false;
 local texts,positions={},{};for _,c in ipairs(MOCK.imgui_calls)do
  if c[1]=='dl:AddText'then texts[#texts+1],positions[c[6]]=c[6],c[4];end
 end
 return table.concat(texts,'|'),positions;
end
local tp={tp=640,goal=2000,rounds=7,hits=9,estimated=true,time_to_goal=65.1};
local function attack(preview)return capture(function()hud.draw_attack(.4,2.4,4,true,s.attack.show_tp and tp or nil,nil,nil,nil,preview);end);end
local text,pos=attack(false);
check('TP goal time always uses approximate rounded time',text:find('2000 TP in ~1:06',1,true),text);
check('TP time is separate from hits and rounds',pos['2000 TP in ~1:06'][2]>pos['9 successful hits est.'][2]);
local height=select(2,hud.element_size('attack'));tp.time_to_goal=nil;
text=attack(false);check('missing TP time leaves a stable optional row',not text:find('TP in ~1:',1,true)and select(2,hud.element_size('attack'))==height);
local view={fill=.3,left=7,gained_hp=24,gained_mp=31,next_hp=25,next_mp=34,next_estimated=true,
 until_full=90,hp_full_in=40,mp_full_in=90,has_mp=true,full=false,flash=0,
 full_meta={ticks=0,confidence='estimated'},
 goal={label='MP 300',seconds=22.1,ticks=2,confidence='estimated',reached=false}};
local function rest()return capture(function()hud.draw_resting(view);end);end
text,pos=rest();
check('partial recovery goal is distinct from full completion',text:find('MP 300 in ~23s',1,true)and text:find('full',1,true),text);
check('zero resting ticks describes passive completion clearly',text:find('full before next tick',1,true)and not text:find('0 ticks',1,true),text);
height=select(2,hud.element_size('resting'));view.goal.reached=true;
text=rest();check('a reached goal keeps its label',text:find('MP 300 reached',1,true),text);
view.goal.reached,view.goal.seconds=false,nil;
text=rest();check('unknown recovery target time is explicit and stable',text:find('MP 300 in --',1,true)and select(2,hud.element_size('resting'))==height,text);
view.why=8;text=rest();check('blocked goal hides its time without shrinking',not text:find('MP 300',1,true)and select(2,hud.element_size('resting'))==height,text);
view.why,view.waiting=nil,true;
text=rest();check('resting preview can display waiting',text:find('waiting',1,true),text);
s.attack.show_label,s.attack.show_value,s.attack.show_delay,s.attack.show_tp=false,false,false,false;
text=attack(true);check('preview remains visible when attack labels and values are hidden',text=='preview',text);
text=attack(false);check('live attack immediately drops the preview cue',not text:find('preview',1,true),text);
s.resting.show_label,s.resting.show_value,s.resting.show_gains,s.resting.show_until_full=false,false,false,false;
s.resting.show_goal,s.resting.show_ticks,s.resting.show_next_gains=false,false,false;
view.preview=true;text=rest();check('resting preview remains visible with text switches off',text=='preview',text);
s.enemy.show_label,s.enemy.show_value,s.enemy.show_name,s.enemy.show_delay,s.enemy.show_effects=false,false,false,false,false;
text=capture(function()hud.draw_enemy({fill=0,left=0,delay=4,learned=true,waiting=true,preview=true});end);
check('enemy preview remains visible with text switches off',text=='preview',text);
out[#out+1]=fails==0 and 'ALL OK'or(fails..' FAILED');return table.concat(out,'\n');
