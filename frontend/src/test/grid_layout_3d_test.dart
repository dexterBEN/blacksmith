import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/prototypes/isometric_3d/grid_layout.dart';
import 'package:test/test.dart';

void main() {
  const layout = GridLayout3D();

  test('the six by six board is centered and maps every position uniquely', () {
    final positions = <({double x, double y, double z})>{};
    for (var row = 0; row < 6; row++) {
      for (var col = 0; col < 6; col++) {
        positions.add(layout.worldPosition(GridPos(row, col)));
      }
    }
    expect(positions.length, 36);
    final first = layout.worldPosition(const GridPos(0, 0));
    final last = layout.worldPosition(const GridPos(5, 5));
    expect(first.x, -last.x);
    expect(first.z, -last.z);
    expect(positions.every((point) => point.y == 0), isTrue);
    expect(layout.width, closeTo(6.225, 1e-9));
    expect(layout.depth, layout.width);
  });

  test('columns follow X and rows follow Z with the same consistent gap', () {
    final first = layout.worldPosition(const GridPos(2, 2));
    final nextCol = layout.worldPosition(const GridPos(2, 3));
    final nextRow = layout.worldPosition(const GridPos(3, 2));
    expect(nextCol.x - first.x - GridLayout3D.tileWidth,
        closeTo(GridLayout3D.gap, 1e-9));
    expect(nextRow.z - first.z - GridLayout3D.tileDepth,
        closeTo(GridLayout3D.gap, 1e-9));
    expect(nextCol.z, first.z);
    expect(nextRow.x, first.x);
  });

  test('mapping rejects coordinates beyond the board', () {
    for (final position in [
      const GridPos(-1, 0),
      const GridPos(0, -1),
      const GridPos(6, 0),
      const GridPos(0, 6)
    ]) {
      expect(() => layout.worldPosition(position), throwsRangeError);
    }
  });

  test('rectangular layouts retain the same axis convention and centering', () {
    const rectangle = GridLayout3D(rows: 3, cols: 5);
    expect(
        rectangle.worldPosition(const GridPos(1, 2)), (x: 0.0, y: 0.0, z: 0.0));
    expect(rectangle.width, greaterThan(rectangle.depth));
  });

  test('all 36 centers round-trip through the inverse footprint mapping', () {
    for (var row = 0; row < layout.rows; row++) {
      for (var col = 0; col < layout.cols; col++) {
        final pos = GridPos(row, col);
        final point = layout.worldPosition(pos);
        expect(layout.positionAtWorld(point.x, point.z), pos);
      }
    }
  });

  test('tile edges are inclusive but gaps in either axis are rejected', () {
    const pos = GridPos(2, 2);
    final point = layout.worldPosition(pos);
    for (final edge in [-0.5, 0.5]) {
      expect(layout.positionAtWorld(point.x + edge, point.z), pos);
      expect(layout.positionAtWorld(point.x, point.z + edge), pos);
      expect(layout.positionAtWorld(point.x + edge, point.z + edge), pos);
    }
    for (final fraction in [0.1, 0.5, 0.9]) {
      final gapPoint = 0.5 + fraction * GridLayout3D.gap;
      expect(layout.positionAtWorld(point.x + gapPoint, point.z), isNull);
      expect(layout.positionAtWorld(point.x, point.z + gapPoint), isNull);
      expect(layout.positionAtWorld(point.x + gapPoint, point.z + gapPoint),
          isNull);
    }
  });

  test('outer edges belong to corner tiles and outside points are rejected',
      () {
    for (final row in [0, 5]) {
      for (final col in [0, 5]) {
        final point = layout.worldPosition(GridPos(row, col));
        final x = point.x + (col == 0 ? -0.5 : 0.5);
        final z = point.z + (row == 0 ? -0.5 : 0.5);
        expect(layout.positionAtWorld(x, z), GridPos(row, col));
        expect(layout.positionAtWorld(x * 1.001, z), isNull);
        expect(layout.positionAtWorld(x, z * 1.001), isNull);
      }
    }
  });

  test('orthographic parallel rays pick distinct tile centers on the top plane',
      () {
    for (var row = 0; row < 6; row++) {
      for (var col = 0; col < 6; col++) {
        final center = layout.worldPosition(GridPos(row, col));
        expect(
            layout.pickRay(
              origin: (x: center.x + 10, y: 10.12, z: center.z + 10),
              direction: (x: -1.0, y: -1.0, z: -1.0),
            ),
            GridPos(row, col));
      }
    }
  });

  test('rays parallel to, facing away from, or missing the board are ignored',
      () {
    expect(
        layout.pickRay(
            origin: (x: 0.0, y: 1.0, z: 0.0),
            direction: (x: 1.0, y: 0.0, z: 0.0)),
        isNull);
    expect(
        layout.pickRay(
            origin: (x: 0.0, y: -1.0, z: 0.0),
            direction: (x: 0.0, y: -1.0, z: 0.0)),
        isNull);
    expect(
        layout.pickRay(
            origin: (x: 100.0, y: 1.0, z: 100.0),
            direction: (x: 0.0, y: -1.0, z: 0.0)),
        isNull);
    expect(
        layout.pickRay(
            origin: (x: double.nan, y: 1.0, z: 0.0),
            direction: (x: 0.0, y: -1.0, z: 0.0)),
        isNull);
    expect(layout.positionAtWorld(double.infinity, 0), isNull);
    expect(layout.positionAtWorld(0, double.nan), isNull);
  });

  test('inverse mapping supports rectangular layouts without a second origin',
      () {
    const rectangle = GridLayout3D(rows: 3, cols: 5);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 5; col++) {
        final point = rectangle.worldPosition(GridPos(row, col));
        expect(rectangle.positionAtWorld(point.x, point.z), GridPos(row, col));
      }
    }
  });
}
