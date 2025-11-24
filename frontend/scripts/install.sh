#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_DIR="${PROJECT_ROOT}/.cache"
mkdir -p "$CACHE_DIR"

echo "==> Project root: ${PROJECT_ROOT}"
echo "==> User: $(whoami)"

# Dépendances système minimales (on lance Godot sur l'hôte)
sudo apt-get update
sudo apt-get install -y curl ca-certificates unzip git jq gpg wget

# Installer Dart (repo officiel)
if ! command -v dart >/dev/null 2>&1; then
  echo "==> Installing Dart SDK"
  echo "deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" | sudo tee /etc/apt/sources.list.d/dart_stable.list
  curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/dart.gpg
  sudo apt-get update && sudo apt-get install -y dart
fi
echo 'export PATH="/usr/lib/dart/bin:$PATH"' | sudo tee /etc/profile.d/dart.sh >/dev/null
echo "==> Dart: $(dart --version || true)"

# Charger .env si présent (GITHUB_TOKEN, GODOT_DART_ARTIFACT_URL)
if [ -f "${PROJECT_ROOT}/.env" ]; then
  set -a; . "${PROJECT_ROOT}/.env"; set +a
fi

REPO="fuzzybinary/godot_dart"
ARTIFACT_NAME="godot-extension"
ZIP_OUT="${CACHE_DIR}/${ARTIFACT_NAME}.zip"
: "${GODOT_DART_ARTIFACT_URL:=}"

download_with_token() {
  : "${GITHUB_TOKEN:?GITHUB_TOKEN manquant (.env)}"
  echo "==> Fetching latest successful artifact"
  runs="$(curl -fsSL -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${REPO}/actions/runs?status=success&per_page=1")"
  run_id="$(echo "$runs" | jq -r '.workflow_runs[0].id')"
  [ -n "$run_id" ] && [ "$run_id" != "null" ] || { echo "No successful run."; return 1; }

  arts="$(curl -fsSL -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${REPO}/actions/runs/${run_id}/artifacts")"
  aid="$(echo "$arts" | jq -r ".artifacts[] | select(.name==\"${ARTIFACT_NAME}\") | .id")"
  [ -n "$aid" ] && [ "$aid" != "null" ] || { echo "Artifact not found."; return 1; }

  echo "==> Downloading artifact id=$aid"
  curl -fsSL -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -o "${ZIP_OUT}" \
    "https://api.github.com/repos/${REPO}/actions/artifacts/${aid}/zip"
}

download_with_url() {
  echo "==> Downloading artifact from URL"
  curl -fL -o "${ZIP_OUT}" "${GODOT_DART_ARTIFACT_URL}"
}

echo "==> Downloading prebuilt extension"
if [ -n "${GITHUB_TOKEN:-}" ]; then
  download_with_token || { [ -n "${GODOT_DART_ARTIFACT_URL}" ] && download_with_url || exit 1; }
else
  [ -n "${GODOT_DART_ARTIFACT_URL}" ] && download_with_url || { echo "No token/URL."; exit 1; }
fi

echo "==> Unzipping into project root"
unzip -o "${ZIP_OUT}" -d "${PROJECT_ROOT}"

cat > "${PROJECT_ROOT}/godot_dart.gdextension" <<'EOF'
[configuration]
entry_symbol = "godot_dart_init"
compatibility_minimum = 4.2

[icons]
DartScript = "res://godot_dart/logo_dart.svg"
DartHotReload = "res://godot_dart/hot_reload.svg"

[libraries]
linux.debug.x86_64   = "res://libgodot_dart.so"
linux.release.x86_64 = "res://libgodot_dart.so"
windows.debug.x86_64 = "res://godot_dart.dll"
windows.release.x86_64 = "res://godot_dart.dll"
macos.debug = "res://libgodot_dart.dylib"
macos.release = "res://libgodot_dart.dylib"
EOF

# Première passe (générique)
if [ -d "${PROJECT_ROOT}/src" ]; then
  echo "==> dart pub get (generic)"
  (cd "${PROJECT_ROOT}/src" && dart pub get || true)
  if [ -d "${PROJECT_ROOT}/src/lib" ]; then
    echo "==> build_runner (generic, one-off)"
    (cd "${PROJECT_ROOT}/src" && dart run build_runner build --delete-conflicting-outputs || true)
  fi
else
  echo "No ./src found after unzip."; exit 1
fi

# --- Sync Dart deps for workspace (container-friendly, PUB_CACHE local projet) ---
echo "==> Syncing Dart deps into project-local PUB_CACHE"
PUB_CACHE="${PROJECT_ROOT}/.pub-cache"
(
  cd "${PROJECT_ROOT}/src"
  PUB_CACHE="$PUB_CACHE" dart pub get
  if [ -d "lib" ]; then
    PUB_CACHE="$PUB_CACHE" dart run build_runner build --delete-conflicting-outputs || true
  fi
)
echo "==> Dart deps synced (PUB_CACHE=${PUB_CACHE})"
# -------------------------------------------------------------------------------

echo "✅ Done."