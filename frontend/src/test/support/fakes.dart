import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:blacksmith_front/data/repositories/cloud_storage_repository.dart';
import 'package:blacksmith_front/data/services/cloud_services_api.dart';

/// Records and rejects any accidental provisioning or HTTP call during editing.
class FakeRepository extends CloudStorageRepository {
  factory FakeRepository() {
    final client = TrackedClient((_) async =>
        throw StateError('HTTP is forbidden during editor actions.'));
    return FakeRepository._(client,
        CloudServicesApi(baseUrl: 'http://fake.invalid', client: client));
  }

  FakeRepository._(this.client, this.api)
      : super(api, projectId: 'fake-project');
  final TrackedClient client;
  final CloudServicesApi api;
  final calls = <({int row, int col})>[];

  @override
  Future<String> createBucket({required int row, required int col}) {
    calls.add((row: row, col: col));
    throw StateError('Provisioning is forbidden during editor actions.');
  }
}

class TrackedClient extends MockClient {
  TrackedClient(Future<http.Response> Function(http.Request) handler)
      : super(handler);
  int closeCalls = 0;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    return super.send(request);
  }

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}
