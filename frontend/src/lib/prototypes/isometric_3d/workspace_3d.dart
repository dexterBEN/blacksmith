import 'package:godot_dart/godot_dart.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../../domain/models/resource_kind.dart';
import 'resource_visuals_3d.dart';
import 'workspace_layout.dart';

/// Native desktop workspace geometry. No editing/business state.
class Workspace3D {
  Workspace3D(this._scene,
      {required void Function() configureStorage,
      required bool Function() hasActiveDesign,
      required void Function() onResourcesOpened,
      required void Function() onResourcesClosed})
      : _hasActiveDesign = hasActiveDesign,
        _onResourcesOpened = onResourcesOpened,
        _onResourcesClosed = onResourcesClosed {
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
    _button(resourceCancel).pressed.connect(_scene, () => dismissResources());
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
    // Wrapped text minima settle after container layout. Reapply the bounds
    // when they change so a scene reload cannot leave the dialog at an old,
    // temporarily clamped height larger than the window.
    _control(sidebar).minimumSizeChanged.connect(_scene, resize);
    resize();
  }

  final Node _scene;
  final bool Function() _hasActiveDesign;
  final void Function() _onResourcesOpened, _onResourcesClosed;
  final layout = WorkspaceLayout();
  bool _dialOpen = false;
  bool _blocked = false;
  bool _hadSelection = false;
  static const minimumWidth = WorkspaceLayout.minimumWindowWidth;
  static const minimumHeight = WorkspaceLayout.minimumWindowHeight;

  static void attach(Node scene) {
    // Keep the established world and all its nodes. A separate camera viewport
    // renders it across the full window, underneath the UI overlays.
    viewport(scene).setWorld_3d(scene.getViewport()!.findWorld_3d());
  }

  static const root = 'WorkspaceLayer/Workspace';
  static const emptyState = '$root/EmptyState';
  static const header = '$root/Header';
  static const status = '$header/Rows/Actions/ActiveDesign';
  static const toolbarButtons = [
    '$header/Rows/Actions/NewDesign',
    '$header/Rows/Actions/OpenDesign',
    '$header/Rows/Actions/SaveDesign',
    '$header/Rows/Actions/CopyDesignId',
  ];
  static const body = '$root/Body';
  static const center = '$body/Center';
  static const speedDial = '$center/SpeedDial';
  static const speedToggle = '$speedDial/Toggle';
  static const speedActions = '$speedDial/Actions';
  static const libraryToggle = '$speedActions/LibraryToggle';
  static const inspectorToggle = '$speedActions/InspectorToggle';
  static const resourceOverlay = '$root/ResourcesOverlay';
  static const sidebar = '$resourceOverlay/Dialog';
  static const resourceConfirm = '$sidebar/Content/Footer/Place';
  static const resourceCancel = '$sidebar/Content/Footer/Cancel';
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
    _dialOpen = open && !_blocked && _hasActiveDesign();
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
    if (focusMain && !_blocked && _hasActiveDesign()) {
      _button(speedToggle).grabFocus();
    }
  }

  void _closePanels({bool focusMain = false}) {
    final resourcesWereOpen = isResourcesOpen;
    layout.request(WorkspacePanel.library, false);
    if (resourcesWereOpen) _onResourcesClosed();
    layout.request(WorkspacePanel.inspector, false);
    resize();
    if (focusMain && !_blocked && _hasActiveDesign()) {
      _button(speedToggle).grabFocus();
    }
  }

  bool get isResourcesOpen => _control(resourceOverlay).isVisible();

  void dismissResources() => _request(WorkspacePanel.library, false);

  void _request(WorkspacePanel panel, bool open) {
    if (open && !_hasActiveDesign()) return;
    _setDial(false);
    final resourcesWereOpen = isResourcesOpen;
    layout.request(panel, open);
    resize();
    if (panel == WorkspacePanel.library && open) _onResourcesOpened();
    if (resourcesWereOpen && !(panel == WorkspacePanel.library && open)) {
      _onResourcesClosed();
    }
    if (!open) {
      if (!_blocked && _hasActiveDesign()) _button(speedToggle).grabFocus();
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
    final inspectorHeight =
        380.0.clamp(0.0, (size.y - 36.0).clamp(0.0, double.infinity));
    _control(inspector)
      ..setVisible(result.inspector)
      ..setPosition(Vector2(x: 82, y: size.y - inspectorHeight - 18))
      ..setSize(Vector2(x: layout.inspectorWidth, y: inspectorHeight));
    _control(resourceOverlay).setVisible(result.library);
    for (final path in [speedToggle, libraryToggle, inspectorToggle]) {
      _button(path)
          .setDisabled(!_hasActiveDesign() || _blocked || result.library);
    }
    final canvasBounds = canvasRect(_scene);
    final width = 520.0
        .clamp(0.0, (canvasBounds.size.x - 32).clamp(0.0, double.infinity));
    final height = 500.0
        .clamp(0.0, (canvasBounds.size.y - 32).clamp(0.0, double.infinity));
    _control(sidebar)
      ..setSize(Vector2(x: width, y: height))
      ..setPosition(canvasBounds.position -
          _control(root).getGlobalRect().position +
          Vector2(
              x: (canvasBounds.size.x - width) / 2,
              y: (canvasBounds.size.y - height) / 2));
  }

  /// Full-screen transparent controls never block picking. Only live buttons
  /// and the visible popup rectangles consume canvas input.
  bool blocksPointer(Vector2 point) =>
      isResourcesOpen ||
      [
        ...toolbarButtons,
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
    if (isResourcesOpen) {
      if (event is InputEventKey && event.isPressed() && !event.isEcho()) {
        if (event.getKeycode() == Key.escape) {
          if (!_button(resourceCancel).isDisabled()) dismissResources();
          return true;
        }
        final paths = [
          '$sidebar/Content/Heading/Close',
          for (final item in resourceVisuals3D.values)
            '$catalog/${item.buttonName}',
          resourceCancel,
          resourceConfirm
        ];
        final controls = paths
            .map(_button)
            .where((b) => !b.isDisabled() && b.isVisibleInTree())
            .toList();
        final focused = controls.indexWhere((b) => b.hasFocus());
        if (event.getKeycode() == Key.tab) {
          if (controls.isNotEmpty) {
            final next =
                (focused + (event.isShiftPressed() ? -1 : 1)) % controls.length;
            controls[next].grabFocus();
          }
          return true;
        }
        if (focused < 0) {
          if (controls.isNotEmpty) controls.first.grabFocus();
          return true;
        }
      }
      // Backdrop policy: keep the modal open and swallow all background input.
      if (event is InputEventMouseButton) {
        return !_control(sidebar).getGlobalRect().hasPoint(event.getPosition());
      }
      if (event is InputEventMouseMotion) {
        return !_control(sidebar).getGlobalRect().hasPoint(event.getPosition());
      }
      return false;
    }
    if (_blocked || !_hasActiveDesign()) return false;
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
    final available = _hasActiveDesign();
    _control(emptyState).setVisible(!available);
    _control(speedDial).setVisible(available);
    if (!available ||
        blocked ||
        (_hadSelection && state.selected == null && !isResourcesOpen)) {
      _setDial(false);
      _closePanels();
    }
    for (final path in [speedToggle, libraryToggle, inspectorToggle]) {
      _button(path).setDisabled(!available || blocked || isResourcesOpen);
    }
    if (!isResourcesOpen) {
      _button('$sidebar/Content/Heading/Close').setDisabled(blocked);
    }
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
