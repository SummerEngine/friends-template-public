#!/usr/bin/env python3
"""Engine-free isolation/strict-result tests for clone build preparation."""
import json
import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import prepare_network_build as tool


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name).resolve()
        self.project = self.base / 'clone'
        self.project.mkdir()
        self.engine = self.base / 'engine'
        self.engine.write_text('Never executed by these mocked tests')
        for name in tool.REQUIRED:
            path = self.project / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}')
        (self.project / 'summer.build.json').write_text(json.dumps({'runtime': {'protocolVersion': '1.1.0'}}))

    def tearDown(self):
        self.temp.cleanup()

    def result(self):
        return {'passed': True, 'protocol': '1.1.0', 'profiles': [
            {'profile': 0, 'ok': True, 'diagnostics': []},
            {'profile': 1, 'ok': True, 'diagnostics': []}], 'failures': []}

    def test_live_root_and_alias_rejected(self):
        fake_root = self.base / 'repo'
        live = fake_root / 'demo'
        live.mkdir(parents=True)
        alias = self.base / 'alias'
        alias.symlink_to(live, target_is_directory=True)
        with patch.object(tool, 'ROOT', fake_root):
            for path in (live, fake_root, alias):
                with self.assertRaisesRegex(ValueError, 'disposable clone'):
                    tool.validate_project(path)

    def test_valid_clone_and_commands_target_it(self):
        self.assertEqual(tool.validate_project(self.project), self.project)
        for command in tool.commands(self.project, Path('/fake/engine')).values():
            self.assertEqual(command[command.index('--path') + 1], str(self.project))
            self.assertNotIn('--export-release', command)

    def test_default_cli_plan_has_no_writes_or_processes(self):
        before = {str(path): path.read_bytes() for path in self.project.rglob('*') if path.is_file()}
        output = io.StringIO()
        with patch('sys.argv', ['prepare_network_build.py', '--project', str(self.project)]), \
                patch.object(tool.subprocess, 'run') as run, contextlib.redirect_stdout(output):
            tool.main()
            run.assert_not_called()
        self.assertFalse(json.loads(output.getvalue())['executed'])
        self.assertEqual(before, {str(path): path.read_bytes() for path in self.project.rglob('*') if path.is_file()})

    def test_external_symlink_and_hardlink_rejected(self):
        external = self.base / 'external'
        external.write_text('do not modify')
        link = self.project / 'linked'
        link.symlink_to(external)
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            tool.validate_project(self.project)
        link.unlink()
        link.hardlink_to(external)
        with self.assertRaisesRegex(ValueError, 'hardlinks'):
            tool.validate_project(self.project)

    def test_strict_analyzer_result(self):
        good = self.result()
        self.assertEqual(tool.analyzer_result('GW_BUILD_CHECK ' + json.dumps(good), '1.1.0'), good)
        for mutation in ('diagnostic', 'protocol', 'missing_profile', 'duplicate_profile', 'failure_text', 'failed'):
            wrong = self.result()
            if mutation == 'diagnostic': wrong['profiles'][0]['diagnostics'] = [{'code': 'warning'}]
            elif mutation == 'protocol': wrong['protocol'] = 'old'
            elif mutation == 'missing_profile': wrong['profiles'].pop()
            elif mutation == 'duplicate_profile': wrong['profiles'][1]['profile'] = 0
            elif mutation == 'failure_text': wrong['failures'] = ['not accepted']
            else: wrong['passed'] = False
            with self.assertRaises(ValueError):
                tool.analyzer_result('GW_BUILD_CHECK ' + json.dumps(wrong), '1.1.0')
        with self.assertRaises(ValueError):
            tool.analyzer_result('', '1.1.0')

    def test_execute_passes_explicit_project_to_all_generators(self):
        calls = []
        def step(name, command, directory, timeout):
            calls.append(name)
            return {'command': command, 'output': 'GW_BUILD_CHECK ' + json.dumps(self.result())}
        def prepare_clone(project):
            self.assertEqual(project, self.project)
            calls.append('prune')
            return {'pruned': {}}
        def generate(project):
            self.assertEqual(project, self.project)
            calls.append('graph')
            return {'files': {}}
        def audio(project):
            self.assertEqual(project, self.project)
            return {'waves': 0}
        receipt = self.base / 'receipt.json'
        with patch.object(tool, 'run_step', step), patch.object(tool.graph, 'prepare_clone', prepare_clone), \
                patch.object(tool.graph, 'generate', generate), patch.object(tool, 'prepare_audio_imports', audio), \
                patch.object(tool, 'prune_graph_uids', lambda project: {'removed': []}):
            report = tool.execute(self.project, self.engine, receipt)
        self.assertTrue(report['passed'])
        self.assertEqual(calls, ['prune', 'initial_import', 'network', 'graph', 'canonical_import', 'graph', 'analyzers'])
        self.assertTrue(json.loads(receipt.read_text())['passed'])

    def test_failed_step_preserves_failed_receipt_and_stops(self):
        receipt = self.base / 'failure.json'
        with patch.object(tool, 'run_step', side_effect=RuntimeError('preserved parse failure')), \
                patch.object(tool.graph, 'prepare_clone', return_value={'pruned': {}}), \
                patch.object(tool, 'prepare_audio_imports', return_value={}), \
                patch.object(tool.graph, 'generate') as generate:
            with self.assertRaisesRegex(RuntimeError, 'parse failure'):
                tool.execute(self.project, self.engine, receipt)
            generate.assert_not_called()
        self.assertFalse(json.loads(receipt.read_text())['passed'])

    def test_logged_error_or_timeout_preserves_engine_log(self):
        directory = self.base / 'logs'
        directory.mkdir()
        def engine_error(command, *, stdout, **kwargs):
            stdout.write('SCRIPT ERROR: preserved even with exit0\n')
            return tool.subprocess.CompletedProcess(command, 0)
        with patch.object(tool.subprocess, 'run', side_effect=engine_error):
            with self.assertRaisesRegex(RuntimeError, 'failed'):
                tool.run_step('error', ['/never/run'], directory, 3)
        self.assertIn('SCRIPT ERROR', (directory / 'error.log').read_text())
        def timeout(command, *, stdout, **kwargs):
            stdout.write('startup before timeout\n')
            raise tool.subprocess.TimeoutExpired(command, 3)
        with patch.object(tool.subprocess, 'run', side_effect=timeout):
            with self.assertRaises(tool.subprocess.TimeoutExpired):
                tool.run_step('timeout', ['/never/run'], directory, 3)
        self.assertIn('startup before timeout', (directory / 'timeout.log').read_text())

    def test_shutdown_tls_line_is_not_an_error(self):
        directory = self.base / 'tls'
        directory.mkdir()
        def shutdown(command, *, stdout, **kwargs):
            stdout.write('ERROR: TLS handshake error: -9984\n   at: handshake (x.cpp:1)\nmbedtls error: -0x2700\n')
            return tool.subprocess.CompletedProcess(command, 0)
        with patch.object(tool.subprocess, 'run', side_effect=shutdown):
            self.assertEqual(tool.run_step('tls', ['/never/run'], directory, 3)['exit_code'], 0)

    def test_receipt_cannot_pollute_project(self):
        with patch.object(tool, 'run_step') as run:
            with self.assertRaisesRegex(ValueError, 'outside the project'):
                tool.execute(self.project, Path('/fake/engine'), self.project / 'receipt.json')
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
