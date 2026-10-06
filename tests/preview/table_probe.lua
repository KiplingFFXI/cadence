--[[
    A layout probe for preview.py --script. It isn't part of cadence. With cadence's window style
    pushed, it measures what SameLine(200), Separator, GetContentRegionAvail and PushTextWrapPos(0) do
    inside a 2-column BeginTable cell in ImGui 1.92.3. It also tries SetNextWindowSizeConstraints on a
    resizable window. It logs on the last frame only.

    Separators are pure green and wrapped text is magenta, so the PNG can be checked by pixel.
]]
local imgui = require('imgui');
local theme = require('ui.theme');

local LONG = 'The quick brown fox jumps over the lazy dog while the auto attack timer counts down the delay.';
local GREEN = { 0, 1, 0, 1 };
local MAGENTA = { 1, 0, 1, 1 };
local LOOK = theme.window_style('phoenix');

local function fmt(v) return string.format('%g', v); end

local function probe_cell(log, tag)
    local wx = imgui.GetWindowPos();
    local x0 = imgui.GetCursorScreenPos();
    local lx0 = imgui.GetCursorPosX();
    local aw, ah = imgui.GetContentRegionAvail();
    log(tag, 'cell_start_screen_x=' .. fmt(x0), 'cell_start_local_x=' .. fmt(lx0),
        'avail=' .. fmt(aw) .. 'x' .. fmt(ah), 'cell_right_edge_x=' .. fmt(x0 + aw));

    -- SameLine(200) inside the cell
    imgui.TextUnformatted('A');
    imgui.SameLine(200);
    local sx = imgui.GetCursorScreenPos();
    imgui.TextUnformatted('B');
    log(tag, 'SameLine(200): cursor_screen_x=' .. fmt(sx), 'minus_cell_start=' .. fmt(sx - x0),
        'minus_window_x=' .. fmt(sx - wx));

    -- SameLine(GetCursorPosX() + N) with N = 100.
    local lx = imgui.GetCursorPosX();
    imgui.TextUnformatted('C');
    imgui.SameLine(lx + 100);
    local sx2 = imgui.GetCursorScreenPos();
    imgui.TextUnformatted('D');
    log(tag, 'SameLine(GetCursorPosX()+100): GetCursorPosX()=' .. fmt(lx), 'cursor_screen_x=' .. fmt(sx2),
        'minus_cell_start=' .. fmt(sx2 - x0));

    -- GetContentRegionAvail after some items (x should not change on a new line)
    local aw2, ah2 = imgui.GetContentRegionAvail();
    log(tag, 'avail_after_items=' .. fmt(aw2) .. 'x' .. fmt(ah2));

    -- Separator inside the cell
    imgui.PushStyleColor(ImGuiCol_Separator, GREEN);
    imgui.Separator();
    imgui.PopStyleColor(1);
    local smx, smy = imgui.GetItemRectMin();
    local sMx, sMy = imgui.GetItemRectMax();
    log(tag, 'Separator rect x=' .. fmt(smx) .. '..' .. fmt(sMx), 'y=' .. fmt(smy) .. '..' .. fmt(sMy),
        'width=' .. fmt(sMx - smx));

    -- PushTextWrapPos(0) inside the cell
    local tx0 = imgui.GetCursorScreenPos();
    local aw3 = imgui.GetContentRegionAvail();
    imgui.PushStyleColor(ImGuiCol_Text, MAGENTA);
    imgui.PushTextWrapPos(0);
    imgui.TextUnformatted(LONG);
    imgui.PopTextWrapPos();
    imgui.PopStyleColor(1);
    local rmx, rmy = imgui.GetItemRectMin();
    local rMx, rMy = imgui.GetItemRectMax();
    local cw, ch = imgui.CalcTextSize(LONG, false, aw3);
    local nw, nh = imgui.CalcTextSize(LONG);
    log(tag, 'Wrap(0) text rect x=' .. fmt(rmx) .. '..' .. fmt(rMx), 'size=' .. fmt(rMx - rmx) .. 'x' .. fmt(rMy - rmy),
        'lines=' .. fmt((rMy - rmy) / imgui.GetTextLineHeight()),
        'CalcTextSize(wrap=avail ' .. fmt(aw3) .. ')=' .. fmt(cw) .. 'x' .. fmt(ch),
        'unwrapped=' .. fmt(nw) .. 'x' .. fmt(nh), 'wrap_limit_x=' .. fmt(tx0 + aw3));

    -- PushTextWrapPos(GetCursorPosX() + 150) inside the cell.
    local lx4 = imgui.GetCursorPosX();
    imgui.PushTextWrapPos(lx4 + 150);
    imgui.TextUnformatted(LONG);
    imgui.PopTextWrapPos();
    local qmx = imgui.GetItemRectMin();
    local qMx = imgui.GetItemRectMax();
    log(tag, 'Wrap(GetCursorPosX()+150) text x=' .. fmt(qmx) .. '..' .. fmt(qMx), 'width=' .. fmt(qMx - qmx));
