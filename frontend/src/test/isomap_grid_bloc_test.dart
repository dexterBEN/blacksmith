import 'dart:async';
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/cloud_storage_repository.dart';
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

  setUp(() {
    repository = FakeRepository();
    bloc = IsomapGridBloc(cloudStorageRepository: repository);
  });
  tearDown(() async {
    repository.finishPending();
    if (!bloc.isClosed) await bloc.close();
    repository.close();
  });

  test('initial state uses the shared six by six defaults', () {
    expect(bloc.state.rows, 6);
    expect(bloc.state.cols, 6);
    expect(bloc.state.selected, isNull);
    expect(bloc.state.pendingOperations, 0);
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
    expect(repository.calls, isEmpty);
  });

  test('custom dimensions govern selection and bounds', () async {
    await bloc.close();
    bloc = IsomapGridBloc(cloudStorageRepository: repository, rows: 2, cols: 3);
    await select(const GridPos(1, 2));
    bloc.add(const TileClicked(GridPos(2, 0)));
    await tick();
    expect(bloc.state.selected, const GridPos(1, 2));
  });

  test('placement without selection changes nothing and sends no request',
      () async {
    bloc.add(const PlaceResource(ResourceKind.cloudStorage));
    bloc.add(const PlaceResource(ResourceKind.computeEngine));
    await tick();
    expect(bloc.state.tiles, isEmpty);
    expect(repository.calls, isEmpty);
  });

  test('Compute remains visual-only', () async {
    await select(const GridPos(2, 3));
    bloc.add(const PlaceResource(ResourceKind.computeEngine));
    await until((state) => state.tiles.isNotEmpty);
    expect(bloc.state.tiles[const GridPos(2, 3)], ResourceKind.computeEngine);
    expect(bloc.state.pendingOperations, 0);
    expect(repository.calls, isEmpty);
  });

  test('Cloud Storage placement is optimistic and reports its own result',
      () async {
    await select(const GridPos(2, 3));
    bloc.add(const PlaceResource(ResourceKind.cloudStorage));
    await until((state) => state.pendingOperations == 1);
    expect(bloc.state.tiles[const GridPos(2, 3)], ResourceKind.cloudStorage);
    expect(repository.calls, hasLength(1));
    expect(repository.calls.single.row, 2);
    expect(repository.calls.single.col, 3);
    repository.calls.single.completion.complete('created by fake');
    await until((state) => state.pendingOperations == 0);
    expect(bloc.state.lastResult!.status, PlacementStatus.success);
    expect(bloc.state.lastResult!.position, const GridPos(2, 3));
    expect(bloc.state.lastResult!.message, 'created by fake');
  });

  test('failure retains optimistic placement and newer edits', () async {
    await select(const GridPos(0, 0));
    bloc.add(const PlaceResource(ResourceKind.cloudStorage));
    await until((state) => state.pendingOperations == 1);
    await select(const GridPos(1, 1));
    bloc.add(const PlaceResource(ResourceKind.computeEngine));
    await until((state) => state.tiles.length == 2);
    repository.calls.single.completion.completeError(
      const CloudStorageFailure('The backend is unavailable.'),
    );
    await until((state) => state.pendingOperations == 0);
    expect(bloc.state.selected, const GridPos(1, 1));
    expect(bloc.state.tiles[const GridPos(0, 0)], ResourceKind.cloudStorage);
    expect(bloc.state.tiles[const GridPos(1, 1)], ResourceKind.computeEngine);
    expect(bloc.state.lastResult!.status, PlacementStatus.failure);
    expect(bloc.state.lastResult!.position, const GridPos(0, 0));
  });

  test('reversed completion order cannot restore an older grid snapshot',
      () async {
    await select(const GridPos(0, 0));
    bloc.add(const PlaceResource(ResourceKind.cloudStorage));
    await until((state) => state.pendingOperations == 1);
    final firstSnapshot = bloc.state;
    await select(const GridPos(1, 1));
    bloc.add(const PlaceResource(ResourceKind.cloudStorage));
    await until((state) => state.pendingOperations == 2);
    await select(const GridPos(2, 2));
    bloc.add(const PlaceResource(ResourceKind.computeEngine));
    await until((state) => state.tiles.length == 3);

    repository.calls[1].completion.complete('second');
    await until((state) => state.pendingOperations == 1);
    expect(bloc.state.lastResult!.position, const GridPos(1, 1));
    repository.calls[0].completion.complete('first');
    await until((state) => state.pendingOperations == 0);
    expect(bloc.state.lastResult!.position, const GridPos(0, 0));
    expect(bloc.state.selected, const GridPos(2, 2));
    expect(bloc.state.tiles, hasLength(3));
    expect(firstSnapshot.tiles, hasLength(1));
  });

  test('repeated cloud placements still issue one request per event', () async {
    await select(const GridPos(0, 0));
    bloc.add(const PlaceResource(ResourceKind.cloudStorage));
    bloc.add(const PlaceResource(ResourceKind.cloudStorage));
    await until((state) => state.pendingOperations == 2);
    expect(repository.calls, hasLength(2));
    expect(bloc.state.tiles, hasLength(1));
  });

  test('local diagnostic mode keeps placement without a repository', () async {
    await bloc.close();
    bloc = IsomapGridBloc.local();
    await select(const GridPos(1, 1));
    bloc.add(const PlaceResource(ResourceKind.cloudStorage));
    await until((state) => state.tiles.isNotEmpty);
    expect(bloc.state.tiles[const GridPos(1, 1)], ResourceKind.cloudStorage);
    expect(bloc.state.pendingOperations, 0);
    expect(repository.calls, isEmpty);
  });

  test('completion after BLoC disposal does not emit to disposed views',
      () async {
    await select(const GridPos(0, 0));
    bloc.add(const PlaceResource(ResourceKind.cloudStorage));
    await until((state) => state.pendingOperations == 1);
    final results = <IsomapGridState>[];
    final subscription = bloc.stream.listen(results.add);
    await bloc.close();
    repository.calls.single.completion.complete('too late');
    await tick();
    expect(results, isEmpty);
    await subscription.cancel();
  });
}
