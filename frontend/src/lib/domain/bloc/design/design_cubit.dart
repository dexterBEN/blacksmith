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
import '../../models/placed_resource.dart';
import '../../models/resource_configuration_draft.dart';
import '../isomap_grid/isomap_grid_bloc.dart';
import '../isomap_grid/isomap_grid_event.dart';
import '../isomap_grid/isomap_grid_state.dart';

enum DesignStatus { editing, submitting, failure, saving, loading }

enum DesignDialogMode { create, open }

class DesignState extends Equatable {
  const DesignState(
      {this.active,
      this.configurationDraft,
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
  final ResourceConfigurationDraft? configurationDraft;
  bool get modalOpen => dialogOpen || configurationDraft != null;
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
          ResourceConfigurationDraft? configurationDraft,
          bool clearConfigurationDraft = false,
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
          configurationDraft: clearConfigurationDraft
              ? null
              : configurationDraft ?? this.configurationDraft,
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
        configurationDraft,
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
    _observed = _grid.state.resources;
    _subscription = _grid.stream.listen((grid) {
      if (!_equal.equals(_observed, grid.resources)) {
        _observed = grid.resources;
        if (!isClosed && !state.pending) _feedback();
      }
    });
  }
  final DesignRepository _repository;
  final ResourceRepository? _resources;
  final IsomapGridBloc _grid;
  late final StreamSubscription<IsomapGridState> _subscription;
  late Map<GridPos, PlacedResource> _observed;
  Map<GridPos, PlacedResource>? _confirmed;
  String? _saveProblem;
  final _attempts = <String, Map<String, _PendingResourceSave>>{};
  static const _equal = MapEquality<GridPos, PlacedResource>();
  bool get supportsPersistence => _resources != null;
  bool get _dirty => _confirmed == null
      ? _grid.state.resources.isNotEmpty
      : !_equal.equals(_confirmed, _grid.state.resources);
  bool get _supported => _grid.state.resources.values.every((r) =>
      r.kind == ResourceKind.cloudStorage &&
      (r.configuration == null || r.configuration!.schemaVersion == 1));
  bool get _unsupportedRemoval =>
      _confirmed?.entries.any(
          (entry) => _grid.state.resources[entry.key]?.id != entry.value.id) ??
      false;
  Map<String, _PendingResourceSave> _pending(String designId) =>
      _attempts.putIfAbsent(designId.toLowerCase(), () => {});

  void _feedback() {
    if (isClosed) return;
    final uncertain = state.active != null &&
        (_attempts[state.active!.id.toLowerCase()]?.isNotEmpty ?? false);
    final saved = state.active != null &&
        _confirmed != null &&
        !_dirty &&
        !uncertain &&
        state.configurationDraft == null;
    final count = _grid.state.resources.length;
    final unconfigured = _grid.state.resources.values
        .where((r) => r.configuration == null)
        .length;
    final message = _saveProblem != null
        ? '${_saveProblem!}${uncertain ? " Outcome unknown; Check Save is read only." : ""}'
        : state.active == null
            ? 'Create or open a Design to save.'
            : uncertain
                ? 'Save outcome unknown. Check Save reads the backend without another write.'
                : saved
                    ? (count == 0
                        ? 'Empty Design · No resource saved'
                        : 'Saved placements: $count · Unconfigured: $unconfigured · ${_deploymentSummary()}')
                    : _unsupportedRemoval
                        ? 'Unsaved · Removing or replacing persisted resources is not supported. Open to restore them.'
                        : !_supported
                            ? 'Unsaved · Only Cloud Storage persistence is supported; other kinds remain local.'
                            : count == 0
                                ? 'No placement to save.'
                                : 'Unsaved · Save Cloud Storage placements explicitly. Configuration is not invented.';
    emit(state.copyWith(
        canSave: _resources != null &&
            state.active != null &&
            (uncertain ||
                _supported && !_unsupportedRemoval && _dirty && count > 0) &&
            !state.pending &&
            !state.modalOpen,
        saved: saved,
        saveUncertain: uncertain,
        persistenceMessage: message));
  }

  String _deploymentSummary() {
    final outcomes =
        _grid.state.resources.values.where((r) => r.deployment != null);
    if (outcomes.isEmpty) return 'No deployment';
    return outcomes.map((r) => r.deployment!.describe(r.revision)).join(' | ');
  }

  bool get deploymentEnabled => _resources?.deploymentEnabled ?? false;
  String get deploymentReview {
    final draft = state.configurationDraft;
    if (draft == null) return '';
    try {
      return _resources!.deploymentReview(draft.text);
    } on ResourceFailure {
      return 'Enter a valid configuration to review the target.';
    }
  }

  bool get validDeploymentTarget {
    try {
      _resources!.parseConfiguration(state.configurationDraft!.text);
      return true;
    } on Exception {
      return false;
    }
  }

  bool get configurationMatchesSaved {
    final draft = state.configurationDraft;
    if (draft == null) return false;
    try {
      return _resources!.parseConfiguration(draft.text) ==
          draft.resource.configuration;
    } on ResourceFailure {
      return false;
    }
  }

  bool get checksDeployment {
    final draft = state.configurationDraft;
    if (draft == null) return false;
    final previous = draft.resource.deployment;
    return draft.deploymentCommand && draft.uncertain ||
        configurationMatchesSaved &&
            previous != null &&
            (previous.status == 'unknown' ||
                previous.status == 'succeeded' ||
                previous.status == 'pending' && previous.code != 'queued');
  }

  bool get retriesDeployment =>
      configurationMatchesSaved &&
      state.configurationDraft?.resource.deployment != null &&
      !checksDeployment;

  void approveDeployment(bool approved) {
    final draft = state.configurationDraft;
    if (draft == null ||
        state.pending ||
        draft.uncertain ||
        !validDeploymentTarget) {
      return;
    }
    emit(state.copyWith(configurationDraft: draft.copyWith(consent: approved)));
  }

  void open() {
    if (isClosed || state.pending || state.configurationDraft != null) return;
    emit(state.copyWith(
        dialogOpen: true,
        name: '',
        error: null,
        mode: DesignDialogMode.create,
        status: DesignStatus.editing,
        requiresDiscard: _grid.state.resources.isNotEmpty,
        discardApproved: false));
    _feedback();
  }

  void openExisting() {
    if (isClosed ||
        state.pending ||
        state.configurationDraft != null ||
        _resources == null) {
      return;
    }
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
    final placements = _grid.state.resources.isNotEmpty;
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
      await _hydrate(const {});
      if (isClosed) return;
      _confirmed = const {};
      _saveProblem = null;
      emit(DesignState(active: design));
      _feedback();
    } on Exception catch (failure) {
      if (!isClosed) {
        emit(state.copyWith(
            status: DesignStatus.failure,
            error: failure is DesignFailure
                ? failure.message
                : 'Design creation could not be confirmed. Check the API before submitting again.'));
      }
    }
  }

