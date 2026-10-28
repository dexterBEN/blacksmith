# Local startup and non-cloud smoke test

This is the existing GCP-only development workflow: Godot/Dart on the Ubuntu
host, .NET 8 in the backend Dev Container, PostgreSQL 16 in Docker Compose.
Reopening a Design reads PostgreSQL through the API; it does not query Google.
The developer has already demonstrated real bucket creation separately.
These checks do not repeat that deployment or verify a real bucket's current state.

## After restarting the VM

1. **Ubuntu host, repository root:** start the existing database if needed:

   ```bash
   docker compose -f backend/docker-compose.yml up -d db
   docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'
   ss -ltnp '( sport = :5100 )'
   curl -fsS http://localhost:5100/cloud_services/ping
   curl -fsS http://localhost:5100/db/ping
   ```

   Reuse a healthy intended API. A listener named `code` may be VS Code's port
   forward, rather than another API. Check the container too before launching
   another server: `docker top CONTAINER_ID -eo pid,comm` shows process IDs and
   names without printing environment variables. If available inside the container,
   `ss -ltnp '( sport = :5100 )'` identifies its actual listener.

2. **VS Code:** open `backend/` in its existing Dev Container. Its `runArgs`
   loads `backend/.env` when the container is created. The existing settings are
   `BlacksmithDeployment__Enabled`, `BlacksmithDeployment__ApprovedProjects__0`
   and `BlacksmithDeployment__Token`; do not copy them into Dart, a scene or a
   terminal command. The frontend and container have separate environments.
   Changing `.env` requires recreating/rebuilding the Dev Container to inherit
   new values; restarting only `dotnet` cannot update the container environment.
   Its existing connection string targets the Compose database.

3. **Backend Dev Container, `/workspaces/backend`:** if the intended API is not
   already running, start it in a terminal that you keep open:

   ```bash
   ASPNETCORE_ENVIRONMENT=Development dotnet run \
     --project src/CloudServices.Api --no-launch-profile \
     --urls http://0.0.0.0:5100
   ```

   Keep one intended API per container port. `Address already in use` means a
   second server cannot bind that port. Reuse the healthy existing server or
   stop the **identified API** with Ctrl+C in its original terminal, then restart.
   Do not kill an arbitrary PID, remove a container or delete a volume.
   VS Code forwards this port to the host; repeat the two host `curl` checks.
   Startup does not apply EF migrations. If the API reports missing tables, stop
   and use a separately reviewed migration procedure; do not reset the database.

4. **Ubuntu host, repository root:** open the existing graphical editor:

   ```bash
   cd frontend
   bash scripts/run_local.sh
   ```

   Use Run Project (F5) for the default 3D workspace. The launcher resolves paths
   from its own location, so it also works from another directory. It reads only
   the deployment token from the ignored backend `.env`, passes it to Godot and
   its children, preserves `LD_LIBRARY_PATH`, forwards extra Godot arguments and
   propagates its exit code. It never sources `.env` or displays the secret.
   No manual token export or frontend secret file is needed in a new terminal.

Prerequisites are the existing host Godot 4.4, compatible native Godot/Dart
libraries and Dart dependencies/bindings. Mounted ADC credentials and cloud IAM
permissions are needed **only for an explicitly authorized real deployment**,
not Save configuration, Open or the fake-provider tests. The existing Dev Container
mount must still exist for Docker to start that configured container; this
procedure does not change its mounts or authorization policy.

## Dependency/code-generation refresh, only when needed

From the **Ubuntu host**, repository root:

```bash
cd frontend/src
/usr/lib/dart/bin/dart pub get
/usr/lib/dart/bin/dart run build_runner build --delete-conflicting-outputs
```

Keep the committed `pubspec.lock` and `.dart_tool/`. Normal startup does not need
dependency resolution or generation on every run. The standalone Dart SDK path
above avoids accidentally using this VM's Flutter Dart installation. If packages
were resolved in a container and contain inaccessible paths, resolve them again
on the host; inspect the error before deleting anything. Keep native libraries
compatible with the project's Godot/Dart versions. Generation may warn that its
pinned analyzer is older than the host Dart SDK; use analysis and native checks
to verify the resulting bindings.

## Read-only restoration check

Use an existing Design ID with two configured Cloud Storage resources, preferably
one with a deployment record and one saved without deployment. Do not overwrite
it or deploy a new resource to obtain a fixture.

For each of five cycles, launch the editor/application, choose **Open**, enter the
same ID and confirm that the same Resource IDs occupy the same tiles. Open each
configuration, compare its complete JSON and close with **Cancel**. The workspace
summary reports deployment status; the existing configuration dialog reports the
selected resource's outcome. Compare with these **read-only** API endpoints:

```text
GET /designs/{designId}
GET /designs/{designId}/resources?include=configuration
GET /resources/{resourceId}?include=configuration
GET /designs/{designId}/resources/{resourceId}/deployments/{operationId}
```

The model has `pending`, `succeeded`, `failed` and `unknown`, not a `saved`
deployment status. Save-only has **no deployment record**. An expired pending
execution is projected as `unknown` / `execution_interrupted` by metadata reads;
the stored row is not rewritten by that read. Success is evidence associated
with a particular Resource revision, not an ongoing live health check.

