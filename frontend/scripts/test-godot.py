#!/usr/bin/env python3
"""Run the real scene with fake provisioning in an isolated temporary project.

Requires generated Dart bindings, pub get, Godot 4.4 and the existing Linux
native libraries. Does not start the production entrypoint or contact an API.
Temporary files/logs are retained at the printed path for inspection.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path,
                        default=Path(__file__).resolve().parents[1])
    parser.add_argument('--native-dir', type=Path)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--timeout', type=int, default=300,
                        help='Maximum seconds per Godot process (cold Dart compilation can be slow).')
    args = parser.parse_args()
    source = args.source.resolve()
    native = (args.native_dir or source).resolve()
    project = Path(tempfile.mkdtemp(prefix='blacksmith-godot-smoke-'))
    print(f'Isolated Godot fixture and logs: {project}', flush=True)

    def copy(relative, root=source):
        destination = project / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / relative, destination)

    for relative in ['project.godot', 'main.tscn', 'icon.svg',
                     'godot_dart.gdextension', 'src/pubspec.yaml',
                     'src/pubspec.lock', 'src/godot_dart_scripts.g.dart',
                     'src/.dart_tool/package_config.json']:
        copy(relative)
    for relative in ['libgodot_dart.so', 'libdart_dll.so',
                     'godot_dart/logo_dart.svg']:
        copy(relative, native)
    for folder, pattern in [('src/lib', '*.dart'),
                            ('src/test_support', '*.dart'),
                            ('src/assets', '*.png')]:
        for path in (source / folder).rglob(pattern):
            copy(path.relative_to(source))
    (project / 'src/main.dart').write_text(
        "import 'test_support/godot_smoke_main.dart' as smoke;\n"
        "void main() => smoke.main();\n")
    env = os.environ.copy()
    # Confine Godot's editor/runtime caches; never copy env or credential files.
    for name in ['DATA', 'CONFIG', 'CACHE']:
        env[f'XDG_{name}_HOME'] = str(project / f'xdg-{name.lower()}')

    def run(name, arguments, marker, local=False):
        log = project / f'{name}.log'
        run_env = env.copy()
        run_env['BLACKSMITH_SMOKE_LOCAL'] = '1' if local else '0'
        with log.open('w') as output:
            result = subprocess.run(
                [args.godot, '--headless', '--path', str(project), *arguments],
                cwd=project, env=run_env, stdout=output,
                stderr=subprocess.STDOUT, timeout=args.timeout, check=False)
        contents = log.read_text(errors='replace')
        if result.returncode or marker not in contents:
            raise RuntimeError(f'{name} failed; inspect {log}')
        print(f'{name}: PASS ({marker})', flush=True)

    # Exit zero alone is insufficient: native initialization can fail silently.
    run('import', ['--editor', '--import'], 'BLACKSMITH_GODOT_FAKE_READY')
    run('scene', [], 'BLACKSMITH_GODOT_SCENE_PASSED')
    run('diagnostic', [], 'BLACKSMITH_GODOT_LOCAL_PASSED', local=True)


if __name__ == '__main__':
    main()
