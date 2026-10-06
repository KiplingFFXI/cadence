--[[
    Self-test fixture for the preview bridge, dropped in as ui/settings_window.lua of a scratch copy of
    the addon. It isn't a cadence layout. It calls the bindings a settings window uses and checks that
    what comes back has Ashita's shapes. That's two numbers from getters, booleans from widgets and
    one-slot tables edited in place.
]]

local imgui = require('imgui');
local theme = require('ui.theme');
local hud   = require('ui.hud');

local M = {};
local open = { false };
local flag = { false };
local number = { 0 };
local fnum = { 0 };
local P = theme.palette;
local LOOK = theme.window_style('phoenix');
local COLOR_FLAGS = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_AlphaPreviewHalf);

function M.is_open() return open[1]; end
function M.set_open(v) open[1] = v; end

local function expect(cond, what)
    if (not cond) then error('selftest: ' .. what, 2); end
end

local function column(settings, key, title)
    local t = settings[key];
    imgui.TextColored(P.peach, title);
    imgui.Separator();
    flag[1] = t.show_value;
    local changed = imgui.Checkbox('Seconds left##' .. key, flag);
    expect(type(changed) == 'boolean', 'Checkbox returns a boolean');
    number[1] = t.width;
    imgui.SetNextItemWidth(-1);
    expect(type(imgui.SliderInt('##width' .. key, number, 120, 480, 'Width %d px', ImGuiSliderFlags_AlwaysClamp)) == 'boolean', 'SliderInt returns a boolean');
    expect(imgui.IsItemDeactivatedAfterEdit() == false, 'IsItemDeactivatedAfterEdit is false with no input');
    fnum[1] = key == 'attack' and t.almost_seconds or t.flash_seconds;
    imgui.SetNextItemWidth(-1);
    imgui.SliderFloat('##secs' .. key, fnum, 0.1, 2.0, '%.1f s');
    imgui.ColorEdit4('##start' .. key, t.fill_start, COLOR_FLAGS);
    imgui.SameLine();
    imgui.ColorEdit4('##end' .. key, t.fill_end, COLOR_FLAGS);
    imgui.SameLine();
    imgui.AlignTextToFramePadding();
    imgui.TextColored(P.muted, 'Fill');
end

function M.draw(settings, version)
    local result = {};
    if (not open[1]) then return result; end
    local colors, vars = theme.push_window_style(LOOK);
    imgui.SetNextWindowPos({ 120, 120 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSize({ 780, 430 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 560, 300 }, { FLT_MAX, FLT_MAX });
    if (imgui.Begin('selftest##cadence_settings', open, bit.bor(ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoSavedSettings))) then
        local w, h = imgui.GetWindowSize();
        local aw, ah = imgui.GetContentRegionAvail();
        local cx, cy = imgui.GetCursorPos();
        expect(type(w) == 'number' and type(h) == 'number', 'GetWindowSize returns two numbers');
        expect(type(aw) == 'number' and type(ah) == 'number', 'GetContentRegionAvail returns two numbers');
        expect(type(cx) == 'number' and type(cy) == 'number', 'GetCursorPos returns two numbers');
        expect(type(imgui.GetCursorPosX()) == 'number', 'GetCursorPosX returns a number');
        expect(imgui.IsMouseDown(ImGuiMouseButton_Left) == false, 'IsMouseDown is false');
        expect(type(FLT_MAX) == 'number' and FLT_MAX > 1e38, 'FLT_MAX is defined');
        expect(imgui.col32(255, 255, 0, 0) == bit.bor(bit.lshift(255, 24), 255), 'col32 comes from Ashita libs/imgui.lua');
        imgui.TextUnformatted(('window %dx%d  avail %dx%d  v%s'):format(w, h, aw, ah, version));

        if (imgui.BeginTabBar('##tabs', ImGuiTabBarFlags_DrawSelectedOverline)) then
            if (imgui.BeginTabItem('Timers')) then
                if (imgui.BeginTable('##cols', 2, bit.bor(ImGuiTableFlags_SizingStretchSame, ImGuiTableFlags_BordersInnerV,
                        ImGuiTableFlags_PadOuterX))) then
                    imgui.TableSetupColumn('Auto Attack', ImGuiTableColumnFlags_WidthStretch);
                    imgui.TableSetupColumn('Resting', ImGuiTableColumnFlags_WidthStretch);
                    imgui.TableNextRow();
                    imgui.TableNextColumn();
                    column(settings, 'attack', 'AUTO ATTACK');
                    imgui.TableNextColumn();
                    column(settings, 'resting', 'RESTING');
                    imgui.EndTable();
                end
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Look')) then
                imgui.SetNextItemWidth(200);
                if (imgui.BeginCombo('Preset', 'Pick a look')) then
                    imgui.Selectable('Phoenix', false);
                    imgui.EndCombo();
                end
                imgui.BeginDisabled(#hud.font_names() == 0);
                flag[1] = settings.style.system_font;
                imgui.Checkbox('Windows font', flag);
                imgui.EndDisabled();
                imgui.BeginDisabled(true);
                imgui.Button('Disabled button');
                imgui.EndDisabled();
                imgui.EndTabItem();
            end
            imgui.EndTabBar();
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Dummy({ 0, 4 });
        imgui.PushTextWrapPos(imgui.GetCursorPosX() + 500);
        imgui.TextUnformatted('This note wraps at 500 px from the left edge of the content, so the bridge\'s '
            .. 'PushTextWrapPos and PopTextWrapPos run with a real width.');
        imgui.PopTextWrapPos();
        if (imgui.Button('Reset positions')) then result.reset_positions = true; end
        imgui.SameLine();
        imgui.Button('Reset look', { 120, 0 });
    end
    imgui.End();
    theme.pop_window_style(colors, vars);
    return result;
end

return M;
