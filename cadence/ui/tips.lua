-- Timer explanations use existing snapshots or fixed help. They never collect or calculate inputs.
local tips = {};
local NAMES = { attack = 'Auto attack and TP', resting = 'Resting', enemy = 'Enemy attack', recovery = 'Action recovery', enemycast = 'Enemy cast' };
local DISABLED = { [2] = 'Sleep', [7] = 'Petrification', [10] = 'Stun', [19] = 'Sleep',
    [28] = 'Terror', [159] = 'Penalty', [193] = 'Lullaby' };
local function plain(value) return tostring(value or 'unknown'):gsub('[%c]', ' '):gsub('_', ' '); end
local function amount(value) return type(value) == 'number' and ('%.2f'):format(value) or 'unknown'; end
function tips.text(key, details, preview)
    if (preview) then return NAMES[key] .. ' preview. These sample values do not describe your live timing.'; end
    if (key == 'recovery') then
        return 'Action recovery estimate\n'
            .. 'Tracks completed spells, weapon skills, job abilities, items and ranged attacks. Packet arrival is later than the server event.\n'
            .. 'It hides when the estimate ends. Individual recasts, silence and other action locks can still prevent casting.\n'
            .. 'Unavailable timing stays unknown briefly. That notice is not a recovery countdown.';
    end
    if (key == 'enemycast') then
        return 'Enemy cast estimate\n'
            .. 'The spell name comes from an observed cast start. The bar uses its base cast time; monster modifiers can change it.\n'
            .. 'Waiting means the estimate elapsed or its duration is unknown. The cast ends on an observed finish or interruption.\n'
            .. 'Old casts are discarded when evidence goes stale. This does not confirm that the spell completed.';
    end
    if (not details or not details[key]) then return NAMES[key] .. '. Waiting for timing evidence.'; end
    if (key == 'attack' and details.attack.reengage) then
        local retained = details.attack.reengage;
        local lines = { 'Re-engage estimate' };
        if (retained.unknown) then
            lines[#lines + 1] = 'Timing unknown. The last sampled attack delay could not be established.';
        elseif (retained.elapsed) then
            lines[#lines + 1] = 'Estimate elapsed. This does not confirm that you can engage.';
        else
            lines[#lines + 1] = 'Estimated remaining: ' .. amount(retained.left) .. ' s.';
        end
        lines[#lines + 1] = 'The server does not send the exact deadline. This conservative estimate can finish after the actual cooldown.';
        lines[#lines + 1] = 'A new engagement normally starts a separate three-second first-attack timer.';
        return table.concat(lines, '\n');
    end
    local entry, lines = details[key], { NAMES[key] };
    if (entry.source) then lines[#lines + 1] = 'In use: ' .. plain(entry.source) .. '.'; end
    if (entry.delay) then lines[#lines + 1] = 'Interval: ' .. amount(entry.delay) .. ' s.'; end
    lines[#lines + 1] = 'Accepted samples: ' .. tostring(entry.samples or entry.accepted or 0) .. '.';
    if (entry.sample_age) then lines[#lines + 1] = 'Last sample: ' .. amount(entry.sample_age) .. ' s ago.'; end
    if (entry.rejected and entry.rejected > 0) then lines[#lines + 1] = 'Samples not used: ' .. tostring(entry.rejected) .. '.'; end
    if (entry.disabled) then lines[#lines + 1] = 'Attacks are stopped: ' .. plain(DISABLED[entry.disabled] or entry.disabled) .. '.'; end
    if (entry.stalled) then lines[#lines + 1] = 'The attack is stalled. The displayed countdown cannot confirm when you will attack.'; end
    if (entry.overdue) then lines[#lines + 1] = 'The expected attack is overdue. Cadence is waiting for an actual attack.'; end
    if (entry.holding or entry.reason) then lines[#lines + 1] = 'Paused: ' .. plain(entry.holding or entry.reason) .. '.'; end
    if (entry.waiting) then lines[#lines + 1] = 'Waiting for the next observed attack. This is not a ready prediction.'; end
    if (key == 'attack') then
        local tp = details.tp;
        if (tp) then lines[#lines + 1] = 'TP per successful hit: ' .. amount(tp.per_hit) .. ' (' .. plain(tp.source) .. ').'; end
        lines[#lines + 1] = 'Hits count successful attacks. Rounds also depend on misses, extra attacks and other TP gains.';
    elseif (key == 'resting') then
        lines[#lines + 1] = 'Next resting tick: ' .. amount(entry.next_hp) .. ' HP, ' .. amount(entry.next_mp) .. ' MP.';
        lines[#lines + 1] = entry.pattern_known and 'Resting pattern observed.' or 'Resting pattern is still estimated.';
        if (entry.blocked) then lines[#lines + 1] = 'Recovery is currently blocked.'; end
        lines[#lines + 1] = 'Regen and Refresh run separately. They can finish recovery before a resting tick.';
    end
    if (entry.last_rejection) then lines[#lines + 1] = 'Last sample not used: ' .. plain(entry.last_rejection) .. '.'; end
    local model = details.modifiers;
    if (model and key ~= 'enemy') then
        if (model.evidence and model.evidence.age) then lines[#lines + 1] = 'Inputs read ' .. amount(model.evidence.age) .. ' s ago.'; end
        if (#(model.unknown or {}) > 0) then
            lines[#lines + 1] = 'Some inputs remain uncertain: ' .. plain(model.unknown[1]) .. '.';
        end
    end
    lines[#lines + 1] = 'Open Details for the full sources, bonuses and missing inputs.';
    return table.concat(lines, '\n');
end
return tips;
