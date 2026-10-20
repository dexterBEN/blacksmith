import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:blacksmith_front/data/repositories/cloud_storage_repository.dart';
import 'package:blacksmith_front/data/services/cloud_services_api.dart';

class PendingBucket {
  PendingBucket(this.row, this.col);
  final int row;
  final int col;
  final completion = Completer<String>();
}

/// Every operation stays in memory. The API is fail-closed if accidentally used.
class FakeRepository extends CloudStorageRepository {
  factory FakeRepository() => FakeRepository._(CloudServicesApi(
        baseUrl: 'http://fake.invalid',
        client: MockClient((_) async =>
            throw StateError('A fake repository must not send HTTP requests.')),
      ));

  FakeRepository._(this.api) : super(api, projectId: 'fake-project');
  final CloudServicesApi api;
  final calls = <PendingBucket>[];

  @override
  Future<String> createBucket({required int row, required int col}) {
    final call = PendingBucket(row, col);
    calls.add(call);
    return call.completion.future;
  }

  void finishPending() {
    for (final call in calls) {
      if (!call.completion.isCompleted) {
        call.completion.complete('fake cleanup');
      }
    }
  }

  void close() => api.close();
}

class TrackedClient extends MockClient {
  TrackedClient(Future<http.Response> Function(http.Request) handler)
      : super(handler);
  int closeCalls = 0;

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}
