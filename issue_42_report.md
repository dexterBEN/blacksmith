# Issue #42 / PR #43 — Dark desktop workspace validation

The retained workspace has one dark UI theme, a standard desktop sidebar, a
separate 3D canvas and the existing quick-placement strip. This follow-up validates
the committed correction; it introduces no visual redesign or production changes.

## Committed state under test

- Branch: `issue_42`.
- Source commit: `67fcecee21739a1bbe1faa26d87cfa73b41d9b17` (`67fcece`).
- Frontend Git tree: `11feca6f3a1d3849dc09e8c2597c27aeb1521dd1`.
- Test sources come from `git archive` of that commit, not uncommitted sources.
- Only existing native SDK artifacts and package configuration are supplied from
  the development environment. Ignored Dart bindings are generated afresh.
- Godot imports, generated files, screenshots and logs stay in isolated temporary
  projects. The source checkout and its tracked editor metadata are not used as
  the runtime project.

This documentation update preserves the tested frontend Git tree. All three
existing Git stashes and unrelated branch tips were verified unchanged. Stash
identities: `a2e5ae0a13b8`, `46ef0ba2a865`, `3757f17e0e19`.

## Retained presentation and architecture

`workspace_dark.tres` is the single workspace theme, referenced directly by both
the workspace and New Design dialog scenes. The light resource, theme toggle,
switching state and related tests have been removed. The sidebar stays **236 px**
wide with full, single-line labels. The automatic narrow sidebar and forced label
line breaks are removed. The native 3D window minimum is **960 × 640**.

```text
Isometric3DGrid
  GridRoot / ResourceRoot / lights / environment / backdrop (existing World3D)
  WorkspaceLayer
    Workspace / native layout containers / dark theme
      Header: Blacksmith | New Design | active Design guidance
      Body
        Sidebar: four GCP services, full labels, 236 px
        Center
          SubViewportContainer -> SubViewport -> orthographic camera
          Quick-placement strip: guidance + four resource buttons
  DesignLayer
    Existing modal dialog / same dark theme

Sidebar + quick strip -> ResourcePalette3D -> PlaceResource -> IsomapGridBloc
    -> existing incremental cube renderer
New Design -> DesignCubit -> existing repository / Design API
```

The native layout and scroll containers remain. The central viewport shares the
original World3D. Camera fitting uses the canvas's actual dimensions and reserves
the full tile/cube envelope. Pointer coordinates are mapped into that canvas before
ray picking. The camera fit and input mapping are unchanged by the correction.

Cloud Storage, Compute Engine, Cloud VPN and Load Balancing remain available from
both entry points. Selection enables placement; replacement updates the existing
logical tile. Cube scale and tile-top positioning remain `.68` and `.12`.
`IsomapGridBloc`, `DesignCubit`, backend, repositories, resource assets, materials,
renderer and the legacy 2D scene are unchanged. No resource persistence or GCP
provisioning is introduced.

## Corrective-pass validation results

Environment: Godot **4.4.stable.official.4c311cbee**, Dart **3.12.2**, installed
compatible Linux `godot_dart` libraries, X11, and Compatibility rendering on
Mesa 25.2.8 / llvmpipe (LLVM 20.1.2) in the VM.
Package versions remain locked. No backend, database, GCP credential or real cloud
resource is required for these checks.

