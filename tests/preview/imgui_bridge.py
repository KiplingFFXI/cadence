"""
Python half of the Ashita-style imgui bridge.

Every function here takes arguments the way Ashita's GuiManager binding does (see
C:/Games/PhoenixXI/addons/libs/annotations/SDK/IGuiManager.lua) and forwards them to imgui_bundle:

  - ImVec2 / ImVec4 are Lua tables { x, y } / { r, g, b, a } (a { x = , y = } table also works).
  - bool / number out-params are one-slot Lua tables edited in place ({ false }, { 0 }), and a
    color is a 4-slot table edited in place. The function returns the ImGui bool (changed, clicked).
  - Getters that return an ImVec2 return two numbers (GetWindowSize, GetCursorPos, ...).
  - Draw-list colors are packed ABGR numbers. LuaJIT's bit ops can hand them over negative, so they
    are masked to 32 bits like the real binding's integer conversion does.

imgui_bridge.lua turns FUNCTIONS into the table libs/imgui.lua uses as its __index (the stand-in for
AshitaCore:GetGuiManager()), and wraps draw lists, GetIO(), GetStyle() and GetMainViewport().
"""
import os
import re
import types

from imgui_bundle import imgui
from lupa import luajit21 as _lupa

FLT_MAX = 3.402823466e+38


class BridgeError(TypeError):
    pass


def _is_table(v):
    return _lupa.lua_type(v) == 'table'


def _num(v, name='value', default=None):
    if v is None:
        if default is None:
            raise BridgeError('%s: expected a number, got nil' % name)
        return default
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise BridgeError('%s: expected a number, got %r' % (name, v))
    return v


def _flags(v, name='flags'):
    if v is None:
        return 0
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise BridgeError('%s: expected ImGui flags (a number), got %r' % (name, v))
    return int(v)


def _u32(v, name='color'):
    return int(_num(v, name)) & 0xFFFFFFFF


def _str(v, name='label'):
    if isinstance(v, str):
        return v
    if isinstance(v, bytes):
        return v.decode('utf-8', 'replace')
    if isinstance(v, int) and not isinstance(v, bool):
        return str(v)  # sol2 probably converts a number with lua_tostring. Not tested in Ashita.
    if isinstance(v, float):
        return '%.14g' % v  # LuaJIT's tostring format (Python's str(1/3) has 16 digits, Lua's 14)
    raise BridgeError('%s: expected a string, got %r' % (name, v))


def vec2(t, name='ImVec2', default=None):
    if t is None:
        return default
    if isinstance(t, imgui.ImVec2):
        return t
    if _is_table(t):
        x, y = t[1], t[2]
        if x is None and y is None:
            x, y = t['x'], t['y']
        if x is None or y is None:
            raise BridgeError('%s: expected a { x, y } table' % name)
        return imgui.ImVec2(float(x), float(y))
    raise BridgeError('%s: expected a { x, y } table, got %r' % (name, t))


def vec4(t, name='ImVec4', default=None):
    if t is None:
        return default
    if isinstance(t, imgui.ImVec4):
        return t
    if _is_table(t):
        vals = [t[1], t[2], t[3], t[4]]
        if vals[0] is None:
            vals = [t['x'], t['y'], t['z'], t['w']]
        if any(v is None for v in vals):
            raise BridgeError('%s: expected a { r, g, b, a } table' % name)
        return imgui.ImVec4(*(float(v) for v in vals))
    raise BridgeError('%s: expected a { r, g, b, a } table, got %r' % (name, t))


def _slot(t, name):
    if not _is_table(t):
        raise BridgeError('%s: expected a one-slot table like { value }, got %r' % (name, t))
    return t[1]


def _xy(v):
    return float(v.x), float(v.y)


def camel_to_snake(name):
    s = re.sub(r'([A-Z]+)([A-Z][a-z])', r'\1_\2', name)
    s = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', s)
    return s.lower()


