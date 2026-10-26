import 'package:equatable/equatable.dart';
import '../../models/grid_position.dart';
import '../../models/resource_kind.dart';
import '../../models/placed_resource.dart';

class IsomapGridState extends Equatable {
  static const defaultRows = 6;
  static const defaultCols = 6;

  final int rows;
  final int cols;
  final GridPos? selected;
  final Map<GridPos, PlacedResource> resources;

  /// Derived immutable kind projection retained by the 3D/legacy 2D adapters.
  late final Map<GridPos, ResourceKind> tiles = Map.unmodifiable(
      resources.map((position, resource) => MapEntry(position, resource.kind)));

  IsomapGridState({
    required this.rows,
    required this.cols,
    this.selected,
    Map<GridPos, ResourceKind> tiles = const {},
    Map<GridPos, PlacedResource>? resources,
  }) : resources = Map.unmodifiable(resources ??
            tiles.map((position, kind) =>
                MapEntry(position, PlacedResource.local(kind)))) {
    if (resources != null && tiles.isNotEmpty) {
      throw ArgumentError('Specify one grid snapshot.');
    }
    if (rows <= 0 || cols <= 0) {
      throw ArgumentError('Grid dimensions must be positive.');
    }
    if (selected != null && !contains(selected!)) {
      throw ArgumentError('The selected position is outside the grid.');
    }
    if (this.resources.keys.any((position) => !contains(position))) {
      throw ArgumentError('A resource position is outside the grid.');
    }
    final keys = this.resources.values.map((r) => r.localKey).toSet();
    final ids =
        this.resources.values.map((r) => r.id).whereType<String>().toList();
    if (keys.length != this.resources.length ||
        ids.toSet().length != ids.length) {
      throw ArgumentError(
          'Resource identities must be unique within the grid.');
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
    Map<GridPos, PlacedResource>? resources,
  }) {
    if (tiles != null && resources != null) {
      throw ArgumentError('Specify one grid snapshot.');
    }
    return IsomapGridState(
      rows: rows,
      cols: cols,
      selected: clearSelection ? null : (selected ?? this.selected),
      resources: resources ??
          (tiles == null
              ? this.resources
              : tiles.map((position, kind) => MapEntry(
                  position,
                  this.resources[position]?.kind == kind
                      ? this.resources[position]!
                      : PlacedResource.local(kind)))),
    );
  }

  @override
  List<Object?> get props => [
        rows,
        cols,
        selected,
        resources,
      ];
}
