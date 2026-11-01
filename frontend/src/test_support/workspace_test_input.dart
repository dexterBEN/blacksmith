// Native GUI input shared by the isolated editor regression fixtures.
// ignore_for_file: avoid_relative_lib_imports
import 'package:godot_dart/godot_dart.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import '../lib/prototypes/isometric_3d/design_browser_3d.dart';
import '../lib/domain/bloc/design/design_cubit.dart';
import '../lib/domain/models/design_browser_state.dart';

/// Test callers know an ID for verification, but interact through name search
/// and visible browser rows, exactly as a user does (never an ID input field).
Future<void> selectDesignInBrowser(
    Node scene, DesignCubit cubit, String id) async {
  for (var i = 0;
      i < 150 && cubit.state.browser.status != DesignListStatus.ready;
      i++) {
    if (cubit.state.browser.status == DesignListStatus.failure) {
      throw StateError('Design list failed: ${cubit.state.browser.error}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final metadata = cubit.state.browser.entries
      .where((d) => d.id == id.toLowerCase())
      .toList();
  if (metadata.isEmpty) {
    throw StateError('Expected Design is absent from the backend list.');
  }
  final search = scene.getNodeT<LineEdit>(DesignBrowser3D.search)!;
  search
    ..setText(metadata.single.displayName)
    ..textChanged.emit(metadata.single.displayName);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  final index =
      cubit.state.browser.matches.indexWhere((d) => d.id == id.toLowerCase());
  final page = index ~/ DesignBrowserState.pageSize;
  while (cubit.state.browser.page < page) {
    await workspaceClick(
        scene,
        scene
            .getNodeT<Button>(DesignBrowser3D.next)!
            .getGlobalRect()
            .getCenter());
  }
  await workspaceClick(
      scene,
      scene
          .getNodeT<Button>(
              '${DesignBrowser3D.rows}/Row_${index % DesignBrowserState.pageSize}')!
          .getGlobalRect()
          .getCenter());
  if (cubit.state.openId != id.toLowerCase()) {
    throw StateError('Browser row selection was not applied.');
  }
}

Future<void> workspaceClick(Node scene, Vector2 point) async {
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
    await Future<void>.delayed(const Duration(milliseconds: 180));
  }
  // A wall-clock delay can expire before the next software-rendered frame.
  // Wait for the native track, so geometry-dependent clicks use drawn bounds.
  final animation = scene
      .getNodeT<AnimationPlayer>('${Workspace3D.speedDial}/AnimationPlayer')!;
  for (var i = 0; i < 60 && animation.isPlaying(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (animation.isPlaying()) {
    throw StateError('Speed Dial animation did not settle.');
  }
}

Future<void> openWorkspaceAction(Node scene, String action) async {
  if (scene.getNodeT<Control>(Workspace3D.resourceOverlay)!.isVisibleInTree()) {
    if (action == Workspace3D.libraryToggle) return;
    await dismissWorkspaceMenus(scene);
  }
  if (!scene.getNodeT<Control>(Workspace3D.speedActions)!.isVisibleInTree()) {
    await workspaceClick(
        scene,
        scene
            .getNodeT<Button>(Workspace3D.speedToggle)!
            .getGlobalRect()
            .getCenter());
  }
  await workspaceClick(
      scene, scene.getNodeT<Button>(action)!.getGlobalRect().getCenter());
}

Future<void> dismissWorkspaceMenus(Node scene) async {
  for (final pressed in [true, false]) {
    scene.getViewport()!.pushInput(
        InputEventKey()
          ..setKeycode(Key.escape)
          ..setPressed(pressed),
        inLocalCoords: true);
  }
  await Future<void>.delayed(const Duration(milliseconds: 180));
}

Future<void> confirmResourceChoice(Node scene) async {
  await workspaceClick(
      scene,
      scene
          .getNodeT<Button>(Workspace3D.resourceConfirm)!
          .getGlobalRect()
          .getCenter());
  for (var i = 0;
      i < 100 &&
          scene
              .getNodeT<Control>(Workspace3D.resourceOverlay)!
              .isVisibleInTree();
      i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (scene.getNodeT<Control>(Workspace3D.resourceOverlay)!.isVisibleInTree()) {
    throw StateError(
        'Resource confirmation did not complete: ${scene.getNodeT<Label>('${Workspace3D.sidebar}/Content/Feedback')!.getText()}');
  }
}
