#!/usr/bin/env python3
"""Offline launcher regressions; uses a fake Godot only.

Run: python3 frontend/scripts/tests/test_run_local.py
Does not read backend/.env or launch a GUI, API, Docker or Google Cloud.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class LocalLauncherTests(unittest.TestCase):
    token = 'fixture-only-local-token-0000000000000000000000'

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='blacksmith launcher ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.front = self.root / 'project with spaces/frontend'
        self.back = self.front.parent / 'backend'
        self.bin = self.root / 'bin'
        for directory in [self.front / 'scripts', self.back, self.bin]:
            directory.mkdir(parents=True)
        self.script = self.front / 'scripts/run_local.sh'
        shutil.copyfile(Path(__file__).resolve().parents[1] / 'run_local.sh', self.script)
        self.env_file = self.back / '.env'
        self.godot = self.bin / 'godot'
        self.godot.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
expected = json.loads(Path(__file__).with_name('expected.json').read_text())
valid = (os.environ.get('LD_LIBRARY_PATH') == expected['ld']
    and os.getcwd() == expected['cwd'] and sys.argv[1:] == expected['args'])
if not valid:
    print('Godot stub: unexpected launch configuration', file=sys.stderr)
    sys.exit(91)
Path(__file__).with_name('called').touch()
sys.exit(expected['exit'])
''')
        self.godot.chmod(0o700)

    def launch(self, data=None, *, expected_token=None, ld=None, args=(),
               status=0, error=None, trace=False, godot_exit=0, elsewhere=False,
               missing_godot=False):
        if data is not None:
            self.env_file.write_bytes(data)
        token = self.token if expected_token is None else expected_token
        (self.bin / 'expected.json').write_text(json.dumps({
            'token': token, 'cwd': str(self.front),
            'ld': str(self.front) + (':' + ld if ld else ''),
            'args': ['--path', str(self.front), '--editor', *args],
            'exit': godot_exit,
        }))
        env = os.environ.copy()
        env['PATH'] = str(self.bin) + ':/usr/bin:/bin'
        if missing_godot:
            self.godot.unlink()
            (self.bin / 'dirname').symlink_to(shutil.which('dirname'))
            env['PATH'] = str(self.bin)
        env.pop('BLACKSMITH_DEPLOYMENT_TOKEN', None)
        if ld is None:
            env.pop('LD_LIBRARY_PATH', None)
        else:
            env['LD_LIBRARY_PATH'] = ld
        result = subprocess.run(
            ['/bin/bash', *(['-x'] if trace else []), str(self.script), *args],
            cwd=self.root if elsewhere else self.front, env=env,
            capture_output=True, timeout=10)
        # Keep assertion failures sanitized: never include process output/values.
        self.assertEqual(result.returncode, status, 'Unexpected launcher exit')
        self.assertNotIn(self.token.encode(), result.stdout + result.stderr)
        self.assertNotIn(token.encode(), result.stdout + result.stderr)
        if error:
            self.assertIn(error.encode(), result.stderr)
        self.assertEqual((self.bin / 'called').exists(), error is None)
        self.assertNotIn('BLACKSMITH_DEPLOYMENT_TOKEN', env)

    def configuration(self, token=None):
        return f'BlacksmithDeployment__Token={token or self.token}\n'.encode()

    def test_frontend_directory(self):
        self.launch(self.configuration())

    def test_other_directory_arguments_and_library_path(self):
        self.launch(self.configuration(), elsewhere=True, ld='/opt/test/lib:/usr/local/lib',
                    args=('--verbose', 'argument with spaces', '*.literal', '$HOME'))

    def test_empty_library_path(self):
        self.launch(self.configuration(), ld='')

    def test_no_final_newline(self):
        self.launch(self.configuration().rstrip(b'\n'))

    def test_bom_crlf_and_whitespace(self):
        self.launch(b'\xef\xbb\xbf# ignored\r\n\t BlacksmithDeployment__Token=' + self.token.encode() + b'\r\n')

    def test_literal_value_characters(self):
        for token in [f'"{self.token}=#literal"', f' {self.token} ']:
            with self.subTest():
                self.launch(self.configuration(token), expected_token=token)

    def test_no_shell_evaluation(self):
        marker = self.root / 'must not execute'
        token = self.token + f'$(touch "{marker}")'
        self.launch(f'OTHER=$(touch "{marker}")\n'.encode() + self.configuration(token),
                    expected_token=token)
        self.assertFalse(marker.exists())

    def test_no_secret_in_trace(self):
        self.launch(self.configuration(), trace=True)

    def test_godot_exit_propagated(self):
        self.launch(self.configuration(), godot_exit=37, status=37)

    def test_missing_configuration(self):
        self.launch()

    def test_missing_godot(self):
        self.launch(self.configuration(), missing_godot=True,
                    status=127, error='exec: godot: not found')

    def test_configuration_is_ignored(self):
        for data in [b'', b'OTHER=value\n', b'BlacksmithDeployment__Token=\n',
                     b'BlacksmithDeployment__Token=short\n', b'invalid\0content']:
            with self.subTest():
                self.launch(data)


if __name__ == '__main__':
    unittest.main(verbosity=2)
