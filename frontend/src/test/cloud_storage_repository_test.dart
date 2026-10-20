import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/cloud_storage_repository.dart';
import 'package:blacksmith_front/data/services/cloud_services_api.dart';

void main() {
  test('repository supplies the configured project and historical name pattern',
      () async {
    var calls = 0;
    final api = CloudServicesApi(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        calls++;
        expect(request.url.queryParameters['projectId'], 'configured-project');
        expect(request.url.queryParameters['bucketName'],
            matches(RegExp(r'^blacksmith-2-3-[0-9]+$')));
        return http.Response('{"message":"fake bucket created"}', 200);
      }),
    );
    addTearDown(api.close);
    final repository =
        CloudStorageRepository(api, projectId: 'configured-project');
    expect(
        await repository.createBucket(row: 2, col: 3), 'fake bucket created');
    expect(calls, 1);
  });

  test('the existing ping capability still delegates to the backend', () async {
    final api = CloudServicesApi(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/cloud_services/ping');
        return http.Response('{"message":"fake ping"}', 200);
      }),
    );
    addTearDown(api.close);
    final repository =
        CloudStorageRepository(api, projectId: 'configured-project');
    expect(await repository.pingBackend(), 'fake ping');
  });
}
