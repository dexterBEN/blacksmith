import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:blacksmith_front/core/di/service_locator.dart';
import 'package:blacksmith_front/data/repositories/cloud_storage_repository.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'support/fakes.dart';

void main() {
  setUp(disposeServiceLocator);
  tearDown(disposeServiceLocator);

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
    final client = TrackedClient((_) async => http.Response('{}', 200));
    setupServiceLocator(rows: 2, cols: 3, httpClient: client);
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
    await disposeServiceLocator();
    expect(bloc.isClosed, isTrue);
    expect(client.closeCalls, 1);
    await disposeServiceLocator();
    expect(client.closeCalls, 1);
  });

  test('unused lazy registrations are not constructed during teardown',
      () async {
    final client = TrackedClient((_) async => http.Response('{}', 200));
    setupServiceLocator(httpClient: client);
    await disposeServiceLocator();
    expect(client.closeCalls, 0);
    // It was never adopted by an API instance, so the test still owns it.
    client.close();
  });
}
