-- Static samples use your display choices without reading or changing live timers.
local imgui = require('imgui');
local theme = require('ui.theme');
local hud = require('ui.hud');
local chat_colors = require('ui.chat_colors');
local preview = {};
local keys = { 'attack', 'resting', 'enemy' };
local labels = { attack = 'AUTO ATTACK', resting = 'RESTING', enemy = 'ENEMY ATTACK' };
local blocks = { attack = 'casting', resting = 'diseased', enemy = 'casting' };
local cache = {};
local point, edge, space = { 0, 0 }, { 0, 0 }, { 0, 0 };
local black = theme.u32(theme.hex('000000', 0.7));
local offsets = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } };
local chat_ink = {};
for _, entry in ipairs(chat_colors.PALETTE) do chat_ink[entry.code] = theme.hex(entry.swatch); end

local function pos(out, x, y) out[1], out[2] = x, y; return out; end
local function text(list, face, style, x, y, size, ink, words)
    if (style.text_shadow) then list:AddText(face, size, pos(point, x + 1, y + 1), black, words); end
    if (style.text_outline) then
        local outline = theme.u32(style.outline_color);
        local edge_size = math.max(1, math.floor(size / 16 + 0.5));
        for _, offset in ipairs(offsets) do
            list:AddText(face, size, pos(point, x + offset[1] * edge_size, y + offset[2] * edge_size), outline, words);
        end
    end
    list:AddText(face, size, pos(point, x, y), theme.u32(ink), words);
