-- Find controls by their labels and help without changing their settings.
local imgui = require('imgui');
local search = {};
local query, page, pages = '', nil, {};
local color = { 1, 1, 1, 1 };
local match_query, match_words = nil, {};
local tokens, cached = {}, {};
local first, last = { 0, 0 }, { 0, 0 };
function search.matches(text, value)
    if (value == nil or value == '') then return true; end
    value = tostring(value):lower();
    if (value ~= match_query) then
        match_query, match_words = value, {};
        for word in value:gmatch('%S+') do match_words[#match_words + 1] = word; end
    end
    text = tostring(text or ''):lower();
    for _, word in ipairs(match_words) do if (not text:find(word, 1, true)) then return false; end end
    return true;
end
function search.query(value, ink)
    value = tostring(value or '');
    if (value ~= query) then
        query, pages, tokens, cached = value, {}, {}, {};
        for word in value:lower():gmatch('%S+') do tokens[#tokens + 1] = word; end
    end
    color = ink or color;
end
function search.finish_page()
    local current = page and pages[page];
    if (current == nil) then return; end
    current.total = current.seen;
    if (current.total == 0) then
        current.index, current.pending = 0, true;
    elseif (current.index < 1 or current.index > current.total) then
        current.index, current.pending = math.min(math.max(current.index, 1), current.total), true;
    end
end
function search.begin_page(name)
    search.finish_page();
    page = name;
    if (name == nil or #tokens == 0) then return; end
    pages[name] = pages[name] or { index = 1, total = 0, pending = true };
    local current = pages[name];
    current.seen = 0;
    current.x1, current.y1, current.x2, current.y2 = nil, nil, nil, nil;
end
function search.status(name)
    local current = pages[name or page];
    if (current == nil or #tokens == 0) then return 0, 0; end
    return math.min(current.index, current.total), current.total;
end
function search.active() return #tokens > 0; end
function search.step(delta, name)
    local current = pages[name or page];
    if (current == nil or current.total == 0 or delta == 0) then return false; end
    current.index = (current.index - 1 + (delta < 0 and -1 or 1)) % current.total + 1;
    current.pending = true;
    return true;
end
local function matches(label, tip)
    label, tip = tostring(label or ''), tostring(tip or '');
    local by_tip = cached[label];
    if (by_tip == nil) then by_tip = {}; cached[label] = by_tip; end
    if (by_tip[tip] == nil) then
        local words = (label:gsub('##.*$', '') .. ' ' .. tip):lower();
        local found = true;
        for _, word in ipairs(tokens) do
            if (not words:find(word, 1, true)) then found = false; break; end
        end
        by_tip[tip] = found;
    end
    return by_tip[tip];
end
function search.mark(label, tip)
    if (#tokens == 0 or page == nil or not matches(label, tip)) then return; end
    local current = pages[page];
    local x1, y1 = imgui.GetItemRectMin();
    local x2, y2 = imgui.GetItemRectMax();
    if (current.x1 == x1 and current.y1 == y1 and current.x2 == x2 and current.y2 == y2) then return; end
    current.x1, current.y1, current.x2, current.y2 = x1, y1, x2, y2;
    current.seen = current.seen + 1;
    first[1], first[2], last[1], last[2] = x1 - 2, y1 - 1, x2 + 2, y2 + 1;
    imgui.GetWindowDrawList():AddRect(first, last, imgui.GetColorU32(color), 2, 0, 2);
    if (current.pending and current.seen == current.index) then
        imgui.SetScrollHereY(0.3);
        current.pending = false;
    end
end
return search;
