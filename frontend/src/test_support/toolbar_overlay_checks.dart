// Native window geometry and input regression. No backend/cloud dependencies.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:math' as math;
import 'package:godot_dart/godot_dart.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import 'isometric_3d_framing_checks.dart';
import 'workspace_test_input.dart';

Future<void> checkToolbarOverlay(Node scene, IsomapGridBloc bloc,
    {required int Function() tileEvents,
    required bool capture,
    required String output}) async {
  final window = scene.getTree()!.getRoot()!;
  final oldSize = window.getSize(), oldContent = window.getContentScaleSize();
  final oldScale = window.getContentScaleMode();
  Control control(String path) => scene.getNodeT<Control>(path)!;
  final header = control(Workspace3D.header);
  final status = scene.getNodeT<Label>(Workspace3D.status)!;
  final tint = header
      .getIndexed(NodePath.fromString('theme_override_styles/panel:bg_color'))
      .cast<Color>();
  _check(tint.a > 0 && tint.a < 1,
      'The toolbar tint is translucent rather than an opaque band.');
  final fullStatus = status.getText(), tooltip = status.getTooltipText();
  for (final size in [(1152, 648), (960, 640), (1600, 900)]) {
    window
      ..setContentScaleMode(WindowContentScaleMode.disabled)
      ..setContentScaleSize(Vector2i.fromXY(0, 0))
      ..setSize(Vector2i.fromXY(size.$1, size.$2));
    await _until(() =>
        scene.getViewport()!.getVisibleRect().size.x == size.$1 &&
        scene.getViewport()!.getVisibleRect().size.y == size.$2);
    await _pause();
    await dismissWorkspaceMenus(scene);
    checkEditorFraming(scene);
    final canvas = Workspace3D.canvasRect(scene);
    _check(
        canvas.position.length < .1 &&
            (canvas.size -
                        Vector2(x: size.$1.toDouble(), y: size.$2.toDouble()))
                    .length <
                .1,
        'Background and real 3D viewport reach every window edge.');
    void checkRow() {
      final bar = header.getGlobalRect();
      var end = 0.0;
      for (final path in [
        '${Workspace3D.header}/Rows/Actions/Brand',
        ...Workspace3D.toolbarButtons,
        Workspace3D.status
      ]) {
        final rect = control(path).getGlobalRect();
        _check(
            rect.position.x >= end &&
                rect.end.x <= bar.end.x &&
                (rect.getCenter().y - bar.getCenter().y).abs() < 1,
            'Brand, actions and right-aligned status share a row without overlap.');
        end = rect.end.x;
      }
      _check(bar.position.length < .1 && bar.size.y <= 64,
          'The compact toolbar is anchored to the window top.');
    }

    checkRow();
    // Observe the actual projected envelope, not a second camera-fit formula.
    const grid = GridLayout3D();
    final points = [
      for (final x in [-grid.width / 2, grid.width / 2])
        for (final z in [-grid.depth / 2, grid.depth / 2])
          for (final y in [-.12, .80])
            Workspace3D.project(
                scene, (scene as Node3D).toGlobal(Vector3(x: x, y: y, z: z)))
    ];
    final xs = points.map((p) => p.x), ys = points.map((p) => p.y);
    final center = Vector2(
        x: (xs.reduce(math.min) + xs.reduce(math.max)) / 2,
        y: (ys.reduce(math.min) + ys.reduce(math.max)) / 2);
    _check((center - canvas.getCenter()).length < 1,
        'The board/cube envelope stays centered on the entire window after resize.');

    // Long status must never grow the toolbar or squeeze the action buttons.
    status
      ..setText(
          'Long Design name ${List.filled(20, 'with details').join(' ')} · Local placements only')
      ..setTooltipText('Long status presentation check');
    await _pause();
    checkRow();
    _check(
        status.getIndexed(NodePath.fromString('clip_text')).cast<bool>() &&
            status.getTooltipText().isNotEmpty,
        'Secondary status elides within its allocation and retains a tooltip.');
    status
      ..setText(fullStatus)
      ..setTooltipText(tooltip);
    await _pause();
    if (capture) {
      await RenderingServer.singleton.framePostDraw.asFuture(scene);
      _check(
          scene
                  .getViewport()!
                  .getTexture()!
                  .getImage()!
                  .savePng('$output/toolbar_${size.$1}_workspace.png') ==
              GDError.ok,
          'Save the actual native toolbar over the full-window background.');
    }

    final camera = Workspace3D.camera(scene);
    final zoom = camera.getSize(), offset = camera.getVOffset();
    const cell = GridPos(2, 2);
    final world = grid.worldPosition(cell);
    final target = Workspace3D.project(scene,
        (scene as Node3D).toGlobal(Vector3(x: world.x, y: .12, z: world.z)));
    final original = header.getPosition();
    // Put real decorative regions over a real pickable tile. This catches
    // accidental blocking even where the normal bar lies beyond the board.
    header.setPosition(original +
        target -
        header.getGlobalRect().position -
        Vector2(x: 8, y: 4));
    var events = tileEvents();
    await workspaceClick(scene, target);
    _check(bloc.state.selected == cell && tileEvents() == events + 1,
        'Toolbar padding passes pointer input to the underlying tile.');
    header.setPosition(original);
    header.setPosition(original + target - status.getGlobalRect().getCenter());
    events = tileEvents();
    await workspaceClick(scene, target);
    _check(tileEvents() == events + 1,
        'Non-interactive status passes through input while supporting its tooltip.');
    header.setPosition(original);
    for (final path in Workspace3D.toolbarButtons) {
      header.setPosition(
          original + target - control(path).getGlobalRect().getCenter());
      events = tileEvents();
      await workspaceClick(scene, target);
      _check(tileEvents() == events,
          'Every toolbar button, including disabled actions, blocks tile picking.');
      header.setPosition(original);
    }
    _check(
        (camera.getSize() - zoom).abs() < 1e-5 &&
            (camera.getVOffset() - offset).abs() < 1e-5,
        'Overlay interactions never move or reframe the camera.');
  }
  window
    ..setContentScaleMode(oldScale)
    ..setContentScaleSize(oldContent)
    ..setSize(oldSize);
  await _pause();
  GD.print(Variant('BLACKSMITH_ISSUE77_TOOLBAR_PASSED sizes=3 full_window=true '
      'centered=true translucent=true single_row=true status_fallback=true passthrough=true buttons_block=true'));
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
  throw StateError('Timed out waiting for the native toolbar layout.');
}
