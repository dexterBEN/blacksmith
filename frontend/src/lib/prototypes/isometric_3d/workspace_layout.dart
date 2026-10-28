import 'dart:math' as math;

enum WorkspacePanel { library, inspector }

/// Session-only presentation preferences. No Godot, selection or data access.
class WorkspaceLayout {
  static const minimumWindowWidth = 960;
  static const minimumWindowHeight = 640;
  static const minimumCanvasWidth = 480.0;
  static const minimumCanvasHeight = 320.0;
  static const margin = 12.0;
  static const separation = 8.0;
  static const railWidth = 56.0;
  static const gripWidth = 6.0;
  static const minimumLibraryWidth = 200.0;
  static const minimumInspectorWidth = 216.0;
  static const maximumPanelWidth = 304.0;

  bool _libraryRequested = false;
  bool _inspectorRequested = false;
  double _libraryWidth = 216;
  double _inspectorWidth = 240;
  WorkspacePanel _preferred = WorkspacePanel.library;
  double get libraryWidth => _libraryWidth;
  double get inspectorWidth => _inspectorWidth;

  void request(WorkspacePanel panel, bool open) {
    if (panel == WorkspacePanel.library) {
      _libraryRequested = open;
    } else {
      _inspectorRequested = open;
    }
    if (open) _preferred = panel;
  }

  void resize(WorkspacePanel panel, double width) {
    if (panel == WorkspacePanel.library) {
      _libraryWidth = width.clamp(minimumLibraryWidth, maximumPanelWidth);
    } else {
      _inspectorWidth = width.clamp(minimumInspectorWidth, maximumPanelWidth);
    }
    _preferred = panel;
  }

  ({bool library, bool inspector, double canvasWidth}) resolve(double width) {
    final available =
        math.max(width, minimumWindowWidth.toDouble()) - 2 * margin;
    var left = _libraryRequested, right = _inspectorRequested;
    double canvas() {
      final panels = (left ? 1 : 0) + (right ? 1 : 0);
      // Rail + center, and two extra HBox children (panel/grip) per dock.
      return available -
          railWidth -
          separation * (1 + 2 * panels) -
          (left ? libraryWidth + gripWidth : 0) -
          (right ? inspectorWidth + gripWidth : 0);
    }

    if (left && right && canvas() < minimumCanvasWidth) {
      left = _preferred == WorkspacePanel.library;
      right = !left;
    }
    // Maximum panel widths still leave the minimum canvas at the OS minimum.
    return (library: left, inspector: right, canvasWidth: canvas());
  }
}
