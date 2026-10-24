// Use the production main/resolver's file-URI library identities.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async' as async;
import 'package:bloc/bloc.dart' as bloc_core;
import 'package:godot_dart/godot_dart.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import 'package:http/http.dart' as http;
import '../lib/core/di/service_locator.dart' as di;
import '../lib/data/repositories/cloud_storage_repository.dart';
import '../lib/data/services/cloud_services_api.dart';
import '../lib/data/repositories/design_repository.dart';
import '../lib/domain/bloc/design/design_cubit.dart';
import '../lib/domain/models/design.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_event.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/resource_kind.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/resource_visuals_3d.dart';
import 'isometric_3d_framing_checks.dart';
import 'workspace_checks.dart';

class _FixtureDesignRepository extends DesignRepository {
  _FixtureDesignRepository() : super(baseUrl: 'http://forbidden.invalid');
  int calls = 0;
  @override
  Future<Design> create(String name) async {
    calls++;
    return Design(id: '12345678-1234-1234-1234-123456789abc', name: name);
  }
}

class _NoNetworkClient extends http.BaseClient {
  int requests = 0;
  int closes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    throw StateError('HTTP is forbidden in the application startup check.');
  }

  @override
  void close() => closes++;
}

class _NoProvisioningRepository extends CloudStorageRepository {
  _NoProvisioningRepository(CloudServicesApi api)
      : super(api, projectId: 'fake-project');
  int calls = 0;
  @override
  Future<String> createBucket({required int row, required int col}) async {
    calls++;
    throw StateError('Provisioning is forbidden in the startup check.');
  }
}

class _RuntimeObserver extends bloc_core.BlocObserver {
  final created = <IsomapGridBloc>[];
  int closed = 0;
  int tileEvents = 0;
  @override
  void onCreate(bloc_core.BlocBase<dynamic> bloc) {
    if (bloc is IsomapGridBloc) created.add(bloc);
    super.onCreate(bloc);
  }

  @override
  void onClose(bloc_core.BlocBase<dynamic> bloc) {
    if (bloc is IsomapGridBloc) closed++;
    super.onClose(bloc);
  }

  @override
  void onEvent(bloc_core.Bloc<dynamic, dynamic> bloc, Object? event) {
    if (event is TileClicked) tileEvents++;
    super.onEvent(bloc, event);
  }
}

final _client = _NoNetworkClient();
final _observer = _RuntimeObserver();
late final _NoProvisioningRepository _repository;
final _designRepository = _FixtureDesignRepository();

/// The runner wraps the unchanged production main function only for this
/// instrumented phase. It injects cloud tripwires, never a replacement BLoC.
void beforeStartup() {
  if (Engine.singleton.isEditorHint()) return;
  final api = CloudServicesApi(baseUrl: 'http://fake.invalid', client: _client);
  _repository = _NoProvisioningRepository(api);
  di.sl.registerSingleton<CloudServicesApi>(api, dispose: (api) => api.close());
  di.sl.registerSingleton<CloudStorageRepository>(_repository);
  di.sl.registerSingleton<DesignRepository>(_designRepository,
      dispose: (repository) => repository.close());
  bloc_core.Bloc.observer = _observer;
}

