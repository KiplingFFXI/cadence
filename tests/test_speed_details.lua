local delay = require('core.delay');
local out, failed = {}, 0;
local function check(name, yes)
    out[#out + 1] = (yes and 'ok   ' or 'FAIL ') .. name;
    if (not yes) then failed = failed + 1; end
end
local function near(a,b) return math.abs(a-b)<0.00001; end
local p = {main={id=1,delay=240,skill=3},main_job=1,main_level=75,sub_job=0,sub_level=0,buffs={},
    modifiers={haste_magic=5000,haste_ability=5000,haste_gear=3000,delay_known=true}};
local b = delay.breakdown(p);
check('details use the same modeled interval as the timer', b.modeled_interval == delay.estimate(p));
check('gear shows the raw bonus and amount removed by its cap', b.gear.raw==30 and b.gear.effective==25 and near(b.gear.capped,5));
check('magic and ability categories show their separate caps', b.magic.effective==43.75 and b.ability.effective==25);
check('combined haste explains its own cap after category caps', b.combined.raw==93.75 and near(b.combined.effective,93));
check('known complete inputs remain known', b.known and #b.unknown==0);
p.modifiers.haste_magic,p.modifiers.haste_ability,p.modifiers.haste_gear=0,0,-1500;
b=delay.breakdown(p);
check('negative gear haste survives the breakdown and lengthens delay', b.gear.raw==-15 and b.gear.effective==-15 and near(b.modeled_interval,4.6));
p.modifiers.delay_flat,p.modifiers.delay_percent=-500,-3;
b=delay.breakdown(p);
check('flat and percentage delay retain distinct units', b.delay_flat==-500 and b.delay_percent==-3 and b.modeled_interval==delay.estimate(p));
p.modifiers.delay_known=false;
p.modifiers.unknown_sources={{field='haste_magic',reason='March strength unavailable'}};
b=delay.breakdown(p);
check('unknown speed input stays explicitly estimated', not b.known and b.unknown[1]=='March strength unavailable');
p.modifiers.delay_known=true; p.modifiers.unknown_sources={}; p.modifiers.transition=true;
check('pending changes do not claim exact speed', not delay.breakdown(p).known);
p.modifiers={haste_magic=0,haste_ability=0,haste_gear=0,delay_known=true};
p.main.delay,p.main.skill,p.main_job=366,12,2; p.buffs[46]=true;
b=delay.breakdown(p);
check('Hundred Fists works with a staff', near(b.modeled_interval,1.525));
p.main.skill=11;
check('Hundred Fists works with a club', near(delay.estimate(p),1.525));
p.main.delay=239; b=delay.breakdown(p);
check('Hundred Fists rounds to server milliseconds', b.modeled_interval==0.995);
p.main.delay,p.main.skill=366,12;
local before_tp=delay.tp_delay(p); p.modifiers.haste_magic,p.modifiers.haste_gear,p.modifiers.delay_percent=3000,2000,-3;
b=delay.breakdown(p);
check('Hundred Fists bypasses haste and percentage delay in timing', b.hundred_fists and near(b.modeled_interval,1.525)
    and b.magic.effective==0 and b.gear.effective==0 and b.delay_percent==0 and b.raw_delay_percent==-3);
p.buffs[46]=nil;
check('Hundred Fists never changes the TP delay', delay.tp_delay(p)==math.floor(before_tp*0.97));
p.main.delay=600; p.buffs[46]=true;
b=delay.breakdown(p);
check('Hundred Fists explains its upper interval bound', b.modeled_interval==2 and b.before_limit==2.5 and b.limit_adjustment==-0.5);
p.buffs={}; p.main.delay=240; p.main.skill=9; p.sub={id=2,delay=240,skill=9};
p.modifiers={haste_magic=4000,haste_ability=2500,haste_gear=2500,dual_wield=30,delay_known=true};
b=delay.breakdown(p);
check('final reduction floor is shown after Dual Wield and haste', b.dual_wield==30 and b.minimum_interval==1.6 and b.modeled_interval==1.6 and b.limit_adjustment>0);
p.sub=nil; p.main.delay=480; p.main.skill=12;
p.modifiers={haste_magic=4375,haste_ability=2500,haste_gear=2500,delay_percent=20,delay_known=true};
b=delay.breakdown(p);
check('Phoenix haste cap applies before positive percentage delay and final weapon floor', b.modeled_interval==1.6
    and near(b.combined.effective,93) and b.minimum_interval==1.6 and b.before_limit<1.6);
p.modifiers=nil;
check('fallback estimates do not claim a complete modifier model', not delay.breakdown(p).known);
out[#out+1]=failed==0 and 'ALL PASSED' or (failed..' FAILED'); return table.concat(out,'\n');
