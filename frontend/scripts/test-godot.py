#!/usr/bin/env python3
"""Validate application startup or legacy 2D in an isolated temporary project.

Requires generated Dart bindings, pub get, Godot 4.4 and the existing Linux
native libraries. --application also runs the unchanged production entrypoint.
Temporary files/logs are retained at the printed path for inspection.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import json
import re
from urllib.parse import urlparse
import sys

sys.dont_write_bytecode = True
from check_resource_cubes import validate_assets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path,
                        default=Path(__file__).resolve().parents[1])
    parser.add_argument('--native-dir', type=Path)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--timeout', type=int, default=300,
                        help='Maximum seconds per Godot process (cold Dart compilation can be slow).')
    parser.add_argument('--application', action='store_true',
                        help='Validate production bootstrap/default 3D, then capture clean 3D and explicit 2D launches.')
    parser.add_argument('--design', action='store_true',
                        help='Exercise the New Design UI with fail-closed HTTP doubles and native screenshots.')
    parser.add_argument('--design-live', metavar='BASE_URL',
                        help='With --design, send one real POST + GET to this dedicated test backend (writes a Design).')
    parser.add_argument('--trace-network', action='store_true',
                        help='Use installed Linux strace to reject outgoing IP connections in application runs.')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--persistence', metavar='BASE_URL',
                        help='Real dedicated local API/PostgreSQL save, full quit, open journey; never GCP.')
    parser.add_argument('--deployment', metavar='BASE_URL', help='Native Save & Deploy journey, only against the marked fake-provider fixture.')
    parser.add_argument('--persistence-phase', choices=['save', 'open'],
                        help='Run one restart phase per invocation, sharing --output; useful on slow VMs.')
    parser.add_argument('--reopen-cycles', type=int, default=1,
                        help='Repeat the fake deployment Open phase in distinct native processes, preserving per-cycle evidence.')
    parser.add_argument('--local-editor', action='store_true',
                        help='For a deployment fixture, import with the real host run_local.sh launcher before the player cycles (requires backend/.env).')
    args = parser.parse_args()
    if sum(bool(mode) for mode in [args.design, args.application, args.persistence, args.deployment]) > 1:
        parser.error('--design and --application are separate checks.')
    if args.design_live and not args.design:
        parser.error('--design-live requires --design and a dedicated test database.')
    if args.persistence_phase and not (args.persistence or args.deployment):
        parser.error('--persistence-phase requires --persistence or --deployment.')
    if args.persistence_phase and not args.output:
        parser.error('--persistence-phase requires a shared --output directory.')
    if args.design_live and args.trace_network:
        parser.error('--trace-network forbids IP connections; use it with the offline --design check.')
    if args.reopen_cycles < 1 or (args.reopen_cycles != 1 or args.local_editor) and not args.deployment:
        parser.error('--reopen-cycles and --local-editor require --deployment; cycle count must be positive.')
    journey = args.deployment or args.persistence
    if args.deployment:
        from urllib.request import urlopen
        with urlopen(args.deployment.rstrip('/') + '/__test/deployment-provider', timeout=5) as response:
            if json.load(response).get('fakeProvider') is not True:
                parser.error('The deployment fixture must explicitly identify its injected fake provider.')
    source = args.source.resolve()
    native = (args.native_dir or source).resolve()
    project = Path(tempfile.mkdtemp(prefix='blacksmith-godot-smoke-'))
    output = args.output.resolve() if args.output else project
    output.mkdir(parents=True, exist_ok=True)
    print(f'Isolated Godot fixture and logs: {project}', flush=True)
    if args.output:
        print(f'Output: {output}', flush=True)
    validate_assets(source)

    def copy(relative, root=source):
        destination = project / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / relative, destination)

    for relative in ['project.godot', 'main.tscn', 'icon.svg', 'src/main.dart',
                     'godot_dart.gdextension', 'src/pubspec.yaml',
                     'src/pubspec.lock', 'src/godot_dart_scripts.g.dart',
                     'src/.dart_tool/package_config.json']:
        copy(relative)
    for relative in ['libgodot_dart.so', 'libdart_dll.so',
                     'godot_dart/logo_dart.svg']:
        copy(relative, native)
    for folder, pattern in [('src/lib', '*.dart'),
                            ('src/test_support', '*.dart'),
                            ('src/assets', '*.png'),
                            ('scenes', '*.tscn'), ('scenes', '*.tres'),
                            ('scenes', '*.gdshader'), ('scenes', '*.svg'),
                            ('scenes', '*.jpeg')]:
        for path in (source / folder).rglob(pattern):
            copy(path.relative_to(source))
    shutil.copytree(source / 'assets/models/resource_cubes',
                    project / 'assets/models/resource_cubes',
                    ignore=shutil.ignore_patterns('*.import', '*.uid'))
    if not args.application and not args.design and not (args.persistence or args.deployment):
        (project / 'src/main.dart').write_text(
            "import 'test_support/godot_smoke_main.dart' as smoke;\n"
            "void main() => smoke.main();\n")
    env = os.environ.copy()
    # Confine Godot's editor/runtime caches; never copy env or credential files.
    for name in ['DATA', 'CONFIG', 'CACHE']:
        env[f'XDG_{name}_HOME'] = str(project / f'xdg-{name.lower()}')
    # Clean application launches must not depend on any old fixture environment.
    if args.application or args.design or args.persistence or args.deployment:
        env = {key: value for key, value in env.items()
               if not key.startswith('BLACKSMITH_')}
    if args.design:
        env['BLACKSMITH_DESIGN_OUTPUT'] = str(output)
        if args.design_live:
            env['BLACKSMITH_BACKEND_URL'] = args.design_live
            env['BLACKSMITH_DESIGN_LIVE'] = '1'
    if args.application:
        env['BLACKSMITH_WORKSPACE_OUTPUT'] = str(output)
    if journey:
        env['BLACKSMITH_BACKEND_URL'] = journey
        env['BLACKSMITH_PERSISTENCE_OUTPUT'] = str(output)
    if args.trace_network and not shutil.which('strace'):
        raise RuntimeError('--trace-network requires an installed Linux strace.')

    def run(name, arguments, marker, local=False, headless=True, trace=False, launcher=False):
        log = output / f'{name}.log'
        run_env = env.copy()
        if not args.application and not args.design and not (args.persistence or args.deployment):
            run_env['BLACKSMITH_SMOKE_LOCAL'] = '1' if local else '0'
        command = [args.godot, *(['--headless'] if headless else []),
                   '--path', str(project), *arguments]
        if launcher:
            command = ['bash', str(source / 'scripts/run_local.sh'),
                       '--path', str(project), *arguments]
        network = output / f'{name}.network.log'
        if trace:
            # Filter unrelated syscalls in-kernel: ordinary ptrace makes cold
            # Dart compilation unnecessarily slow on the development VM.
            command = ['strace', '--seccomp-bpf', '-f', '-qq', '-e', 'trace=connect',
                       '-o', str(network), *command]
        with log.open('w') as stream:
            result = subprocess.run(
                command, cwd=project, env=run_env, stdout=stream,
                stderr=subprocess.STDOUT, timeout=args.timeout, check=False)
        contents = log.read_text(errors='replace')
        if result.returncode or marker not in contents:
            raise RuntimeError(f'{name} failed; inspect {log}')
        # Legacy headless imports have known Godot 4.4 progress-dialog errors,
        # but a readiness marker must never conceal a Dart/native exception.
        if any(line.startswith(('ERROR: GodotDart:', 'ERROR: Unhandled exception:',
                                'SCRIPT ERROR:', 'SHADER ERROR:'))
               for line in contents.splitlines()):
            raise RuntimeError(f'{name} Dart/native failure; inspect {log}')
        if (args.application or args.design or args.persistence or args.deployment) and (any(line.startswith(
                ('ERROR:', 'SCRIPT ERROR:', 'SHADER ERROR:'))
                for line in contents.splitlines()) or
                'ObjectDB instances leaked at exit' in contents):
            raise RuntimeError(f'{name} native errors; inspect {log}')
        if trace:
            connections = [line for line in network.read_text(errors='replace').splitlines() if 'AF_INET' in line]
            if journey:
                target = urlparse(journey)
                allowed = f'inet_addr("{target.hostname}")'
                port = f'sin_port=htons({target.port or 80})'
                # godot_dart's editor connects to its own advertised VM service.
                # Only that exact IPv4 loopback endpoint is exempt, only for the
                # real editor launcher; player requests stay API-only.
                debugger_ports = re.findall(
                    r'The Dart VM service is listening on http://127\.0\.0\.1:(\d+)/',
                    contents) if launcher else []
                def permitted(line):
                    return (allowed in line and port in line) or (
                        'inet_addr("127.0.0.1")' in line and
                        any(f'sin_port=htons({value})' in line for value in debugger_ports))
                if any(not permitted(line) for line in connections):
                    raise RuntimeError(f'{name}: connection outside the dedicated API; inspect {network}')
            elif connections:
                raise RuntimeError(f'{name} attempted an outgoing IP connection; inspect {network}')
        print(f'{name}: PASS ({marker})', flush=True)
        return contents

    if journey:
        graphical = ['--display-driver', 'x11', '--rendering-method',
                     'gl_compatibility', '--resolution', '1152x648']
        run('persistence-import', ['--editor', '--import', *graphical],
            '[main] Dart scripts attached.', headless=False,
            launcher=args.local_editor, trace=args.trace_network and args.local_editor)
        original_main = (project / 'src/main.dart').read_bytes()
        (project / 'src/production_main.dart').write_bytes(original_main)
        (project / 'src/main.dart').write_text(
            "import 'production_main.dart' as application;\n"
            f"import 'test_support/{'deployment' if args.deployment else 'persistence'}_journey_checks.dart' as checks;\n"
            'void main() { checks.beforeStartup(); application.main(); checks.afterStartup(); }\n')
        try:
            phases = [args.persistence_phase] if args.persistence_phase else ['save', 'open']
            for phase in phases:
                env['BLACKSMITH_PERSISTENCE_PHASE'] = phase
                cycles = args.reopen_cycles if phase == 'open' else 1
                for cycle in range(1, cycles + 1):
                    suffix = f'-{cycle}' if phase == 'open' else ''
                    run(f'persistence-{phase}{suffix}', [*graphical, '--max-fps', '60'],
                        f'BLACKSMITH_PERSISTENCE_{phase.upper()}_PASSED',
                        headless=False, trace=args.trace_network)
                    if phase == 'open':
                        for name in ['reopened.json', 'open-http.json',
                                     'deployment_restored.png', 'deployment_reopened_workspace.png']:
                            path = output / name
                            if path.exists():
                                shutil.copyfile(path, output / f'cycle-{cycle}-{name}')
                if phase == 'open':
                    opened = [json.loads((output / f'cycle-{cycle}-reopened.json').read_text())
                              for cycle in range(1, cycles + 1)]
                    if len({item['open_pid'] for item in opened}) != cycles:
                        raise RuntimeError('Every reopen cycle must use a distinct native process.')
            if 'open' in phases:
                saved = json.loads((output / 'journey.json').read_text())
                opened = json.loads((output / 'reopened.json').read_text())
                if saved['save_pid'] == opened['open_pid'] or not opened['restored']:
                    raise RuntimeError('A real complete application restart was not proved.')
                print('BLACKSMITH_DEPLOYMENT_RESTART_PASSED real_api=true fake_provider=true resources=2' if args.deployment else 'BLACKSMITH_PERSISTENCE_RESTART_PASSED real_api=true resources=2 cloud_calls=0', flush=True)
        finally:
            (project / 'src/main.dart').write_bytes(original_main)
            (project / 'src/production_main.dart').unlink()
        return

    if args.design:
        graphical = ['--display-driver', 'x11', '--rendering-method',
                     'gl_compatibility', '--resolution', '1152x648']
        run('design-import', ['--editor', '--import', *graphical],
            '[main] Dart scripts attached.', headless=False)
        original_main = (project / 'src/main.dart').read_bytes()
        (project / 'src/production_main.dart').write_bytes(original_main)
        (project / 'src/main.dart').write_text(
            "import 'production_main.dart' as application;\n"
            "import 'test_support/design_creation_checks.dart' as checks;\n"
            'void main() { checks.beforeStartup(); application.main(); checks.afterStartup(); }\n')
        try:
            run('design-interactions', [*graphical, '--max-fps', '60'],
                'BLACKSMITH_DESIGN_UI_PASSED', headless=False,
                trace=args.trace_network and not args.design_live)
        finally:
            (project / 'src/main.dart').write_bytes(original_main)
            (project / 'src/production_main.dart').unlink()
        return

    if args.application:
        copy('scripts/check-workspace-scene-save.gd')
        configuration = (project / 'project.godot').read_bytes()
        original_main = (project / 'src/main.dart').read_bytes()
        if b'run/main_scene="res://scenes/isometric_3d.tscn"' not in configuration:
            raise RuntimeError('The committed project must default to the existing 3D scene.')
        graphical = ['--display-driver', 'x11', '--rendering-method',
                     'gl_compatibility', '--resolution', '1152x648']
        run('application-import', ['--editor', '--import', *graphical],
            '[main] Dart scripts attached.', headless=False)
        # Re-save both real scenes with editor ownership rules. Subsequent
        # native launches use these saved files, so losing the viewport fails
        # here instead of escaping startup-only coverage.
        run('workspace-scene-save', ['--script',
            'res://scripts/check-workspace-scene-save.gd'],
            'BLACKSMITH_WORKSPACE_SCENE_SAVE_PASSED', trace=args.trace_network)
        # Instrument only this phase. The actual bootstrap function is unchanged
        # and creates the real BLoC; only cloud dependencies are fail-closed doubles.
        (project / 'src/production_main.dart').write_bytes(original_main)
        (project / 'src/main.dart').write_text(
            "import 'production_main.dart' as application;\n"
            "import 'test_support/application_startup_checks.dart' as checks;\n"
            'void main() { checks.beforeStartup(); application.main(); checks.afterStartup(); }\n')
        try:
            contents = run('application-interactions', [*graphical, '--max-fps', '60'],
                'BLACKSMITH_DEFAULT_APPLICATION_PASSED', headless=False,
                trace=args.trace_network)
            if 'BLACKSMITH_WORKSPACE_PASSED' not in contents:
                raise RuntimeError('The desktop workspace layout checks did not complete.')
        finally:
            (project / 'src/main.dart').write_bytes(original_main)
            (project / 'src/production_main.dart').unlink()
        # These launches contain no wrapper, autoload observer, fake dependency
        # or required test variable. Default launch has no scene override; legacy
        # uses Godot's explicit scene argument, without rewriting project settings.
        for name, scene, marker, forbidden, image_name in [
            ('normal', [], 'bloc=shared resources=0', '[AppRoot] Grid and palette ready.', 'normal_3d.png'),
            ('legacy', ['res://main.tscn'], '[AppRoot] Grid and palette ready.', '[Isometric3DGrid] 36 shared', 'legacy_2d.png'),
        ]:
            assert (project / 'src/main.dart').read_bytes() == original_main
            assert (project / 'project.godot').read_bytes() == configuration
            contents = run(f'application-{name}', [*graphical, *scene,
                '--write-movie', str(output / f'{name}.png'),
                '--fixed-fps', '30', '--quit-after', '16'], marker,
                headless=False, trace=args.trace_network)
            if ('[main] DI ready & scripts attached' not in contents or
                    forbidden in contents or 'Using local selection state' in contents or
                    'Local diagnostic mode' in contents):
                raise RuntimeError(f'{name} did not use the expected production bootstrap/scene.')
            frames = sorted(output.glob(f'{name}[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].png'))
            if len(frames) < 12:
                raise RuntimeError(f'{name}: expected actual Godot movie-writer frames.')
            shutil.copyfile(frames[-1], output / image_name)
            print(f'Native capture: {output / image_name}', flush=True)
        print('BLACKSMITH_NORMAL_STARTUP_PASSED default=3D legacy=2D restart_empty=true '
              f'network_trace={args.trace_network}', flush=True)
        return

    # Exit zero alone is insufficient: native initialization can fail silently.
    run('import', ['--editor', '--import'], 'BLACKSMITH_GODOT_FAKE_READY')
    # The application default is 3D; this fixture explicitly exercises legacy 2D.
    run('scene', ['res://main.tscn'], 'BLACKSMITH_GODOT_SCENE_PASSED')
    run('diagnostic', ['res://main.tscn'], 'BLACKSMITH_GODOT_LOCAL_PASSED', local=True)


if __name__ == '__main__':
    main()
