"""
The fit gate. Every tab of cadence's settings window has to fit its default size, 920x680, with no
outer scrollbar; each page scrolls below fixed navigation. That goes for every preset, at Ashita's 18 px font, in three states. Shown has the timers
showing. Hidden has /cadence hide on, which adds a line at the top. Off also turns the auto attack and
resting timers off, so the Timers tab adds a note under each of their headings. That's the tallest a
tab gets, and the state 680 was picked for.

Then the overlap pass draws every tab tall enough not to scroll, in each window font at 18 px and in
Ashita's font at 12, 20, 21 and 24 px. overlap_probe.lua logs any item that runs into another one and
any dropdown too narrow for the choice it shows.

Each check runs the whole addon in preview.py and saves its PNG in ../out/fit/. A render that hits the
preview's known flake runs once more.

    python fit_gate.py [--addon DIR] [--jobs N]

The tabs, presets and window fonts come from the addon itself, so a new one gets checked with no change
here. The exit code is 1 when a tab doesn't fit, something overlaps or a check fails.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
TESTS = os.path.dirname(HERE)
ADDON = os.path.join(os.path.dirname(TESTS), 'cadence')
OUT = os.path.join(TESTS, 'out', 'fit')
PREVIEW = os.path.join(HERE, 'preview.py')
PROBE = os.path.join(HERE, 'overlap_probe.lua').replace('\\', '/')
ASHITA_LIBS = os.environ.get('ASHITA_LIBS', r'C:/Games/PhoenixXI/addons/libs').replace('\\', '/')

WIDTH, HEIGHT = 920, 680
STATES = ('shown', 'hidden', 'off')

# The preview's known flake. Lua gets the wrong imgui_bundle object, like an ImFont for GetIO(), or the
# run dies with an access violation (0xC0000005). preview.py keeps Lua's garbage collector out of the
# middle of a frame to prevent it. A render that fails like that anyway runs once more, so a flake can't
# pass for a real failure. A real one fails the second time too.
FLAKE = re.compile(r'has no (field|attribute)')
ACCESS_VIOLATION = 3221225477

# The overlap pass's screen and window, tall enough that no tab scrolls at 24 px. Every window font is
# drawn at 18 px, and Ashita's at these sizes too.
TALL_SCREEN = (1600, 1360)
TALL_WINDOW = (WIDTH, 1300)
ASHITA_SIZES = (12, 20, 21, 24)

# Runs the addon in the tests' mock with /cadence hide on and draws one frame of the settings window. The
# mock opens every tab. It hands back the label of every tab, the id of every preset and window font, and
# the line cadence printed if the drawing broke, since the tabs after the break would be missing.
FIND_TABS_PRESETS_AND_FONTS = r'''
dofile(ADDON_DIR .. '/cadence.lua')
MOCK.fire('load')
MOCK.now = 100
MOCK.fire('command', { command = '/cadence hide' })
MOCK.fire('command', { command = '/cadence' })
MOCK.imgui_calls = {}
MOCK.record_imgui = true
MOCK.frame(1 / 60)
MOCK.record_imgui = false
local tabs = {}
for _, call in ipairs(MOCK.imgui_calls) do
    if (call[1] == 'BeginTabItem') then
        local label = call[2]:gsub('##.*', '')
        tabs[#tabs + 1] = label:match('^%s*(.-)%s*$')
    end
end
local broke = nil
for _, line in ipairs(MOCK.printed) do
    if (line:find('Drawing stopped', 1, true)) then broke = line end
end
local fonts = {}
for _, entry in ipairs(require('ui.window_font').LIST) do fonts[#fonts + 1] = entry.id end
return table.concat(tabs, '\n'), table.concat(require('ui.presets').IDS, '\n'), table.concat(fonts, '\n'), broke
'''


def find_tabs_presets_and_fonts(addon):
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    L.execute("package.path = [[%s/?.lua;%s/?.lua;]] .. package.path" % (addon, TESTS.replace('\\', '/')))
    L.execute("package.path = package.path .. [[;%s/?.lua]]" % ASHITA_LIBS)
    install = tempfile.mkdtemp(prefix='cadence_fit_')
    try:
        L.globals().MOCK_INSTALL_PATH = install
        L.globals().ADDON_DIR = addon
        L.execute(open(os.path.join(TESTS, 'mock_ashita.lua'), encoding='utf-8').read())
        tabs, ids, fonts, broke = L.execute(FIND_TABS_PRESETS_AND_FONTS)
    finally:
        shutil.rmtree(install, ignore_errors=True)
    return [t for t in tabs.split('\n') if t], [i for i in ids.split('\n') if i], \
        [f for f in fonts.split('\n') if f], broke


def render(cmd):
    """Runs preview.py, and runs it again when it hit the known flake."""
    run = subprocess.run(cmd, capture_output=True, text=True)
    if run.returncode == ACCESS_VIOLATION or (run.returncode != 0 and FLAKE.search(run.stdout + run.stderr)):
        run = subprocess.run(cmd, capture_output=True, text=True)
    return run


def setup(preset, state):
    """Lua for preview.py's --exec. It picks the preset with its command and stops if it didn't go on. Hidden
    and off hide the timers, and off turns two of them off with their commands and stops if they're still on."""
    lua = ("MOCK.fire('command', { command = '/cadence preset %s' }) "
           "assert(settings.style.window_look == '%s', 'the %s preset did not go on') " % (preset, preset, preset))
    if state != 'shown':
        lua += "MOCK.fire('command', { command = '/cadence hide' }) "
    if state == 'off':
        lua += ("MOCK.fire('command', { command = '/cadence attack off' }) "
                "MOCK.fire('command', { command = '/cadence resting off' }) "
                "assert(not settings.attack.enabled and not settings.resting.enabled, 'the timers did not go off') ")
    return lua


