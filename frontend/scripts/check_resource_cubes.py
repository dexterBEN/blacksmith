#!/usr/bin/env python3
"""Check the complete native resource dependency graph before Godot import.

Includes the original OBJ/MTL comparison assets. --require-tracked also rejects
dependencies absent from the Git index, preventing local-only texture fixes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

SERVICES = ('cloud_storage', 'compute_engine', 'cloud_vpn', 'load_balancer')


def validate_assets(source, require_tracked=False):
    source = Path(source).resolve()
    assets = Path('assets/models/resource_cubes')
    pending = [assets / f'{service}.tscn' for service in SERVICES]
    pending += [assets / 'source' / service / f'{service}.obj'
                for service in SERVICES]
    pending += [assets / 'icons/official' / f'{service}.svg'
                for service in ('cloud_storage', 'cloud_vpn', 'cloud_load_balancing')]
    visited = set()
    missing = set()
    while pending:
        relative = pending.pop()
        if relative in visited:
            continue
        visited.add(relative)
        path = source / relative
        if not path.is_file():
            missing.add(relative.as_posix())
            continue
        if path.suffix in {'.tscn', '.tres', '.gdshader'}:
            pending += [Path(name) for name in
                        re.findall(r'res://([^"\s]+)', path.read_text())]
        elif path.suffix in {'.obj', '.mtl'}:
            for line in path.read_text().splitlines():
                fields = line.split(maxsplit=1)
                if len(fields) == 2 and fields[0] in {'mtllib', 'map_Kd'}:
                    pending.append(relative.parent / fields[1])
    if missing:
        raise ValueError('Missing resource dependencies:\n' +
                         '\n'.join(sorted(missing)))
    if require_tracked:
        repository = Path(subprocess.check_output(
            ['git', '-C', str(source), 'rev-parse', '--show-toplevel'],
            text=True).strip())
        indexed = set(subprocess.check_output(
            ['git', '-C', str(repository), 'ls-files', '-z'],
            text=True).split('\0'))
        unpublished = [(source / p).relative_to(repository).as_posix()
                       for p in visited
                       if (source / p).relative_to(repository).as_posix()
                       not in indexed]
        if unpublished:
            raise ValueError('Resource dependencies not in the Git index:\n' +
                             '\n'.join(sorted(unpublished)))
    return [{'file': p.as_posix(),
             'sha256': hashlib.sha256((source / p).read_bytes()).hexdigest()}
            for p in sorted(visited)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path,
                        default=Path(__file__).resolve().parents[1])
    parser.add_argument('--require-tracked', action='store_true')
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    try:
        files = validate_assets(args.source, args.require_tracked)
    except ValueError as error:
        parser.exit(1, f'{error}\n')
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(files, indent=2) + '\n')
    print(f'RESOURCE_DEPENDENCIES_PASSED files={len(files)} '
          f'git_index_checked={args.require_tracked}')


if __name__ == '__main__':
    main()
