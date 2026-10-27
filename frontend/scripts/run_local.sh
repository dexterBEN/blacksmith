#!/usr/bin/env bash
# Keep deployment credentials out of traces, including `bash -x` launches.
set +x
set -euo pipefail

fail() {
    printf 'Blacksmith launcher: %s\n' "$1" >&2
    exit 1
}

frontend_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
env_file="$frontend_dir/../backend/.env"
[[ -f "$env_file" ]] || fail 'Missing backend/.env; configure the existing backend environment first.'
[[ -r "$env_file" ]] || fail 'Cannot read backend/.env; check its file permissions.'

# Bash read would silently skip NUL bytes; reject them rather than alter a token.
if IFS= read -r -d '' line < "$env_file"; then
    fail 'Invalid backend/.env: NUL bytes are not supported.'
fi

token=''
token_found=0
first_line=1
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if (( first_line )); then
        line="${line#$'\xef\xbb\xbf'}"
        first_line=0
    fi
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
        BlacksmithDeployment__Token=*)
            (( token_found == 0 )) || fail 'Duplicate BlacksmithDeployment__Token assignments in backend/.env.'
            # Docker --env-file values are literal: never source, eval or unquote.
            token="${line#*=}"
            token_found=1
            ;;
        BlacksmithDeployment__Token|BlacksmithDeployment__Token[[:space:]]*)
            fail 'Invalid BlacksmithDeployment__Token assignment; use KEY=value without spaces around the key.'
            ;;
    esac
done < "$env_file"

(( token_found )) || fail 'Missing BlacksmithDeployment__Token in backend/.env.'
[[ -n "${token//[[:space:]]/}" ]] || fail 'BlacksmithDeployment__Token must not be empty.'
[[ "$token" != *[[:cntrl:]]* ]] || fail 'BlacksmithDeployment__Token contains an invalid control character.'

cd -- "$frontend_dir"
export BLACKSMITH_DEPLOYMENT_TOKEN="$token"
export LD_LIBRARY_PATH="$frontend_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec godot --path "$frontend_dir" --editor "$@"
