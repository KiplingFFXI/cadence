"""Exercise the weekly job's GitHub boundary with local git/gh stand-ins."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/weekly-data.yml'
SOURCE = 'a' * 40
BRANCH = 'data-refresh-' + SOURCE[:12]
FILES = (
    'CHANGELOG.md',
    'cadence/cadence.lua',
    'cadence/data/phoenix_effects.lua',
    'cadence/data/phoenix_modifiers.lua',
    'tools/generate_modifiers.py',
    'tools/source_guards.json',
)


def step_script(name):
    lines = WORKFLOW.read_text(encoding='utf-8').splitlines()
    index = lines.index('      - name: ' + name)
    while not lines[index].lstrip().startswith('run:'):
        index += 1
    indent = len(lines[index]) - len(lines[index].lstrip()) + 2
    script = []
    for line in lines[index + 1:]:
        if line.strip() and len(line) - len(line.lstrip()) < indent:
            break
        script.append(line[indent:])
    return '\n'.join(script) + '\n'


STUBS = r'''
git() {
    printf '%s\n' "$*" >> "$STUB_DIR/git.txt"
    case "$1" in
        fetch) [ "$STUB_FETCH_FAIL" != true ] ;;
        rev-parse)
            if [ "$2" = 'HEAD^{tree}' ]; then printf '%s\n' "$STUB_TREE";
            elif [ "$2" = 'FETCH_HEAD^{tree}' ]; then printf '%s\n' "$STUB_REMOTE_TREE";
            elif [ "$2" = FETCH_HEAD ]; then printf '%s\n' "$STUB_MAIN";
            else printf '%s\n' "$STUB_BASE"; fi ;;
        ls-remote)
            if [ "$STUB_REMOTE_BRANCH" = true ]; then
                printf '%s\trefs/heads/%s\n' "$STUB_BASE" "$BRANCH"
            fi ;;
        diff) printf '%s\n' "$STUB_CHANGED" ;;
        -c) [ "$STUB_PUSH_FAIL" != true ] ;;
        *) return 0 ;;
    esac
}
gh() {
    printf '%s\n' "$*" >> "$STUB_DIR/gh.txt"
    if [ "$1 $2" = 'pr list' ]; then
        [ "$STUB_LIST_FAIL" != true ] || return 1
        printf '%s' "$STUB_PENDING"
    elif [ "$1 $2" = 'pr create' ]; then
        printf '%s\n' "$@" > "$STUB_DIR/created.txt"
    else
        return 1
    fi
}
'''


class WeeklyWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = WORKFLOW.read_text(encoding='utf-8')
        cls.bash = next((str(path) for path in (
            Path(r'C:\Program Files\Git\bin\bash.exe'),
            Path(shutil.which('bash') or '__missing__'),
        ) if path.is_file() and 'system32' not in str(path).lower()), None)

    def run_step(self, name='Commit the verified data and open a pull request',
                 report='Candidate data changes.\n', **overrides):
        if not self.bash:
            self.skipTest('Git Bash or bash is required for workflow fixtures')
        with tempfile.TemporaryDirectory(prefix='cadence_weekly_') as folder:
            scratch = Path(folder)
            if report is not None:
                (scratch / 'cadence-refresh.md').write_text(report, encoding='utf-8')
            (scratch / 'output.txt').write_text('', encoding='utf-8')
            (scratch / 'summary.txt').write_text('', encoding='utf-8')
            env = dict(os.environ)
            env.update({
                'STUB_DIR': scratch.as_posix(),
                'RUNNER_TEMP': scratch.as_posix(),
                'GITHUB_OUTPUT': (scratch / 'output.txt').as_posix(),
                'GITHUB_STEP_SUMMARY': (scratch / 'summary.txt').as_posix(),
                'GH_TOKEN': 'fixture-token',
                'SOURCE': SOURCE,
                'VERSION': '9.8.7',
                'BRANCH': BRANCH,
                'STUB_BASE': 'b' * 40,
                'STUB_MAIN': 'b' * 40,
                'STUB_CHANGED': '\n'.join(FILES),
                'STUB_PENDING': '',
                'STUB_FETCH_FAIL': '',
                'STUB_PUSH_FAIL': '',
                'STUB_LIST_FAIL': '',
                'STUB_REMOTE_BRANCH': '',
                'STUB_TREE': 'd' * 40,
                'STUB_REMOTE_TREE': 'd' * 40,
                'CHANGED': 'true',
                'STATUS': 'success',
                'VERIFIED': 'success',
                'OPENED': 'true',
            })
            env.update(overrides)
            result = subprocess.run(
                [self.bash, '--noprofile', '--norc', '-e', '-o', 'pipefail', '-c',
                 STUBS + step_script(name)],
                cwd=scratch, env=env, text=True, capture_output=True,
            )
            outputs = {}
            for filename in ('git.txt', 'gh.txt', 'created.txt', 'output.txt', 'summary.txt'):
                path = scratch / filename
                outputs[filename] = path.read_text(encoding='utf-8').splitlines() if path.exists() else []
            return result, outputs

    def test_schedule_permissions_and_human_release_boundary(self):
        for required in ("cron: '17 12 * * 1'", 'workflow_dispatch:',
                         "if: github.ref == 'refs/heads/main'", 'runs-on: windows-2022',
                         'cancel-in-progress: false', 'contents: read',
                         'pull-requests: write', 'persist-credentials: false'):
            self.assertIn(required, self.text)
        for forbidden in ('gh pr merge', 'gh release', 'pull_request_target', '--force',
                          'secrets.PAT', 'git add .'):
            self.assertNotIn(forbidden, self.text)
        for line in self.text.splitlines():
            if 'uses: actions/' in line:
                self.assertRegex(line, r'@[0-9a-f]{40}(?:\s|$)')

    def test_full_windows_verification_precedes_push(self):
        push = self.text.index('- name: Commit the verified data and open a pull request')
        gates = (
            'python tools/check_source.py',
            'python tools/generate_modifiers.py',
            'python tools/generate_effects.py',
            "python -m unittest discover -s tools/tests -p 'test_*.py'",
            'python tests/run.py',
            'python tests/test_release.py',
        )
        verify = (ROOT / '.github/workflows/verify.yml').read_text(encoding='utf-8')
        for gate in gates:
            self.assertIn(gate, verify)
            self.assertLess(self.text.index(gate), push)
        self.assertIn('CADENCE_SOURCE_REPO: ${{ runner.temp }}/Phoenix', self.text)
        self.assertIn('fetch --quiet --depth 1 phoenix "$reviewed"', self.text)
        self.assertIn('ref: ${{ steps.source.outputs.ref }}', verify)
        for name in ('Read the pinned Ashita libraries', 'Verify the prepared source and generated data',
                     'Run tool mutations and addon tests', 'Check release packaging and workflow behavior',
                     'Commit the verified data and open a pull request'):
            section = self.text.split('- name: ' + name, 1)[1].split('\n      - ', 1)[0]
            self.assertIn("if: steps.refresh.outputs.changed == 'true'", section)

    def test_pending_refresh_stops_before_preparation(self):
        result, outputs = self.run_step('Look for a pending data refresh',
                                        STUB_PENDING='data-refresh-older')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs['output.txt'], ['found=true'])
        self.assertFalse(outputs['git.txt'])
        result, outputs = self.run_step('Look for a pending data refresh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(outputs['output.txt'])

    def test_pending_refresh_at_publish_time_leaves_no_branch(self):
        result, outputs = self.run_step(STUB_PENDING='data-refresh-another')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(outputs['git.txt'])
        self.assertFalse(outputs['created.txt'])

    def test_invalid_outputs_stop_before_git_or_github(self):
        for overrides in ({'SOURCE': 'live'}, {'SOURCE': 'a' * 39},
                          {'VERSION': '1.2.3; echo bad'}, {'BRANCH': 'main'}):
            with self.subTest(overrides=overrides):
                result, outputs = self.run_step(**overrides)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(outputs['git.txt'])
                self.assertFalse(outputs['gh.txt'])

    def test_missing_report_stops_before_git_or_github(self):
        result, outputs = self.run_step(report=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(outputs['git.txt'])
        self.assertFalse(outputs['gh.txt'])

    def test_main_advance_requires_another_validation_run(self):
        result, outputs = self.run_step(STUB_MAIN='c' * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('main changed', result.stdout)
        self.assertFalse(any(line.startswith(('switch ', 'add ', 'commit ', '-c '))
                             for line in outputs['git.txt']))
        self.assertFalse(outputs['created.txt'])

    def test_unexpected_or_missing_files_stop_before_commit(self):
        for changed in ('\n'.join(FILES) + '\ncadence/core/tp.lua', '\n'.join(FILES[:-1])):
            with self.subTest(changed=changed):
                result, outputs = self.run_step(STUB_CHANGED=changed)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('six allowed', result.stdout)
                self.assertFalse(any(line.startswith(('switch ', 'add ', 'commit ', '-c '))
                                     for line in outputs['git.txt']))
                self.assertFalse(outputs['created.txt'])

    def test_failed_queries_and_push_never_create_pull_request(self):
        for failure in ('STUB_LIST_FAIL', 'STUB_FETCH_FAIL', 'STUB_PUSH_FAIL'):
            with self.subTest(failure=failure):
                result, outputs = self.run_step(**{failure: 'true'})
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(outputs['created.txt'])

    def test_existing_identical_branch_is_reused_without_push(self):
        result, outputs = self.run_step(STUB_REMOTE_BRANCH='true')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Reusing it', result.stdout)
        self.assertFalse(any(line.startswith('-c ') for line in outputs['git.txt']))
        self.assertTrue(outputs['created.txt'])
        self.assertEqual(outputs['output.txt'], ['opened=true'])

    def test_existing_different_branch_is_not_overwritten_or_proposed(self):
        result, outputs = self.run_step(STUB_REMOTE_BRANCH='true', STUB_REMOTE_TREE='e' * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('differs from the verified files', result.stdout)
        self.assertFalse(any(line.startswith('-c ') for line in outputs['git.txt']))
        self.assertFalse(outputs['created.txt'])

    def test_failure_report_is_preserved_in_the_run_summary(self):
        self.assertIn("if: always() && steps.pending.outputs.found != 'true'", self.text)
        result, outputs = self.run_step('Record the refresh result',
                                        report='Source review required: healing rule changed.\n',
                                        CHANGED='', STATUS='failure', VERIFIED='skipped', OPENED='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs['summary.txt'], [
            'Source review required: healing rule changed.',
            'Refresh or verification failed. No pull request was opened by this run.',
        ])
        result, outputs = self.run_step('Record the refresh result', report=None,
                                        CHANGED='', STATUS='failure', VERIFIED='skipped', OPENED='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('stopped before it could write a report', outputs['summary.txt'][0])

    def test_no_change_summary_does_not_claim_a_release(self):
        result, outputs = self.run_step('Record the refresh result', report=None,
                                        CHANGED='false', OPENED='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs['summary.txt'], [
            'No relevant Phoenix data changes. No version or release was created.',
        ])

    def test_verified_update_only_pushes_allowed_files_to_its_branch(self):
        result, outputs = self.run_step()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('switch --create ' + BRANCH, outputs['git.txt'])
        added = next(line for line in outputs['git.txt'] if line.startswith('add '))
        self.assertEqual(added.split(), ['add', '--', *FILES])
        push = next(line for line in outputs['git.txt'] if line.startswith('-c '))
        self.assertTrue(push.endswith('push origin HEAD:refs/heads/' + BRANCH), push)
        self.assertNotIn('--force', push)
        self.assertIn('commit --quiet --message Refresh Phoenix data for cadence 9.8.7',
                      outputs['git.txt'])
        created = outputs['created.txt']
        self.assertEqual(created[:6], ['pr', 'create', '--base', 'main', '--head', BRANCH])
        self.assertEqual(created[6], '--body-file')
        self.assertTrue(created[7].endswith('/cadence-refresh.md'))
        self.assertEqual(created[8:], ['--title', 'cadence 9.8.7, Phoenix data ' + SOURCE[:12]])


if __name__ == '__main__':
    unittest.main()
