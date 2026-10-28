import 'package:godot_dart/godot_dart.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../../domain/models/resource_kind.dart';
import 'resource_visuals_3d.dart';
import 'workspace_layout.dart';

/// Native desktop workspace geometry. No editing/business state.
class Workspace3D {
  Workspace3D(this._scene, {required void Function() configureStorage}) {
    _button(libraryToggle)
        .pressed
        .connect(_scene, () => _toggle(WorkspacePanel.library));
    _button(inspectorToggle)
        .pressed
        .connect(_scene, () => _toggle(WorkspacePanel.inspector));
    _button('$sidebar/Content/Heading/Close')
        .pressed
        .connect(_scene, () => _request(WorkspacePanel.library, false));
    _button('$inspector/Content/Heading/Close')
        .pressed
        .connect(_scene, () => _request(WorkspacePanel.inspector, false));
    _button('$details/Configure').pressed.connect(_scene, configureStorage);
    for (final panel in WorkspacePanel.values) {
      _control(panel == WorkspacePanel.library ? libraryGrip : inspectorGrip)
          .guiInput
          .connect(_scene, (event) {
        if (event is InputEventMouseButton &&
            event.isPressed() &&
            event.getButtonIndex() == MouseButton.left) {
          _dragging = panel;
          _dragStart = event.getGlobalPosition().x;
          _initialWidth = panel == WorkspacePanel.library
              ? layout.libraryWidth
              : layout.inspectorWidth;
          _scene.getViewport()!.setInputAsHandled();
        }
      });
    }
    _scene
        .getTree()!
        .getRoot()!
        .focusExited
        .connect(_scene, () => _dragging = null);
    resize();
  }

  final Node _scene;
  final layout = WorkspaceLayout();
  WorkspacePanel? _dragging;
  double _dragStart = 0, _initialWidth = 0;
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
  static const rail = '$body/NavigationRail';
  static const libraryToggle = '$rail/LibraryToggle';
  static const inspectorToggle = '$rail/InspectorToggle';
  static const sidebar = '$root/Margin/Layout/Body/Sidebar';
  static const inspector = '$body/Inspector';
  static const details = '$inspector/Content/Scroll/Details';
  static const libraryGrip = '$body/LibraryResize';
  static const inspectorGrip = '$body/InspectorResize';
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

  Control _control(String path) => _scene.getNodeT<Control>(path)!;
  Button _button(String path) => _scene.getNodeT<Button>(path)!;

  void _request(WorkspacePanel panel, bool open) {
    layout.request(panel, open);
    resize();
  }

  void _toggle(WorkspacePanel panel) {
    final visible =
        layout.resolve(_scene.getViewport()!.getVisibleRect().size.x);
    _request(
        panel,
        !(panel == WorkspacePanel.library
            ? visible.library
            : visible.inspector));
  }

  void resize() {
    final result =
        layout.resolve(_scene.getViewport()!.getVisibleRect().size.x);
    _control(sidebar)
      ..setVisible(result.library)
      ..setCustomMinimumSize(Vector2(x: layout.libraryWidth, y: 0));
    _control(inspector)
      ..setVisible(result.inspector)
      ..setCustomMinimumSize(Vector2(x: layout.inspectorWidth, y: 0));
    _control(libraryGrip).setVisible(result.library);
    _control(inspectorGrip).setVisible(result.inspector);
    _button(libraryToggle)
      ..setPressedNoSignal(result.library)
      ..setTooltipText(
          result.library ? 'Close Resource Library' : 'Open Resource Library');
    _button(inspectorToggle)
      ..setPressedNoSignal(result.inspector)
      ..setTooltipText(result.inspector
          ? 'Close Inspector'
          : 'Open tile and resource Inspector');
  }

  bool handleInput(InputEvent? event) {
    final dragging = _dragging;
    if (dragging == null) return false;
    if (event is InputEventMouseButton &&
        event.getButtonIndex() == MouseButton.left &&
        !event.isPressed()) {
      _dragging = null;
      // Let Godot clear its GUI mouse capture. World picking ignores releases.
      return false;
    }
    if (event is InputEventMouseMotion) {
      final delta = event.getPosition().x - _dragStart;
      layout.resize(
          dragging,
          _initialWidth +
              (dragging == WorkspacePanel.library ? delta : -delta));
      resize();
      return true;
    }
    return false;
  }

  void render(IsomapGridState state,
      {required bool blocked, required bool canConfigure}) {
    if (blocked) _dragging = null;
    _button(libraryToggle).setDisabled(blocked);
    _button(inspectorToggle).setDisabled(blocked);
    _button('$sidebar/Content/Heading/Close').setDisabled(blocked);
    _button('$inspector/Content/Heading/Close').setDisabled(blocked);
    if (_hadSelection && state.selected == null) {
      _request(WorkspacePanel.inspector, false);
    }
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
            ? 'Choose a resource from the library or quick placement.'
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
