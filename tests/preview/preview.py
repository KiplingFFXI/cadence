"""
Renders cadence's real settings window with real Dear ImGui (imgui_bundle 1.92.3) offscreen and saves
a PNG cropped to that window.

    python preview.py --addon <addon folder> --out <png> [--tab Timers] [--size W H] [--frames N]
                      [--set key.path=value ...] [--window-size W H] [--window NAME] [--margin PX]
                      [--full] [--exec LUA] [--font PATH]

The addon's Lua files are loaded unmodified into LuaJIT (lupa) with the tests' mock of Ashita
(../mock_ashita.lua), except that require('imgui') is Ashita's own libs/imgui.lua over a
bridge to imgui_bundle (imgui_bridge.lua / imgui_bridge.py). See README.txt.
"""
import argparse
import os
import re
import shutil
import sys
import tempfile
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
HARNESS = os.path.dirname(HERE)
ADDON = os.path.join(os.path.dirname(HARNESS), 'cadence')
ASHITA_LIBS = os.environ.get('ASHITA_LIBS', r'C:/Games/PhoenixXI/addons/libs').replace('\\', '/')
ASHITA_DLL = os.path.join(ASHITA_LIBS, '..', '..', 'Ashita.dll')
AGAVE = os.path.join(HERE, 'fonts', 'Agave_Regular.ttf')
FONT_AWESOME = [os.path.join(HERE, 'fonts', n) for n in
                ('Font_Awesome_7_Free_Solid.ttf', 'Font_Awesome_7_Free_Regular.ttf', 'Font_Awesome_7_Brands_Regular.ttf')]
BACKGROUND = (0.075, 0.085, 0.10, 1.0)   # dark blue-grey, like a night-time field behind the window

sys.path.insert(0, HERE)

import numpy as np                                   # noqa: E402
from PIL import Image                                # noqa: E402
from lupa import luajit21                            # noqa: E402
from imgui_bundle import imgui, hello_imgui, immapp  # noqa: E402

import imgui_bridge                                  # noqa: E402
import imgui_enums                                   # noqa: E402


def parse_args(argv):
    p = argparse.ArgumentParser(description='Render cadence\'s settings window with real Dear ImGui.')
    p.add_argument('--addon', default=ADDON, help='addon folder (holds cadence.lua, ui/, core/), default ../../cadence')
    p.add_argument('--out', required=True, help='PNG to write')
    p.add_argument('--tab', help='tab to show, matched against the visible tab label (case-insensitive)')
    p.add_argument('--size', nargs=2, type=int, default=(1600, 1200), metavar=('W', 'H'),
                   help='game screen (ImGui display) size, default 1600 1200')
    p.add_argument('--frames', type=int, default=4, help='frames to draw before the screenshot (default 4)')
    p.add_argument('--set', action='append', default=[], metavar='key.path=value',
                   help='change a settings value before drawing: numbers, true/false, nil, #rrggbb[aa], '
                        'comma lists (1,0.5,0,1) or text. Repeatable.')
    p.add_argument('--window-size', nargs=2, type=float, metavar=('W', 'H'),
                   help='force the settings window to this size every frame (like a user resize)')
    p.add_argument('--window', help='substring of the window name to crop to (default: the largest window '
                                    'whose name does not start with ##)')
    p.add_argument('--margin', type=int, default=10, help='pixels kept around the window in the crop')
    p.add_argument('--full', action='store_true',
                   help='run the whole addon: dofile cadence.lua, fire load, "/cadence", then d3d_present '
                        'each frame (HUD timers included) instead of calling settings_window.draw directly')
    p.add_argument('--exec', action='append', default=[], metavar='LUA',
                   help='Lua run after settings load and --set, before the first frame (settings = the table)')
    p.add_argument('--script', metavar='LUA_FILE',
                   help='draw this Lua file instead of the settings window. The file returns a function that '
                        'is called once per frame; PREVIEW.log(text) and PREVIEW.frame / PREVIEW.last_frame '
                        'are available, and the last frame\'s log lines are printed on stderr as "log: ..."')
    p.add_argument('--font', default=None, help='TTF for the default ImGui font (default: Ashita\'s Agave)')
    p.add_argument('--font-size', type=float, default=18.0, help='default ImGui font size, Ashita uses 18')
    p.add_argument('--no-crop', action='store_true', help='save the whole screen instead of cropping to the window')
    return p.parse_args(argv)