| Check | Actual result |
| --- | --- |
| Fresh Dart bindings generation | **Passed**, exit 0; 57 outputs / 167 actions, four script parts and resolver match compatible generated output |
| Dart analysis | **Passed**, exit 0: `No issues found!` |
| Existing Dart unit suite | **Passed**, exit 0: **93 tests** |
| Native startup and workspace interactions | **Passed**, exit 0; production bootstrap, workspace input, reload/shutdown, clean default 3D and explicit legacy 2D launches |
| Four GCP kinds through both entry points, placement and replacement | **Passed**; native workspace marker confirms 4 kinds / 2 entry points, replacement and node/state preservation |
| Supplementary occupied-tile replacement matrix (4 kinds × 2 entry points) | **Passed**, exit 0; **8 replacements**, old cube freed, exactly one correctly typed cube, HTTP/provisioning calls 0 |
| Desktop resizing, minimum and perimeter cube visibility | **Passed**; four workspace sizes, native 960×640 minimum and independent tile/cube bounds; fresh minimum capture inspected |
| New Design dialog regression checks | **Passed**, exit 0; `live=false`, validation/cancel, pending/duplicate guard, controlled 503/201 responses, discard policy, active Design and reload; cloud calls 0 |
| Detailed 3D selection, placement and lifecycle checks | **Passed**, exit 0; 36 tile centers, GUI/gap filtering, six framing sizes / 216 resize selections, cube bounds, replacement/removal/replay and cleanup; HTTP/cloud calls 0 |
| Legacy 2D editor regressions | **Passed**, exit 0; shared-state and scene-owned diagnostic modes, selection/placement/replacement, resize, reload and palette input; HTTP/cloud calls 0 |
| Unintended HTTP / GCP provisioning guards | **Passed**; **5 runtime network traces, 0 outgoing IP connections**; application/3D/2D/probe HTTP and provisioning counters 0; Design uses only deliberate in-memory responses |

### Recorded process results

| Phase | Exit code | Wall time (seconds) |
| --- | --- | ---: |
| Fresh bindings | 0 | 63.3 |
| Dart analysis | 0 | 3.0 |
| 93 unit tests | 0 | 10.3 |
| Application / workspace / clean startup | 0 | 911.9 |
| New Design | 0 | 317.5 |
| Detailed 3D | 0 | 195.0 |
| Legacy 2D | 0 | 144.5 |
| Supplementary replacement probe | 0 | 220.9 |

Times include cold compilation and native imports in the software-rendered VM.
They are validation durations, not graphics performance measurements.

### Coverage

- Workspace viewports: **1280×800, 960×640, 1024×768, 1920×1080**. Check all
  four corner resources, full labels, fixed sidebar width, panel separation,
  active Design and native cube identity preservation during resizing.
- Detailed framing viewports: **1152×648, 960×640, 1024×768, 1280×800,
  1440×900, 1600×900**. Project native tile/cube bounds independently of the
  fitting formula and click every tile center: **216** resize-case selections.
- Physical window requests: **1152×648** and **960×640**, then **640×480** to
  verify the configured lower bound. The native window manager may keep a larger
  size; the test waits for resize processing and checks that neither dimension
  falls below the minimum.
- Both resource lists: disabled actions without selection; all four kinds;
  same-tile replacement; consumed UI clicks; original cube scene/scale/height.
  A supplementary temporary native harness additionally checks all **8** combinations
  of occupied-tile replacement (four kinds × two entry points), with one resulting
  cube and explicit HTTP/provisioning tripwires. Committed source and test files
  remain unchanged; only a temporary bootstrap wrapper invokes this harness.
- Production bootstrap: one shared BLoC, state replay after scene reload,
  scene/node/subscription cleanup and runtime shutdown. Separate clean launches
  use the unchanged production entrypoint for default 3D and explicit legacy 2D.
- New Design: validation, cancel, pending/duplicate prevention, controlled 503
  failure, explicit discard consent, controlled 201 success, active Design display,
  clearing only after success, scene reload and blocked placement while modal.
- Legacy 2D: selection, placement/replacement, redraw/reload, palette interception,
  shared state and scene-owned diagnostic mode, including its existing 640×360 check.
- Application and dialog runs trace outgoing IP connections with `strace`.
  Fail-closed cloud repository/HTTP clients reject any provisioning attempt.
  The dialog deliberately exercises two in-memory Design HTTP responses; this is
  separate from real network I/O, which is forbidden in these runs.

### Failures and diagnostics

All seven standard stages and the supplementary native probe completed with
exit code **0**. There were **no unexpected runtime errors, script/shader errors
or ObjectDB leak messages**, and no failed or timed-out check in this rerun.
No production fix was required.

After requesting a 640×480 physical window, the native readback reported the
configured minimum **960×640** and actual size **1214×731**. The window manager
retained a larger size; the configured lower bound held. The 960×640 render
viewport and perimeter-cube bounds were independently checked and captured.

An earlier corrective-pass attempt used an overly strict assertion that the
window must be exactly 960×640 after an undersized request. The observed native
readback was 1214×731, above the configured minimum. The already committed test
waits for resize processing and checks the lower bound instead. That earlier
assertion failure is not evidence of a production layout defect and is not a
failure of this committed-state rerun.