end

return function ()
    local last = PREVIEW.frame == PREVIEW.last_frame;
    local log = last and PREVIEW.log or function () end;

    local color_count, var_count = theme.push_window_style(LOOK);

    -- Resizable window (no AlwaysAutoResize) with size constraints: min 600x300, max 1000 wide.
    imgui.SetNextWindowPos({ 40, 40 }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ 800, 520 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 600, 300 }, { 1000, FLT_MAX });
    if (imgui.Begin('tableprobe', nil, bit.bor(ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoSavedSettings))) then
        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        local cx0 = imgui.GetCursorScreenPos();
        local caw = imgui.GetContentRegionAvail();
        log('window pos=' .. fmt(wx) .. ',' .. fmt(wy), 'size=' .. fmt(ww) .. 'x' .. fmt(wh),
            'content_start_x=' .. fmt(cx0), 'content_avail_w=' .. fmt(caw));

        -- Outside a table, for comparison
        imgui.TextUnformatted('A');
        imgui.SameLine(200);
        local ox = imgui.GetCursorScreenPos();
        imgui.TextUnformatted('B (window, SameLine(200))');
        log('outside table: SameLine(200) cursor_screen_x=' .. fmt(ox), 'minus_window_x=' .. fmt(ox - wx),
            'minus_content_start=' .. fmt(ox - cx0));
        imgui.PushStyleColor(ImGuiCol_Separator, GREEN);
        imgui.Separator();
        imgui.PopStyleColor(1);
        local a1 = imgui.GetItemRectMin();
        local a2 = imgui.GetItemRectMax();
        log('outside table: Separator x=' .. fmt(a1) .. '..' .. fmt(a2));

        -- A default table, with flags 0, two columns, default (stretch) sizing and full width.
        if (imgui.BeginTable('##probe', 2, 0)) then
            imgui.TableNextRow();
            imgui.TableSetColumnIndex(0);
            probe_cell(log, 'stretch col0');
            imgui.TableSetColumnIndex(1);
            probe_cell(log, 'stretch col1');
            imgui.EndTable();
        end
        local t1 = imgui.GetItemRectMin();
        local t2 = imgui.GetItemRectMax();
        log('stretch table rect x=' .. fmt(t1) .. '..' .. fmt(t2));

        -- Fixed left column 380 px + stretch right column.
        if (imgui.BeginTable('##probe_fixed', 2, ImGuiTableFlags_SizingFixedFit)) then
            imgui.TableSetupColumn('left', ImGuiTableColumnFlags_WidthFixed, 380);
            imgui.TableSetupColumn('right', ImGuiTableColumnFlags_WidthStretch);
            imgui.TableNextRow();
            imgui.TableSetColumnIndex(0);
            local x0 = imgui.GetCursorScreenPos();
            local aw = imgui.GetContentRegionAvail();
            imgui.TextUnformatted('fixed');
            imgui.TableSetColumnIndex(1);
            local x1 = imgui.GetCursorScreenPos();
            local aw1 = imgui.GetContentRegionAvail();
            imgui.TextUnformatted('stretch');
            log('fixed380 table: col0 start=' .. fmt(x0), 'avail=' .. fmt(aw), 'col1 start=' .. fmt(x1), 'avail=' .. fmt(aw1));
            imgui.EndTable();
        end
    end
    imgui.End();

    -- Auto-resize window with a min width constraint: does the constraint widen the auto-fit size?
    imgui.SetNextWindowPos({ 40, 620 }, ImGuiCond_Always);
    imgui.SetNextWindowSizeConstraints({ 500, 0 }, { FLT_MAX, FLT_MAX });
    if (imgui.Begin('autofit##probe2', nil, bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings))) then
        imgui.TextUnformatted('short');
    end
    local aw, ah = imgui.GetWindowSize();
    imgui.End();
    log('autofit window with min {500,0}: size=' .. fmt(aw) .. 'x' .. fmt(ah));

    theme.pop_window_style(color_count, var_count);
end