void afterStartup() {
  if (Engine.singleton.isEditorHint()) return;
  async.Timer.run(() async {
    final tree = Engine.singleton.getMainLoop()! as SceneTree;
    try {
      await _until(() => tree.getCurrentScene() != null);
      var scene = tree.getCurrentScene()!;
      _check(
          scene is Node3D &&
              scene.getSceneFilePath() == 'res://scenes/isometric_3d.tscn',
          'The unchanged project setting must start the existing 3D editor.');
      final bloc = di.sl<IsomapGridBloc>();
      _check(
          _observer.created.length == 1 &&
              identical(bloc, _observer.created.single),
          'One production DI BLoC.');
      di.setupServiceLocator();
      _check(
          identical(bloc, di.sl<IsomapGridBloc>()), 'Bootstrap is idempotent.');
      await _pause();
      checkEditorFraming(scene);
      final viewport = scene.getViewport()!;
      viewport
        ..setDisableInput(false)
        ..call('notify_mouse_entered');
      _check(bloc.state.selected == null && bloc.state.tiles.isEmpty,
          'A new application starts without selection or saved resources.');
      for (final kind in ResourceKind.values) {
        final button = _button(scene, kind);
        _check(button.isDisabled(), 'Placement requires a selected tile.');
        await _click(scene, button.getGlobalRect().getCenter());
      }
      _check(bloc.state.selected == null && bloc.state.tiles.isEmpty,
          'Disabled buttons cannot place or select.');
      await checkWorkspace(scene, bloc, di.sl<DesignCubit>(),
          tileEvents: () => _observer.tileEvents);
      _check(_designRepository.calls == 1,
          'Only explicit fixture Design creation may call its repository.');

      Future<void> select(GridPos position) async {
        final point = const GridLayout3D().worldPosition(position);
        final screen = Workspace3D.project(
            scene,
            (scene as Node3D)
                .toGlobal(Vector3(x: point.x, y: .12, z: point.z)));
        final before = _observer.tileEvents;
        await _click(scene, screen);
        _check(
            bloc.state.selected == position &&
                _observer.tileEvents == before + 1,
            'One selection event per click.');
      }

      Future<void> choose(ResourceKind kind) async {
        final selected = bloc.state.selected;
        final events = _observer.tileEvents;
        await _click(scene, _button(scene, kind).getGlobalRect().getCenter());
        _check(
            bloc.state.selected == selected &&
                _observer.tileEvents == events &&
                bloc.state.tiles[selected] == kind,
            'Palette placement must stay local on the selected tile.');
        _checkResources(scene, bloc);
      }

      const center = GridPos(2, 3);
      await select(center);
      await choose(ResourceKind.cloudStorage);
      final previous = _cube(scene, center).getInstanceId();
      await choose(ResourceKind.computeEngine);
      _check(
          !GD.isInstanceIdValid(previous) && _root(scene).getChildCount() == 1,
          'Replacing Storage with Compute frees the obsolete cube.');
      final compute = _cube(scene, center).getInstanceId();
      await choose(ResourceKind.computeEngine);
      _check(_cube(scene, center).getInstanceId() == compute,
          'Repeated placement must reuse one cube.');
      for (final entry in {
        const GridPos(4, 1): ResourceKind.cloudStorage,
        const GridPos(1, 1): ResourceKind.cloudVpn,
        const GridPos(1, 4): ResourceKind.cloudLoadBalancing,
        const GridPos(0, 0): ResourceKind.computeEngine,
        const GridPos(0, 5): ResourceKind.cloudVpn,
        const GridPos(5, 0): ResourceKind.cloudLoadBalancing,
        const GridPos(5, 5): ResourceKind.cloudStorage,
      }.entries) {
        await select(entry.key);
        await choose(entry.value);
      }
      for (final size in const [
        (1152, 648),
        (Workspace3D.minimumWidth, Workspace3D.minimumHeight)
      ]) {
        tree.getRoot()!.setSize(Vector2i.fromXY(size.$1, size.$2));
        await _until(
            () => scene.getViewport()!.getVisibleRect().size.x == size.$1);
        await _pause();
        checkEditorFraming(scene);
        await select(const GridPos(5, 5));
      }
      // Godot must clamp an undersized physical window, not enter a second
      // presentation mode. Exercise this in the native X11 application too.
      final window = tree.getRoot()!;
      window.setSize(Vector2i.fromXY(640, 480));
      await _until(() =>
          window.getSize().x >= Workspace3D.minimumWidth &&
          window.getSize().y >= Workspace3D.minimumHeight);
      await _pause();
      final minimum = window.getMinSize();
      final actual = window.getSize();
      _check(
          minimum.x == Workspace3D.minimumWidth &&
              minimum.y == Workspace3D.minimumHeight &&
              actual.x >= minimum.x &&
              actual.y >= minimum.y,
          'The native window enforces the desktop minimum: '
          'minimum=${minimum.x}x${minimum.y}, actual=${actual.x}x${actual.y}.');
      GD.print(Variant('BLACKSMITH_DESKTOP_MINIMUM_PASSED '
          'minimum=${minimum.x}x${minimum.y} actual=${actual.x}x${actual.y}'));
      checkEditorFraming(scene);
      await select(const GridPos(0, 0));
      final oldScene = scene.getInstanceId();
      final oldCube = _cube(scene, center).getInstanceId();
      _check(
          tree.reloadCurrentScene() == GDError.ok, 'Reload the default scene.');
      await _until(() =>
          tree.getCurrentScene() != null &&
          tree.getCurrentScene()!.getInstanceId() != oldScene);
      await _pause();
      scene = tree.getCurrentScene()!;
      _check(
          _observer.created.length == 1 &&
              !bloc.isClosed &&
              !GD.isInstanceIdValid(oldScene) &&
              !GD.isInstanceIdValid(oldCube),
          'Scene reload frees old nodes and retains the single shared BLoC.');
      _checkResources(scene, bloc);
      await select(center);
      await choose(ResourceKind.cloudStorage);
      tree.unloadCurrentScene();
      await _pause();
      _check(!bloc.isClosed, 'Scene exit must not close the runtime BLoC.');
      bloc.add(const TileClicked(GridPos(0, 0)));
      await _pause();
      // Trigger the actual installed root hook while the VM can still observe
      // asynchronous disposal, then quit normally. This adds no production API.
      tree.getRoot()!.emitSignal('tree_exiting');
      await _until(() => bloc.isClosed && _client.closes == 1);
      _check(
          _observer.closed == 1 &&
              !di.sl.isRegistered<IsomapGridBloc>() &&
              _repository.calls == 0 &&
              _client.requests == 0,
          'Runtime shutdown closes shared services once, with zero cloud I/O.');
      GD.print(Variant('BLACKSMITH_DEFAULT_APPLICATION_PASSED bloc_instances=1 '
          'kinds=4 reload=true shutdown=true repository_calls=0 http_requests=0'));
      tree.quit();
    } catch (error, stack) {
      GD.print(
          Variant('BLACKSMITH_DEFAULT_APPLICATION_FAILED: $error\n$stack'));
      tree.quit(exitCode: 1);
    }
  });
}

