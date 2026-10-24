import 'package:godot_dart/godot_dart.dart';

/// Native desktop workspace geometry. No editing/business state.
class Workspace3D {
  static const minimumWidth = 960;
  static const minimumHeight = 640;

  static void attach(Node scene) {
    // Keep the established world and all its nodes. A separate camera viewport
    // renders it only inside the container, never underneath the UI panels.
    viewport(scene).setWorld_3d(scene.getViewport()!.findWorld_3d());
  }

  static const root = 'WorkspaceLayer/Workspace';
  static const header = '$root/Margin/Layout/Header';
  static const sidebar = '$root/Margin/Layout/Body/Sidebar';
  static const catalog = '$sidebar/Content/Scroll/Choices';
  static const canvas = '$root/Margin/Layout/Body/Center/Canvas';
  static const quick = '$root/Margin/Layout/Body/Center/QuickPlacement';
  static const choices = '$quick/Content/Choices';
  static const cameraPath = '$canvas/WorldViewport/Camera3D';

  static SubViewport viewport(Node scene) =>
      scene.getNodeT<SubViewport>('$canvas/WorldViewport')!;
  static Camera3D camera(Node scene) => scene.getNodeT<Camera3D>(cameraPath)!;
  static Rect2 canvasRect(Node scene) =>
      scene.getNodeT<SubViewportContainer>(canvas)!.getGlobalRect();

  /// Inverse of the canvas-local mapping used by the input route. Useful also
  /// for overlays/tests that project a world position into the main UI viewport.
  static Vector2 project(Node scene, Vector3 world) {
    final local = camera(scene).unprojectPosition(world);
    final rect = canvasRect(scene);
    final size = viewport(scene).getVisibleRect().size;
    return rect.position +
        Vector2(
            x: local.x * rect.size.x / size.x,
            y: local.y * rect.size.y / size.y);
  }
}
