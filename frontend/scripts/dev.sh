#!/usr/bin/env bash
# One entry point; specialized runners retain their own options and implementations.
set +x
set -euo pipefail
scripts_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
    cat <<'HELP'
Usage: dev.sh COMMAND [arguments...]
  build          Resolve locked Dart dependencies and generate bindings.
  host-build     Regenerate .dart_tool for the host, then build (keeps pubspec.lock).
  reset          Clear generated Dart tooling state, then build (keeps pubspec.lock).
  run            Open the Godot editor through run_local.sh; forward Godot arguments.
  test           Run isolated Godot integration tests; forward runner arguments.
  check          Validate resource cube dependencies; forward validator arguments.
  preview        Open the isolated Dart 3D preview; forward preview arguments.
  preview-cubes  Open the native cube preview without Dart; forward preview arguments.
DART_BIN overrides the Dart executable. PUB_CACHE overrides frontend/.pub-cache.
Use a specialized runner's --help for its advanced options.
HELP
}
command="${1:-}"
if (( $# )); then shift; fi
case "$command" in
    build|host-build|reset) exec bash "$scripts_dir/build_dart.sh" "$command" "$@" ;;
    run) exec bash "$scripts_dir/run_local.sh" "$@" ;;
    test) exec python3 "$scripts_dir/tests/test-godot.py" "$@" ;;
    check) exec python3 "$scripts_dir/check_resource_cubes.py" "$@" ;;
    preview) exec python3 "$scripts_dir/preview/run-isometric-3d.py" "$@" ;;
    preview-cubes) exec python3 "$scripts_dir/preview/preview-resource-cubes.py" "$@" ;;
    -h|--help|help) usage ;;
    *) usage >&2; exit 2 ;;
esac
