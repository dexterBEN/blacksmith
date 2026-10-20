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
}
