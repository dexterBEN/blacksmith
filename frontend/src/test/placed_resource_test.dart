import 'package:test/test.dart';
import 'package:blacksmith_front/domain/models/placed_resource.dart';
import 'package:blacksmith_front/domain/models/persisted_resource.dart';
import 'package:blacksmith_front/domain/models/resource_configuration.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_state.dart';

void main() {
  test(
      'selection/kind projections retain stable local identities and immutable snapshots',
      () {
    final resource = PlacedResource.local(ResourceKind.cloudStorage);
    expect(PersistedResource.validId(resource.localKey), true);
    final state = IsomapGridState(
        rows: 6, cols: 6, resources: {const GridPos(2, 3): resource});
    final selected = state.copyWith(selected: const GridPos(2, 3));
    expect(
        selected.resources[const GridPos(2, 3)]!.localKey, resource.localKey);
    expect(selected.tiles, {const GridPos(2, 3): ResourceKind.cloudStorage});
    expect(() => selected.resources.clear(), throwsUnsupportedError);
    expect(() => selected.tiles.clear(), throwsUnsupportedError);
    expect(state.selected, isNull);
  });

  test(
      'configuration values are deeply immutable and canonical field order does not create a dirty edit',
      () {
    final nested = <String, dynamic>{
      'nested': <String, dynamic>{
        'items': [1, 2]
      }
    };
    final frozen = ResourceConfiguration(schemaVersion: 2, values: nested);
    (nested['nested'] as Map<String, dynamic>)['items'] = [3];
    expect((frozen.values['nested'] as Map)['items'], [1, 2]);
    expect(() => (frozen.values['nested'] as Map)['other'] = 3,
        throwsUnsupportedError);
    final a = ResourceConfiguration(schemaVersion: 1, values: {
      'projectId': 'example-project-123',
      'bucketName': 'example-bucket',
      'location': 'europe-west9'
    });
    final b = ResourceConfiguration(schemaVersion: 1, values: {
      'location': 'europe-west9',
      'bucketName': 'example-bucket',
      'projectId': 'example-project-123',
      'storageClass': 'STANDARD',
      'uniformBucketLevelAccess': true,
      'publicAccessPrevention': 'enforced'
    });
    expect(a, b);
  });

  test('one persistent identity cannot occupy two tiles in a grid snapshot',
      () {
    const id = '12345678-1234-1234-1234-123456789abc';
    final a = PlacedResource.fromPersisted(
        const PersistedResource(id: id, designId: id, position: GridPos(1, 1)));
    final b = PlacedResource.fromPersisted(
        const PersistedResource(id: id, designId: id, position: GridPos(2, 2)),
        localKey: 'other-local-key');
    expect(
        () => IsomapGridState(
            rows: 6,
            cols: 6,
            resources: {const GridPos(1, 1): a, const GridPos(2, 2): b}),
        throwsArgumentError);
  });

  test(
      'restore rejects an out-of-grid complete snapshot without clearing existing contents',
      () async {
    final grid = IsomapGridBloc.local();
    addTearDown(grid.close);
    grid.add(const TileClicked(GridPos(1, 1)));
    await grid.stream.firstWhere((s) => s.selected != null);
    grid.add(const PlaceResource(ResourceKind.cloudStorage));
    await grid.stream.firstWhere((s) => s.resources.isNotEmpty);
    final before = grid.state;
    final invalid = RestoreDesignResources.resources({
      const GridPos(99, 1): PlacedResource.local(ResourceKind.cloudStorage)
    });
    grid.add(invalid);
    expect(await invalid.applied.future, false);
    expect(grid.state, before);
  });
}
