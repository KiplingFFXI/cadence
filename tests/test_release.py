"""
Checks the release tools in ..\\tools and the draft release job in ..\\.github\\workflows.

    .venv\\Scripts\\python test_release.py

It builds the zip with and without the sounds and checks every file in each. It bumps the version on a copy of
the project and checks each place that changed. Then it runs the job's steps in Git Bash, with stand-ins for git
and gh, so nothing reaches GitHub. When Git Bash isn't there, it says so and skips the job's steps.

Nothing in the project changes. What it writes goes in a new folder in %TEMP%, which is deleted at the end. It
prints each check and ends with "ALL PASSED" or "N FAILED". The exit code is 1 when a check failed.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WORKFLOW = os.path.join(ROOT, '.github', 'workflows', 'draft-release.yml')

# The files the zip holds, by their names in the zip. A new .lua file in the addon goes on this list too.
LUA = [
    'cadence/cadence.lua',
    'cadence/core/attack.lua',
    'cadence/core/delay.lua',
    'cadence/core/enemy.lua',
    'cadence/core/monster_effects.lua',
    'cadence/core/packets.lua',
    'cadence/core/player.lua',
    'cadence/core/reach.lua',
    'cadence/core/resting.lua',
    'cadence/core/shared_layout.lua',
    'cadence/core/tp.lua',
    'cadence/ui/chat_colors.lua',
    'cadence/ui/defaults.lua',
    'cadence/ui/hud.lua',
    'cadence/ui/presets.lua',
    'cadence/ui/profiles.lua',
    'cadence/ui/settings_window.lua',
    'cadence/ui/sound.lua',
    'cadence/ui/theme.lua',
    'cadence/ui/window_font.lua',
]
SOUNDS = ['cadence/sounds/FF IX Moogle.mp3', 'cadence/sounds/FF VII Save.mp3']
NO_SOUNDS = ['cadence/LICENSE'] + LUA
WITH_SOUNDS = NO_SOUNDS + SOUNDS

VERSION_LINE = re.compile(r"^addon\.version\s*=\s*'([^']+)';", re.M)

out = []
fails = 0


def check(name, cond, detail=None):
    global fails
    if cond:
        out.append('ok   ' + name)
    else:
        fails += 1
        out.append('FAIL ' + name + ('' if detail is None else '  -> %s' % (detail,)))


def read(path):
    with open(path, encoding='utf-8', newline='') as handle:
        return handle.read()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='') as handle:
        handle.write(text)


def version_of(folder):
    return VERSION_LINE.search(read(os.path.join(folder, 'cadence', 'cadence.lua'))).group(1)


def set_version(folder, version):
    path = os.path.join(folder, 'cadence', 'cadence.lua')
    write(path, VERSION_LINE.sub("addon.version = '%s';" % version, read(path), 1))


def copy_project(folder):
    """A copy of the parts of the project the tools and the job read."""
    skip = shutil.ignore_patterns('__pycache__', 'dist')
    for name in ('cadence', 'tools', '.github'):
        shutil.copytree(os.path.join(ROOT, name), os.path.join(folder, name), ignore=skip)
    for name in ('CHANGELOG.md', 'LICENSE', 'README.md'):
        shutil.copy2(os.path.join(ROOT, name), os.path.join(folder, name))
    return folder


def tree(folder):
    """Each file under the folder with its bytes."""
    files = {}
    for at, _, names in os.walk(folder):
        for name in names:
            path = os.path.join(at, name)
            with open(path, 'rb') as handle:
                files[os.path.relpath(path, folder).replace(os.sep, '/')] = handle.read()
    return files


def tree_file(folder, name):
    with open(os.path.join(folder, name), 'rb') as handle:
        return handle.read()


def python(folder, script, *args):
    return subprocess.run([sys.executable, os.path.join(folder, 'tools', script)] + list(args),
                          cwd=folder, capture_output=True, text=True)


def zip_names(path):
    with zipfile.ZipFile(path) as archive:
        return archive.namelist()


def same_list(names, wanted):
    return sorted(names) == sorted(wanted) and len(set(names)) == len(names)


def find_bash():
    """Git Bash, never the WSL bash in System32."""
    for path in (r'C:\Program Files\Git\bin\bash.exe', shutil.which('bash')):
        if path and os.path.isfile(path) and 'system32' not in path.lower():
            return path
    return None


def step_script(name):
    """The run: script of the job's step with this name, without its indent."""
    lines = read(WORKFLOW).splitlines()
    at = lines.index('      - name: ' + name)
    while not lines[at].lstrip().startswith('run:'):
        at += 1
    key = lines[at]
    body = key.split('run:', 1)[1].strip()
    if body != '|':
        return body + '\n'
    indent = len(key) - len(key.lstrip()) + 2
    script = []
    for line in lines[at + 1:]:
        if line.strip() and len(line) - len(line.lstrip()) < indent:
            break
        script.append(line[indent:])
    return '\n'.join(script) + '\n'


