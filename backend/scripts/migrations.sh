#!/usr/bin/env bash
set -Eeuo pipefail

# Blacksmith: test migrations on a restored PostgreSQL backup, optionally apply
# the SAME migration SQL to the development database after explicit confirmation.
# Run on the Ubuntu host from the backend repository; requires docker compose
# and the .NET development container used by Blacksmith.

MODE=verify
BACKEND_DIR="${BACKEND_DIR:-$(pwd)}"
COMPOSE_SERVICE="${COMPOSE_SERVICE:-db}"
PG_USER="${PG_USER:-admin}"
DOTNET_CONTAINER="${DOTNET_CONTAINER:-affectionate_wescoff}"
DOTNET_WORKDIR="${DOTNET_WORKDIR:-/workspaces/backend}"
ORIGINAL_DB="blacksmith_db"
BACKUP_FILE="${BACKUP_FILE:-$BACKEND_DIR/blacksmith_db_before_migration.dump}"

usage() {
  cat <<'HELP'
Usage: bash scripts/manage_migrations.sh [--verify | --apply | --dry-run | --help]
  --verify    Restore an existing backup into a NEW temporary DB and test migrations (default).
  --apply     Create a fresh backup, verify it on a NEW temporary DB, then request
              an exact interactive confirmation before updating blacksmith_db.
  --dry-run   Print planned actions only (no writes, no temporary database).
  --help      Show help.
Environment: BACKEND_DIR, BACKUP_FILE (--verify only), DOTNET_CONTAINER,
             DOTNET_WORKDIR, PG_USER, COMPOSE_SERVICE.
Run from backend/ where docker-compose.yml is present.
HELP
}

