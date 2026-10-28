// Match the production resolver's file-URI library identities.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';
import 'dart:convert';
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
import '../lib/prototypes/isometric_3d/workspace_layout.dart';
import 'isometric_3d_framing_checks.dart';

/// Real native containers/controls, actual window sizes, production BLoC/Cubit.
/// The caller injects fail-closed repositories; this suite never saves/deploys.
Future<void> checkWorkspace(Node scene, IsomapGridBloc grid, DesignCubit design,
    {required int Function() tileEvents,
    required int Function() placementEvents}) async {
  final window = scene.getTree()!.getRoot()!;
  final originalMode = window.getContentScaleMode();
  final originalSize = window.getContentScaleSize();
  final originalAspect = window.getContentScaleAspect();
  final originalWindow = window.getSize();
  final output = Platform.environment['BLACKSMITH_WORKSPACE_OUTPUT']!;
  final layout = GridLayout3D(rows: grid.state.rows, cols: grid.state.cols);
  final matrix = <Map<String, Object>>[];
  bool visible(String path) => scene.getNodeT<Control>(path)!.isVisibleInTree();
  Future<void> click(String path) =>
      _click(scene, scene.getNodeT<Control>(path)!.getGlobalRect().getCenter());
  Future<void> library() async {
    if (!visible(Workspace3D.sidebar)) {
      await click(Workspace3D.libraryToggle);
    }
  }

  Future<void> inspector() async {
    if (!visible(Workspace3D.inspector)) {
      await click(Workspace3D.inspectorToggle);
    }
  }

  Future<void> closeDocks() async {
    // Closing the winner at narrow sizes can reveal a previously requested dock.
    for (var i = 0; i < 4; i++) {
      if (visible(Workspace3D.sidebar)) {
        await click('${Workspace3D.sidebar}/Content/Heading/Close');
      } else if (visible(Workspace3D.inspector)) {
        await click('${Workspace3D.inspector}/Content/Heading/Close');
      } else {
        return;
      }
    }
    _check(!visible(Workspace3D.sidebar) && !visible(Workspace3D.inspector),
        'Both docks can be closed through their native controls.');
  }

  Future<void> resize(int width, int height) async {
    // GNOME clamps a decorated 1920x1080 client on a 1920x1080 desktop.
    // Use the actual native fullscreen mode for that matrix row, without
    // changing desktop resolution or pretending a scaled canvas is a window.
    final mode = width == 1920 && height == 1080
        ? WindowMode.fullscreen
        : WindowMode.windowed;
    if (window.getMode() != mode) {
      window.setMode(mode);
      await _settle(scene);
    }
    window
      ..setContentScaleMode(WindowContentScaleMode.viewport)
      ..setContentScaleSize(Vector2i.fromXY(0, 0));
    if (mode == WindowMode.windowed) {
      window.setSize(Vector2i.fromXY(width, height));
    }
    await _until(() =>
        window.getSize().x == width &&
        window.getSize().y == height &&
        scene.getViewport()!.getVisibleRect().size.x == width &&
        scene.getViewport()!.getVisibleRect().size.y == height);
    await _settle(scene);
    final actual = scene.getViewport()!.getVisibleRect().size;
    _check(
        actual.x == width && actual.y == height,
        'Native resize: requested=${width}x$height, window=${window.getSize().x}x${window.getSize().y}, '
        'viewport=${actual.x}x${actual.y}, content=${window.getContentScaleSize().x}x${window.getContentScaleSize().y}.');
    checkEditorFraming(scene);
  }

  await _settle(scene);
  _check(!visible(Workspace3D.sidebar) && !visible(Workspace3D.inspector),
      'Canvas-first startup has both optional docks closed.');
  await resize(1280, 720);
  await _capture(scene, '$output/dark_empty.png');
  await library();
  for (final kind in ResourceKind.values) {
    final button = _button(scene, Workspace3D.catalog, kind);
    _check(
        button.isDisabled() &&
            button.getButtonIcon() != null &&
            button.getText().isNotEmpty &&
            button.getFocusMode() == ControlFocusMode.focusNone,
        'The four labelled Library choices require a selected tile.');
    await _click(scene, button.getGlobalRect().getCenter());
  }
  _check(grid.state.selected == null && grid.state.tiles.isEmpty,
      'Disabled resource controls cannot select or place.');
  design.open();
  design.changeName('Docked workspace validation');
  await design.submit();
  await _settle(scene);
  final active = design.state.active;
  _check(active != null, 'Include an active fake Design without HTTP.');

  Future<void> select(GridPos position) async {
    final world = layout.worldPosition(position);
    final screen = Workspace3D.project(scene,
        (scene as Node3D).toGlobal(Vector3(x: world.x, y: .12, z: world.z)));
    final before = tileEvents();
    await _click(scene, screen);
    _check(grid.state.selected == position && tileEvents() == before + 1,
        'Picking after layout changes emits exactly one logical selection.');
  }

  Future<void> choose(String group, ResourceKind kind) async {
    if (group == Workspace3D.catalog) await library();
    final selected = grid.state.selected;
    final before = tileEvents();
    final placements = placementEvents();
    final button = _button(scene, group, kind);
    if (kind == ResourceKind.cloudStorage) {
      if (!button.isDisabled()) {
        await _click(scene, button.getGlobalRect().getCenter());
        _check(design.state.configurationDraft != null,
            'Cloud Storage retains its existing configuration entry point.');
        design.cancelResourceConfiguration();
        await _settle(scene);
      }
      // Explicit legacy local rendering fixture only; configured persistence is
      // validated independently with --deployment and its isolated real API.
      grid.add(const PlaceResource(ResourceKind.cloudStorage));
      await _settle(scene);
    } else {
      _check(!button.isDisabled(), 'A selected local tile enables placement.');
      await _click(scene, button.getGlobalRect().getCenter());
    }
    _check(
        grid.state.selected == selected &&
            grid.state.tiles[selected] == kind &&
            tileEvents() == before &&
            placementEvents() == placements + 1,
        'Each placement/replacement emits exactly once and preserves selection.');
    _check(
        _cube(scene, selected!).getSceneFilePath() ==
            resourceVisuals3D[kind]!.scenePath,
        'Reuse the supported resource cube.');
  }

  for (var i = 0; i < ResourceKind.values.length; i++) {
    final kind = ResourceKind.values[i];
    final next = ResourceKind.values[(i + 1) % ResourceKind.values.length];
    final position = GridPos(2, i);
    await select(position);
    await choose(Workspace3D.catalog, kind);
    final previous = _cube(scene, position).getInstanceId();
    await choose(Workspace3D.catalog, next);
    _check(!GD.isInstanceIdValid(previous),
        'Replacement frees the obsolete cube.');
    await choose(Workspace3D.catalog, kind);
  }

  // Default Godot keyboard activation survives relocation; no custom shortcut
  // or duplicate pressed binding is introduced by moving the existing buttons.
  await closeDocks();
  await select(const GridPos(3, 2));
  final beforeLibrary = grid.state;
  await library();
  _check(grid.state == beforeLibrary,
      'Opening the Library exposes placement tools without changing selection.');
  final keyboardChoice =
      _button(scene, Workspace3D.catalog, ResourceKind.computeEngine);
  keyboardChoice.grabFocus();
  await _settle(scene);
  _check(keyboardChoice.hasFocus(), 'Library choices retain keyboard focus.');
  final keyboardEvents = placementEvents();
  final selectionEvents = tileEvents();
  for (final pressed in [true, false]) {
    scene.getViewport()!.pushInput(
        InputEventKey()
          ..setKeycode(Key.enter)
          ..setPressed(pressed),
        inLocalCoords: true);
    await _settle(scene);
  }
  _check(
      placementEvents() == keyboardEvents + 1 &&
          tileEvents() == selectionEvents &&
          grid.state.tiles[const GridPos(3, 2)] == ResourceKind.computeEngine,
      'Enter activates the focused Library command exactly once.');
  keyboardChoice.releaseFocus();
  await click('${Workspace3D.sidebar}/Content/Heading/Close');

  // Opening Inspector reads the current selection, including changes made
  // while it was closed, rather than retaining the previously inspected tile.
  await inspector();
  _check(
      scene.getNodeT<Label>('${Workspace3D.details}/Kind')!.getText() ==
          'Compute Engine',
      'Inspector opens on the resource selected while closed.');
  await click('${Workspace3D.inspector}/Content/Heading/Close');
  await select(const GridPos(3, 3));
  await inspector();
  _check(
      scene.getNodeT<Label>('${Workspace3D.details}/Coordinates')!.getText() ==
              'Row 3 · Column 3' &&
          scene.getNodeT<Label>('${Workspace3D.details}/Kind')!.getText() ==
              'Empty tile' &&
          scene.getNodeT<Label>('${Workspace3D.details}/Identity')!.getText() ==
              '' &&
          scene
                  .getNodeT<Label>('${Workspace3D.details}/Deployment')!
                  .getText() ==
              '',
      'Reopened Inspector clears stale resource identity and deployment details.');
  grid.add(const ResetGridForNewDesign());
  await _settle(scene);
  _check(
      scene.getNodeT<Label>('${Workspace3D.details}/Coordinates')!.getText() ==
          'No tile selected',
      'Reset clears the Inspector selection context.');
  final corners = [
    GridPos(0, 0),
    GridPos(0, grid.state.cols - 1),
    GridPos(grid.state.rows - 1, 0),
    GridPos(grid.state.rows - 1, grid.state.cols - 1)
  ];
  for (var i = 0; i < corners.length; i++) {
    await select(corners[i]);
    await choose(Workspace3D.catalog, ResourceKind.values[i]);
  }
  final ids = {for (final p in corners) p: _cube(scene, p).getInstanceId()};

  for (final size in const [
    (960, 640),
    (1280, 720),
    (1600, 900),
    (1920, 1080)
  ]) {
    await resize(size.$1, size.$2);
    double? closedWidth;
    for (final requested in const [
      (false, false),
      (true, false),
      (false, true),
      (true, true)
    ]) {
      final before = grid.state;
      final events = tileEvents();
      await closeDocks();
      if (requested.$1) await library();
      if (requested.$2) await inspector();
      await _settle(scene);
      checkEditorFraming(scene);
      final left = visible(Workspace3D.sidebar),
          right = visible(Workspace3D.inspector);
      _check(
          left == (requested.$1 && !(requested.$2 && size.$1 == 960)) &&
              right == requested.$2,
          'Desktop docks are independent; the last requested Inspector wins at 960.');
      _check(
          grid.state == before &&
              tileEvents() == events &&
              design.state.active == active,
          'Panel transitions do not mutate the selected tile, placements or active Design.');
      final bounds = Workspace3D.canvasRect(scene);
      if (!requested.$1 && !requested.$2) {
        closedWidth = bounds.size.x;
      } else {
        _check(bounds.size.x < closedWidth!,
            'Opening docks reserves real canvas space.');
      }
      for (final action in [
        'NewDesign',
        'OpenDesign',
        'SaveDesign',
        'CopyDesignId'
      ]) {
        final button = scene
            .getNodeT<Button>('${Workspace3D.header}/Rows/Actions/$action')!;
        final rect = button.getGlobalRect();
        _check(
            button.isVisibleInTree() &&
                rect.position.x >= 0 &&
                rect.end.x <= size.$1,
            'Essential header actions remain reachable.');
      }
      for (final corner in corners) {
        await select(corner);
      }
      _check(corners.every((p) => _cube(scene, p).getInstanceId() == ids[p]),
          'Container changes never recreate resource nodes.');
      matrix.add({
        'width': size.$1,
        'height': size.$2,
        'libraryRequested': requested.$1,
        'inspectorRequested': requested.$2,
        'libraryVisible': left,
        'inspectorVisible': right,
        'windowMode': window.getMode().name,
        'canvasWidth': bounds.size.x,
        'canvasHeight': bounds.size.y,
        'result': 'PASS'
      });
      if ((size.$1 == 1280 || size.$1 == 1920) &&
          requested.$1 == requested.$2) {
        await _capture(scene,
            '$output/workspace_${size.$1}x${size.$2}_${requested.$1 ? "docked" : "closed"}.png');
      }
    }
  }

  // Real grip input and clamps; not direct layout/model mutation.
  await resize(1600, 900);
  await library();
  await inspector();
  final beforeDrag = grid.state;
  final leftWidth = scene.getNodeT<Control>(Workspace3D.sidebar)!.getSize().x;
  await _drag(scene, Workspace3D.libraryGrip, 60);
  final grown = scene.getNodeT<Control>(Workspace3D.sidebar)!.getSize().x;
  _check(grown > leftWidth + 40,
      'The native library grip changes reserved width.');
  // Stay inside the native client while dragging past the minimum boundary.
  await _drag(scene, Workspace3D.libraryGrip, -300);
  _check(
      (scene.getNodeT<Control>(Workspace3D.sidebar)!.getSize().x -
                  WorkspaceLayout.minimumLibraryWidth)
              .abs() <
          .1,
      'Library minimum: actual=${scene.getNodeT<Control>(Workspace3D.sidebar)!.getSize().x}, '
      'combinedMinimum=${scene.getNodeT<Control>(Workspace3D.sidebar)!.getCombinedMinimumSize().x}.');
  await _drag(scene, Workspace3D.inspectorGrip, -1000);
  _check(
      (scene.getNodeT<Control>(Workspace3D.inspector)!.getSize().x -
                  WorkspaceLayout.maximumPanelWidth)
              .abs() <
          .1,
      'Inspector width clamps at its maximum.');
  _check(grid.state == beforeDrag,
      'Grip input never selects or modifies a resource.');
  checkEditorFraming(scene);
  await resize(960, 640);
  _check(!visible(Workspace3D.sidebar) && visible(Workspace3D.inspector),
      'Narrow resize preserves the last-used dock.');
  await library();
  _check(visible(Workspace3D.sidebar) && !visible(Workspace3D.inspector),
      'The rail can switch the visible narrow dock.');
  await resize(1280, 720);
  _check(visible(Workspace3D.sidebar) && visible(Workspace3D.inspector),
      'Widening restores both requested docks.');

  await select(corners.first);
  _check(
      scene.getNodeT<Label>('${Workspace3D.details}/Kind')!.getText() ==
          'Cloud Storage',
      'Inspector derives the selected resource kind from the existing grid.');
  await click('${Workspace3D.details}/Configure');
  _check(
      design.state.configurationDraft != null &&
          !design.state.configurationDraft!.consent,
      'Inspector opens the original configuration form without deployment consent.');
  await click('DesignLayer/ConfigurationControls/Shade/Dialog/Cancel');
  final inspected = grid.state;
  await click('${Workspace3D.inspector}/Content/Heading/Close');
  _check(grid.state == inspected, 'Closing Inspector never deselects.');

  window.setMode(WindowMode.maximized);
  await _until(() => window.getMode() == WindowMode.maximized);
  await _settle(scene);
  checkEditorFraming(scene);
  window.setMode(WindowMode.windowed);
  await resize(1280, 720);
  checkEditorFraming(scene);
  _check(grid.state == inspected,
      'Maximize/restore preserves selection and placements.');
  await File('$output/workspace_matrix.json').writeAsString(jsonEncode(matrix));
  await closeDocks();
  grid.add(const ResetGridForNewDesign());
  window
    ..setContentScaleMode(originalMode)
    ..setContentScaleSize(originalSize)
    ..setContentScaleAspect(originalAspect)
    ..setSize(originalWindow);
  await _settle(scene);
  checkEditorFraming(scene);
  GD.print(Variant('BLACKSMITH_WORKSPACE_PASSED resources=4 entry_points=1 '
      'panel_states=4 desktop_sizes=4 minimum=960x640 minimum_canvas=480x320 '
      'native_resize=true grips=true maximize_restore=true selection_preserved=true '
      'footer_absent=true commands_once=true keyboard=true inspector_reopen=true'));
}