# Stand-ins for gh and git. gh lists the releases in STUB_RELEASES and keeps what a release create was given.
# git fetch works only when STUB_OLD_VERSION is set, and git show gives a cadence.lua with that version.
# Git for Windows' awk drops the \r at the end of each line it reads. GitHub's keeps it, and BINMODE=3 makes
# this one keep it too. Other awks ignore it.
STUBS = r'''
awk() {
    command awk -v BINMODE=3 "$@"
}
gh() {
    if [ "$1 $2" = "release list" ]; then printf '%s\n' $STUB_RELEASES; return; fi
    printf '%s\n' "$@" > "$STUB_DIR/gh.txt"
}
git() {
    printf '%s\n' "$*" >> "$STUB_DIR/git.txt"
    case "$1" in
        fetch) [ -n "$STUB_OLD_VERSION" ] ;;
        show) printf "addon.version = '%s';\n" "$STUB_OLD_VERSION" ;;
    esac
}
'''


def run_step(bash, name, folder, scratch, **env):
    """Runs a step the way GitHub does, with bash -e. Gives the exit code, what it printed, its outputs, what
    gh release create was given and the git commands it ran."""
    stub_dir = tempfile.mkdtemp(dir=scratch)
    output = os.path.join(stub_dir, 'output.txt')
    write(output, '')
    environ = dict(os.environ)
    environ.update({
        'GITHUB_OUTPUT': output.replace(os.sep, '/'),
        'GITHUB_REF_TYPE': 'branch',
        'GITHUB_REF_NAME': 'main',
        'STUB_DIR': stub_dir.replace(os.sep, '/'),
        'STUB_RELEASES': '',
        'STUB_OLD_VERSION': '',
        'BEFORE': '',
    })
    environ.update(env)
    # The step's python is the one running this test.
    environ['PATH'] = os.path.dirname(sys.executable) + os.pathsep + environ['PATH']
    result = subprocess.run([bash, '--noprofile', '--norc', '-e', '-c', STUBS + step_script(name)],
                            cwd=folder, env=environ, capture_output=True, text=True)
    outputs = dict(line.split('=', 1) for line in read(output).splitlines() if '=' in line)
    gh = os.path.join(stub_dir, 'gh.txt')
    git = os.path.join(stub_dir, 'git.txt')
    created = read(gh).splitlines() if os.path.exists(gh) else None
    commands = read(git).splitlines() if os.path.exists(git) else []
    return result.returncode, result.stdout + result.stderr, outputs, created, commands


