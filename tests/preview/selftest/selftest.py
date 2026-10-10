"""
Self-test for preview.py. Builds scratch copies of an addon with ui/settings_window.lua swapped for
small fixtures, runs preview.py on each and checks the exit code and summary line. Then it checks
that fit_gate.py runs a render once more after the preview's known flake.

    python selftest.py [--addon <addon folder>]
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEW = os.path.join(os.path.dirname(HERE), 'preview.py')
WORK = os.path.join(tempfile.gettempdir(), 'cadence_preview_selftest')
DEFAULT_ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), 'cadence')
# A file one run leaves in its folder, and where that run says its folder was.
LEFT_FILE = 'config/addons/cadence/left_by_selftest.txt'
LAST_FOLDER = os.path.join(WORK, 'last_folder.txt').replace('\\', '/')

# Small broken windows. Each draws inside a normal Begin/End with the theme pushed.
BROKEN = r'''
local imgui = require('imgui')
local theme = require('ui.theme')
local M = {}
local open = { false }
local look = theme.window_style('phoenix')
function M.is_open() return open[1] end
function M.set_open(v) open[1] = v end
function M.draw(settings, version)
    local c, v = theme.push_window_style(look)
    if (imgui.Begin('broken##cadence_settings', open, ImGuiWindowFlags_AlwaysAutoResize)) then
        imgui.TextUnformatted('before')
        %s
    end
    imgui.End()
    theme.pop_window_style(c, v)
    return {}
end
return M
'''

CASES = [
    # name, window source, extra args, expected exit, substrings expected in the summary / stderr
    ('fixture', None, ['--tab', 'Timers'], 0, ["window='selftest##cadence_settings'", 'tab=Timers', 'size=780x430']),
    ('fixture_look', None, ['--tab', 'Appearance'], 0, ['tab=Appearance']),
    ('fixture_resized', None, ['--tab', 'Timers', '--window-size', '1000', '360'], 0, ['size=1000x360']),
    ('fixture_min', None, ['--tab', 'Timers', '--window-size', '300', '200'], 0, ['size=560x300']),
    ('unknown_function', "imgui.NotARealFunction('x')", [], 1, ['imgui.NotARealFunction is not implemented']),
    ('unbalanced_color', 'imgui.PushStyleColor(ImGuiCol_Text, { 1, 0, 0, 1 })', [], 1, ['Missing PopStyleColor()']),
    ('wrong_var_type', 'imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, 5); imgui.PopStyleVar(1)', [], 1, ['IM_ASSERT']),
    ('bad_out_param', "imgui.Checkbox('x', true)", [], 1, ['one-slot table']),
    ('lua_error', "local x = nil; x.y = 1", [], 1, ["attempt to index local 'x'"]),
    ('missing_end_tab_item', "if imgui.BeginTabBar('##t') then if imgui.BeginTabItem('A') then end imgui.EndTabBar() end", [], 1, ['IM_ASSERT']),
    ('unbalanced_after_end', "imgui.End(); imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.5); imgui.Begin('x')", [], 1, ['unbalanced ImGui stacks', 'style_var_stack +1']),
    ('proxies', "local s = imgui.GetStyle(); assert(s.WindowPadding.x == 14, 'pad ' .. tostring(s.WindowPadding.x)); "
                "s.ItemInnerSpacing.x = 5; assert(s.ItemInnerSpacing.x == 5, 'write-through'); s.ItemInnerSpacing.x = 4; "
                "local io = imgui.GetIO(); assert(io.DisplaySize.x == 1600 and io.DisplaySize.y == 1200, 'display'); "
                "assert(io.KeyShift == false, 'KeyShift'); local c = imgui.GetMainViewport():GetCenter(); "
                "assert(c.x == 800 and c.y == 600, 'center'); assert(imgui.GetVersion():match('^1%.92'), 'version'); "
                "assert(imgui.ColorConvertFloat4ToU32({ 1, 0, 0, 1 }) == 0xFF0000FF, 'u32'); "
                "local r, g, b, a = imgui.GetStyleColorVec4(ImGuiCol_Text); assert(r > 0.99 and a == 1, 'vec4'); "
                "local list = imgui.GetWindowDrawList(); local x, y = imgui.GetWindowPos(); "
                "list:AddRectFilled({ x, y }, { x + 10, y + 10 }, imgui.col32(255, 255, 0, 0), 2, ImDrawFlags_RoundCornersLeft); "
                "list:AddText({ x, y }, 0xFFFFFFFF, 'dl'); list:AddText(imgui.GetFont(), 12, { x, y }, -1, 'dl2')",
     [], 0, ["window='broken##cadence_settings'"]),
    # The bridge handles these itself. Packed colors below 2^31 would hit imgui_bundle's ImGuiCol overload
    # and crash. MenuItem with no shortcut and ColorConvertRGBtoHSV would raise TypeErrors.
    ('conversions', "assert(imgui.GetColorU32(imgui.col32(64, 255, 0, 0)) == 0x400000FF, 'packed low alpha'); "
                    "assert(imgui.GetColorU32(imgui.col32(200, 1, 2, 3), 0.5) == 0x64030201, 'alpha_mul'); "
                    "assert(imgui.GetColorU32(imgui.col32(255, 0, 0, 255)) == 0xFFFF0000, 'negative from bit ops'); "
                    "assert(type(imgui.MenuItem('m')) == 'boolean', 'MenuItem'); "
                    "local h, s, v = imgui.ColorConvertRGBtoHSV(1, 0, 0); assert(h == 0 and s == 1 and v == 1, 'hsv'); "
                    "if imgui.BeginCombo('c', nil) then imgui.EndCombo() end; imgui.SetWindowFocus('broken##cadence_settings')",
     [], 0, ["window='broken##cadence_settings'"]),
    # Warnings, not failures: one from the static scan of the addon's Lua, one when the line runs.
    ('undefined_constant', 'imgui.Text(tostring(ImGuiWindowFlags_NoSuchThing))', [], 0,
     ['warnings=2', 'ImGuiWindowFlags_NoSuchThing is not an ImGui constant (nil)']),
    ('bundle_only_constant', 'imgui.Text(tostring(ImGuiStyleVar_LayoutAlign))', [], 0,
     ['warnings=2', "ImGuiStyleVar_LayoutAlign is not defined by Ashita's libs/imgui.lua (nil in game)"]),
    # --script draws the given Lua file instead of the settings window and prints its last-frame logs.
    ('script', None, ['--script', os.path.join(os.path.dirname(HERE), 'table_probe.lua'), '--window', 'tableprobe'], 0,
     ["window='tableprobe'", 'log: stretch col1 Separator rect x=452..826']),
    # Lua's garbage collector never runs while the addon loads or a frame draws. Each frame makes about
    # 1.5 MB of garbage, and the next one checks it was collected in between.
    ('garbage_between_frames',
     "assert(collectgarbage('isrunning') == false, 'the collector can run while a frame draws'); "
     "local kb = collectgarbage('count'); "
     "assert(SELFTEST_KB == nil or kb < SELFTEST_KB + 500, 'the last frame left its garbage'); "
     "local junk = {}; for i = 1, 20000 do junk[i] = { i } end; SELFTEST_KB = kb",
     ['--frames', '3', '--exec', "assert(collectgarbage('isrunning') == false, 'the collector can run while the addon loads')"],
     0, ["window='broken##cadence_settings'"]),
    # Each run writes in its own folder, deleted when it ends. The first leaves a file and says where. The
    # second checks that its folder is another one and the file went with the first one's folder.
    ('leaves_a_file', None, ['--exec', "local f = assert(io.open(AshitaCore:GetInstallPath() .. '/%s', 'w')) f:write('x') "
                                       "f:close() f = assert(io.open([[%s]], 'w')) f:write(AshitaCore:GetInstallPath()) "
                                       "f:close()" % (LEFT_FILE, LAST_FOLDER)],
     0, ["window='selftest##cadence_settings'"]),
    ('own_folder', None, ['--exec', "local f = assert(io.open([[%s]])) local last = f:read('*a') f:close() "
                                    "assert(last ~= AshitaCore:GetInstallPath(), 'this run uses the last one\\'s folder') "
                                    "assert(io.open(last .. '/%s') == nil, 'the last run left its folder')"
                                    % (LAST_FOLDER, LEFT_FILE)],
     0, ["window='selftest##cadence_settings'"]),
]

# fit_gate runs a render once more when it hit the preview's known flake, and only then. A stand-in for
# preview.py ends each try the way it's told and counts its tries in a file.
FAKE_RENDER = r'''
import os, sys
count, outcomes = sys.argv[1], sys.argv[2:]
tries = len(open(count).read()) if os.path.exists(count) else 0
open(count, 'a').write('x')
outcome = outcomes[tries]
if outcome == 'crash':
    os._exit(-1073741819)   # 0xC0000005, an access violation
if outcome == 'flake':
    print("error: frame 23: ImFont has no field 'DisplaySize'")
if outcome == 'fail':
    print('error: frame 1: a real failure')
sys.exit(0 if outcome == 'ok' else 1)
'''
RETRIES = [
    # how each try ends, the exit code fit_gate gets back, how many tries it made
    (['flake', 'ok'], 0, 2),
    (['crash', 'ok'], 0, 2),
    (['fail', 'ok'], 1, 1),
    (['flake', 'flake', 'ok'], 1, 2),
]


def make_addon(base, name, window_src):
    dst = os.path.join(WORK, name)
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(base, dst)
    path = os.path.join(dst, 'ui', 'settings_window.lua')
    if window_src is None:
        shutil.copyfile(os.path.join(HERE, 'fixture_window.lua'), path)
    else:
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(BROKEN % window_src)
    return dst


def check_retries():
    sys.path.insert(0, os.path.dirname(HERE))
    import fit_gate
    fails = 0
    count = os.path.join(WORK, 'tries.txt')
    for outcomes, want_code, want_tries in RETRIES:
        if os.path.exists(count):
            os.remove(count)
        run = fit_gate.render([sys.executable, '-c', FAKE_RENDER, count] + outcomes)
        tries = len(open(count).read())
        ok = run.returncode == want_code and tries == want_tries
        fails += 0 if ok else 1
        print('%s %-22s exit=%d tries=%d' % ('ok  ' if ok else 'FAIL', 'retry ' + ','.join(outcomes), run.returncode, tries))
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--addon', default=DEFAULT_ADDON)
    args = ap.parse_args()
    os.makedirs(WORK, exist_ok=True)
    if os.path.exists(LAST_FOLDER):
        os.remove(LAST_FOLDER)
    fails = 0
    for name, src, extra, want_code, needles in CASES:
        addon = make_addon(args.addon, name, src)
        out = os.path.join(WORK, name + '.png')
        cmd = [sys.executable, PREVIEW, '--addon', addon, '--out', out] + extra
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        text = p.stdout + p.stderr
        missing = [n for n in needles if n not in text]
        ok = p.returncode == want_code and not missing
        fails += 0 if ok else 1
        print('%s %-22s exit=%d %s' % ('ok  ' if ok else 'FAIL', name, p.returncode,
                                        '' if ok else 'missing=%r' % missing))
        print('     ' + text.strip().replace('\n', '\n     '))
    fails += check_retries()
    total = len(CASES) + len(RETRIES)
    print('%d/%d passed' % (total - fails, total))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