Observed non-failing diagnostics:

- The locked binding generator warns that analyzer language support is older than
  the Dart SDK; generation succeeds and analysis reports no issues.
- X11/llvmpipe warns that changing V-Sync mode is unsupported. Native resource UID
  fallback and an already-notified mouse-enter warning also appear.
- Headless Godot 4.4 editor imports print **8** `progress_dialog.cpp` `ERROR`
  lines for the 3D import and **8** for the legacy import. Both imports exit 0
  and emit required completion markers. These are editor-import diagnostics;
  the separate native runtime tests pass without error or leak messages.

The legacy diagnostic scenario deliberately omits normal DI registration. Its
expected GetIt fallback stack and scene-owned-state warning are followed by
`BLACKSMITH_GODOT_LOCAL_PASSED`; this is not an unexpected runtime failure.

## Reproduction and evidence

These are the exact validation commands, run from the committed frontend export
with existing native SDK artifacts and package configuration supplied as above:

```bash
cd frontend/src
/usr/lib/dart/bin/dart run build_runner build --delete-conflicting-outputs
/usr/lib/dart/bin/dart analyze
/usr/lib/dart/bin/dart test --reporter expanded
cd ../..
python3 frontend/scripts/test-godot.py --application --trace-network --timeout 600 --output /tmp/blacksmith-pr43-67fcece-application
python3 frontend/scripts/test-godot.py --design --trace-network --timeout 600 --output /tmp/blacksmith-pr43-67fcece-design
python3 frontend/scripts/run-isometric-3d.py --headless --timeout 600 --output /tmp/blacksmith-pr43-67fcece-3d
python3 frontend/scripts/test-godot.py --timeout 600 --output /tmp/blacksmith-pr43-67fcece-2d
```

Selected verbatim pass markers from the actual native logs:

```text
BLACKSMITH_WORKSPACE_PASSED resources=4 entry_points=2 desktop_sizes=4 minimum=960x640 active_design_preserved=true native_nodes_preserved=true
BLACKSMITH_DESKTOP_MINIMUM_PASSED minimum=960x640 actual=1214x731
BLACKSMITH_DEFAULT_APPLICATION_PASSED bloc_instances=1 kinds=4 reload=true shutdown=true repository_calls=0 http_requests=0
BLACKSMITH_DESIGN_UI_PASSED live=false cancel=true validation=true duplicate_guard=true active=true discard_after_success=true reload=true cloud_calls=0
BLACKSMITH_ISSUE35_FRAMING_PASSED sizes=6 tile_centers=216 cube_bounds=true palette_clear=true stable=true
BLACKSMITH_GODOT_SCENE_PASSED repository_calls=0 http_requests=0
BLACKSMITH_GODOT_LOCAL_PASSED repository_calls=0 http_requests=0
BLACKSMITH_PR43_REPLACEMENTS_PASSED entry_points=2 kinds=4 replacements=8 one_cube=true http_requests=0 provisioning_calls=0
```

Source export: `/tmp/blacksmith-pr43-67fcece-export`.
Driver status, exit codes, timings and command logs:
`/tmp/blacksmith-pr43-67fcece-validation`.
Supplementary probe source: `/tmp/blacksmith-pr43-replacement-probe.dart`;
runner: `/tmp/blacksmith-pr43-67fcece-supplemental.py`;
result, native log and network trace: `/tmp/blacksmith-pr43-67fcece-replacements`.
Its temporary bootstrap wrapper is restored after the run.

Native runtime logs and captures are retained in the corresponding output paths.
These paths are local validation artifacts, not durable repository files.

The workspace test produces actual Godot captures named `dark_empty.png`,
`dark_resources.png` and `minimum_resources.png`. No removed presentation is
reintroduced. Previously reviewed screenshots are not restored to the repository;
commit `67fcece` deliberately removed those image files.

## Scope

This follow-up changes only this report. It does not alter the committed UI,
production state components, tests, backend, database, Dev Containers or resources.
No real cloud operation, stash modification, history rewrite, automatic merge,
container removal or volume removal is performed.
