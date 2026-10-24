import 'package:godot_dart/godot_dart.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../../domain/models/resource_kind.dart';
import 'resource_visuals_3d.dart';
import 'workspace_3d.dart';

/// Native controls belong to the scene; this helper holds presentation references
/// only. Signal ownership is the scene node, never an additional state owner.
class ResourcePalette3D {
  ResourcePalette3D(Node owner, void Function(ResourceKind) onChosen) {
    _instruction =
        owner.getNodeT<Label>('${Workspace3D.quick}/Content/Instruction')!;
    _guidance =
        owner.getNodeT<Label>('${Workspace3D.sidebar}/Content/Guidance')!;
    for (final entry in resourceVisuals3D.entries) {
      for (final path in [Workspace3D.catalog, Workspace3D.choices]) {
        final button =
            owner.getNodeT<Button>('$path/${entry.value.buttonName}')!;
        _buttons.add(button);
        button.pressed.connect(owner, () => onChosen(entry.key));
      }
    }
  }

  late final Label _instruction, _guidance;
  final _buttons = <Button>[];

  void render(IsomapGridState state, {bool blocked = false}) {
    final selected = state.selected;
    final hasSelection = selected != null && state.contains(selected);
    final enabled = !blocked && hasSelection;
    for (final button in _buttons) {
      button.setDisabled(!enabled);
      button.setFocusMode(
          enabled ? ControlFocusMode.focusAll : ControlFocusMode.focusNone);
    }
    final text = hasSelection
        ? 'Tile (${selected.row}, ${selected.col}) · Local placement'
        : 'Select a tile first';
    _instruction.setText(text);
    _guidance.setText(text);
  }
}
