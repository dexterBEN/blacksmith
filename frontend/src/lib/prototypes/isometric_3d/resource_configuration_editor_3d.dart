import 'dart:async' as async;
import 'dart:math' as math;
import 'package:godot_dart/godot_dart.dart';
import '../../domain/bloc/design/design_cubit.dart';

/// Native presentation for the single draft held by the shared DesignCubit.
/// No HTTP, JSON parsing, placement state or additional controller lifecycle.
class ResourceConfigurationEditor3D {
  ResourceConfigurationEditor3D(Node owner, this._cubit) {
    final packed = ResourceLoader.singleton.load(
            'res://scenes/isometric_3d/resource_configuration_controls.tscn')!
        as PackedScene;
    final controls = packed.instantiate()!;
    owner.getNodeT<Node>('DesignLayer')!.addChild(controls);
    _shade = controls.getNodeT<ColorRect>('Shade')!;
    _dialog = _shade.getNodeT<Panel>('Dialog')!;
    _json = _dialog.getNodeT<TextEdit>('Json')!;
    _save = _dialog.getNodeT<Button>('Save')!;
    _cancel = _dialog.getNodeT<Button>('Cancel')!;
    _close = _dialog.getNodeT<Button>('Close')!;
    _feedback = _dialog.getNodeT<Label>('FeedbackScroll/Feedback')!;
    _json.textChanged.connect(owner, () {
      if (!_updating) _cubit?.changeResourceConfigurationText(_json.getText());
    });
    _cancel.pressed.connect(owner, () => _cubit?.cancelResourceConfiguration());
    _close.pressed.connect(owner, () => _cubit?.cancelResourceConfiguration());
    _save.pressed.connect(owner, () {
      if (_cubit != null) async.unawaited(_cubit.saveResourceConfiguration());
    });
  }
  final DesignCubit? _cubit;
  late final ColorRect _shade;
  late final Panel _dialog;
  late final TextEdit _json;
  late final Button _save, _cancel, _close;
  late final Label _feedback;
  bool _updating = false, _wasOpen = false;

  void render(DesignState state) {
    final draft = state.configurationDraft;
    _shade.setVisible(draft != null);
    if (draft == null) {
      _wasOpen = false;
      return;
    }
    _updating = true;
    if (_json.getText() != draft.text) _json.setText(draft.text);
    _updating = false;
    _json.setEditable(!state.pending && !draft.uncertain);
    _save
      ..setDisabled(state.pending)
      ..setText(state.pending
          ? 'Please wait…'
          : draft.uncertain
              ? 'Check Save'
              : 'Save configuration');
    _cancel.setDisabled(state.pending);
    _close.setDisabled(state.pending);
    _dialog.getNodeT<Label>('Target')!.setText(
        'Design: ${draft.designId}\nTile: (${draft.position.row}, ${draft.position.col}) · '
        '${draft.resource.id == null ? "New resource" : "Resource revision ${draft.resource.revision}"}');
    final legacy =
        draft.original != null && draft.original!.configuration == null;
    _dialog.getNodeT<Label>('Notice')!.setText(legacy
        ? 'Unconfigured resource. Enter projectId, bucketName and location. Save only; no deployment. Never paste credentials.'
        : draft.original == null
            ? 'Example identifiers: replace projectId and bucketName. Save only; no deployment. Never paste credentials.'
            : 'Edit this saved configuration. Save only; no deployment. Never paste credentials.');
    _feedback.setText(state.pending
        ? (draft.uncertain
            ? 'Checking the original Resource ID (read only)…'
            : 'Saving configuration… The grid changes only after confirmation.')
        : '${draft.error ?? "Ready. The backend validates and normalizes the v1 document."}'
            '${draft.uncertain ? "\nOutcome unknown. Check Save only reads the original Resource. Closing keeps the recovery guard." : ""}');
    if (!_wasOpen) _json.grabFocus();
    _wasOpen = true;
  }

  bool handleInput(InputEvent? event) {
    if (_cubit?.state.configurationDraft == null ||
        event is! InputEventKey ||
        !event.isPressed() ||
        event.getKeycode() != Key.escape) {
      return false;
    }
    _cubit?.cancelResourceConfiguration();
    return true;
  }

  void resize(Vector2 viewport) {
    final width = math.min(760.0, viewport.x - 32);
    final height = math.min(640.0, viewport.y - 32);
    _dialog
      ..setPosition(
          Vector2(x: (viewport.x - width) / 2, y: (viewport.y - height) / 2))
      ..setSize(Vector2(x: width, y: height));
    void place(String name, double x, double y, double w, double h) {
      _dialog.getNodeT<Control>(name)!
        ..setPosition(Vector2(x: x, y: y))
        ..setSize(Vector2(x: w, y: h));
    }

    place('Title', 16, 12, width - 80, 32);
    place('Close', width - 52, 12, 36, 32);
    place('Target', 16, 52, width - 32, 44);
    place('Notice', 16, 104, width - 32, 48);
    place('Json', 16, 160, width - 32, height - 304);
    place('FeedbackScroll', 16, height - 132, width - 32, 68);
    _feedback.setCustomMinimumSize(Vector2(x: width - 64, y: 0));
    place('Cancel', width - 350, height - 52, 130, 36);
    place('Save', width - 208, height - 52, 192, 36);
  }
}
