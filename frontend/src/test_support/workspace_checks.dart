// Match the production resolver's file-URI library identities.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';
import 'dart:io';
import 'package:godot_dart/godot_dart.dart';
import '../lib/domain/bloc/design/design_cubit.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_event.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/resource_kind.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/resource_visuals_3d.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import 'isometric_3d_framing_checks.dart';

/// Native desktop layout/pointer checks. The caller supplies the real runtime
/// Cubit/BLoC and a fail-closed Design repository, never a replacement grid.
Future<void> checkWorkspace(Node scene, IsomapGridBloc grid, DesignCubit design,
    {required int Function() tileEvents}) async {
  final window = scene.getTree()!.getRoot()!;
  final originalMode = window.getContentScaleMode();
  final originalSize = window.getContentScaleSize();
  final originalAspect = window.getContentScaleAspect();
  final output = Platform.environment['BLACKSMITH_WORKSPACE_OUTPUT']!;
  window
    ..setContentScaleMode(WindowContentScaleMode.viewport)
    ..setContentScaleAspect(WindowContentScaleAspect.keep)
    ..setContentScaleSize(Vector2i.fromXY(1280, 800));
  await _settle(scene);
  checkEditorFraming(scene);
  for (final group in [Workspace3D.catalog, Workspace3D.choices]) {
    for (final kind in ResourceKind.values) {
      final button = _button(scene, group, kind);
      _check(
          button.isDisabled() &&
              button.getButtonIcon() != null &&
              button.getFocusMode() == ControlFocusMode.focusNone,
          'All eight illustrated choices require a selected tile.');
      await _click(scene, button.getGlobalRect().getCenter());
    }
  }
  _check(grid.state.selected == null && grid.state.tiles.isEmpty,
      'Disabled catalog/quick actions cannot select or place.');
  await _capture(scene, '$output/dark_empty.png');

  // Explicit fixture creation solely to test that a non-empty active Design
  // survives desktop resizing. The repository sends no HTTP request.
  design.open();
  design.changeName('Desktop workspace validation');
  await design.submit();
  await _settle(scene);
  final active = design.state.active;
  _check(active != null, 'The layout test must include an active Design.');

  Future<void> select(GridPos pos) async {
    final p = const GridLayout3D().worldPosition(pos);
    final screen = Workspace3D.project(
        scene, (scene as Node3D).toGlobal(Vector3(x: p.x, y: .12, z: p.z)));
    final before = tileEvents();
    await _click(scene, screen);
    _check(grid.state.selected == pos && tileEvents() == before + 1,
        'Canvas-local picking emits exactly one logical selection.');
  }

  Future<void> choose(String group, ResourceKind kind) async {
    final selected = grid.state.selected;
    final before = tileEvents();
    final button = _button(scene, group, kind);
    if (kind == ResourceKind.cloudStorage) {
      // This offline geometry regression uses an explicitly local legacy cube.
      // The real configured Save journey is covered by --persistence.
      if (!button.isDisabled()) {
        await _click(scene, button.getGlobalRect().getCenter());
        _check(design.state.configurationDraft != null,
            'Cloud Storage opens configuration instead of placing a cube.');
        design.cancelResourceConfiguration();
        await _settle(scene);
      } else {
        _check(grid.state.tiles[selected] != ResourceKind.cloudStorage,
            'Cloud Storage does not silently replace a different local kind.');
      }
      grid.add(const PlaceResource(ResourceKind.cloudStorage));
      await _settle(scene);
    } else {
      _check(!button.isDisabled(), 'A selected local tile enables placement.');
      await _click(scene, button.getGlobalRect().getCenter());
    }
    _check(
        grid.state.selected == selected &&
            grid.state.tiles[selected] == kind &&
            tileEvents() == before,
        'Other local kinds and the explicit legacy fixture preserve selection.');
    final cube = _cube(scene, selected!);
    _check(
        cube.getSceneFilePath() == resourceVisuals3D[kind]!.scenePath &&
            (cube.getPosition().y - .12).abs() < 1e-5 &&
            (cube.getScale() - Vector3(x: .68, y: .68, z: .68)).length < 1e-5,
        'Reuse the existing uniformly sized cube directly on the tile.');
  }

  // Each kind is exercised from each UI entry point; same-tile replacement
  // changes the one cube, without introducing an active-resource tool state.
  for (var i = 0; i < ResourceKind.values.length; i++) {
    final kind = ResourceKind.values[i];
    final next = ResourceKind.values[(i + 1) % ResourceKind.values.length];
    final pos = GridPos(2, i);
    await select(pos);
    await choose(Workspace3D.catalog, kind);
    final old = _cube(scene, pos).getInstanceId();
    await choose(Workspace3D.choices, next);
    _check(!GD.isInstanceIdValid(old), 'Replacement frees the previous cube.');
    await choose(Workspace3D.choices, kind);
  }
  grid.add(
      const ResetGridForNewDesign()); // Reset this independent test scenario.
  await _settle(scene);
  const corners = [GridPos(0, 0), GridPos(0, 5), GridPos(5, 0), GridPos(5, 5)];
  for (var i = 0; i < corners.length; i++) {
    await select(corners[i]);
    await choose(i.isEven ? Workspace3D.catalog : Workspace3D.choices,
        ResourceKind.values[i]);
  }
  checkEditorFraming(scene);
  final ids = {for (final p in corners) p: _cube(scene, p).getInstanceId()};
  await _capture(scene, '$output/dark_resources.png');

  final beforeUiClicks = grid.state;
  for (final path in [
    Workspace3D.header,
    Workspace3D.sidebar,
    Workspace3D.quick
  ]) {
    final rect = scene.getNodeT<Control>(path)!.getGlobalRect();
    await _click(scene, rect.position + Vector2(x: 2, y: 2));
  }
  _check(grid.state == beforeUiClicks,
      'UI margins and panels do not select tiles behind them.');
  for (final size in const [
    (Workspace3D.minimumWidth, Workspace3D.minimumHeight),
    (1024, 768),
    (1920, 1080)
  ]) {
    window.setContentScaleSize(Vector2i.fromXY(size.$1, size.$2));
    await _settle(scene);
    checkEditorFraming(scene);
    for (final pos in corners) {
      await select(pos);
    }
    _check(
        design.state.active == active &&
            corners.every((p) => _cube(scene, p).getInstanceId() == ids[p]),
        'Desktop resizing preserves the existing Design and cube nodes.');
    final sidebar = scene.getNodeT<Control>(Workspace3D.sidebar)!;
    _check(sidebar.getSize().x == 236,
        'The standard desktop sidebar keeps its width.');
    final scroll = scene
        .getNodeT<ScrollContainer>('${Workspace3D.sidebar}/Content/Scroll')!;
    for (final kind in ResourceKind.values) {
      final button = _button(scene, Workspace3D.catalog, kind);
      final rect = scroll.getGlobalRect();
      final bounds = button.getGlobalRect();
      _check(
          bounds.position.y >= rect.position.y - .1 &&
              bounds.end.y <= rect.end.y + .1 &&
              button.getText() == resourceVisuals3D[kind]!.label,
          'All four full resource labels remain visible without wrapping or scrolling.');
    }
    if (size.$1 == Workspace3D.minimumWidth) {
      await _capture(scene, '$output/minimum_resources.png');
    }
  }
  grid.add(const ResetGridForNewDesign());
  window
    ..setContentScaleMode(originalMode)
    ..setContentScaleSize(originalSize)
    ..setContentScaleAspect(originalAspect);
  await _settle(scene);
  checkEditorFraming(scene);
  GD.print(Variant('BLACKSMITH_WORKSPACE_PASSED resources=4 entry_points=2 '
      'desktop_sizes=4 minimum=960x640 active_design_preserved=true native_nodes_preserved=true'));
}