def parse_value(text):
    t = text.strip()
    if t in ('true', 'false'):
        return t == 'true'
    if t == 'nil':
        return None
    if re.fullmatch(r'#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?', t):
        vals = [int(t[i:i + 2], 16) / 255 for i in range(1, len(t), 2)]
        return vals + ([1.0] if len(vals) == 3 else [])
    try:
        return int(t)
    except ValueError:
        pass
    try:
        return float(t)
    except ValueError:
        pass
    if ',' in t:
        parts = [parse_value(x) for x in t.split(',')]
        if all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in parts):
            return parts
    if len(t) >= 2 and t[0] == t[-1] and t[0] in '\'"':
        return t[1:-1]
    return t


LUA_SETUP = r'''
local addon_dir, mode = ...
local function read_version()
    local f = io.open(addon_dir .. '/cadence.lua', 'r')
    if (f == nil) then return nil end
    local text = f:read('*a'); f:close()
    return text:match("addon%.version%s*=%s*'([^']+)'") or text:match('addon%.version%s*=%s*"([^"]+)"')
end
PREVIEW = { version = read_version() or '0.0.0' }
addon.name = 'cadence'
addon.version = PREVIEW.version
addon.path = addon_dir
-- Real file checks, so hud.load_fonts() finds Windows' fonts like it does in game.
local mock_exists = ashita.fs.exists
ashita.fs.exists = function (path) return mock_exists(path) or PREVIEW_PY.file_exists(path) end
'''

LUA_DIRECT = r'''
local settings_lib = require('settings')
local defaults = require('ui.defaults')
PREVIEW.settings = settings_lib.load(defaults.make())
PREVIEW.hud = require('ui.hud')
PREVIEW.window = require('ui.settings_window')
PREVIEW.hud.load_fonts()
require('ui.window_font').load_all()
PREVIEW.window.set_open(true)
function PREVIEW.draw()
    PREVIEW.window.draw(MOCK.settings.current, PREVIEW.version)
end
'''

LUA_FULL = r'''
dofile(PREVIEW.addon_dir .. '/cadence.lua')
MOCK.fire('load')
PREVIEW.settings = MOCK.settings.current
PREVIEW.hud = require('ui.hud')
PREVIEW.window = require('ui.settings_window')
MOCK.fire('command', { command = '/cadence' })
if (not PREVIEW.window.is_open()) then PREVIEW.window.set_open(true) end
function PREVIEW.draw()
    MOCK.frame(1 / 60)
end
'''

LUA_SCRIPT = r'''
local path, last_frame = ...
PREVIEW.last_frame = last_frame
PREVIEW.frame = 0
PREVIEW.log = function (...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
    PREVIEW_PY.log(table.concat(parts, ' '))
end
local draw = dofile(path)
if (type(draw) ~= 'function') then
    error(('--script %s must return a function (called once per frame), got %s'):format(path, type(draw)))
end
function PREVIEW.draw()
    PREVIEW.frame = PREVIEW.frame + 1
    draw()
end
'''

LUA_SET = r'''
local root, path, value = ...
local node = root
local keys = {}
for key in path:gmatch('[^%.]+') do keys[#keys + 1] = key end
if (keys[1] == 'settings') then table.remove(keys, 1) end
local created = {}
for i = 1, #keys - 1 do
    local k = tonumber(keys[i]) or keys[i]
    if (type(node[k]) ~= 'table') then
        if (node[k] ~= nil) then error(('--set %s: %s is not a table'):format(path, keys[i])) end
        node[k] = {}
        created[#created + 1] = keys[i]
    end
    node = node[k]
end
local last = tonumber(keys[#keys]) or keys[#keys]
local old = node[last]
if (type(value) == 'userdata' or type(value) == 'table') then
    local t = {}
    for i = 1, #value do t[i] = value[i] end
    value = t
end
node[last] = value
return type(old), table.concat(created, '.')
'''


