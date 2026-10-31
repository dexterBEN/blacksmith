import '../../domain/models/grid_position.dart';
import '../../domain/models/resource_kind.dart';

class ResourcePickerFailure implements Exception {
  const ResourcePickerFailure(this.message);
  final String message;
}

/// View-only draft. The grid BLoC remains the placement/selection authority.
class ResourcePickerDraft {
  GridPos? target;
  ResourceKind? chosen;
  bool active = false, pending = false, invalidated = false;
  String? error;
  int _generation = 0;

  void open(GridPos? position) {
    _generation++;
    target = position;
    chosen = null;
    active = true;
    pending = invalidated = false;
    error = null;
  }

  void close() {
    _generation++;
    active = pending = false;
    chosen = null;
    error = null;
  }

  void observe(GridPos? current) {
    if (active && current != target) {
      invalidated = true;
      error =
          'The selected tile changed. Close Resources and select a tile again.';
    }
  }

  void choose(ResourceKind kind) {
    if (!active || pending || invalidated) return;
    chosen = kind;
    error = null;
  }

  bool canConfirm({required bool eligible}) =>
      active &&
      !pending &&
      !invalidated &&
      target != null &&
      chosen != null &&
      eligible;

  Future<bool> confirm(
      {required bool eligible,
      required Future<void> Function(ResourceKind, GridPos) place}) async {
    if (!canConfirm(eligible: eligible)) return false;
    pending = true;
    error = null;
    final generation = _generation;
    final kind = chosen!, position = target!;
    try {
      await place(kind, position);
      return generation == _generation && active;
    } on ResourcePickerFailure catch (failure) {
      if (generation == _generation) error = failure.message;
    } catch (_) {
      if (generation == _generation) {
        error = 'Placement could not be completed. Please try again.';
      }
    } finally {
      if (generation == _generation) pending = false;
    }
    return false;
  }
}