Close the player and editor between cycles; restart the intended backend in at
least one cycle. Reads must retain identities/configurations and must not add
Resources, operations or attempts. Unknown must remain unconfirmed without an
automatic retry. Prefer the isolated protocol below if existing data does not
cover the required states.

**Action boundaries:** Open, startup, configuration review/Cancel and ordinary
deployment GETs are database-only reads. Save configuration/header Save write
the database but do not provision GCP. Check Save recovers metadata without a
cloud call. **Check deployment** is a separate explicit provider inspection and
can add an attempt. **Save & Deploy / Retry deployment** can create billable
resources and require target/cost approval, valid authorization and fresh consent.
Do not press those buttons while validating read-only reopen behavior.

## Automated regressions and five native reopen cycles

No real GCP project, token or ADC is used by the deployment fixture. The test host
injects `RecordingBucketProvider`; its literal token authorizes only that fixture.
It creates/migrates a uniquely named `blacksmith_front_smoke_*` database on the
existing PostgreSQL server. It never migrates or clears `blacksmith_db`.

From the **Ubuntu host**, repository root:

```bash
python3 frontend/scripts/test_run_local.py
cd frontend/src
/usr/lib/dart/bin/dart analyze
/usr/lib/dart/bin/dart test
cd ../..
```

In the **backend Dev Container**, run the existing unit/HTTP tests:

```bash
cd /workspaces/backend
dotnet test BlacksmithBackend.sln --configuration Release --no-restore
```

PostgreSQL tests are skipped without `BLACKSMITH_TEST_POSTGRES`. Use an isolated
test server/administrative connection with CREATE DATABASE permission; each test
creates and removes only its own random database. Never paste its password into
a command/report. The existing `backend/scripts/test-postgresql.sh` can instead
create a private host cluster when .NET 8 and PostgreSQL 16 binaries are available.

For native checks, substitute the current backend container ID and its numeric
Docker-network IP (inspect with `docker inspect --format
'{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' CONTAINER_ID`).
Choose an unused dedicated port, separate from the live API's 5100:

```bash
# Host terminal A: leave the fake API supervisor running; note RUN_PATH.
python3 frontend/scripts/start-design-test-backend.py CONTAINER_ID --deployment --port 5146

# Host terminal B: seeds two resources through the real UI/API, fake cloud only.
python3 frontend/scripts/test-godot.py --deployment http://CONTAINER_IP:5146 \
  --persistence-phase save --local-editor --trace-network --timeout 600 \
  --output /tmp/blacksmith-local-smoke

# Restart that test API process while retaining ONLY its isolated database.
python3 frontend/scripts/start-design-test-backend.py CONTAINER_ID --restart RUN_PATH
# Wait for the next BLACKSMITH_DEPLOYMENT_BACKEND_STARTED message in terminal A.

# Import through the real editor, then five complete player restart/Open cycles.
python3 frontend/scripts/test-godot.py --deployment http://CONTAINER_IP:5146 \
  --persistence-phase open --reopen-cycles 5 --local-editor --trace-network \
  --timeout 600 --output /tmp/blacksmith-local-smoke

# Stop the test host; it removes ONLY the disposable DB it created.
python3 frontend/scripts/start-design-test-backend.py CONTAINER_ID --stop RUN_PATH
```

The initial import uses the **real graphical host launcher**; each of the five
cycles then runs a distinct native player with the production bootstrap wrapped
by test instrumentation. The editor need not re-import between player launches.
That wrapper supplies fixture repositories/token and drives existing native UI
events; no production source or scene is patched. `--local-editor` requires the
real ignored backend `.env` but its token is used only by the editor process;
the player uses the fixture token. `--trace-network` requires installed Linux
`strace` with `--seccomp-bpf` support (available on this Ubuntu VM), which avoids
tracing unrelated syscalls during cold Dart compilation. It rejects IP connections
outside the dedicated API, except the real
editor's exact advertised loopback Dart VM debugger endpoint. The player has no
debugger exception. Logs omit headers.
This is automated native validation, not five human F5 sessions or VM reboots.

The fake provider's in-memory counters/buckets reset on backend process restart;
the persisted PostgreSQL Resource/configuration/deployment/attempt rows do not.
Zero creates/inspections after that restart proves metadata reopen never tries to
reconstruct cloud state. Per-cycle JSON, HTTP methods, network traces and actual
Godot PNGs stay under the requested `/tmp` output directory.

Existing independent regressions remain available:

```bash
python3 frontend/scripts/test-godot.py --application --trace-network --timeout 600
python3 frontend/scripts/test-godot.py --design --trace-network --timeout 600
python3 frontend/scripts/test-godot.py --timeout 600
```

Run editor/import commands sequentially on this VM. The existing headless Godot
4.4 import can emit progress-dialog errors even when import and subsequent runtime
checks pass; the harness still rejects Dart/native exceptions. See the
[validation report](../issue_60_report.md) for the actual warnings and outcomes.

The all-status PostgreSQL regression models succeeded/failed/unknown, active and
expired pending executions plus a saved-only resource, checks five fresh API hosts
and verifies complete table fingerprints. No UI status-indicator redesign is part
of this baseline; richer per-resource status visuals remain a separate follow-up.
