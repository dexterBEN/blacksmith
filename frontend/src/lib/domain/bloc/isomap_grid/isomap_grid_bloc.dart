import 'package:bloc/bloc.dart';
import 'isomap_grid_event.dart';
import 'isomap_grid_state.dart';

class IsomapGridBloc extends Bloc<IsomapGridEvent, IsomapGridState> {
  IsomapGridBloc({
    int rows = IsomapGridState.defaultRows,
    int cols = IsomapGridState.defaultCols,
  }) : super(IsomapGridState.initial(rows: rows, cols: cols)) {
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
    emit(state.copyWith(
      tiles: {...state.tiles, selected: event.kind},
    ));
  }
}