def check(addon, tab, preset, state):
    name = '%s_%s%s.png' % (tab.replace(' ', '_'), preset, '' if state == 'shown' else '_' + state)
    script = setup(preset, state)
    # Every page scrolls below fixed navigation. Hidden timers add a notice above it, so the
    # available page height must shrink while the outer window stays fixed.
    script += """
local imgui = require('imgui')
local text, child = imgui.TextUnformatted, imgui.BeginChild
imgui.TextUnformatted = function(words, ...)
    if words == 'The timers are hidden.' then PREVIEW_PY.log('hidden_notice_drawn') end
    return text(words, ...)
end
imgui.BeginChild = function(id, size, ...)
    if tostring(id):find('##page_', 1, true) then PREVIEW_PY.log('page_height=' .. size[2]) end
    if id == '##estimate_details' then PREVIEW_PY.log('details_height=' .. size[2]) end
    return child(id, size, ...)
end
"""
    cmd = [sys.executable, PREVIEW, '--addon', addon, '--out', os.path.join(OUT, name), '--full', '--tab', tab,
           '--window-size', str(WIDTH), str(HEIGHT), '--exec', script]
    run = render(cmd)
    lines = run.stdout.strip().splitlines()
    line = lines[-1] if lines else '(no output)'
    size = re.search(r' size=(\d+)x(\d+)', line)
    content = re.search(r' content=(\d+)x(\d+)', line)
    problems = []
    if run.returncode != 0:
        problems.append('the render failed')
    elif size is None or (int(size.group(1)), int(size.group(2))) != (WIDTH, HEIGHT):
        problems.append('not drawn at %dx%d' % (WIDTH, HEIGHT))
    if ' scrollbar=' in line:
        problems.append('SCROLLBAR')
    child_heights = re.findall(r'details_height=([0-9.]+)', run.stderr)
    page_heights = re.findall(r'page_height=([0-9.]+)', run.stderr)
    return {
        'tab': tab, 'preset': preset, 'state': state, 'line': line, 'problems': problems,
        'height': int(content.group(2)) if content else None,
        'details_height': float(child_heights[-1]) if child_heights else None,
        'page_height': float(page_heights[-1]) if page_heights else None,
        'hidden_notice': 'hidden_notice_drawn' in run.stderr,
        'warnings': [line for line in run.stderr.strip().splitlines()
                     if 'hidden_notice_drawn' not in line and 'details_height=' not in line and 'page_height=' not in line],
    }


