#!/usr/bin/env python3
"""Build the existing API in its Dev Container and run it on an isolated DB.

Uses cached .NET dependencies and the container's existing DB configuration;
never prints it, copies credentials, or changes the development database.
Applies existing migrations only to a uniquely named disposable database.
No containers, volumes, or GCP resources are created or deleted.

Start: python3 frontend/scripts/start-design-test-backend.py CONTAINER --port 5139
Stop/cleanup: python3 frontend/scripts/start-design-test-backend.py CONTAINER --stop RUN_PATH
Restart the fake deployment API, retaining its test DB: ... CONTAINER --restart RUN_PATH
Verify SQL: ... CONTAINER --verify RUN_PATH DESIGN_ID DESIGN_NAME
The initial command stays running until --stop is requested in another terminal.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def docker(*arguments, **kwargs):
    return subprocess.run(['docker', *arguments], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('container')
    parser.add_argument('--deployment', action='store_true', help='Test-only host with an injected GCP fake; never provisions Google Cloud.')
    parser.add_argument('--port', type=int, default=5139)
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--stop', metavar='RUN_PATH')
    action.add_argument('--restart', metavar='RUN_PATH', help='Restart only the deployment fixture process; keep its isolated database.')
    action.add_argument('--verify', nargs=3, metavar=('RUN_PATH', 'DESIGN_ID', 'DESIGN_NAME'))
    action.add_argument('--verify-resource', metavar='DESIGN_ID_AND_RUN', nargs=2)
    args = parser.parse_args()
    if args.stop or args.restart or args.verify or args.verify_resource:
        run = args.stop or args.restart or (args.verify[0] if args.verify else args.verify_resource[0])
        if not run.startswith('/tmp/blacksmith-design-backend-') or '/' in run[len('/tmp/'):]:
            parser.error('Expected the exact temporary RUN_PATH printed at startup.')
        if args.restart:
            # Refuse to target the ordinary persistence fixture (it drops on exit).
            docker('exec', args.container, 'test', '-f', f'{run}/tests/Support/DeploymentApiFactory.cs')
            docker('exec', args.container, 'touch', f'{run}/restart')
        elif args.stop:
            docker('exec', args.container, 'touch', f'{run}/stop')
        elif args.verify_resource:
            docker('exec', args.container, 'dotnet',
                   f'{run}/test-host/bin/Release/net8.0/DesignTestBackend.dll',
                   run, 'verify-resource', args.verify_resource[1])
        else:
            docker('exec', args.container, 'dotnet',
                   f'{run}/test-host/bin/Release/net8.0/DesignTestBackend.dll',
                   run, 'verify', *args.verify[1:])
        return
    repo = Path(__file__).resolve().parents[2]
    backend = repo / 'backend'
    snapshot = Path(tempfile.mkdtemp(prefix='blacksmith-design-backend-'))
    for path in (backend / 'src').rglob('*'):
        if path.suffix not in {'.cs', '.csproj'} or any(part in {'obj', 'bin'} for part in path.parts):
            continue
        target = snapshot / path.relative_to(backend)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    fixture = 'deployment-test-backend' if args.deployment else 'design-test-backend'
    if args.deployment:
        shutil.copyfile(backend / 'BlacksmithBackend.sln', snapshot / 'BlacksmithBackend.sln')
        shutil.copytree(backend / 'tests/Support', snapshot / 'tests/Support')
    shutil.copytree(Path(__file__).with_name(fixture), snapshot / 'test-host',
                    ignore=shutil.ignore_patterns('bin', 'obj'))
    # ProjectReference is resolved relative to the temporary test-host directory.
    project = snapshot / 'test-host/DesignTestBackend.csproj'
    project.write_text(project.read_text().replace('../../../backend/src/', '../src/').replace('../../../backend/tests/', '../tests/'))
    run = f'/tmp/{snapshot.name}'
    print(f'RUN_PATH={run}', flush=True)
    docker('cp', str(snapshot), f'{args.container}:/tmp/')
    for project in ['src/CloudServices.Api/CloudServices.Api.csproj', 'test-host/DesignTestBackend.csproj']:
        docker('exec', args.container, 'dotnet', 'build', f'{run}/{project}',
               '--configuration', 'Release', '--source', '/root/.nuget/packages',
               '-p:NuGetAudit=false', '--nologo')
    resume = []
    while True:
        docker('exec', args.container, 'dotnet',
               f'{run}/test-host/bin/Release/net8.0/DesignTestBackend.dll', run, str(args.port), *resume)
        if not args.deployment:
            break
        stopped = subprocess.run(['docker', 'exec', args.container, 'test', '-f', f'{run}/stop'])
        if stopped.returncode == 0:
            break
        restart = subprocess.run(['docker', 'exec', args.container, 'test', '-f', f'{run}/restart'])
        if restart.returncode != 0:
            break
        resume = ['--resume']


if __name__ == '__main__':
    main()
