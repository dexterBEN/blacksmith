// Native GUI input shared by the isolated editor regression fixtures.
// ignore_for_file: avoid_relative_lib_imports
import 'package:godot_dart/godot_dart.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';

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