Button _button(Node scene, String group, ResourceKind kind) =>
    scene.getNodeT<Button>('$group/${resourceVisuals3D[kind]!.buttonName}')!;
Node3D _cube(Node scene, GridPos p) =>
    scene.getNodeT<Node3D>('ResourceRoot/Resource_${p.row}_${p.col}')!;
void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _settle(Node scene) async {
  await RenderingServer.singleton.framePostDraw.asFuture(scene);
  await Future<void>.delayed(const Duration(milliseconds: 150));
  await RenderingServer.singleton.framePostDraw.asFuture(scene);
}

Future<void> _capture(Node scene, String path) async {
  await _settle(scene);
  _check(
      scene.getViewport()!.getTexture()!.getImage()!.savePng(path) ==
          GDError.ok,
      'Save unmodified native Godot viewport.');
}

Future<void> _click(Node scene, Vector2 point) async {
  final viewport = scene.getViewport()!;
  viewport.pushInput(InputEventMouseMotion()..setPosition(point),
      inLocalCoords: true);
  await _settle(scene);
  for (final pressed in [true, false]) {
    viewport.pushInput(
        InputEventMouseButton()
          ..setPosition(point)
          ..setGlobalPosition(point)
          ..setButtonIndex(MouseButton.left)
          ..setPressed(pressed),
        inLocalCoords: true);
    await _settle(scene);
  }
}
