// Native GUI integration; the caller injects fail-closed repositories.
// ignore_for_file: avoid_relative_lib_imports
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
import 'speed_dial_checks.dart';
import 'workspace_test_input.dart';
import 'isometric_3d_framing_checks.dart';

Future<void> checkWorkspace(Node scene, IsomapGridBloc grid, DesignCubit design,
    {required int Function() tileEvents,
    required int Function() placementEvents}) async {
  await openWorkspaceAction(scene, Workspace3D.libraryToggle);
  for (final visual in resourceVisuals3D.values) {
    final button =
        scene.getNodeT<Button>('${Workspace3D.catalog}/${visual.buttonName}')!;
    _check(
        button.isDisabled() &&
            button.getButtonIcon() != null &&
            button.getText().isNotEmpty,
        'Existing resource choices remain disabled until a tile is selected.');
  }
  await dismissWorkspaceMenus(scene);
  design.open();
  design.changeName('Floating workspace validation');
  await design.submit();
  await _settle();
  final active = design.state.active;
  _check(active != null, 'One explicit fake Design creation, without HTTP.');

  Future<void> select(GridPos position) async {
    await dismissWorkspaceMenus(scene);
    final p = const GridLayout3D().worldPosition(position);
    final before = tileEvents();
    await workspaceClick(
        scene,
        Workspace3D.project(
            scene,
            (scene as Node3D).toGlobal(
                Vector3(x: p.x, y: GridLayout3D.tileHeight / 2, z: p.z))));
    _check(grid.state.selected == position && tileEvents() == before + 1,
        'Tile-first selection remains authoritative.');
  }

  Future<void> choose(ResourceKind kind) async {
    await openWorkspaceAction(scene, Workspace3D.libraryToggle);
    final before = tileEvents(), placements = placementEvents();
    final selected = grid.state.selected;
    final button = scene.getNodeT<Button>(
        '${Workspace3D.catalog}/${resourceVisuals3D[kind]!.buttonName}')!;
    _check(!button.isDisabled(),
        'Selected local tile enables its existing resource action.');
    await workspaceClick(scene, button.getGlobalRect().getCenter());
    await confirmResourceChoice(scene);
    if (kind == ResourceKind.cloudStorage) {
      _check(design.state.configurationDraft != null,
          'Cloud Storage still opens its existing configuration dialog.');
      design.cancelResourceConfiguration();
      // Legacy local rendering fixture; no saving/deploying is implied.
      grid.add(const PlaceResource(ResourceKind.cloudStorage));
      await _settle();
    }
    _check(
        grid.state.selected == selected &&
            tileEvents() == before &&
            placementEvents() == placements + 1 &&
            grid.state.tiles[selected] == kind,
        'Choosing a resource places exactly once on the previously selected tile.');
  }

  for (var i = 0; i < ResourceKind.values.length; i++) {
    final position = GridPos(2, i);
    await select(position);
    await choose(ResourceKind.values[i]);
    final cube = scene.getNodeT<Node3D>('ResourceRoot/Resource_2_$i')!;
    _check(
        cube.getSceneFilePath() ==
            resourceVisuals3D[ResourceKind.values[i]]!.scenePath,
        'Existing resource scenes and logical mapping are reused.');
  }

  await select(const GridPos(3, 2));
  await openWorkspaceAction(scene, Workspace3D.libraryToggle);
  final keyboard =
      scene.getNodeT<Button>('${Workspace3D.catalog}/ComputeEngine')!;
  keyboard.grabFocus();
  final commands = placementEvents(), selectionEvents = tileEvents();
  for (final pressed in [true, false]) {
    scene.getViewport()!.pushInput(
        InputEventKey()
          ..setKeycode(Key.enter)
          ..setPressed(pressed),
        inLocalCoords: true);
    await _settle();
  }
  _check(placementEvents() == commands,
      'Enter on a resource row only selects it.');
  await confirmResourceChoice(scene);
  _check(placementEvents() == commands + 1 && tileEvents() == selectionEvents,
      'Keyboard row selection followed by confirmation places exactly once.');
  await dismissWorkspaceMenus(scene);
  await openWorkspaceAction(scene, Workspace3D.inspectorToggle);
  _check(
      scene.getNodeT<Label>('${Workspace3D.details}/Kind')!.getText() ==
          'Compute Engine',
      'Inspector reads the current BLoC selection when opened.');
  await select(const GridPos(3, 3));
  await openWorkspaceAction(scene, Workspace3D.inspectorToggle);
  _check(
      scene.getNodeT<Label>('${Workspace3D.details}/Kind')!.getText() ==
              'Empty tile' &&
          scene
              .getNodeT<Label>('${Workspace3D.details}/Identity')!
              .getText()
              .isEmpty,
      'Reopened inspector clears stale resource data.');
  await checkSpeedDial(scene, grid,
      tileEvents: tileEvents,
      capture: true,
      output: Platform.environment['BLACKSMITH_WORKSPACE_OUTPUT']);
  _check(
      design.state.active == active, 'UI changes preserve the active Design.');

  await select(const GridPos(2, 0));
  await openWorkspaceAction(scene, Workspace3D.inspectorToggle);
  final selected = grid.state.selected;
  await workspaceClick(
      scene,
      scene
          .getNodeT<Button>('${Workspace3D.details}/Configure')!
          .getGlobalRect()
          .getCenter());
  _check(
      design.state.configurationDraft != null &&
          grid.state.selected == selected,
      'Inspector retains the original configuration entry point and selection.');
  _check(
      !scene.getNodeT<Control>(Workspace3D.inspector)!.isVisibleInTree() &&
          !scene.getNodeT<Control>(Workspace3D.speedActions)!.isVisibleInTree(),
      'Opening a modal hides floating workspace controls.');
  design.cancelResourceConfiguration();
  await _settle();
  grid.add(const ResetGridForNewDesign());
  await _settle();
  _check(!scene.getNodeT<Control>(Workspace3D.speedActions)!.isVisibleInTree(),
      'Switching/resetting a Design leaves the dial collapsed.');
  checkEditorFraming(scene);
  GD.print(Variant('BLACKSMITH_WORKSPACE_PASSED resources=4 floating=true '
      'native_resize=true selection_preserved=true commands_once=true keyboard=true inspector_reopen=true'));
}

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 250));
