# Issue #31 — Local resource placement without GCP provisioning

[Issue #31](https://github.com/dexterBEN/blacksmith/issues/31) · branch `issue_31`.
Base: `78c1e0883b83be2471eec177eeb7e3ca5f726464`, after
`git pull --rebase origin master`.

## Problem and resulting behavior

Choosing Cloud Storage previously updated a tile and automatically created a real
bucket. Repeating that choice could create multiple buckets for one visual cell.
Storage and Compute placement/replacement now update **local editor state only**.
Selection, sprite rendering and scene reload never request provisioning.

### Verified old call chain

`MenuOverlay` button → `AppRoot.onMenuItemChosen` → `PlaceResource` →
`IsomapGridBloc._onPlaceResource` → `CloudStorageRepository.createBucket` →
`CloudServicesApi.createBucket` → `POST /cloud_services/create-bucket` → GCS.

The repository generated a fresh timestamped bucket name per call. The BLoC
optimistically replaced the tile, counted pending requests and reported cloud
results; failed requests retained the visual. Compute already stayed local.
Scene entry/render/reload did not themselves call the repository, but palette
Storage events did, including replacement and repeated clicks.

### New flow and focused changes

`Select tile → choose Storage/Compute → PlaceResource → immutable tile-map update
→ render one sprite on that cell`.

- Remove the cloud dependency and asynchronous provisioning/completion handler
  from `IsomapGridBloc`; both kinds now use the same synchronous local operation.
- Keep `GridPos(row, col)`, bounds validation, immutable state snapshots and
  one resource per tile. Missing selection is ignored. Invalid tile clicks
  preserve the previous valid selection; initially invalid clicks cannot enable
  placement. Repeated selection/placement does not duplicate entries.
- Remove obsolete `pendingOperations`, `PlacementResult`/`PlacementStatus` and
  `lastResult`, together with AppRoot's bucket-created/failed messages. Local
  placement does not simulate deployment success.
- DI still registers the existing cloud API/repository lazily for explicit use,
  but constructing the editor BLoC no longer resolves them. Normal and diagnostic
  BLoCs have the same local placement semantics.
- AppRoot derives palette availability from the BLoC selection. Before selection,
  both buttons are disabled/dimmed and explain “Select a tile before placing a
  resource.” Once selected, their normal service tooltips return. No second
  selected-position state is introduced.

Production changes affect only `app_root.dart`, `menu_overlay.dart`,
`core/di/service_locator.dart` and the existing grid BLoC/state. Unit/native fixture
updates use existing components; no new service, repository, BLoC or scene is added.
The README now describes local-only placement and corrects its stale port-5256
note to match the unchanged explicit client's port-5100 default.

## Explicit cloud capability remains separate

`CloudStorageRepository`, `CloudServicesApi` and the backend are unchanged.
The explicit contract remains an empty-body POST with encoded `projectId` and
`bucketName` query parameters to `/cloud_services/create-bucket`, returning
HTTP 200 and a JSON message. Existing repository naming/project handling,
timeout uncertainty, sanitized errors, no automatic retries and client disposal
are still covered by mocked unit tests.

No Deploy UI, provisioning event or persistence API integration was added.
No explicit cloud request was sent during implementation or verification.

## Verification

The normal-DI tests register a fail-closed cloud repository and HTTP client:
accidental calls are counted and rejected. Tests assert **zero repository calls
and zero backend HTTP requests**, including teardown, rather than relying only
on the diagnostic local constructor.

| Check | Actual result |
| --- | --- |
| `dart analyze` | Passed; no issues |
| `dart test --reporter expanded` | 52 tests passed, including unchanged explicit API timeout/error tests |
| Negative control | New configured-DI regression test fails against the base BLoC/state/DI: three forbidden provisioning attempts detected; doubles prevent network access |
| Native Godot 2D | Import marker, main scene and diagnostic checks passed; both scene markers report `repository_calls=0 http_requests=0` |
| Native Godot 3D | Import marker and headless selection/lifecycle checks passed: 36 centers, gaps, GUI, resize, reload, listener cleanup and zero repository/HTTP calls |
| Git-export verification | 52 tests and static analysis pass from the candidate export; all 27 2D and 35 3D committed runtime inputs match the tested native fixtures |

The 2D fixture drives the actual palette: disabled/no-selection feedback, both
kinds, replacement in both directions, repeated clicks retaining one sprite,
explicit redraw, shared-state scene reload, resizing/highlighting and GUI input
interception. Diagnostic mode retains its scene-owned lifetime and resets when
that scene is destroyed. The existing 3D fixture retains its selection/lifecycle
checks; only its test constructor/registrations and obsolete state check change.

Commands from the repository root:

```bash
cd frontend/src
/usr/lib/dart/bin/dart analyze
/usr/lib/dart/bin/dart test --reporter expanded
cd ../..
python3 frontend/scripts/test-godot.py --timeout 600
python3 frontend/scripts/run-isometric-3d.py --headless --timeout 600 --output /tmp/blacksmith-issue31-3d
```

Native tests use the existing Godot 4.4/Dart libraries and local generated bindings
in temporary projects, with fake dependencies and no backend/database/credentials.
Logs and temporary negative-control files stay outside the repository.

The verified frontend Git tree is `9e41cf8f5e642f723ca15032b306c89caf54ff0a`.
Before publication, the final commit is checked against that same tree. The
export uses existing ignored generated bindings and package configuration as
development prerequisites, not additional application/test source changes.

The headless editor import emits the existing Godot 4.4
`editor/progress_dialog.cpp` diagnostics on this VM, despite exit code 0 and its
positive Dart-initialization marker. This is not an error-free import claim.
Both 2D runtime logs and the 3D runtime log have no engine/script/shader errors
or ObjectDB leak warnings. The 3D fixture deliberately triggers a DI failure to
test fallback ownership; its GetIt stack trace/local-state warning is expected.
Existing scene-UID warnings resolve through text paths. No engine or renderer
configuration was changed to suppress these diagnostics.

## Manual validation

With the usual local Godot/Dart development prerequisites available, run the
unchanged production `frontend/main.tscn`:

1. Before selecting a tile, hover the disabled palette and confirm its instruction.
2. Select a tile; choose Storage, then Compute, then Storage again. Confirm one
   visual resource on that tile and no bucket-created/failed message.
3. Repeat a choice, select another tile and place a resource there; confirm both
   placements and selection behave normally.
4. Reload the scene within the same shared runtime; placements are reconstructed.
   Fully restart the application; the editor starts empty.

These are reproducible user checks; automated native checks above exercise the
corresponding behavior. No separate manual GUI session is claimed.

## Limitations and scope

There is **no durable persistence**: normal in-memory state survives scene reload,
but not a full application restart. Diagnostic fallback state belongs to its
scene and resets on scene disposal. Save/load Designs and Resources remain
separate work.

No backend, database, migration, GCP resource, credential infrastructure,
production 2D/3D scene, renderer, asset, camera or Dev Container was modified.
The standalone 3D view still supports selection only; its palette/dynamic
resources remain a follow-up. Only Storage and Compute are placeable kinds.
Existing branches/stashes, including deferred lighting work, are preserved.
Publication uses a normal commit; no history rewrite or automatic merge.
