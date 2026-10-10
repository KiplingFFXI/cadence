--[[
    The fit gate's overlap probe. fit_gate.py runs it with --exec before the first frame. It wraps the
    imgui calls the settings window draws with and keeps where each item lands in the window. Items in
    its tips, open lists and the profiles list don't count. When the window ends, it logs each item that
    runs into another one and each closed dropdown too narrow for the choice it shows, then a count.
    preview.py prints the last frame's lines on stderr as "log: ...".
]]

local imgui = require('imgui');
local theme = require('ui.theme');

local WINDOW = 'cadence##cadence_settings';

-- ImGui puts 4 between a dropdown and its name, and the theme pads the dropdown's text on the left.
local LABEL_GAP = 4;
local TEXT_PADDING = theme.FRAME_PADDING[1];

local inside = false; -- True while the settings window is being drawn.
local depth = 0;      -- How many tips, lists and popups deep the drawing is inside the window.
local items = {};
local problems = 0;

-- Inspect controls inside groups that start folded in the normal window.
local header = imgui.CollapsingHeader;
imgui.CollapsingHeader = function (label, ...)
    imgui.SetNextItemOpen(true, ImGuiCond_Always);
    return header(label, ...);
end

local function report(words)
    problems = problems + 1;
    PREVIEW_PY.log(words);
end

-- Keeps where the last item landed, named by `label`.
local function record(kind, label)
    if (not inside or depth > 0) then
        return;
    end
    local x0, y0 = imgui.GetItemRectMin();
    local x1, y1 = imgui.GetItemRectMax();
    items[#items + 1] = { kind = kind, label = tostring(label), x0 = x0, y0 = y0, x1 = x1, y1 = y1 };
end

-- Logs every pair of items that share more than half a pixel each way.
local function find_overlaps()
    for i = 1, #items do
        local a = items[i];
        for j = i + 1, #items do
            local b = items[j];
            local w = math.min(a.x1, b.x1) - math.max(a.x0, b.x0);
            local h = math.min(a.y1, b.y1) - math.max(a.y0, b.y0);
            if (w > 0.5 and h > 0.5) then
                report(('OVERLAP %s %q [%.0f..%.0f] with %s %q [%.0f..%.0f] at y=%.0f by %.1fx%.1f'):format(a.kind,
                    a.label, a.x0, a.x1, b.kind, b.label, b.x0, b.x1, a.y0, w, h));
            end
        end
    end
    PREVIEW_PY.log(('items=%d problems=%d'):format(#items, problems));
end

-- The items that take their label first.
for _, name in ipairs({ 'Checkbox', 'Button', 'SmallButton', 'SliderInt', 'SliderFloat', 'ColorEdit4',
    'ColorButton', 'TextUnformatted', 'TextDisabled', 'InputText', 'InputTextWithHint' }) do
    local draw = imgui[name];
    imgui[name] = function (label, ...)
        local results = { draw(label, ...) };
        record(name, label);
        return unpack(results);
    end
end

local options_opened = {};
local small_button = imgui.SmallButton;
imgui.SmallButton = function (label, ...)
    local clicked = small_button(label, ...);
    if (label:find('^Options##readout_') and not options_opened[label]) then
        options_opened[label] = true;
        return true;
    end
    return clicked;
end

-- TextColored takes its color first and its words second.
local text_colored = imgui.TextColored;
imgui.TextColored = function (color, words, ...)
    text_colored(color, words, ...);
    record('TextColored', words);
end

local begin, finish = imgui.Begin, imgui.End;
imgui.Begin = function (name, ...)
    local results = { begin(name, ...) };
    if (name == WINDOW) then
        inside, depth, items, problems = true, 0, {}, 0;
    elseif (inside) then
        depth = depth + 1;
    end
    return unpack(results);
end
imgui.End = function (...)
    if (inside and depth == 0) then
        inside = false;
        find_overlaps();
    elseif (inside) then
        depth = depth - 1;
    end
    return finish(...);
end

-- cadence ends every tip it begins.
local begin_tip, end_tip = imgui.BeginTooltip, imgui.EndTooltip;
imgui.BeginTooltip = function (...)
    if (inside) then
        depth = depth + 1;
    end
    return begin_tip(...);
end
imgui.EndTooltip = function (...)
    if (inside) then
        depth = depth - 1;
    end
    return end_tip(...);
end

-- The profiles list counts as one item. What's in it doesn't.
local begin_list, end_list = imgui.BeginListBox, imgui.EndListBox;
imgui.BeginListBox = function (...)
    local shown = begin_list(...);
    if (shown and inside) then
        depth = depth + 1;
    end
    return shown;
end
imgui.EndListBox = function (...)
    if (inside) then
        depth = depth - 1;
    end
    end_list(...);
    record('ListBox', '##list');
end

-- The page scrolls under fixed navigation. Check its controls normally; the nested Details
-- area is clipped separately, so only its visible rectangle can overlap surrounding controls.
local begin_child, end_child = imgui.BeginChild, imgui.EndChild;
local child_depths = {};
imgui.BeginChild = function (id, ...)
    local shown = begin_child(id, ...);
    local clipped = inside and not tostring(id):find('##page_', 1, true);
    child_depths[#child_depths + 1] = clipped;
    if (clipped) then depth = depth + 1; end
    return shown;
end
imgui.EndChild = function (...)
    local clipped = table.remove(child_depths);
    if (clipped) then depth = depth - 1; end
    end_child(...);
    if (clipped) then record('Child', '##details'); end
end

-- A closed dropdown is an item. Its text runs from its left padding to its arrow, which is as wide as the
-- dropdown is tall, and ImGui cuts off whatever doesn't fit.
local begin_combo, end_combo = imgui.BeginCombo, imgui.EndCombo;
imgui.BeginCombo = function (label, preview, ...)
    local open = begin_combo(label, preview, ...);
    if (open) then
        if (inside) then
            depth = depth + 1;
        end
        return open;
    end
    record('Combo', label);
    if (inside and depth == 0) then
        local x0 = imgui.GetItemRectMin();
        local x1 = imgui.GetItemRectMax();
        local name = tostring(label):gsub('##.*$', '');
        local name_width = imgui.CalcTextSize(name);
        local frame = (x1 - x0) - (name_width > 0 and (name_width + LABEL_GAP) or 0);
        local room = frame - imgui.GetFrameHeight() - TEXT_PADDING;
        local needs = imgui.CalcTextSize(preview);
        if (needs > room + 0.5) then
            report(('CLIPPED dropdown %q shows %q, needs %.1f and has %.1f'):format(label, preview, needs, room));
        end
    end
    return open;
end
imgui.EndCombo = function (...)
    if (inside) then
        depth = depth - 1;
    end
    return end_combo(...);
end
