import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/cloud_storage_failure.dart';
import 'package:blacksmith_front/data/services/cloud_services_api.dart';
import 'support/fakes.dart';

TypeMatcher<CloudStorageFailure> failureContaining(String text) =>
    isA<CloudStorageFailure>().having(
      (failure) => failure.message,
      'safe message',
      contains(text),
    );

void main() {
  CloudServicesApi makeApi(
    Future<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final api = CloudServicesApi(
      baseUrl: 'http://example.test:5100/base/',
      client: TrackedClient(handler),
      requestTimeout: timeout,
    );
    addTearDown(api.close);
    return api;
  }

  test('ping uses GET and returns the backend message', () async {
    final api = makeApi((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/base/cloud_services/ping');
      expect(request.url.hasQuery, isFalse);
      return http.Response('{"message":"alive"}', 200);
    });
    expect(await api.ping(), 'alive');
  });

  test('creation uses POST, encoded query parameters and an empty body',
      () async {
    var calls = 0;
    final api = makeApi((request) async {
      calls++;
      expect(request.method, 'POST');
      expect(request.url.path, '/base/cloud_services/create-bucket');
      expect(request.url.queryParameters, {
        'projectId': 'project & dev/one',
        'bucketName': 'bucket name?one&two=3',
      });
      expect(request.url.query, contains('%26'));
      expect(request.body, isEmpty);
      return http.Response('{"message":"created"}', 200);
    });
    expect(
        await api.createBucket(
          projectId: 'project & dev/one',
          bucketName: 'bucket name?one&two=3',
        ),
        'created');
    expect(calls, 1);
  });

  test('missing or null messages retain the historical success fallback',
      () async {
    final api = makeApi((_) async => http.Response('{}', 200));
    expect(await api.ping(), 'OK');
    expect(await api.createBucket(projectId: 'p', bucketName: 'b'),
        'Bucket created');
    final nullMessage =
        makeApi((_) async => http.Response('{"message":null}', 200));
    expect(await nullMessage.ping(), 'OK');
  });

  for (final status in [201, 400, 403, 409, 500]) {
    test('HTTP $status becomes a safe failure with no creation retry',
        () async {
      var calls = 0;
      final api = makeApi((_) async {
        calls++;
        return http.Response('RAW_SERVER_DIAGNOSTIC', status);
      });
      await expectLater(
        api.createBucket(projectId: 'p', bucketName: 'b'),
        throwsA(failureContaining('HTTP $status').having(
          (failure) => failure.toString(),
          'sanitized response',
          isNot(contains('RAW_SERVER_DIAGNOSTIC')),
        )),
      );
      expect(calls, 1);
    });
  }

  for (final body in ['not-json', '[]', 'null', '{"message":42}']) {
    test('unexpected JSON $body is normalized', () async {
      final api = makeApi((_) async => http.Response(body, 200));
      await expectLater(api.ping(), throwsA(isA<CloudStorageFailure>()));
    });
  }

  test('transport errors are sanitized and are not retried', () async {
    var calls = 0;
    final api = makeApi((_) async {
      calls++;
      throw http.ClientException('RAW_TRANSPORT_DIAGNOSTIC');
    });
    await expectLater(
      api.createBucket(projectId: 'p', bucketName: 'b'),
      throwsA(failureContaining('Unable to reach the backend.')),
    );
    expect(calls, 1);
  });

  test('timeout reports an uncertain server outcome without retrying',
      () async {
    var calls = 0;
    final response = Completer<http.Response>();
    final api = makeApi((_) {
      calls++;
      return response.future;
    }, timeout: const Duration(milliseconds: 10));

    await expectLater(
      api.createBucket(projectId: 'p', bucketName: 'b'),
      throwsA(failureContaining('may still complete on the server')),
    );
    expect(calls, 1);
    response.complete(http.Response('{"message":"late success"}', 200));
  });

  test('client is closed once and closed APIs send no further request',
      () async {
    var requests = 0;
    final client = TrackedClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    final api =
        CloudServicesApi(baseUrl: 'http://example.test', client: client);
    await api.ping();
    api.close();
    api.close();
    expect(client.closeCalls, 1);
    await expectLater(api.ping(), throwsA(failureContaining('closed')));
    expect(requests, 1);
  });

  test('configuration rejects unusable URLs and nonpositive timeouts', () {
    for (final base in [
      '/relative',
      'ftp://example.test',
      'http://example.test?x=y'
    ]) {
      expect(() => CloudServicesApi(baseUrl: base), throwsArgumentError);
    }
    expect(
        () => CloudServicesApi(
              baseUrl: 'http://example.test',
              requestTimeout: Duration.zero,
            ),
        throwsArgumentError);
  });
}
