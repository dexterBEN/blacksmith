import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import '../../../data/repositories/design_repository.dart';
import '../../../data/repositories/resource_repository.dart';
import '../../models/design.dart';
import '../../models/grid_position.dart';
import '../../models/persisted_resource.dart';
import '../../models/resource_kind.dart';
import '../isomap_grid/isomap_grid_bloc.dart';
import '../isomap_grid/isomap_grid_event.dart';
import '../isomap_grid/isomap_grid_state.dart';

enum DesignStatus { editing, submitting, failure, saving, loading }

enum DesignDialogMode { create, open }

class DesignState extends Equatable {
  const DesignState(
      {this.active,
      this.dialogOpen = false,
      this.name = '',
      this.status = DesignStatus.editing,
      this.error,
      this.requiresDiscard = false,
      this.discardApproved = false,
      this.mode = DesignDialogMode.create,
      this.openId = '',
      this.canSave = false,
      this.saved = false,
      this.saveUncertain = false,
      this.persistenceMessage = 'Local placements only'});
  final Design? active;
  final bool dialogOpen;
  final String name;
  final DesignStatus status;
  final String? error;
  final bool requiresDiscard, discardApproved;
  final DesignDialogMode mode;
  final String openId;
  final bool canSave, saved, saveUncertain;
  final String persistenceMessage;
  bool get pending =>
      status == DesignStatus.submitting ||
      status == DesignStatus.saving ||
      status == DesignStatus.loading;
  bool get canSubmit =>
      dialogOpen &&
      !pending &&
      (mode == DesignDialogMode.create
          ? Design.validateName(name) == null
          : PersistedResource.validId(openId.trim())) &&
      (!requiresDiscard || discardApproved);

  DesignState copyWith(
          {Design? active,
          bool? dialogOpen,
          String? name,
          DesignStatus? status,
          String? error,
          bool? requiresDiscard,
          bool? discardApproved,
          DesignDialogMode? mode,
          String? openId,
          bool? canSave,
          bool? saved,
          bool? saveUncertain,
          String? persistenceMessage}) =>
      DesignState(
          active: active ?? this.active,
          dialogOpen: dialogOpen ?? this.dialogOpen,
          name: name ?? this.name,
          status: status ?? this.status,
          error: error,
          requiresDiscard: requiresDiscard ?? this.requiresDiscard,
          discardApproved: discardApproved ?? this.discardApproved,
          mode: mode ?? this.mode,
          openId: openId ?? this.openId,
          canSave: canSave ?? this.canSave,
          saved: saved ?? this.saved,
          saveUncertain: saveUncertain ?? this.saveUncertain,
          persistenceMessage: persistenceMessage ?? this.persistenceMessage);
  @override
  List<Object?> get props => [
        active,
        dialogOpen,
        name,
        status,
        error,
        requiresDiscard,
        discardApproved,
        mode,
        openId,
        canSave,
        saved,
        saveUncertain,
        persistenceMessage
      ];
}

/// Single coordination point for explicit persistence and local-grid hydration.
/// Repositories own I/O; the grid BLoC remains the only visible placement state.
class DesignCubit extends Cubit<DesignState> {
  DesignCubit(this._repository, this._grid, {ResourceRepository? resources})
      : _resources = resources,
        super(const DesignState()) {
    _observed = _grid.state.tiles;
    _subscription = _grid.stream.listen((grid) {
      if (!_equal.equals(_observed, grid.tiles)) {
        _observed = grid.tiles;
        if (!isClosed && !state.pending) _feedback();
      }
    });
  }
  final DesignRepository _repository;
  final ResourceRepository? _resources;
  final IsomapGridBloc _grid;
  late final StreamSubscription<IsomapGridState> _subscription;
  late Map<GridPos, ResourceKind> _observed;
  Map<GridPos, ResourceKind>? _confirmed;
  PersistedResource? _record;
  String? _saveProblem;
  final _attempts = <String, ({GridPos position, String? id})>{};
  static const _equal = MapEquality<GridPos, ResourceKind>();

