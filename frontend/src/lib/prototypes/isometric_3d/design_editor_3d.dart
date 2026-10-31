import 'dart:async' as async;
import 'dart:math' as math;
import 'package:godot_dart/godot_dart.dart';
import '../../domain/bloc/design/design_cubit.dart';
import 'workspace_3d.dart';
import 'resource_configuration_editor_3d.dart';

/// Presentation only: native controls and the scene-owned state subscription.
/// The shared Cubit, request, active Design and discard policy outlive scenes.
class DesignEditor3D {
  DesignEditor3D(Node owner, this._cubit, this._onModalChanged) {
    _controls = owner.getNodeT<Control>('DesignLayer/DesignControls')!;
    _new =
        owner.getNodeT<Button>('${Workspace3D.header}/Rows/Actions/NewDesign')!;
    _open = owner
        .getNodeT<Button>('${Workspace3D.header}/Rows/Actions/OpenDesign')!;
    _save = owner
        .getNodeT<Button>('${Workspace3D.header}/Rows/Actions/SaveDesign')!;
    _copy = owner
        .getNodeT<Button>('${Workspace3D.header}/Rows/Actions/CopyDesignId')!;
    _open.pressed.connect(owner, () => _cubit?.openExisting());
    _save.pressed.connect(owner, () {
      if (_cubit != null) async.unawaited(_cubit.save());
    });
    _copy.pressed.connect(owner, () {
      final id = _cubit?.state.active?.id;
      if (id != null) DisplayServer.singleton.clipboardSet(id);
    });
    _active = owner.getNodeT<Label>(Workspace3D.status)!;
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
    _name.textChanged.connect(owner, (name) {
      if (_cubit?.state.mode == DesignDialogMode.open) {
        _cubit?.changeOpenId(name);
      } else {
        _cubit?.changeName(name);
      }
    });
    _name.textSubmitted.connect(owner, (_) {
      final cubit = _cubit;
      if (cubit != null && cubit.state.canSubmit) {
        async.unawaited(cubit.submit());
      }
    });
    _discard.toggled
        .connect(owner, (approved) => _cubit?.approveDiscard(approved));
    _configuration = ResourceConfigurationEditor3D(owner, _cubit);
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
  late final Panel _dialog;
  late final ColorRect _shade;
  late final Button _new, _create, _cancel, _open, _save, _copy;
  late final Label _active, _feedback;
  late final LineEdit _name;
  late final CheckButton _discard;
  late final ResourceConfigurationEditor3D _configuration;
  bool _wasOpen = false;
  bool _disposed = false;
  bool get isOpen =>
      (_cubit?.state.modalOpen ?? false) || (_cubit?.state.pending ?? false);
  bool handleInput(InputEvent? event) => _configuration.handleInput(event);

  void _render(DesignState state) {
    if (_disposed) return;
    final blocked = state.modalOpen || state.pending;
    final opening = state.mode == DesignDialogMode.open;
    _new.setDisabled(_cubit == null || blocked);
    _open.setDisabled(!(_cubit?.supportsPersistence ?? false) || blocked);
    _save
      ..setDisabled(!state.canSave || blocked)
      ..setText(state.saveUncertain ? 'Check Save' : 'Save')
      ..setTooltipText(state.persistenceMessage);
    _copy.setDisabled(state.active == null || blocked);
    _active.setText(state.active == null
        ? 'No active Design · ${state.persistenceMessage}'
        : '${state.active!.name} · ${state.persistenceMessage}');
    _active.setTooltipText(state.active == null
        ? _active.getText()
        : '${_active.getText()}\nDesign ID: ${state.active!.id}');
    _shade.setVisible(state.dialogOpen);
    _configuration.render(state);
    _onModalChanged(blocked);
    _dialog
        .getNodeT<Label>('Title')!
        .setText(opening ? 'Open an existing Design' : 'Create a new Design');
    _dialog
        .getNodeT<Label>('NameLabel')!
        .setText(opening ? 'Design ID' : 'Design name (1–200 characters)');
    _name.setPlaceholder(
        opening ? 'Paste the saved Design ID' : 'My infrastructure design');
    final input = opening ? state.openId : state.name;
    if (_name.getText() != input) _name.setText(input);
    _name.setEditable(!state.pending);
    _discard
      ..setText(opening
          ? 'Replace unsaved placements after a successful load'
          : 'Clear unsaved placements after creation')
      ..setVisible(state.requiresDiscard)
      ..setDisabled(state.pending)
      ..setPressedNoSignal(state.discardApproved);
    _create
      ..setDisabled(!state.canSubmit)
      ..setText(state.pending
          ? (opening ? 'Opening…' : 'Creating…')
          : (opening ? 'Open' : 'Create'));
    _cancel.setDisabled(state.pending);
    _feedback.setText(state.pending
        ? (opening
            ? 'Opening Design… Local placements are preserved until loading succeeds.'
            : 'Creating Design… Please wait. Closing this dialog cannot cancel a request already sent.')
        : state.error ??
            (state.requiresDiscard
                ? (opening
                    ? 'Unsaved local placements will be replaced only after a successful load.'
                    : 'Current placements are unsaved. Confirm clearing them only after the API creates the new Design.')
                : (opening
                    ? 'Loads all supported Cloud Storage placements and existing configurations. No GCP operations.'
                    : 'The new Design starts empty. Save Cloud Storage placements explicitly; no bucket settings are invented.')));
    if (state.dialogOpen && !_wasOpen) _name.grabFocus();
    if (!state.dialogOpen && _wasOpen) _new.grabFocus();
    _wasOpen = state.dialogOpen;
  }

  void resize(Vector2 viewport) {
    _configuration.resize(viewport);
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
