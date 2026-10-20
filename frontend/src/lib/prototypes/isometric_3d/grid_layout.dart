import '../../domain/models/grid_position.dart';

/// Logical-to-world mapping for the native tile asset. No camera dependency.
/// Columns follow +X, rows follow +Z, Y=0 is the center of each tile.
class GridLayout3D {
  const GridLayout3D({this.rows = 6, this.cols = 6});

  final int rows;
  final int cols;
  static const tileWidth = 1.0;
  static const tileDepth = 1.0;
  static const tileHeight = 0.24;
  static const gap = 0.045;
  static const pitch = tileWidth + gap;

  double get width => cols * tileWidth + (cols - 1) * gap;
  double get depth => rows * tileDepth + (rows - 1) * gap;

  ({double x, double y, double z}) worldPosition(GridPos position) {
    if (rows <= 0 || cols <= 0) {
      throw StateError('Grid dimensions must be positive.');
    }
    if (position.row < 0 ||
        position.row >= rows ||
        position.col < 0 ||
        position.col >= cols) {
      throw RangeError('Grid position is outside the board.');
    }
    return (
      x: (position.col - (cols - 1) / 2) * pitch,
      y: 0,
      z: (position.row - (rows - 1) / 2) * pitch,
    );
  }
}