class Preview:
    def __init__(self, args):
        self.args = args
        self.errors = []
        self.warnings = []
        self.frame = 0
        self.last_windows = {}
        self.stack_before = None
        self.work = None                # this run's own folder for what the addon writes, see run()
        self.lua = None
        self.font_name = None
        self.style_done = False
        self.logs = []                  # PREVIEW.log lines of the frame being drawn (--script)
        self.sets = []
        for item in args.set:
            key, sep, raw = item.partition('=')
            if not sep or not key.strip():
                raise SystemExit('--set expects key.path=value, got %r' % item)
            self.sets.append((key.strip(), parse_value(raw)))

    # -- Lua side ---------------------------------------------------------------------------------
    def warn(self, text):
        if text not in self.warnings:
            self.warnings.append(text)

    def make_lua(self):
        a = self.args
        addon = os.path.abspath(a.addon).replace('\\', '/')
        L = luajit21.LuaRuntime(unpack_returned_tuples=True)
        # Lua's garbage collector runs only between frames (see gui()). In the middle of one, it makes lupa
        # now and then give Lua the wrong imgui_bundle object, like an ImFont for GetIO(), or crash the run.
        # Keeping Python references to the objects handed to Lua doesn't stop that.
        L.execute("collectgarbage('stop')")
        self.collect_garbage = L.eval("function () collectgarbage('collect') collectgarbage('stop') end")
        L.execute("package.path = [[%s/?.lua;%s/?.lua;]] .. package.path" % (addon, HARNESS.replace('\\', '/')))
        L.execute("package.path = package.path .. [[;%s/?.lua]]" % ASHITA_LIBS)
        install = self.work
        os.makedirs(os.path.join(install, 'config', 'addons', 'cadence'), exist_ok=True)
        L.globals().MOCK_INSTALL_PATH = install
        L.execute(open(os.path.join(HARNESS, 'mock_ashita.lua'), encoding='utf-8').read())

        self.bridge = imgui_bridge.Bridge(select_tab=a.tab, window_filter=a.window,
                                          forced_size=tuple(a.window_size) if a.window_size else None)
        enums = imgui_enums.bundle_enums()
        imgui_lua = os.path.join(ASHITA_LIBS, 'imgui.lua')
        if not os.path.exists(imgui_lua):
            self.warn('Ashita libs/imgui.lua not found; using imgui_bundle enum names only')
            imgui_lua = None
        py = L.table_from({
            'functions': L.table_from(self.bridge.functions),
            'draw_list': L.table_from(imgui_bridge.DRAW_LIST_FUNCTIONS),
            'get_attr': imgui_bridge.get_attr,
            'set_attr': imgui_bridge.set_attr,
            'call_attr': imgui_bridge.call_attr,
            'vec_get': imgui_bridge.vec_get,
            'vec_set': imgui_bridge.vec_set,
            'enums': L.table_from(enums),
            'imgui_lua': imgui_lua.replace('\\', '/') if imgui_lua else None,
            'warn': self.warn,
        })
        L.globals().PREVIEW_PY = L.table_from({'file_exists': imgui_bridge.file_exists, 'log': self.logs.append})
        bridge_src = open(os.path.join(HERE, 'imgui_bridge.lua'), encoding='utf-8').read()
        L.execute(bridge_src, py)
        L.execute(LUA_SETUP, addon, 'full' if a.full else 'direct')
        L.globals().PREVIEW.addon_dir = addon
        self.lua = L
        self.check_constants(addon)

    def lua_files(self, addon):
        """(path, shown name) of every .lua file in the addon, plus the --script file."""
        for root, _, files in os.walk(addon):
            for f in files:
                if f.endswith('.lua'):
                    path = os.path.join(root, f)
                    yield path, os.path.relpath(path, addon)
        if self.args.script:
            yield os.path.abspath(self.args.script), os.path.basename(self.args.script)

    def check_constants(self, addon):
        """Every ImGui constant named in the addon's Lua (and --script) must be one Ashita's libs/imgui.lua defines."""
        rawget = self.lua.eval('function (k) return rawget(_G, k) end')
        self.constants_checked = 0
        for path, shown in self.lua_files(addon):
            text = open(path, encoding='utf-8', errors='replace').read()
            code = re.sub(r'--\[(=*)\[.*?\]\1\]|--[^\n]*', '', text, flags=re.S)
            for name in sorted(set(re.findall(r'\b(Im(?:Gui|Draw|Font|Texture)\w*?_\w+)\b', code))):
                self.constants_checked += 1
                if rawget(name) is None:
                    self.warn("%s (in %s) is not defined by Ashita's libs/imgui.lua, so it is nil in game" % (name, shown))

    def load_addon(self):
        """Runs inside hello_imgui's font-loading callback, so hud.load_fonts() may add fonts."""
        L = self.lua
        L.execute(LUA_FULL if self.args.full else LUA_DIRECT)
        if self.args.tab:
            L.execute("require('ui.navigation').select(...)", self.args.tab)
        if L.eval('#PREVIEW.hud.font_names()') == 0:
            self.warn('hud.load_fonts() found no fonts, so the Font list only has Ashita')
        set_fn = L.eval('function (...) ' + LUA_SET + ' end')
        for key, value in self.sets:
            if isinstance(value, list):
                value = L.table_from(value)
            old_type, created = set_fn(L.globals().MOCK.settings.current, key, value)
            if created:
                self.warn('--set %s created missing table(s) %s' % (key, created))
            elif old_type == 'nil':
                self.warn('--set %s: the key did not exist before' % key)
        if self.args.full and self.args.set:
            L.execute('PREVIEW.hud.refresh(MOCK.settings.current)')
        for code in self.args.exec:
            L.execute('local settings = MOCK.settings.current\n' + code)
        if self.args.script:
            L.execute(LUA_SCRIPT, os.path.abspath(self.args.script).replace('\\', '/'), self.args.frames)

    # -- hello_imgui callbacks --------------------------------------------------------------------
    def load_fonts(self):
        io = imgui.get_io()
        path = self.args.font or AGAVE
        if not self.args.font and not os.path.exists(path) and os.path.exists(ASHITA_DLL):
            try:
                import subprocess
                subprocess.run([sys.executable, os.path.join(HERE, 'extract_ashita_fonts.py'), ASHITA_DLL,
                                os.path.join(HERE, 'fonts')], check=True, capture_output=True)
            except Exception as ex:
                self.warn('could not extract Agave from Ashita.dll: %s' % ex)
        if not os.path.exists(path):
            import imgui_bundle
            path = os.path.join(os.path.dirname(imgui_bundle.__file__), 'assets', 'fonts', 'Inconsolata-Medium.ttf')
            self.warn('Agave not found (run extract_ashita_fonts.py); using Inconsolata-Medium')
        font = io.fonts.add_font_from_file_ttf(path, self.args.font_size)
        self.font_name = os.path.basename(path)
        if not self.args.font:
            # Ashita merges Font Awesome into every font it loads.
            for fa in FONT_AWESOME:
                if os.path.exists(fa):
                    cfg = imgui.ImFontConfig()
                    cfg.merge_mode = True
                    io.fonts.add_font_from_file_ttf(fa, self.args.font_size, cfg)
        io.font_default = font
        try:
            self.load_addon()
        except Exception as ex:
            # Ending the app from inside this callback crashes hello_imgui, so gui() ends it on frame 1.
            self.errors.append('loading the addon failed: %s' % _short(ex))

    def setup_style(self):
        style = imgui.get_style()
        fresh = imgui.Style()
        for name in dir(fresh):
            if name.startswith('_'):
                continue
            value = getattr(fresh, name)
            if callable(value):
                continue
            try:
                setattr(style, name, value)
            except (AttributeError, TypeError):
                pass
        imgui.style_colors_dark(style)
        style.font_size_base = self.args.font_size
        style.font_scale_main = 1.0
        style.font_scale_dpi = 1.0
        io = imgui.get_io()
        io.set_ini_filename(None)
        io.config_dpi_scale_fonts = False
        io.config_error_recovery = True
        io.config_error_recovery_enable_assert = True
        io.config_error_recovery_enable_debug_log = False
        io.config_error_recovery_enable_tooltip = False
        io.config_debug_highlight_id_conflicts = False

    def pre_new_frame(self):
        # ImGui's default style (hello_imgui applies its own theme first), set before the first frame.
        if not self.style_done:
            self.setup_style()
            self.style_done = True
        # No mouse over anything, so nothing renders hovered.
        imgui.get_io().add_mouse_pos_event(-imgui_bridge.FLT_MAX, -imgui_bridge.FLT_MAX)

    def gui(self):
        self.frame += 1
        params = hello_imgui.get_runner_params()
        if self.frame > self.args.frames or params.app_shall_exit or self.errors:
            params.app_shall_exit = True
            return
        self.bridge.begin_frame(self.frame)
        del self.logs[:]
        self.collect_garbage()
        before = imgui.internal.ErrorRecoveryState()
        imgui.internal.error_recovery_store_state(before)
        raised = False
        try:
            self.lua.globals().PREVIEW.draw()
        except Exception as ex:
            raised = True
            self.errors.append('frame %d: %s' % (self.frame, _short(ex)))
            params.app_shall_exit = True
        after = imgui.internal.ErrorRecoveryState()
        imgui.internal.error_recovery_store_state(after)
        diffs = [n[len('size_of_'):] + ' %+d' % (getattr(after, n) - getattr(before, n))
                 for n in dir(before) if n.startswith('size_of_') and getattr(after, n) != getattr(before, n)]
        if diffs:
            # A Lua error mid-window always leaves the stacks open, so only report them on their own.
            if not raised:
                self.errors.append('frame %d: unbalanced ImGui stacks after drawing: %s' % (self.frame, ', '.join(diffs)))
            # Unwind what the addon left open, so ImGui can finish the frame and exit cleanly.
            io = imgui.get_io()
            io.config_error_recovery_enable_assert = False
            try:
                imgui.internal.error_recovery_try_to_recover_state(before)
            except Exception as ex:
                self.errors.append('recovery failed: %s' % _short(ex))
            finally:
                io.config_error_recovery_enable_assert = True
            params.app_shall_exit = True
        if self.args.full:
            for line in self.lua.globals().MOCK.printed.values():
                if 'Drawing stopped after an error' in str(line):
                    self.errors.append('frame %d: cadence caught a drawing error: %s' % (self.frame, line))
                    params.app_shall_exit = True
            self.lua.execute('MOCK.printed = {}')
        self.last_windows = dict(self.bridge.windows)
        if self.frame >= self.args.frames:
            params.app_shall_exit = True

    # -- run --------------------------------------------------------------------------------------
    def run(self):
        a = self.args
        # The addon's files, like profiles.json, and ImGui's ini file go in a new folder in %TEMP%, so no
        # run sees another's. main() deletes it at the end.
        self.work = tempfile.mkdtemp(prefix='cadence_preview_')
        self.make_lua()
        rp = hello_imgui.RunnerParams()
        rp.app_window_params.window_title = 'cadence preview'
        rp.app_window_params.hidden = True
        rp.app_window_params.restore_previous_geometry = False
        rp.app_window_params.window_geometry.size = (int(a.size[0]), int(a.size[1]))
        rp.imgui_window_params.default_imgui_window_type = hello_imgui.DefaultImGuiWindowType.no_default_window
        rp.imgui_window_params.background_color = imgui.ImVec4(*BACKGROUND)
        rp.imgui_window_params.show_menu_bar = False
        rp.imgui_window_params.show_status_bar = False
        rp.imgui_window_params.remember_theme = False
        rp.fps_idling.enable_idling = False
        # Every run starts from ImGui's first-use state: no window positions or sizes carried over. Each
        # run gets its own file, so the fit gate's runs at once can't lock each other's.
        rp.ini_folder_type = hello_imgui.IniFolderType.absolute_path
        rp.ini_filename = os.path.join(self.work, 'hello_imgui_preview_%d.ini' % os.getpid())
        hello_imgui.delete_ini_settings(rp)
        rp.dpi_aware_params.dpi_window_size_factor = 1.0
        rp.callbacks.default_icon_font = hello_imgui.DefaultIconFont.no_icons
        rp.callbacks.load_additional_fonts = self.load_fonts
        rp.callbacks.setup_imgui_style = self.setup_style
        rp.callbacks.pre_new_frame = self.pre_new_frame
        rp.callbacks.show_gui = self.gui
        try:
            immapp.run(rp)
        except Exception as ex:
            self.errors.append('ImGui: %s' % _short(ex))
        try:
            hello_imgui.delete_ini_settings(rp)
        except Exception:
            pass

        shot = hello_imgui.final_app_window_screenshot()
        arr = np.asarray(shot) if shot is not None else None
        return arr

    def save(self, arr):
        a = self.args
        if a.tab and not self.bridge.tab_applied:
            self.errors.append('tab %r never opened (tabs seen: %s)' % (a.tab, sorted(set(self.bridge.tabs_seen)) or 'none'))
        if self.errors:
            return None, None   # no PNG for a failed run, so a stale or half-drawn image can't pass for a result
        if arr is None or arr.size == 0:
            self.errors.append('no screenshot was captured')
            return None, None
        h, w = arr.shape[0], arr.shape[1]
        target = self.pick_window()
        if target is None:
            self.errors.append('no settings window was drawn (windows seen: %s)' % (list(self.last_windows) or 'none'))
            return None, None
        if a.no_crop:
            box = (0, 0, w, h)
        else:
            info = self.last_windows[target]
            if info['hidden']:
                self.warn('window %r was still hidden on the last frame (auto-fit windows skip their first '
                          'frame); use --frames 2 or more' % target)
            x0, y0 = info['pos']
            x1, y1 = x0 + info['size'][0], y0 + info['size'][1]
            if x0 < 0 or y0 < 0 or x1 > w or y1 > h:
                self.warn('window %r runs off the %dx%d screen; the crop is clipped' % (target, w, h))
            m = a.margin
            box = (max(0, int(x0) - m), max(0, int(y0) - m), min(w, int(np.ceil(x1)) + m), min(h, int(np.ceil(y1)) + m))
        img = Image.fromarray(arr[:, :, :3] if arr.ndim == 3 else arr).crop(box)
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        img.save(a.out)
        return target, box

    def pick_window(self):
        if not self.last_windows:
            return None
        names = list(self.last_windows)
        if self.args.window:
            names = [n for n in names if self.args.window.lower() in n.lower()]
        else:
            named = [n for n in names if not n.startswith('##')]
            names = named or names
        if not names:
            return None
        return max(names, key=lambda n: self.last_windows[n]['size'][0] * self.last_windows[n]['size'][1])


