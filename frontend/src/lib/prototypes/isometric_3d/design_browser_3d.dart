import 'dart:async' as async;
import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:godot_dart/godot_dart.dart';
import '../../domain/bloc/design/design_cubit.dart';
import '../../domain/models/design_browser_state.dart';
import '../../domain/models/design_summary.dart';
import 'workspace_3d.dart';

/// Native browser projection. The Cubit owns list, search, selection and load.
class DesignBrowser3D {
  DesignBrowser3D(this._owner, this._cubit) {
    _root = _control(root);
    _dialog = _control(dialog);
    _rows = _control(rows);
    _search = _owner.getNodeT<LineEdit>(search)!;
    _discard = _owner.getNodeT<CheckButton>(discard)!;
    for (final path in [cancel, close]) {
      _button(path).pressed.connect(_owner, () => _cubit?.cancel());
    }
    _button(confirm).pressed.connect(_owner, _submit);
    _button(retry).pressed.connect(_owner, () {
      if (_cubit != null) async.unawaited(_cubit.refreshDesigns());
    });
    _button(newDesign).pressed.connect(_owner, () => _cubit?.open());
    _button(previous).pressed.connect(
        _owner, () => _cubit?.changeDesignPage(_cubit.state.browser.page - 1));
    _button(next).pressed.connect(
        _owner, () => _cubit?.changeDesignPage(_cubit.state.browser.page + 1));
    _search.textChanged
        .connect(_owner, (value) => _cubit?.searchDesigns(value));
    _search.textSubmitted.connect(_owner, (_) => _submit());
    _discard.toggled
        .connect(_owner, (approved) => _cubit?.approveDiscard(approved));
    _dialog.minimumSizeChanged.connect(_owner, resize);
  }

  static const root = 'DesignLayer/DesignControls/DesignBrowser';
  static const dialog = '$root/Dialog';
  static const content = '$dialog/Content';
  static const search = '$content/Search';
  static const rows = '$content/Scroll/Rows';
  static const close = '$content/Heading/Close';
  static const cancel = '$content/Footer/Cancel';
  static const confirm = '$content/Footer/Open';
  static const retry = '$content/Recovery/Retry';
  static const newDesign = '$content/Recovery/NewDesign';
  static const previous = '$content/Pagination/Previous';
  static const next = '$content/Pagination/Next';
  static const discard = '$content/Discard';

  final Node _owner;
  final DesignCubit? _cubit;
  late final Control _root, _dialog, _rows;
  late final LineEdit _search;
  late final CheckButton _discard;
  final _buttons = <String, Button>{};
  List<DesignSummary> _rendered = const [];
  bool _wasOpen = false;
  bool get isOpen => _root.isVisibleInTree();
  Control _control(String path) => _owner.getNodeT<Control>(path)!;
  Button _button(String path) => _owner.getNodeT<Button>(path)!;

  void _submit() {
    if (_cubit != null && _cubit.state.canSubmit) {
      async.unawaited(_cubit.submit());
    }
  }

