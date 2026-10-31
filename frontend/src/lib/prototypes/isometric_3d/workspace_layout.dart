import 'dart:math' as math;

enum WorkspacePanel { library, inspector }

/// Session-only floating-panel preferences. No selection or data access.
class WorkspaceLayout {
  static const minimumWindowWidth = 960;
  static const minimumWindowHeight = 640;
  static const minimumCanvasWidth = 480.0;
  static const minimumCanvasHeight = 320.0;
  static const margin = 12.0;
  static const minimumLibraryWidth = 200.0;
  static const minimumInspectorWidth = 216.0;
  static const maximumPanelWidth = 304.0;

  WorkspacePanel? _active;
  double _libraryWidth = 216;
  double _inspectorWidth = 240;
  double get libraryWidth => _libraryWidth;
  double get inspectorWidth => _inspectorWidth;

  void request(WorkspacePanel panel, bool open) {
    if (open) {
      _active = panel;
    } else if (_active == panel) {
      _active = null;
    }
  }

  void resize(WorkspacePanel panel, double width) {
    if (panel == WorkspacePanel.library) {
      _libraryWidth = width.clamp(minimumLibraryWidth, maximumPanelWidth);
    } else {
      _inspectorWidth = width.clamp(minimumInspectorWidth, maximumPanelWidth);
    }
  }

  ({bool library, bool inspector, double canvasWidth}) resolve(double width) =>
      (
        library: _active == WorkspacePanel.library,
        inspector: _active == WorkspacePanel.inspector,
        canvasWidth:
            math.max(width, minimumWindowWidth.toDouble()) - 2 * margin,
      );
}
