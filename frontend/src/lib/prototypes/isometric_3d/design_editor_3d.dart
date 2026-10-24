import 'dart:async' as async;
import 'dart:math' as math;
import 'package:godot_dart/godot_dart.dart';
import '../../domain/bloc/design/design_cubit.dart';

/// Presentation only: native controls and the scene-owned state subscription.
/// The shared Cubit, request, active Design and discard policy outlive scenes.
class DesignEditor3D {
  DesignEditor3D(Node owner, this._cubit, this._onModalChanged) {
    _controls = owner.getNodeT<Control>('DesignLayer/DesignControls')!;
    _header = _controls.getNodeT<Panel>('Header')!;
    _new = _header.getNodeT<Button>('NewDesign')!;
    _active = _header.getNodeT<Label>('ActiveDesign')!;
    _shade = _controls.getNodeT<ColorRect>('Shade')!;
    _dialog = _shade.getNodeT<Panel>('Dialog')!;
    _name = _dialog.getNodeT<LineEdit>('Name')!;
    _discard = _dialog.getNodeT<CheckButton>('Discard')!;
    _feedback = _dialog.getNodeT<Label>('Feedback')!;
    _create = _dialog.getNodeT<Button>('Create')!;
    _cancel = _dialog.getNodeT<Button>('Cancel')!;
    _new.pressed.connect(owner, () => _cubit?.open());
    _cancel.pressed.connect(owner, () => _cubit?.cancel());
    _create.pressed.connect(owner, () {
      final cubit = _cubit;
      if (cubit != null) async.unawaited(cubit.submit());
    });
    _name.textChanged.connect(owner, (name) => _cubit?.changeName(name));
    _name.textSubmitted.connect(owner, (_) {
      final cubit = _cubit;
      if (cubit != null && cubit.state.canSubmit) {
        async.unawaited(cubit.submit());
      }
    });
    _discard.toggled
        .connect(owner, (approved) => _cubit?.approveDiscard(approved));
    _subscription = _cubit?.stream.listen(_render);
    _render(_cubit?.state ?? const DesignState());
    if (_cubit == null) {
      _new.setTooltipText(
          'Design creation is unavailable in this isolated preview.');
    }
  }

  final DesignCubit? _cubit;
  final void Function(bool) _onModalChanged;
  async.StreamSubscription<DesignState>? _subscription;
  late final Control _controls;
  late final Panel _header, _dialog;
  late final ColorRect _shade;
  late final Button _new, _create, _cancel;
  late final Label _active, _feedback;
  late final LineEdit _name;
  late final CheckButton _discard;
  bool _wasOpen = false;
  bool _disposed = false;
  bool get isOpen => _cubit?.state.dialogOpen ?? false;
  static const boardTop = 68.0;

  void _render(DesignState state) {
    if (_disposed) return;
    _new.setDisabled(_cubit == null || state.dialogOpen);
    _active.setText(state.active == null
        ? 'No active Design · Local placements only'
        : '${state.active!.name} · Placements not saved');
    _active.setTooltipText(
        state.active == null ? '' : 'Design ID: ${state.active!.id}');
    _shade.setVisible(state.dialogOpen);
    _onModalChanged(state.dialogOpen);
    if (_name.getText() != state.name) _name.setText(state.name);
    _name.setEditable(!state.pending);
    _discard
      ..setVisible(state.requiresDiscard)
      ..setDisabled(state.pending)
      ..setPressedNoSignal(state.discardApproved);
    _create
      ..setDisabled(!state.canSubmit)
      ..setText(state.pending ? 'Creating…' : 'Create');
    _cancel.setDisabled(state.pending);
    _feedback.setText(state.pending
        ? 'Creating Design… Please wait. Closing this dialog cannot cancel a request already sent.'
        : state.error ??
            (state.requiresDiscard
                ? 'Current placements are unsaved. Confirm clearing them only after the API creates the new Design.'
                : 'The new Design starts empty. Resource placements remain local and are not saved.'));
    if (state.dialogOpen && !_wasOpen) _name.grabFocus();
    if (!state.dialogOpen && _wasOpen) _new.grabFocus();
    _wasOpen = state.dialogOpen;
  }

  void resize(Vector2 viewport) {
    _header
      ..setPosition(Vector2(x: 12, y: 12))
      ..setSize(Vector2(x: viewport.x - 24, y: 44));
    _new
      ..setPosition(Vector2(x: 8, y: 6))
      ..setSize(Vector2(x: 116, y: 32));
    _active
      ..setPosition(Vector2(x: 136, y: 6))
      ..setSize(Vector2(x: math.max(1, viewport.x - 172), y: 32));
    final width = math.min(520.0, viewport.x - 32);
    const height = 300.0;
    _dialog
      ..setPosition(
          Vector2(x: (viewport.x - width) / 2, y: (viewport.y - height) / 2))
      ..setSize(Vector2(x: width, y: height));
    void place(Control control, double x, double y, double w, double h) {
      control
        ..setPosition(Vector2(x: x, y: y))
        ..setSize(Vector2(x: w, y: h));
    }

    place(_dialog.getNodeT<Label>('Title')!, 16, 12, width - 32, 30);
    place(_dialog.getNodeT<Label>('NameLabel')!, 16, 50, width - 32, 24);
    place(_name, 16, 78, width - 32, 36);
    place(_discard, 12, 120, width - 24, 32);
    place(_feedback, 16, 158, width - 32, 80);
    place(_cancel, width - 232, 250, 100, 36);
    place(_create, width - 120, 250, 104, 36);
  }

  void dispose() {
    _disposed = true;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) async.unawaited(subscription.cancel());
  }
}
