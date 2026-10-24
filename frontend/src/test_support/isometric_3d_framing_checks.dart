// Match the native resolver's file-URI library identities.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';
import 'package:godot_dart/godot_dart.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/resource_kind.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/resource_visuals_3d.dart';

/// Assert actual native projections against the actual panel, not the fitting
/// formula. Also reserve hypothetical cubes on every tile of an empty board.
void checkEditorFraming(Node scene) {
  final camera = scene.getNodeT<Camera3D>('Camera3D')!;
  final viewport = scene.getViewport()!.getVisibleRect().size;
  final panel = scene.getNodeT<Panel>('PaletteLayer/ResourcePalette/Panel')!;
  final rect = panel.getGlobalRect();
  final header = scene
      .getNodeT<Panel>('DesignLayer/DesignControls/Header')!
      .getGlobalRect();
  _check(
      header.position.x >= 0 &&
          header.position.y >= 0 &&
          header.end.x <= viewport.x &&
          header.end.y < rect.position.y,
      'Design header stays inside the viewport above the board.');
  _check(
      rect.position.x >= 0 &&
          rect.position.y > 24 &&
          rect.position.x + rect.size.x <= viewport.x &&
          rect.position.y + rect.size.y <= viewport.y,
      'Palette must fit inside the viewport.');
  for (final entry in resourceVisuals3D.values) {
    final button = panel.getNodeT<Button>('Choices/${entry.buttonName}')!;
    final bounds = button.getGlobalRect();
    _check(
        bounds.position.x >= rect.position.x &&
            bounds.position.y >= rect.position.y &&
            bounds.position.x + bounds.size.x <=
                rect.position.x + rect.size.x + .1 &&
            bounds.position.y + bounds.size.y <=
                rect.position.y + rect.size.y + .1,
        'Each palette button must stay inside its panel: ${entry.buttonName} '
        'at ${bounds.position.x},${bounds.position.y} '
        '${bounds.size.x}x${bounds.size.y}, panel '
        '${rect.position.x},${rect.position.y} ${rect.size.x}x${rect.size.y}.');
  }
  void point(Vector3 world) {
    final screen = camera.unprojectPosition(world);
    _check(
        screen.x > 12 &&
            screen.x < viewport.x - 12 &&
            screen.y > header.end.y + 12 &&
            screen.y < rect.position.y - 12,
        'Every tile/cube corner must clear the viewport and palette: '
        '${viewport.x}x${viewport.y}, point=${screen.x},${screen.y}.');
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
  final camera = scene.getNodeT<Camera3D>('Camera3D')!;
  for (final size in const [
    (1152, 648),
    (640, 360),
    (480, 360),
    (800, 600),
    (480, 640),
    (1600, 900)
  ]) {
    window.setContentScaleSize(Vector2i.fromXY(size.$1, size.$2));
    await _pause();
    checkEditorFraming(scene);
    final cameraSize = camera.getSize();
    final offset = camera.getVOffset();
    for (var row = 0; row < 6; row++) {
      for (var col = 0; col < 6; col++) {
        final position = GridPos(row, col);
        final center = const GridLayout3D().worldPosition(position);
        final screen = camera.unprojectPosition((scene as Node3D)
            .toGlobal(Vector3(x: center.x, y: .12, z: center.z)));
        final before = tileEvents();
        await _click(scene, screen);
        _check(bloc.state.selected == position && tileEvents() == before + 1,
            'All 36 tile centers remain selectable after resize.');
      }
    }
    final button = scene.getNodeT<Button>(
        'PaletteLayer/ResourcePalette/Panel/Choices/CloudStorage')!;
    final before = tileEvents();
    await _click(scene, button.getGlobalRect().getCenter());
    _check(
        tileEvents() == before &&
            bloc.state.selected == const GridPos(5, 5) &&
            bloc.state.tiles[const GridPos(5, 5)] == ResourceKind.cloudStorage,
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
    for (final size in const [(800, 600), (640, 480)]) {
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