  void render(DesignState state) {
    final open = state.dialogOpen && state.mode == DesignDialogMode.open;
    _root.setVisible(open);
    if (!open) {
      if (_wasOpen && !state.modalOpen && !state.pending) {
        _button('${Workspace3D.header}/Rows/Actions/OpenDesign').grabFocus();
      }
      _wasOpen = false;
      return;
    }
    final browser = state.browser;
    final entries = browser.pageEntries;
    if (!const ListEquality<DesignSummary>().equals(entries, _rendered)) {
      for (final row in _buttons.values) {
        _rows.removeChild(row);
        row.queueFree();
      }
      _buttons.clear();
      _owner.getNodeT<ScrollContainer>('$content/Scroll')!.setVScroll(0);
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        final row = _button('$root/RowTemplate').duplicate()! as Button;
        row
          ..setName('Row_$index')
          ..setVisible(true);
        row
            .getNodeT<Label>('Margin/Content/Labels/Name')!
            .setText(entry.displayName);
        final date = _date(entry.updatedAtUtc);
        row.getNodeT<Label>('Margin/Content/Labels/Updated')!.setText(date);
        row.setTooltipText('${entry.displayName}\n$date');
        _rows.addChild(row);
        _buttons[entry.id] = row;
        row.pressed.connect(_owner, () {
          _cubit?.selectDesign(entry.id);
          // Pressing the already-selected toggle must leave it highlighted,
          // even when the Cubit correctly suppresses an identical state.
          _syncSelection(_cubit?.state.openId ?? '');
        });
      }
      _rendered = List.unmodifiable(entries);
    }
    _syncSelection(state.openId);
    for (final row in _buttons.values) {
      row.setDisabled(state.pending);
    }
    if (_search.getText() != browser.query) _search.setText(browser.query);
    _search.setEditable(
        !state.pending && browser.status != DesignListStatus.failure);
    final ready = browser.status == DesignListStatus.ready;
    final failed = browser.status == DesignListStatus.failure;
    final matches = browser.matches.length;
    final status = state.pending
        ? 'Opening Design… Your current workspace is preserved.'
        : failed
            ? browser.error ?? 'Unable to load Designs. Please retry.'
            : !ready
                ? 'Loading designs…'
                : browser.entries.isEmpty
                    ? 'No designs available'
                    : matches == 0
                        ? 'No matching designs'
                        : '';
    _owner.getNodeT<Label>('$content/Status')!
      ..setText(status)
      ..setTooltipText(status)
      ..setVisible(status.isNotEmpty);
    _button(retry)
      ..setVisible(failed)
      ..setDisabled(state.pending);
    _button(newDesign)
      ..setVisible(ready && browser.entries.isEmpty)
      ..setDisabled(state.pending);
    _control('$content/Recovery')
        .setVisible(failed || ready && browser.entries.isEmpty);
    _owner.getNodeT<Label>('$content/Pagination/Count')!.setText(!ready
        ? ''
        : browser.pageCount > 1
            ? '${browser.page * DesignBrowserState.pageSize + 1}–${math.min((browser.page + 1) * DesignBrowserState.pageSize, matches)} of $matches designs'
            : '$matches ${matches == 1 ? "design" : "designs"} available');
    _button(previous)
      ..setVisible(browser.pageCount > 1)
      ..setDisabled(state.pending || browser.page == 0);
    _button(next)
      ..setVisible(browser.pageCount > 1)
      ..setDisabled(state.pending || browser.page + 1 >= browser.pageCount);
    _discard
      ..setVisible(state.requiresDiscard)
      ..setDisabled(state.pending)
      ..setPressedNoSignal(state.discardApproved);
    final error = state.error;
    _owner.getNodeT<Label>('$content/Feedback')!
      ..setText(error ?? '')
      ..setTooltipText(error ?? '')
      ..setVisible(error != null);
    _button(confirm)
      ..setDisabled(!state.canSubmit)
      ..setText(state.pending ? 'Opening…' : 'Open Design');
    _button(cancel).setDisabled(state.pending);
    _button(close).setDisabled(state.pending);
    resize();
    if (!_wasOpen) _search.grabFocus();
    _wasOpen = true;
  }

  void _syncSelection(String id) {
    for (final entry in _buttons.entries) {
      entry.value.setPressedNoSignal(entry.key == id);
    }
  }

  static String _date(DateTime? value) {
    if (value == null) return 'Update date unavailable';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final utc = value.toUtc();
    return 'Updated ${months[utc.month - 1]} ${utc.day}, ${utc.year}';
  }

  void resize() {
    final viewport = _owner.getViewport()!.getVisibleRect().size;
    final width = math.min(600.0, viewport.x - 32);
    final height = math.min(560.0, viewport.y - 32);
    _dialog
      ..setSize(Vector2(x: width, y: height))
      ..setPosition(
          Vector2(x: (viewport.x - width) / 2, y: (viewport.y - height) / 2));
  }

  bool handleInput(InputEvent? event) {
    if (!isOpen) return false;
    if (event is InputEventKey && event.isPressed() && !event.isEcho()) {
      if (event.getKeycode() == Key.escape) {
        _cubit?.cancel();
        return true;
      }
      final candidates = <Control>[
        _button(close),
        _search,
        ..._buttons.values,
        _button(previous),
        _button(next),
        _button(retry),
        _button(newDesign),
        _discard,
        _button(cancel),
        _button(confirm)
      ];
      final focus = candidates
          .where((c) =>
              c.isVisibleInTree() &&
              c.getFocusMode() != ControlFocusMode.focusNone &&
              (c is! BaseButton || !c.isDisabled()) &&
              (c is! LineEdit || c.isEditable()))
          .toList();
      final current = focus.indexWhere((c) => c.hasFocus());
      if (event.getKeycode() == Key.tab) {
        if (focus.isNotEmpty) {
          final next = current < 0
              ? (event.isShiftPressed() ? focus.length - 1 : 0)
              : (current + (event.isShiftPressed() ? -1 : 1)) % focus.length;
          focus[next].grabFocus();
        }
        return true;
      }
      if (current < 0) {
        if (focus.isNotEmpty) focus.first.grabFocus();
        return true;
      }
    }
    if (event is InputEventMouseButton) {
      return !_dialog.getGlobalRect().hasPoint(event.getPosition());
    }
    if (event is InputEventMouseMotion) {
      return !_dialog.getGlobalRect().hasPoint(event.getPosition());
    }
    return false;
  }
}
