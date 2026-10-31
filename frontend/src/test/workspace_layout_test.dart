import 'package:blacksmith_front/prototypes/isometric_3d/workspace_layout.dart';
import 'package:test/test.dart';

void main() {
  test('collapsed controls leave the entire body width to the canvas', () {
    final result = WorkspaceLayout().resolve(1280);
    expect(result.library, isFalse);
    expect(result.inspector, isFalse);
    expect(result.canvasWidth, 1256);
  });

  for (final width in [960.0, 1280.0, 1600.0, 1920.0]) {
    test('$width floating panels never reserve canvas space', () {
      final state = WorkspaceLayout();
      final fullWidth = state.resolve(width).canvasWidth;
      for (final panel in WorkspacePanel.values) {
        state.request(panel, true);
        final open = state.resolve(width);
        expect(open.canvasWidth, fullWidth);
        expect(open.library, panel == WorkspacePanel.library);
        expect(open.inspector, panel == WorkspacePanel.inspector);
        state.request(panel, false);
        expect(state.resolve(width).canvasWidth, fullWidth);
      }
    });
  }

  test('choosing another popup replaces it without leaving a hidden request',
      () {
    final state = WorkspaceLayout()
      ..request(WorkspacePanel.library, true)
      ..request(WorkspacePanel.inspector, true);
    expect(state.resolve(960).library, isFalse);
    expect(state.resolve(960).inspector, isTrue);
    state.request(WorkspacePanel.library, false);
    expect(state.resolve(960).inspector, isTrue);
    state.request(WorkspacePanel.inspector, false);
    expect(state.resolve(1920).library, isFalse);
    expect(state.resolve(1920).inspector, isFalse);
  });

  test('panel preferences cannot reduce the render viewport', () {
    final state = WorkspaceLayout();
    for (final panel in WorkspacePanel.values) {
      state.resize(panel, 10000);
      state.request(panel, true);
      expect(state.resolve(960).canvasWidth, 936);
      expect(
          panel == WorkspacePanel.library
              ? state.libraryWidth
              : state.inspectorWidth,
          WorkspaceLayout.maximumPanelWidth);
    }
  });
}