Node3D _root(Node scene) => scene.getNodeT<Node3D>('ResourceRoot')!;
Node3D _cube(Node scene, GridPos pos) =>
    _root(scene).getNodeT<Node3D>('Resource_${pos.row}_${pos.col}')!;
Button _button(Node scene, ResourceKind kind) => scene.getNodeT<Button>(
    '${Workspace3D.choices}/${resourceVisuals3D[kind]!.buttonName}')!;
void _checkResources(Node scene, IsomapGridBloc bloc) {
  _check(_root(scene).getChildCount() == bloc.state.tiles.length,
      'Exactly one existing scene per logical resource.');
  for (final entry in bloc.state.tiles.entries) {
    final cube = _cube(scene, entry.key);
    final scale = cube.getScale();
    _check(
        cube.getSceneFilePath() == resourceVisuals3D[entry.value]!.scenePath &&
            [scale.x, scale.y, scale.z].every((v) => (v - .68).abs() < 1e-5) &&
            (cube.getPosition().y - .12).abs() < 1e-5,
        'Correct GCP identity, uniform cube size and tile-top alignment.');
  }
  checkEditorFraming(scene);
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _pause() =>
    Future<void>.delayed(const Duration(milliseconds: 150));
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 80; i++) {
    if (condition()) return;
    await _pause();
  }
  throw StateError('Timed out waiting for normal application state/lifecycle.');
}

Future<void> _click(Node scene, Vector2 position) async {
  final viewport = scene.getViewport()!;
  viewport.pushInput(InputEventMouseMotion()..setPosition(position),
      inLocalCoords: true);
  for (final pressed in [true, false]) {
    viewport.pushInput(
        InputEventMouseButton()
          ..setPosition(position)
          ..setGlobalPosition(position)
          ..setButtonIndex(MouseButton.left)
          ..setPressed(pressed),
        inLocalCoords: true);
    await _pause();
  }
}
