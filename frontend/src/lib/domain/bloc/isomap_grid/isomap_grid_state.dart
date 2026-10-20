import 'package:equatable/equatable.dart';
import '../../models/grid_position.dart';
import '../../models/resource_kind.dart';

enum PlacementStatus { success, failure }

class PlacementResult extends Equatable {
  const PlacementResult({
    required this.attemptId,
    required this.position,
    required this.status,
    required this.message,
  });

  final int attemptId;
  final GridPos position;
  final PlacementStatus status;
  final String message;

  @override
  List<Object> get props => [attemptId, position, status, message];
}

class IsomapGridState extends Equatable {
  static const defaultRows = 6;
  static const defaultCols = 6;

  final int rows;
  final int cols;
  final GridPos? selected;
  final Map<GridPos, ResourceKind> tiles;
  final int pendingOperations;
  final PlacementResult? lastResult;

  IsomapGridState({
    required this.rows,
    required this.cols,
    this.selected,
    Map<GridPos, ResourceKind> tiles = const {},
    this.pendingOperations = 0,
    this.lastResult,
  }) : tiles = Map.unmodifiable(tiles) {
    if (rows <= 0 || cols <= 0) {
      throw ArgumentError('Grid dimensions must be positive.');
    }
    if (pendingOperations < 0) {
      throw ArgumentError('Pending operation count must not be negative.');
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
    int? pendingOperations,
    PlacementResult? lastResult,
  }) {
    return IsomapGridState(
      rows: rows,
      cols: cols,
      selected: clearSelection ? null : (selected ?? this.selected),
      tiles: tiles ?? this.tiles,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      lastResult: lastResult ?? this.lastResult,
    );
  }

  @override
  List<Object?> get props => [
        rows,
        cols,
        selected,
        tiles,
        pendingOperations,
        lastResult,
      ];
}
