// Match the native resolver's file-URI library identities.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';
import 'package:godot_dart/godot_dart.dart';
import 'workspace_test_input.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import '../lib/prototypes/isometric_3d/workspace_layout.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/resource_kind.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/resource_visuals_3d.dart';

/// Assert actual native projections against the actual panel, not the fitting
/// formula. Also reserve hypothetical cubes on every tile of an empty board.
void checkEditorFraming(Node scene) {
  final camera = Workspace3D.camera(scene);
  final viewport = scene.getViewport()!.getVisibleRect().size;
  final rect = Workspace3D.canvasRect(scene);
  final renderSize = Workspace3D.viewport(scene).getVisibleRect().size;
  final header =
      scene.getNodeT<PanelContainer>(Workspace3D.header)!.getGlobalRect();
  final sidebar =
      scene.getNodeT<PanelContainer>(Workspace3D.sidebar)!.getGlobalRect();
  final docks = [Workspace3D.sidebar, Workspace3D.inspector]
      .map((path) => scene.getNodeT<Control>(path)!)
      .where((control) => control.isVisibleInTree())
      .map((control) => control.getGlobalRect())
      .toList();
  _check(
      rect.size.x >= WorkspaceLayout.minimumCanvasWidth - .1 &&
          rect.size.y >= WorkspaceLayout.minimumCanvasHeight - .1 &&
          (renderSize.x - rect.size.x).abs() <= 1 &&
          (renderSize.y - rect.size.y).abs() <= 1,
      'A real render viewport must follow the canvas container dimensions.');
  for (final panel in [header, rect, ...docks]) {
    _check(
        panel.position.x >= 0 &&
            panel.position.y >= 0 &&
            panel.end.x <= viewport.x + .1 &&
            panel.end.y <= viewport.y + .1,
        'Every workspace panel must fit the actual main viewport.');
  }
  _check(
      (rect.position.x - WorkspaceLayout.margin).abs() < .1 &&
          (rect.size.x - (viewport.x - 2 * WorkspaceLayout.margin)).abs() < .1,
      'The viewport fills the complete body width without a navigation allocation.');
  _check(
      rect.position.y >= header.end.y + 7 &&
          (rect.end.y - (viewport.y - 8)).abs() <= .1 &&
          !scene.hasNode(
              NodePath.fromString('${Workspace3D.body}/Center/QuickPlacement')),
      'The canvas fills the body down to its bottom margin, with no footer allocation.');
  _check(
      !scene.hasNode(NodePath.fromString(
              '${Workspace3D.header}/Rows/Actions/PlacementChoices')) &&
          !scene.hasNode(NodePath.fromString(
              '${Workspace3D.header}/Rows/Actions/PlacementSeparator')),
      'The header contains Design actions; resource tools belong to the Library.');
  final container = scene.getNodeT<Control>(Workspace3D.catalog)!;
  _check(container.getChildCount() == 4,
      'Exactly four resource controls in the single Library palette.');
  if (container.isVisibleInTree()) {
    final scroll = scene
        .getNodeT<Control>('${Workspace3D.sidebar}/Content/Scroll')!
        .getGlobalRect();
    for (final entry in resourceVisuals3D.values) {
      final button = container.getNodeT<Button>(entry.buttonName)!;
      final bounds = button.getGlobalRect();
      // The native sidebar retains its vertical scroll container; no horizontal
      // overflow is permitted at the minimum dock width.
      _check(
          bounds.position.x >= sidebar.position.x &&
              bounds.end.x <= sidebar.end.x + .1 &&
              bounds.position.y >= scroll.position.y - .1 &&
              bounds.end.y <= scroll.end.y + .1,
          'All four labelled resource tools are fully visible in the open Library.');
    }
  }
  void point(Vector3 world) {
    final screen = camera.unprojectPosition(world);
    _check(
        screen.x > 12 &&
            screen.x < renderSize.x - 12 &&
            screen.y > 12 &&
            screen.y < renderSize.y - 12,
        'Every tile/cube corner must fit inside the allocated render viewport: '
        '${renderSize.x}x${renderSize.y}, point=${screen.x},${screen.y}.');
  }

  void meshBounds(MeshInstance3D mesh) {
    final box = mesh.getMesh()!.getAabb();
    for (final x in [box.position.x, box.position.x + box.size.x]) {
      for (final y in [box.position.y, box.position.y + box.size.y]) {
        for (final z in [box.position.z, box.position.z + box.size.z]) {
          point(mesh.toGlobal(Vector3(x: x, y: y, z: z)));
        }
      }
    }
  }

  final grid = scene.getNodeT<Node3D>('GridRoot')!;
  for (var row = 0; row < 6; row++) {
    for (var col = 0; col < 6; col++) {
      meshBounds(grid.getChild(row * 6 + col)! as MeshInstance3D);
      final center = const GridLayout3D().worldPosition(GridPos(row, col));
      for (final dx in [-.34, .34]) {
        for (final dz in [-.34, .34]) {
          for (final y in [.12, .80]) {
            point((scene as Node3D)
                .toGlobal(Vector3(x: center.x + dx, y: y, z: center.z + dz)));
          }
        }
      }
    }
  }
  final resources = scene.getNodeT<Node3D>('ResourceRoot')!;
  for (var i = 0; i < resources.getChildCount(); i++) {
    meshBounds(resources.getChild(i)!.getNodeT<MeshInstance3D>('Cube')!);
  }
  final transform = camera.getTransform();
  _check(
      (transform.origin - Vector3(x: 10, y: 10, z: 10)).length < 1e-5 &&
          (transform.basis.x - Vector3(x: .707107, y: 0, z: -.707107)).length <
              1e-5 &&
          (transform.basis.y - Vector3(x: -.408248, y: .816497, z: -.408248))
                  .length <
              1e-5 &&
          (transform.basis.z - Vector3(x: .57735, y: .57735, z: .57735))
                  .length <
              1e-5 &&
          camera.getProjection() == Camera3DProjectionType.projectionOrthogonal,
      'Keep the original native camera transform and orthographic projection.');
}