def test_zip(scratch):
    version = version_of(ROOT)
    builds = (('with the sounds', [], WITH_SOUNDS), ('with --no-sounds', ['--no-sounds'], NO_SOUNDS))
    for label, args, wanted in builds:
        folder = tempfile.mkdtemp(dir=scratch)
        result = python(ROOT, 'build_release.py', '--out', folder, *args)
        path = os.path.join(folder, 'cadence-%s.zip' % version)
        check('the zip %s builds into --out as cadence-%s.zip' % (label, version),
              result.returncode == 0 and os.listdir(folder) == ['cadence-%s.zip' % version],
              result.stderr or os.listdir(folder))
        if not os.path.exists(path):
            continue
        names = zip_names(path)
        check('the zip %s holds just these files' % label, same_list(names, wanted),
              sorted(set(names) ^ set(wanted)))
        with zipfile.ZipFile(path) as archive:
            changed = [name for name in names if name in wanted
                       and archive.read(name) != tree_file(ROOT, 'LICENSE' if name == 'cadence/LICENSE' else name)]
        check('each file in the zip %s matches the project\'s, LICENSE at cadence/LICENSE' % label, not changed,
              changed)
        with open(path, 'rb') as handle:
            digest = hashlib.sha256(handle.read()).hexdigest()
        check('it says where it wrote the zip %s, how many files it has and its SHA-256' % label,
              ('Wrote %s with %d files' % (path, len(wanted))) in result.stdout
              and ('SHA-256 %s' % digest) in result.stdout, result.stdout)

    # A copy with a new version and stray files. Only .lua files and the sounds folder's .mp3 and .wav files go
    # in, so nothing from tests or tools does either.
    copy = copy_project(os.path.join(scratch, 'strays'))
    set_version(copy, '9.8.7')
    for name in ('cadence/notes.txt', 'cadence/core/attack.lua.bak', 'cadence/ui/__pycache__/x.pyc',
                 'cadence/sounds/readme.txt', 'cadence/sounds/Bell.WAV', 'cadence/sounds/old/x.mp3',
                 'tests/test_fake.lua', 'tools/fake.lua', 'fake.lua'):
        write(os.path.join(copy, name), 'x')
    result = python(copy, 'build_release.py')
    path = os.path.join(copy, 'dist', 'cadence-9.8.7.zip')
    check('without --out it writes dist\\cadence-<version>.zip, with the version from cadence.lua',
          result.returncode == 0 and os.path.exists(path), result.stderr)
    if os.path.exists(path):
        names = zip_names(path)
        wanted = WITH_SOUNDS + ['cadence/sounds/Bell.WAV']
        check('stray files stay out, and a .wav in the sounds folder goes in', same_list(names, wanted),
              sorted(set(names) ^ set(wanted)))
    result = python(copy, 'build_release.py', '--no-sounds')
    if os.path.exists(path):
        names = zip_names(path)
        check('--no-sounds leaves out every file in the sounds folder', result.returncode == 0
              and same_list(names, NO_SOUNDS), sorted(set(names) ^ set(NO_SOUNDS)))


def bumped(version):
    parts = version.split('.')
    return '.'.join(parts[:-1] + [str(int(parts[-1]) + 1)])


