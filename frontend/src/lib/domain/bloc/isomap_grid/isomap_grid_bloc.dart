import 'package:bloc/bloc.dart';
import '../../models/grid_position.dart';
import 'isomap_grid_event.dart';
import 'isomap_grid_state.dart';


class IsomapGridBloc extends Bloc<IsomapGridEvent, IsomapGridState> {
  IsomapGridBloc({int rows = 6, int cols = 6})
      : super(IsomapGridState.initial(rows: rows, cols: cols)) {
    on<TileClicked>(_onTileClicked);
    on<PlaceResource>(_onPlaceResource);
  }

  void _onTileClicked(TileClicked event, Emitter<IsomapGridState> emit) {
    emit(state.copyWith(selected: event.pos));
  }

  void _onPlaceResource(PlaceResource event, Emitter<IsomapGridState> emit) {
    final selected = state.selected;
    if (selected == null) {
      // pas de tuile sélectionnée → on ignore
      return;
    }

    final newTiles = Map<GridPos, String>.from(state.tiles);
    newTiles[selected] = event.path;

    emit(state.copyWith(tiles: newTiles));
  }
}

