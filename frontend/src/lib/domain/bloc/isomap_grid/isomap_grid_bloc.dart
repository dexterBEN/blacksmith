import 'package:bloc/bloc.dart';
import '../../../data/repositories/cloud_storage_repository.dart';
import '../../models/grid_position.dart';
import '../../models/resource_kind.dart';
import 'isomap_grid_event.dart';
import 'isomap_grid_state.dart';

class IsomapGridBloc extends Bloc<IsomapGridEvent, IsomapGridState> {
  IsomapGridBloc({
    int rows = IsomapGridState.defaultRows,
    int cols = IsomapGridState.defaultCols,
    required CloudStorageRepository cloudStorageRepository,
  }) : this._(cloudStorageRepository, rows, cols);

  /// Preserves the existing visual-only diagnostic fallback without giving
  /// Godot nodes a second logical grid state or constructing an HTTP client.
  IsomapGridBloc.local({
    int rows = IsomapGridState.defaultRows,
    int cols = IsomapGridState.defaultCols,
  }) : this._(null, rows, cols);

  IsomapGridBloc._(this._cloudRepo, int rows, int cols)
      : super(IsomapGridState.initial(rows: rows, cols: cols)) {
    on<TileClicked>(_onTileClicked);
    on<PlaceResource>(_onPlaceResource);
  }

  final CloudStorageRepository? _cloudRepo;
  int _nextAttemptId = 0;

  void _onTileClicked(
    TileClicked event,
    Emitter<IsomapGridState> emit,
  ) {
    if (state.contains(event.pos)) {
      emit(state.copyWith(selected: event.pos));
    }
  }

  Future<void> _onPlaceResource(
    PlaceResource event,
    Emitter<IsomapGridState> emit,
  ) async {
    final selected = state.selected;
    if (selected == null) return;
    final repository = _cloudRepo;
    final provision =
        event.kind == ResourceKind.cloudStorage && repository != null;
    final attemptId = provision ? ++_nextAttemptId : 0;

    emit(state.copyWith(
      tiles: {...state.tiles, selected: event.kind},
      pendingOperations: state.pendingOperations + (provision ? 1 : 0),
    ));
    if (!provision) return;

    try {
      final message = await repository.createBucket(
        row: selected.row,
        col: selected.col,
      );
      _complete(emit, attemptId, selected, PlacementStatus.success, message);
    } catch (error) {
      final message = error is CloudStorageFailure
          ? error.message
          : 'Bucket creation failed.';
      _complete(emit, attemptId, selected, PlacementStatus.failure, message);
    }
  }

  void _complete(
    Emitter<IsomapGridState> emit,
    int attemptId,
    GridPos position,
    PlacementStatus status,
    String message,
  ) {
    if (emit.isDone) return;
    // Use the latest state: an older request must not restore a stale grid
    // snapshot or change the user's newer selection.
    emit(state.copyWith(
      pendingOperations: state.pendingOperations - 1,
      lastResult: PlacementResult(
        attemptId: attemptId,
        position: position,
        status: status,
        message: message,
      ),
    ));
  }
}
