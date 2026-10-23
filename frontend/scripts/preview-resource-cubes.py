#!/usr/bin/env python3
"""Preview the supplied resource cubes on the existing board without Dart/cloud.

The temporary native fixture reuses the current board scene, camera, lights,
materials, reflection and background. Only its Dart root script is replaced.
Source application scenes and the issue #27 stash remain untouched.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--variant', choices=['original', 'corrected'],
                        default='corrected')
    parser.add_argument('--check', action='store_true',
                        help='Validate, capture real viewport images and exit.')
    parser.add_argument('--compare', action='store_true',
                        help='Check both variants after one import (requires --check or --headless).')
    parser.add_argument('--headless', action='store_true',
                        help='Validate native resources without rendering.')
    parser.add_argument('--generate-mesh', action='store_true',
                        help='Regenerate the shared corrected mesh in the repo.')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    if args.compare and not (args.check or args.headless):
        parser.error('--compare requires --check or --headless')
    source = Path(__file__).resolve().parents[1]
    project = Path(tempfile.mkdtemp(prefix='blacksmith-resource-cubes-'))
    output = args.output.resolve() if args.output else project / 'captures'
    output.mkdir(parents=True, exist_ok=True)
    print(f'Temporary project: {project}', flush=True)
    print(f'Output: {output}', flush=True)

    for folder in ['scenes/isometric_3d', 'assets/models/resource_cubes']:
        shutil.copytree(source / folder, project / folder,
                        ignore=shutil.ignore_patterns('*.import', '*.uid'))
    (project / 'tools').mkdir()
    for name in ['resource_cubes_preview.gd', 'generate_resource_cube.gd']:
        shutil.copyfile(source / 'tools' / name, project / 'tools' / name)
    scene = (source / 'scenes/isometric_3d.tscn').read_text()
    old = next(line for line in scene.splitlines()
               if line.startswith('[ext_resource type="Script"')
               and 'isometric_3d_grid.dart' in line)
    scene = scene.replace(old, '[ext_resource type="Script" '
                          'path="res://tools/resource_cubes_preview.gd" '
                          'id="1_script"]')
    # This is a distinct fixture, so it must not reuse the source scene UID.
    scene = scene.replace(' uid="uid://d0nh6ysxiiuyd"', '', 1)
    (project / 'scenes/resource_cubes_preview.tscn').write_text(scene)
    (project / 'project.godot').write_text(
        'config_version=5\n[application]\n'
        'config/name="Blacksmith — Resource Cube Preview"\n'
        'run/main_scene="res://scenes/resource_cubes_preview.tscn"\n'
        '[display]\nwindow/size/viewport_width=1152\n'
        'window/size/viewport_height=648\n'
        'window/stretch/mode="viewport"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        'anti_aliasing/quality/msaa_3d=2\n')
    env = os.environ.copy()
    for name in ['DATA', 'CONFIG', 'CACHE']:
        env[f'XDG_{name}_HOME'] = str(project / f'xdg-{name.lower()}')
    env['BLACKSMITH_CUBES_VARIANT'] = args.variant
    env['BLACKSMITH_CUBES_CHECK'] = '1' if args.check or args.headless else '0'
    env['BLACKSMITH_CUBES_OUTPUT'] = str(output)

    def run(name, arguments, marker=None, timeout=args.timeout):
        log = output / f'{env["BLACKSMITH_CUBES_VARIANT"]}_{name}.log'
        try:
            with log.open('w') as stream:
                result = subprocess.run(
                    [args.godot, '--path', str(project), *arguments],
                    cwd=project, env=env, stdout=stream,
                    stderr=subprocess.STDOUT, timeout=timeout, check=False)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f'{name} timed out; inspect {log}') from error
        contents = log.read_text(errors='replace')
        if (result.returncode or (marker and marker not in contents)
                or 'ObjectDB instances leaked at exit' in contents
                or any(line.startswith(('ERROR:', 'SCRIPT ERROR:', 'SHADER ERROR:'))
                       for line in contents.splitlines())):
            raise RuntimeError(f'{name} failed; inspect {log}')
        print(f'{name}: PASS (exit {result.returncode})', flush=True)

    if args.generate_mesh:
        destination = source / 'assets/models/resource_cubes/beveled_resource_cube.tres'
        run('generate', ['--headless', '--script',
                         'res://tools/generate_resource_cube.gd', '--',
                         str(destination)], 'BLACKSMITH_RESOURCE_CUBE_GENERATED')
        shutil.copyfile(destination, project / destination.relative_to(source))
    # Godot 4.4's headless editor emits progress-dialog errors on this VM.
    # Import through the real editor; --headless only affects the scene check.
    run('import', ['--editor', '--import', '--display-driver', 'x11',
                   '--rendering-method', 'gl_compatibility'])
    arguments = ['--headless'] if args.headless else [
        '--display-driver', 'x11', '--rendering-method', 'gl_compatibility',
        '--resolution', '1152x648', '--max-fps', '60']
    marker = ('BLACKSMITH_RESOURCE_CUBES_PASSED'
              if args.check or args.headless else 'BLACKSMITH_RESOURCE_CUBES_READY')
    for variant in ['original', 'corrected'] if args.compare else [args.variant]:
        env['BLACKSMITH_CUBES_VARIANT'] = variant
        run('scene', arguments, marker,
            args.timeout if args.check or args.headless else None)


if __name__ == '__main__':
    main()