class Bridge:
    """Holds the per-run state the preview needs (tab to select, window rects) and the functions."""

    def __init__(self, select_tab=None, window_filter=None, forced_size=None):
        self.select_tab = select_tab.lower() if select_tab else None
        self.tab_applied = False        # SetSelected was sent and the tab came back selected
        self.tabs_seen = []             # visible labels of every BeginTabItem call
        self.tab_open = []              # tabs whose BeginTabItem returned true this frame
        self.window_filter = window_filter
        self.forced_size = forced_size
        self.window_stack = []
        self.windows = {}               # name -> info, top-level windows ended this frame
        self.frame = 0
        self.fonts_added = []
        self.functions = self._build()

    # -- frame bookkeeping ------------------------------------------------------------------------
    def begin_frame(self, n):
        self.frame = n
        self.window_stack = []
        self.windows = {}
        self.tab_open = []

    def _matches_target(self, name):
        if self.window_filter:
            return self.window_filter.lower() in name.lower()
        return not name.startswith('##')

    # -- functions --------------------------------------------------------------------------------
    def _build(self):
        B = self
        F = {}

        def fn(f):
            F[f.__name__] = f
            return f

        # Windows ---------------------------------------------------------------------------------
        @fn
        def Begin(name, is_open=None, flags=None):
            name = _str(name, 'Begin name')
            top = not B.window_stack
            if top and B.forced_size and B._matches_target(name):
                imgui.set_next_window_size(imgui.ImVec2(*B.forced_size), imgui.Cond_.always)
            B.window_stack.append(name)
            fl = _flags(flags)
            if _is_table(is_open):
                shown, still_open = imgui.begin(name, bool(is_open[1]), fl)
                if not still_open:
                    is_open[1] = False
                return shown
            # A boolean p_open (hud.lua passes true) is treated as no close button. That's a guess. The
            # binding probably only writes back through a table.
            shown, _ = imgui.begin(name, None, fl)
            return shown

        @fn
        def End():
            if len(B.window_stack) == 1:
                w = imgui.internal.get_current_window()
                B.windows[B.window_stack[0]] = {
                    'pos': _xy(w.pos), 'size': _xy(w.size), 'content': _xy(w.content_size),
                    'content_ideal': _xy(w.content_size_ideal), 'scroll_max': _xy(w.scroll_max),
                    'scrollbar_x': bool(w.scrollbar_x), 'scrollbar_y': bool(w.scrollbar_y),
                    'flags': int(w.flags), 'order': len(B.windows),
                    'hidden': bool(w.hidden) or int(w.hidden_frames_cannot_skip_items) > 0
                              or int(w.hidden_frames_can_skip_items) > 0,
                }
            if B.window_stack:
                B.window_stack.pop()
            imgui.end()

        @fn
        def BeginChild(str_id, size=None, child_flags=None, window_flags=None):
            if isinstance(child_flags, bool):
                raise BridgeError('BeginChild: child_flags must be ImGuiChildFlags_* (a number). Passing a '
                                  'boolean is untested with the 1.92 binding.')
            sid = str_id if isinstance(str_id, (int, float)) and not isinstance(str_id, bool) else _str(str_id, 'BeginChild id')
            B.window_stack.append('<child>')
            return imgui.begin_child(sid if isinstance(sid, str) else int(sid), vec2(size, 'size', imgui.ImVec2(0, 0)),
                                     _flags(child_flags), _flags(window_flags))

        @fn
        def EndChild():
            if B.window_stack:
                B.window_stack.pop()
            imgui.end_child()

        fn_simple = {
            'IsWindowAppearing': imgui.is_window_appearing,
            'IsWindowCollapsed': imgui.is_window_collapsed,
            'SetNextWindowFocus': imgui.set_next_window_focus,
            'GetWindowWidth': imgui.get_window_width,
            'GetWindowHeight': imgui.get_window_height,
            'GetScrollX': imgui.get_scroll_x, 'GetScrollY': imgui.get_scroll_y,
            'GetScrollMaxX': imgui.get_scroll_max_x, 'GetScrollMaxY': imgui.get_scroll_max_y,
            'PopFont': imgui.pop_font, 'GetFont': imgui.get_font, 'GetFontSize': imgui.get_font_size,
            'PopItemFlag': imgui.pop_item_flag, 'PopItemWidth': imgui.pop_item_width,
            'CalcItemWidth': imgui.calc_item_width, 'PopTextWrapPos': imgui.pop_text_wrap_pos,
            'GetCursorPosX': imgui.get_cursor_pos_x, 'GetCursorPosY': imgui.get_cursor_pos_y,
            'Separator': imgui.separator, 'NewLine': imgui.new_line, 'Spacing': imgui.spacing,
            'BeginGroup': imgui.begin_group, 'EndGroup': imgui.end_group,
            'AlignTextToFramePadding': imgui.align_text_to_frame_padding,
            'GetTextLineHeight': imgui.get_text_line_height,
            'GetTextLineHeightWithSpacing': imgui.get_text_line_height_with_spacing,
            'GetFrameHeight': imgui.get_frame_height,
            'GetFrameHeightWithSpacing': imgui.get_frame_height_with_spacing,
            'PopID': imgui.pop_id, 'Bullet': imgui.bullet,
            'EndCombo': imgui.end_combo, 'TreePop': imgui.tree_pop, 'EndListBox': imgui.end_list_box,
            'BeginMenuBar': imgui.begin_menu_bar, 'EndMenuBar': imgui.end_menu_bar,
            'EndMenu': imgui.end_menu, 'BeginTooltip': imgui.begin_tooltip, 'EndTooltip': imgui.end_tooltip,
            'BeginItemTooltip': imgui.begin_item_tooltip,
            'EndPopup': imgui.end_popup, 'CloseCurrentPopup': imgui.close_current_popup,
            'EndTable': imgui.end_table, 'TableNextColumn': imgui.table_next_column,
            'TableHeadersRow': imgui.table_headers_row,
            'TableGetColumnCount': imgui.table_get_column_count,
            'TableGetColumnIndex': imgui.table_get_column_index,
            'TableGetRowIndex': imgui.table_get_row_index,
            'EndTabBar': imgui.end_tab_bar, 'EndTabItem': imgui.end_tab_item,
            'EndDisabled': imgui.end_disabled, 'PopClipRect': imgui.pop_clip_rect,
            'SetItemDefaultFocus': imgui.set_item_default_focus,
            'IsItemActive': imgui.is_item_active, 'IsItemFocused': imgui.is_item_focused,
            'IsItemVisible': imgui.is_item_visible, 'IsItemEdited': imgui.is_item_edited,
            'IsItemActivated': imgui.is_item_activated, 'IsItemDeactivated': imgui.is_item_deactivated,
            'IsItemDeactivatedAfterEdit': imgui.is_item_deactivated_after_edit,
            'IsItemToggledOpen': imgui.is_item_toggled_open,
            'IsAnyItemHovered': imgui.is_any_item_hovered, 'IsAnyItemActive': imgui.is_any_item_active,
            'IsAnyItemFocused': imgui.is_any_item_focused, 'GetItemID': imgui.get_item_id,
            'GetTime': imgui.get_time, 'GetFrameCount': imgui.get_frame_count,
            'IsAnyMouseDown': imgui.is_any_mouse_down,
            'SetNextItemAllowOverlap': imgui.set_next_item_allow_overlap,
            'GetVersion': imgui.get_version,
            'GetTreeNodeToLabelSpacing': imgui.get_tree_node_to_label_spacing,
        }
        for k, f in fn_simple.items():
            F[k] = (lambda f: (lambda: f()))(f)

        @fn
        def SetWindowFocus(name=None):
            if name is None:
                imgui.set_window_focus()
            else:
                imgui.set_window_focus(_str(name, 'name'))

        @fn
        def IsWindowFocused(flags=None):
            return imgui.is_window_focused(_flags(flags))

        @fn
        def IsWindowHovered(flags=None):
            return imgui.is_window_hovered(_flags(flags))

        @fn
        def GetWindowPos():
            return _xy(imgui.get_window_pos())

        @fn
        def GetWindowSize():
            return _xy(imgui.get_window_size())

        @fn
        def SetNextWindowPos(pos, cond=None, pivot=None):
            imgui.set_next_window_pos(vec2(pos, 'pos'), _flags(cond, 'cond'), vec2(pivot, 'pivot'))

        @fn
        def SetNextWindowSize(size, cond=None):
            imgui.set_next_window_size(vec2(size, 'size'), _flags(cond, 'cond'))

        @fn
        def SetNextWindowSizeConstraints(size_min, size_max, callback=None):
            if callback is not None:
                raise BridgeError('SetNextWindowSizeConstraints: the callback argument is not supported by the preview bridge')
            imgui.set_next_window_size_constraints(vec2(size_min, 'size_min'), vec2(size_max, 'size_max'))

        @fn
        def SetNextWindowContentSize(size):
            imgui.set_next_window_content_size(vec2(size, 'size'))

        @fn
        def SetNextWindowCollapsed(collapsed, cond=None):
            imgui.set_next_window_collapsed(bool(collapsed), _flags(cond, 'cond'))

        @fn
        def SetNextWindowScroll(scroll):
            imgui.set_next_window_scroll(vec2(scroll, 'scroll'))

        @fn
        def SetNextWindowBgAlpha(alpha):
            imgui.set_next_window_bg_alpha(float(_num(alpha, 'alpha')))

        @fn
        def SetWindowPos(a, b=None, c=None):
            if isinstance(a, str):
                imgui.set_window_pos(a, vec2(b, 'pos'), _flags(c, 'cond'))
            else:
                imgui.set_window_pos(vec2(a, 'pos'), _flags(b, 'cond'))

        @fn
        def SetWindowSize(a, b=None, c=None):
            if isinstance(a, str):
                imgui.set_window_size(a, vec2(b, 'size'), _flags(c, 'cond'))
            else:
                imgui.set_window_size(vec2(a, 'size'), _flags(b, 'cond'))

        @fn
        def SetScrollX(v):
            imgui.set_scroll_x(float(_num(v)))

        @fn
        def SetScrollY(v):
            imgui.set_scroll_y(float(_num(v)))

        @fn
        def SetScrollHereX(r=None):
            imgui.set_scroll_here_x(0.5 if r is None else float(r))

        @fn
        def SetScrollHereY(r=None):
            imgui.set_scroll_here_y(0.5 if r is None else float(r))

        # Fonts and style stacks -----------------------------------------------------------------
        @fn
        def PushFont(font=None, size=None):
            # In 1.92, size 0 keeps the current size. Ashita's annotation makes the size required.
            imgui.push_font(font, float(_num(size, 'font_size_base_unscaled', 0.0)))

        @fn
        def PushStyleColor(idx, col):
            if _is_table(col):
                imgui.push_style_color(_flags(idx, 'idx'), vec4(col, 'col'))
            else:
                imgui.push_style_color(_flags(idx, 'idx'), _u32(col))

        @fn
        def PopStyleColor(count=None):
            imgui.pop_style_color(int(_num(count, 'count', 1)))

        @fn
        def PushStyleVar(idx, val):
            if _is_table(val):
                imgui.push_style_var(_flags(idx, 'idx'), vec2(val, 'val'))
            else:
                imgui.push_style_var(_flags(idx, 'idx'), float(_num(val, 'val')))

        @fn
        def PushStyleVarX(idx, v):
            imgui.push_style_var_x(_flags(idx, 'idx'), float(_num(v)))

        @fn
        def PushStyleVarY(idx, v):
            imgui.push_style_var_y(_flags(idx, 'idx'), float(_num(v)))

        @fn
        def PopStyleVar(count=None):
            imgui.pop_style_var(int(_num(count, 'count', 1)))

        @fn
        def PushItemFlag(option, enabled):
            imgui.push_item_flag(_flags(option, 'option'), bool(enabled))

        @fn
        def PushItemWidth(w):
            imgui.push_item_width(float(_num(w, 'item_width')))

        @fn
        def SetNextItemWidth(w):
            imgui.set_next_item_width(float(_num(w, 'item_width')))

        @fn
        def PushTextWrapPos(x=None):
            imgui.push_text_wrap_pos(float(_num(x, 'wrap_local_pos_x', 0.0)))

        @fn
        def GetColorU32(a, alpha_mul=None):
            # Ashita lists GetColorU32(idx, alpha_mul) first, so a small number is an ImGuiCol index.
            # A number that can't be an index is treated as a packed color. That part is a guess.
            if _is_table(a):
                return imgui.get_color_u32(vec4(a))
            n = int(_num(a))
            mul = float(_num(alpha_mul, 'alpha_mul', 1.0))
            if 0 <= n < imgui.Col_.count:
                return imgui.get_color_u32(n, mul)
            # Not imgui.get_color_u32(col): an ImU32 below 2^31 binds to its ImGuiCol overload and reads
            # style.Colors out of bounds (segfault). This is ImGui's GetColorU32(ImU32, alpha_mul) body.
            col = n & 0xFFFFFFFF
            mul *= imgui.get_style().alpha
            if mul >= 1.0:
                return col
            alpha = int(((col >> 24) & 0xFF) * mul)
            return (col & 0x00FFFFFF) | (alpha << 24)

        @fn
        def GetStyleColorVec4(idx):
            c = imgui.get_style_color_vec4(_flags(idx, 'idx'))
            return float(c.x), float(c.y), float(c.z), float(c.w)

        # Cursor / layout ---------------------------------------------------------------------------
        @fn
        def GetCursorScreenPos():
            return _xy(imgui.get_cursor_screen_pos())

        @fn
        def SetCursorScreenPos(pos):
            imgui.set_cursor_screen_pos(vec2(pos, 'pos'))

        @fn
        def GetContentRegionAvail():
            return _xy(imgui.get_content_region_avail())

        @fn
        def GetCursorPos():
            return _xy(imgui.get_cursor_pos())

        @fn
        def SetCursorPos(pos):
            imgui.set_cursor_pos(vec2(pos, 'local_pos'))

        @fn
        def SetCursorPosX(x):
            imgui.set_cursor_pos_x(float(_num(x)))

        @fn
        def SetCursorPosY(y):
            imgui.set_cursor_pos_y(float(_num(y)))

        @fn
        def GetCursorStartPos():
            return _xy(imgui.get_cursor_start_pos())

        @fn
        def SameLine(offset_from_start_x=None, spacing=None):
            imgui.same_line(float(_num(offset_from_start_x, 'offset_from_start_x', 0.0)),
                            float(_num(spacing, 'spacing', -1.0)))

        @fn
        def Dummy(size):
            imgui.dummy(vec2(size, 'size'))

        @fn
        def Indent(w=None):
            imgui.indent(float(_num(w, 'indent_w', 0.0)))

        @fn
        def Unindent(w=None):
            imgui.unindent(float(_num(w, 'indent_w', 0.0)))

        @fn
        def PushID(a, b=None):
            if b is not None:
                imgui.push_id(_str(a) + _str(b))
            elif isinstance(a, (int, float)) and not isinstance(a, bool):
                imgui.push_id(int(a))
            else:
                imgui.push_id(_str(a, 'str_id'))

        @fn
        def GetID(a, b=None):
            if b is not None:
                return imgui.get_id(_str(a) + _str(b))
            if isinstance(a, (int, float)) and not isinstance(a, bool):
                return imgui.get_id(int(a))
            return imgui.get_id(_str(a, 'str_id'))

        # Text --------------------------------------------------------------------------------------
        @fn
        def TextUnformatted(text):
            imgui.text_unformatted(_str(text, 'text'))

        @fn
        def Text(text):
            imgui.text_unformatted(_str(text, 'text'))  # Ashita's annotation says "Renders an unformatted text string."

        @fn
        def TextColored(color, text):
            imgui.text_colored(vec4(color, 'color'), _str(text, 'text'))

        @fn
        def TextDisabled(text):
            imgui.text_disabled(_str(text, 'text'))

        @fn
        def TextWrapped(text):
            imgui.text_wrapped(_str(text, 'text'))

        @fn
        def LabelText(label, text):
            imgui.label_text(_str(label), _str(text, 'text'))

        @fn
        def BulletText(text):
            imgui.bullet_text(_str(text, 'text'))

        @fn
        def SeparatorText(label):
            imgui.separator_text(_str(label))

        # Main widgets ------------------------------------------------------------------------------
        @fn
        def Button(label, size=None):
            return imgui.button(_str(label), vec2(size, 'size', imgui.ImVec2(0, 0)))

        @fn
        def SmallButton(label):
            return imgui.small_button(_str(label))

        @fn
        def InvisibleButton(str_id, size, flags=None):
            return imgui.invisible_button(_str(str_id), vec2(size, 'size'), _flags(flags))

        @fn
        def ArrowButton(str_id, direction):
            return imgui.arrow_button(_str(str_id), _flags(direction, 'dir'))

        @fn
        def Checkbox(label, val):
            cur = _slot(val, 'Checkbox value')
            changed, new = imgui.checkbox(_str(label), bool(cur))
            if changed:
                val[1] = new
            return changed

        @fn
        def RadioButton(label, a, v_button=None):
            if _is_table(a):
                cur = int(_num(a[1], 'RadioButton value'))
                changed, new = imgui.radio_button(_str(label), cur, int(_num(v_button, 'v_button')))
                if changed:
                    a[1] = new
                return changed
            return imgui.radio_button(_str(label), bool(a))

        @fn
        def ProgressBar(fraction, size=None, overlay=None):
            imgui.progress_bar(float(_num(fraction, 'fraction')), vec2(size, 'size_arg', imgui.ImVec2(-FLT_MIN_, 0)),
                               None if overlay is None else _str(overlay, 'overlay'))

        # Combo / selectables / lists -----------------------------------------------------------------
        @fn
        def BeginCombo(label, preview_value, flags=None):
            # ImGui takes NULL for "no preview". imgui_bundle wants a str, and '' draws the same.
            preview = '' if preview_value is None else _str(preview_value, 'preview_value')
            return imgui.begin_combo(_str(label), preview, _flags(flags))

        @fn
        def Combo(label, current_item, items, items_count=None, popup_max_height_in_items=None):
            # current_item is taken as the 0-based ImGui index in a one-slot table, and items as a Lua
            # array. That's a guess.
            cur = int(_num(_slot(current_item, 'Combo current_item')))
            if isinstance(items, str):
                names = [s for s in items.split('\0') if s]
                max_h = items_count
            else:
                n = int(_num(items_count, 'items_count', 0)) or len(items)
                names = [_str(items[i + 1], 'item') for i in range(n)]
                max_h = popup_max_height_in_items
            changed, new = imgui.combo(_str(label), cur, names, int(_num(max_h, 'popup_max_height_in_items', -1)))
            if changed:
                current_item[1] = new
            return changed

        @fn
        def Selectable(label, selected=None, flags=None, size=None):
            sz = vec2(size, 'size', imgui.ImVec2(0, 0))
            if _is_table(selected):
                clicked, new = imgui.selectable(_str(label), bool(selected[1]), _flags(flags), sz)
                if clicked:
                    selected[1] = new
                return clicked
            clicked, _ = imgui.selectable(_str(label), bool(selected), _flags(flags), sz)
            return clicked

        @fn
        def BeginListBox(label, size=None):
            return imgui.begin_list_box(_str(label), vec2(size, 'size', imgui.ImVec2(0, 0)))

        # Sliders / drags / inputs ------------------------------------------------------------------
        def _scalar_widget(kind, n):
            is_int = 'Int' in kind

            def conv(v):
                return int(v) if is_int else float(v)

            def widget(label, val, a=None, b=None, c=None, d=None, e=None):
                if not _is_table(val):
                    raise BridgeError('%s: expected a table holding the value(s), got %r' % (kind, val))
                cur = [conv(_num(val[i + 1], '%s value' % kind)) for i in range(n)]
                arg = cur[0] if n == 1 else cur
                lbl = _str(label)
                if kind.startswith('Slider'):
                    vmin, vmax, fmt, flags = a, b, c, d
                    f = getattr(imgui, camel_to_snake(kind))
                    default_fmt = '%d' if is_int else '%.3f'
                    changed, new = f(lbl, arg, conv(_num(vmin, 'v_min', 0)), conv(_num(vmax, 'v_max', 0)),
                                     default_fmt if fmt is None else _str(fmt, 'format'), _flags(flags))
                elif kind.startswith('Drag'):
                    speed, vmin, vmax, fmt, flags = a, b, c, d, e
                    f = getattr(imgui, camel_to_snake(kind))
                    default_fmt = '%d' if is_int else '%.3f'
                    changed, new = f(lbl, arg, float(_num(speed, 'v_speed', 1.0)), conv(_num(vmin, 'v_min', 0)),
                                     conv(_num(vmax, 'v_max', 0)), default_fmt if fmt is None else _str(fmt, 'format'),
                                     _flags(flags))
                else:
                    raise BridgeError(kind)
                if changed:
                    vals = [new] if n == 1 else list(new)
                    for i, v in enumerate(vals):
                        val[i + 1] = v
                return changed
            widget.__name__ = kind
            return widget

        for kind in ('SliderFloat', 'SliderInt', 'DragFloat', 'DragInt'):
            F[kind] = _scalar_widget(kind, 1)
            for n in (2, 3, 4):
                F['%s%d' % (kind, n)] = _scalar_widget('%s%d' % (kind, n), n)

        @fn
        def InputText(label, buffer, buffer_size=None, flags=None, callback=None):
            if callback is not None:
                raise BridgeError('InputText: callbacks are not supported by the preview bridge')
            cur = _slot(buffer, 'InputText buffer')
            changed, new = imgui.input_text(_str(label), '' if cur is None else _str(cur, 'buffer'), _flags(flags))
            if changed:
                buffer[1] = new
            return changed

        @fn
        def InputTextWithHint(label, hint, buffer, buffer_size=None, flags=None, callback=None):
            if callback is not None:
                raise BridgeError('InputTextWithHint: callbacks are not supported by the preview bridge')
            cur = _slot(buffer, 'InputTextWithHint buffer')
            changed, new = imgui.input_text_with_hint(_str(label), _str(hint, 'hint'),
                                                      '' if cur is None else _str(cur, 'buffer'), _flags(flags))
            if changed:
                buffer[1] = new
            return changed

        @fn
        def InputInt(label, val, step=None, step_fast=None, flags=None):
            cur = int(_num(_slot(val, 'InputInt value')))
            changed, new = imgui.input_int(_str(label), cur, int(_num(step, 'step', 1)),
                                           int(_num(step_fast, 'step_fast', 100)), _flags(flags))
            if changed:
                val[1] = new
            return changed

        @fn
        def InputFloat(label, val, step=None, step_fast=None, fmt=None, flags=None):
            cur = float(_num(_slot(val, 'InputFloat value')))
            changed, new = imgui.input_float(_str(label), cur, float(_num(step, 'step', 0.0)),
                                             float(_num(step_fast, 'step_fast', 0.0)),
                                             '%.3f' if fmt is None else _str(fmt, 'format'), _flags(flags))
            if changed:
                val[1] = new
            return changed

        # Color -----------------------------------------------------------------------------------
        def _color_widget(kind, n):
            def widget(label, color, flags=None, ref_color=None):
                if not _is_table(color):
                    raise BridgeError('%s: expected a { r, g, b%s } table, got %r' % (kind, ', a' if n == 4 else '', color))
                cur = [float(_num(color[i + 1], '%s component %d' % (kind, i + 1))) for i in range(n)]
                f = getattr(imgui, camel_to_snake(kind))
                if kind == 'ColorPicker4' and ref_color is not None:
                    raise BridgeError('ColorPicker4: ref_color is not supported by the preview bridge')
                changed, new = f(_str(label), cur, _flags(flags))
                if changed:
                    for i, v in enumerate(list(new)[:n]):
                        color[i + 1] = float(v)
                return changed
            widget.__name__ = kind
            return widget

        for kind, n in (('ColorEdit3', 3), ('ColorEdit4', 4), ('ColorPicker3', 3), ('ColorPicker4', 4)):
            F[kind] = _color_widget(kind, n)

        @fn
        def ColorButton(desc_id, color, flags=None, size=None):
            return imgui.color_button(_str(desc_id), vec4(color, 'color'), _flags(flags), vec2(size, 'size', imgui.ImVec2(0, 0)))

        # Trees / headers -------------------------------------------------------------------------
        @fn
        def TreeNode(a, b=None):
            if b is not None:
                return imgui.tree_node(_str(a), _str(b))
            return imgui.tree_node(_str(a))

        @fn
        def TreeNodeEx(label, flags=None, text=None):
            if text is not None:
                return imgui.tree_node_ex(_str(label), _flags(flags), _str(text))
            return imgui.tree_node_ex(_str(label), _flags(flags))

        @fn
        def TreePush(str_id):
            imgui.tree_push(_str(str_id))

        @fn
        def CollapsingHeader(label, a=None, b=None):
            if _is_table(a):
                shown, visible = imgui.collapsing_header(_str(label), bool(a[1]), _flags(b))
                if not visible:
                    a[1] = False
                return shown
            return imgui.collapsing_header(_str(label), _flags(a))

        @fn
        def SetNextItemOpen(is_open, cond=None):
            imgui.set_next_item_open(bool(is_open), _flags(cond, 'cond'))

        # Menus / tooltips / popups ---------------------------------------------------------------
        @fn
        def BeginMenu(label, enabled=None):
            return imgui.begin_menu(_str(label), True if enabled is None else bool(enabled))

        @fn
        def MenuItem(label, shortcut=None, selected=None, enabled=None):
            sc = None if shortcut is None else _str(shortcut, 'shortcut')
            en = True if enabled is None else bool(enabled)
            if _is_table(selected):
                # imgui_bundle's pointer form wants a str shortcut. ImGui draws '' the same as NULL.
                clicked, new = imgui.menu_item(_str(label), sc or '', bool(selected[1]), en)
                if clicked:
                    selected[1] = new
                return clicked
            return imgui.menu_item_simple(_str(label), sc, bool(selected), en)

        @fn
        def SetTooltip(text):
            imgui.set_tooltip(_str(text, 'text'))

        @fn
        def SetItemTooltip(text):
            imgui.set_item_tooltip(_str(text, 'text'))

        @fn
        def BeginPopup(str_id, flags=None):
            return imgui.begin_popup(_str(str_id), _flags(flags))

        @fn
        def BeginPopupModal(name, p_open=None, flags=None):
            if _is_table(p_open):
                shown, still = imgui.begin_popup_modal(_str(name), bool(p_open[1]), _flags(flags))
                if not still:
                    p_open[1] = False
                return shown
            shown, _ = imgui.begin_popup_modal(_str(name), None, _flags(flags))
            return shown

        @fn
        def OpenPopup(str_id, flags=None):
            imgui.open_popup(_str(str_id), _flags(flags))

        # ImGui's default popup_flags is 1 (right button). An explicit 0 is ImGuiPopupFlags_MouseButtonLeft.
        @fn
        def BeginPopupContextItem(str_id=None, flags=None):
            return imgui.begin_popup_context_item(None if str_id is None else _str(str_id),
                                                  1 if flags is None else _flags(flags))

        @fn
        def BeginPopupContextWindow(str_id=None, flags=None):
            return imgui.begin_popup_context_window(None if str_id is None else _str(str_id),
                                                    1 if flags is None else _flags(flags))

        @fn
        def IsPopupOpen(str_id, flags=None):
            return imgui.is_popup_open(_str(str_id), _flags(flags))

        # Tables ----------------------------------------------------------------------------------
        @fn
        def BeginTable(str_id, columns, flags=None, outer_size=None, inner_width=None):
            return imgui.begin_table(_str(str_id), int(_num(columns, 'columns')), _flags(flags),
                                     vec2(outer_size, 'outer_size', imgui.ImVec2(0, 0)),
                                     float(_num(inner_width, 'inner_width', 0.0)))

        @fn
        def TableNextRow(row_flags=None, min_row_height=None):
            imgui.table_next_row(_flags(row_flags, 'row_flags'), float(_num(min_row_height, 'min_row_height', 0.0)))

        @fn
        def TableSetColumnIndex(column_n):
            return imgui.table_set_column_index(int(_num(column_n, 'column_n')))

        @fn
        def TableSetupColumn(label, flags=None, init_width_or_weight=None, user_id=None):
            imgui.table_setup_column(_str(label), _flags(flags), float(_num(init_width_or_weight, 'init_width_or_weight', 0.0)),
                                     int(_num(user_id, 'user_id', 0)))

        @fn
        def TableSetupScrollFreeze(cols, rows):
            imgui.table_setup_scroll_freeze(int(_num(cols)), int(_num(rows)))

        @fn
        def TableHeader(label):
            imgui.table_header(_str(label))

        @fn
        def TableSetBgColor(target, color, column_n=None):
            imgui.table_set_bg_color(_flags(target, 'target'), _u32(color), int(_num(column_n, 'column_n', -1)))

        # Tab bars --------------------------------------------------------------------------------
        @fn
        def BeginTabBar(str_id, flags=None):
            return imgui.begin_tab_bar(_str(str_id), _flags(flags))

        @fn
        def BeginTabItem(label, p_open=None, flags=None):
            label = _str(label)
            visible = label.split('##')[0].strip()
            fl = _flags(flags)
            B.tabs_seen.append(visible)
            wanted = B.select_tab is not None and (visible.lower() == B.select_tab or label.lower() == B.select_tab)
            if wanted and not B.tab_applied:
                fl |= int(imgui.TabItemFlags_.set_selected)
            if _is_table(p_open):
                shown, still = imgui.begin_tab_item(label, bool(p_open[1]), fl)
                if not still:
                    p_open[1] = False
            else:
                shown, _ = imgui.begin_tab_item(label, None, fl)
            if shown:
                B.tab_open.append(visible)
                if wanted:
                    B.tab_applied = True
            return shown

        @fn
        def TabItemButton(label, flags=None):
            return imgui.tab_item_button(_str(label), _flags(flags))

        @fn
        def SetTabItemClosed(label):
            imgui.set_tab_item_closed(_str(label))

        # Disabled / clipping / items ----------------------------------------------------------------
        @fn
        def BeginDisabled(disabled=None):
            imgui.begin_disabled(True if disabled is None else bool(disabled))

        @fn
        def PushClipRect(clip_min, clip_max, intersect):
            imgui.push_clip_rect(vec2(clip_min, 'clip_rect_min'), vec2(clip_max, 'clip_rect_max'), bool(intersect))

        @fn
        def SetKeyboardFocusHere(offset=None):
            imgui.set_keyboard_focus_here(int(_num(offset, 'offset', 0)))

        @fn
        def IsItemHovered(flags=None):
            return imgui.is_item_hovered(_flags(flags))

        @fn
        def IsItemClicked(button=None):
            return imgui.is_item_clicked(_flags(button, 'mouse_button'))

        @fn
        def GetItemRectMin():
            return _xy(imgui.get_item_rect_min())

        @fn
        def GetItemRectMax():
            return _xy(imgui.get_item_rect_max())

        @fn
        def GetItemRectSize():
            return _xy(imgui.get_item_rect_size())

        @fn
        def IsRectVisible(a, b=None):
            if b is None:
                return imgui.is_rect_visible(vec2(a, 'size'))
            return imgui.is_rect_visible(vec2(a, 'rect_min'), vec2(b, 'rect_max'))

        @fn
        def CalcTextSize(text, hide_text_after_double_hash=None, wrap_width=None):
            v = imgui.calc_text_size(_str(text, 'text'), None, bool(hide_text_after_double_hash),
                                     float(_num(wrap_width, 'wrap_width', -1.0)))
            return _xy(v)

        @fn
        def ColorConvertU32ToFloat4(color):
            c = imgui.color_convert_u32_to_float4(_u32(color))
            return float(c.x), float(c.y), float(c.z), float(c.w)

        @fn
        def ColorConvertFloat4ToU32(color):
            return imgui.color_convert_float4_to_u32(vec4(color, 'color'))

        # imgui_bundle keeps the C++ out-params as inputs (ignored) and returns the three results.
        @fn
        def ColorConvertRGBtoHSV(r, g, b):
            return tuple(imgui.color_convert_rgb_to_hsv(float(_num(r, 'r')), float(_num(g, 'g')), float(_num(b, 'b')),
                                                        0.0, 0.0, 0.0))

        @fn
        def ColorConvertHSVtoRGB(h, s, v):
            return tuple(imgui.color_convert_hsv_to_rgb(float(_num(h, 'h')), float(_num(s, 's')), float(_num(v, 'v')),
                                                        0.0, 0.0, 0.0))

        # Input ------------------------------------------------------------------------------------
        @fn
        def IsKeyDown(key):
            return imgui.is_key_down(imgui.Key(_flags(key, 'key')))

        @fn
        def IsKeyPressed(key, repeat=None):
            return imgui.is_key_pressed(imgui.Key(_flags(key, 'key')), True if repeat is None else bool(repeat))

        @fn
        def IsKeyReleased(key):
            return imgui.is_key_released(imgui.Key(_flags(key, 'key')))

        @fn
        def IsMouseDown(button):
            return imgui.is_mouse_down(_flags(button, 'button'))

        @fn
        def IsMouseClicked(button, repeat=None):
            return imgui.is_mouse_clicked(_flags(button, 'button'), bool(repeat))

        @fn
        def IsMouseReleased(button):
            return imgui.is_mouse_released(_flags(button, 'button'))

        @fn
        def IsMouseDoubleClicked(button):
            return imgui.is_mouse_double_clicked(_flags(button, 'button'))

        @fn
        def IsMouseHoveringRect(r_min, r_max, clip=None):
            return imgui.is_mouse_hovering_rect(vec2(r_min, 'r_min'), vec2(r_max, 'r_max'), True if clip is None else bool(clip))

        @fn
        def GetMousePos():
            return _xy(imgui.get_mouse_pos())

        @fn
        def IsMouseDragging(button, lock_threshold=None):
            return imgui.is_mouse_dragging(_flags(button, 'button'), float(_num(lock_threshold, 'lock_threshold', -1.0)))

        @fn
        def GetMouseDragDelta(button=None, lock_threshold=None):
            return _xy(imgui.get_mouse_drag_delta(_flags(button, 'button'), float(_num(lock_threshold, 'lock_threshold', -1.0))))

        @fn
        def ResetMouseDragDelta(button=None):
            imgui.reset_mouse_drag_delta(_flags(button, 'button'))

        @fn
        def SetMouseCursor(cursor_type):
            imgui.set_mouse_cursor(_flags(cursor_type, 'cursor_type'))

        # Draw lists and objects (wrapped by imgui_bridge.lua) ------------------------------------
        F['GetWindowDrawList'] = lambda: imgui.get_window_draw_list()
        F['GetBackgroundDrawList'] = lambda viewport=None: imgui.get_background_draw_list()
        F['GetForegroundDrawList'] = lambda viewport=None: imgui.get_foreground_draw_list()
        F['GetIO'] = lambda: imgui.get_io()
        F['GetStyle'] = lambda: imgui.get_style()
        F['GetMainViewport'] = lambda: imgui.get_main_viewport()

        # Ashita custom helpers ---------------------------------------------------------------------
        @fn
        def AddFontFromFileTTF(filename, size_pixels):
            path = _str(filename, 'filename')
            font = imgui.get_io().fonts.add_font_from_file_ttf(path, float(_num(size_pixels, 'size_pixels')))
            B.fonts_added.append((path, size_pixels))
            return font

        return F


