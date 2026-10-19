#!/usr/bin/env bash
set -euo pipefail

# Requires .NET 8 and PostgreSQL 16 binaries. Initializes a fresh private cluster;
# never uses the application's connection string, Docker containers, or volumes.
backend_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
dotnet_command="${DOTNET_COMMAND:-dotnet}"
pg_bindir="${PG_BINDIR:-}"
if [[ -z "$pg_bindir" ]]; then
    if command -v pg_config >/dev/null 2>&1; then
        pg_bindir="$(pg_config --bindir)"
    elif command -v initdb >/dev/null 2>&1; then
        pg_bindir="$(dirname -- "$(command -v initdb)")"
    else
        echo "Set PG_BINDIR to the directory containing PostgreSQL 16 initdb and pg_ctl." >&2
        exit 1
    fi
fi
for executable in initdb pg_ctl; do
    if [[ ! -x "$pg_bindir/$executable" ]]; then
        echo "Missing PostgreSQL executable: $pg_bindir/$executable" >&2
        exit 1
    fi
done

test_directory="$(mktemp -d /tmp/blacksmith-pg-tests.XXXXXXXX)"
echo "Isolated PostgreSQL cluster: $test_directory"
mkdir -m 700 "$test_directory/socket"
started=false
stop_cluster() {
    if [[ "$started" == true ]]; then
        "$pg_bindir/pg_ctl" -D "$test_directory/data" -m fast -w stop
    fi
    echo "Test files retained for inspection: $test_directory"
}
trap stop_cluster EXIT
"$pg_bindir/initdb" -D "$test_directory/data" --username=blacksmith_test \
    --auth=trust --encoding=UTF8 --locale=C.UTF-8 >"$test_directory/initdb.log"
cat >>"$test_directory/data/postgresql.conf" <<EOF
listen_addresses = ''
unix_socket_directories = '$test_directory/socket'
unix_socket_permissions = 0700
max_connections = 40
shared_buffers = '32MB'
EOF
"$pg_bindir/pg_ctl" -D "$test_directory/data" -l "$test_directory/postgresql.log" -w start
started=true
export BLACKSMITH_TEST_POSTGRES="Host=$test_directory/socket;Username=blacksmith_test;Database=postgres;Pooling=false"
"$dotnet_command" test "$backend_dir/BlacksmithBackend.sln" --configuration Release "$@"
