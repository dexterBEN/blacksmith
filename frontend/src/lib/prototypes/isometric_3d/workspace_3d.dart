import 'package:godot_dart/godot_dart.dart';
import 'resource_visuals_3d.dart';

/// Native workspace geometry and UI appearance only. No editing/business state.
class Workspace3D {
  Workspace3D(this._owner) {
    // Keep the established world and all its nodes. A separate camera viewport
    // renders it only inside the container, never underneath the UI panels.
    viewport(_owner).setWorld_3d(_owner.getViewport()!.findWorld_3d());
    _appearance = _owner.getNodeT<Button>('$header/Rows/Actions/Appearance')!;
    _appearance.pressed.connect(_owner, () {
      if (!_active || _blocked) return;
      _light = !_light;
      _applyAppearance();
    });
    _applyAppearance();
    resize();
  }

  static const root = 'WorkspaceLayer/Workspace';
  static const header = '$root/Margin/Layout/Header';
  static const sidebar = '$root/Margin/Layout/Body/Sidebar';
  static const catalog = '$sidebar/Content/Scroll/Choices';
  static const canvas = '$root/Margin/Layout/Body/Center/Canvas';
  static const quick = '$root/Margin/Layout/Body/Center/QuickPlacement';
  static const choices = '$quick/Content/Choices';
  static const cameraPath = '$canvas/WorldViewport/Camera3D';
  // Session-only presentation preference, preserved on scene reload.
  static bool _light = false;
  final Node _owner;
  late final Button _appearance;
  final _themes = <bool, Theme>{};
  bool _active = true;
  bool _blocked = false;

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

  void setBlocked(bool blocked) {
    _blocked = blocked;
    _appearance.setDisabled(blocked);
  }

  void resize() {
    final size = _owner.getViewport()!.getVisibleRect().size;
    final narrow = size.x < 760;
    _owner
        .getNodeT<PanelContainer>(sidebar)!
        .setCustomMinimumSize(Vector2(x: narrow ? 164 : 236, y: 0));
    for (final visual in resourceVisuals3D.values) {
      _owner.getNodeT<Button>('$catalog/${visual.buttonName}')!.setText(
          narrow ? visual.label.replaceFirst(' ', '\n') : visual.label);
    }
  }

  void _applyAppearance() {
    final theme = _themes.putIfAbsent(
        _light,
        () => ResourceLoader.singleton.load('res://scenes/isometric_3d/'
            'workspace_${_light ? "light" : "dark"}.tres')! as Theme);
    _owner.getNodeT<Control>(root)!.setTheme(theme);
    _owner.getNodeT<Control>('DesignLayer/DesignControls')!.setTheme(theme);
    _owner.getNodeT<ColorRect>('$root/Background')!.setColor(_light
        ? Color.fromRGB(0.87, 0.91, 0.96)
        : Color.fromRGB(0.018, 0.028, 0.05));
    _appearance.setText(_light ? 'Dark UI' : 'Light UI');
  }

  void dispose() {
    _active = false;
    _themes.clear();
  }
}
