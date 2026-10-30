-- Packet evidence ends casts; a base-duration estimate never reports a spell completed.
local out, failed = {}, 0;
local function check(name, ok, detail)
    out[#out + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -> ' .. tostring(detail)) or '');
    if (not ok) then failed = failed + 1; end
end
local cast, view = require('core.enemy_cast'), {};
check('a valid start is accepted', cast.on_start(10, 101, 144, 'Fire', 2, 'first'));
check('the base duration is explicitly estimated', cast.progress(10.5, 101, view) and view.spell == 'Fire'
    and view.left == 1.5 and view.fill == 0.25 and view.estimated and not view.waiting);
check('an expired estimate keeps the observed cast and waits', cast.progress(13, 101, view)
    and view.spell == 'Fire' and view.waiting and view.left == 0 and view.fill == 1);
check('a matching finish ends the cast', cast.on_end(101, 144, 'finish-first') and not cast.progress(13.1, 101, view));
check('a repeated start does not resurrect a finished cast', not cast.on_start(14, 101, 144, 'Fire', 2, 'first')
    and not cast.progress(14, 101, view));
cast.on_start(14, 101, 144, 'Fire', 2, 'same-spell-again');
check('a repeated old finish cannot clear a newer cast of the same spell', not cast.on_end(101, 144, 'finish-first')
    and cast.progress(14.5, 101, view) and view.left == 1.5);
cast.on_start(15, 101, 145, 'Fire II', 4, 'second');
check('a stale finish for another spell cannot clear the current one', not cast.on_end(101, 144) and cast.progress(16, 101, view));
check('an interrupt can clear the cast without a spell id', cast.on_end(101) and not cast.progress(16, 101, view));
cast.on_start(20, 101, 999, nil, nil);
check('missing client resources show an unknown timer with an identified spell', cast.progress(21, 101, view)
    and view.spell == 'Spell 999' and view.duration == nil and view.left == nil and view.waiting and view.fill == 0);
cast.on_start(21, 102, 144, 'Fire', 2);
check('switching targets does not lose another monster cast', cast.progress(22, 101, view) and cast.progress(22, 102, view));
cast.forget(102);
check('despawn invalidation clears only that actor', not cast.progress(22, 102, view) and cast.progress(22, 101, view));
check('a missing finish has a bounded stale lifetime', cast.progress(49.99, 101, view) and not cast.progress(50, 101, view));
cast.on_start(60, 101, 144, 'Fire', 100);
check('a long known cast retains a reasonable finish grace', cast.progress(173, 101, view) and view.waiting
    and not cast.progress(175, 101, view));
cast.on_start(180, 101, 144, 'Fire', 2);
check('out-of-order starts do not replace the active spell', not cast.on_start(179, 101, 145, 'Fire II', 4)
    and cast.progress(181, 101, view) and view.spell_id == 144);
check('a backwards clock clears stale timing', not cast.progress(179, 101, view) and not cast.progress(181, 101, view));
for _, duration in ipairs({ 0, -1, math.huge, 0 / 0, 121 }) do
    cast.on_start(200, 101, 144, 'Fire', duration);
    check('invalid duration is unknown: ' .. tostring(duration), cast.progress(200.1, 101, view) and view.left == nil and view.waiting);
end
check('malformed events are rejected', not cast.on_start(0 / 0, 101, 144, 'Fire', 2)
    and not cast.on_start(200, 0, 144, 'Fire', 2) and not cast.on_start(200, 101, 0, 'Fire', 2));
cast.reset();
for id = 1, 65 do cast.on_start(id / 100, id, 144, 'Fire', 2); end
check('the clock cap evicts the oldest actor', not cast.progress(1, 1, view) and cast.progress(1, 65, view));
cast.sweep(40);
check('sweep clears expired off-target casts', not cast.progress(40, 65, view));
cast.on_start(100, 1, 144, 'Fire', 2);
if (jit) then jit.off(); end
for _ = 1, 20 do cast.progress(100.5, 1, view); end
collectgarbage('collect'); collectgarbage('stop');
local allocated = collectgarbage('count');
for _ = 1, 100 do cast.progress(100.5, 1, view); end
local bytes = (collectgarbage('count') - allocated) * 1024 / 100;
collectgarbage('restart');
check('progress reuses the supplied view without frame allocations', bytes == 0, bytes);
cast.reset();
check('zone reset forgets casts and duplicate history', not cast.progress(100.5, 1, view)
    and cast.on_start(101, 101, 144, 'Fire', 2, 'first'));
out[#out + 1] = failed == 0 and 'ALL PASSED' or (failed .. ' FAILED');
return table.concat(out, '\n');
