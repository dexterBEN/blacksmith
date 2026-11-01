// Production bootstrap with asynchronous in-memory repositories; never HTTP/GCP.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async' as async;
import 'dart:io';
import 'package:godot_dart/godot_dart.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import '../lib/core/di/service_locator.dart' as di;
import '../lib/data/repositories/design_repository.dart';
import '../lib/data/repositories/resource_repository.dart';
import '../lib/data/repositories/cloud_storage_repository.dart';
import '../lib/data/services/cloud_services_api.dart';
import '../lib/domain/bloc/design/design_cubit.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_event.dart';
import '../lib/domain/models/design.dart';
import '../lib/domain/models/design_summary.dart';
import '../lib/prototypes/isometric_3d/design_browser_3d.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/persisted_resource.dart';
import '../lib/domain/models/resource_kind.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import 'isometric_3d_framing_checks.dart';
import 'workspace_test_input.dart';

class _NoHttp extends http.BaseClient {
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    throw StateError('HTTP forbidden in the empty workspace regression.');
  }
}

class _Designs extends DesignRepository {
  _Designs() : super(baseUrl: 'http://forbidden.invalid', client: _http);
  int creates = 0, reads = 0;
  var createResult = async.Completer<Design>();
  var readResult = async.Completer<Design>();
  @override
  Future<Design> create(String name) {
    creates++;
    return createResult.future;
  }

  @override
  Future<List<DesignSummary>> listDesigns() async =>
      [const DesignSummary(id: _id, name: 'Restored Design')];
  @override
  Future<Design> getById(String id) {
    reads++;
    return readResult.future;
  }
}

class _Resources extends ResourceRepository {
  _Resources() : super(baseUrl: 'http://forbidden.invalid', client: _http);
  int reads = 0;
  final result = async.Completer<List<PersistedResource>>();
  @override
  Future<List<PersistedResource>> listForDesign(String id,
      {int rows = 6, int cols = 6}) {
    reads++;
    return result.future;
  }
}

class _Grid extends IsomapGridBloc {
  int selections = 0, placements = 0;
  @override
  void onEvent(IsomapGridEvent event) {
    if (event is TileClicked) selections++;
    if (event is PlaceResource) placements++;
    super.onEvent(event);
  }
}

class _DesignLifecycle extends DesignCubit {
  _DesignLifecycle(DesignRepository repository, IsomapGridBloc grid,
      ResourceRepository resources)
      : super(repository, grid, resources: resources);
  // There is currently no production Close Design command. This test-only
  // transition verifies how the view reacts if an owner clears active state.
  void clearForTest() {
    emit(const DesignState());
  }
}

final _http = _NoHttp();
late final _Designs _designs;
late final _Resources _resources;
late final _Grid _grid;
late final _DesignLifecycle _design;
const _id = '12345678-1234-1234-1234-123456789abc';

void beforeStartup() {
  if (Engine.singleton.isEditorHint()) return;
  _designs = _Designs();
  _resources = _Resources();
  _grid = _Grid();
  _design = _DesignLifecycle(_designs, _grid, _resources);
  final api =
      CloudServicesApi(baseUrl: 'http://forbidden.invalid', client: _http);
  di.sl.registerSingleton<CloudServicesApi>(api, dispose: (a) => a.close());
  di.sl.registerSingleton<CloudStorageRepository>(
      CloudStorageRepository(api, projectId: 'forbidden-fixture-project'));
  di.sl
      .registerSingleton<DesignRepository>(_designs, dispose: (r) => r.close());
  di.sl.registerSingleton<ResourceRepository>(_resources,
      dispose: (r) => r.close());
  di.sl.registerSingleton<IsomapGridBloc>(_grid, dispose: (g) => g.close());
  di.sl.registerSingleton<DesignCubit>(_design, dispose: (c) => c.close());
}

