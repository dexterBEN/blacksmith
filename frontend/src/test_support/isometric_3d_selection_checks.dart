// Keep the same file-URI library identities as the native script resolver.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async' as async;
import 'dart:io';
import 'package:bloc/bloc.dart' as bloc_core;
import 'package:godot_dart/godot_dart.dart';
import 'package:http/http.dart' as http;
import '../lib/core/di/service_locator.dart' as di;
import '../lib/data/repositories/cloud_storage_repository.dart';
import '../lib/data/services/cloud_services_api.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_event.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';

class _NoNetworkClient extends http.BaseClient {
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    throw StateError('HTTP is forbidden in the standalone 3D fixture.');
  }
}

class _NoProvisioningRepository extends CloudStorageRepository {
  _NoProvisioningRepository(CloudServicesApi api)
      : super(api, projectId: 'fake-project');
  int calls = 0;

  @override
  Future<String> createBucket({required int row, required int col}) async {
    calls++;
    throw StateError('Provisioning is forbidden in the 3D selection fixture.');
  }
}

class _ObservedBloc extends IsomapGridBloc {
  _ObservedBloc(CloudStorageRepository repository)
      : super(cloudStorageRepository: repository);
  int listeners = 0;
  int tileEvents = 0;
  int otherEvents = 0;

  @override
  Stream<IsomapGridState> get stream => async.Stream.multi((controller) {
        listeners++;
        final subscription = super.stream.listen(controller.addSync,
            onError: controller.addErrorSync, onDone: controller.closeSync);
        controller.onCancel = () {
          listeners--;
          return subscription.cancel();
        };
      }, isBroadcast: true);

  @override
  void onEvent(IsomapGridEvent event) {
    if (event is TileClicked) {
      tileEvents++;
    } else {
      otherEvents++;
    }
    super.onEvent(event);
  }
}

class _LocalBlocObserver extends bloc_core.BlocObserver {
  IsomapGridBloc? created;

  @override
  void onCreate(bloc_core.BlocBase<dynamic> bloc) {
    if (bloc is IsomapGridBloc) created = bloc;
    super.onCreate(bloc);
  }
}

/// Reuses the real BLoC behind a fail-closed, in-memory repository. No
/// application bootstrap, backend, database or credential is used.
class SelectionFixture {
  SelectionFixture() {
    _api = CloudServicesApi(baseUrl: 'http://fake.invalid', client: _client);
    _repository = _NoProvisioningRepository(_api);
    _bloc = _ObservedBloc(_repository);
    _register();
  }

  final _client = _NoNetworkClient();
  late final CloudServicesApi _api;
  late final _NoProvisioningRepository _repository;
  late final _ObservedBloc _bloc;
  final _originalMaterialColors = <String, List<double>>{};
  bool _disposed = false;

