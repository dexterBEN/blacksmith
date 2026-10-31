// Focused real Godot UI checks; the caller owns a fail-closed BLoC fixture.
// ignore_for_file: avoid_relative_lib_imports
import 'package:godot_dart/godot_dart.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_event.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/resource_kind.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import 'workspace_test_input.dart';

Future<void> checkResourceModal(Node scene, IsomapGridBloc bloc,
    {required int Function() tileEvents,
    required int Function() placements,
    required void Function(IsomapGridState) restore,
    required bool capture,
    required String output}) async {
  final window = scene.getTree()!.getRoot()!;
  final oldSize = window.getSize(), oldContent = window.getContentScaleSize();
  final oldScale = window.getContentScaleMode();
  Control c(String path) => scene.getNodeT<Control>(path)!;
  Button b(String path) => scene.getNodeT<Button>(path)!;
  bool visible() => c(Workspace3D.resourceOverlay).isVisibleInTree();
  Future<void> click(String path) =>
      workspaceClick(scene, c(path).getGlobalRect().getCenter());
  Future<void> open() => openWorkspaceAction(scene, Workspace3D.libraryToggle);
  Future<void> snap(String name) async {
    if (!capture) return;
    await RenderingServer.singleton.framePostDraw.asFuture(scene);
    await RenderingServer.singleton.framePostDraw.asFuture(scene);
    _check(
        scene
                .getViewport()!
                .getTexture()!
                .getImage()!
                .savePng('$output/$name.png') ==
            GDError.ok,
        'Native screenshot.');
  }

  Vector2 project(GridPos pos) {
    final p = const GridLayout3D().worldPosition(pos);
    return Workspace3D.project(
        scene,
        scene
            .getNodeT<Node3D>('.')!
            .toGlobal(Vector3(x: p.x, y: GridLayout3D.tileHeight / 2, z: p.z)));
  }

  restore(IsomapGridState.initial());
  await _pause();
  await open();
  _check(
      b(Workspace3D.resourceConfirm).isDisabled() &&
          scene
              .getNodeT<Label>('${Workspace3D.sidebar}/Content/Guidance')!
              .getText()
              .contains('Select a tile'),
      'No target means clear guidance and no placement.');
  await click(Workspace3D.resourceCancel);
  const cells = [GridPos(3, 1), GridPos(1, 2), GridPos(2, 4), GridPos(4, 3)];
  for (var i = 0; i < 4; i++) {
    bloc.add(TileClicked(cells[i]));
    bloc.add(PlaceResource(ResourceKind.values[i]));
    await _pause();
  }
  const target = GridPos(4, 4);
  for (final size in [(1152, 648), (960, 640)]) {
    window
      ..setContentScaleMode(WindowContentScaleMode.disabled)
      ..setSize(Vector2i.fromXY(size.$1, size.$2));
    await _until(() => scene.getViewport()!.getVisibleRect().size.x == size.$1);
    await _pause();
    await workspaceClick(scene, project(target));
    _check(bloc.state.selected == target,
        'Select the tile before opening Resources.');
    final before = bloc.state,
        selections = tileEvents(),
        commands = placements();
    final canvas = Workspace3D.canvasRect(scene),
        camera = Workspace3D.camera(scene);
    final cameraSize = camera.getSize(), offset = camera.getVOffset();
    await open();
    final dialog = c(Workspace3D.sidebar).getGlobalRect();
    _check(
        (dialog.getCenter() - canvas.getCenter()).length < 1 &&
            dialog.position.x >= canvas.position.x &&
            dialog.end.x <= canvas.end.x &&
            dialog.position.y >= canvas.position.y &&
            dialog.end.y <= canvas.end.y,
        'Dialog is centered in usable workspace and fits at each native size.');
    _check(
        (Workspace3D.canvasRect(scene).size - canvas.size).length < .1 &&
            (camera.getSize() - cameraSize).abs() < 1e-5 &&
            (camera.getVOffset() - offset).abs() < 1e-5,
        'Modal reserves no viewport space and never reframes the camera.');
    _check(
        !c(Workspace3D.speedActions).isVisibleInTree() &&
            b(Workspace3D.speedToggle).isDisabled(),
        'Speed Dial is collapsed and inactive behind the scrim.');
    _check(
        scene
                .getNodeT<Label>('${Workspace3D.sidebar}/Content/Guidance')!
                .getText() ==
            'Selected tile: (4, 4)',
        'Footer identifies the frozen target.');
    _check(b(Workspace3D.resourceConfirm).isDisabled(),
        'A row must be chosen first.');
    await snap('resources_${size.$1}_initial');
    _check(b('${Workspace3D.catalog}/CloudStorage').isDisabled(),
        'Existing no-active-Design constraint is retained.');
    await click('${Workspace3D.catalog}/ComputeEngine');
    _check(
        bloc.state == before &&
            placements() == commands &&
            tileEvents() == selections,
        'A row click only highlights a UI draft.');
    await click('${Workspace3D.catalog}/CloudVpn');
    _check(
        !b('${Workspace3D.catalog}/ComputeEngine').isPressed() &&
            b('${Workspace3D.catalog}/CloudVpn').isPressed(),
        'Only one resource row is selected.');
    await click('${Workspace3D.catalog}/ComputeEngine');
    _check(!b(Workspace3D.resourceConfirm).isDisabled(),
        'Eligible choice enables explicit confirmation.');
    await snap('resources_${size.$1}_selected');
    final backdrop = project(const GridPos(5, 0));
    _check(!dialog.hasPoint(backdrop),
        'Backdrop regression must target an actual outside tile.');
    await workspaceClick(scene, backdrop);
    await click('${Workspace3D.header}/Rows/Actions/NewDesign');
    _check(
        visible() &&
            bloc.state == before &&
            tileEvents() == selections &&
            placements() == commands,
        'Backdrop keeps the modal open and blocks grid and toolbar clicks.');
    for (var i = 0; i < 12; i++) {
      for (final pressed in [true, false]) {
        scene.getViewport()!.pushInput(
            InputEventKey()
              ..setKeycode(Key.tab)
              ..setPressed(pressed),
            inLocalCoords: true);
      }
      await _pause();
      final focus = scene.getViewport()!.guiGetFocusOwner();
      _check(focus != null && c(Workspace3D.sidebar).isAncestorOf(focus),
          'Tab focus stays in the modal.');
    }
    for (final close in [
      Workspace3D.resourceCancel,
      '${Workspace3D.sidebar}/Content/Heading/Close',
      'escape'
    ]) {
      if (!visible()) await open();
      if (close == 'escape') {
        await dismissWorkspaceMenus(scene);
      } else {
        await click(close);
      }
      _check(
          !visible() &&
              bloc.state == before &&
              placements() == commands &&
              tileEvents() == selections,
          'Cancel, close and Escape have no placement/selection side effects.');
      _check(b(Workspace3D.speedToggle).hasFocus(),
          'Modal close restores focus to its trigger.');
    }
    await open();
    _check(b(Workspace3D.resourceConfirm).isDisabled(),
        'Reopening clears the prior draft.');
    await click('${Workspace3D.catalog}/ComputeEngine');
    await confirmResourceChoice(scene);
    _check(
        !visible() &&
            bloc.state.selected == target &&
            bloc.state.tiles[target] == ResourceKind.computeEngine &&
            placements() == commands + 1 &&
            tileEvents() == selections,
        'Confirmation places exactly once using the existing path on the frozen tile.');
    await openWorkspaceAction(scene, Workspace3D.inspectorToggle);
    _check(
        scene.getNodeT<Label>('${Workspace3D.details}/Kind')!.getText() ==
            'Compute Engine',
        'Existing inspector still reads the placed resource.');
    await dismissWorkspaceMenus(scene);
    // An external selection reset invalidates, rather than retargeting, an open draft.
    await open();
    await click('${Workspace3D.catalog}/ComputeEngine');
    final snapshot = bloc.state;
    restore(IsomapGridState.initial());
    await _pause();
    _check(
        visible() &&
            b(Workspace3D.resourceConfirm).isDisabled() &&
            scene
                .getNodeT<Label>('${Workspace3D.sidebar}/Content/Feedback')!
                .getText()
                .contains('selected tile changed'),
        'Invalidated target stays visible with feedback and cannot dispatch.');
    await _pause();
    final feedback =
        scene.getNodeT<Label>('${Workspace3D.sidebar}/Content/Feedback')!;
    await _until(
        () => feedback.isVisibleInTree() && feedback.getSize().y >= 40);
    _check(feedback.isVisibleInTree() && feedback.getSize().y >= 40,
        'Validation feedback occupies readable space rather than a zero-height label.');
    await snap('resources_${size.$1}_invalid');
    await click(Workspace3D.resourceCancel);
    restore(snapshot);
    await _pause();
    // Return to an empty target for the next native-size confirmation.
    restore(
        snapshot.copyWith(resources: {...snapshot.resources}..remove(target)));
    await _pause();
  }
  window
    ..setContentScaleMode(oldScale)
    ..setContentScaleSize(oldContent)
    ..setSize(oldSize);
  await _pause();
  GD.print(Variant(
      'BLACKSMITH_ISSUE75_MODAL_PASSED sizes=2 centered=true scrim=true choice_only=true confirmation=true cancel=true escape=true focus_trap=true invalidation=true inspect=true'));
}

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> _pause() =>
    Future<void>.delayed(const Duration(milliseconds: 200));
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await _pause();
  }
  throw StateError('Timed out waiting for Resources modal layout.');
}
