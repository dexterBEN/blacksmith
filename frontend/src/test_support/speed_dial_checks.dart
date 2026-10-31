// Focused native input/layout regression; real BLoC, no backend or cloud.
// ignore_for_file: avoid_relative_lib_imports
import 'package:godot_dart/godot_dart.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import 'workspace_test_input.dart';
import 'isometric_3d_framing_checks.dart';

Future<void> checkSpeedDial(Node scene, IsomapGridBloc bloc,
    {required int Function() tileEvents,
    required bool capture,
    String? output}) async {
  final window = scene.getTree()!.getRoot()!;
  final originalSize = window.getSize();
  final originalScale = window.getContentScaleMode();
  final originalContent = window.getContentScaleSize();
  Control control(String path) => scene.getNodeT<Control>(path)!;
  Button button(String path) => scene.getNodeT<Button>(path)!;
  bool visible(String path) => control(path).isVisibleInTree();
  Future<void> click(String path) =>
      workspaceClick(scene, control(path).getGlobalRect().getCenter());
  Future<void> screenshot(String name) async {
    if (!capture || output == null) return;
    await RenderingServer.singleton.framePostDraw.asFuture(scene);
    _check(
        scene
                .getViewport()!
                .getTexture()!
                .getImage()!
                .savePng('$output/$name.png') ==
            GDError.ok,
        'Actual native UI capture.');
  }

  await dismissWorkspaceMenus(scene);
  _check(
      !scene.hasNode(NodePath.fromString('${Workspace3D.body}/NavigationRail')),
      'There is no navigation rail or reserved sidebar column.');
  for (final size in [(1152, 648), (960, 640)]) {
    window
      ..setContentScaleMode(WindowContentScaleMode.disabled)
      ..setSize(Vector2i.fromXY(size.$1, size.$2));
    await _until(() => scene.getViewport()!.getVisibleRect().size.x == size.$1);
    await _pause();
    await dismissWorkspaceMenus(scene);
    final canvas = Workspace3D.canvasRect(scene);
    _check((canvas.size.x - size.$1).abs() < 1,
        'The complete body width belongs to the render viewport.');
    final toggle = control(Workspace3D.speedToggle).getGlobalRect();
    _check(
        (toggle.position.x - canvas.position.x - 18).abs() < 1 &&
            (canvas.end.y - toggle.end.y - 18).abs() < 1,
        'Dial stays attached to the canvas bottom-left after real window resizing.');
    _check(
        button(Workspace3D.speedToggle).getText() == '+' &&
            !visible(Workspace3D.speedActions),
        'Collapsed state shows only the main plus button.');
    await screenshot('speed_dial_${size.$1}_collapsed');
    final before = bloc.state;
    final events = tileEvents();
    await click(Workspace3D.speedToggle);
    _check(
        visible(Workspace3D.speedActions) &&
            button(Workspace3D.speedToggle).getText() == '×',
        'Main toggle expands and changes glyph.');
    final resources = control(Workspace3D.libraryToggle).getGlobalRect();
    final inspect = control(Workspace3D.inspectorToggle).getGlobalRect();
    _check(
        resources.position.x == toggle.position.x &&
            inspect.position.x == toggle.position.x &&
            resources.end.y < inspect.position.y &&
            inspect.end.y < toggle.position.y &&
            resources.position.y > canvas.position.y,
        'Resources and Inspect expand in one upward-only column.');
    _check(button(Workspace3D.libraryToggle).getText() == 'Resources',
        'Visible plural Resources label.');
    _check(
        (Workspace3D.canvasRect(scene).size - canvas.size).length < 0.1 &&
            bloc.state == before &&
            tileEvents() == events,
        'Expanding the dial neither allocates viewport width nor changes selection.');
    await screenshot('speed_dial_${size.$1}_expanded');
    await click(Workspace3D.libraryToggle);
    _check(
        visible(Workspace3D.sidebar) &&
            !visible(Workspace3D.speedActions) &&
            bloc.state == before &&
            tileEvents() == events,
        'Resources opens existing content and preserves BLoC selection.');
    _check((Workspace3D.canvasRect(scene).size - canvas.size).length < 0.1,
        'Popup reserves no viewport space.');
    checkEditorFraming(scene);
    await screenshot('speed_dial_${size.$1}_resources');
    await dismissWorkspaceMenus(scene);
    _check(
        !visible(Workspace3D.sidebar) &&
            button(Workspace3D.speedToggle).hasFocus(),
        'Escape closes the popup and returns focus to the main control.');
    await openWorkspaceAction(scene, Workspace3D.inspectorToggle);
    _check(
        visible(Workspace3D.inspector) &&
            !visible(Workspace3D.sidebar) &&
            !visible(Workspace3D.speedActions),
        'Inspect opens the existing inspector as a mutually exclusive popover.');
    await click('${Workspace3D.inspector}/Content/Heading/Close');
    _check(bloc.state == before && tileEvents() == events,
        'Popup and close-button input never reaches the grid.');
    await click(Workspace3D.speedToggle);
    await dismissWorkspaceMenus(scene);
    _check(!visible(Workspace3D.speedActions), 'Escape closes the dial.');

    // Put the actual native toggle over a valid tile to detect click-through,
    // even though its normal bottom-left location can lie outside the board.
    final dial = control(Workspace3D.speedDial);
    final savedPosition = dial.getPosition();
    final cell = const GridLayout3D().worldPosition(const GridPos(3, 3));
    final target = Workspace3D.project(
        scene,
        scene.getNodeT<Node3D>('.')!.toGlobal(
            Vector3(x: cell.x, y: GridLayout3D.tileHeight / 2, z: cell.z)));
    dial.setPosition(savedPosition +
        target -
        control(Workspace3D.speedToggle).getGlobalRect().getCenter());
    await click(Workspace3D.speedToggle);
    _check(tileEvents() == events && bloc.state == before,
        'Toggle over a tile consumes its own pointer input.');
    await click(Workspace3D.libraryToggle);
    _check(tileEvents() == events && bloc.state == before,
        'Action over the grid never selects through the overlay.');
    final popup = control(Workspace3D.sidebar);
    final popupPosition = popup.getPosition();
    popup.setPosition(popupPosition +
        target -
        popup.getGlobalRect().position -
        Vector2(x: 2, y: 2));
    await workspaceClick(scene, target);
    _check(tileEvents() == events && bloc.state == before,
        'Opaque popup padding blocks the tile underneath without issuing a command.');
    popup.setPosition(popupPosition);
    await dismissWorkspaceMenus(scene);
    dial.setPosition(savedPosition);

    dial.setPosition(savedPosition +
        target -
        dial.getGlobalRect().position -
        Vector2(x: 21, y: 48));
    await click(Workspace3D.speedToggle);
    final beforeGap = tileEvents();
    await workspaceClick(scene, target);
    _check(
        bloc.state.selected == const GridPos(3, 3) &&
            tileEvents() == beforeGap + 1,
        'The transparent gap between action rows does not block the grid.');
    dial.setPosition(savedPosition);

    // Transparent overlay areas still select normally and dismiss the dial.
    final point = const GridLayout3D().worldPosition(const GridPos(2, 2));
    final screen = Workspace3D.project(
        scene,
        scene.getNodeT<Node3D>('.')!.toGlobal(
            Vector3(x: point.x, y: GridLayout3D.tileHeight / 2, z: point.z)));
    await click(Workspace3D.speedToggle);
    final beforeOutside = tileEvents();
    await workspaceClick(scene, screen);
    _check(
        !visible(Workspace3D.speedActions) &&
            bloc.state.selected == const GridPos(2, 2) &&
            tileEvents() == beforeOutside + 1,
        'An outside grid click dismisses the menu and selects exactly once.');
    checkEditorFraming(scene);
  }
  window
    ..setContentScaleMode(originalScale)
    ..setContentScaleSize(originalContent)
    ..setSize(originalSize);
  await _pause();
  GD.print(Variant(
      'BLACKSMITH_ISSUE73_SPEED_DIAL_PASSED sizes=2 full_width=true upward=true escape=true outside=true no_clickthrough=true selection_preserved=true'));
}

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> _pause() =>
    Future<void>.delayed(const Duration(milliseconds: 250));
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await _pause();
  }
  throw StateError('Timed out waiting for native Speed Dial layout.');
}