FLT_MIN_ = 1.175494351e-38


# -- draw list methods (called by imgui_bridge.lua with the imgui_bundle ImDrawList as `dl`) ----------
def _dl_functions():
    D = {}

    def fn(f):
        D[f.__name__] = f
        return f

    @fn
    def AddLine(dl, p1, p2, col, thickness=None):
        dl.add_line(vec2(p1, 'p1'), vec2(p2, 'p2'), _u32(col), float(_num(thickness, 'thickness', 1.0)))

    @fn
    def AddRect(dl, p_min, p_max, col, rounding=None, flags=None, thickness=None):
        dl.add_rect(vec2(p_min, 'p_min'), vec2(p_max, 'p_max'), _u32(col), float(_num(rounding, 'rounding', 0.0)),
                    _flags(flags), float(_num(thickness, 'thickness', 1.0)))

    @fn
    def AddRectFilled(dl, p_min, p_max, col, rounding=None, flags=None):
        dl.add_rect_filled(vec2(p_min, 'p_min'), vec2(p_max, 'p_max'), _u32(col), float(_num(rounding, 'rounding', 0.0)),
                           _flags(flags))

    @fn
    def AddRectFilledMultiColor(dl, p_min, p_max, ul, ur, br, bl):
        dl.add_rect_filled_multi_color(vec2(p_min, 'p_min'), vec2(p_max, 'p_max'), _u32(ul), _u32(ur), _u32(br), _u32(bl))

    @fn
    def AddCircle(dl, center, radius, col, segments=None, thickness=None):
        dl.add_circle(vec2(center, 'center'), float(_num(radius, 'radius')), _u32(col), int(_num(segments, 'num_segments', 0)),
                      float(_num(thickness, 'thickness', 1.0)))

    @fn
    def AddCircleFilled(dl, center, radius, col, segments=None):
        dl.add_circle_filled(vec2(center, 'center'), float(_num(radius, 'radius')), _u32(col), int(_num(segments, 'num_segments', 0)))

    @fn
    def AddTriangleFilled(dl, p1, p2, p3, col):
        dl.add_triangle_filled(vec2(p1), vec2(p2), vec2(p3), _u32(col))

    @fn
    def AddQuadFilled(dl, p1, p2, p3, p4, col):
        dl.add_quad_filled(vec2(p1), vec2(p2), vec2(p3), vec2(p4), _u32(col))

    @fn
    def AddText(dl, a, b, c, d=None, e=None, f=None):
        # AddText(pos, col, text) or AddText(font, font_size, pos, col, text [, wrap_width])
        if _is_table(a):
            dl.add_text(vec2(a, 'pos'), _u32(b), _str(c, 'text'))
        else:
            dl.add_text(a, float(_num(b, 'font_size')), vec2(c, 'pos'), _u32(d), _str(e, 'text'), None,
                        float(_num(f, 'wrap_width', 0.0)))

    @fn
    def PushClipRect(dl, clip_min, clip_max, intersect=None):
        dl.push_clip_rect(vec2(clip_min, 'clip_rect_min'), vec2(clip_max, 'clip_rect_max'), bool(intersect))

    @fn
    def PopClipRect(dl):
        dl.pop_clip_rect()

    return D