end
local function build(settings, state)
    local rows = {};
    for _, key in ipairs(keys) do
        local timer, lines = settings[key], {};
        if (timer.enabled) then
            if (key == 'attack') then
                if (timer.show_delay) then lines[#lines + 1] = 'Delay 3.8s'; end
                if (timer.show_tp) then
                    lines[#lines + 1] = ('640 TP / %d%s'):format(timer.tp_goal, timer.show_tp_rounds and '  ~2 rounds' or '');
                    if (timer.show_tp_hits) then lines[#lines + 1] = '5 successful hits'; end
                    if (timer.show_tp_time) then lines[#lines + 1] = '~7.6s to TP goal'; end
                end
                if (state == 'blocked' and timer.show_why and not timer.show_value) then lines[#lines + 1] = blocks[key]; end
                if (state == 'waiting' and timer.show_reason) then lines[#lines + 1] = 'too far'; end
            elseif (key == 'resting') then
                if (timer.show_gains and state ~= 'blocked') then lines[#lines + 1] = '+24 HP  +31 MP'; end
                if (timer.show_next_gains and state ~= 'blocked') then lines[#lines + 1] = 'Next: +25 HP  +32 MP est.'; end
                if (timer.show_until_full and state ~= 'blocked') then lines[#lines + 1] = state == 'full' and 'Full HP/MP' or '~28s until full'; end
                if (timer.show_each_full and state ~= 'blocked' and state ~= 'full') then lines[#lines + 1] = 'HP ~16s  MP ~28s'; end
                if (timer.show_ticks and state ~= 'blocked' and state ~= 'full') then lines[#lines + 1] = '~3 ticks until full'; end
                if (timer.show_goal and state ~= 'blocked' and state ~= 'full') then
                    local target = timer.goal_mode == 'percent' and (timer.goal_value .. '%') or tostring(timer.goal_value);
                    lines[#lines + 1] = timer.goal_stat:upper() .. ' ' .. target .. (timer.goal_stat == 'hp' and '  ~16s' or '  ~28s');
                end
                if (state == 'blocked' and timer.show_why and not timer.show_value) then lines[#lines + 1] = blocks[key]; end
            else
                if (timer.show_name) then lines[#lines + 1] = 'Sample enemy'; end
                if (timer.show_delay) then lines[#lines + 1] = 'Attack speed ~4.2s'; end
                if (timer.show_effects) then lines[#lines + 1] = 'Slow'; end
                if (state == 'blocked' and timer.show_holds) then lines[#lines + 1] = blocks[key]; end
            end
            rows[#rows + 1] = { key = key, lines = lines };
        end
    end
    return rows;
end

function preview.draw(settings, state, edited)
    state = state or 'normal';
    if (cache.settings ~= settings or cache.state ~= state or edited) then
        cache.settings, cache.state, cache.rows = settings, state, build(settings, state);
    end
    local style, face = settings.style, hud.preview_font and hud.preview_font() or imgui.GetFont();
    local available, used = imgui.GetContentRegionAvail(), 0;
    if (#cache.rows == 0) then imgui.TextUnformatted('All timers are off in this sample.'); end
    for _, row in ipairs(cache.rows) do
        local timer = settings[row.key];
        local height_scale = timer.height_scale or 1;
        local text_scale = style.scale * height_scale;
        local size = style.font_size * text_scale;
        local label_size = (style.label_size > 0 and style.label_size or style.font_size) * text_scale;
        local detail_size = (style.detail_size > 0 and style.detail_size or style.font_size) * text_scale;
        local width = math.max(20, math.min(timer.width * style.scale, available));
        if (used > 0 and used + 8 + width <= available) then
            imgui.SameLine(0, 8);
            used = used + 8;
        elseif (used > 0) then
            imgui.Spacing();
            used = 0;
        end
        local bar = timer.numbers_only and 0 or math.max(1, timer.bar_height * text_scale);
        local has_label = style.show_labels and timer.show_label;
        local top_height = math.max(has_label and label_size or 0, timer.show_value and size or 0);
        local height = 16 * height_scale + top_height + (bar > 0 and bar + 6 * height_scale or 0)
            + #row.lines * (detail_size + 4 * height_scale);
        local x, y = imgui.GetCursorScreenPos(); x, y = x or 0, y or 0;
        local list = imgui.GetWindowDrawList();
        list:PushClipRect(pos(point, x, y), pos(edge, x + width, y + height), true);
        local rounding = style.rounding * style.scale;
        if (style.panel) then list:AddRectFilled(pos(point, x, y), pos(edge, x + width, y + height), theme.u32(style.panel_color), rounding); end
        if (style.border) then list:AddRect(pos(point, x, y), pos(edge, x + width, y + height), theme.u32(style.border_color), rounding); end
        if (style.accent) then list:AddRectFilled(pos(point, x, y), pos(edge, x + 3, y + height), theme.u32(style.accent_color)); end
        local left, right, top = x + 8, x + width - 8, y + 8 * height_scale;
        local value, ink = '2.4', style.value_color;
        if (state == 'full') then
            value = row.key == 'resting' and 'full' or 'ready';
            ink = timer.ready_color or timer.full_color;
        elseif (state == 'waiting') then value = 'waiting';
        elseif (state == 'blocked') then value = blocks[row.key]; end
        local value_x = right;
        if (timer.show_value) then
            imgui.PushFont(face, size);
            local value_width = imgui.CalcTextSize(value);
            imgui.PopFont();
            value_x = math.max(left, right - value_width);
            text(list, face, style, value_x, top, size, ink, value);
        end
        if (has_label) then
            local label = timer.label_text ~= '' and timer.label_text or labels[row.key];
            list:PushClipRect(pos(point, left, top), pos(edge, math.max(left, value_x - 6), top + top_height), true);
            local label_ink = row.key == 'enemy' and timer.show_on_you and timer.which ~= 'attacker' and timer.on_you_color or style.label_color;
            text(list, face, style, left, top, label_size, label_ink, label);
            list:PopClipRect();
        end
        top = top + top_height + 6 * height_scale;
        if (bar > 0) then
            list:AddRectFilled(pos(point, left, top), pos(edge, right, top + bar), theme.u32(style.track_color));
            local fill = state == 'full' and 1 or 0.6;
            if (style.bar_drains and state ~= 'full') then fill = 1 - fill; end
            local start = state == 'full' and (timer.ready_color or timer.full_color) or timer.fill_start;
            local finish = state == 'full' and start or timer.fill_end;
            list:AddRectFilledMultiColor(pos(point, left, top), pos(edge, left + (right - left) * fill, top + bar),
                theme.u32(start), theme.u32(finish), theme.u32(finish), theme.u32(start));
            if (timer.almost_ready and timer.almost_mark) then
                local mark_x = left + (right - left) * (style.bar_drains and 0.2 or 0.8);
                list:AddRectFilled(pos(point, mark_x, top - 2), pos(edge, mark_x + 1, top + bar + 2), theme.u32(timer.almost_color));
            end
            top = top + bar + 4 * height_scale;
        end
        for _, line in ipairs(row.lines) do
            local line_ink = row.key == 'attack' and line:find('640 TP', 1, true) and timer.tp_color or style.detail_color;
            text(list, face, style, left, top, detail_size, line_ink, line);
            top = top + detail_size + 4 * height_scale;
        end
        list:PopClipRect();
        space[1], space[2] = width, height;
        imgui.Dummy(space);
        used = used + width;
    end
    imgui.Spacing();
end

function preview.chat(settings)
    local colors = settings.chat;
    imgui.TextColored(chat_ink[colors.tag_brackets] or chat_ink[106], '['); imgui.SameLine(0, 0);
    imgui.TextColored(chat_ink[colors.tag_word] or chat_ink[106], 'cadence'); imgui.SameLine(0, 0);
    imgui.TextColored(chat_ink[colors.tag_brackets] or chat_ink[106], '] '); imgui.SameLine(0, 0);
    imgui.TextColored(chat_ink[colors.replies] or chat_ink[106], 'Sample reply.');
    imgui.TextWrapped('Chat shades are approximate here. Print a sample shows the game colors.');
end
return preview;