def test_bump(scratch):
    old = version_of(ROOT)
    new = bumped(old)

    # bump_version.py changes only cadence.lua and CHANGELOG.md, so nothing else may name the version.
    others = []
    for name, text in tree(os.path.join(ROOT, 'cadence')).items():
        if name.endswith('.lua'):
            for line in text.decode('utf-8').splitlines():
                if old in line and line != "addon.version = '%s';" % old:
                    others.append('cadence/%s: %s' % (name, line))
    for name in ('README.md', 'CHANGELOG.md'):
        for line in read(os.path.join(ROOT, name)).splitlines():
            if old in line and not (name == 'CHANGELOG.md' and line == '## ' + old):
                others.append('%s: %s' % (name, line))
    check('the version shows up only in cadence.lua\'s addon.version and a CHANGELOG.md heading', not others,
          others)

    copy = copy_project(os.path.join(scratch, 'bump'))
    before = tree(copy)
    bullets = os.path.join(scratch, 'bullets.txt')
    write(bullets, '- One.\n\n- Two.  \n')
    result = python(copy, 'bump_version.py', 'Fixed a thing.', bullets)
    after = tree(copy)
    check('bump_version.py prints the new version and nothing else', result.returncode == 0
          and result.stdout == new + '\n', result.stdout + result.stderr)
    lua = before['cadence/cadence.lua'].decode('ascii')
    check('cadence.lua gets the new version, and nothing else in it changes',
          after['cadence/cadence.lua'].decode('ascii')
          == lua.replace("addon.version = '%s';" % old, "addon.version = '%s';" % new, 1)
          and lua != after['cadence/cadence.lua'].decode('ascii'))
    log = before['CHANGELOG.md'].decode('utf-8')
    at = log.index('\n## ') + 1
    wanted = log[:at] + '## %s\n\nFixed a thing.\n\n- One.\n- Two.\n\n' % new + log[at:]
    check('CHANGELOG.md gets a section above the newest one with the line and the bullets',
          after['CHANGELOG.md'].decode('utf-8') == wanted, after['CHANGELOG.md'].decode('utf-8')[:200])
    changed = sorted(name for name in set(before) | set(after) if before.get(name) != after.get(name))
    check('no other file changes', changed == ['CHANGELOG.md', 'cadence/cadence.lua'], changed)
    result = python(copy, 'build_release.py', '--out', os.path.join(scratch, 'bumped'))
    check('the zip after a bump carries the new version',
          os.path.exists(os.path.join(scratch, 'bumped', 'cadence-%s.zip' % new)), result.stdout + result.stderr)

    result = python(copy, 'bump_version.py', 'Again.')
    check('with no bullets file the section is just the line',
          result.stdout == bumped(new) + '\n'
          and read(os.path.join(copy, 'CHANGELOG.md')).startswith(log[:at] + '## %s\n\nAgain.\n\n## %s\n'
                                                                  % (bumped(new), new)))

    # Files with Windows line endings keep them.
    crlf = copy_project(os.path.join(scratch, 'crlf'))
    for name in ('CHANGELOG.md', 'cadence/cadence.lua'):
        write(os.path.join(crlf, name), read(os.path.join(ROOT, name)).replace('\n', '\r\n'))
    python(crlf, 'bump_version.py', 'Fixed a thing.', bullets)
    text = read(os.path.join(crlf, 'CHANGELOG.md'))
    check('a CHANGELOG.md with Windows line endings keeps them in the new section',
          ('## %s\r\n\r\nFixed a thing.\r\n\r\n- One.\r\n- Two.\r\n\r\n' % new) in text
          and text.count('\n') == text.count('\r\n'))
    check('and so does cadence.lua', version_of(crlf) == new
          and read(os.path.join(crlf, 'cadence', 'cadence.lua')).count('\n')
          == read(os.path.join(crlf, 'cadence', 'cadence.lua')).count('\r\n'))

    # A wrong call changes nothing.
    broken = copy_project(os.path.join(scratch, 'broken'))
    start = tree(broken)
    usage = python(broken, 'bump_version.py')
    check('with no line given it prints how to use it and changes nothing',
          usage.returncode != 0 and 'bump_version.py' in usage.stderr and tree(broken) == start, usage.stderr)
    path = os.path.join(broken, 'cadence', 'cadence.lua')
    write(path, read(path).replace('addon.version', 'addon.release', 1))
    start_broken = tree(broken)
    no_line = python(broken, 'bump_version.py', 'Fixed a thing.')
    check('with no addon.version line it stops and changes nothing',
          no_line.returncode != 0 and 'addon.version' in no_line.stderr and tree(broken) == start_broken,
          no_line.stderr)
    return copy, crlf, new


