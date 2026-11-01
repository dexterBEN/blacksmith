import 'package:bloc/bloc.dart';
import '../../models/resource_kind.dart';
import 'isomap_grid_event.dart';
import 'isomap_grid_state.dart';

class IsomapGridBloc extends Bloc<IsomapGridEvent, IsomapGridState> {
  IsomapGridBloc({
    int rows = IsomapGridState.defaultRows,
    int cols = IsomapGridState.defaultCols,
  }) : super(IsomapGridState.initial(rows: rows, cols: cols)) {
    on<RestoreDesignResources>((event, emit) {
      var accepted = false;
      try {
        if (event.resources.keys.every(state.contains)) {
          emit(
              state.copyWith(resources: event.resources, clearSelection: true));
          accepted = true;
        }
      } on ArgumentError {
        // Reject the entire invalid snapshot; never partially hydrate.
      }
      event.applied.complete(accepted);
    });
    on<ConfirmResourceSaved>((event, emit) {
      final current = state.resources[event.position];
      final accepted = current != null &&
          current.localKey == event.sent.localKey &&
          current.kind == event.sent.kind;
      if (accepted) {
        emit(state.copyWith(resources: {
          ...state.resources,
          event.position: current.confirm(event.record, event.sent)
        }));
      }
      event.applied.complete(accepted);
    });
    on<ChangeResourceConfiguration>((event, emit) {
      final current = state.resources[event.position];
      if (current == null || current.kind != ResourceKind.cloudStorage) return;
      emit(state.copyWith(resources: {
        ...state.resources,
        event.position: current.withConfiguration(event.configuration)
      }));
    });
    on<ApplyConfiguredResource>((event, emit) {
      var accepted = false;
      try {
        if (state.contains(event.position) &&
            state.resources[event.position] == event.original) {
          emit(state.copyWith(resources: {
            ...state.resources,
            event.position: event.intent.confirm(event.record, event.intent)
          }));
          accepted = true;
        }
      } on ArgumentError {/* Do not overwrite an incompatible snapshot. */}
      event.applied.complete(accepted);
    });
    on<ClearTileSelection>(
        (event, emit) => emit(state.copyWith(clearSelection: true)));
    on<TileClicked>(_onTileClicked);
    on<PlaceResource>(_onPlaceResource);
    on<ResetGridForNewDesign>((event, emit) =>
        emit(IsomapGridState.initial(rows: state.rows, cols: state.cols)));
  }

  /// Preserves the existing visual-only diagnostic fallback without giving
  /// Godot nodes a second logical grid state or constructing an HTTP client.
  IsomapGridBloc.local({
    int rows = IsomapGridState.defaultRows,
    int cols = IsomapGridState.defaultCols,
  }) : this(rows: rows, cols: cols);

  void _onTileClicked(
    TileClicked event,
    Emitter<IsomapGridState> emit,
  ) {
    if (state.contains(event.pos)) {
      emit(state.copyWith(selected: event.pos));
    }
  }

  void _onPlaceResource(
    PlaceResource event,
    Emitter<IsomapGridState> emit,
  ) {
    final selected = state.selected;
    if (selected == null) return;
    final previous = state.resources[selected];
    if (previous?.kind == event.kind || previous?.id != null) return;
    emit(state.copyWith(
      tiles: {...state.tiles, selected: event.kind},
    ));
  }
}
