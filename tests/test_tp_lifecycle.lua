-- Character changes drop unfinished TP packets and the previous character's quiet periods.
local tp = require('core.tp');
local out, fails = {}, 0;
local function check(name, condition)
    out[#out + 1] = (condition and 'ok   ' or 'FAIL ') .. name;
    if (not condition) then fails = fails + 1; end
end
local loadout = { main = { id = 1, delay = 240, skill = 3 }, main_job = 1, main_level = 75,
    sub_job = 0, sub_level = 0, buffs = {}, modifiers = { store_tp = 0, tp_known = true,
        tp_key = 'plain', rounds_key = 'plain' } };
local function begin(now)
    tp.forget(); tp.on_engage(loadout); tp.on_vitals(now, 0);
end

begin(0);
tp.on_round(4, 1, false, true, loadout);
tp.forget();
tp.on_vitals(4.1, 64);
check('a character change discards the unfinished round', tp.info(4.1).samples == 0 and tp.per_hit() == nil);

begin(10);
tp.on_vitals(11, 20);
tp.forget(); tp.on_engage(loadout); tp.on_vitals(11.1, 0);
tp.on_round(12, 1, false, true, loadout); tp.on_vitals(12.1, 64);
check('a previous character cannot delay clean TP learning', tp.info(12.1).samples == 1 and select(2, tp.per_hit()));

begin(20);
tp.on_own_action(20.1, 63);
tp.forget(); tp.on_engage(loadout); tp.on_vitals(21, 0);
tp.on_round(25, 1, false, true, loadout); tp.on_vitals(25.1, 64);
tp.on_stir(); tp.on_vitals(26, 85);
tp.on_round(29, 1, false, true, loadout); tp.on_vitals(29.1, 149);
check('the previous character\'s Meditate does not suppress outside TP', tp.other_per_round() == 7);

begin(50);
for i = 1, 3 do
    tp.on_round(50 + i * 4, 1, false, true, loadout);
    tp.on_vitals(50.1 + i * 4, i * 64);
end
tp.on_stir(); tp.on_vitals(63, 213);
tp.on_round(66, 1, false, true, loadout); tp.on_vitals(66.1, 277);
check('the old zone has hit-rate and outside-TP evidence', tp.info(67).recent_rounds == 4 and tp.other_per_round() == 7);
tp.on_zone();
check('zoning keeps learned TP per hit', tp.per_hit() == 64 and select(2, tp.per_hit()));
check('zoning drops the previous fight hit-rate and outside TP', tp.info(67).recent_rounds == 0 and tp.other_per_round() == 0);

out[#out + 1] = fails == 0 and 'ALL PASSED' or (fails .. ' FAILED');
return table.concat(out, '\n');