  bool get supportsPersistence => _resources != null;
  bool get _dirty => _confirmed == null
      ? _grid.state.tiles.isNotEmpty
      : !_equal.equals(_confirmed, _grid.state.tiles);
  bool get _supported =>
      _grid.state.tiles.length == 1 &&
      _grid.state.tiles.values.single == ResourceKind.cloudStorage;
  void _feedback() {
    if (isClosed) return;
    final uncertain = state.active != null &&
        _attempts.containsKey(state.active!.id.toLowerCase());
    final saved = state.active != null && _confirmed != null && !_dirty;
    final enabled = _resources != null &&
        state.active != null &&
        (uncertain || _supported && !saved && _record == null);
    final message = _saveProblem != null
        ? '${_saveProblem!}${uncertain ? " Outcome unknown; Check Save is read only." : ""}'
        : (state.active == null
            ? 'Create or open a Design to save.'
            : uncertain
                ? 'Save outcome unknown. Check Save reads the backend without another POST.'
                : saved
                    ? (_record == null
                        ? 'Empty Design · No resource saved'
                        : 'Saved · Verified by backend read-back')
                    : _grid.state.tiles.isEmpty
                        ? 'No placement to save.'
                        : !_supported
                            ? 'Unsaved · Only one Cloud Storage cube can be saved in this workflow.'
                            : _record != null
                                ? 'Unsaved · Replacement and deletion synchronization are not supported.'
                                : 'Unsaved · Save the Cloud Storage placement explicitly.');
    emit(state.copyWith(
        canSave: enabled && !state.pending && !state.dialogOpen,
        saved: saved && !uncertain,
        saveUncertain: uncertain,
        persistenceMessage: message));
  }

  void open() {
    if (isClosed || state.pending) return;
    emit(state.copyWith(
        dialogOpen: true,
        name: '',
        error: null,
        mode: DesignDialogMode.create,
        status: DesignStatus.editing,
        requiresDiscard: _grid.state.tiles.isNotEmpty,
        discardApproved: false));
    _feedback();
  }

  void openExisting() {
    if (isClosed || state.pending || _resources == null) return;
    emit(state.copyWith(
        dialogOpen: true,
        openId: '',
        error: null,
        mode: DesignDialogMode.open,
        status: DesignStatus.editing,
        requiresDiscard: _dirty,
        discardApproved: false));
    _feedback();
  }

  void changeName(String value) {
    if (isClosed || !state.dialogOpen || state.pending) return;
    emit(state.copyWith(
        name: value,
        status: DesignStatus.editing,
        error: Design.validateName(value)));
  }

  void changeOpenId(String value) {
    if (isClosed || !state.dialogOpen || state.pending) return;
    emit(state.copyWith(
        openId: value,
        status: DesignStatus.editing,
        error: PersistedResource.validId(value.trim())
            ? null
            : 'Enter a valid Design ID.'));
  }

  void approveDiscard(bool approved) {
    if (!isClosed && state.dialogOpen && !state.pending) {
      emit(state.copyWith(discardApproved: approved));
    }
  }

  void cancel() {
    if (isClosed || state.pending) return;
    emit(state.copyWith(dialogOpen: false, status: DesignStatus.editing));
    _feedback();
  }

  Future<void> submit() async {
    if (isClosed || !state.dialogOpen || state.pending) return;
    if (state.mode == DesignDialogMode.open) return _load();
    final invalid = Design.validateName(state.name);
    final placements = _grid.state.tiles.isNotEmpty;
    if (invalid != null || placements && !state.discardApproved) {
      emit(state.copyWith(
          error: invalid ?? 'Confirm clearing the unsaved local placements.',
          requiresDiscard: placements));
      return;
    }
    final name = state.name.trim();
    emit(state.copyWith(status: DesignStatus.submitting, canSave: false));
    try {
      final design = await _repository.create(name);
      if (isClosed) return;
      _confirmed = const {};
      _record = null;
      _saveProblem = null;
      await _hydrate(const {});
      if (isClosed) return;
      emit(DesignState(active: design));
      _feedback();
    } on DesignFailure catch (failure) {
      if (!isClosed) {
        emit(state.copyWith(
            status: DesignStatus.failure, error: failure.message));
      }
    } on Exception {
      if (!isClosed) {
        emit(state.copyWith(
            status: DesignStatus.failure,
            error:
                'Design creation could not be confirmed. Check the API before submitting again.'));
      }
    }
  }

  Future<void> _hydrate(Map<GridPos, ResourceKind> tiles) async {
    if (_equal.equals(_grid.state.tiles, tiles) &&
        _grid.state.selected == null) {
      return;
    }
    final applied = _grid.stream
        .firstWhere((s) => _equal.equals(s.tiles, tiles) && s.selected == null);
    _grid.add(RestoreDesignResources(tiles));
    await applied;
  }