if [[ $# -gt 1 ]]; then usage; exit 2; fi
case "${1:---verify}" in
  --verify) MODE=verify ;;
  --apply) MODE=apply ;;
  --dry-run) MODE=dry-run ;;
  --help|-h) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "$BACKEND_DIR" = /* ]] || fail 'BACKEND_DIR must be an absolute path'
COMPOSE_FILE="$BACKEND_DIR/docker-compose.yml"
[[ -f "$COMPOSE_FILE" ]] || fail "Compose file not found: $COMPOSE_FILE"
if [[ "$MODE" == dry-run ]]; then
  echo "Plan for $BACKEND_DIR:"
  echo '  [verify] Read dump, restore to a unique temporary DB, generate EF SQL,'
  echo '           run migrations on temporary DB and compare row counts.'
  echo '  [apply]  Take NEW backup of blacksmith_db, perform all verify steps,'
  echo '           require confirmation, run SAME SQL on blacksmith_db and recheck.'
  echo 'No action taken.'
  exit 0
fi

command -v docker >/dev/null || fail 'Docker not found'
docker compose -f "$COMPOSE_FILE" config --quiet || fail 'Invalid Compose configuration'
docker inspect "$DOTNET_CONTAINER" >/dev/null 2>&1 || fail "Missing .NET container: $DOTNET_CONTAINER"
pg() { docker compose -f "$COMPOSE_FILE" exec -T "$COMPOSE_SERVICE" "$@"; }

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/blacksmith-migrations.XXXXXXXX")"
TEST_DB="blacksmith_migration_test_$(date +%Y%m%d_%H%M%S)_$$"
SQL_IN_CONTAINER="/tmp/blacksmith-migrations-${TEST_DB}.sql"
SQL_LOCAL="$RUN_DIR/migrations.sql"
QUERY='SELECT (SELECT COUNT(*) FROM public.designs), (SELECT COUNT(*) FROM public.resources), (SELECT COUNT(*) FROM public.resource_types);'
MIGRATIONS_QUERY='SELECT "MigrationId" FROM public."__EFMigrationsHistory" ORDER BY "MigrationId";'

if [[ "$MODE" == apply ]]; then
  [[ -t 0 ]] || fail '--apply requires an interactive terminal; piping confirmation is disabled'
  # Separate backup path to avoid overwriting a previously verified archive.
  BACKUP_FILE="$BACKEND_DIR/blacksmith_db_before_apply_$(date +%Y%m%d_%H%M%S)_$$.dump"
  echo "Creating fresh backup: $BACKUP_FILE"
  pg pg_dump -U "$PG_USER" -d "$ORIGINAL_DB" -Fc > "$BACKUP_FILE" || fail 'pg_dump failed'
  [[ -s "$BACKUP_FILE" ]] || fail 'Backup is empty'
else
  [[ -s "$BACKUP_FILE" ]] || fail "Backup not found or empty: $BACKUP_FILE"
fi
pg pg_restore -l < "$BACKUP_FILE" > "$RUN_DIR/dump_contents.txt" || fail 'Backup archive could not be listed'

echo "Mode: $MODE"
echo "Original database: $ORIGINAL_DB"
echo "Temporary database: $TEST_DB"
echo "Backup: $BACKUP_FILE"
echo "Reports: $RUN_DIR"

# Use identical migration SQL for the rehearsal and possible real application.
docker exec "$DOTNET_CONTAINER" sh -lc \
  "cd '$DOTNET_WORKDIR' && dotnet ef migrations script --idempotent --project src/Blacksmith.Infrastructure --startup-project src/CloudServices.Api --output '$SQL_IN_CONTAINER'"
docker cp "$DOTNET_CONTAINER:$SQL_IN_CONTAINER" "$SQL_LOCAL"
[[ -s "$SQL_LOCAL" ]] || fail 'EF migration SQL empty'

pg createdb -U "$PG_USER" "$TEST_DB"
echo 'Restoring backup into temporary database...'
pg pg_restore -U "$PG_USER" -d "$TEST_DB" --exit-on-error --no-owner < "$BACKUP_FILE" > "$RUN_DIR/restore.log"
pg psql -X -At -U "$PG_USER" -d "$TEST_DB" -c "$QUERY" > "$RUN_DIR/counts_before.txt"
pg psql -X -v ON_ERROR_STOP=1 -U "$PG_USER" -d "$TEST_DB" < "$SQL_LOCAL" > "$RUN_DIR/migration_test.log"
pg psql -X -At -U "$PG_USER" -d "$TEST_DB" -c "$QUERY" > "$RUN_DIR/counts_after.txt"
pg psql -X -At -U "$PG_USER" -d "$TEST_DB" -c "$MIGRATIONS_QUERY" > "$RUN_DIR/migrations_test.txt"

cmp -s "$RUN_DIR/counts_before.txt" "$RUN_DIR/counts_after.txt" || fail "Row counts changed on test DB; see $RUN_DIR"
echo "Verified counts (designs|resources|types): $(cat "$RUN_DIR/counts_after.txt")"
echo "Applied migration IDs on test database:"
cat "$RUN_DIR/migrations_test.txt"
echo "Temporary database retained: $TEST_DB"

if [[ "$MODE" == verify ]]; then
  echo 'SUCCESS: migration rehearsal succeeded. Original database untouched.'
  exit 0
fi

# Block writes until the operator takes the API and UI offline.
echo
echo 'Before continuing: STOP the backend API and Godot application, and check no other writers use blacksmith_db.'
echo "Your backup is stored at: $BACKUP_FILE"
echo 'The next step MODIFIES blacksmith_db. The script never deletes it.'
read -r -p 'Type exactly APPLY blacksmith_db to proceed (anything else cancels): ' ANSWER
[[ "$ANSWER" == 'APPLY blacksmith_db' ]] || { echo 'Cancelled; original database untouched.'; exit 0; }

# Refuse live update if other client sessions still connect to the original DB.
ACTIVE="$(pg psql -X -At -U "$PG_USER" -d postgres -c "SELECT count(*) FROM pg_stat_activity WHERE datname = '$ORIGINAL_DB' AND pid <> pg_backend_pid();")"
[[ "$ACTIVE" == 0 ]] || fail "Found $ACTIVE active connections to $ORIGINAL_DB. Stop backend/clients and retry."

pg psql -X -At -U "$PG_USER" -d "$ORIGINAL_DB" -c "$QUERY" > "$RUN_DIR/counts_original_before.txt"
pg psql -X -v ON_ERROR_STOP=1 -U "$PG_USER" -d "$ORIGINAL_DB" < "$SQL_LOCAL" > "$RUN_DIR/migration_original.log" || fail "Original migration failed; inspect $RUN_DIR/migration_original.log and backup; DO NOT rerun blindly"
pg psql -X -At -U "$PG_USER" -d "$ORIGINAL_DB" -c "$QUERY" > "$RUN_DIR/counts_original_after.txt"
pg psql -X -At -U "$PG_USER" -d "$ORIGINAL_DB" -c "$MIGRATIONS_QUERY" > "$RUN_DIR/migrations_original.txt"
cmp -s "$RUN_DIR/counts_original_before.txt" "$RUN_DIR/counts_original_after.txt" || fail 'Unexpected change in original row counts; inspect logs immediately'
cmp -s "$RUN_DIR/migrations_test.txt" "$RUN_DIR/migrations_original.txt" || fail 'Migration history differs between test and original; inspect logs'
echo 'SUCCESS: original DB migrated with same SQL. Counts and migration IDs match.'