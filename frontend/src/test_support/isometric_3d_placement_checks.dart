// Match the native resolver's file-URI library identities.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';
import 'package:godot_dart/godot_dart.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_event.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/resource_kind.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/resource_visuals_3d.dart';
import 'isometric_3d_framing_checks.dart';

/// Real native input and scene ownership checks, using the shared local BLoC.
Future<Node> check3DPlacement(SceneTree tree, IsomapGridBloc bloc,
    {required void Function(IsomapGridState) restore,
    required int Function() tileEvents,
    required int Function() listeners,
    required bool capture}) async {
  var scene = tree.getCurrentScene()!;
  restore(IsomapGridState.initial());
  await _pause();
  for (final kind in ResourceKind.values) {
    final button = _button(scene, kind);
    _check(button.isDisabled() && button.getButtonIcon() != null,
        'Four disabled, illustrated native palette buttons.');
    await _click(scene, button.getGlobalRect().getCenter());
  }
  _check(bloc.state.selected == null && bloc.state.tiles.isEmpty,
      'Disabled palette must neither place nor select.');
  if (capture) await _capture(scene, '01_empty.jpg');

  Future<void> select(GridPos position) async {
    final center = const GridLayout3D().worldPosition(position);
    final point = Workspace3D.project(
        scene,
        (scene as Node3D).toGlobal(
            Vector3(x: center.x, y: GridLayout3D.tileHeight / 2, z: center.z)));
    await _click(scene, point);
    _check(bloc.state.selected == position, 'Actual tile click: $position.');
    final tile = scene
        .getNodeT<Node3D>('GridRoot')!
        .getChild(position.row * 6 + position.col)! as MeshInstance3D;
    _check(tile.getMaterialOverride() != null,
        'Selected occupied or empty tile retains its highlight.');
  }

  Future<void> choose(ResourceKind kind) async {
    final selected = bloc.state.selected;
    final before = tileEvents();
    final button = _button(scene, kind);
    if (kind == ResourceKind.cloudStorage) {
      _check(button.isDisabled(),
          'Isolated preview cannot configure without an active Design.');
      // Explicit legacy fixture for rendering checks; configured UI is tested
      // through the production bootstrap and real API by --persistence.
      bloc.add(const PlaceResource(ResourceKind.cloudStorage));
      await _pause();
    } else {
      _check(!button.isDisabled(), 'Selected tile enables local placement.');
      await _click(scene, button.getGlobalRect().getCenter());
    }
    _check(bloc.state.selected == selected && tileEvents() == before,
        'Palette must consume input before the 3D grid.');
    _check(
        bloc.state.tiles[selected] == kind, 'Palette updates the real BLoC.');
    _checkResources(scene, bloc.state);
  }

  const storage = GridPos(2, 3);
  const compute = GridPos(4, 1);
  await select(storage);
  if (capture) await _capture(scene, '02_selected.jpg');
  await choose(ResourceKind.cloudStorage);
  await select(compute);
  await choose(ResourceKind.computeEngine);
  if (capture) await _capture(scene, '03_storage_compute.jpg');
  await select(const GridPos(1, 1));
  await choose(ResourceKind.cloudVpn);
  await select(const GridPos(1, 4));
  await choose(ResourceKind.cloudLoadBalancing);
  if (capture) await _capture(scene, '04_four_services.jpg');
  await select(storage);
  if (capture) await _capture(scene, '05_before_replacement.jpg');
  final previous = _cube(scene, storage).getInstanceId();
  final neighbor = _cube(scene, compute).getInstanceId();
  await choose(ResourceKind.cloudVpn);
  _check(!GD.isInstanceIdValid(previous), 'Replaced cube must be freed.');
  _check(_cube(scene, compute).getInstanceId() == neighbor,
      'Unchanged cubes must not be rebuilt.');
  if (capture) await _capture(scene, '06_after_replacement.jpg');
  final sameKind = _cube(scene, storage).getInstanceId();
  await choose(ResourceKind.cloudVpn);
  _check(_cube(scene, storage).getInstanceId() == sameKind,
      'Repeated identical placement must reuse its node.');
  for (final kind in ResourceKind.values) {
    await choose(kind);
  }
  for (final position in const [
    GridPos(0, 0),
    GridPos(0, 5),
    GridPos(5, 0),
    GridPos(5, 5),
    GridPos(0, 2)
  ]) {
    await select(position);
    await choose(ResourceKind.cloudStorage);
  }
  await select(const GridPos(5, 5));
  if (capture) await _capture(scene, '07_selected_corner.jpg');
  await checkEditorResizing(scene, bloc,
      tileEvents: tileEvents, capture: capture);

  // Full state changes must render even when selection is unchanged.
  final removed = _cube(scene, storage).getInstanceId();
  restore(bloc.state.copyWith(tiles: {...bloc.state.tiles}..remove(storage)));
  await _pause();
  _check(!GD.isInstanceIdValid(removed), 'Removed state frees its visual.');
  _checkResources(scene, bloc.state);
  final cameraSize = Workspace3D.camera(scene).getSize();
  tree.getRoot()!.setContentScaleSize(
      Vector2i.fromXY(Workspace3D.minimumWidth, Workspace3D.minimumHeight));
  await _pause();
  for (final kind in ResourceKind.values) {
    final rect = _button(scene, kind).getGlobalRect();
    _check(
        rect.position.x >= 0 &&
            rect.position.y >= 0 &&
            rect.position.x + rect.size.x <= Workspace3D.minimumWidth &&
            rect.position.y + rect.size.y <= Workspace3D.minimumHeight,
        'Desktop palette must remain fully visible at the minimum size.');
  }
  await choose(ResourceKind.cloudLoadBalancing);
  tree.getRoot()!.setContentScaleSize(Vector2i.fromXY(1152, 648));
  await _pause();
  _check((Workspace3D.camera(scene).getSize() - cameraSize).abs() < 1e-4,
      'Viewport restoration preserves the original camera.');

  final oldIds = [
    scene.getInstanceId(),
    for (var i = 0; i < _root(scene).getChildCount(); i++)
      _root(scene).getChild(i)!.getInstanceId()
  ];
  tree.unloadCurrentScene();
  await _pause();
  _check(
      listeners() == 0 &&
          !bloc.isClosed &&
          oldIds.every((id) => !GD.isInstanceIdValid(id)),
      'Scene exit frees cubes/signals and cancels only its subscription.');
  bloc.add(const TileClicked(compute));
  await _pause();
  _check(listeners() == 0, 'No callbacks survive scene exit.');
  _check(tree.changeSceneToFile('res://scenes/isometric_3d.tscn') == GDError.ok,
      'Reload the same scene.');
  for (var i = 0; tree.getCurrentScene() == null && i < 80; i++) {
    await _pause();
  }
  scene = tree.getCurrentScene()!;
  await _pause();
  _check(
      listeners() == 1 && !bloc.isClosed, 'Exactly one shared subscription.');
  _checkResources(scene, bloc.state);
  await choose(ResourceKind.cloudVpn);
  return scene;
}

