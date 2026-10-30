"""Prepare a reviewed Phoenix data update. This tool never commits, pushes or publishes.

    python tools/refresh_data.py --server ../Phoenix --ref phoenix/live --report report.md

Only supported SQL data changes can advance automatically. Source rules and other
generator inputs must still match the reviewed code. GitHub runs the complete test
suite on the prepared files before opening a pull request.
"""
import argparse
import json
from pathlib import Path
import re

from lupa import luajit21

import bump_version
import generate_effects
import generate_modifiers
import generate_recovery
from source_parity import GitSource, check_guards, file_fingerprint, fingerprint, loaded_gitlinks, module_entries

ROOT = Path(__file__).resolve().parents[1]
PIN_LINE = re.compile(r"^REF = '([0-9a-f]{40})'(?=\r?$)", re.M)
DATA_FILES = ('cadence/data/phoenix_modifiers.lua', 'cadence/data/phoenix_effects.lua', 'cadence/data/phoenix_recovery.lua')
UPDATE_FILES = (*DATA_FILES, 'tools/generate_modifiers.py', 'tools/source_guards.json',
                'cadence/cadence.lua', 'CHANGELOG.md')
SQL_DATA = frozenset('sql/' + name + '.sql' for name in (
    'item_basic', 'item_equipment', 'item_mods', 'item_latents', 'traits', 'blue_traits',
    'spell_list', 'blue_spell_list', 'blue_spell_mods', 'augments', 'item_usable'))


def plain(value):
    if luajit21.lua_type(value) == 'table':
        return {key: plain(item) for key, item in value.items()}
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    raise RuntimeError('Generated data contains a value other than a table or constant.')


def read_data(text):
    runtime = luajit21.LuaRuntime()
    # These are our generated constants. They do not need any Lua or Python globals.
    load = runtime.eval('function(s) local f=assert(loadstring(s)); setfenv(f, {}); return f() end')
    result = plain(load(text))
    if not isinstance(result, dict) or not isinstance(result.get('source_hashes'), dict):
        raise RuntimeError('Generated data has no source manifest.')
    return result


def semantic(data):
    result = {key: value for key, value in data.items() if key != 'source_hashes'}
    if isinstance(result.get('source'), dict):
        result['source'] = {key: value for key, value in result['source'].items() if key != 'ref'}
    else:
        result.pop('source', None)
    return result


def source_ref(data):
    source = data['source']
    return source['ref'] if isinstance(source, dict) else source


def sql_structure(source, path):
    # The generators validate each INSERT. Other SQL still needs a source review.
    remainder = '\n'.join(line for line in source.read(path).splitlines()
                          if not re.match(r'\s*INSERT\b', line, re.I))
    return fingerprint(remainder, 'sql')


def check_module_changes(reviewed, candidate):
    # A new indirect override may not mention one of the known modifier names.
    entries = module_entries(candidate)
    changes = candidate.git('diff', '--name-status', '--no-renames', '-z',
                            reviewed.ref, candidate.ref, '--', 'modules').strip('\0').split('\0')
    if changes == ['']:
        return
    if len(changes) % 2:
        raise RuntimeError('Cannot read changed Phoenix module paths.')
    gitlinks = set(loaded_gitlinks(reviewed)) | set(loaded_gitlinks(candidate))
    unsupported = []
    for status, path in zip(changes[::2], changes[1::2]):
        if path in gitlinks:
            unsupported.append(path)
            continue
        if not path.endswith(('.lua', '.cpp', '.h', '.hpp', '.sql', '.yaml', '.yml')):
            continue
        if not any(path == entry or path.startswith(entry + '/') for entry in entries):
            continue
        if status == 'M' and file_fingerprint(reviewed, path) == file_fingerprint(candidate, path):
            continue
        unsupported.append(path)
    if unsupported:
        raise RuntimeError('Source review required for loaded module changes:\n  ' + '\n  '.join(unsupported))


