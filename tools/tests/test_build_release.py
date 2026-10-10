"""Release archives contain only reviewed files and never replace a good zip after a failed check."""
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.addon = self.root / 'cadence'
        self.addon.mkdir()
        (self.addon / 'core').mkdir()
        (self.addon / 'cadence.lua').write_text("addon.version = '1.0.0';\n", encoding='ascii')
        (self.addon / 'core/main.lua').write_text('return {};\n', encoding='ascii')
        self.license = self.root / 'LICENSE'
        self.license.write_text('Public license notice.\n', encoding='ascii')
        self.allowed = patch.object(build_release, 'FILES', {'cadence.lua', 'core/main.lua'})
        self.directories = patch.object(build_release, 'DIRECTORIES', {'core'})
        self.sounds = patch.object(build_release, 'SOUNDS', set())
        self.sounds.start()
        self.allowed.start()
        self.directories.start()

    def tearDown(self):
        self.sounds.stop()
        self.directories.stop()
        self.allowed.stop()
        self.temporary.cleanup()

    def build(self):
        return build_release.build(self.root / 'out', addon=self.addon, license_path=self.license)

    def test_manifest_and_license_are_the_whole_archive(self):
        path, count, digest = self.build()
        with zipfile.ZipFile(path) as archive:
            self.assertEqual(archive.namelist(), ['cadence/LICENSE', 'cadence/cadence.lua', 'cadence/core/main.lua'])
            self.assertTrue(all(info.date_time == (1980, 1, 1, 0, 0, 0) for info in archive.infolist()))
            self.assertEqual(archive.read('cadence/LICENSE'), self.license.read_bytes().replace(b'\r\n', b'\n'))
        self.assertEqual(count, 3)
        self.assertEqual(digest, hashlib.sha256(path.read_bytes()).hexdigest())

    def test_repeated_build_is_byte_identical(self):
        path, _, first = self.build()
        (self.addon / 'core/main.lua').touch()
        _, _, second = self.build()
        self.assertEqual(first, second)
        self.assertTrue(path.is_file())

    def test_text_newlines_produce_identical_archives(self):
        sources = {
            self.addon / 'cadence.lua': b"addon.version = '1.0.0';\n-- Public addon.\n",
            self.addon / 'core/main.lua': b'-- Runtime.\nreturn {};\n',
            self.license: b'Public license notice.\nLicense terms.\n',
        }
        for source, data in sources.items():
            source.write_bytes(data)
        path, count, digest = self.build()
        original = path.read_bytes()
        for mixed in (False, True):
            with self.subTest(mixed=mixed):
                for source, data in sources.items():
                    source.write_bytes(data.replace(b'\n', b'\r\n', 1 if mixed else -1))
                _, new_count, new_digest = self.build()
                self.assertEqual(new_count, count)
                self.assertEqual(new_digest, digest)
                self.assertEqual(path.read_bytes(), original)
                for source, data in sources.items():
                    self.assertEqual(source.read_bytes(), data.replace(b'\n', b'\r\n', 1 if mixed else -1))

    def test_sound_bytes_are_unchanged_when_text_is_normalized(self):
        sounds = {'sounds/FF VII Save.mp3', 'sounds/FF IX Moogle.mp3'}
        audio = b'ID3\xff\x00\r\n\x01\n\x02\r\n'
        with patch.object(build_release, 'SOUNDS', sounds), patch.object(build_release, 'DIRECTORIES', {'core', 'sounds'}):
            (self.addon / 'sounds').mkdir()
            for name in sounds:
                (self.addon / name).write_bytes(audio)
            (self.addon / 'core/main.lua').write_bytes(b'-- Runtime.\r\nreturn {};\r\n')
            path, _, first = self.build()
            with zipfile.ZipFile(path) as archive:
                for name in sounds:
                    self.assertEqual(archive.read('cadence/' + name), audio)
                self.assertEqual(archive.read('cadence/core/main.lua'), b'-- Runtime.\nreturn {};\n')
            (self.addon / 'core/main.lua').write_bytes(b'-- Runtime.\nreturn {};\n')
            self.assertEqual(self.build()[2], first)
            for name in sounds:
                self.assertEqual((self.addon / name).read_bytes(), audio)

    def test_private_note_and_extra_lua_are_rejected(self):
        for name in ('notes.txt', 'test_probe.lua', '.env', 'cadence.lua.bak'):
            path = self.addon / name
            path.write_text('not for release', encoding='ascii')
            with self.assertRaisesRegex(RuntimeError, 'Unexpected.*file'):
                self.build()
            path.unlink()

    def test_even_empty_developer_folder_is_rejected(self):
        (self.addon / 'tests').mkdir()
        with self.assertRaisesRegex(RuntimeError, 'Unexpected.*folder'):
            self.build()

    def test_missing_runtime_file_is_rejected(self):
        (self.addon / 'core/main.lua').unlink()
        with self.assertRaisesRegex(RuntimeError, 'missing.*core/main.lua'):
            self.build()

    def test_private_path_fails_without_printing_the_path(self):
        (self.addon / 'core/main.lua').write_text("-- C:\\Users\\PrivatePerson\\secret.txt\nreturn {};", encoding='ascii')
        with self.assertRaisesRegex(RuntimeError, 'Private path.*core/main.lua') as caught:
            self.build()
        self.assertNotIn('PrivatePerson', str(caught.exception))

    def test_system_font_path_and_public_author_are_allowed(self):
        (self.addon / 'core/main.lua').write_text("-- Public author.\nreturn 'C:\\\\Windows\\\\Fonts';", encoding='ascii')
        self.build()

    def test_failed_content_check_keeps_previous_archive(self):
        path, _, digest = self.build()
        (self.addon / 'core/main.lua').write_text('-----BEGIN PRIVATE KEY-----', encoding='ascii')
        with self.assertRaisesRegex(RuntimeError, 'credential'):
            self.build()
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), digest)
        self.assertEqual(list(path.parent.glob('.cadence-*')), [])

    def test_public_docs_are_checked_without_packing_them(self):
        self.assertIn('docs/GUIDE.md', build_release.PUBLIC_DOCS)
        for name in build_release.PUBLIC_DOCS:
            document = self.root / name
            document.parent.mkdir(parents=True, exist_ok=True)
            document.write_text('Public project documentation.\n', encoding='ascii')
        path, count, _ = self.build()
        self.assertEqual(count, 3)
        with zipfile.ZipFile(path) as archive:
            self.assertFalse(any(name.endswith(build_release.PUBLIC_DOCS) for name in archive.namelist()))

    def test_private_public_doc_keeps_previous_archive(self):
        path, _, digest = self.build()
        for name in build_release.PUBLIC_DOCS:
            with self.subTest(name=name):
                document = self.root / name
                document.parent.mkdir(parents=True, exist_ok=True)
                document.write_text('Saved to C:\\Users\\PrivatePerson\\notes.txt', encoding='ascii')
                with self.assertRaisesRegex(RuntimeError, 'Private path.*' + name) as caught:
                    self.build()
                self.assertNotIn('PrivatePerson', str(caught.exception))
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), digest)
                self.assertEqual(list(path.parent.glob('.cadence-*')), [])
                document.unlink()

    def test_guide_rejects_credentials_and_character_settings(self):
        document = self.root / 'docs/GUIDE.md'
        document.parent.mkdir()
        for content in ('-----BEGIN PRIVATE KEY-----', 'config/addons/cadence/PrivatePerson_123/settings.lua'):
            with self.subTest(content=content):
                document.write_text(content, encoding='ascii')
                with self.assertRaisesRegex(RuntimeError, 'Private path or credential marker.*docs/GUIDE.md') as caught:
                    self.build()
                self.assertNotIn(content, str(caught.exception))

    def test_linked_public_doc_is_rejected(self):
        original = build_release.linked
        for name in build_release.PUBLIC_DOCS:
            with self.subTest(name=name):
                document = self.root / name
                with patch.object(build_release, 'linked', side_effect=lambda path: Path(path) == document or original(path)):
                    with self.assertRaisesRegex(RuntimeError, 'Linked release file: ' + name):
                        self.build()

    def test_linked_file_is_rejected(self):
        original = build_release.linked
        with patch.object(build_release, 'linked', side_effect=lambda path: str(path).endswith('main.lua') or original(path)):
            with self.assertRaisesRegex(RuntimeError, 'linked release file'):
                self.build()

    def test_output_inside_addon_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'outside the addon'):
            build_release.build(self.addon / 'dist', addon=self.addon, license_path=self.license)

    def test_unsafe_version_is_rejected(self):
        (self.addon / 'cadence.lua').write_text("addon.version = '../bad';", encoding='ascii')
        with self.assertRaisesRegex(RuntimeError, 'three numeric parts'):
            self.build()

    def test_bundled_sounds_remain_optional(self):
        sounds = {'sounds/FF VII Save.mp3', 'sounds/FF IX Moogle.mp3'}
        with patch.object(build_release, 'SOUNDS', sounds), patch.object(build_release, 'DIRECTORIES', {'core', 'sounds'}):
            (self.addon / 'sounds').mkdir()
            for name in sounds:
                (self.addon / name).write_bytes(b'ID3audio')
            path, _, _ = self.build()
            with zipfile.ZipFile(path) as archive:
                self.assertTrue({'cadence/' + name for name in sounds} <= set(archive.namelist()))
            path, _, _ = build_release.build(self.root / 'out', False, self.addon, self.license)
            with zipfile.ZipFile(path) as archive:
                self.assertFalse(any(name.startswith('cadence/sounds/') for name in archive.namelist()))
            for name in sounds:
                (self.addon / name).unlink()
            build_release.build(self.root / 'out', False, self.addon, self.license)
            with self.assertRaisesRegex(RuntimeError, 'missing'):
                self.build()


if __name__ == '__main__':
    unittest.main()
