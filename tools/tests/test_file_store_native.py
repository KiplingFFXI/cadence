"""Exercise Windows file replacement through the addon's real LuaJIT FFI calls."""
import ctypes
import json
import os
from pathlib import Path
import tempfile
import unittest

from lupa import luajit21

ROOT = Path(__file__).resolve().parents[2]
LIBS = Path(os.environ.get('ASHITA_LIBS', 'C:/Games/PhoenixXI/addons/libs'))


@unittest.skipUnless(os.name == 'nt' and (LIBS / 'json.lua').is_file(), 'Windows and Ashita json.lua are required')
class NativeSaveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='cadence_native_save_')
        self.path = Path(self.temporary.name) / 'profiles.json'
        self.runtime = luajit21.LuaRuntime(unpack_returned_tuples=True)
        self.runtime.execute('T = function(value) return value or {} end')
        self.runtime.execute('package.path = [[%s/?.lua;%s/?.lua;]] .. package.path'
                             % ((ROOT / 'cadence').as_posix(), LIBS.as_posix()))
        self.store = self.runtime.eval("require('core.file_store')")

    def tearDown(self):
        self.store, self.runtime = None, None
        self.temporary.cleanup()

    def write(self, name):
        return self.store.write(str(self.path), self.runtime.table_from({'name': name}))

    def test_create_and_replace_use_the_real_windows_calls(self):
        self.assertTrue(self.write('first'))
        self.assertTrue(self.write('replacement'))
        self.assertEqual(json.loads(self.path.read_text(encoding='utf-8')), {'name': 'replacement'})
        self.assertEqual(list(self.path.parent.glob('*.tmp')), [])

    def test_locked_destination_preserves_the_old_file(self):
        self.assertTrue(self.write('original'))
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
                                     ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
        kernel.CreateFileW.restype = ctypes.c_void_p
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.CreateFileW(str(self.path), 0x80000000, 0, None, 3, 0x80, None)
        self.assertNotEqual(handle, ctypes.c_void_p(-1).value)
        try:
            self.assertFalse(self.write('blocked'))
        finally:
            kernel.CloseHandle(handle)
        self.assertEqual(json.loads(self.path.read_text(encoding='utf-8')), {'name': 'original'})
        self.assertEqual(list(self.path.parent.glob('*.tmp')), [])


if __name__ == '__main__':
    unittest.main()
