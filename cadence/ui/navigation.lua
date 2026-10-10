-- The selected page scrolls below these wrapping tab buttons.
local imgui = require('imgui');
local navigation = {};
navigation.TAB_NAMES = { 'Timers', 'Enemy', 'Appearance', 'Preview', 'Details', 'Profiles' };
local active = 'Timers';
local pending_reveal;
local layout, from, to = {}, { 0, 0 }, { 0, 0 };
local NAMES = { timers = 'Timers', enemy = 'Enemy', look = 'Appearance', appearance = 'Appearance', window = 'Appearance',
    windowcolors = 'Appearance', preview = 'Preview', details = 'Details', profiles = 'Profiles' };
function navigation.canonical(name)
    return NAMES[tostring(name or ''):lower():gsub('[%s_-]+', '')];
end
function navigation.visible(tabs, name)
    name = navigation.canonical(name) or name;
    return name == 'Appearance' or type(tabs) ~= 'table' or tabs[name] ~= false;
end
function navigation.normalize(tabs)
    local result = {};
    for _, name in ipairs(navigation.TAB_NAMES) do result[name] = navigation.visible(tabs, name); end
    return result;
end
function navigation.set_visible(tabs, name, shown)
    name = navigation.canonical(name);
    if (type(tabs) ~= 'table' or name == nil) then return false; end
    shown = name == 'Appearance' or shown ~= false;
    local changed = tabs[name] ~= shown;
    tabs[name] = shown;
    return changed;
end
function navigation.restore(tabs)
    local changed = false;
    for _, name in ipairs(navigation.TAB_NAMES) do
        if (navigation.set_visible(tabs, name, true)) then changed = true; end
    end
    return changed;
end
function navigation.select(name, tabs)
    local selected = navigation.canonical(name);
    if (selected == nil) then return false; end
    active = selected;
    pending_reveal = tabs == nil and selected or nil;
    return true, tabs ~= nil and navigation.set_visible(tabs, selected, true) or false;
end
function navigation.current() return active; end
function navigation.rows(labels, available, measure, padding, gap)
    local rows, row, used = {}, {}, 0;
    available, padding, gap = math.max(1, available), padding or 10, gap or 8;
    for _, name in ipairs(labels) do
        local width = math.min(available, math.ceil(measure(name) + padding));
        if (#row > 0 and used + gap + width > available) then rows[#rows + 1], row, used = row, {}, 0; end
        used = used + (#row > 0 and gap or 0) + width;
        row[#row + 1] = { name = name, width = width };
    end
    if (#row > 0) then rows[#rows + 1] = row; end
    return rows;
end
local function visibility_key(tabs)
    local key = 0;
    for index, name in ipairs(navigation.TAB_NAMES) do
        if (navigation.visible(tabs, name)) then key = key + 2 ^ index; end
    end
    return key;
end
local function prepare(tabs, matches, visibility)
    local width, face, size = imgui.GetContentRegionAvail(), imgui.GetFont(), imgui.GetFontSize();
    local key = visibility_key(visibility);
    if (layout.tabs ~= tabs or layout.matches ~= matches or layout.width ~= width or layout.face ~= face or layout.size ~= size
        or layout.visibility ~= key) then
        local names, pages, hidden = {}, {}, {};
        for _, tab in ipairs(tabs) do
            if (matches[tab[1]]) then
                if (navigation.visible(visibility, tab[1])) then names[#names + 1], pages[tab[1]] = tab[1], tab;
                else hidden[#hidden + 1] = tab[1]; end
            end
        end
        local rows = navigation.rows(names, width, imgui.CalcTextSize, 16, 8);
        for _, row in ipairs(rows) do for _, entry in ipairs(row) do
            entry.id, entry.size = entry.name .. '##cadence_tab', { entry.width, 0 };
        end end
        layout = { tabs = tabs, matches = matches, width = width, face = face, size = size, names = names, pages = pages, rows = rows,
            visibility = key, hidden = hidden, reveal = ('Show hidden matches (%d)##reveal_tabs'):format(#hidden) };
    end
end
function navigation.draw(tabs, look, matches, draw_page, visibility, options)
    local changed = false;
    if (pending_reveal ~= nil) then
        changed = navigation.set_visible(visibility, pending_reveal, true);
        pending_reveal = nil;
    end
    prepare(tabs, matches, visibility);
    if (options and options.searching and #layout.hidden > 0) then
        if (imgui.Button(layout.reveal)) then
            active = layout.hidden[1];
            for _, name in ipairs(layout.hidden) do
                if (navigation.set_visible(visibility, name, true)) then changed = true; end
            end
            prepare(tabs, matches, visibility);
        end
        if (imgui.IsItemHovered()) then
            imgui.BeginTooltip();
            imgui.PushTextWrapPos(360);
            imgui.TextUnformatted('Shows the hidden tabs matching this search. Their timer settings stay as they are.');
            imgui.PopTextWrapPos();
            imgui.EndTooltip();
        end
    end
    local names, pages, rows = layout.names, layout.pages, layout.rows;
    if (#names == 0) then imgui.TextUnformatted('No matching settings. Clear the search or show hidden matches.'); return changed; end
    if (pages[active] == nil) then active = names[1]; end
    local focused = imgui.IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows);
    for _, row in ipairs(rows) do
        for index, entry in ipairs(row) do
            if (index > 1) then imgui.SameLine(0, 8); end
            local selected = entry.name == active;
            local ink = focused and (selected and look.open_tab or look.tabs)
                or (selected and look.open_tab_unfocused or look.tabs_unfocused);
            imgui.PushStyleColor(ImGuiCol_Button, ink);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, look.tabs_hovered);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, look.open_tab);
            if (imgui.Button(entry.id, entry.size)) then active = entry.name; end
            imgui.PopStyleColor(3);
            if (entry.name == active) then
                local x1, y1 = imgui.GetItemRectMin();
                local x2 = imgui.GetItemRectMax();
                from[1], from[2], to[1], to[2] = x1, y1, x2, y1;
                imgui.GetWindowDrawList():AddLine(from, to,
                    imgui.GetColorU32(focused and look.open_tab_line or look.open_tab_line_unfocused), 2);
            end
        end
    end
    imgui.Separator();
    draw_page(pages[active]);
    return changed;
end
return navigation;