DRAW_LIST_FUNCTIONS = _dl_functions()


# -- generic attribute access for GetIO() / GetStyle() / GetMainViewport() proxies ---------------------
def _field_name(obj, key):
    for name in (camel_to_snake(key), key):
        if hasattr(obj, name):
            return name
    raise BridgeError('%s has no field %r (tried %r)' % (type(obj).__name__, key, camel_to_snake(key)))


def _plain(v):
    """ImVec2/ImVec4 results as objects Lua can read .x/.y/.z/.w from (lupa item-indexes anything with
    __getitem__, which ImVec2 has, so it can't be handed over as is)."""
    if isinstance(v, imgui.ImVec2):
        return types.SimpleNamespace(x=float(v.x), y=float(v.y))
    if isinstance(v, imgui.ImVec4):
        return types.SimpleNamespace(x=float(v.x), y=float(v.y), z=float(v.z), w=float(v.w))
    return v


def get_attr(obj, key):
    """Returns (value, kind) for a CamelCase field (mapped to imgui_bundle's snake_case). kind is
    'callable', 'vec' (an ImVec2/ImVec4 field, which imgui_bridge.lua wraps so .x reads and writes go
    through to obj) or 'plain'."""
    v = getattr(obj, _field_name(obj, key))
    if isinstance(v, (imgui.ImVec2, imgui.ImVec4)):
        return None, 'vec'
    if callable(v):
        return None, 'callable'
    return v, 'plain'


