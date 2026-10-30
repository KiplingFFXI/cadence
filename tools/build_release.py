"""Check and build the Cadence release zip, with optional bundled sounds."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'cadence'
LICENSE = ROOT / 'LICENSE'
VERSION_LINE = re.compile(r"^addon\.version\s*=\s*'([^']+)';", re.M)

# New runtime files need an explicit entry before they can ship.
CORE = 'attack delay diagnostics enemy enemy_cast file_store monster_effects modifiers packets player reach recovery resting shared_layout stat_state tp'.split()
UI = 'chat_colors defaults history hud layouts navigation presets preview profiles search settings_window sound theme tips window_font'.split()
DATA = {'data/phoenix_modifiers.lua', 'data/phoenix_effects.lua', 'data/phoenix_recovery.lua'}
FILES = {'cadence.lua'} | {'core/%s.lua' % name for name in CORE} | {'ui/%s.lua' % name for name in UI} | DATA
SOUNDS = {'sounds/FF VII Save.mp3', 'sounds/FF IX Moogle.mp3'}
PUBLIC_DOCS = ('README.md', 'CHANGELOG.md', 'docs/GUIDE.md')
DIRECTORIES = {'core', 'ui', 'data', 'sounds'}
PRIVATE_PATH = re.compile(r'(?i)(?:[a-z]:[\\/]+Users[\\/]+|/(?:home|Users)/)[^\s\x00\'"<>]+')
CHARACTER_PATH = re.compile(r'(?i)\bconfig[\\/]+addons[\\/]+cadence[\\/]+[^\s\\/\'"<>]+_\d+(?:[\\/]|$)')
PRIVATE_MARKERS = re.compile(r'(?i)[\\/]\.(?:claude|codex)[\\/]|'
                             r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|'
                             r'\b(?:ghp_[a-zA-Z0-9]{30,}|github_pat_[a-zA-Z0-9_]{40,})\b')


def addon_version(addon=None):
    text = (Path(addon or ADDON) / 'cadence.lua').read_text(encoding='ascii')
    match = VERSION_LINE.search(text)
    if not match:
        raise RuntimeError('cadence.lua has no addon.version line.')
    if not re.fullmatch(r'\d+\.\d+\.\d+', match.group(1)):
        raise RuntimeError('addon.version must have three numeric parts.')
    return match.group(1)


def linked(path):
    return os.path.islink(path) or (hasattr(os.path, 'isjunction') and os.path.isjunction(path))


def addon_files(sounds=True, addon=None):
    """Reject extra, missing or linked files before collecting the release manifest."""
    addon = Path(addon or ADDON)
    if linked(addon):
        raise RuntimeError('The addon folder must not be a linked path.')
    found = set()
    for folder, subfolders, names in os.walk(addon):
        subfolders.sort()
        for name in subfolders:
            path = Path(folder) / name
            relative = path.relative_to(addon).as_posix()
            if linked(path) or relative not in DIRECTORIES:
                raise RuntimeError('Unexpected or linked release folder: %s' % relative)
        for name in sorted(names):
            path = Path(folder) / name
            relative = path.relative_to(addon).as_posix()
            if linked(path) or relative not in FILES | SOUNDS:
                raise RuntimeError('Unexpected or linked release file: %s' % relative)
            found.add(relative)
    missing = (FILES | (SOUNDS if sounds else set())) - found
    if missing:
        raise RuntimeError('Release files are missing: %s' % ', '.join(sorted(missing)))
    wanted = found if sounds else found - SOUNDS
    return [(addon / name, 'cadence/' + name) for name in sorted(wanted)]


def checked_bytes(source, name):
    if linked(source):
        raise RuntimeError('Linked release file: %s' % name)
    data = Path(source).read_bytes()
    if not name.endswith('.mp3'):
        text = data.decode('utf-8')
        if PRIVATE_PATH.search(text) or CHARACTER_PATH.search(text) or PRIVATE_MARKERS.search(text):
            raise RuntimeError('Private path or credential marker in release file: %s' % name)
        data = data.replace(b'\r\n', b'\n')
    return data


def build(out, sounds=True, addon=None, license_path=None):
    addon = Path(addon or ADDON)
    out = Path(out)
    if out.resolve().is_relative_to(addon.resolve()):
        raise RuntimeError('Write release archives outside the addon folder.')
    files = [(license_path or LICENSE, 'cadence/LICENSE')] + addon_files(sounds, addon)
    version = addon_version(addon)
    for name in PUBLIC_DOCS:
        document = addon.parent / name
        if document.exists() or linked(document):
            checked_bytes(document, name)
    out.mkdir(parents=True, exist_ok=True)
    path = out / ('cadence-%s.zip' % version)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.cadence-', suffix='.zip', dir=out, delete=False) as handle:
            temporary = Path(handle.name)
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            for source, name in files:
                entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = 0o100644 << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, checked_bytes(source, name))
        with zipfile.ZipFile(temporary) as archive:
            bad = archive.testzip()
            if bad or archive.namelist() != [name for _, name in files]:
                raise RuntimeError('Release archive validation failed: %s' % (bad or 'file list'))
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return path, len(files), digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', default=ROOT / 'dist', help='the folder to write the zip into')
    parser.add_argument('--no-sounds', action='store_true', help='leave the bundled sounds out')
    args = parser.parse_args()
    path, count, digest = build(args.out, not args.no_sounds)
    print('Wrote %s with %d files, %.1f MB.' % (path, count, path.stat().st_size / 1048576.0))
    print('SHA-256 %s' % digest)


if __name__ == '__main__':
    main()
