import 'package:blacksmith_front/prototypes/isometric_3d/workspace_layout.dart';
import 'package:test/test.dart';

void main() {
  test('canvas-first defaults reclaim both optional docks', () {
    final state = WorkspaceLayout();
    final result = state.resolve(1280);
    expect(result.library, isFalse);
    expect(result.inspector, isFalse);
    expect(result.canvasWidth, 1192);
  });

  for (final width in [960.0, 1280.0, 1600.0, 1920.0]) {
    for (final left in [false, true]) {
      for (final right in [false, true]) {
        test('$width library=$left inspector=$right reserves minimum canvas',
            () {
          final state = WorkspaceLayout()
            ..request(WorkspacePanel.library, left)
            ..request(WorkspacePanel.inspector, right);
          final result = state.resolve(width);
          expect(result.canvasWidth,
              greaterThanOrEqualTo(WorkspaceLayout.minimumCanvasWidth));
          if (width >= 1280) {
            expect(result.library, left);
            expect(result.inspector, right);
          }
        });
      }
    }
  }

  test('desktop docks are independent; closing returns their space', () {
    final state = WorkspaceLayout();
    final empty = state.resolve(1600).canvasWidth;
    state.request(WorkspacePanel.library, true);
    final left = state.resolve(1600).canvasWidth;
    state.request(WorkspacePanel.inspector, true);
    final both = state.resolve(1600).canvasWidth;
    expect(empty, greaterThan(left));
    expect(left, greaterThan(both));
    state.request(WorkspacePanel.library, false);
    expect(state.resolve(1600).inspector, isTrue);
    expect(state.resolve(1600).library, isFalse);
    state.request(WorkspacePanel.inspector, false);
    expect(state.resolve(1600).canvasWidth, empty);
  });

  test(
      'narrow fallback honors the last requested dock and preserves preferences',
      () {
    final state = WorkspaceLayout()
      ..request(WorkspacePanel.library, true)
      ..request(WorkspacePanel.inspector, true);
    expect(state.resolve(960).library, isFalse);
    expect(state.resolve(960).inspector, isTrue);
    state.request(WorkspacePanel.library, true);
    expect(state.resolve(960).library, isTrue);
    expect(state.resolve(960).inspector, isFalse);
    expect(state.resolve(1920).library, isTrue);
    expect(state.resolve(1920).inspector, isTrue);
  });

  test('drag widths clamp to useful limits and cannot consume the canvas', () {
    final state = WorkspaceLayout()
      ..request(WorkspacePanel.library, true)
      ..request(WorkspacePanel.inspector, true);
    for (final panel in WorkspacePanel.values) {
      state.resize(panel, -100);
      expect(
          panel == WorkspacePanel.library
              ? state.libraryWidth
              : state.inspectorWidth,
          panel == WorkspacePanel.library
              ? WorkspaceLayout.minimumLibraryWidth
              : WorkspaceLayout.minimumInspectorWidth);
      state.resize(panel, 10000);
      expect(
          panel == WorkspacePanel.library
              ? state.libraryWidth
              : state.inspectorWidth,
          WorkspaceLayout.maximumPanelWidth);
      expect(state.resolve(960).canvasWidth,
          greaterThanOrEqualTo(WorkspaceLayout.minimumCanvasWidth));
      expect(state.resolve(1280).library, isTrue);
      expect(state.resolve(1280).inspector, isTrue);
    }
  });
}
