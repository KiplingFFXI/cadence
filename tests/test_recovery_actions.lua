-- Direct recovery packets must not teach passive gains, including near a normal effect pass.
local out, failed = {}, 0;
local function check(name, yes)
    out[#out+1]=(yes and 'ok   ' or 'FAIL ')..name;
    if (not yes) then failed=failed+1; end
end
MOCK.player.main_job,MOCK.player.main_level,MOCK.player.sub_job,MOCK.player.sub_level=1,1,0,0;
MOCK.player.hp_max,MOCK.player.mp_max,MOCK.player.status=1000,500,33;
MOCK.player.buffs={}; MOCK.player.equipment={};
dofile(ADDON_DIR..'/cadence.lua'); MOCK.fire('load');
local resting=require('core.resting');
local function vitals(at,hp,mp)
    MOCK.now=at; MOCK.player.hp,MOCK.player.mp=hp,mp;
    MOCK.fire('packet_in',MOCK.vitals_packet(1001,hp,mp,0));
end
local function sit()
    resting.reset(); resting.on_buffs(0,{}); vitals(0,100,100); resting.start(0);
end
local function action(at,message,target)
    MOCK.now=at;
    MOCK.fire('packet_in',MOCK.action_packet(1002,4,1,target or 1001,{{message=message,damage=90}}));
end
sit(); action(3,7); vitals(3.1,190,100); action(6,7); vitals(6.1,280,100); resting.update(6.7);
check('normal Cure action packets exclude false Regen even three seconds apart',resting.info(6.7).regen_hp==0);
check('a direct cure does not move the resting countdown',select(2,resting.progress(6.7))>10 and resting.info(6.7).accepted==0);
sit(); action(3,25); vitals(3.1,100,190); action(6,25); vitals(6.1,100,280); resting.update(6.7);
check('direct MP restoration does not become Refresh',resting.info(6.7).regen_mp==0);
sit();
for i=1,2 do
    MOCK.now=i*3;
    MOCK.fire('packet_in',MOCK.message_packet(1002,1001,90,0,24,0));
    vitals(i*3+0.1,100+i*90,100);
end
resting.update(6.7);
check('battle-message heals are excluded too',resting.info(6.7).regen_hp==0);
sit(); vitals(3,190,100); action(3.1,7); vitals(6,280,100); action(6.1,7); resting.update(6.7);
check('late cure actions cancel staged passive learning',resting.info(6.7).regen_hp==0);
sit();
for i=1,2 do
    MOCK.now=i*3;
    MOCK.fire('packet_in',MOCK.action_packet(0x01000200,1,0,1001,{
        {message=1,damage=0,add_effect=true,added_message=162,added_param=10}}));
    vitals(i*3+0.1,100,100-i*10);
end
resting.update(6.7);
check('additional MP drain is excluded from passive MP learning',resting.info(6.7).regen_mp==0);
local direct=resting.on_direct_change;
local observed;
resting.on_direct_change=function(_,hp,mp,tp) observed={hp,mp,tp}; end;
for _,case in ipairs({
    {161,1002,1001,1}, {162,1002,1001,2}, {165,1001,1002,3},
    {152,1001,1002,2}, {167,1001,1002,1}, {384,1002,1001,1},
}) do
    observed=nil;
    MOCK.fire('packet_in',MOCK.action_packet(case[2],1,0,case[3],{
        {message=0,damage=0,add_effect=true,added_message=case[1],added_param=10}}));
    check('additional resource message '..case[1]..' excludes the right resource',observed and observed[case[4]]);
end
for _,case in ipairs({
    {44,1001,1002,1}, {132,1002,1001,1}, {373,1002,1001,1},
    {383,1001,1002,1}, {162,1001,1002,2},
}) do
    observed=nil;
    MOCK.fire('packet_in',MOCK.action_packet(case[2],1,0,case[3],{
        {message=0,damage=0,reaction=true,reaction_message=case[1],reaction_param=10}}));
    check('reaction resource message '..case[1]..' excludes the right resource',observed and observed[case[4]]);
end
observed=nil;
MOCK.fire('packet_in',MOCK.action_packet(1002,1,0,1003,{
    {message=0,damage=0,add_effect=true,added_message=162,added_param=10,reaction=true}}));
check('other players secondary results leave your recovery alone',observed==nil);
resting.on_direct_change=direct;
local errors=0; for _,line in ipairs(MOCK.printed) do if line:find('Drawing stopped',1,true) then errors=errors+1; end end
check('recovery hooks send no commands or drawing errors',errors==0 and #MOCK.commands==0);
out[#out+1]=failed==0 and 'ALL PASSED' or (failed..' FAILED'); return table.concat(out,'\n');
