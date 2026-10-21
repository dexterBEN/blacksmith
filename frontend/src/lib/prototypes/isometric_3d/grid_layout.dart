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

  // Godot's float coordinates can differ slightly from Dart's doubles at
  // an exact edge. This tolerance is far smaller than the physical gap.
  static const _edgeTolerance = 1e-6;

  double get width => cols * tileWidth + (cols - 1) * gap;
  double get depth => rows * tileDepth + (rows - 1) * gap;

  /// Inverse mapping on the top-surface footprint. Gaps and outside points
  /// are ignored; tile footprint edges are inclusive. Beveled side faces
  /// are deliberately not separate picking surfaces in this prototype.
  GridPos? positionAtWorld(double x, double z) {
    if (rows <= 0 || cols <= 0) {
      throw StateError('Grid dimensions must be positive.');
    }
    if (!x.isFinite ||
        !z.isFinite ||
        x.abs() > width / 2 + _edgeTolerance ||
        z.abs() > depth / 2 + _edgeTolerance) {
      return null;
    }
    final col = (x / pitch + (cols - 1) / 2).round();
    final row = (z / pitch + (rows - 1) / 2).round();
    if (row < 0 || row >= rows || col < 0 || col >= cols) return null;
    final position = GridPos(row, col);
    final center = worldPosition(position);
    if ((x - center.x).abs() > tileWidth / 2 + _edgeTolerance ||
        (z - center.z).abs() > tileDepth / 2 + _edgeTolerance) {
      return null;
    }
    return position;
  }

  /// Intersect a ray expressed in grid-local coordinates with Y=top surface.
  /// Rendering supplies the camera ray; this calculation has no Godot or
  /// BLoC dependency and never depends on tile node names.
  GridPos? pickRay({
    required ({double x, double y, double z}) origin,
    required ({double x, double y, double z}) direction,
  }) {
    if (![origin.x, origin.y, origin.z, direction.x, direction.y, direction.z]
            .every((v) => v.isFinite) ||
        direction.y.abs() < 1e-9) {
      return null;
    }
    final distance = (tileHeight / 2 - origin.y) / direction.y;
    if (distance < 0) return null;
    return positionAtWorld(
      origin.x + distance * direction.x,
      origin.z + distance * direction.z,
    );
  }

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
