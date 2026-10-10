cadence settings window preview
===============================

Renders cadence's real settings window (the addon's own Lua, unmodified) with real Dear ImGui 1.92.3
(imgui_bundle) in a hidden window, and saves a PNG cropped to the settings window.

It runs on the tests' venv (see ../README.txt). It needs lupa, imgui_bundle 1.92.3, pillow, numpy and
munch. The first run pulls Ashita's Agave font out of Ashita.dll into fonts/. Ashita's libs and
Ashita.dll come from ASHITA_LIBS like the tests (default C:/Games/PhoenixXI/addons/libs, with the DLL
two folders up).


Usage
-----

  python preview.py --addon <addon folder> --out <png> [options]

  --addon DIR          folder with cadence.lua, ui/, core/ (read only, never written).
                       Defaults to ../../cadence.
  --out PNG            where the PNG goes (not written when the run fails)
  --tab NAME           tab to show, matched to the visible tab label, any case ("Timers", "Appearance").
                       Selects the matching wrapping navigation button. The run fails if
                       no tab has that label, and lists the labels it saw.
  --size W H           game screen size (ImGui display size), default 1600 1200
  --frames N           frames drawn before the screenshot, default 4. Auto-fit windows are hidden on
                       their first frame, so use 2 or more.
  --set key.path=val   change a settings value before drawing (repeatable). Paths start at the
                       settings table: style.scale=1.5, attack.width=300, window.width=640.
                       A value can be 12, 0.5, true, false, nil, #rrggbb or #rrggbbaa (a color
                       table) or 1,0.5,0,1 (a list table). Anything else is a string. Missing parent
                       tables are created, with a warning.
  --window-size W H    force the settings window to W x H every frame, like a user dragging its
                       corner. Size constraints the addon sets still apply.
  --window TEXT        crop to the window whose name contains TEXT (default: the biggest window
                       whose name doesn't start with ##)
  --margin PX          pixels kept around the window in the crop, default 10
  --no-crop            save the whole screen
  --full               run the whole addon instead: dofile cadence.lua, fire 'load', run
                       "/cadence", then fire d3d_present each frame. The HUD timers draw too
                       (with sample values), and cadence's own pcall is watched for errors.
  --exec LUA           Lua run after the settings load and --set, before the first frame.
                       `settings` is the settings table. Repeatable.
  --script LUA_FILE    draw this Lua file instead of the settings window (the addon still loads, so
                       require('ui.theme') etc. work). The file returns a function called once per
                       frame. It can call PREVIEW.log(...) and read PREVIEW.frame / PREVIEW.last_frame.
                       The last frame's log lines go to stderr as "log: ...". Use --window to pick
                       the window to crop to. table_probe.lua is one, a probe for tables, SameLine
                       and text wrapping.
  --font PATH          default ImGui font (default: fonts/Agave_Regular.ttf, Ashita's own)
  --font-size PX       default font size, default 18 (Ashita's)

Examples

  python preview.py --tab Timers --out timers.png
  python preview.py --tab Appearance --out look_big.png --set style.scale=1.5
  python preview.py --tab Timers --out wide.png --window-size 900 480
  python preview.py --tab Timers --out small_screen.png --size 1280 720

  --addon defaults to the project's addon folder (../../cadence).


Fit gate
--------

  python fit_gate.py [--addon DIR] [--jobs N]

Checks that every tab of the settings window fits its default size, 920x680, with no outer scrollbar.
Pages scroll below fixed navigation. Each tab is drawn in every preset at Ashita's 18 px font in three states. Shown has the timers showing.
Hidden has /cadence hide on, which adds a line at the top. Off is hidden with the auto attack and
resting timers turned off too, so the Timers tab adds a note under each of their headings. That's the
tallest a tab gets, and the state 680 was picked for. Each check runs the whole addon (--full), picks
the preset with /cadence preset and stops if it didn't go on, then stops if the timers didn't go off.

Then the overlap pass draws every tab 920 wide, in a window tall enough to show every control.
Appearance is 4200 tall, Timers 2600, Profiles 2200 and the other tabs 1300. Every group is opened for
this inspection. Each runs in every window font at 18 px and in Ashita's font at 12, 20, 21 and 24 px.
overlap_probe.lua runs with --exec. The desktop can cap a tall screenshot's pixel height, but the probe
still checks every submitted control rectangle. Inspect normal-size captures for the visible result.
It logs each item that runs into another one and each closed dropdown too narrow for the choice it
shows, like a font name cut off. Items in tips and open lists don't count. The PNGs go in ../out/fit/.

The tabs, presets and window fonts come from the addon. The gate runs it once in the tests' mock,
which opens every tab, and reads the tab labels it drew, presets.IDS and window_font.LIST. So a new
tab, preset or window font gets checked with no change to the gate. If the window breaks in the mock,
the gate stops there, since the tabs after the break would be missing.

A render that hits the preview's known flake runs once more. That's Lua handed the wrong object, like
an ImFont for GetIO() ("has no field" or "has no attribute"), or an access violation. A real failure
fails the second time too.

Each line gives the tab, the preset, the state, the content height, and "fits" or what went wrong. A
check fails on an outer scrollbar, a failed render, or a window not drawn at 920x680. Each page
uses a clipped scrolling child: its hidden check verifies the notice draws and the child shrinks,
and overlap checks measure the child rectangle against the surrounding controls. Then come
the tallest tab and a line for each tab, font and size of the overlap pass, with "clear" or the count
and each thing the probe found under it. An overlap check fails on anything found, a failed render or
a probe that saw nothing. The last line counts the failures. The exit code is 1 when any check failed.
--jobs is how many renders run at once, 4 by default.


Output
------

stdout is one line:

  OK window='cadence##cadence_settings' pos=(120,10) size=920x680 content=892x557 tab=Timers
     screen=1600x1200 frames=4 font=Agave_Regular.ttf crop=(110, 0, 1050, 670) out=timers.png

  size     the window's outer size on the last frame
  content  ImGui's content size (what the cursor reached, without padding and decorations)
  scrollbar=y / x   shown when the window has a scrollbar
  tab      the tab(s) whose BeginTabItem returned true on the last frame
  warnings=N        count of warnings, each printed on stderr as "warning: ..."

On failure the line starts with FAIL, ends with "error: <first error>" (the others are on stderr as
"error: ..."), no PNG is written and the exit code is 1 (2 for a missing addon folder).
A run fails on a Lua error in the addon, an ImGui assert (IM_ASSERT, raised by imgui_bundle), a call
to an imgui function the bridge doesn't have, a bad argument shape (like Checkbox given true instead
of { true }), ImGui stacks left unbalanced by the draw (Push without Pop), --tab never opening, and in
--full mode cadence reporting "Drawing stopped after an error".
It only warns, with exit 0, on an ImGui constant the addon names that Ashita's libs/imgui.lua doesn't
define (nil in game, found by scanning the addon's .lua files and again when the line runs), the
window running off the screen (crop clipped), the window still hidden on the last frame, and --set
creating tables.


How it works
------------

preview.py          CLI, Lua setup, hello_imgui run (hidden window, OpenGL), screenshot, crop.
imgui_bridge.py     Ashita GuiManager functions -> imgui_bundle, with Ashita's argument shapes.
imgui_bridge.lua    builds the GuiManager stand-in (unknown names raise
                    "imgui bridge: imgui.X is not implemented by the preview bridge"), wraps draw
                    lists, GetIO(), GetStyle(), GetMainViewport(), then loads Ashita's real
                    C:/Games/PhoenixXI/addons/libs/imgui.lua on top of it, like the game does. So
                    imgui.col32, FLT_MAX, ShowHelp and the ICON_FA globals are Ashita's own.
imgui_enums.py      exact C enum names from imgui_bundle's .pyi stubs ("# ImGuiCol_Text ... original
                    C++ signature" comments), so ResizeNS, DisplayRGB, COUNT come out right.
extract_ashita_fonts.py   pulls the fonts compiled into Ashita.dll (ImGui base85 + stb compressed):
                    Agave Regular and Font Awesome 7. preview.py runs it by itself if fonts/ is empty.
fit_gate.py         the fit gate above. It runs preview.py once for each tab, preset and state, then
                    once for each tab, window font and size of the overlap pass.
overlap_probe.lua   the overlap pass's probe. It wraps the imgui calls the settings window draws with.
selftest/           selftest.py builds scratch addon copies with small fixture windows and checks
                    19 cases (tables, combo, disabled, wrap, resize and min-size constraints,
                    GetIO/GetStyle/viewport proxies, draw lists, packed colors, --script, every
                    failure path above, Lua's garbage collector running only between frames, and
                    each run's own folder). Then it checks 4 times that fit_gate.py runs a render
                    once more after the known flake, and only then.
                    Run it with python selftest\selftest.py [--addon DIR].

Everything else comes from ../mock_ashita.lua, loaded the same way ../run.py does. The
settings the window edits are MOCK.settings.current (settings.load(defaults.make()), like cadence.lua).
Each run gets its own folder in %TEMP% for the files the addon writes, like profiles.json and
shared_layout.json, and for ImGui's ini file. It's deleted when the run ends, so no run sees another's
files, even with the fit gate's runs going at once.

Lua's garbage collector is stopped while the addon loads and while each frame draws, and does a full
collection before each frame. If it runs in the middle of a frame, lupa now and then gives Lua the
wrong imgui_bundle object, like an ImFont for GetIO(), or the run dies with an access violation. That
happens in about half the runs of 60 frames. Keeping Python references to every object handed to
Lua doesn't stop it.
hud.load_fonts() runs in hello_imgui's font callback. It loads the fonts it finds in C:\Windows\Fonts
through the bridge's AddFontFromFileTTF, since ashita.fs.exists checks real files here. If it finds
none, there's a warning and the Font list only has Ashita's font. window_font.load_all() runs there
too, so --set window_style.font=segoeui --set window_style.font_size=24 draws the settings window in
Segoe UI at 24 px the way the game would.

Default mode calls settings_window.draw(settings, addon.version) directly each frame, with the
version read from cadence.lua. --full drives the whole addon instead.

ImGui starts from its default style plus StyleColorsDark (hello_imgui's theme is undone before the
first frame), FontSizeBase 18, font scale 1 and framebuffer scale 1. There's no ini file, so every
run is ImGui's first use of the window and FirstUseEver positions and sizes apply. The mouse is
off-screen, so nothing is hovered. Error recovery asserts are on. The background behind the window
is a dark blue-grey (19, 22, 26).


Enum values
-----------

Names come from Ashita's libs/imgui.lua. Values come from imgui_bundle, so a flag means the same
thing to the ImGui drawing the preview. They agree everywhere except ImGuiStyleVar: imgui_bundle's
ImGui carries an extra ImGuiStyleVar_LayoutAlign (its stack-layout patch) at 24, so TabRounding and
everything after it is one higher than in Ashita (Ashita TabRounding = 24, bundle 25). Mapping by name
handles that. An addon that pushed a style var by raw number would get the wrong var here.


Binding semantics that are guesses
----------------------------------

These were checked against annotations/SDK/IGuiManager.lua, but not against Ashita's C++ binding,
which isn't available.

- Begin, BeginTabItem and BeginPopupModal given a boolean instead of a table (hud.lua passes true)
  get no close button. A table { bool } gets a close button and is set false when clicked.
- Out-param tables are written back only when ImGui reports a change.
- GetColorU32(number) takes a number below ImGuiCol_COUNT as a color index and anything else as a
  packed color. The packed color is worked out in Python with ImGui's own formula, because
  imgui_bundle binds an ImU32 below 2^31 to its ImGuiCol overload, which reads out of bounds and
  crashes the preview.
- Combo(label, { index }, items, count) takes ImGui's 0-based index and a Lua array of items.
- Text / labels given a number are converted like Lua's tostring (%.14g for non-integers). sol2
  probably does the same.
- Text, TextColored, TextDisabled, TextWrapped, SetTooltip and the like are never printf-formatted
  ("100%" draws as is), matching Ashita's "Renders an unformatted text string".
- PushFont(font) with no size passes 0, which keeps the current size in 1.92.
- Packed colors are masked to 32 bits (LuaJIT bit ops return them negative).
- BeginChild with a boolean child_flags is rejected on purpose (untested with the 1.92 binding).


Known gaps
----------

- Ashita's own default ImGui style isn't known. ImGui's default dark style is assumed. cadence pushes
  nearly every color and the spacing it cares about, so this only shows in things it doesn't push
  (ItemInnerSpacing, ScrollbarSize, IndentSpacing, table borders...).
- Ashita keeps window positions/sizes in config\imgui.ini for windows without NoSavedSettings. The
  preview always shows first use.
- No input: nothing is hovered, pressed or dragged, so hover colors, open combos/popups and the
  resize grip highlight never show. IsItemDeactivatedAfterEdit etc. are always false.
- Font rasterizing is imgui_bundle's (stb_truetype, OpenGL). The game draws through Direct3D 8 via
  dgVoodoo, so edge anti-aliasing can differ slightly. Glyph metrics and layout are the same font.
- The game screen size is whatever --size says. The real one is the user's resolution.
- These aren't bridged and raise the clear error if called: callbacks (size constraints, InputText),
  multi-select, drag and drop, docking, plots, images, ListBox(), Value(), logging, clipboard, ini
  functions, and draw-list calls other than AddLine, AddRect, AddRectFilled, AddRectFilledMultiColor,
  AddCircle(Filled), AddTriangleFilled, AddQuadFilled, AddText and Push/PopClipRect.
- GetStyle().Colors[...] isn't bridged (imgui_bundle has no plain colors array). Use
  GetStyleColorVec4 instead. io.Fonts methods aren't bridged either.


Measured table-cell behavior (table_probe.lua, cadence's theme pushed, ImGui 1.92.3)
------------------------------------------------------------------------------------

Window 800 wide at x=40, WindowPadding.x 14, BeginTable('##probe', 2, 0): stretch columns,
cells at screen x 54..428 and 452..826 (cadence's CellPadding.x 12 each side, so a 24 px gap).

- SameLine(200) in a cell: lands at cell start + 186, which is 200 minus WindowPadding.x, the same
  place relative to the cell as SameLine(200) is to the window's content outside a table.
- SameLine(GetCursorPosX() + N) in a cell: GetCursorPosX() is window-local (412 at the start of
  the 2nd cell), so in the 2nd column this lands at cell start + 398 + N, off the cell (clipped).
- Separator in a cell spans only that cell: x 54..428 and 452..826 (checked by pixel too).
- GetContentRegionAvail in a cell: x is the cell's width to its right edge (374). y is what's left
  of the window's height, not a cell height.
- PushTextWrapPos(0) in a cell wraps at the cell's right edge (text 370 wide, CalcTextSize with
  wrap_width = avail gives the same 370x54). PushTextWrapPos(GetCursorPosX() + 150) in a cell
  works too (window-local x), wrapping at 150.
- SetNextWindowSizeConstraints({600,300},{1000,FLT_MAX}) on a resizable window: --window-size
  400 200 gives 600x300, 1400 900 gives 1000x900. On an AlwaysAutoResize window a min {500,0}
  widens the auto-fit size to 500.

Checkmate UI port scenes
------------------------

  python preview.py --tab Details --script port_scene.lua --out details.png
  python preview.py --tab Timers --script port_scene.lua --exec "SCENE_MODE = 'search'" --out search.png
  python preview.py --script port_scene.lua --exec "SCENE_MODE = 'hover'" --no-crop --size 900 480 --frames 8 --out hover.png

These scenes use synthetic evidence and mouse positions. They verify rendering, not live gameplay.
The fit gate keeps navigation outside each scrolling page, checks that the hidden-timer notice
reduces the page height, and checks control overlaps inside pages in every supported window font.
