import 'package:bloc/bloc.dart';
import 'package:godot_dart/godot_dart.dart';

import '../../../data/repositories/cloud_storage_repository.dart';
import '../../../data/repositories/resources_repository.dart'; // <-- à créer
import '../../models/grid_position.dart';
import '../../models/grid_resource.dart';

import 'isomap_grid_event.dart';
import 'isomap_grid_state.dart';

class IsomapGridBloc extends Bloc<IsomapGridEvent, IsomapGridState> {
  IsomapGridBloc({
    int rows = 6,
    int cols = 6,
    required CloudStorageRepository cloudStorageRepository,
    required ResourcesRepository resourcesRepository,
    String gcpProjectId = 'isometric-app-sample', // TODO: make it dynamic
  })  : _cloudRepo = cloudStorageRepository,
        _resourcesRepo = resourcesRepository,
        _gcpProjectId = gcpProjectId,
        super(IsomapGridState.initial(rows: rows, cols: cols)) {
    on<TileClicked>(_onTileClicked);
    on<NameSubmitted>(_onNameSubmitted);
    on<PlaceResource>(_onPlaceResource);
  }

  final CloudStorageRepository _cloudRepo;
  final ResourcesRepository _resourcesRepo;
  final String _gcpProjectId;

  void _onTileClicked(TileClicked event, Emitter<IsomapGridState> emit) {
    emit(state.copyWith(selected: event.pos, clearError: true));
  }

  void _onNameSubmitted(NameSubmitted event, Emitter<IsomapGridState> emit) {
    final cleaned = event.name.trim();
    if (cleaned.isEmpty) return;
    emit(state.copyWith(draftName: cleaned, clearError: true));
    GD.print(Variant('[IsomapGridBloc] draftName set -> $cleaned'));
  }

  Future<void> _onPlaceResource(
  PlaceResource event,
  Emitter<IsomapGridState> emit,
) async {
  final pos = state.selected;
  if (pos == null) {
    GD.pushWarning(Variant('[IsomapGridBloc] PlaceResource ignored: no tile selected'));
    return;
  }

  // 1)  built resource to place
  final GridResource draft = GridResource(
    id: null, // ex: "gcp:cloud_storage"
    texturePath: _texturePathFromKind(event.kind), name: '', 
    type: ResourceType.database, 
    provider: Provider.gcp, 
    position: pos,
  );

  // 2) UI
  final tilesNow = Map<GridPos, GridResource>.from(state.tiles);
  tilesNow[pos] = draft;
  emit(state.copyWith(tiles: tilesNow));

  // 3) backend DB
  try {
    final createdId = await _resourcesRepo.createResource(
      name: state.draftName,              // nom step 1
      type: _typeFromKind(event.kind),    // ex: "storageBucket"
      x: pos.row,
      y: pos.col,
    );

    GD.print(Variant('[IsomapGridBloc] ✅ DB created: $createdId'));
  } catch (e) {
    GD.pushWarning(Variant('[IsomapGridBloc] ❌ DB failed: $e'));
    // rollback :
    // final rolledBack = Map<GridPos, GridResource>.from(state.tiles)..remove(pos);
    // emit(state.copyWith(tiles: rolledBack));
    return;
  }

  // 4) cloud (storage)
  if (event.kind == 'gcp:cloud_storage') {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;

      final msg = await _cloudRepo.createBucket(
        bucketName: state.draftName,
        row: pos.row,
        col: pos.col,
      );

      GD.print(Variant('[IsomapGridBloc] ✅ GCP bucket ok: $msg'));
    } catch (e) {
      GD.pushWarning(Variant('[IsomapGridBloc] ❌ GCP bucket failed: $e'));
      // rollback optional or status "failed"
    }
  }
}

String _texturePathFromKind(String kind) {
  switch (kind) {
    case 'gcp:cloud_storage':
      return 'res://src/assets/gcp_cloud_storage.png';
    case 'gcp:compute_engine':
      return 'res://src/assets/gcp_compute_engine.png';
    default:
      // prevent none existing assets
      GD.pushWarning(Variant('[IsomapGridBloc] unknown kind="$kind"'));
      return 'res://src/assets/gcp_cloud_storage.png'; // fallback safe temporaire
  }
}

String _typeFromKind(String kind) {
  switch (kind) {
    case 'gcp:cloud_storage':
      return 'storageBucket';
    case 'gcp:compute_engine':
      return 'vm';
    default:
      return 'unknown';
  }
}

  GridResource? _resourceFromKind(String kind, String name, GridPos pos) {
    switch (kind) {
      case 'gcp:cloud_storage':
        return GridResource(
          id: null,
          name: name,
          provider: Provider.gcp,
          type: ResourceType.storageBucket,
          position: pos,
          texturePath: 'res://src/assets/gcp_cloud_storage.png',
        );
      case 'gcp:compute_engine':
        return GridResource(
          id: null,
          name: name,
          provider: Provider.gcp,
          type: ResourceType.vm,
          position: pos,
          texturePath: 'res://src/assets/gcp_compute_engine.png',
        );
      default:
        return null;
    }
  }

  /// Mapper enum -> string (/resources)
  String _toBackendType(ResourceType t) {
    switch (t) {
      case ResourceType.storageBucket:
        return 'storageBucket';
      case ResourceType.database:
        return 'database';
      case ResourceType.vm:
        return 'vm';
      case ResourceType.loadBalancer:
        return 'loadBalancer';
      case ResourceType.cache:
        return 'cache';
    }
  }
}

