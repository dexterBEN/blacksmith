#!/usr/bin/env python3
"""Launch the interactive 3D scene in an isolated fixture without a backend.

Default: interactive preview. --check captures a real viewport and a lightweight
runtime sample; --headless checks structure, input and lifecycle without images.
Only fake selection dependencies are registered. Requires the existing Dart
packages, generated bindings and Linux Godot/Dart native libraries.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--headless', action='store_true')
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--timeout', type=int, default=300)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    project = Path(tempfile.mkdtemp(prefix='blacksmith-isometric3d-'))
    output = args.output.resolve() if args.output else project / 'evidence'
    output.mkdir(parents=True, exist_ok=True)
    print(f'Isolated scene: {project}', flush=True)
    print(f'Runtime evidence: {output}', flush=True)

    def copy(relative):
        destination = project / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / relative, destination)

    for relative in ['godot_dart.gdextension', 'godot_dart/logo_dart.svg',
                     'libgodot_dart.so', 'libdart_dll.so', 'icon.svg',
                     'src/pubspec.yaml', 'src/pubspec.lock',
                     'src/.dart_tool/package_config.json',
                     'src/godot_dart_scripts.g.dart']:
        copy(relative)
    for folder, pattern in [('src/lib', '*.dart'), ('src/test_support', '*.dart'),
                            ('scenes', '*.tscn'), ('scenes', '*.tres'),
                            ('scenes', '*.gdshader'), ('scenes', '*.svg'),
                            ('scenes', '*.jpeg')]:
        for path in (source / folder).rglob(pattern):
            copy(path.relative_to(source))
    config = (source / 'project.godot').read_text()
    config = config.replace('config/name="frontend"',
                            'config/name="Blacksmith — Interactive 3D Grid"')
    config = '\n'.join(
        'run/main_scene="res://scenes/isometric_3d.tscn"'
        if line.startswith('run/main_scene=') else line
        for line in config.splitlines())
    config += ('\n\n[display]\nwindow/size/viewport_width=1152\n'
               'window/size/viewport_height=648\n')
    (project / 'project.godot').write_text(config)
    (project / 'src/main.dart').write_text(
        "import 'test_support/isometric_3d_main.dart' as preview;\n"
        'void main() => preview.main();\n')
    env = os.environ.copy()
    for name in ['DATA', 'CONFIG', 'CACHE']:
        env[f'XDG_{name}_HOME'] = str(project / f'xdg-{name.lower()}')
    env['BLACKSMITH_ISSUE17_MODE'] = (
        'headless' if args.headless else 'check' if args.check else 'interactive')
    env['BLACKSMITH_ISSUE17_OUTPUT'] = str(output)
    env['BLACKSMITH_ISSUE17_GODOT_VERSION'] = subprocess.check_output(
        [args.godot, '--version'], text=True).strip()

    def run(name, arguments, marker, timeout):
        log = output / f'{name}.log'
        with log.open('w') as stream:
            result = subprocess.run(
                [args.godot, '--path', str(project), *arguments],
                cwd=project, env=env, stdout=stream, stderr=subprocess.STDOUT,
                timeout=timeout, check=False)
        contents = log.read_text(errors='replace')
        if result.returncode or marker not in contents:
            raise RuntimeError(f'{name} failed; inspect {log}')
        print(f'{name}: PASS ({marker})', flush=True)

    # Import exit status alone is insufficient if native Dart loading fails.
    run('import', ['--headless', '--editor', '--import'],
        'BLACKSMITH_ISSUE17_DART_READY', args.timeout)
    arguments = ['--headless'] if args.headless else [
        '--display-driver', 'x11', '--rendering-method', 'gl_compatibility',
        '--resolution', '1152x648', '--max-fps', '60']
    marker = ('BLACKSMITH_ISSUE17_RENDER_PASSED' if args.check else
              'BLACKSMITH_ISSUE17_SELECTION_PASSED' if args.headless else
              'BLACKSMITH_ISSUE17_SCENE_PASSED')
    run('scene', arguments, marker,
        args.timeout if args.check or args.headless else None)


if __name__ == '__main__':
    main()
