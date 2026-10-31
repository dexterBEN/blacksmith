import 'package:godot_dart/godot_dart.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../../domain/models/resource_kind.dart';
import 'resource_visuals_3d.dart';
import 'workspace_layout.dart';

/// Native desktop workspace geometry. No editing/business state.
class Workspace3D {
  Workspace3D(this._scene, {required void Function() configureStorage}) {
    _button(speedToggle).pressed.connect(_scene, () {
      _closePanels(focusMain: false);
      _setDial(!_dialOpen);
    });
    _button(libraryToggle)
        .pressed
        .connect(_scene, () => _request(WorkspacePanel.library, true));
    _button(inspectorToggle)
        .pressed
        .connect(_scene, () => _request(WorkspacePanel.inspector, true));
    _button('$sidebar/Content/Heading/Close')
        .pressed
        .connect(_scene, () => _request(WorkspacePanel.library, false));
    _button('$inspector/Content/Heading/Close')
        .pressed
        .connect(_scene, () => _request(WorkspacePanel.inspector, false));
    _button('$details/Configure').pressed.connect(_scene, configureStorage);
    _scene
        .getTree()!
        .getRoot()!
        .focusExited
        .connect(_scene, () => _setDial(false));
    _control(center).resized.connect(_scene, resize);
    resize();
  }

  final Node _scene;
  final layout = WorkspaceLayout();
  bool _dialOpen = false;
  bool _blocked = false;
  bool _hadSelection = false;
  static const minimumWidth = WorkspaceLayout.minimumWindowWidth;
  static const minimumHeight = WorkspaceLayout.minimumWindowHeight;

  static void attach(Node scene) {
    // Keep the established world and all its nodes. A separate camera viewport
    // renders it only inside the container, never underneath the UI panels.
    viewport(scene).setWorld_3d(scene.getViewport()!.findWorld_3d());
  }

  static const root = 'WorkspaceLayer/Workspace';
  static const header = '$root/Margin/Layout/Header';
  static const body = '$root/Margin/Layout/Body';
  static const center = '$body/Center';
  static const speedDial = '$center/SpeedDial';
  static const speedToggle = '$speedDial/Toggle';
  static const speedActions = '$speedDial/Actions';
  static const libraryToggle = '$speedActions/LibraryToggle';
  static const inspectorToggle = '$speedActions/InspectorToggle';
  static const sidebar = '$center/Sidebar';
  static const inspector = '$center/Inspector';
  static const details = '$inspector/Content/Scroll/Details';
  static const catalog = '$sidebar/Content/Scroll/Choices';
  static const canvas = '$center/Canvas';
  static const cameraPath = '$canvas/WorldViewport/Camera3D';

  static SubViewport viewport(Node scene) =>
      scene.getNodeT<SubViewport>('$canvas/WorldViewport')!;
  static Camera3D camera(Node scene) => scene.getNodeT<Camera3D>(cameraPath)!;
  static Rect2 canvasRect(Node scene) =>
      scene.getNodeT<SubViewportContainer>(canvas)!.getGlobalRect();

  Control _control(String path) => _scene.getNodeT<Control>(path)!;
  Button _button(String path) => _scene.getNodeT<Button>(path)!;

  void _setDial(bool open, {bool focusMain = false}) {
    _dialOpen = open && !_blocked;
    _control(speedActions).setVisible(_dialOpen);
    _button(speedToggle)
      ..setText(_dialOpen ? '×' : '+')
      ..setTooltipText(
          _dialOpen ? 'Close workspace actions' : 'Open workspace actions');
    final animation =
        _scene.getNodeT<AnimationPlayer>('$speedDial/AnimationPlayer')!;
    if (_dialOpen) {
      animation.play(name: 'expand');
    } else {
      animation.stop();
    }
    if (focusMain && !_blocked) _button(speedToggle).grabFocus();
  }

  void _closePanels({bool focusMain = false}) {
    layout.request(WorkspacePanel.library, false);
    layout.request(WorkspacePanel.inspector, false);
    resize();
    if (focusMain && !_blocked) _button(speedToggle).grabFocus();
  }

