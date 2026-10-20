// Godot loads scripts through file URIs; keep one library identity in this
// temporary entrypoint and the generated resolver.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async' as async;
import 'dart:io';
import 'package:godot_dart/godot_dart.dart';
import 'package:http/http.dart' as http;
import '../godot_dart_scripts.g.dart';
import '../lib/core/di/service_locator.dart' as di;
import '../lib/data/repositories/cloud_storage_repository.dart';
import '../lib/data/services/cloud_services_api.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_event.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/resource_kind.dart';
import '../lib/resource_visuals.dart';

class _NoNetworkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw StateError('Network access is forbidden in the Godot smoke test.');
}

class _FakeRepository extends CloudStorageRepository {
  _FakeRepository(this.api) : super(api, projectId: 'fake-project');
  final CloudServicesApi api;
  final calls = <async.Completer<String>>[];

  @override
  Future<String> createBucket({required int row, required int col}) {
    final completion = async.Completer<String>();
    calls.add(completion);
    return completion.future;
  }
}

class _ObservedBloc extends IsomapGridBloc {
  _ObservedBloc(_FakeRepository repository)
      : super(cloudStorageRepository: repository);
  int listeners = 0;
  int tileEvents = 0;

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
    if (event is TileClicked) tileEvents++;
    super.onEvent(event);
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _frame() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 40; i++) {
    if (condition()) return;
    await _frame();
  }
  throw StateError('Timed out waiting for scene/state synchronization.');
}

Future<void> _click(Viewport viewport, Vector2 position) async {
  viewport.pushInput(InputEventMouseMotion()..setPosition(position),
      inLocalCoords: true);
  await _frame();
  for (final pressed in [true, false]) {
    viewport.pushInput(
      InputEventMouseButton()
        ..setPosition(position)
        ..setGlobalPosition(position)
        ..setButtonIndex(MouseButton.left)
        ..setPressed(pressed),
      inLocalCoords: true,
    );
    await _frame();
  }
}

Vector2 _cell(Node2D grid, int row, int col) {
  final origin = grid.getGlobalPosition();
  return Vector2(
      x: origin.x + (col - row) * 32, y: origin.y + (col + row) * 16);
}

Sprite2D _icon(Node grid, int row, int col) =>
    grid.getChild(row * 6 + col)!.getChild(2)! as Sprite2D;

