# Issue #70 — Refactor and simplify frontend development scripts

Implements [issue #70](https://github.com/dexterBEN/blacksmith/issues/70).

The frontend's development scripts mixed daily commands, visual previews and integration fixtures in one directory. `dev.sh` also ran Dart in `frontend/` instead of the package directory `frontend/src/`, used a different default package cache from the installer, duplicated Godot launch setup and deleted the dependency lockfile during reset.

This change provides a small command dispatcher, separates scripts by purpose and preserves specialized runners and their existing CLI options. It does not change application state management, backend logic, cloud provisioning or godot_dart dependencies.

## Supported commands

| Command | Behavior |
| --- | --- |
| `build` | Resolve dependencies and generate bindings from `frontend/src` |
| `host-build` | Recreate generated Dart tooling state with the host SDK, then resolve/build |
| `reset` | Clear generated `.dart_tool` state and rebuild with the configured SDK |
| `run` | Delegate to the existing canonical `run_local.sh` editor launcher |
| `test` | Delegate to the isolated Godot integration runner, preserving its options |
| `check` | Delegate to resource cube dependency validation |
| `preview` | Delegate to the isolated Dart 3D preview |
| `preview-cubes` | Delegate to the native cube preview without Dart |

All commands resolve their locations independently of the caller's working directory. Godot and Python runner arguments are forwarded unchanged, including whitespace and literal shell characters. Child exit codes propagate to callers. Bash tracing is disabled at entry to avoid exposing inherited sensitive values.

Dart work is implemented once in `build_dart.sh`, keeping `dev.sh` a dispatcher. The default cache is `frontend/.pub-cache`, matching the existing installer and frontend DevContainer. Explicit `PUB_CACHE` and `DART_BIN` settings are supported, including paths containing spaces; relative overrides are resolved before entering the package directory. On the Ubuntu host, `host-build` prefers `/usr/lib/dart/bin/dart` when available, avoiding the Flutter wrapper earlier in PATH.

`build` preserves incremental generator state. `host-build` and `reset` remove only generated `frontend/src/.dart_tool` state and rebuild it; they preserve `pubspec.lock` and do not upgrade dependencies, launch Godot or contact cloud provisioning endpoints. Missing executables are detected before cleanup. Dependency and generator failures stop the command and identify the failing stage.

## Script organization

```text
frontend/scripts/
  dev.sh
  build_dart.sh
  run_local.sh
  install.sh
  check_resource_cubes.py
  script_support.py
  README.md
  tests/
    test_dev.py
    test_run_local.py
    test-godot.py
    check-workspace-scene-save.gd
  preview/
    run-isometric-3d.py
    preview-resource-cubes.py
  fixtures/
    start-design-test-backend.py
    design-test-backend/
    deployment-test-backend/
```

`install.sh` remains byte-for-byte unchanged. `run_local.sh` remains the canonical launcher. Script paths, Python imports, source-root resolution, Godot fixture resource paths, test project references and documentation callers were updated. The former flat paths are intentionally replaced by the organized paths above; external automation must use the new paths or `dev.sh`. Python bytecode is ignored locally under scripts.

Both preview tools remain useful: the Dart preview retains isolated placement, framing, resize, lifecycle, headless and material-variant capabilities, while the native preview renders cubes without Dart. They are not replaced by application-startup tests. Only frontend-root resolution and isolated XDG environment creation are shared; fixture copying and native process checks remain specialized to avoid a broad test infrastructure rewrite.

Validation exposed a pre-existing native-cube fixture assumption: its GDScript still expected `Camera3D` directly below the root, although the production camera had moved into the workspace SubViewport. The fixture now reparents that existing camera into its own root viewport, removes unused workspace overlays and asserts the active camera before capture. Production scenes and runtime Dart behavior are unchanged. The corrected capture was visually inspected.

## Host and container workflow

Recommended Ubuntu host sequence:

```bash
cd frontend
./scripts/dev.sh host-build
./scripts/dev.sh run
```

The frontend DevContainer uses `build` with its installed SDK. Host/container portability of `.dart_tool` is not solved: both environments share this directory, and dependency resolution in one can invalidate paths and generator state for the other. Run `host-build` again after container work before starting native Godot on the host. Concurrent builds across environments remain unsupported. This limitation and the supported command/cache overrides are documented in `frontend/scripts/README.md`, linked from the main and Dart READMEs.

## Validation

| Check | Result |
| --- | --- |
| Bash syntax and Python parsing | Passed |
| Offline launcher/dispatcher regressions | **21 passed**: 12 preserved launcher tests and 9 new command/build tests |
| Ubuntu `host-build` with Dart 3.12.2 | Passed dependency resolution and binding generation |
| Standard `build` with the configured standalone SDK | Passed |
| Existing Dart suite | **225 passed** |
| Resource dependencies and Git index validation | Passed: 20 assets/dependencies |
| Native cube preview | Passed: active camera, geometry/material checks and real capture |
| Isolated Dart 3D preview | Passed: selection, placement/replacement, framing, resize, lifecycle and rendering |
| Real canonical editor launcher | Passed isolated import through `run_local.sh`, including argument forwarding and network tracing |
| Application import and scene save/reload | Passed: production bootstrap and preservation of viewport/camera across two save cycles |
| Clean production 3D and explicit legacy 2D startup | Passed separately in headless mode, without application instrumentation; no outgoing IP connections |
| Real API/PostgreSQL persistence | Passed Save, full Godot exit and Open; independent SQL verification confirmed two resource IDs, configurations and coordinates |
| Fake-provider Save & Deploy | Passed save/retry/recovery journey, fixture API restart with database retained, and Open in a new Godot process |
| Fake-provider counters after restart and Open | Zero create/inspection calls; resource/configuration/operation/attempt counts preserved |
| Full graphical application interaction matrix | **Incomplete: reached the 900-second timeout on llvmpipe**; not counted as passed |
| Installer, lockfile and tracked Dart resolver | Byte-for-byte unchanged |
| Final whitespace check | `git diff --check` passed |

Core checks can be reproduced from the repository root:

```bash
python3 -m unittest discover -s frontend/scripts/tests -p 'test_*.py'
frontend/scripts/dev.sh host-build
DART_BIN=/usr/lib/dart/bin/dart frontend/scripts/dev.sh build
frontend/scripts/dev.sh check --require-tracked
```

The native integration commands and dedicated backend fixture lifecycle are documented in `frontend/scripts/README.md` and `frontend/src/README.md`. Run those checks sequentially and target only the dedicated test APIs.

The full graphical interaction matrix emitted no native assertion failure before timeout and produced initial workspace captures. The validation VM uses llvmpipe software rendering; the isolated 3D runtime sample measured approximately 4 FPS. The complete multi-resolution/dock matrix and its graphical clean-launch captures therefore remain unverified in this run. The separate headless production startup checks do not replace those visual assertions. No test assertions or supported test modes were removed to obtain a passing result.

The compatible locked generator emits its existing analyzer/Dart SDK version warning. Dependencies were not upgraded to silence it. Host/container `.dart_tool` portability remains the documented workflow limitation; it is not claimed as fixed. Validation used the Ubuntu host and an existing backend DevContainer; a separate frontend DevContainer was not started.

Evidence retained on the validation machine:

- `/tmp/blacksmith-issue70-cubes-fixed` — native cube capture and report; capture visually inspected.
- `/tmp/blacksmith-issue70-preview-fixed` — native 3D preview, framing and placement evidence.
- `/tmp/blacksmith-issue70-application` — successful import/scene-save logs and the timed-out graphical matrix trace/captures.
- `/tmp/blacksmith-issue70-clean-startup` — clean production 3D and legacy 2D headless startup/network logs.
- `/tmp/blacksmith-issue70-persistence` — Save/Open restart proof, HTTP logs, configurations and captures.
- `/tmp/blacksmith-issue70-deployment` — fake-provider save/reopen proof, HTTP logs and captures.

Backend validation used uniquely named fixture databases on the existing PostgreSQL server, never the development database. Both were dropped through their fixture launchers, and a PostgreSQL query confirmed that neither database remained. The existing backend DevContainer was initially stopped; it was started for validation and returned to its stopped state afterward. No containers or volumes were created or deleted, no backend application logic was modified, and no real cloud provisioning occurred.
