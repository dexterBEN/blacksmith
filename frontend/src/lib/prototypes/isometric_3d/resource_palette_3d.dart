import 'dart:math' as math;
import 'package:godot_dart/godot_dart.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../../domain/models/resource_kind.dart';
import 'resource_visuals_3d.dart';

/// Native controls belong to the scene; this helper holds presentation references
/// only. Signal ownership is the scene node, never an additional state owner.
class ResourcePalette3D {
  ResourcePalette3D(Node owner, void Function(ResourceKind) onChosen) {
    owner.getNodeT<CanvasLayer>('PaletteLayer')!.setVisible(true);
    _panel = owner.getNodeT<Panel>('PaletteLayer/ResourcePalette/Panel')!;
    _instruction = _panel.getNodeT<Label>('Instruction')!;
    _choices = _panel.getNodeT<GridContainer>('Choices')!;
    for (final entry in resourceVisuals3D.entries) {
      final button = _choices.getNodeT<Button>(entry.value.buttonName)!;
      _buttons.add(button);
      button.pressed.connect(owner, () => onChosen(entry.key));
    }
  }

  late final Panel _panel;
  late final Label _instruction;
  late final GridContainer _choices;
  final _buttons = <Button>[];

  void render(IsomapGridState state) {
    final selected = state.selected;
    final enabled = selected != null && state.contains(selected);
    for (final button in _buttons) {
      button.setDisabled(!enabled);
    }
    _instruction.setText(enabled
        ? 'Tile (${selected.row}, ${selected.col}) · Local placement'
        : 'Select a tile first');
  }

  void resize(Vector2 viewport) {
    final width = math.min(880.0, math.max(1.0, viewport.x - 24));
    final columns = viewport.x >= 816 ? 4 : (viewport.x >= 416 ? 2 : 1);
    final rows = (4 / columns).ceil();
    final height = 36.0 + rows * 40 + (rows - 1) * 8;
    _panel
      ..setPosition(Vector2(
          x: (viewport.x - width) / 2,
          y: math.max(0.0, viewport.y - height - 12)))
      ..setSize(Vector2(x: width, y: height));
    _instruction
      ..setPosition(Vector2(x: 8, y: 6))
      ..setSize(Vector2(x: width - 16, y: 20));
    _choices
      ..setColumns(columns)
      ..setPosition(Vector2(x: 8, y: 28))
      ..setSize(Vector2(x: width - 16, y: height - 34));
    for (final button in _buttons) {
      button.setCustomMinimumSize(Vector2(
          x: math.max(1.0, (width - 16 - (columns - 1) * 8) / columns), y: 40));
    }
  }
}