void afterStartup() {
  if (Engine.singleton.isEditorHint()) return;
  async.Timer.run(() async {
    final tree = Engine.singleton.getMainLoop()! as SceneTree;
    try {
      final window = tree.getRoot()!;
      window
        ..setFlag(WindowFlags.flagMousePassthrough, true)
        ..setFlag(WindowFlags.flagNoFocus, true)
        ..setContentScaleMode(WindowContentScaleMode.disabled)
        ..setContentScaleSize(Vector2i.fromXY(0, 0));
      await _until(() => tree.getCurrentScene() != null);
      var scene = tree.getCurrentScene()!;
      scene.getViewport()!
        ..setDisableInput(false)
        ..call('notify_mouse_entered');
      Control control(String path) => scene.getNodeT<Control>(path)!;
      Button button(String path) => scene.getNodeT<Button>(path)!;
      bool visible(String path) => control(path).isVisibleInTree();
      Future<void> click(String path) =>
          workspaceClick(scene, control(path).getGlobalRect().getCenter());
      String action(String name) => '${Workspace3D.header}/Rows/Actions/$name';
      const dialog = 'DesignLayer/DesignControls/Shade/Dialog';
      void enter(String text) {
        final input = scene.getNodeT<LineEdit>('$dialog/Name')!;
        input
          ..setText(text)
          ..textChanged.emit(text);
      }

      var emptyFrames = 0, flashes = 0;
      RenderingServer.singleton.framePreDraw.connect(window, () {
        final current = tree.getCurrentScene();
        if (current == null || _design.state.active != null) return;
        emptyFrames++;
        if (current.getNodeT<Node3D>('GridRoot')!.isVisibleInTree() ||
            current.getNodeT<Node3D>('ResourceRoot')!.isVisibleInTree() ||
            current
                .getNodeT<Control>(Workspace3D.speedDial)!
                .isVisibleInTree()) {
          flashes++;
        }
      });
      void empty({bool initial = false}) {
        _check(
            _design.state.active == null &&
                !scene.getNodeT<Node3D>('GridRoot')!.isVisibleInTree() &&
                !scene.getNodeT<Node3D>('ResourceRoot')!.isVisibleInTree() &&
                visible(Workspace3D.emptyState) &&
                !visible(Workspace3D.speedDial) &&
                !visible(Workspace3D.resourceOverlay) &&
                !visible(Workspace3D.inspector),
            'Absent Design hides the board, cubes, dial and design overlays.');
        if (initial) {
          _check(
              scene.getNodeT<Node3D>('GridRoot')!.getChildCount() == 0 &&
                  scene.getNodeT<Node3D>('ResourceRoot')!.getChildCount() == 0,
              'Fresh startup allocates no editable grid or resource nodes.');
        }
        _check(
            button(action('SaveDesign')).isDisabled() &&
                button(action('CopyDesignId')).isDisabled(),
            'No target means no Save or Copy ID.');
      }

      Future<void> snap(String name) async {
        await RenderingServer.singleton.framePostDraw.asFuture(scene);
        await RenderingServer.singleton.framePostDraw.asFuture(scene);
        final output = Platform.environment['BLACKSMITH_WORKSPACE_OUTPUT']!;
        _check(
            scene
                    .getViewport()!
                    .getTexture()!
                    .getImage()!
                    .savePng('$output/$name.png') ==
                GDError.ok,
            'Capture the actual native viewport.');
      }

      for (final size in [(1600, 900), (1152, 648), (960, 640)]) {
        window.setSize(Vector2i.fromXY(size.$1, size.$2));
        await _until(() =>
            scene.getViewport()!.getVisibleRect().size.x == size.$1 &&
            scene.getViewport()!.getVisibleRect().size.y == size.$2);
        await _pause();
        empty(initial: true);
        checkEditorFraming(scene);
        final rect =
            control('${Workspace3D.emptyState}/Message').getGlobalRect();
        _check(
            (rect.getCenter() -
                        scene.getViewport()!.getVisibleRect().getCenter())
                    .length <
                1,
            'The welcome message stays centered at actual desktop window sizes.');
        _check(
            !button(action('NewDesign')).isDisabled() &&
                !button(action('OpenDesign')).isDisabled(),
            'Existing New/Open remain accessible.');
        final p = const GridLayout3D().worldPosition(const GridPos(2, 2));
        final point = Workspace3D.project(
            scene, (scene as Node3D).toGlobal(Vector3(x: p.x, y: .12, z: p.z)));
        final selections = _grid.selections;
        await workspaceClick(scene, point);
        _check(
            _grid.state.selected == null &&
                _grid.selections == selections &&
                _grid.placements == 0,
            'Empty background clicks cannot select or place a tile.');
        // Even a stale/programmatic button signal cannot open design tools.
        button(Workspace3D.libraryToggle).pressed.emit();
        button(Workspace3D.inspectorToggle).pressed.emit();
        await _pause();
        empty(initial: true);
        await snap('empty_${size.$1}');
      }
      await click(action('NewDesign'));
      await click('$dialog/Cancel');
      empty(initial: true);
      _check(_designs.creates == 0, 'Cancel creates no implicit Design.');
      await click(action('NewDesign'));
      enter('Creation failure fixture');
      await _pause();
      await click('$dialog/Create');
      _check(_design.state.pending,
          'New Design uses the existing asynchronous creation flow.');
      await snap('creating');
      empty(initial: true);
      _designs.createResult
          .completeError(const DesignFailure('Fixture creation failed.'));
      await _until(() => _design.state.status == DesignStatus.failure);
      empty(initial: true);
      await click('$dialog/Cancel');

      await click(action('OpenDesign'));
      await click(DesignBrowser3D.cancel);
      _check(_designs.reads == 0, 'Cancel Open does not start a read.');
      empty(initial: true);
      await click(action('OpenDesign'));
      await selectDesignInBrowser(scene, _design, _id);
      await _pause();
      await click(DesignBrowser3D.confirm);
      await _pause();
      empty(initial: true);
      _designs.readResult
          .completeError(const DesignFailure('Fixture Design not found.'));
      await _until(() => _design.state.status == DesignStatus.failure);
      _check(
          scene
              .getNodeT<Label>('${DesignBrowser3D.content}/Feedback')!
              .getText()
              .contains('not found'),
          'Open failure retains the existing visible feedback.');
      empty(initial: true);
      await click(DesignBrowser3D.cancel);

      _designs.readResult = async.Completer<Design>();
      await click(action('OpenDesign'));
      await selectDesignInBrowser(scene, _design, _id);
      await _pause();
      await click(DesignBrowser3D.confirm);
      _designs.readResult
          .complete(const Design(id: _id, name: 'Restored Design'));
      await _until(() => _resources.reads == 1);
      empty(initial: true);
      await snap('loading');
      _resources.result.complete(const [
        PersistedResource(
            id: '11111111-1111-4111-8111-111111111111',
            designId: _id,
            position: GridPos(1, 1)),
        PersistedResource(
            id: '22222222-2222-4222-8222-222222222222',
            designId: _id,
            position: GridPos(4, 3))
      ]);
      await _until(
          () => _design.state.active != null && !_design.state.pending);
      await _pause();
      _check(
          scene.getNodeT<Node3D>('GridRoot')!.getChildCount() == 36 &&
              scene.getNodeT<Node3D>('GridRoot')!.isVisibleInTree() &&
              scene.getNodeT<Node3D>('ResourceRoot')!.getChildCount() == 2 &&
              !visible(Workspace3D.emptyState) &&
              visible(Workspace3D.speedDial),
          'Successful Open reveals the fully restored board, never a fallback blank Design.');
      window.setSize(Vector2i.fromXY(1600, 900));
      await _until(() => scene.getViewport()!.getVisibleRect().size.x == 1600);
      await _pause();
      checkEditorFraming(scene);
      await snap('opened_1600');
      final world = const GridLayout3D().worldPosition(const GridPos(2, 2));
      await workspaceClick(
          scene,
          Workspace3D.project(
              scene,
              (scene as Node3D)
                  .toGlobal(Vector3(x: world.x, y: .12, z: world.z))));
      await openWorkspaceAction(scene, Workspace3D.libraryToggle);
      final placements = _grid.placements;
      await click('${Workspace3D.catalog}/ComputeEngine');
      _check(_grid.placements == placements,
          'Choosing a row still does not place a resource.');
      await snap('resources_1600');
      await click(action('NewDesign'));
      _check(!_design.state.modalOpen && visible(Workspace3D.resourceOverlay),
          'Resources still blocks toolbar actions.');
      await confirmResourceChoice(scene);
      _check(
          _grid.placements == placements + 1 &&
              _grid.state.tiles[const GridPos(2, 2)] ==
                  ResourceKind.computeEngine,
          'Explicit confirmation places once on the captured tile.');
      await openWorkspaceAction(scene, Workspace3D.inspectorToggle);
      _check(
          scene.getNodeT<Label>('${Workspace3D.details}/Kind')!.getText() ==
              'Compute Engine',
          'Inspector retains its established behavior for an active Design.');
      await dismissWorkspaceMenus(scene);
      final beforeReplace = _grid.state;
      await click(action('OpenDesign'));
      await selectDesignInBrowser(scene, _design, _id);
      await _pause();
      _check(
          _design.state.requiresDiscard &&
              button(DesignBrowser3D.confirm).isDisabled(),
          'Unsaved-change consent still protects active placements.');
      await click(DesignBrowser3D.cancel);
      _check(_grid.state == beforeReplace && _design.state.active?.id == _id,
          'Canceled replacement preserves the Design and unsaved grid.');
      final clipboard = DisplayServer.singleton.clipboardGet();
      try {
        await click(action('CopyDesignId'));
        _check(DisplayServer.singleton.clipboardGet() == _id,
            'Existing Copy ID callback remains intact.');
      } finally {
        DisplayServer.singleton.clipboardSet(clipboard);
      }
      await openWorkspaceAction(scene, Workspace3D.libraryToggle);
      _design.clearForTest();
      await _until(() => _grid.state.selected == null);
      await _pause();
      empty();
      _check(
          const MapEquality()
              .equals(_grid.state.resources, beforeReplace.resources),
          'View deactivation clears selection without discarding resources or bypassing discard policy.');
      _designs.createResult = async.Completer<Design>();
      await click(action('NewDesign'));
      enter('Unsaved Design');
      await _pause();
      final discard = scene.getNodeT<CheckButton>('$dialog/Discard')!;
      if (discard.isVisibleInTree()) await click('$dialog/Discard');
      await click('$dialog/Create');
      await _pause();
      empty();
      _designs.createResult
          .complete(const Design(id: '', name: 'Unsaved Design'));
      await _until(
          () => _design.state.active != null && !_design.state.pending);
      await _pause();
      _check(
          scene.getNodeT<Node3D>('GridRoot')!.isVisibleInTree() &&
              _grid.state.resources.isEmpty &&
              _grid.state.selected == null &&
              !visible(Workspace3D.emptyState) &&
              button(action('CopyDesignId')).isDisabled(),
          'An active Design without a persisted ID shows an empty editable grid.');
      await snap('new_unsaved_1600');
      await workspaceClick(
          scene,
          Workspace3D.project(
              scene, scene.toGlobal(Vector3(x: world.x, y: .12, z: world.z))));
      _check(_grid.state.selected == const GridPos(2, 2),
          'ID-less active Design remains selectable.');
      _design.clearForTest();
      await _until(() => _grid.state.selected == null);
      await _pause();
      empty();
      tree.reloadCurrentScene();
      final old = scene;
      await _until(() =>
          tree.getCurrentScene() != null && tree.getCurrentScene() != old);
      scene = tree.getCurrentScene()!;
      await _pause();
      empty(initial: true);
      _check(emptyFrames > 2 && flashes == 0 && _http.requests == 0,
          'No inactive frame reveals grid/resource/dial visuals; no HTTP or cloud request is sent.');
      GD.print(Variant('BLACKSMITH_ISSUE79_EMPTY_PASSED sizes=3 startup=true '
          'lazy_tiles=true create=true idless_active=true open_restored=true '
          'cancel=true failure=true pending_hidden=true cleared=true reload=true '
          'placement=true inspect=true discard=true no_flash=true http_requests=0'));
      tree.getRoot()!.treeExiting.emit();
      await _until(() => _design.isClosed && _grid.isClosed);
      tree.quit();
    } catch (error, stack) {
      GD.print(Variant('BLACKSMITH_ISSUE79_EMPTY_FAILED $error\n$stack'));
      tree.quit(exitCode: 1);
    }
  });
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _pause() =>
    Future<void>.delayed(const Duration(milliseconds: 250));
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await _pause();
  }
  throw StateError('Timed out waiting for empty workspace transition.');
}