  bool _matches(PersistedResource record, GridPos position, {String? id}) =>
      record.position == position &&
      record.type == PersistedResource.storageType &&
      (id == null || record.id == id);
  Future<List<PersistedResource>> _read(String id) => _resources!
      .listForDesign(id, rows: _grid.state.rows, cols: _grid.state.cols);
  void _validateAttempt(String id, List<PersistedResource> records) {
    final attempt = _attempts[id.toLowerCase()];
    if (attempt != null &&
        (records.length != 1 ||
            !_matches(records.single, attempt.position, id: attempt.id))) {
      throw const ResourceFailure(
          'Save outcome remains unknown. No new write will be sent. '
          'Wait and use Check Save again.',
          ambiguous: true);
    }
  }

  Future<void> _load() async {
    final id = state.openId.trim().toLowerCase();
    if (!PersistedResource.validId(id)) {
      emit(state.copyWith(error: 'Enter a valid Design ID.'));
      return;
    }
    if (_dirty && !state.discardApproved) {
      emit(state.copyWith(
          requiresDiscard: true,
          error:
              'Confirm replacing unsaved local placements only after a successful load.'));
      return;
    }
    emit(state.copyWith(status: DesignStatus.loading, canSave: false));
    try {
      final design = await _repository.getById(id);
      if (isClosed) return;
      final records = await _read(id);
      if (isClosed) return;
      _validateAttempt(id, records);
      if (_dirty && !state.discardApproved) {
        emit(state.copyWith(
            status: DesignStatus.failure,
            requiresDiscard: true,
            error:
                'Local placements changed while loading. Confirm replacement and open again.'));
        return;
      }
      final tiles = {
        for (final r in records) r.position: ResourceKind.cloudStorage
      };
      await _hydrate(tiles);
      if (isClosed) return;
      _attempts.remove(id);
      _confirmed = Map.unmodifiable(tiles);
      _record = records.isEmpty ? null : records.single;
      _saveProblem = null;
      emit(DesignState(active: design));
      _feedback();
    } on Exception catch (failure) {
      if (!isClosed) {
        emit(state.copyWith(
            status: DesignStatus.failure,
            error: failure is DesignFailure
                ? failure.message
                : failure is ResourceFailure
                    ? failure.message
                    : 'Unable to open the Design. Local placements are preserved.'));
      }
    }
  }

  Future<void> save() async {
    if (isClosed ||
        state.pending ||
        state.dialogOpen ||
        !state.canSave ||
        _resources == null) {
      return;
    }
    final design = state.active!;
    final snapshot = Map<GridPos, ResourceKind>.unmodifiable(_grid.state.tiles);
    final oldAttempt = _attempts[design.id.toLowerCase()];
    if (oldAttempt == null &&
        (!_supported ||
            _record != null ||
            _equal.equals(_confirmed, snapshot))) {
      _feedback();
      return;
    }
    final position = oldAttempt?.position ?? snapshot.keys.single;
    _saveProblem = null;
    emit(state.copyWith(
        status: DesignStatus.saving,
        canSave: false,
        saved: false,
        persistenceMessage:
            oldAttempt == null ? 'Saving…' : 'Checking Save… (read only)'));
    try {
      // All preflight reads finish before the single possible non-idempotent POST.
      await _repository.getById(design.id);
      if (isClosed) return;
      var records = await _read(design.id);
      if (isClosed) return;
      if (oldAttempt != null) {
        _validateAttempt(design.id, records);
      } else if (records.isEmpty) {
        _attempts[design.id.toLowerCase()] = (position: position, id: null);
        try {
          final created = await _resources.createCloudStorage(
              design.id, position,
              rows: _grid.state.rows, cols: _grid.state.cols);
          if (isClosed) return;
          _attempts[design.id.toLowerCase()] =
              (position: position, id: created.id);
        } on ResourceFailure catch (failure) {
          if (!failure.ambiguous) _attempts.remove(design.id.toLowerCase());
          rethrow;
        }
        // A 201 alone never sets confirmed/saved state.
        await _repository.getById(design.id);
        if (isClosed) return;
        records = await _read(design.id);
        if (isClosed) return;
        _validateAttempt(design.id, records);
      }
      if (records.length != 1 || !_matches(records.single, position)) {
        throw const ResourceFailure(
            'The backend snapshot does not match this placement. '
            'Existing resources were not overwritten.');
      }
      if (isClosed) return;
      _record = records.single;
      _confirmed = Map.unmodifiable({position: ResourceKind.cloudStorage});
      _attempts.remove(design.id.toLowerCase());
    } on Exception catch (failure) {
      if (!isClosed) {
        _saveProblem = failure is DesignFailure
            ? failure.message
            : failure is ResourceFailure
                ? failure.message
                : 'Save could not be verified. Use Check Save before another write.';
      }
    } finally {
      if (!isClosed) {
        emit(state.copyWith(status: DesignStatus.editing));
        _feedback();
      }
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