void main() {
  final localOnly = Platform.environment['BLACKSMITH_SMOKE_LOCAL'] == '1';
  final api = CloudServicesApi(
      baseUrl: 'http://fake.invalid', client: _NoNetworkClient());
  final repository = _FakeRepository(api);
  di.sl.registerSingleton<CloudStorageRepository>(repository,
      dispose: (_) => api.close());
  final bloc = _ObservedBloc(repository);
  if (localOnly) {
    di.sl.registerFactory<IsomapGridBloc>(() =>
        throw StateError('Deliberately unavailable DI in diagnostic test.'));
  } else {
    di.sl.registerSingleton<IsomapGridBloc>(bloc,
        dispose: (bloc) => bloc.close());
  }
  attachScriptResolver();
  GD.print(Variant('BLACKSMITH_GODOT_FAKE_READY'));
  if (Engine.singleton.isEditorHint()) return;
  async.Timer.run(() async {
    final tree = Engine.singleton.getMainLoop()! as SceneTree;
    try {
      await _until(() => tree.getCurrentScene() != null);
      // The headless display initially exposes a 64x64 window, too small for
      // this scene's palette. Use a normal desktop viewport for GUI events.
      tree.getRoot()!.setSize(Vector2i.fromXY(1152, 648));
      await _frame();
      var scene = tree.getCurrentScene()!;
      _check(scene is Node2D, 'AppRoot must attach to Node2D.');
      var grid = scene.getNodeT<Node2D>('IsoMapGrid')!;
      final viewport = grid.getViewport()!;
      _check(grid.getChildCount() == 36, 'Expected the default 6x6 grid.');
      final menu = scene.getNodeT<Control>('MenuOverlay')!;
      final panel = menu.getChild(0)! as Control;
      final buttons = panel.getChild(0)!;
      final cloud = buttons.getChild(0)! as Control;
      final compute = buttons.getChild(2)! as Control;
      final size = viewport.getVisibleRect().size;
      final rect = cloud.getGlobalRect();
      GD.print(Variant('SMOKE viewport=${size.x},${size.y} '
          'disabled=${viewport.isInputDisabled()} '
          'grid=${grid.getPosition().x},${grid.getPosition().y} '
          'cloud=${rect.position.x},${rect.position.y},${rect.size.x},${rect.size.y} '
          'unhandled=${grid.isProcessingUnhandledInput()}'));
      viewport.setDisableInput(false);
      viewport.call('notify_mouse_entered');
      Vector2 center(Control control) {
        final rect = control.getGlobalRect();
        return Vector2(
            x: rect.position.x + rect.size.x / 2,
            y: rect.position.y + rect.size.y / 2);
      }

      await _click(viewport, center(cloud));
      _check(repository.calls.isEmpty, 'No bucket without a selected tile.');
      await _click(viewport, _cell(grid, 1, 1));
      await _click(viewport, center(compute));
      _check(
          _icon(grid, 1, 1).getTexture()!.getPath() ==
              resourceVisuals[ResourceKind.computeEngine]!.path,
          'Compute texture.');
      await _click(viewport, center(cloud));
      final icon = _icon(grid, 1, 1);
      _check(
          icon.getTexture()!.getPath() ==
              resourceVisuals[ResourceKind.cloudStorage]!.path,
          'Replacing a resource must replace the displayed sprite.');
      _check(
          (icon.getScale().x * icon.getTexture()!.getSize().x - 80).abs() <
              0.01,
          'Preserve icon width scaling.');
      _check(icon.getZIndex() == 6, 'Preserve icon z ordering.');

      if (localOnly) {
        _check(
            repository.calls.isEmpty, 'Diagnostic mode must never provision.');
        tree.reloadCurrentScene();
        await _frame();
        GD.print(Variant('BLACKSMITH_GODOT_LOCAL_PASSED'));
      } else {
        _check(
            repository.calls.length == 1, 'One request for one cloud click.');
        _check(bloc.tileEvents == 1, 'Menu clicks must not select grid cells.');
        _check(bloc.listeners == 1, 'One live scene subscription.');
        repository.calls.single.completeError(
            const CloudStorageFailure('Simulated safe failure.'));
        await _until(() => bloc.state.pendingOperations == 0);
        _check(
            bloc.state.tiles[const GridPos(1, 1)] == ResourceKind.cloudStorage,
            'Failure must keep the optimistic resource.');

        final previousId = scene.getInstanceId();
        tree.reloadCurrentScene();
        await _until(() =>
            tree.getCurrentScene() != null &&
            tree.getCurrentScene()!.getInstanceId() != previousId);
        await _frame();
        scene = tree.getCurrentScene()!;
        grid = scene.getNodeT<Node2D>('IsoMapGrid')!;
        _check(!bloc.isClosed && bloc.listeners == 1,
            'Scene reload must release the old observer and retain shared state.');
        _check(
            _icon(grid, 1, 1).getTexture()!.getPath() ==
                resourceVisuals[ResourceKind.cloudStorage]!.path,
            'Reload must render existing logical state.');

        final previousY = grid.getPosition().y;
        tree.getRoot()!.setSize(Vector2i.fromXY(640, 360));
        await _until(() => grid.getPosition().y != previousY);
        final eventsBeforePanel = bloc.tileEvents;
        await _click(viewport, _cell(grid, 4, 4));
        _check(bloc.tileEvents == eventsBeforePanel,
            'The palette panel must intercept a click over an underlying tile.');
        await _click(viewport, _cell(grid, 0, 0));
        _check(bloc.tileEvents == eventsBeforePanel + 1,
            'A grid click must travel through only one input route.');
        _check(bloc.state.selected == const GridPos(0, 0), 'New selection.');
        final tile = grid.getChild(0)!.getChild(0)! as Polygon2D;
        _check((tile.getColor().r - 241 / 255).abs() < 0.01,
            'Selection must update the visible highlight.');
        _check(repository.calls.length == 1,
            'Reload must not repeat provisioning.');
        GD.print(Variant('BLACKSMITH_GODOT_SCENE_PASSED'));
      }
      tree.quit();
    } catch (error, stack) {
      GD.print(Variant('BLACKSMITH_GODOT_FAILED: $error\n$stack'));
      tree.quit(exitCode: 1);
    }
  });
}