def changed_inputs(before, after, reviewed, candidate):
    """Reject code and unsupported input changes before using the candidate tables."""
    old, new = before['source_hashes'], after['source_hashes']
    changed, unsupported = [], []
    for path in sorted(set(old) | set(new)):
        if old.get(path) == new.get(path):
            continue
        changed.append(path)
        if path in SQL_DATA and path in old and path in new:
            if sql_structure(reviewed, path) != sql_structure(candidate, path):
                unsupported.append(path)
            continue
        if path in old and path in new and file_fingerprint(reviewed, path) == file_fingerprint(candidate, path):
            continue
        unsupported.append(path)
    if unsupported:
        raise RuntimeError('Source review required for generator inputs:\n  ' + '\n  '.join(unsupported))
    return changed


def differences(before, after):
    changes = []
    for key in sorted(set(before) | set(after)):
        old, new = before.get(key), after.get(key)
        if old == new:
            continue
        if isinstance(old, dict) and isinstance(new, dict):
            added = sorted(set(new) - set(old), key=str)
            removed = sorted(set(old) - set(new), key=str)
            updated = sorted((row for row in set(old) & set(new) if old[row] != new[row]), key=str)
            changes.append((key, added, removed, updated))
        else:
            changes.append((key, [], [], ['value']))
    return changes


def escape(value):
    return str(value).replace('`', '').replace('|', '\\|').replace('\n', ' ').replace('\r', ' ')


def describe_rows(keys, old, new):
    labels = []
    for key in keys[:8]:
        row = new.get(key, old.get(key)) if isinstance(new, dict) and isinstance(old, dict) else None
        name = row.get('name') if isinstance(row, dict) else None
        labels.append(escape(key) + (' (' + escape(name) + ')' if name else ''))
    if len(keys) > 8:
        labels.append('%d more' % (len(keys) - 8))
    return ', '.join(labels)


def report_changes(old_tables, new_tables, old_ref, new_ref):
    lines = ['Phoenix data update', '',
             'Source: [%s...%s](https://github.com/phoenixffxi/Phoenix/compare/%s...%s).'
             % (old_ref[:12], new_ref[:12], old_ref, new_ref), '',
             'Only generated data changes are included. Source rules and the configured profile still match the reviewed guards.',
             '', '| Data | Added | Removed | Changed |', '| --- | ---: | ---: | ---: |']
    bullets, details = [], []
    for label, old, new in zip(('Modifiers', 'Enemy timing', 'Action recovery'), old_tables, new_tables):
        for key, added, removed, updated in differences(semantic(old), semantic(new)):
            lines.append('| %s: %s | %d | %d | %d |' % (label, escape(key), len(added), len(removed), len(updated)))
            if key != 'coverage':
                bullets.append('- %s %s: %d added, %d removed, %d changed.'
                               % (label, key.replace('_', ' '), len(added), len(removed), len(updated)))
            for title, keys in (('Added', added), ('Removed', removed), ('Changed', updated)):
                if keys:
                    details.append('- %s %s, %s: %s.' % (label, escape(key), title.lower(),
                                   describe_rows(keys, old.get(key), new.get(key))))
    lines += ['', 'Changed rows (up to eight examples per category):', '', *details]
    coverage_before, coverage_after = old_tables[0].get('coverage', {}), new_tables[0].get('coverage', {})
    coverage_lines = []
    names = {value: key for key, value in new_tables[0].get('mod_ids', {}).items()}
    for mod in sorted(set(coverage_before) | set(coverage_after)):
        old, new = coverage_before.get(mod, {}), coverage_after.get(mod, {})
        for category in sorted(set(old) | set(new)):
            if old.get(category, 0) != new.get(category, 0):
                coverage_lines.append('| %s | %s | %s | %s |' %
                                      (escape(names.get(mod, mod)), escape(category), old.get(category, 0), new.get(category, 0)))
    if coverage_lines:
        lines += ['', 'Coverage changes:', '', '| Modifier | Source | Before | After |',
                  '| --- | --- | ---: | ---: |', *coverage_lines]
    lines += ['', 'The weekly workflow must pass source, generator, tool, addon and package checks before opening this PR.',
              'Review and merge the PR to main to run Verify again and prepare a draft release. Publish that draft manually.', '']
    return '\n'.join(lines), bullets


