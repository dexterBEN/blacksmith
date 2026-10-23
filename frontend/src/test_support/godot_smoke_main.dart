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
import '../lib/isomap_grid.dart';
import '../lib/resource_visuals.dart';

class _NoNetworkClient extends http.BaseClient {
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    throw StateError('Network access is forbidden in the Godot smoke test.');
  }
}

class _FakeRepository extends CloudStorageRepository {
  _FakeRepository(this.api) : super(api, projectId: 'fake-project');
  final CloudServicesApi api;
  int calls = 0;

  @override
  Future<String> createBucket({required int row, required int col}) {
    calls++;
    throw StateError('Provisioning is forbidden in the Godot smoke test.');
  }
}

class _ObservedBloc extends IsomapGridBloc {
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
  final client = _NoNetworkClient();
  final api = CloudServicesApi(baseUrl: 'http://fake.invalid', client: client);
  final repository = _FakeRepository(api);
  di.sl.registerSingleton<CloudServicesApi>(api, dispose: (api) => api.close());
  di.sl.registerSingleton<CloudStorageRepository>(repository);
  final bloc = _ObservedBloc();
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
      final cloud = buttons.getChild(0)! as TextureButton;
      final compute = buttons.getChild(2)! as TextureButton;
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

      _check(cloud.isDisabled() && compute.isDisabled(),
          'The palette must be disabled until a tile is selected.');
      _check(
          cloud.getTooltipText() == 'Select a tile before placing a resource.',
          'Disabled placement must explain how to enable the palette.');
      await _click(viewport, center(cloud));
      _check(grid.getChild(7)!.getChildCount() == 2,
          'A disabled palette click must not add a resource.');
      await _click(viewport, _cell(grid, 1, 1));
      _check(!cloud.isDisabled() && !compute.isDisabled(),
          'Selecting a tile enables both resource choices.');
      _check(
          cloud.getTooltipText() ==
              resourceVisuals[ResourceKind.cloudStorage]!.tooltip,
          'Enabled buttons restore their service tooltip.');
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
      await _click(viewport, center(cloud));
      _check(
          _icon(grid, 1, 1).getInstanceId() == icon.getInstanceId() &&
              grid.getChild(7)!.getChildCount() == 3,
          'Repeated placement must reuse one sprite without duplicates.');
      await _click(viewport, center(compute));
      _check(
          _icon(grid, 1, 1).getTexture()!.getPath() ==
                  resourceVisuals[ResourceKind.computeEngine]!.path &&
              grid.getChild(7)!.getChildCount() == 3,
          'Replacing Storage with Compute keeps exactly one sprite.');
      await _click(viewport, center(cloud));

      if (localOnly) {
        final previousId = scene.getInstanceId();
        tree.reloadCurrentScene();
        await _until(() =>
            tree.getCurrentScene() != null &&
            tree.getCurrentScene()!.getInstanceId() != previousId);
        await _frame();
        _check(
            tree
                    .getCurrentScene()!
                    .getNodeT<Node2D>('IsoMapGrid')!
                    .getChild(7)!
                    .getChildCount() ==
                2,
            'Scene-owned diagnostic state resets when its scene is disposed.');
        await bloc.close(); // Not registered in diagnostic mode.
      } else {
        _check(bloc.tileEvents == 1, 'Menu clicks must not select grid cells.');
        _check(bloc.listeners == 1, 'One live scene subscription.');
        _check(
            bloc.state.tiles[const GridPos(1, 1)] == ResourceKind.cloudStorage,
            'Storage placement belongs only to the local editor state.');
        final renderer = scene.getNodeT<IsoMapGrid>('IsoMapGrid')!;
        renderer.render(bloc.state);
        renderer.render(bloc.state);
        _check(grid.getChild(7)!.getChildCount() == 3,
            'Redrawing state must not duplicate its sprite.');

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
      }
      _check(repository.calls == 0 && client.requests == 0,
          'Initialization, placement, replacement, redraw and reload must never provision or send HTTP.');
      GD.print(Variant(
          '${localOnly ? "BLACKSMITH_GODOT_LOCAL_PASSED" : "BLACKSMITH_GODOT_SCENE_PASSED"} '
          'repository_calls=0 http_requests=0'));
      tree.quit();
    } catch (error, stack) {
      GD.print(Variant('BLACKSMITH_GODOT_FAILED: $error\n$stack'));
      tree.quit(exitCode: 1);
    }
  });
}
