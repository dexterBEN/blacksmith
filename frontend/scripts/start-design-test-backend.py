#!/usr/bin/env python3
"""Build the existing API in its Dev Container and run it on an isolated DB.

Uses cached .NET dependencies and the container's existing DB configuration;
never prints it, copies credentials, or changes the development database.
Applies existing migrations only to a uniquely named disposable database.
No containers, volumes, or GCP resources are created or deleted.

Start: python3 frontend/scripts/start-design-test-backend.py CONTAINER --port 5139
Stop/cleanup: python3 frontend/scripts/start-design-test-backend.py CONTAINER --stop RUN_PATH
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
    parser.add_argument('--port', type=int, default=5139)
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--stop', metavar='RUN_PATH')
    action.add_argument('--verify', nargs=3, metavar=('RUN_PATH', 'DESIGN_ID', 'DESIGN_NAME'))
    action.add_argument('--verify-resource', metavar='DESIGN_ID_AND_RUN', nargs=2)
    args = parser.parse_args()
    if args.stop or args.verify or args.verify_resource:
        run = args.stop or (args.verify[0] if args.verify else args.verify_resource[0])
        if not run.startswith('/tmp/blacksmith-design-backend-') or '/' in run[len('/tmp/'):]:
            parser.error('Expected the exact temporary RUN_PATH printed at startup.')
        if args.stop:
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
    shutil.copytree(Path(__file__).with_name('design-test-backend'), snapshot / 'test-host',
                    ignore=shutil.ignore_patterns('bin', 'obj'))
    # ProjectReference is resolved relative to the temporary test-host directory.
    project = snapshot / 'test-host/DesignTestBackend.csproj'
    project.write_text(project.read_text().replace('../../../backend/src/', '../src/'))
    run = f'/tmp/{snapshot.name}'
    print(f'RUN_PATH={run}', flush=True)
    docker('cp', str(snapshot), f'{args.container}:/tmp/')
    for project in ['src/CloudServices.Api/CloudServices.Api.csproj', 'test-host/DesignTestBackend.csproj']:
        docker('exec', args.container, 'dotnet', 'build', f'{run}/{project}',
               '--configuration', 'Release', '--source', '/root/.nuget/packages',
               '-p:NuGetAudit=false', '--nologo')
    docker('exec', args.container, 'dotnet',
           f'{run}/test-host/bin/Release/net8.0/DesignTestBackend.dll', run, str(args.port))


if __name__ == '__main__':
    main()