def release_notes(changelog, version, first_line, bullets):
    # Include pending changes in the next release instead of leaving them above its notes.
    match = re.search(r'^## Unreleased\r?\n(.*?)(?=^## |\Z)', changelog, re.M | re.S)
    pending = match[1].strip() if match else ''
    if match:
        changelog = changelog[:match.start()] + changelog[match.end():]
    eol = '\r\n' if '\r\n' in changelog else '\n'
    if pending:
        first_line = pending.replace('\r\n', '\n').replace('\n', eol) + eol + eol + first_line
    return bump_version.add_section(changelog, version, first_line, bullets)


def prepare(server, ref, root=ROOT):
    originals = {path: bump_version.read(root / path) for path in UPDATE_FILES}
    matches = PIN_LINE.findall(originals['tools/generate_modifiers.py'])
    if len(matches) != 1:
        raise RuntimeError('Expected one full reviewed SHA in generate_modifiers.py.')
    reviewed_ref = matches[0]
    manifest = json.loads(originals['tools/source_guards.json'])
    if manifest.get('ref') != reviewed_ref:
        raise RuntimeError('The source guard manifest and generator pin disagree.')
    old_tables = [read_data(originals[path]) for path in DATA_FILES]
    if any(source_ref(data) != reviewed_ref for data in old_tables):
        raise RuntimeError('Generated data and generator pin disagree.')
    candidate = GitSource(server, ref)
    check_guards(candidate, manifest)
    result = {'changed': 'false', 'source': candidate.ref, 'branch': 'data-refresh-' + candidate.ref[:12]}
    if candidate.ref == reviewed_ref:
        return result, 'Phoenix live already matches the reviewed data revision. No update is needed.\n'
    reviewed = GitSource(server, reviewed_ref)
    check_module_changes(reviewed, candidate)
    generators = (generate_modifiers.generate, generate_effects.generate, generate_recovery.generate)
    for path, generate in zip(DATA_FILES, generators):
        if generate(server, reviewed.ref) != originals[path].replace('\r\n', '\n'):
            raise RuntimeError('Checked-in data does not match the reviewed source: ' + path)
    generated = [generate(server, candidate.ref) for generate in generators]
    new_tables = [read_data(text) for text in generated]
    for old, new in zip(old_tables, new_tables):
        if source_ref(new) != candidate.ref:
            raise RuntimeError('Generated candidate data does not name the resolved source revision.')
        changed_inputs(old, new, reviewed, candidate)
    if all(semantic(old) == semantic(new) for old, new in zip(old_tables, new_tables)):
        return result, 'Phoenix has a newer revision, but Cadence data is unchanged. No version or pin was changed.\n'
    report, bullets = report_changes(old_tables, new_tables, reviewed_ref, candidate.ref)
    version, addon = bump_version.bump_addon(originals['cadence/cadence.lua'])
    manifest['ref'] = candidate.ref
    updates = dict(zip(DATA_FILES, generated))
    updates['tools/generate_modifiers.py'] = PIN_LINE.sub("REF = '%s'" % candidate.ref,
                                                        originals['tools/generate_modifiers.py'])
    updates['tools/source_guards.json'] = json.dumps(manifest, indent=2, sort_keys=True) + '\n'
    updates['cadence/cadence.lua'] = addon
    updates['CHANGELOG.md'] = release_notes(originals['CHANGELOG.md'], version,
        'Phoenix data refreshed from live revision %s.' % candidate.ref[:12], bullets)
    bump_version.write_pair([(str(root / path), originals[path], updates[path]) for path in UPDATE_FILES])
    result.update(changed='true', version=version)
    return result, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, default=ROOT.parent / 'Phoenix')
    parser.add_argument('--ref', default='phoenix/live')
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--github-output', type=Path)
    args = parser.parse_args()
    try:
        result, report = prepare(args.server, args.ref)
    except Exception as error:
        args.report.write_text('Phoenix data refresh stopped.\n\n' + str(error) + '\n', encoding='utf-8', newline='\n')
        raise SystemExit(str(error)) from error
    args.report.write_text(report, encoding='utf-8', newline='\n')
    if args.github_output:
        with args.github_output.open('a', encoding='utf-8', newline='\n') as handle:
            handle.write(''.join('%s=%s\n' % pair for pair in result.items()))
    print(report)


if __name__ == '__main__':
    main()