  Future<void> _hydrate(Map<GridPos, PlacedResource> resources) async {
    if (_grid.isClosed) {
      throw const ResourceFailure('The editor state is closed.');
    }
    final event = RestoreDesignResources.resources(resources);
    _grid.add(event);
    if (!await event.applied.future) {
      throw const ResourceFailure(
          'The complete Design snapshot could not be restored.');
    }
  }

  Future<List<PersistedResource>> _read(String id) => _resources!
      .listForDesign(id, rows: _grid.state.rows, cols: _grid.state.cols);

  bool _matches(PersistedResource row, _PendingResourceSave attempt) =>
      row.position == attempt.position &&
      row.type == attempt.sent.type &&
      row.name == attempt.sent.name &&
      row.configuration == attempt.sent.configuration &&
      row.configurationState ==
          (attempt.sent.configuration == null ? 'absent' : 'validated') &&
      (attempt.sent.catalogId == null ||
          row.catalogId == attempt.sent.catalogId) &&
      (attempt.ack == null ||
          row.id == attempt.ack!.id &&
              row.revision == attempt.ack!.revision &&
              (attempt.ack!.catalogId == null ||
                  row.catalogId == attempt.ack!.catalogId));

  PersistedResource _resolve(
      _PendingResourceSave attempt, List<PersistedResource> rows) {
    final id = (attempt.ack?.id ??
            attempt.sent.id ??
            (attempt.sent.configuration != null ? attempt.sent.localKey : null))
        ?.toLowerCase();
    final candidates = rows
        .where((row) => id != null
            ? row.id == id
            : !attempt.beforeIds.contains(row.id) &&
                row.position == attempt.position &&
                row.revision == 1)
        .toList();
    if (candidates.length != 1 || !_matches(candidates.single, attempt)) {
      throw const ResourceFailure(
          'Save outcome remains unknown or conflicts with backend state. No new write will be sent. Use Check Save again.',
          ambiguous: true);
    }
    return candidates.single;
  }