Node3D _root(Node scene) => scene.getNodeT<Node3D>('ResourceRoot')!;
Node3D _cube(Node scene, GridPos position) =>
    _root(scene).getNodeT<Node3D>('Resource_${position.row}_${position.col}')!;
Button _button(Node scene, ResourceKind kind) => scene.getNodeT<Button>(
    '${Workspace3D.choices}/${resourceVisuals3D[kind]!.buttonName}')!;

void _checkResources(Node scene, IsomapGridState state) {
  _check(_root(scene).getChildCount() == state.tiles.length,
      'Exactly one cube per occupied tile, no static demo.');
  int? sharedMesh;
  for (final entry in state.tiles.entries) {
    final cube = _cube(scene, entry.key);
    _check(cube.getSceneFilePath() == resourceVisuals3D[entry.value]!.scenePath,
        'The instantiated scene must match the logical GCP service.');
    final point = const GridLayout3D().worldPosition(entry.key);
    final position = cube.getPosition();
    final scale = cube.getScale();
    _check(
        (position.x - point.x).abs() < 1e-5 &&
            (position.z - point.z).abs() < 1e-5 &&
            (position.y - .12).abs() < 1e-5 &&
            [scale.x, scale.y, scale.z]
                .every((value) => (value - .68).abs() < 1e-5),
        'Cube must fit its tile and rest precisely on its top surface.');
    final mesh = cube.getNodeT<MeshInstance3D>('Cube')!.getMesh()!;
    final bounds = mesh.getAabb();
    _check(
        bounds.position.y.abs() < 1e-5 &&
            bounds.size.x * scale.x < GridLayout3D.pitch &&
            cube.getRotation().length < 1e-5,
        'Asset base, footprint and camera-facing orientation remain intact.');
    sharedMesh ??= mesh.getInstanceId();
    _check(
        mesh.getInstanceId() == sharedMesh, 'Existing cube mesh stays shared.');
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _pause() =>
    Future<void>.delayed(const Duration(milliseconds: 150));
Future<void> _click(Node scene, Vector2 point) async {
  final viewport = scene.getViewport()!;
  viewport.pushInput(InputEventMouseMotion()..setPosition(point),
      inLocalCoords: true);
  for (final pressed in [true, false]) {
    viewport.pushInput(
        InputEventMouseButton()
          ..setPosition(point)
          ..setGlobalPosition(point)
          ..setButtonIndex(MouseButton.left)
          ..setPressed(pressed),
        inLocalCoords: true);
    await _pause();
  }
}

Future<void> _capture(Node scene, String filename) async {
  await RenderingServer.singleton.framePostDraw.asFuture(scene);
  final image = scene.getViewport()!.getTexture()!.getImage()!;
  _check(image.getWidth() == 1152 && image.getHeight() == 648,
      'Evidence uses the same native viewport and unchanged camera.');
  final output = Platform.environment['BLACKSMITH_ISSUE17_OUTPUT']!;
  _check(image.saveJpg('$output/$filename', quality: .95) == GDError.ok,
      'Save actual Godot rendering, never generated concept art.');
}
