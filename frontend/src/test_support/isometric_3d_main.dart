// Match Godot's file-URI script identities and the generated resolver.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async' as async;
import 'dart:convert';
import 'dart:io';
import 'package:godot_dart/godot_dart.dart';
import '../godot_dart_scripts.g.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';

/// Isolated launch/test entrypoint: does not initialize application DI.
void main() {
  attachScriptResolver();
  GD.print(Variant('BLACKSMITH_ISSUE15_DART_READY'));
  if (Engine.singleton.isEditorHint()) return;
  async.Timer.run(() async {
    final tree = Engine.singleton.getMainLoop()! as SceneTree;
    try {
      await _until(() => tree.getCurrentScene() != null);
      final scene = tree.getCurrentScene()!;
      tree.getRoot()!.closeRequested.connect(scene, () => tree.quit());
      final window = tree.getRoot()!;
      // X11's window manager can override requested window dimensions. Keep
      // capture/framing assertions deterministic through an internal viewport.
      window
        ..setContentScaleMode(WindowContentScaleMode.viewport)
        ..setContentScaleAspect(WindowContentScaleAspect.keep)
        ..setContentScaleSize(Vector2i.fromXY(1152, 648));
      await _until(
          () => scene.getNodeT<Node3D>('GridRoot')!.getChildCount() == 36);
      await _pause();
      _validate(scene);
      // Validate automatic framing at a narrow viewport too; no navigation
      // control or production camera is modified.
      final camera = scene.getNodeT<Camera3D>('Camera3D')!;
      final originalSize = camera.getSize();
      window.setContentScaleSize(Vector2i.fromXY(480, 640));
      await _until(() => camera.getSize() > originalSize);
      _validateFraming(scene, camera);
      window.setContentScaleSize(Vector2i.fromXY(1152, 648));
      await _until(() => (camera.getSize() - originalSize).abs() < 1e-4);
      _validateFraming(scene, camera);
      GD.print(Variant('BLACKSMITH_ISSUE15_SCENE_PASSED tiles=36 beveled=true '
          'shared_mesh=true orthographic=true mapping=true resize=true'));

      final mode = Platform.environment['BLACKSMITH_ISSUE15_MODE'];
      if (mode == 'interactive') return;
      if (mode == 'headless') {
        tree.quit();
        return;
      }
      await _captureRuntime(scene);
      GD.print(Variant('BLACKSMITH_ISSUE15_RENDER_PASSED'));
      tree.quit();
    } catch (error, stack) {
      GD.print(Variant('BLACKSMITH_ISSUE15_FAILED: $error\n$stack'));
      tree.quit(exitCode: 1);
    }
  });
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _pause() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) return;
    await _pause();
  }
  throw StateError('Timed out waiting for the 3D scene/frame.');
}

void _validate(Node scene) {
  _check(scene is Node3D, 'The root must be Node3D.');
  const layout = GridLayout3D();
  final grid = scene.getNodeT<Node3D>('GridRoot')!;
  _check(grid.getChildCount() == 36, 'Exactly 36 tile nodes are required.');
  int? sharedMesh;
  int? sharedMaterial;
  for (var row = 0; row < layout.rows; row++) {
    for (var col = 0; col < layout.cols; col++) {
      final tile = grid.getNodeT<MeshInstance3D>('Tile_${row}_$col')!;
      final expected = layout.worldPosition(GridPos(row, col));
      final position = tile.getPosition();
      _check(
          (position.x - expected.x).abs() < 1e-5 &&
              position.y.abs() < 1e-5 &&
              (position.z - expected.z).abs() < 1e-5,
          'Logical/world mapping must agree for ($row,$col).');
      final mesh = tile.getMesh()! as ArrayMesh;
      final size = mesh.getAabb().size;
      _check(
          (size.x - 1).abs() < 1e-5 &&
              (size.y - 0.24).abs() < 1e-5 &&
              (size.z - 1).abs() < 1e-5,
          'Tile mesh dimensions and thickness.');
      _check(
          mesh.getSurfaceCount() == 1 && mesh.surfaceGetArrayIndexLen(0) == 132,
          'The mesh must contain the complete 44-triangle bevel treatment.');
      _check(
          mesh.surfaceGetFormat(0) & 2 != 0, 'Bevel normals must be present.');
      sharedMesh ??= mesh.getInstanceId();
      final material = tile.getMaterialOverride()! as StandardMaterial3D;
      sharedMaterial ??= material.getInstanceId();
      _check(
          mesh.getInstanceId() == sharedMesh &&
              material.getInstanceId() == sharedMaterial,
          'All tiles must reuse the mesh and material.');
    }
  }
  final camera = scene.getNodeT<Camera3D>('Camera3D')!;
  _check(camera.getProjection() == Camera3DProjectionType.projectionOrthogonal,
      'An orthographic camera is required.');
  _check(
      scene.getNodeT<WorldEnvironment>('WorldEnvironment')!.getEnvironment() !=
          null,
      'A native environment is required.');
  _check(scene.getNodeT<DirectionalLight3D>('DirectionalLight3D')!.hasShadow(),
      'Basic directional shadows must be enabled.');
  _validateFraming(scene, camera);
}

