
import 'package:bloc/bloc.dart';
import 'package:godot_dart/godot_dart.dart';

import '../../../data/repositories/cloud_storage_repository.dart';
import '../../models/grid_position.dart';

import 'isomap_grid_event.dart';
import 'isomap_grid_state.dart';

class IsomapGridBloc extends Bloc<IsomapGridEvent, IsomapGridState> {
  IsomapGridBloc({
    int rows = 6,
    int cols = 6,
    required CloudStorageRepository cloudStorageRepository,
  })  : _cloudRepo = cloudStorageRepository,
        super(IsomapGridState.initial(rows: rows, cols: cols)) {
    on<TileClicked>(_onTileClicked);
    on<PlaceResource>(_onPlaceResource);
  }

  final CloudStorageRepository _cloudRepo;

  void _onTileClicked(
    TileClicked event,
    Emitter<IsomapGridState> emit,
  ) {
    emit(state.copyWith(selected: event.pos));
  }

  Future<void> _onPlaceResource(
    PlaceResource event,
    Emitter<IsomapGridState> emit,
  ) async {
    final selected = state.selected;
    if (selected == null) {
      // Pas de tuile sélectionnée → on ignore
      return;
    }

    final newTiles = Map<GridPos, String>.from(state.tiles);
    newTiles[selected] = event.path;

    emit(state.copyWith(tiles: newTiles));

    if (event.path.contains('cloud_storage')) {
      try {
        final message = await _cloudRepo.createBucket(
          projectId: 'isometric-app-sample',
          row: selected.row,
          col: selected.col,
        );

        GD.print(Variant('[IsomapGridBloc] ✅ Backend OK: $message'));
      } catch (e) {
        GD.pushWarning(
          Variant('[IsomapGridBloc] ❌ Backend error: $e'),
        );

        //fallback
        // newTiles.remove(selected);
        // emit(state.copyWith(tiles: newTiles));
      }
    }
  }
}

