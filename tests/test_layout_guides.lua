-- Guides only affect an unlocked Shift drag, and return the layout from before the whole gesture.
local hud,defaults,imgui=require('ui.hud'),require('ui.defaults'),require('imgui');
local s=defaults.make();
s.style.shared_spot,s.style.layout_guides,s.style.locked=false,true,false;
s.attack.x,s.attack.y,s.resting.x,s.resting.y=100,100,500,400;
s.enemy.enabled=false;
local out,fails,guides={},0,{};
local function check(name,ok,detail)
 out[#out+1]=(ok and 'ok   'or'FAIL ')..name..(detail and (' '..tostring(detail))or'');
 if not ok then fails=fails+1;end
end
local guide_list={AddLine=function(_,a,b)guides[#guides+1]={a[1],a[2],b[1],b[2]};end};
rawset(imgui,'GetForegroundDrawList',function()return guide_list;end);
rawset(imgui,'SetWindowPos',function(pos)
 MOCK.positions['##cadence_attack']={pos[1],pos[2]};
end);
local grip_id,active_grip,activated,mouse_x,mouse_y=nil,nil,false,0,0;
rawset(imgui,'InvisibleButton',function(id)grip_id=id;end);
rawset(imgui,'IsItemActivated',function()return activated and grip_id==active_grip;end);
rawset(imgui,'IsItemActive',function()return grip_id==active_grip;end);
rawset(imgui,'GetMousePos',function()return mouse_x,mouse_y;end);
local view={fill=.4,left=5,gained_hp=0,gained_mp=0,full=false,flash=0};
hud.refresh(s);
local function frame(moving,draw_rest)
 guides={};MOCK.imgui_calls,MOCK.record_imgui={},true;hud.set_movable(moving);
 hud.begin_frame();hud.draw_attack(.4,2,4,true,nil);
 if draw_rest~=false then hud.draw_resting(view);end
 local changed,before=hud.end_frame();MOCK.record_imgui=false;return changed,before;
end
local function moved(x,y,moving)
 MOCK.window_pos['##cadence_attack']={x,y};return frame(moving);
end
MOCK.mouse_down=false;frame(false);
MOCK.mouse_down=true;moved(4,105,true);
check('a dragged left edge snaps within6px',s.attack.x==0 and #guides>0,s.attack.x);
check('snapping keeps unrelated layout fields',s.resting.x==500 and s.attack.width==240);
MOCK.window_pos['##cadence_attack']=nil;frame(true);
check('the guide remains visible while an aligned drag is held',#guides>0);
moved(50,105,true);check('moving away releases the snap',s.attack.x==50,s.attack.x);
MOCK.mouse_down=false;MOCK.window_pos['##cadence_attack']=nil;
local changed,before=frame(true);
check('one undo snapshot starts before the whole drag',changed and before and before.attack.x==100
 and before.attack.y==100 and before.attack.width==240 and before.resting.x==500);
check('completed drag emits one save event',frame(true)==false);
MOCK.mouse_down=true;moved(508,120,true);
check('outside6px does not snap to another card',s.attack.x==508,s.attack.x);
moved(504,120,true);check('another card left edge is an alignment target',s.attack.x==500,s.attack.x);
local width=hud.element_size('attack');
moved(800-width/2+4,120,true);check('the card center snaps to screen center',s.attack.x+width/2==800,s.attack.x);
MOCK.mouse_down=false;MOCK.window_pos['##cadence_attack']=nil;frame(true);
s.style.layout_guides=false;MOCK.mouse_down=true;moved(504,120,true);
check('guides off preserves free dragging',s.attack.x==504 and #guides==0,s.attack.x);
MOCK.mouse_down=false;MOCK.window_pos['##cadence_attack']=nil;frame(true);
s.style.layout_guides=true;s.style.locked=true;MOCK.mouse_down=true;
local old_x=s.attack.x;moved(4,120,true);
check('lock prevents snapping and saved-position changes',s.attack.x==old_x and #guides==0,s.attack.x);
s.style.locked=false;moved(4,120,false);
check('ordinary gameplay stays click through with no guides',s.attack.x==old_x and #guides==0);
local saw_clickthrough=false;
for _,c in ipairs(MOCK.imgui_calls)do if c[1]=='Begin'and c[2]=='##cadence_attack'then
 saw_clickthrough=bit.band(c[4],ImGuiWindowFlags_NoInputs)~=0;end end
check('the real window flags still forbid gameplay input',saw_clickthrough);
MOCK.mouse_down=false;MOCK.window_pos['##cadence_attack']=nil;frame(false);

-- Resize the right edge toward the other card while keeping the starting x/y intact.
s.attack.x,s.attack.y,s.attack.width=100,100,240;hud.refresh(s);frame(true);
active_grip='##grip_width_attack';activated=true;mouse_x,mouse_y=362,110;MOCK.mouse_down=true;frame(true);
activated=false;mouse_x=497;frame(true);
check('resizing snaps the right edge to a visible card',s.attack.x+hud.element_size('attack')==500,s.attack.width);
active_grip=nil;MOCK.mouse_down=false;changed,before=frame(true);
check('resize undo contains its initial size and position',changed and before and before.attack.width==240
 and before.attack.x==100 and before.attack.y==100);
-- The vertical guide uses the whole drawn card, including its text and footer.
s.attack.x,s.attack.y,s.attack.height_scale=100,100,1.4;hud.refresh(s);
s.resting.y=s.attack.y+select(2,hud.element_size('attack'));
s.attack.height_scale=1;hud.refresh(s);frame(true);
local original_height=select(2,hud.element_size('attack'));
active_grip='##grip_height_attack';activated=true;mouse_x,mouse_y=120,100+original_height;
MOCK.mouse_down=true;frame(true);
activated=false;mouse_y=s.resting.y-4;frame(true);
check('vertical resize snaps the complete card bottom to another card',#guides>0
 and math.abs(s.attack.y+select(2,hud.element_size('attack'))-s.resting.y)<=1);
check('vertical guides preserve width and bar thickness',s.attack.width==378 and s.attack.bar_height==5);
active_grip=nil;MOCK.mouse_down=false;changed,before=frame(true);
check('vertical snap Undo keeps the starting height scale',changed and before and before.attack.height_scale==1);
s.resting.y=400;hud.refresh(s);frame(true);
-- A card absent for two frames is not a hidden alignment target.
frame(true,false);frame(true,false);MOCK.mouse_down=true;moved(504,140,true);
check('hidden cards are removed from alignment targets',s.attack.x==504,s.attack.x);
out[#out+1]=fails==0 and 'ALL OK'or(fails..' FAILED');return table.concat(out,'\n');
