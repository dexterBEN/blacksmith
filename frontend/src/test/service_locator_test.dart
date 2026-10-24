import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:blacksmith_front/core/di/service_locator.dart';
import 'package:blacksmith_front/data/repositories/cloud_storage_repository.dart';
import 'package:blacksmith_front/data/services/cloud_services_api.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';
import 'support/fakes.dart';
import 'package:blacksmith_front/data/repositories/design_repository.dart';
import 'package:blacksmith_front/domain/bloc/design/design_cubit.dart';

void main() {
  setUp(disposeServiceLocator);
  tearDown(disposeServiceLocator);

  test('Design runtime shares the grid, uses configured URL and disposes once',
      () async {
    final client = TrackedClient((request) async {
      expect(request.url.toString(), 'http://configured.test:5139/designs');
      return http.Response(
          '{"id":"12345678-1234-1234-1234-123456789abc","name":"DI test"}',
          201);
    });
    setupServiceLocator(
        baseUrl: 'http://configured.test:5139', designHttpClient: client);
    final cubit = sl<DesignCubit>();
    setupServiceLocator();
    expect(identical(cubit, sl<DesignCubit>()), true);
    expect(client.requests, 0);
    cubit.open();
    cubit.changeName('DI test');
    await cubit.submit();
    expect(cubit.state.active!.name, 'DI test');
    await disposeServiceLocator();
    expect(cubit.isClosed, true);
    expect(client.closeCalls, 1);
    await disposeServiceLocator();
    expect(client.closeCalls, 1);
    expect(sl.isRegistered<DesignRepository>(), false);
  });

  test('the existing defaults and request contract remain configured',
      () async {
    final client = TrackedClient((request) async {
      expect(request.url.host, 'localhost');
      expect(request.url.port, 5100);
      expect(request.url.queryParameters['projectId'], 'isometric-app-sample');
      return http.Response('{}', 200);
    });
    setupServiceLocator(httpClient: client);
    await sl<CloudStorageRepository>().createBucket(row: 0, col: 0);
    await disposeServiceLocator();
    expect(client.closeCalls, 1);
  });

  test('setup is idempotent and does not reset shared selection', () async {
    setupServiceLocator(rows: 2, cols: 3);
    final bloc = sl<IsomapGridBloc>();
    bloc.add(const TileClicked(GridPos(1, 2)));
    await bloc.stream
        .firstWhere((state) => state.selected == const GridPos(1, 2));
    setupServiceLocator();
    expect(identical(bloc, sl<IsomapGridBloc>()), isTrue);
    expect(bloc.state.rows, 2);
    expect(bloc.state.cols, 3);
    expect(bloc.state.selected, const GridPos(1, 2));
    expect(bloc.isClosed, isFalse);
  });

  test('runtime teardown disposes the shared BLoC and HTTP client once',
      () async {
    final client = TrackedClient((_) async => http.Response('{}', 200));
    setupServiceLocator(httpClient: client);
    final bloc = sl<IsomapGridBloc>();
    sl<CloudServicesApi>(); // Explicit API usage adopts the client; editing does not.
    await disposeServiceLocator();
    expect(bloc.isClosed, isTrue);
    expect(client.closeCalls, 1);
    await disposeServiceLocator();
    expect(client.closeCalls, 1);
  });

  test('creating the editor leaves unused cloud registrations unconstructed',
      () async {
    final client = TrackedClient((_) async => http.Response('{}', 200));
    setupServiceLocator(httpClient: client);
    final bloc = sl<IsomapGridBloc>();
    await disposeServiceLocator();
    expect(bloc.isClosed, isTrue);
    expect(client.closeCalls, 0);
    // It was never adopted by an API instance, so the test still owns it.
    client.close();
  });

  test('placements stay local with an available cloud repository', () async {
    final repository = FakeRepository();
    sl.registerSingleton<CloudServicesApi>(repository.api,
        dispose: (api) => api.close());
    sl.registerSingleton<CloudStorageRepository>(repository);
    setupServiceLocator();
    final bloc = sl<IsomapGridBloc>();
    bloc.add(const TileClicked(GridPos(2, 3)));
    await bloc.stream
        .firstWhere((state) => state.selected == const GridPos(2, 3));
    for (final kind in [
      ResourceKind.cloudStorage,
      ResourceKind.computeEngine,
      ResourceKind.cloudStorage,
    ]) {
      bloc.add(PlaceResource(kind));
      await bloc.stream
          .firstWhere((state) => state.tiles[const GridPos(2, 3)] == kind);
    }
    bloc.add(const PlaceResource(ResourceKind.cloudStorage));
    await disposeServiceLocator();
    expect(bloc.state.tiles, {const GridPos(2, 3): ResourceKind.cloudStorage});
    expect(repository.calls, isEmpty);
    expect(repository.client.requests, 0);
  });
}
