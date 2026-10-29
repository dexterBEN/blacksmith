#!/usr/bin/env bash
# Keep deployment credentials out of traces, including `bash -x` launches.
set +x
set -euo pipefail

fail() {
    printf 'Blacksmith launcher: %s\n' "$1" >&2
    exit 1
}

frontend_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd -- "$frontend_dir"
export LD_LIBRARY_PATH="$frontend_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec godot --path "$frontend_dir" --editor "$@"