void _validateFraming(Node scene, Camera3D camera) {
  const layout = GridLayout3D();
  final viewport = scene.getViewport()!.getVisibleRect().size;
  for (final x in [-layout.width / 2, layout.width / 2]) {
    for (final z in [-layout.depth / 2, layout.depth / 2]) {
      for (final y in [
        -GridLayout3D.tileHeight / 2,
        GridLayout3D.tileHeight / 2
      ]) {
        final screen = camera.unprojectPosition(Vector3(x: x, y: y, z: z));
        _check(
            screen.x > 5 &&
                screen.x < viewport.x - 5 &&
                screen.y > 5 &&
                screen.y < viewport.y - 5,
            'Every board corner must remain within the viewport.');
      }
    }
  }
  final center = camera.unprojectPosition(Vector3());
  _check(
      (center.x - viewport.x / 2).abs() < 1 &&
          (center.y - viewport.y / 2).abs() < 1,
      'The board must be centered.');
}

Future<void> _captureRuntime(Node scene) async {
  await Future<void>.delayed(const Duration(seconds: 2));
  final startFrames = Engine.singleton.getFramesDrawn();
  final clock = Stopwatch()..start();
  await Future<void>.delayed(const Duration(seconds: 6));
  clock.stop();
  final frames = Engine.singleton.getFramesDrawn() - startFrames;
  _check(frames > 5, 'Real rendered frames must be observed.');
  final output = Directory(Platform.environment['BLACKSMITH_ISSUE15_OUTPUT']!);
  output.createSync(recursive: true);
  await RenderingServer.singleton.framePostDraw.asFuture(scene);
  final image = scene.getViewport()!.getTexture()!.getImage();
  _check(image != null && image.getWidth() == 1152 && image.getHeight() == 648,
      'Capture must come from the real 1152x648 Godot viewport.');
  _check(image!.savePng('${output.path}/grid.png') == GDError.ok,
      'Saving the actual renderer image must succeed.');
  final averageMs = clock.elapsedMicroseconds / frames / 1000;
  final rendering = RenderingServer.singleton;
  final result = {
    'godot': Platform.environment['BLACKSMITH_ISSUE15_GODOT_VERSION'],
    'adapter': rendering.getVideoAdapterName(),
    'graphics_api': rendering.getVideoAdapterApiVersion(),
    'viewport': {'width': image.getWidth(), 'height': image.getHeight()},
    'renderer': 'Compatibility',
    'frame_cap_fps': 60,
    'warmup_seconds': 2,
    'sample_seconds': 6,
    'rendered_frames': frames,
    'elapsed_sample_seconds': clock.elapsedMicroseconds / 1e6,
    'engine_reported_fps':
        Performance.singleton.getMonitor(PerformanceMonitor.timeFps),
    'average_fps': 1000 / averageMs,
    'average_frame_ms': averageMs,
    'note': 'Lightweight windowed check using native Godot frame counts; includes presentation. '
        'Not an uncapped benchmark or a measurement of the final visual target.',
  };
  File('${output.path}/runtime.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  GD.print(Variant('BLACKSMITH_ISSUE15_RUNTIME ${jsonEncode(result)}'));
}
