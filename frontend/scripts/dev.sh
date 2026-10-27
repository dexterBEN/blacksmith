#!/usr/bin/env bash
set -euo pipefail

FRONTEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_ENV="$FRONTEND_DIR/../backend/.env"

cd "$FRONTEND_DIR"

load_deployment_token() {
    if [[ ! -r "$BACKEND_ENV" ]]; then
        echo "Backend .env not found"
        return 1
    fi

    local token
    token="$(sed -n 's/^BlacksmithDeployment__Token=//p' "$BACKEND_ENV" | head -n 1 | tr -d '\r')"

    if [[ -z "$token" ]]; then
        echo "Deployment token missing"
        return 1
    fi

    export BLACKSMITH_DEPLOYMENT_TOKEN="$token"
    echo "Deployment token loaded"
}

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
        load_deployment_token
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