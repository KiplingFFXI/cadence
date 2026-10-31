-- A new zone cannot inherit full HP/MP or a blocking effect before its first vitals packet.
local out, failed = {}, 0;
local function check(name, ok)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name;
    if (not ok) then failed = failed + 1; end
end
local resting = require('core.resting');
resting.on_vitals(0, 300, 100, 0, 300, 100);
resting.start(0);
resting.on_buffs(1, { [8] = true });
check('the previous rest has full vitals and a blocking effect', resting.is_full() and resting.blocked_by() == 8);
resting.reset();
check('reset forgets fullness along with the old vitals and blocking effect',
    not resting.is_active() and not resting.knows_vitals() and not resting.is_full() and resting.blocked_by() == nil);
resting.on_max_vitals(2, 900, 300);
check('maximums alone cannot restore known or full vitals after reset', not resting.knows_vitals() and not resting.is_full());
resting.start(2, true);
local _, left, _, _, _, full, unknown = resting.progress(2);
check('joining the next rest before vitals is observing rather than full', left == nil and unknown and not full);
check('unknown current vitals have no full-recovery or goal forecast', resting.until_each_full(2) == nil
    and resting.until_full(2) == nil and resting.goal_progress(2, 'both', 'percent', 100) == nil);
resting.on_vitals(3, 100, 25, 0, 900, 300);
check('the new current vitals establish their own missing recovery', resting.knows_vitals() and not resting.is_full());
resting.on_vitals(4, 900, 300, 0, 900, 300);
check('full is known only after the new character vitals establish it', resting.is_full());

-- Exercise the render visibility decision, not only the core accessor.
resting.reset();
dofile(ADDON_DIR .. '/cadence.lua'); MOCK.fire('load');
local hud, sound = require('ui.hud'), require('ui.sound');
local s = MOCK.settings.current;
s.resting.hide_when_full, s.resting.show_each_full, s.resting.sound = true, true, true;
MOCK.player.status, MOCK.player.hp_max, MOCK.player.mp_max = 33, 300, 100;
local shown, plays = nil, 0;
hud.draw_resting = function(view)
    shown = { full = view.full, unknown = view.phase_unknown, hp = view.hp_full_in, mp = view.mp_full_in };
end;
sound.play = function() plays = plays + 1; return true; end;
MOCK.fire('packet_in', MOCK.vitals_packet(MOCK.player.server_id, 300, 100, 0));
MOCK.frame(0.25);
check('full recovery hides the previous resting card', resting.is_full() and shown == nil);
MOCK.fire('packet_in', MOCK.zone_packet(MOCK.player.server_id));
shown = nil;
MOCK.frame(0.25);
check('a post-zone rest stays visible while its current vitals are unknown', shown ~= nil
    and not shown.full and shown.unknown and shown.hp == nil and shown.mp == nil and not resting.knows_vitals());
check('reset and observing cannot play the full-recovery sound', plays == 0);
local error_seen = false;
for _, line in ipairs(MOCK.printed) do error_seen = error_seen or line:find('Drawing stopped', 1, true) ~= nil; end
check('resting reset adds no drawing errors or game commands', not error_seen and #MOCK.commands == 0);
out[#out + 1] = failed == 0 and 'ALL PASSED' or failed .. ' FAILED';
return table.concat(out, '\n');
