
import 'package:equatable/equatable.dart';

import '../../models/grid_position.dart';


class IsomapGridState extends Equatable {
  final int rows;
  final int cols;
  final GridPos? selected;
  // map position -> chemin d’asset Godot, ex: 'res://src/assets/gcp_cloud_storage.png'
  final Map<GridPos, String> tiles;

  const IsomapGridState({
    required this.rows,
    required this.cols,
    this.selected,
    required this.tiles,
  });

  factory IsomapGridState.initial({int rows = 6, int cols = 6}) {
    return IsomapGridState(
      rows: rows,
      cols: cols,
      selected: null,
      tiles: const {},
    );
  }

  IsomapGridState copyWith({
    GridPos? selected,
    bool clearSelection = false,
    Map<GridPos, String>? tiles,
  }) {
    return IsomapGridState(
      rows: rows,
      cols: cols,
      selected: clearSelection ? null : (selected ?? this.selected),
      tiles: tiles ?? this.tiles,
    );
  }

  @override
  List<Object?> get props => [rows, cols, selected, tiles];
}

