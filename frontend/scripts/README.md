# Frontend development scripts

Run commands from `frontend/`, or invoke `dev.sh` by its path from any directory.
It is a small dispatcher; specialized scripts remain available with their advanced
arguments. Python 3 and Bash are required; native checks also require the existing
compatible Godot/Dart libraries and generated bindings.

| Command | Purpose |
| --- | --- |
| `./scripts/dev.sh build` | Run `dart pub get` and binding generation in `frontend/src` |
| `./scripts/dev.sh host-build` | Remove generated `src/.dart_tool`, resolve dependencies and regenerate bindings for the host |
| `./scripts/dev.sh reset` | Clear generated `src/.dart_tool`, then rebuild using the configured Dart executable |
| `./scripts/dev.sh run [Godot arguments]` | Open the Godot editor through the canonical `run_local.sh` launcher |
| `./scripts/dev.sh test [options]` | Run `tests/test-godot.py`; default is the existing legacy 2D check |
| `./scripts/dev.sh check [options]` | Validate resource cube dependencies (`--require-tracked` checks the Git index) |
| `./scripts/dev.sh preview [options]` | Run the isolated Dart 3D scene; supports `--check`, `--headless`, focused `--speed-dial` / `--resources-modal` checks and material variants |
| `./scripts/dev.sh preview-cubes [options]` | Preview/check native resource cubes without Dart |

`build`, `host-build` and `reset` all preserve `src/pubspec.lock`; they never run a
dependency upgrade, start Godot, launch an API or provision cloud resources.
`host-build` and `reset` remove the entire generated `.dart_tool` directory,
including build_runner state, so code generation after these commands is a cold
build. `build` keeps that state for incremental generation. Dependency resolution
may still need network access; existing package versions must be compatible with
the selected SDK. A failure stops the sequence and reports the failing stage.

## Ubuntu host

Prepare the existing native libraries separately, then:

```bash
cd frontend
./scripts/dev.sh host-build
./scripts/dev.sh run
# F5 in Godot runs the application.
```

On Ubuntu, `host-build` prefers `/usr/lib/dart/bin/dart` when installed, avoiding a
Flutter wrapper earlier in PATH. `DART_BIN` overrides this choice, including paths
containing spaces. Other build commands use `dart` from PATH unless overridden:

```bash
DART_BIN=/usr/lib/dart/bin/dart ./scripts/dev.sh build
./scripts/dev.sh run --verbose
./scripts/dev.sh test --application --trace-network --timeout 600 --output /tmp/blacksmith-startup
./scripts/dev.sh preview --check --timeout 600 --output /tmp/blacksmith-placement
```

The default cache is `frontend/.pub-cache`, matching the existing installer and
frontend DevContainer setting. An explicit `PUB_CACHE` is respected. Relative
cache paths and executable paths are resolved from the invoking working directory
before changing to the Dart package. No `.env` or deployment token is required by
the launcher. Godot arguments and existing `LD_LIBRARY_PATH` entries are preserved.

## Frontend DevContainer

Use `./scripts/dev.sh build` with the container's installed Dart SDK. The existing
`install.sh` remains the initial setup hook and is unchanged. It installs tooling
and native artifacts; it is not a daily launcher. The graphical editor runs on the
Ubuntu host, not as part of these container build commands.

Host and container share `src/.dart_tool`; running dependency resolution in one
can invalidate SDK/package paths and generated build state for the other. Run
`host-build` again after working in the container before launching native Godot
on the host. This workflow regenerates environment-specific state; it does not
make Dart package configuration portable or support concurrent host/container
builds. If both environments share an explicitly configured package cache, keep
its paths and permissions valid in each environment.

## Organization and specialized tools

```text
scripts/
  dev.sh, build_dart.sh       command dispatch and Dart preparation
  run_local.sh               canonical host editor launcher
  install.sh                 unchanged initial environment installer
  check_resource_cubes.py    shared asset dependency validation
  script_support.py          frontend path and isolated XDG environment helper
  tests/
    test_dev.py, test_run_local.py
    test-godot.py
    check-workspace-scene-save.gd (+ its Godot UID)
  preview/
    run-isometric-3d.py
    preview-resource-cubes.py
  fixtures/
    start-design-test-backend.py
    design-test-backend/
    deployment-test-backend/
```

The Dart 3D preview retains headless placement/framing checks, material experiments
and interactive use without a backend. The native cube preview has no Dart
requirement. Neither is fully replaced by application-startup tests. Fixture copy
and process checks stay specialized because their native bootstraps and success
conditions differ; only genuinely common XDG setup is shared.

Offline shell/dispatcher regressions:

```bash
python3 scripts/tests/test_run_local.py
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
```

The backend fixture launcher is run on the host with access to the existing
backend DevContainer. It snapshots the API into `/tmp`, creates a uniquely named
test database on the configured PostgreSQL server, and leaves the development
database untouched. It creates no containers or volumes. Use the exact RUN_PATH
printed by the launcher for verification and cleanup:

```bash
python3 scripts/fixtures/start-design-test-backend.py CONTAINER --port 5139
python3 scripts/fixtures/start-design-test-backend.py CONTAINER --stop RUN_PATH
# Fake-provider Save & Deploy fixture; never invokes real GCP:
python3 scripts/fixtures/start-design-test-backend.py CONTAINER --deployment --port 5148
python3 scripts/fixtures/start-design-test-backend.py CONTAINER --restart RUN_PATH
```

Use `--help` on the specialized scripts for all options. See
[the Dart workflow](../src/README.md) for the real API persistence and fake-provider
Save & Deploy journeys. Run native checks sequentially because godot_dart's VM
service uses fixed ports. Even some `--headless` modes perform an editor import
that can require a graphical session.

On software renderers such as llvmpipe, cold Dart startup and large native UI
matrices can take many minutes. Increase the runner's `--timeout` when needed;
a timeout does not establish that the UI checks passed. See the issue report
for the checks actually completed on the validation VM.
