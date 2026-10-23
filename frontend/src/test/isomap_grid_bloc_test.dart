import 'package:test/test.dart';
import 'package:blacksmith_front/core/di/service_locator.dart' as di;
import 'package:blacksmith_front/data/repositories/cloud_storage_repository.dart';
import 'package:blacksmith_front/data/services/cloud_services_api.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_state.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';
import 'support/fakes.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeRepository repository;
  late IsomapGridBloc bloc;

  Future<IsomapGridState> until(bool Function(IsomapGridState) matches) {
    if (matches(bloc.state)) return Future.value(bloc.state);
    return bloc.stream.firstWhere(matches).timeout(const Duration(seconds: 3));
  }

  Future<void> select(GridPos position) async {
    bloc.add(TileClicked(position));
    await until((state) => state.selected == position);
  }

  Future<void> place(ResourceKind kind) async {
    bloc.add(PlaceResource(kind));
    await until((state) => state.tiles[state.selected] == kind);
  }

  setUp(() async {
    await di.disposeServiceLocator();
    repository = FakeRepository();
    di.sl.registerSingleton<CloudServicesApi>(repository.api,
        dispose: (api) => api.close());
    di.sl.registerSingleton<CloudStorageRepository>(repository);
    di.setupServiceLocator();
    bloc = di.sl<IsomapGridBloc>();
  });
  tearDown(() async {
    await di.disposeServiceLocator();
    expect(repository.calls, isEmpty,
        reason: 'Editor events must never provision, even with configured DI.');
    expect(repository.client.requests, 0,
        reason: 'Editor events must never send backend HTTP requests.');
  });

  test('initial state uses the shared six by six defaults', () {
    expect(bloc.state.rows, 6);
    expect(bloc.state.cols, 6);
    expect(bloc.state.selected, isNull);
    expect(bloc.state.tiles, isEmpty);
  });

  test('invalid tile events preserve a valid selection', () async {
    await select(const GridPos(1, 2));
    for (final position in [
      const GridPos(-1, 0),
      const GridPos(0, -1),
      const GridPos(6, 0),
      const GridPos(0, 6),
    ]) {
      bloc.add(TileClicked(position));
    }
    await tick();
    expect(bloc.state.selected, const GridPos(1, 2));
    expect(bloc.state.tiles, isEmpty);
  });

  test('selection switches and repeated selection never place resources',
      () async {
    final states = <IsomapGridState>[];
    final subscription = bloc.stream.listen(states.add);
    await select(const GridPos(0, 5));
    await select(const GridPos(5, 0));
    bloc.add(const TileClicked(GridPos(5, 0)));
    await tick();
    expect(states.map((state) => state.selected),
        [const GridPos(0, 5), const GridPos(5, 0)]);
    expect(bloc.state.tiles, isEmpty);
    await subscription.cancel();
  });

  test('custom dimensions govern selection and bounds', () async {
    final custom = IsomapGridBloc(rows: 2, cols: 3);
    addTearDown(custom.close);
    custom.add(const TileClicked(GridPos(1, 2)));
    await custom.stream
        .firstWhere((state) => state.selected == const GridPos(1, 2));
    custom.add(const TileClicked(GridPos(2, 0)));
    await tick();
    expect(custom.state.selected, const GridPos(1, 2));
  });

  test('placement without selection changes nothing and sends no request',
      () async {
    for (final kind in ResourceKind.values) {
      bloc.add(PlaceResource(kind));
    }
    await tick();
    expect(bloc.state.selected, isNull);
    expect(bloc.state.tiles, isEmpty);
  });

  test('out-of-bounds clicks cannot enable placement from an empty selection',
      () async {
    for (final position in [
      const GridPos(-1, 0),
      const GridPos(0, -1),
      const GridPos(6, 0),
      const GridPos(0, 6),
    ]) {
      bloc.add(TileClicked(position));
      bloc.add(const PlaceResource(ResourceKind.cloudStorage));
    }
    await tick();
    expect(bloc.state.selected, isNull);
    expect(bloc.state.tiles, isEmpty);
  });

  for (final kind in ResourceKind.values) {
    test('$kind placement is local with a cloud repository available',
        () async {
      await select(const GridPos(2, 3));
      await place(kind);
      expect(bloc.state.tiles, {const GridPos(2, 3): kind});
      expect(bloc.state.selected, const GridPos(2, 3));
    });

    test('repeated $kind placement keeps one resource entry', () async {
      await select(const GridPos(0, 0));
      await place(kind);
      for (var i = 0; i < 10; i++) {
        bloc.add(PlaceResource(kind));
      }
      await tick();
      expect(bloc.state.tiles, {const GridPos(0, 0): kind});
    });
  }

  test('replacement changes one tile without mutating earlier snapshots',
      () async {
    await select(const GridPos(2, 3));
    await place(ResourceKind.cloudStorage);
    final first = bloc.state;
    await place(ResourceKind.computeEngine);
    expect(bloc.state.tiles, {const GridPos(2, 3): ResourceKind.computeEngine});
    expect(first.tiles, {const GridPos(2, 3): ResourceKind.cloudStorage});
    await place(ResourceKind.cloudStorage);
    expect(bloc.state.tiles, {const GridPos(2, 3): ResourceKind.cloudStorage});
  });

  test('selection and replacement preserve resources on other tiles', () async {
    await select(const GridPos(0, 0));
    await place(ResourceKind.cloudStorage);
    await select(const GridPos(1, 1));
    expect(bloc.state.tiles, {const GridPos(0, 0): ResourceKind.cloudStorage});
    await place(ResourceKind.computeEngine);
    await select(const GridPos(0, 0));
    await place(ResourceKind.computeEngine);
    expect(bloc.state.tiles, {
      const GridPos(0, 0): ResourceKind.computeEngine,
      const GridPos(1, 1): ResourceKind.computeEngine,
    });
  });

  test('consecutive edits preserve the latest selection and all placements',
      () async {
    for (var i = 0; i < 3; i++) {
      await select(GridPos(i, i));
      await place(ResourceKind.cloudStorage);
    }
    expect(bloc.state.selected, const GridPos(2, 2));
    expect(bloc.state.tiles, hasLength(3));
  });

  test('local diagnostic mode retains the same placement semantics', () async {
    final local = IsomapGridBloc.local();
    addTearDown(local.close);
    local.add(const TileClicked(GridPos(1, 1)));
    await local.stream
        .firstWhere((state) => state.selected == const GridPos(1, 1));
    local.add(const PlaceResource(ResourceKind.cloudStorage));
    await local.stream.firstWhere((state) => state.tiles.isNotEmpty);
    expect(local.state.tiles, {const GridPos(1, 1): ResourceKind.cloudStorage});
  });
}