def overlaps(addon, tab, font, size):
    """Draws a tab tall in a window font with the overlap probe. Every line the probe logged is a problem."""
    name = 'overlap_%s_%s%d.png' % (tab.replace(' ', '_'), font, size)
    # Expanded pages need enough height to inspect every row below the fixed navigation.
    height = {'Appearance': 4200, 'Timers': 2600, 'Enemy': 2600, 'Profiles': 2200}.get(tab, TALL_WINDOW[1])
    screen = (TALL_SCREEN[0], height + 60)
    window = (WIDTH, height)
    cmd = [sys.executable, PREVIEW, '--addon', addon, '--out', os.path.join(OUT, name), '--full', '--tab', tab,
           '--size', str(screen[0]), str(screen[1]),
           '--window-size', str(window[0]), str(window[1]),
           '--set', 'window_style.font=%s' % font, '--set', 'window_style.font_size=%d' % size,
           '--exec', "dofile('%s')" % PROBE]
    run = render(cmd)
    lines = run.stdout.strip().splitlines()
    line = lines[-1] if lines else '(no output)'
    logged = [text[len('log: '):] for text in run.stderr.splitlines() if text.startswith('log: ')]
    count = [text for text in logged if re.match(r'items=\d+ problems=\d+$', text)]
    problems = []
    if run.returncode != 0:
        problems.append('the render failed')
    elif not count:
        problems.append('the probe logged nothing')
    elif count[-1].startswith('items=0 '):
        problems.append('the probe saw no items')
    elif not count[-1].endswith(' problems=0'):
        problems.append(count[-1])
    return {
        'tab': tab, 'font': font, 'size': size, 'line': line, 'problems': problems,
        'found': [text for text in logged if text not in count],
        'warnings': [text for text in run.stderr.strip().splitlines() if not text.startswith('log: ')],
    }


def main(argv=None):
    p = argparse.ArgumentParser(description='Checks that every tab of the settings window fits at %dx%d.' % (WIDTH, HEIGHT))
    p.add_argument('--addon', default=ADDON, help='addon folder, default ../../cadence')
    p.add_argument('--jobs', type=int, default=4, help='renders at once, default 4')
    args = p.parse_args(argv)
    addon = os.path.abspath(args.addon).replace('\\', '/')
    tabs, presets, fonts, broke = find_tabs_presets_and_fonts(addon)
    if broke:
        print('The settings window broke while the tabs were being found, so some could be missing.\n    %s' % broke)
        return 1
    if not tabs or not presets or not fonts:
        print('No tabs, presets or window fonts found (tabs %s, presets %s, fonts %s).' % (tabs, presets, fonts))
        return 1
    print('Checking the tabs %s in the presets %s, then in the window fonts %s.\n' % (
        ', '.join(tabs), ', '.join(presets), ', '.join(fonts)))
    os.makedirs(OUT, exist_ok=True)

    runs = [(tab, preset, state) for tab in tabs for preset in presets for state in STATES]
    # The addon lists Ashita's font first.
    sizes = [(font, 18) for font in fonts] + [(fonts[0], size) for size in ASHITA_SIZES]
    probes = [(tab, font, size) for tab in tabs for font, size in sizes]
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(lambda r: check(addon, *r), runs))
        probed = list(pool.map(lambda r: overlaps(addon, *r), probes))

    shown = {(r['tab'], r['preset']): r for r in results if r['state'] == 'shown'}
    for r in results:
        other = shown[(r['tab'], r['preset'])]
        if r['state'] == 'hidden':
            if not r['hidden_notice'] or r['page_height'] is None or other['page_height'] is None \
                    or r['page_height'] >= other['page_height']:
                r['problems'].append('the page did not make room for the hidden notice')
        print('%-14s %-12s %-7s %-6s %s' % (r['tab'], r['preset'], r['state'],
                                           r['height'] if r['height'] is not None else '-',
                                           ', '.join(r['problems']) or 'fits'))
        if r['problems']:
            print('    ' + r['line'])
        for warning in r['warnings']:
            print('    ' + warning)

    measured = [r for r in results if r['height'] is not None]
    if measured:
        tallest = max(measured, key=lambda r: r['height'])
        how = {'shown': '', 'hidden': ' with the timers hidden', 'off': ' with two timers off and hidden'}
        print('\nThe tallest is %s in %s%s, %d px of content.\n' % (
            tallest['tab'], tallest['preset'], how[tallest['state']], tallest['height']))

    for r in probed:
        print('%-14s %-12s %-7s %s' % (r['tab'], r['font'], '%d px' % r['size'], ', '.join(r['problems']) or 'clear'))
        if r['problems']:
            print('    ' + r['line'])
        for found in r['found']:
            print('    ' + found)
        for warning in r['warnings']:
            print('    ' + warning)

    checks = results + probed
    failed = sum(1 for r in checks if r['problems'])
    print('\n' + ('%d of %d checks failed.' % (failed, len(checks)) if failed
                  else 'Every tab fits and nothing overlaps, %d checks.' % len(checks)))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
