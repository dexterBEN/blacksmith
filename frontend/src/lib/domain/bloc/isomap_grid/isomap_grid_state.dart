import 'package:equatable/equatable.dart';
import '../../models/grid_position.dart';
import '../../models/grid_resource.dart';

class IsomapGridState extends Equatable {
  final int rows;
  final int cols;
  final GridPos? selected;

  /// Step 1 : name input
  final String draftName;

  /// Map position -> business logic
  final Map<GridPos, GridResource> tiles;

  /// Feedback async
  final bool isPlacing;
  final String? lastError;

  const IsomapGridState({
    required this.rows,
    required this.cols,
    this.selected,
    required this.draftName,
    required this.tiles,
    required this.isPlacing,
    required this.lastError,
  });

  factory IsomapGridState.initial({int rows = 6, int cols = 6}) {
    return IsomapGridState(
      rows: rows,
      cols: cols,
      selected: null,
      draftName: '',
      tiles: const {},
      isPlacing: false,
      lastError: null,
    );
  }

  IsomapGridState copyWith({
    GridPos? selected,
    bool clearSelection = false,
    String? draftName,
    Map<GridPos, GridResource>? tiles,
    bool? isPlacing,
    String? lastError,
    bool clearError = false,
  }) {
    return IsomapGridState(
      rows: rows,
      cols: cols,
      selected: clearSelection ? null : (selected ?? this.selected),
      draftName: draftName ?? this.draftName,
      tiles: tiles ?? this.tiles,
      isPlacing: isPlacing ?? this.isPlacing,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [rows, cols, selected, draftName, tiles, isPlacing, lastError];
}

