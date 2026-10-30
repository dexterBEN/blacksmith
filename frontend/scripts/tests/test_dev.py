#!/usr/bin/env python3
"""Offline command/build regressions; no real Dart, Godot, Docker or network."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class DevelopmentCommandsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='blacksmith dev scripts ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.frontend = self.root / 'project with spaces/frontend'
        self.scripts = self.frontend / 'scripts'
        self.package = self.frontend / 'src'
        self.package.mkdir(parents=True)
        self.scripts.mkdir()
        source = Path(__file__).resolve().parents[1]
        for name in ['dev.sh', 'build_dart.sh', 'run_local.sh']:
            shutil.copyfile(source / name, self.scripts / name)
        (self.package / 'pubspec.yaml').write_text('name: fixture\n')
        self.lock = self.package / 'pubspec.lock'
        self.lock.write_text('locked fixture\n')
        (self.package / '.dart_tool').mkdir()
        self.stale = self.package / '.dart_tool/container-state'
        self.stale.write_text('stale')
        self.log = self.root / 'calls.jsonl'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.stub = self.bin / 'tool with spaces'
        self.stub.write_text('''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
with open(os.environ['FIXTURE_LOG'], 'a') as output:
    output.write(json.dumps({'args':sys.argv[1:], 'cwd':os.getcwd(),
        'cache':os.environ.get('PUB_CACHE'), 'ld':os.environ.get('LD_LIBRARY_PATH'),
        'stale':Path('.dart_tool/container-state').exists()}) + '\\n')
if sys.argv[1:] == ['pub', 'get']:
    sys.exit(int(os.environ.get('PUB_EXIT', '0')))
sys.exit(int(os.environ.get('TOOL_EXIT', '0')))
''')
        self.stub.chmod(0o700)
        for name in ['godot', 'python3']:
            (self.bin / name).symlink_to(self.stub)
        self.env = os.environ.copy()
        self.env.update(PATH=str(self.bin) + ':/usr/bin:/bin', DART_BIN=str(self.stub), FIXTURE_LOG=str(self.log))
        self.env.pop('PUB_CACHE', None)
        self.env.pop('LD_LIBRARY_PATH', None)

    def run_command(self, *args, status=0, env=None):
        result = subprocess.run(['/bin/bash', str(self.scripts / 'dev.sh'), *args],
                                cwd=self.root, env=env or self.env, capture_output=True, timeout=10)
        self.assertEqual(status, result.returncode, result.stderr.decode())
        self.assertEqual('locked fixture\n', self.lock.read_text())
        return result

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_build_runs_inside_package_with_default_cache_and_preserves_generated_state(self):
        self.run_command('build')
        calls = self.calls()
        self.assertEqual([['pub', 'get'], ['run', 'build_runner', 'build', '--delete-conflicting-outputs']], [c['args'] for c in calls])
        self.assertTrue(all(c['cwd'] == str(self.package) for c in calls))
        self.assertTrue(all(c['cache'] == str(self.frontend / '.pub-cache') for c in calls))
        self.assertTrue(self.stale.exists())

    def test_host_build_and_reset_clear_only_generated_state(self):
        for command in ['host-build', 'reset']:
            with self.subTest(command=command):
                (self.package / '.dart_tool').mkdir(exist_ok=True)
                self.stale.write_text('stale')
                self.run_command(command)
                self.assertFalse(self.stale.exists())
                self.assertFalse(self.calls()[-2]['stale'])
                self.assertTrue((self.package / 'pubspec.yaml').exists())

    def test_explicit_relative_cache_is_resolved_before_changing_directory(self):
        env = self.env | {'PUB_CACHE': 'custom cache'}
        self.run_command('build', env=env)
        self.assertEqual(str(self.root / 'custom cache'), self.calls()[0]['cache'])

    def test_dependency_failure_stops_generation_and_reports_stage(self):
        result = self.run_command('build', env=self.env | {'PUB_EXIT': '37'}, status=37)
        self.assertEqual(1, len(self.calls()))
        self.assertIn(b'dependency resolution failed', result.stderr)

    def test_generator_failure_propagates_and_reports_stage(self):
        result = self.run_command('host-build', env=self.env | {'TOOL_EXIT': '41'}, status=41)
        self.assertIn(b'binding generation failed', result.stderr)
        self.assertEqual(2, len(self.calls()))

    def test_missing_dart_does_not_remove_tooling_state(self):
        self.run_command('reset', env=self.env | {'DART_BIN': str(self.bin / 'missing')}, status=127)
        self.assertTrue(self.stale.exists())

    def test_run_delegates_to_canonical_launcher_with_literal_arguments(self):
        self.run_command('run', '--verbose', 'argument with spaces', '$HOME', '*.literal')
        call = self.calls()[0]
        self.assertEqual(['--path', str(self.frontend), '--editor', '--verbose', 'argument with spaces', '$HOME', '*.literal'], call['args'])
        self.assertEqual(str(self.frontend), call['cwd'])
        self.assertEqual(str(self.frontend), call['ld'])

    def test_specialized_dispatch_preserves_options_and_exit_code(self):
        targets = {'test': 'tests/test-godot.py', 'check': 'check_resource_cubes.py',
                   'preview': 'preview/run-isometric-3d.py', 'preview-cubes': 'preview/preview-resource-cubes.py'}
        for command, target in targets.items():
            with self.subTest(command=command):
                self.run_command(command, '--output', 'a directory', '--timeout', '600', env=self.env | {'TOOL_EXIT': '19'}, status=19)
                self.assertEqual([str(self.scripts / target), '--output', 'a directory', '--timeout', '600'], self.calls()[-1]['args'])

    def test_help_and_invalid_commands_never_start_tools(self):
        self.run_command('--help')
        self.run_command('unknown', status=2)
        self.run_command('build', 'unexpected', status=2)
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