  void _register() => di.sl.registerSingleton<IsomapGridBloc>(_bloc);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await di.sl.reset(dispose: false);
    await _bloc.close();
    _api.close();
  }

  Future<Node> check(SceneTree tree, {required bool capture}) async {
    var scene = tree.getCurrentScene()!;
    final viewport = scene.getViewport()!;
    viewport
      ..setDisableInput(false)
      ..call('notify_mouse_entered');
    _check(_bloc.listeners == 1, 'One initial scene subscription.');
    _check(_bloc.state.selected == null, 'No initial selection.');

    // Deliberately change names: picking must use logical coordinates.
    final grid = scene.getNodeT<Node3D>('GridRoot')!;
    final mesh = (grid.getChild(0)! as MeshInstance3D).getMesh()!;
    for (var surface = 0; surface < mesh.getSurfaceCount(); surface++) {
      final property = 'surface_$surface/material';
      final path = mesh
          .getIndexed(NodePath.fromString('$property:resource_path'))
          .cast<String>();
      final color = mesh
          .getIndexed(NodePath.fromString('$property:albedo_color'))
          .cast<Color>();
      _originalMaterialColors[path] = [color.r, color.g, color.b, color.a];
    }
    for (var i = 0; i < grid.getChildCount(); i++) {
      grid.getChild(i)!.setName('Renamed_$i');
    }
    for (var row = 0; row < 6; row++) {
      for (var col = 0; col < 6; col++) {
        final position = GridPos(row, col);
        final before = _bloc.tileEvents;
        await _click(scene, _project(scene, position));
        await _until(() => _bloc.state.selected == position);
        _check(_bloc.tileEvents == before + 1, 'One TileClicked per click.');
        _checkHighlight(scene, position);
      }
    }

    final beforeInvalid = _bloc.tileEvents;
    const layout = GridLayout3D();
    final center = layout.worldPosition(const GridPos(2, 2));
    for (final point in [
      (x: -layout.width / 2 - 0.05, z: 0.0),
      (x: layout.width / 2 + 0.05, z: 0.0),
      (x: 0.0, z: -layout.depth / 2 - 0.05),
      (x: 0.0, z: layout.depth / 2 + 0.05),
      (x: center.x + GridLayout3D.pitch / 2, z: center.z),
      (x: center.x, z: center.z + GridLayout3D.pitch / 2),
      (
        x: center.x + GridLayout3D.pitch / 2,
        z: center.z + GridLayout3D.pitch / 2
      ),
    ]) {
      await _click(scene, _projectPoint(scene, point.x, point.z));
    }
    await _click(scene, _project(scene, const GridPos(0, 0)),
        button: MouseButton.right);
    viewport.pushInput(
        InputEventMouseButton()
          ..setPosition(_project(scene, const GridPos(0, 0)))
          ..setButtonIndex(MouseButton.left)
          ..setPressed(false),
        inLocalCoords: true);
    await _pause();
    _check(_bloc.tileEvents == beforeInvalid,
        'Outside, gaps, right clicks and release events must be ignored.');
    _checkHighlight(scene, const GridPos(5, 5));

    // GUI input must be consumed before the grid's _unhandled_input route.
    final blocker = Control()
      ..setSize(viewport.getVisibleRect().size)
      ..setMouseFilter(ControlMouseFilter.stop);
    scene.addChild(blocker);
    await _pause();
    await _click(scene, _project(scene, const GridPos(0, 0)));
    _check(
        _bloc.tileEvents == beforeInvalid, 'GUI must intercept grid clicks.');
    blocker.queueFree();
    await _pause();

    if (capture) {
      _bloc.add(const TileClicked(GridPos(5, 2)));
      await _until(() => _bloc.state.selected == const GridPos(5, 2));
      await _pause();
      _checkHighlight(scene, const GridPos(5, 2));
      await _capture(scene, 'selection_edge.png');
    }

    // A state change with no mouse event must also update the highlight.
    _bloc.add(const TileClicked(GridPos(5, 0)));
    await _until(() => _bloc.state.selected == const GridPos(5, 0));
    await _pause();
    _checkHighlight(scene, const GridPos(5, 0));
    if (capture) await _capture(scene, 'selection_corner.png');

    // Resize the viewport, then pick using the actual adjusted camera.
    final window = tree.getRoot()!;
    final camera = scene.getNodeT<Camera3D>('Camera3D')!;
    final initialSize = camera.getSize();
    window.setContentScaleSize(Vector2i.fromXY(480, 640));
    await _until(() => camera.getSize() > initialSize);
    await _click(scene, _project(scene, const GridPos(0, 5)));
    await _until(() => _bloc.state.selected == const GridPos(0, 5));
    _checkHighlight(scene, const GridPos(0, 5));
    window.setContentScaleSize(Vector2i.fromXY(1152, 648));
    await _until(() => (camera.getSize() - initialSize).abs() < 1e-4);

    for (var i = 0; i < 2; i++) {
      final previous = scene.getInstanceId();
      _check(tree.reloadCurrentScene() == GDError.ok, 'Reload must succeed.');
      await _until(() =>
          tree.getCurrentScene() != null &&
          tree.getCurrentScene()!.getInstanceId() != previous &&
          _bloc.listeners == 1);
      await _pause();
      scene = tree.getCurrentScene()!;
      _check(!_bloc.isClosed, 'A scene must not close the shared BLoC.');
      _checkHighlight(scene, const GridPos(0, 5));
    }

    // No scene listener may survive unload or receive a later state update.
    tree.unloadCurrentScene();
    await _until(() => _bloc.listeners == 0);
    _check(!_bloc.isClosed, 'Shared BLoC survives scene exit.');
    _bloc.add(const TileClicked(GridPos(2, 3)));
    await _until(() => _bloc.state.selected == const GridPos(2, 3));

    // Exercise AppRoot's established local diagnostic ownership pattern.
    await di.sl.reset(dispose: false);
    di.sl.registerFactory<IsomapGridBloc>(() => throw StateError(
        'Deliberately unavailable DI for the fallback check.'));
    final previousObserver = bloc_core.Bloc.observer;
    final observer = _LocalBlocObserver();
    bloc_core.Bloc.observer = observer;
    try {
      tree.changeSceneToFile('res://scenes/isometric_3d.tscn');
      await _until(
          () => observer.created != null && tree.getCurrentScene() != null);
      scene = tree.getCurrentScene()!;
      await _click(scene, _project(scene, const GridPos(1, 4)));
      final local = observer.created!;
      await _until(() => local.state.selected == const GridPos(1, 4));
      _checkHighlight(scene, const GridPos(1, 4));
      tree.unloadCurrentScene();
      await _until(() => local.isClosed);
    } finally {
      bloc_core.Bloc.observer = previousObserver;
    }
    await di.sl.reset(dispose: false);
    _register();
    tree.changeSceneToFile('res://scenes/isometric_3d.tscn');
    await _until(() => tree.getCurrentScene() != null && _bloc.listeners == 1);
    await _pause();
    scene = tree.getCurrentScene()!;
    _checkHighlight(scene, const GridPos(2, 3));
    final beforeFinal = _bloc.tileEvents;
    await _click(scene, _project(scene, const GridPos(2, 3)));
    _check(_bloc.tileEvents == beforeFinal + 1 && _bloc.listeners == 1,
        'Reopened scene must handle each click exactly once.');
    _check(
        _repository.calls == 0 &&
            _client.requests == 0 &&
            _bloc.otherEvents == 0 &&
            _bloc.state.tiles.isEmpty &&
            _bloc.state.pendingOperations == 0,
        'Selection must never place resources, provision or call HTTP.');
    GD.print(Variant('BLACKSMITH_ISSUE17_SELECTION_PASSED centers=36 gaps=true '
        'gui=true resize=true reload=true listeners=1 fallback_disposed=true '
        'repository_calls=0 http_requests=0'));
    return scene;
  }

  void _checkHighlight(Node scene, GridPos selected) {
    final highlight = ResourceLoader.singleton
        .load('res://scenes/isometric_3d/selection_material.tres')! as Material;
    final grid = scene.getNodeT<Node3D>('GridRoot')!;
    int? meshId;
    var count = 0;
    for (var index = 0; index < 36; index++) {
      final tile = grid.getChild(index)! as MeshInstance3D;
      final mesh = tile.getMesh()!;
      meshId ??= mesh.getInstanceId();
      _check(mesh.getInstanceId() == meshId, 'All tiles share one mesh.');
      final isSelected = index == selected.row * 6 + selected.col;
      _check(
          isSelected
              ? tile.getMaterialOverride()?.getInstanceId() ==
                  highlight.getInstanceId()
              : tile.getMaterialOverride() == null,
          'Selection override must match BLoC state for tile $index.');
      for (var surface = 0; surface < mesh.getSurfaceCount(); surface++) {
        final property = 'surface_$surface/material';
        final path = mesh
            .getIndexed(NodePath.fromString('$property:resource_path'))
            .cast<String>();
        final color = mesh
            .getIndexed(NodePath.fromString('$property:albedo_color'))
            .cast<Color>();
        final expected = _originalMaterialColors[path]!;
        final actual = [color.r, color.g, color.b, color.a];
        _check(
            List.generate(4, (i) => (expected[i] - actual[i]).abs() < 1e-6)
                .every((equal) => equal),
            'Shared base materials must remain unchanged.');
        _check(tile.getSurfaceOverrideMaterial(surface) == null,
            'Deselection must restore each correct shared surface material.');
      }
      if (isSelected) count++;
    }
    _check(count == 1, 'Exactly one tile must be highlighted.');
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _pause() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 80; i++) {
    if (condition()) return;
    await _pause();
  }
  throw StateError('Timed out waiting for 3D selection/lifecycle.');
}

