import 'package:godot_dart/godot_dart.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../../domain/models/resource_kind.dart';
import 'resource_visuals_3d.dart';
import 'workspace_3d.dart';

/// Native controls belong to the scene; this helper holds presentation references
/// only. Signal ownership is the scene node, never an additional state owner.
class ResourcePalette3D {
  ResourcePalette3D(Node owner, void Function(ResourceKind) onChosen) {
    _guidance =
        owner.getNodeT<Label>('${Workspace3D.sidebar}/Content/Guidance')!;
    for (final entry in resourceVisuals3D.entries) {
      final button = owner.getNodeT<Button>(
          '${Workspace3D.catalog}/${entry.value.buttonName}')!;
      _buttons.add((button: button, kind: entry.key));
      button.pressed.connect(owner, () => onChosen(entry.key));
    }
  }

  late final Label _guidance;
  final _buttons = <({Button button, ResourceKind kind})>[];

  void render(IsomapGridState state,
      {bool blocked = false, bool canConfigure = false}) {
    final selected = state.selected;
    final hasSelection = selected != null && state.contains(selected);
    final enabled = !blocked && hasSelection;
    final persisted = state.resources[selected]?.id != null;
    for (final choice in _buttons) {
      final button = choice.button;
      final storage = choice.kind == ResourceKind.cloudStorage;
      final available = !storage ||
          canConfigure &&
              (state.resources[selected] == null ||
                  state.resources[selected]?.kind == ResourceKind.cloudStorage);
      final canChoose = enabled &&
          available &&
          (!persisted || state.resources[selected]?.kind == choice.kind);
      button.setDisabled(!canChoose);
      button.setFocusMode(
          canChoose ? ControlFocusMode.focusAll : ControlFocusMode.focusNone);
      button.setTooltipText(storage && !canConfigure
          ? 'Create or open a Design to configure Cloud Storage.'
          : storage && !available
              ? 'Choose an empty tile or an existing Cloud Storage resource.'
              : persisted && !canChoose && enabled
                  ? 'Replacing a persisted resource is not supported. Choose another tile.'
                  : !hasSelection
                      ? '${resourceVisuals3D[choice.kind]!.label} · Select a tile first'
                      : storage
                          ? 'Configure Cloud Storage'
                          : resourceVisuals3D[choice.kind]!.label);
    }
    final text = hasSelection
        ? 'Tile (${selected.row}, ${selected.col}) · ${persisted ? (state.resources[selected]?.configuration == null ? "Unconfigured" : "Saved configuration") : "Local placement"}'
        : 'Select a tile first';
    final selectedResource = state.resources[selected];
    final detail =
        selectedResource?.deployment?.describe(selectedResource.revision);
    _guidance.setTooltipText(detail ?? 'No deployment requested.');
    _guidance.setText(detail == null
        ? text
        : '$text · ${selectedResource!.deployment!.status}');
  }
}