def _short(ex):
    text = str(ex).strip()
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if len(lines) > 6:
        lines = lines[:6] + ['...']
    return ' | '.join(lines) if lines else repr(ex)


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors='replace')
        except Exception:
            pass
    args = parse_args(argv if argv is not None else sys.argv[1:])
    if not os.path.isdir(args.addon):
        print('FAIL addon folder not found: %s' % args.addon)
        return 2
    pv = Preview(args)
    try:
        arr = pv.run()
        target, box = pv.save(arr)
    except SystemExit:
        raise
    except Exception as ex:
        traceback.print_exc()
        pv.errors.append('preview crashed: %s' % _short(ex))
        target, box = None, None
    finally:
        if pv.work is not None:
            shutil.rmtree(pv.work, ignore_errors=True)

    b = pv.bridge if hasattr(pv, 'bridge') else None
    for line in pv.logs:
        print('log: ' + line, file=sys.stderr)
    for w in pv.warnings:
        print('warning: ' + w, file=sys.stderr)

    parts = ['OK' if not pv.errors else 'FAIL']
    if target is not None:
        info = pv.last_windows[target]
        parts.append('window=%r pos=(%g,%g) size=%gx%g content=%gx%g' % (
            target, info['pos'][0], info['pos'][1], info['size'][0], info['size'][1],
            info['content'][0], info['content'][1]))
        if info['scrollbar_y'] or info['scrollbar_x']:
            parts.append('scrollbar=%s%s' % ('x' if info['scrollbar_x'] else '', 'y' if info['scrollbar_y'] else ''))
    if b is not None:
        parts.append('tab=%s' % (','.join(b.tab_open) or '-'))
    parts.append('screen=%dx%d frames=%d font=%s' % (args.size[0], args.size[1], args.frames, pv.font_name))
    if box is not None and not pv.errors:
        parts.append('crop=%s out=%s' % (box, args.out))
    if pv.warnings:
        parts.append('warnings=%d' % len(pv.warnings))
    if pv.errors:
        for e in pv.errors:
            print('error: ' + e, file=sys.stderr)
        parts.append('error: ' + pv.errors[0])
        if len(pv.errors) > 1:
            parts.append('(+%d follow-on, see stderr)' % (len(pv.errors) - 1))
    sys.stderr.flush()
    print(' '.join(parts))
    sys.stdout.flush()
    return 1 if pv.errors else 0


if __name__ == '__main__':
    code = main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(code)   # Skips interpreter teardown. hello_imgui and GL objects don't always unload cleanly.