Button _button(Node scene, String group, ResourceKind kind) =>
    scene.getNodeT<Button>('$group/${resourceVisuals3D[kind]!.buttonName}')!;
Node3D _cube(Node scene, GridPos p) =>
    scene.getNodeT<Node3D>('ResourceRoot/Resource_${p.row}_${p.col}')!;
void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 150; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Timed out waiting for native workspace resize.');
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
      'Capture unmodified native Godot rendering.');
}

Future<void> _drag(Node scene, String grip, double dx) async {
  final viewport = scene.getViewport()!;
  final point = scene.getNodeT<Control>(grip)!.getGlobalRect().getCenter();
  viewport.pushInput(
      InputEventMouseButton()
        ..setPosition(point)
        ..setGlobalPosition(point)
        ..setButtonIndex(MouseButton.left)
        ..setPressed(true),
      inLocalCoords: true);
  await _settle(scene);
  final target = point + Vector2(x: dx, y: 0);
  viewport.pushInput(
      InputEventMouseMotion()
        ..setPosition(target)
        ..setGlobalPosition(target),
      inLocalCoords: true);
  await _settle(scene);
  viewport.pushInput(
      InputEventMouseButton()
        ..setPosition(target)
        ..setGlobalPosition(target)
        ..setButtonIndex(MouseButton.left)
        ..setPressed(false),
      inLocalCoords: true);
  await _settle(scene);
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
