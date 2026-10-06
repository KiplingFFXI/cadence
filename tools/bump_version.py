"""
Adds one to the last number of addon.version in cadence\\cadence.lua and gives CHANGELOG.md a section for it.

    python tools\\bump_version.py "First line of the section." [BULLETS_FILE]

Those are the only two places that name the version. The new section goes above the newest one. It holds the
line, then the bullets from the file as they are. The script prints the new version and nothing else.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON_LUA = os.path.join(ROOT, 'cadence', 'cadence.lua')
CHANGELOG = os.path.join(ROOT, 'CHANGELOG.md')

# The version line in the addon header, like addon.version = '1.0.0'.
VERSION_LINE = re.compile(r"^(addon\.version\s*=\s*')(\d+)\.(\d+)\.(\d+)(';)", re.M)


def read(path):
    # Reading with newline='' keeps the file's own line endings when it's written back.
    with open(path, encoding='utf-8', newline='') as handle:
        return handle.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', newline='') as handle:
        handle.write(text)


def bump_addon():
    text = read(ADDON_LUA)
    match = VERSION_LINE.search(text)
    if not match:
        raise RuntimeError('cadence.lua has no addon.version line like 1.0.0.')
    version = '%s.%s.%d' % (match.group(2), match.group(3), int(match.group(4)) + 1)
    write(ADDON_LUA, text[:match.start()] + match.group(1) + version + match.group(5) + text[match.end():])
    return version


def add_section(version, first_line, bullets):
    text = read(CHANGELOG)
    eol = '\r\n' if '\r\n' in text else '\n'
    lines = ['## ' + version, '', first_line, ''] + (bullets + [''] if bullets else [])
    section = eol.join(lines) + eol
    newest = re.search(r'^## ', text, re.M)
    at = newest.start() if newest else len(text)
    write(CHANGELOG, text[:at] + section + text[at:])


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    bullets = []
    if len(sys.argv) == 3:
        with open(sys.argv[2], encoding='utf-8') as handle:
            bullets = [line.rstrip() for line in handle if line.strip()]
    version = bump_addon()
    add_section(version, sys.argv[1], bullets)
    print(version)


if __name__ == '__main__':
    main()