Future<void> checkEditorResizing(Node scene, IsomapGridBloc bloc,
    {required int Function() tileEvents, required bool capture}) async {
  final window = (Engine.singleton.getMainLoop()! as SceneTree).getRoot()!;
  final camera = Workspace3D.camera(scene);
  for (final size in const [
    (1152, 648),
    (Workspace3D.minimumWidth, Workspace3D.minimumHeight),
    (1024, 768),
    (1280, 800),
    (1440, 900),
    (1600, 900)
  ]) {
    window.setContentScaleSize(Vector2i.fromXY(size.$1, size.$2));
    await _pause();
    if (!scene.getNodeT<Control>(Workspace3D.sidebar)!.isVisibleInTree()) {
      await openWorkspaceAction(scene, Workspace3D.libraryToggle);
    }
    checkEditorFraming(scene);
    await dismissWorkspaceMenus(scene);
    final cameraSize = camera.getSize();
    final offset = camera.getVOffset();
    for (var row = 0; row < 6; row++) {
      for (var col = 0; col < 6; col++) {
        final position = GridPos(row, col);
        final center = const GridLayout3D().worldPosition(position);
        final screen = Workspace3D.project(
            scene,
            (scene as Node3D)
                .toGlobal(Vector3(x: center.x, y: .12, z: center.z)));
        final before = tileEvents();
        await _click(scene, screen);
        _check(bloc.state.selected == position && tileEvents() == before + 1,
            'All 36 tile centers remain selectable after resize.');
      }
    }
    await openWorkspaceAction(scene, Workspace3D.libraryToggle);
    final button =
        scene.getNodeT<Button>('${Workspace3D.catalog}/ComputeEngine')!;
    final before = tileEvents();
    await _click(scene, button.getGlobalRect().getCenter());
    await confirmResourceChoice(scene);
    _check(
        tileEvents() == before &&
            bloc.state.selected == const GridPos(5, 5) &&
            bloc.state.tiles[const GridPos(5, 5)] == ResourceKind.computeEngine,
        'Foreground placement consumes palette input without changing selection.');
    _check(
        (camera.getSize() - cameraSize).abs() < 1e-5 &&
            (camera.getVOffset() - offset).abs() < 1e-5,
        'Selection and placement must not change the framing.');
    final foreground =
        scene.getNodeT<Node3D>('GridRoot')!.getChild(35)! as MeshInstance3D;
    _check(foreground.getMaterialOverride() != null,
        'Foreground selection remains visible beneath the cube.');
    checkEditorFraming(scene);
    if (capture) {
      await RenderingServer.singleton.framePostDraw.asFuture(scene);
      final image = scene.getViewport()!.getTexture()!.getImage()!;
      _check(image.getWidth() == size.$1 && image.getHeight() == size.$2,
          'Evidence must use the requested internal viewport.');
      final output = Platform.environment['BLACKSMITH_ISSUE17_OUTPUT']!;
      _check(
          image.saveJpg('$output/framing_${size.$1}x${size.$2}.jpg',
                  quality: .95) ==
              GDError.ok,
          'Capture actual Godot rendering.');
    }
  }
  window.setContentScaleSize(Vector2i.fromXY(1152, 648));
  await _pause();
  checkEditorFraming(scene);
  // Exercise actual native window resizing too: interactive mode must follow
  // its dimensions rather than letterboxing a fixed 1152x648 internal viewport.
  if (capture) {
    final originalSize = window.getSize();
    window
      ..setContentScaleMode(WindowContentScaleMode.disabled)
      ..setContentScaleSize(Vector2i.fromXY(0, 0));
    for (final size in const [
      (1152, 648),
      (Workspace3D.minimumWidth, Workspace3D.minimumHeight)
    ]) {
      window.setSize(Vector2i.fromXY(size.$1, size.$2));
      for (var i = 0; i < 80; i++) {
        final actual = scene.getViewport()!.getVisibleRect().size;
        if (actual.x == size.$1 && actual.y == size.$2) break;
        await _pause();
      }
      final actual = scene.getViewport()!.getVisibleRect().size;
      _check(actual.x == size.$1 && actual.y == size.$2,
          'Interactive viewport must track the physical window size.');
      await _pause();
      checkEditorFraming(scene);
    }
    window
      ..setSize(originalSize)
      ..setContentScaleMode(WindowContentScaleMode.viewport)
      ..setContentScaleAspect(WindowContentScaleAspect.keep)
      ..setContentScaleSize(Vector2i.fromXY(1152, 648));
    await _pause();
    checkEditorFraming(scene);
    GD.print(Variant('BLACKSMITH_ISSUE35_WINDOW_RESIZE_PASSED sizes=2'));
  }
  GD.print(Variant('BLACKSMITH_ISSUE35_FRAMING_PASSED sizes=6 '
      'tile_centers=216 cube_bounds=true palette_clear=true stable=true'));
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
