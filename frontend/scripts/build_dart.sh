#!/usr/bin/env bash
# Dart setup only: never starts Godot, the backend or cloud operations.
set +x
set -euo pipefail
frontend_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
dart_dir="$frontend_dir/src"
mode="${1:-build}"
if (( $# > 1 )) || [[ "$mode" != build && "$mode" != host-build && "$mode" != reset ]]; then
    printf 'Usage: build_dart.sh {build|host-build|reset}\n' >&2
    exit 2
fi
[[ -f "$dart_dir/pubspec.yaml" ]] || { printf 'Missing frontend/src/pubspec.yaml\n' >&2; exit 1; }
dart_bin="${DART_BIN:-dart}"
# Ubuntu host has both standalone Dart and a Flutter wrapper; use the native SDK.
if [[ "$mode" == host-build && -z "${DART_BIN:-}" && -x /usr/lib/dart/bin/dart ]]; then
    dart_bin=/usr/lib/dart/bin/dart
fi
# Resolve before changing directory, including explicit relative executable paths.
dart_bin="$(command -v -- "$dart_bin")" || { printf 'Dart executable not found; set DART_BIN.\n' >&2; exit 127; }
if [[ "$dart_bin" != /* ]]; then dart_bin="$PWD/$dart_bin"; fi
export PUB_CACHE="${PUB_CACHE:-$frontend_dir/.pub-cache}"
if [[ "$PUB_CACHE" != /* ]]; then export PUB_CACHE="$PWD/$PUB_CACHE"; fi
cd -- "$dart_dir"
if [[ "$mode" == host-build || "$mode" == reset ]]; then
    printf 'Regenerating frontend/src/.dart_tool; preserving pubspec.lock.\n'
    rm -rf -- "$dart_dir/.dart_tool"
fi
printf 'Resolving Dart dependencies in frontend/src.\n'
if "$dart_bin" pub get; then :; else
    result=$?; printf 'Dart dependency resolution failed (exit %s).\n' "$result" >&2; exit "$result"
fi
printf 'Generating Godot/Dart bindings.\n'
if "$dart_bin" run build_runner build --delete-conflicting-outputs; then :; else
    result=$?; printf 'Dart binding generation failed (exit %s).\n' "$result" >&2; exit "$result"
fi