  void _verifyBaseline(List<PersistedResource> rows,
      {Set<String> replacing = const {}}) {
    final baseline = _confirmed ?? const <GridPos, PlacedResource>{};
    for (final entry in baseline.entries) {
      final resource = entry.value;
      if (replacing.contains(resource.id)) continue;
      final found = rows.where((r) => r.id == resource.id).toList();
      if (found.length != 1 ||
          !PlacedResource.fromPersisted(found.single,
                  localKey: resource.localKey)
              .sameSavedContent(resource) ||
          found.single.position != entry.key) {
        throw const ResourceFailure(
            'The backend Design changed. Open it before saving; local changes are preserved.',
            code: 'snapshot_changed');
      }
    }
    final allowed = {
      ...baseline.values.map((r) => r.id).whereType<String>(),
      ...replacing
    };
    if (rows.any((r) => !allowed.contains(r.id))) {
      throw const ResourceFailure(
          'The backend contains unrelated resources. Open the Design before saving; none were overwritten.',
          code: 'unrelated_resources');
    }
  }

  Future<void> _accept(
      _PendingResourceSave attempt, PersistedResource record) async {
    if (attempt.configurationDialog) {
      if (_grid.isClosed || isClosed || state.active?.id != record.designId) {
        throw const ResourceFailure(
            'Saved in the backend, but the active Design changed. Open the original Design to restore it.',
            ambiguous: true);
      }
      final event = ApplyConfiguredResource(
          attempt.position, attempt.original, attempt.sent, record);
      _grid.add(event);
      if (!await event.applied.future) {
        throw const ResourceFailure(
            'Saved in the backend, but the captured tile changed. Open the Design to restore it.',
            ambiguous: true);
      }
      _confirmed = Map.unmodifiable({
        ...?_confirmed,
        attempt.position: PlacedResource.fromPersisted(record,
            localKey: attempt.sent.localKey)
      });
      return;
    }
    _confirmed = Map.unmodifiable({
      ...?_confirmed,
      attempt.position:
          PlacedResource.fromPersisted(record, localKey: attempt.sent.localKey)
    });
    if (_grid.isClosed || isClosed) return;
    final event = ConfirmResourceSaved(attempt.position, attempt.sent, record);
    _grid.add(event);
    await event.applied.future;
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
      final rows = await _read(id);
      if (isClosed) return;
      for (final attempt
          in (_attempts[id]?.values ?? <_PendingResourceSave>[])) {
        _resolve(attempt, rows);
      }
      if (_dirty && !state.discardApproved) {
        emit(state.copyWith(
            status: DesignStatus.failure,
            requiresDiscard: true,
            error:
                'Local placements changed while loading. Confirm replacement and open again.'));
        return;
      }
      final resources = {
        for (final row in rows) row.position: PlacedResource.fromPersisted(row)
      };
      await _hydrate(resources);
      if (isClosed) return;
      _confirmed = Map.unmodifiable(resources);
      _attempts.remove(id);
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
        state.modalOpen ||
        !state.canSave ||
        _resources == null) {
      return;
    }
    final design = state.active!;
    final snapshot =
        Map<GridPos, PlacedResource>.unmodifiable(_grid.state.resources);
    final attempts = _pending(design.id);
    final checking = attempts.isNotEmpty;
    _saveProblem = null;
    emit(state.copyWith(
        status: DesignStatus.saving,
        canSave: false,
        saved: false,
        persistenceMessage:
            checking ? 'Checking Save… (read only)' : 'Saving placements…'));
    try {
      await _repository.getById(design.id);
      if (isClosed) return;
      var rows = await _read(design.id);
      if (isClosed) return;
      if (checking) {
        final resolved = {
          for (final entry in attempts.entries)
            entry.key: _resolve(entry.value, rows)
        };
        _verifyBaseline(rows,
            replacing: resolved.values.map((r) => r.id).toSet());
        for (final key in resolved.keys) {
          await _accept(attempts[key]!, resolved[key]!);
          if (isClosed) return;
          attempts.remove(key);
        }
        return; // Check Save never starts another write, even after recovery.
      }
      _verifyBaseline(rows);
      for (final entry in snapshot.entries) {
        final position = entry.key, intent = entry.value;
        if (_confirmed?[position] == intent) continue;
        if (intent.id != null && intent.configuration == null) {
          throw const ResourceFailure(
              'Editing, replacing or deleting persisted metadata-only resources is not supported. Open to restore them.');
        }
        final attempt = _PendingResourceSave(
            position, intent, rows.map((r) => r.id).toSet());
        attempts[intent.localKey] = attempt;
        try {
          attempt.ack = intent.configuration == null
              ? await _resources.createCloudStorage(design.id, position,
                  rows: _grid.state.rows, cols: _grid.state.cols)
              : await _resources.writeConfigured(design.id, position, intent,
                  rows: _grid.state.rows, cols: _grid.state.cols);
          if (isClosed) return;
          await _repository.getById(design.id);
          if (isClosed) return;
          rows = await _read(design.id);
          if (isClosed) return;
          final record = _resolve(attempt, rows);
          _verifyBaseline(rows, replacing: {record.id});
          await _accept(attempt, record);
          if (isClosed) return;
          attempts.remove(intent.localKey);
        } on ResourceFailure catch (failure) {
          // Once a write returned successfully, a later read failure is still uncertain.
          if (!failure.ambiguous && attempt.ack == null) {
            attempts.remove(intent.localKey);
          }
          rethrow;
        }
      }
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

  /// Captures one target/identity. Drafts never enter the renderable grid.
  void openResourceConfiguration() {
    if (isClosed || state.pending || state.modalOpen || _resources == null) {
      return;
    }
    final design = state.active;
    final position = _grid.state.selected;
    if (design == null || position == null || !_grid.state.contains(position)) {
      return;
    }
    if (_pending(design.id).isNotEmpty) {
      _saveProblem =
          'Resolve the previous save with Check Save before configuring another resource.';
      _feedback();
      return;
    }
    final original = _grid.state.resources[position];
    if (original != null && original.kind != ResourceKind.cloudStorage) return;
    final resource =
        original ?? PlacedResource.local(ResourceKind.cloudStorage);
    emit(state.copyWith(
        configurationDraft: ResourceConfigurationDraft(
            designId: design.id,
            position: position,
            original: original,
            resource: resource,
            operationId: resource.deployment?.id,
            text: _resources.configurationText(resource.configuration,
                legacy: original != null && original.configuration == null)),
        canSave: false,
        saved: false));
  }

  void changeResourceConfigurationText(String text) {
    final draft = state.configurationDraft;
    if (isClosed || state.pending || draft == null || draft.uncertain) return;
    String? error;
    try {
      _resources!.parseConfiguration(text);
    } on ResourceFailure catch (failure) {
      error = failure.message;
    }
    emit(state.copyWith(
        configurationDraft:
            draft.copyWith(text: text, error: error, consent: false)));
  }

  void cancelResourceConfiguration() {
    if (isClosed || state.pending || state.configurationDraft == null) return;
    // An uncertain attempt remains in the shared coordinator. Header Check Save
    // can still reconcile its original ID/configuration after closing the form.
    emit(state.copyWith(clearConfigurationDraft: true));
    _feedback();
  }

  /// Explicitly authorized cloud command. A pending/unknown result is checked,
  /// never converted into another creation by a timer, Open or header Save.
  Future<void> deployResourceConfiguration({bool metadataOnly = false}) async {
    var draft = state.configurationDraft;
    if (isClosed || state.pending || draft == null || _resources == null) {
      return;
    }
    final attempts = _pending(draft.designId);
    final previous = draft.resource.deployment;
    final checking = checksDeployment || metadataOnly;
    if (!checking && (!deploymentEnabled || !draft.consent)) return;
    PlacedResource intent;
    try {
      intent = draft.resource
          .withConfiguration(_resources.parseConfiguration(draft.text));
    } on ResourceFailure catch (e) {
      emit(
          state.copyWith(configurationDraft: draft.copyWith(error: e.message)));
      return;
    }
    final existing = attempts[intent.localKey];
    final operationId = previous != null && !configurationMatchesSaved
        ? newResourceId()
        : draft.operationId ?? newResourceId();
    draft = draft.copyWith(
        operationId: operationId, deploymentCommand: true, consent: false);
    emit(state.copyWith(
        status: DesignStatus.saving,
        canSave: false,
        configurationDraft: draft));
    var attempt = existing;
    try {
      if (state.active?.id != draft.designId ||
          _grid.state.resources[draft.position] != draft.original) {
        throw ResourceFailure(
            'The captured tile changed. Open the original Design.',
            ambiguous: existing != null);
      }
      await _repository.getById(draft.designId);
      var rows = await _read(draft.designId);
      if (isClosed) return;
      if (checking) {
        // First recover the durable intent by ID. A 404 is not permission to create.
        final saved = await _resources.getById(
            draft.designId, intent.id ?? intent.localKey);
        if (saved.position != draft.position ||
            saved.configuration != intent.configuration) {
          throw const ResourceFailure(
              'The saved target changed. Open the Design before checking deployment.',
              ambiguous: true);
        }
        final operation = saved.deployment;
        if (operation == null) {
          throw const ResourceFailure(
              'No deployment record confirmed. No new cloud command was sent.',
              ambiguous: true);
        }
        await _resources.checkDeployment(draft.designId, saved.id, operation.id,
            reconcile: !metadataOnly && deploymentEnabled);
        attempt ??= _PendingResourceSave(
            draft.position, intent, rows.map((r) => r.id).toSet(),
            configurationDialog: true, original: draft.original);
      } else if (previous != null &&
          intent.configuration == draft.resource.configuration &&
          previous.resourceRevision == draft.resource.revision) {
        _verifyBaseline(rows);
        attempt = _PendingResourceSave(
            draft.position, intent, rows.map((r) => r.id).toSet(),
            configurationDialog: true, original: draft.original);
        attempts[intent.localKey] = attempt;
        await _resources.retryDeployment(
            draft.designId, draft.resource, previous.id, newResourceId(),
            consent: true);
      } else {
        _verifyBaseline(rows);
        attempt = _PendingResourceSave(
            draft.position, intent, rows.map((r) => r.id).toSet(),
            configurationDialog: true, original: draft.original);
        attempts[intent.localKey] = attempt;
        attempt.ack = await _resources.saveAndDeploy(
            draft.designId, draft.position, intent, operationId,
            consent: true, rows: _grid.state.rows, cols: _grid.state.cols);
      }
      if (isClosed) return;
      final record = await _resources.getById(
          draft.designId, intent.id ?? intent.localKey);
      rows = await _read(draft.designId);
      if (isClosed) return;
      final confirmed = _resolve(attempt, rows);
      if (!PlacedResource.fromPersisted(record)
          .sameSavedContent(PlacedResource.fromPersisted(confirmed))) {
        throw const ResourceFailure(
            'Resource changed during confirmation. Check again.',
            ambiguous: true);
      }
      _verifyBaseline(rows, replacing: {confirmed.id});
      await _accept(attempt, confirmed);
      attempts.remove(intent.localKey);
      final canonical =
          PlacedResource.fromPersisted(confirmed, localKey: intent.localKey);
      _saveProblem = null;
      emit(state.copyWith(
          status: DesignStatus.editing,
          configurationDraft: ResourceConfigurationDraft(
              designId: draft.designId,
              position: draft.position,
              resource: canonical,
              original: canonical,
              text: _resources.configurationText(canonical.configuration),
              operationId: canonical.deployment?.id,
              error:
                  'Configuration saved. ${canonical.deployment?.describe(canonical.revision) ?? "Deployment not confirmed"}')));
    } on Exception catch (failure) {
      if (isClosed) return;
      if (failure is ResourceFailure &&
          !failure.ambiguous &&
          existing == null) {
        attempts.remove(intent.localKey);
      }
      emit(state.copyWith(
          status: DesignStatus.editing,
          configurationDraft: draft.copyWith(
              uncertain: attempts.containsKey(intent.localKey),
              error: failure is ResourceFailure
                  ? failure.message
                  : 'Deployment could not be confirmed. Saved configuration is retained.')));
    } finally {
      if (!isClosed) _feedback();
    }
  }

  Future<void> saveResourceConfiguration() async {
    final draft = state.configurationDraft;
    if (isClosed || state.pending || draft == null || _resources == null) {
      return;
    }
    if (draft.deploymentCommand && draft.uncertain) {
      await deployResourceConfiguration(metadataOnly: true);
      return;
    }
    final attempts = _pending(draft.designId);
    var attempt = attempts[draft.resource.localKey];
    final checking = attempt != null;
    PlacedResource intent;
    try {
      intent = attempt?.sent ??
          draft.resource
              .withConfiguration(_resources.parseConfiguration(draft.text));
    } on ResourceFailure catch (failure) {
      emit(state.copyWith(
          configurationDraft: draft.copyWith(error: failure.message)));
      return;
    }
    emit(state.copyWith(
        status: DesignStatus.saving,
        canSave: false,
        configurationDraft: draft.copyWith(uncertain: checking)));
    try {
      if (state.active?.id != draft.designId ||
          _grid.state.resources[draft.position] != draft.original) {
        throw ResourceFailure(
            'The captured Design or tile changed. Close the form and open the original Design.',
            ambiguous: checking);
      }
      await _repository.getById(draft.designId);
      if (isClosed) return;
      var rows = await _read(draft.designId);
      if (isClosed) return;
      if (!checking) {
        _verifyBaseline(rows);
        attempt = _PendingResourceSave(
            draft.position, intent, rows.map((r) => r.id).toSet(),
            configurationDialog: true, original: draft.original);
        attempts[intent.localKey] = attempt;
        try {
          attempt.ack = await _resources.writeConfigured(
              draft.designId, draft.position, intent,
              rows: _grid.state.rows, cols: _grid.state.cols);
        } on ResourceFailure catch (failure) {
          if (!failure.ambiguous) attempts.remove(intent.localKey);
          rethrow;
        }
        if (isClosed) return;
      }
      // Original UUID and complete intent are retained across transport errors.
      final record = await _resources.getById(
          draft.designId, intent.id ?? intent.localKey,
          rows: _grid.state.rows, cols: _grid.state.cols);
      if (isClosed) return;
      rows = await _read(draft.designId);
      if (isClosed) return;
      final confirmed = _resolve(attempt, rows);
      if (!PlacedResource.fromPersisted(record)
          .sameSavedContent(PlacedResource.fromPersisted(confirmed))) {
        throw const ResourceFailure(
            'The Resource changed during confirmation. Check Save again.',
            ambiguous: true);
      }
      _verifyBaseline(rows, replacing: {confirmed.id});
      await _accept(attempt, confirmed);
      if (isClosed) return;
      attempts.remove(intent.localKey);
      _saveProblem = null;
      emit(state.copyWith(
          status: DesignStatus.editing, clearConfigurationDraft: true));
    } on Exception catch (failure) {
      if (isClosed) return;
      final uncertain = attempts.containsKey(intent.localKey);
      final message = failure is ResourceFailure
          ? failure.message
          : failure is DesignFailure
              ? failure.message
              : 'Save could not be confirmed. Your configuration is preserved.';
      emit(state.copyWith(
          status: DesignStatus.editing,
          configurationDraft:
              draft.copyWith(error: message, uncertain: uncertain)));
    } finally {
      if (!isClosed) _feedback();
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}

class _PendingResourceSave {
  _PendingResourceSave(this.position, this.sent, Set<String> beforeIds,
      {this.configurationDialog = false, this.original})
      : beforeIds = Set.unmodifiable(beforeIds);
  final GridPos position;
  final PlacedResource sent;
  final Set<String> beforeIds;
  final bool configurationDialog;
  final PlacedResource? original;
  PersistedResource? ack;
}