  void _request(WorkspacePanel panel, bool open) {
    _setDial(false);
    layout.request(panel, open);
    resize();
    if (!open) {
      if (!_blocked) _button(speedToggle).grabFocus();
      return;
    }
    var target = '$inspector/Content/Heading/Close';
    if (panel == WorkspacePanel.library) {
      target = '$sidebar/Content/Heading/Close';
      for (final entry in resourceVisuals3D.values) {
        final path = '$catalog/${entry.buttonName}';
        if (!_button(path).isDisabled()) {
          target = path;
          break;
        }
      }
    }
    _button(target).grabFocus();
  }

  void resize() {
    final result =
        layout.resolve(_scene.getViewport()!.getVisibleRect().size.x);
    final size = _control(center).getSize();
    for (final panel in WorkspacePanel.values) {
      final resource = panel == WorkspacePanel.library;
      final control = _control(resource ? sidebar : inspector);
      final width = resource ? layout.libraryWidth : layout.inspectorWidth;
      final height = (resource ? 340.0 : 380.0)
          .clamp(0.0, size.y - 36.0 < 0 ? 0.0 : size.y - 36.0);
      control
        ..setVisible(resource ? result.library : result.inspector)
        ..setPosition(Vector2(x: 82, y: size.y - height - 18))
        ..setSize(Vector2(x: width, y: height));
    }
  }

  /// Full-screen transparent controls never block picking. Only live buttons
  /// and the visible popup rectangles consume canvas input.
  bool blocksPointer(Vector2 point) => [
        speedToggle,
        if (_dialOpen) ...[libraryToggle, inspectorToggle],
        sidebar,
        inspector,
      ].any((path) {
        final control = _control(path);
        return control.isVisibleInTree() &&
            control.getGlobalRect().hasPoint(point);
      });

  bool handleInput(InputEvent? event) {
    if (_blocked) return false;
    final panel = layout.resolve(_scene.getViewport()!.getVisibleRect().size.x);
    if (event is InputEventKey &&
        event.isPressed() &&
        !event.isEcho() &&
        event.getKeycode() == Key.escape) {
      if (_dialOpen || panel.library || panel.inspector) {
        _setDial(false);
        _closePanels(focusMain: true);
        return true;
      }
    }
    if (event is InputEventMouseButton &&
        event.isPressed() &&
        event.getButtonIndex() == MouseButton.left &&
        !blocksPointer(event.getPosition())) {
      _setDial(false);
      _closePanels();
      // Outside clicks still reach the normal grid/UI input route.
    }
    return false;
  }

  void render(IsomapGridState state,
      {required bool blocked, required bool canConfigure}) {
    _blocked = blocked;
    if (blocked || (_hadSelection && state.selected == null)) {
      _setDial(false);
      _closePanels();
    }
    _button(speedToggle).setDisabled(blocked);
    _button(libraryToggle).setDisabled(blocked);
    _button(inspectorToggle).setDisabled(blocked);
    _button('$sidebar/Content/Heading/Close').setDisabled(blocked);
    _button('$inspector/Content/Heading/Close').setDisabled(blocked);
    _hadSelection = state.selected != null;
    final position = state.selected;
    final resource = state.resources[position];
    void label(String name, String text) {
      final node = _scene.getNodeT<Label>('$details/$name')!;
      node
        ..setText(text)
        ..setTooltipText(text);
    }

    label(
        'Coordinates',
        position == null
            ? 'No tile selected'
            : 'Row ${position.row} · Column ${position.col}');
    label(
        'Kind',
        position == null
            ? 'Select a tile'
            : resource == null
                ? 'Empty tile'
                : resourceVisuals3D[resource.kind]!.label);
    label(
        'Placement',
        resource == null
            ? 'Open Resources to choose a resource.'
            : resource.id == null
                ? 'Local placement'
                : resource.configuration == null
                    ? 'Saved metadata · unconfigured'
                    : 'Saved configuration · revision ${resource.revision}');
    label('Identity', resource?.id == null ? '' : 'Resource: ${resource!.id}');
    label(
        'Deployment',
        resource == null
            ? ''
            : resource.deployment?.describe(resource.revision) ??
                (resource.kind == ResourceKind.cloudStorage
                    ? 'No deployment recorded'
                    : 'Local preview · deployment unavailable'));
    final configure = _button('$details/Configure');
    configure.setVisible(position != null &&
        (resource == null || resource.kind == ResourceKind.cloudStorage));
    configure.setDisabled(blocked || !canConfigure || position == null);
  }

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
