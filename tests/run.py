"""
Runs cadence's offline tests. Each test file runs in a fresh LuaJIT (lupa) with the mock of Ashita in
mock_ashita.lua, loading the real addon from ../cadence.

    python run.py                    every test_*.lua in this folder
    python run.py test_window.lua    just the ones named

A test fails when it raises an error or prints a line like "2 FAILED". The exit code is 1 when any
test failed.

json.lua comes from the Phoenix install's Ashita libs. Settings and imgui are mocked in
mock_ashita.lua. Set ASHITA_LIBS to point somewhere else.
"""
import glob
import os
import re
import shutil
import sys
import tempfile

from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(os.path.dirname(HERE), 'cadence')
ASHITA_LIBS = os.environ.get('ASHITA_LIBS', r'C:/Games/PhoenixXI/addons/libs')

FAILED_LINE = re.compile(r'^\d+ FAILED$', re.MULTILINE)


def lua_path(path):
    return path.replace('\\', '/')


# A fresh LuaJIT with the mock loaded. Files the addon writes, like its settings, go under `install`.
def runtime(install):
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    L.execute("package.path = [[%s/?.lua;%s/?.lua;]] .. package.path" % (lua_path(ADDON), lua_path(HERE)))
    L.execute("package.path = package.path .. [[;%s/?.lua]]" % lua_path(ASHITA_LIBS))
    os.makedirs(os.path.join(install, 'config', 'addons', 'cadence'), exist_ok=True)
    L.globals().MOCK_INSTALL_PATH = install
    L.globals().ADDON_DIR = lua_path(ADDON)
    L.execute(open(os.path.join(HERE, 'mock_ashita.lua'), encoding='utf-8').read())
    return L


def main(names):
    tests = names or sorted(os.path.basename(p) for p in glob.glob(os.path.join(HERE, 'test_*.lua')))
    failures = 0
    # Each run gets its own folder in %TEMP% for what the addon writes, so two runs at once can't
    # break each other. It's deleted at the end.
    install = tempfile.mkdtemp(prefix='cadence_tests_')
    try:
        for test in tests:
            L = runtime(install)
            src = open(os.path.join(HERE, test), encoding='utf-8').read()
            try:
                out = L.execute(src)
            except Exception as ex:
                failures += 1
                print(f'!! {test} FAILED: {ex}')
                continue
            print(f'== {test}')
            print(out if out is not None else '(no output)')
            if out is not None and FAILED_LINE.search(str(out)):
                failures += 1
    finally:
        shutil.rmtree(install, ignore_errors=True)
    print(f'\n{len(tests) - failures} of {len(tests)} test files passed.')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
