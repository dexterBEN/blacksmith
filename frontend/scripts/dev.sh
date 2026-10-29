#!/usr/bin/env bash
set -euo pipefail

FRONTEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$FRONTEND_DIR"

build_frontend() {
    export PUB_CACHE="$FRONTEND_DIR/../.pub-cache"

    dart pub get
    dart run build_runner build --delete-conflicting-outputs
}

case "${1:-}" in
    build)
        build_frontend
        ;;

    run)
        export LD_LIBRARY_PATH="$FRONTEND_DIR:${LD_LIBRARY_PATH:-}"
        exec godot --path "$FRONTEND_DIR" -e
        ;;

    reset)
        rm -rf .dart_tool
        rm -f pubspec.lock
        build_frontend
        ;;

    *)
        echo "Usage: bash scripts/dev.sh {build|run|reset}"
        exit 1
        ;;
esac