Vector2 _project(Node scene, GridPos position) {
  final center = const GridLayout3D().worldPosition(position);
  return _projectPoint(scene, center.x, center.z);
}

Vector2 _projectPoint(Node scene, double x, double z) =>
    scene.getNodeT<Camera3D>('Camera3D')!.unprojectPosition((scene as Node3D)
        .toGlobal(Vector3(x: x, y: GridLayout3D.tileHeight / 2, z: z)));

Future<void> _click(Node scene, Vector2 point,
    {MouseButton button = MouseButton.left}) async {
  final viewport = scene.getViewport()!;
  viewport.pushInput(InputEventMouseMotion()..setPosition(point),
      inLocalCoords: true);
  for (final pressed in [true, false]) {
    viewport.pushInput(
        InputEventMouseButton()
          ..setPosition(point)
          ..setGlobalPosition(point)
          ..setButtonIndex(button)
          ..setPressed(pressed),
        inLocalCoords: true);
    await _pause();
  }
}

Future<void> _capture(Node scene, String filename) async {
  await RenderingServer.singleton.framePostDraw.asFuture(scene);
  final output = Platform.environment['BLACKSMITH_ISSUE17_OUTPUT']!;
  _check(
      scene
              .getViewport()!
              .getTexture()!
              .getImage()!
              .savePng('$output/$filename') ==
          GDError.ok,
      'Capture must come from the actual renderer.');
}