def test_job(scratch, bumped_copy, crlf_copy, new):
    text = read(WORKFLOW)
    check('the job runs on a push to main that touches cadence.lua, on a version tag and by hand, one at a time',
          'branches: [main]' in text and 'paths: [cadence/cadence.lua]' in text and "tags: ['v[0-9]*']" in text
          and 'workflow_dispatch:' in text and 'cancel-in-progress: false' in text)
    check('the job never builds a zip without the sounds and never names checkmate',
          '--no-sounds' not in text and 'checkmate' not in text.lower())

    bash = find_bash()
    if not bash:
        out.append('skip the job\'s steps, Git Bash wasn\'t found')
        return

    copy = copy_project(os.path.join(scratch, 'job'))
    version = version_of(copy)
    other = bumped(version)

    def check_version(**env):
        return run_step(bash, 'Check the version', copy, scratch, **env)

    code, said, outputs, _, commands = check_version(BEFORE='abc123', STUB_OLD_VERSION='0.0.1',
                                                     STUB_RELEASES='v0.0.1 v%s1' % version)
    check('a push to main that changes the version drafts it', code == 0
          and outputs == {'version': version, 'draft': 'true'}, (code, said, outputs))
    check('and it reads the version before from cadence/cadence.lua at that commit',
          'show abc123:cadence/cadence.lua' in commands, commands)
    code, said, outputs, _, _ = check_version(BEFORE='abc123', STUB_OLD_VERSION=version)
    check('a push to main that leaves the version alone drafts nothing', code == 0 and 'draft' not in outputs
          and ('didn\'t change addon.version from %s' % version) in said, (code, said, outputs))
    code, said, outputs, _, commands = check_version()
    check('a run by hand drafts the version on main', code == 0 and outputs.get('draft') == 'true'
          and not commands, (code, said, outputs, commands))
    code, said, outputs, _, _ = check_version(BEFORE='abc123')
    check('so does the first push of main, with no commit before it to read', code == 0
          and outputs.get('draft') == 'true', (code, said, outputs))
    code, said, outputs, _, _ = check_version(BEFORE='abc123', STUB_OLD_VERSION='0.0.1',
                                              STUB_RELEASES='v0.0.1 v%s' % version)
    check('a version that already has a release drafts nothing', code == 0 and 'draft' not in outputs
          and 'already has a release' in said, (code, said, outputs))
    tag = {'GITHUB_REF_TYPE': 'tag', 'GITHUB_REF_NAME': 'v' + version, 'BEFORE': '0' * 40}
    code, said, outputs, _, commands = check_version(**tag)
    check('pushing the tag v%s drafts it' % version, code == 0
          and outputs == {'version': version, 'draft': 'true'} and not commands, (code, said, outputs, commands))
    code, said, outputs, _, _ = check_version(STUB_RELEASES='v' + version, **tag)
    check('and a tag for a version with a release drafts nothing, like the tag publishing a draft makes',
          code == 0 and 'draft' not in outputs, (code, said, outputs))
    tag['GITHUB_REF_NAME'] = 'v' + other
    code, said, outputs, _, _ = check_version(**tag)
    check('a tag that doesn\'t match addon.version stops the job with an error', code != 0
          and 'draft' not in outputs and ("The tag v%s doesn't match addon.version %s" % (other, version)) in said,
          (code, said, outputs))

    runner = tempfile.mkdtemp(dir=scratch)
    code, said, _, _, _ = run_step(bash, 'Build the zip', copy, scratch, RUNNER_TEMP=runner.replace(os.sep, '/'))
    path = os.path.join(runner, 'cadence-%s.zip' % version)
    check('the job builds the zip with the sounds', code == 0 and os.path.exists(path)
          and same_list(zip_names(path), WITH_SOUNDS), said)

    # In the copy bumped twice, the section sits between two others. The notes start under its heading and stop
    # at the older one.
    for label, folder in (('', bumped_copy), (' with Windows line endings', crlf_copy)):
        runner = tempfile.mkdtemp(dir=scratch).replace(os.sep, '/')
        code, said, _, created, _ = run_step(bash, 'Draft the release', folder, scratch, VERSION=new,
                                             RUNNER_TEMP=runner, GITHUB_SHA='deadbeef')
        notes = read(os.path.join(runner, 'notes.md')) if os.path.exists(os.path.join(runner, 'notes.md')) else ''
        check('the draft\'s notes are just that version\'s section of CHANGELOG.md' + label,
              code == 0 and notes == '\nFixed a thing.\n\n- One.\n- Two.\n\n', (code, said, notes))
        check('the draft is v%s with the zip, on the commit, named cadence %s%s' % (new, new, label),
              created == ['release', 'create', 'v' + new, runner + '/cadence-%s.zip' % new, '--draft',
                          '--target', 'deadbeef', '--title', 'cadence ' + new, '--notes-file',
                          runner + '/notes.md'], created)
    code, said, _, created, _ = run_step(bash, 'Draft the release', copy, scratch, VERSION=other,
                                         RUNNER_TEMP=tempfile.mkdtemp(dir=scratch).replace(os.sep, '/'),
                                         GITHUB_SHA='deadbeef')
    check('a version with no CHANGELOG.md section stops the job before it drafts anything',
          code != 0 and created is None and ('CHANGELOG.md has no section for %s' % other) in said, (code, said))


def main():
    scratch = tempfile.mkdtemp(prefix='cadence_release_')
    try:
        test_zip(scratch)
        test_job(scratch, *test_bump(scratch))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    out.append('ALL PASSED' if fails == 0 else '%d FAILED' % fails)
    print('\n'.join(out))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
