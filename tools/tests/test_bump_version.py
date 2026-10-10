"""A failed version update leaves both release files intact."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bump_version


class VersionTests(unittest.TestCase):
    def test_preparation_failure_changes_neither_file(self):
        with tempfile.TemporaryDirectory() as directory:
            addon, log = Path(directory) / 'cadence.lua', Path(directory) / 'CHANGELOG.md'
            addon.write_bytes(b'old addon')
            log.write_bytes(b'old log')
            temporary, calls = bump_version.tempfile.NamedTemporaryFile, 0

            def fail_fourth_file(*args, **kwargs):
                nonlocal calls
                calls += 1
                if calls == 4:
                    raise PermissionError('cannot prepare changelog')
                return temporary(*args, **kwargs)

            with patch.object(bump_version.tempfile, 'NamedTemporaryFile', side_effect=fail_fourth_file), \
                    patch.object(bump_version.os, 'replace') as replace:
                with self.assertRaises(PermissionError):
                    bump_version.write_pair(((str(addon), 'old addon', 'new addon'), (str(log), 'old log', 'new log')))
                replace.assert_not_called()
            self.assertEqual(addon.read_bytes(), b'old addon')
            self.assertEqual(log.read_bytes(), b'old log')
            self.assertEqual(sorted(path.name for path in Path(directory).iterdir()), ['CHANGELOG.md', 'cadence.lua'])

    def test_first_replace_failure_changes_neither_file(self):
        with tempfile.TemporaryDirectory() as directory:
            addon, log = Path(directory) / 'cadence.lua', Path(directory) / 'CHANGELOG.md'
            addon.write_bytes(b'old addon')
            log.write_bytes(b'old log')
            with patch.object(bump_version.os, 'replace', side_effect=PermissionError('locked addon')):
                with self.assertRaises(PermissionError):
                    bump_version.write_pair(((str(addon), 'old addon', 'new addon'), (str(log), 'old log', 'new log')))
            self.assertEqual(addon.read_bytes(), b'old addon')
            self.assertEqual(log.read_bytes(), b'old log')
            self.assertEqual(sorted(path.name for path in Path(directory).iterdir()), ['CHANGELOG.md', 'cadence.lua'])

    def test_missing_changelog_does_not_change_addon(self):
        with tempfile.TemporaryDirectory() as directory:
            addon = Path(directory) / 'cadence.lua'
            addon.write_text("addon.version = '1.1.0';\n", encoding='ascii')
            before = addon.read_bytes()
            with patch.object(bump_version, 'ADDON_LUA', str(addon)), \
                    patch.object(bump_version, 'CHANGELOG', str(Path(directory) / 'missing.md')), \
                    patch.object(sys, 'argv', ['bump_version.py', 'A correction.']):
                with self.assertRaises(FileNotFoundError):
                    bump_version.main()
            self.assertEqual(addon.read_bytes(), before)

    def test_second_replace_failure_rolls_back_first_file(self):
        with tempfile.TemporaryDirectory() as directory:
            addon, log = Path(directory) / 'cadence.lua', Path(directory) / 'CHANGELOG.md'
            addon.write_bytes(b'old addon\r\n')
            log.write_bytes(b'old log\r\n')
            replace = bump_version.os.replace

            def fail_log(source, destination):
                if destination == str(log):
                    raise PermissionError('locked changelog')
                replace(source, destination)

            with patch.object(bump_version.os, 'replace', side_effect=fail_log):
                with self.assertRaises(PermissionError):
                    bump_version.write_pair(((str(addon), 'old addon\r\n', 'new addon\r\n'),
                                             (str(log), 'old log\r\n', 'new log\r\n')))
            self.assertEqual(addon.read_bytes(), b'old addon\r\n')
            self.assertEqual(log.read_bytes(), b'old log\r\n')
            self.assertEqual(sorted(path.name for path in Path(directory).iterdir()), ['CHANGELOG.md', 'cadence.lua'])

    def test_failed_rollback_keeps_recoverable_original(self):
        with tempfile.TemporaryDirectory() as directory:
            addon, log = Path(directory) / 'cadence.lua', Path(directory) / 'CHANGELOG.md'
            addon.write_bytes(b'old addon')
            log.write_bytes(b'old log')
            replace, calls = bump_version.os.replace, 0

            def fail_after_first(source, destination):
                nonlocal calls
                calls += 1
                if calls > 1:
                    raise PermissionError('locked files')
                replace(source, destination)

            with patch.object(bump_version.os, 'replace', side_effect=fail_after_first):
                with self.assertRaisesRegex(RuntimeError, 'Original files were kept at:'):
                    bump_version.write_pair(((str(addon), 'old addon', 'new addon'), (str(log), 'old log', 'new log')))
            backups = list(Path(directory).glob('.cadence-version-*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), b'old addon')
            self.assertEqual(log.read_bytes(), b'old log')


if __name__ == '__main__':
    unittest.main()
