"""
ImGui enum constants for the preview, named the way Ashita's libs/imgui.lua names them.

imgui_bundle exposes enums as Python classes with snake_case members (imgui.Col_.tab_dimmed_selected).
The .pyi stubs keep each member's original C++ line as a comment ("# ImGuiCol_TabDimmedSelected,"),
so the exact C names are read from there instead of being guessed from the snake_case spelling
(which would get ImGuiMouseCursor_ResizeNS, ImGuiColorEditFlags_DisplayRGB, ImGuiCol_COUNT wrong).
"""
import os
import re

import imgui_bundle
from imgui_bundle import imgui

_CLASS_RE = re.compile(r'^class (\w+)\(enum\.(?:IntFlag|IntEnum|Enum|Flag)\):')
_CPP_RE = re.compile(r'^\s+#\s*((?:ImGui|ImDraw|ImFont|ImTexture)\w*?_\w+)\b[^/]*/\* original C\+\+ signature \*/')
_MEMBER_RE = re.compile(r'^\s{4}(\w+)\s*=')


def _stub_paths():
    base = os.path.join(os.path.dirname(imgui_bundle.__file__), 'imgui')
    paths = [os.path.join(base, '__init__.pyi'), os.path.join(base, 'internal.pyi')]
    return [p for p in paths if os.path.exists(p)]


def bundle_enums():
    """Returns {C name: int value} for every enum member in imgui_bundle's imgui (public first,
    then imgui.internal for names the public module doesn't have)."""
    out = {}
    for path in _stub_paths():
        module = imgui if path.endswith('__init__.pyi') else imgui.internal
        cls_name, pending = None, None
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                m = _CLASS_RE.match(line)
                if m:
                    cls_name, pending = m.group(1), None
                    continue
                if cls_name is None:
                    continue
                if line and not line[0].isspace() and line.strip():
                    cls_name, pending = None, None
                    continue
                m = _CPP_RE.match(line)
                if m:
                    pending = m.group(1)
                    continue
                m = _MEMBER_RE.match(line)
                if m and pending:
                    cls = getattr(module, cls_name, None)
                    member = getattr(cls, m.group(1), None) if cls is not None else None
                    if member is not None and pending not in out:
                        try:
                            out[pending] = int(member)
                        except (TypeError, ValueError):
                            pass
                    pending = None
    return out
