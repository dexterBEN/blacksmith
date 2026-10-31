import 'dart:async' as async;
import 'package:godot_dart/godot_dart.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../../domain/models/grid_position.dart';
import '../../domain/models/resource_kind.dart';
import 'resource_visuals_3d.dart';
import 'resource_picker_draft.dart';
import 'workspace_3d.dart';

/// Native resource rows and a UI-only draft; placement stays in the existing BLoC.
class ResourcePalette3D {
  ResourcePalette3D(this._owner, this._onChosen,
      {required void Function() onPlaced})
      : _onPlaced = onPlaced {
    _guidance =
        _owner.getNodeT<Label>('${Workspace3D.sidebar}/Content/Guidance')!;
    _feedback =
        _owner.getNodeT<Label>('${Workspace3D.sidebar}/Content/Feedback')!;
    _confirm = _owner.getNodeT<Button>(Workspace3D.resourceConfirm)!;
    _confirm.pressed.connect(_owner, () => async.unawaited(_submit()));
    for (final entry in resourceVisuals3D.entries) {
      final button = _owner.getNodeT<Button>(
          '${Workspace3D.catalog}/${entry.value.buttonName}')!;
      _buttons.add((button: button, kind: entry.key));
      button.pressed.connect(_owner, () {
        if (!button.isDisabled()) _draft.choose(entry.key);
        _updateDraft();
      });
    }
  }

  final Node _owner;
  final Future<void> Function(ResourceKind, GridPos) _onChosen;
  final void Function() _onPlaced;
  final _draft = ResourcePickerDraft();
  IsomapGridState _state = IsomapGridState.initial();
  bool _blocked = false, _canConfigure = false;
  late final Label _guidance, _feedback;
  late final Button _confirm;
  final _buttons = <({Button button, ResourceKind kind})>[];

  void open() {
    _draft.open(_state.selected);
    render(_state, blocked: _blocked, canConfigure: _canConfigure);
  }

  void close() => _draft.close();

  bool get _eligible =>
      _draft.chosen != null &&
      _buttons.any((choice) =>
          choice.kind == _draft.chosen && !choice.button.isDisabled());

  Future<void> _submit() async {
    final result = _draft.confirm(eligible: _eligible, place: _onChosen);
    // The synchronous portion marks the submission pending before yielding.
    render(_state, blocked: _blocked, canConfigure: _canConfigure);
    if (await result) {
      _onPlaced();
    } else if (_draft.active) {
      render(_state, blocked: _blocked, canConfigure: _canConfigure);
    }
  }

  void _updateDraft() {
    for (final choice in _buttons) {
      choice.button.setPressedNoSignal(_draft.chosen == choice.kind);
    }
    _confirm
      ..setDisabled(!_draft.canConfirm(eligible: _eligible))
      ..setText(_draft.pending ? 'Placing…' : 'Place Resource');
    for (final name in ['Content/Heading/Close', 'Content/Footer/Cancel']) {
      _owner
          .getNodeT<Button>('${Workspace3D.sidebar}/$name')!
          .setDisabled(_draft.pending);
    }
    final message = _draft.error;
    _feedback
      ..setText(message ?? '')
      ..setTooltipText(message ?? '')
      ..setVisible(message != null);
  }

  void render(IsomapGridState state,
      {bool blocked = false, bool canConfigure = false}) {
    _state = state;
    _blocked = blocked;
    _canConfigure = canConfigure;
    _draft.observe(state.selected);
    final selected = state.selected;
    final hasSelection = selected != null && state.contains(selected);
    final enabled =
        !blocked && hasSelection && !_draft.pending && !_draft.invalidated;
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
              : persisted && !canChoose && hasSelection
                  ? 'Replacing a persisted resource is not supported. Choose another tile.'
                  : !hasSelection
                      ? '${resourceVisuals3D[choice.kind]!.label} · Select a tile first'
                      : storage
                          ? 'Configure Cloud Storage'
                          : resourceVisuals3D[choice.kind]!.label);
    }
    final target = _draft.active ? _draft.target : selected;
    _guidance.setText(target == null
        ? 'Select a tile first'
        : 'Selected tile: (${target.row}, ${target.col})');
    _updateDraft();
  }
}
