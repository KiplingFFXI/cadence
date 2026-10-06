"""
Zips the addon folder for a release and prints the zip's SHA-256.

    python tools\\build_release.py [--out FOLDER] [--no-sounds]

The zip is cadence-<version>.zip, with the version from addon.version in cadence\\cadence.lua. It holds the
addon folder, under its own name, so cadence.lua sits at cadence/cadence.lua inside it. Only the addon's .lua
files go in, plus the .mp3 and .wav files in cadence\\sounds. The repo's LICENSE goes in at cadence/LICENSE, so
every copy of the addon carries the license.

The two sounds belong to Square Enix. --no-sounds leaves the sounds folder out of the zip.
"""
import argparse
import hashlib
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, 'cadence')
SOUNDS = os.path.join(ADDON, 'sounds')
LICENSE = os.path.join(ROOT, 'LICENSE')

# The files the Sound list shows. Anything else in the sounds folder stays out.
SOUND_TYPES = ('.mp3', '.wav')

# The version line in the addon header, like addon.version = '1.0.0'.
VERSION_LINE = re.compile(r"^addon\.version\s*=\s*'([^']+)';", re.M)


def addon_version():
    with open(os.path.join(ADDON, 'cadence.lua'), encoding='ascii') as handle:
        match = VERSION_LINE.search(handle.read())
    if not match:
        raise RuntimeError('cadence.lua has no addon.version line.')
    return match.group(1)


def addon_files(sounds):
    """(path on disk, path in the zip) for each file that goes in, folder by folder in name order."""
    files = []
    for folder, subfolders, names in os.walk(ADDON):
        subfolders.sort()
        for name in sorted(names):
            kind = os.path.splitext(name)[1].lower()
            if folder == SOUNDS:
                wanted = sounds and kind in SOUND_TYPES
            else:
                wanted = kind == '.lua'
            if wanted:
                path = os.path.join(folder, name)
                files.append((path, os.path.relpath(path, ROOT).replace(os.sep, '/')))
    return files


def main():
    parser = argparse.ArgumentParser(description='Zip the cadence addon folder for a release.')
    parser.add_argument('--out', default=os.path.join(ROOT, 'dist'), help='the folder to write the zip into')
    parser.add_argument('--no-sounds', action='store_true', help='leave the sounds folder out')
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, 'cadence-%s.zip' % addon_version())
    # The license sits at the top of the repo. The zip puts it in the addon folder.
    files = [(LICENSE, 'cadence/LICENSE')] + addon_files(not args.no_sounds)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for source, name in files:
            archive.write(source, name)
    with open(path, 'rb') as handle:
        digest = hashlib.sha256(handle.read()).hexdigest()
    print('Wrote %s with %d files, %.1f MB.' % (path, len(files), os.path.getsize(path) / 1048576.0))
    print('SHA-256 %s' % digest)


if __name__ == '__main__':
    sys.exit(main())
