#!/usr/bin/env python3
"""Engine-free tests of the app build helpers."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import app_build


class EngineLogTests(unittest.TestCase):
    def test_script_and_engine_errors_are_found(self):
        self.assertTrue(app_build.engine_errors('ok\nSCRIPT ERROR: Parse Error: x\n'))
        self.assertTrue(app_build.engine_errors('ERROR: Cannot open file\n'))
        self.assertFalse(app_build.engine_errors('fixture client 3\nWARNING: harmless\n'))

    def test_shutdown_tls_handshake_is_ignored(self):
        text = 'ERROR: TLS handshake error: -9984\n   at: handshake (x.cpp:1)\nmbedtls error: -0x2700\n'
        self.assertFalse(app_build.engine_errors(text))

    def test_boot_check_fails_on_script_error_and_passes_clean(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'boot.log'
            def runner(text):
                def run(command, *, stdout, **kwargs):
                    stdout.write(text)
                    return app_build.subprocess.CompletedProcess(command, 0)
                return run
            with patch.object(app_build.subprocess, 'run', runner('SCRIPT ERROR: broken\n')):
                with self.assertRaisesRegex(RuntimeError, 'boot check'):
                    app_build.boot_check(Path('/never/run'), log)
            with patch.object(app_build.subprocess, 'run', runner('title shown\n')):
                self.assertEqual(app_build.boot_check(Path('/never/run'), log)['script_errors'], 0)
            command = []
            def capture(cmd, **kwargs):
                command.extend(cmd)
                return app_build.subprocess.CompletedProcess(cmd, 0)
            with patch.object(app_build.subprocess, 'run', capture):
                app_build.boot_check(Path('/never/run'), log)
            self.assertIn('--headless', command)
            self.assertIn('Dummy', command)


if __name__ == '__main__':
    unittest.main()
