import 'package:equatable/equatable.dart';
import '../../models/grid_position.dart';
import '../../models/resource_kind.dart';

class IsomapGridState extends Equatable {
  static const defaultRows = 6;
  static const defaultCols = 6;

  final int rows;
  final int cols;
  final GridPos? selected;
  final Map<GridPos, ResourceKind> tiles;

  IsomapGridState({
    required this.rows,
    required this.cols,
    this.selected,
    Map<GridPos, ResourceKind> tiles = const {},
  }) : tiles = Map.unmodifiable(tiles) {
    if (rows <= 0 || cols <= 0) {
      throw ArgumentError('Grid dimensions must be positive.');
    }
    if (selected != null && !contains(selected!)) {
      throw ArgumentError('The selected position is outside the grid.');
    }
    if (this.tiles.keys.any((position) => !contains(position))) {
      throw ArgumentError('A resource position is outside the grid.');
    }
  }

  factory IsomapGridState.initial({
    int rows = defaultRows,
    int cols = defaultCols,
  }) =>
      IsomapGridState(rows: rows, cols: cols);

  bool contains(GridPos position) =>
      position.row >= 0 &&
      position.row < rows &&
      position.col >= 0 &&
      position.col < cols;

  IsomapGridState copyWith({
    GridPos? selected,
    bool clearSelection = false,
    Map<GridPos, ResourceKind>? tiles,
  }) {
    return IsomapGridState(
      rows: rows,
      cols: cols,
      selected: clearSelection ? null : (selected ?? this.selected),
      tiles: tiles ?? this.tiles,
    );
  }

  @override
  List<Object?> get props => [
        rows,
        cols,
        selected,
        tiles,
      ];
}
