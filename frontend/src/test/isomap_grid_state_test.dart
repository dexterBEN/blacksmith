import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_state.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';
import 'package:test/test.dart';

void main() {
  test('the default grid starts empty with six rows and columns', () {
    final state = IsomapGridState.initial();

    expect(state.rows, 6);
    expect(state.cols, 6);
    expect(state.selected, isNull);
    expect(state.tiles, isEmpty);
  });

  test('selection and clearing selection preserve placed resources', () {
    const position = GridPos(2, 3);
    final state = IsomapGridState.initial().copyWith(
      tiles: {position: ResourceKind.cloudStorage},
    );

    final selected = state.copyWith(selected: position);
    final cleared = selected.copyWith(clearSelection: true);

    expect(selected.selected, position);
    expect(cleared.selected, isNull);
    expect(cleared.tiles, state.tiles);
    expect(state.selected, isNull);
  });

  test('state snapshots copy and protect their input collection', () {
    const position = GridPos(0, 0);
    final input = {position: ResourceKind.cloudStorage};
    final state = IsomapGridState(rows: 2, cols: 3, tiles: input);
    input.clear();

    expect(state.tiles[position], ResourceKind.cloudStorage);
    expect(() => state.tiles.clear(), throwsUnsupportedError);
    final updated = state.copyWith(tiles: {
      ...state.tiles,
      const GridPos(1, 2): ResourceKind.computeEngine,
    });
    expect(state.tiles, hasLength(1));
    expect(updated.tiles, hasLength(2));
  });

  test('state rejects invalid dimensions and out-of-grid positions', () {
    expect(() => IsomapGridState.initial(rows: 0), throwsArgumentError);
    expect(() => IsomapGridState.initial(cols: -1), throwsArgumentError);
    expect(
        () => IsomapGridState(rows: 2, cols: 3, selected: const GridPos(2, 0)),
        throwsArgumentError);
    expect(
        () => IsomapGridState(rows: 2, cols: 3, tiles: {
              const GridPos(-1, 0): ResourceKind.cloudStorage,
            }),
        throwsArgumentError);
  });

  test('positions address tiles by both row and column', () {
    final tiles = <GridPos, String>{
      const GridPos(1, 2): 'first',
      const GridPos(2, 1): 'second',
    };

    tiles[const GridPos(1, 2)] = 'replacement';

    expect(tiles, hasLength(2));
    expect(tiles[const GridPos(1, 2)], 'replacement');
    expect(tiles[const GridPos(2, 1)], 'second');
  });
}
