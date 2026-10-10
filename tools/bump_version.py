"""
Adds one to the last number of addon.version in cadence\\cadence.lua and gives CHANGELOG.md a section for it.

    python tools\\bump_version.py "First line of the section." [BULLETS_FILE]

Those are the only two places that name the version. The new section goes above the newest one. It holds the
line, then the bullets from the file as they are. The script prints the new version and nothing else.
"""
import os
import re
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON_LUA = os.path.join(ROOT, 'cadence', 'cadence.lua')
CHANGELOG = os.path.join(ROOT, 'CHANGELOG.md')

# The version line in the addon header, like addon.version = '1.0.0'.
VERSION_LINE = re.compile(r"^(addon\.version\s*=\s*')(\d+)\.(\d+)\.(\d+)(';)", re.M)


def read(path):
    # Reading with newline='' keeps the file's own line endings when it's written back.
    with open(path, encoding='utf-8', newline='') as handle:
        return handle.read()


def bump_addon(text):
    match = VERSION_LINE.search(text)
    if not match:
        raise RuntimeError('cadence.lua has no addon.version line like 1.0.0.')
    version = '%s.%s.%d' % (match.group(2), match.group(3), int(match.group(4)) + 1)
    return version, text[:match.start()] + match.group(1) + version + match.group(5) + text[match.end():]


def add_section(text, version, first_line, bullets):
    eol = '\r\n' if '\r\n' in text else '\n'
    lines = ['## ' + version, '', first_line, ''] + (bullets + [''] if bullets else [])
    section = eol.join(lines) + eol
    newest = re.search(r'^## ', text, re.M)
    at = newest.start() if newest else len(text)
    return text[:at] + section + text[at:]


def write_pair(changes):
    # Prepare both files before replacing either. Keep a copy for rollback if the second replace fails.
    prepared, replaced, keep = [], [], set()
    try:
        for path, before, after in changes:
            pair = []
            prepared.append((path, pair))
            for text in (before, after):
                with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', newline='',
                                                 dir=os.path.dirname(path), prefix='.cadence-version-',
                                                 delete=False) as handle:
                    pair.append(handle.name)
                    handle.write(text)
        try:
            for path, pair in prepared:
                os.replace(pair[1], path)
                replaced.append((path, pair[0]))
        except OSError as error:
            for path, backup in reversed(replaced):
                try:
                    os.replace(backup, path)
                except OSError:
                    keep.add(backup)
            if keep:
                raise RuntimeError('Version update failed. Original files were kept at: ' + ', '.join(sorted(keep))) from error
            raise
    finally:
        for _, pair in prepared:
            for path in pair:
                if path not in keep and os.path.exists(path):
                    os.remove(path)


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    bullets = []
    if len(sys.argv) == 3:
        with open(sys.argv[2], encoding='utf-8') as handle:
            bullets = [line.rstrip() for line in handle if line.strip()]
    addon_before, log_before = read(ADDON_LUA), read(CHANGELOG)
    version, addon_after = bump_addon(addon_before)
    log_after = add_section(log_before, version, sys.argv[1], bullets)
    write_pair(((ADDON_LUA, addon_before, addon_after), (CHANGELOG, log_before, log_after)))
    print(version)


if __name__ == '__main__':
    main()