def vec_get(obj, key, comp):
    v = getattr(obj, _field_name(obj, key))
    if comp not in ('x', 'y', 'z', 'w') or not hasattr(v, comp):
        raise BridgeError('%s.%s has no component %r' % (type(obj).__name__, key, comp))
    return float(getattr(v, comp))


def vec_set(obj, key, comp, value):
    name = _field_name(obj, key)
    v = getattr(obj, name)
    if comp not in ('x', 'y', 'z', 'w') or not hasattr(v, comp):
        raise BridgeError('%s.%s has no component %r' % (type(obj).__name__, key, comp))
    setattr(v, comp, float(_num(value, '%s.%s' % (key, comp))))
    setattr(obj, name, v)


def set_attr(obj, key, value):
    name = camel_to_snake(key)
    if not hasattr(obj, name):
        raise BridgeError('%s has no field %r' % (type(obj).__name__, key))
    cur = getattr(obj, name)
    if isinstance(cur, imgui.ImVec2):
        value = vec2(value, key)
    elif isinstance(cur, imgui.ImVec4):
        value = vec4(value, key)
    setattr(obj, name, value)


def call_attr(obj, key, *args):
    return _plain(getattr(obj, _field_name(obj, key))(*args))


def file_exists(path):
    return os.path.exists(path)
