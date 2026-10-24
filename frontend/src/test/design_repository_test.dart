import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/design_repository.dart';
import 'support/fakes.dart';

const designId = '12345678-1234-1234-1234-123456789abc';
const responseBody = '{"id":"$designId","name":"Smoke design"}';

void main() {
  DesignRepository repository(
      Future<http.Response> Function(http.Request) handler,
      {Duration timeout = const Duration(seconds: 2)}) {
    final repo = DesignRepository(
        baseUrl: 'http://example.test:5100/base/',
        client: TrackedClient(handler),
        requestTimeout: timeout);
    addTearDown(repo.close);
    return repo;
  }

  test(
      'POST uses the actual contract, requires 201, trims the name; GET reads back',
      () async {
    final calls = <http.Request>[];
    final repo = repository((r) async {
      calls.add(r);
      expect(r.url.path,
          r.method == 'POST' ? '/base/designs' : '/base/designs/$designId');
      if (r.method == 'POST') {
        expect(r.headers['content-type'], 'application/json');
        expect(jsonDecode(r.body), {'name': 'Smoke design'});
      }
      return http.Response(responseBody, r.method == 'POST' ? 201 : 200);
    });
    final created = await repo.create('  Smoke design  ');
    expect(created.id, designId);
    expect(await repo.getById(created.id), created);
    expect(calls.map((r) => r.method), ['POST', 'GET']);
  });

  for (final input in ['', '   ', 'a' * 201, '😀' * 101]) {
    test('invalid UTF-16 name is rejected without HTTP (${input.length})',
        () async {
      final repo =
          repository((_) async => throw StateError('No request expected'));
      await expectLater(repo.create(input), throwsA(isA<DesignFailure>()));
    });
  }
  test('200 UTF-16 code units are accepted', () async {
    final name = '😀' * 100;
    final repo = repository((_) async => http.Response(
        jsonEncode({'id': designId, 'name': name}), 201,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    expect((await repo.create(name)).name, name);
  });

  for (final status in [200, 202, 400, 401, 403, 409, 500, 503]) {
    test('HTTP $status is a sanitized failure and POST is sent once', () async {
      var calls = 0;
      final repo = repository((_) async {
        calls++;
        return http.Response('SECRET_DIAGNOSTIC', status);
      });
      await expectLater(
          repo.create('Smoke design'),
          throwsA(isA<DesignFailure>().having(
              (e) => e.message.contains('SECRET'), 'no raw data', false)));
      expect(calls, 1);
    });
  }

  test('unexpected successful status keeps the creation outcome uncertain',
      () async {
    final repo = repository((_) async => http.Response(responseBody, 200));
    await expectLater(
        repo.create('Smoke design'),
        throwsA(isA<DesignFailure>().having((e) => e.message,
            'uncertain outcome', contains('may have been created'))));
  });

  for (final body in [
    'broken SECRET',
    '{}',
    '[]',
    '{"id":"bad","name":"Smoke design"}',
    '{"id":"00000000-0000-0000-0000-000000000000","name":"Smoke design"}',
    '{"id":"$designId","name":"different"}',
    '{"id":"$designId","name":null}'
  ]) {
    test('malformed/unexpected success is not reported as persistence: $body',
        () async {
      final repo = repository((_) async => http.Response(body, 201));
      await expectLater(
          repo.create('Smoke design'),
          throwsA(isA<DesignFailure>().having((e) => e.message,
              'uncertain outcome', contains('may have been created'))));
    });
  }

  test('transport failure is safe, uncertain and not retried', () async {
    var calls = 0;
    final repo = repository((_) async {
      calls++;
      throw http.ClientException('SECRET');
    });
    await expectLater(
        repo.create('Smoke design'),
        throwsA(isA<DesignFailure>().having(
            (e) => e.message,
            'message',
            allOf(
                contains('Unable to reach'),
                contains('may have been created'),
                isNot(contains('SECRET'))))));
    expect(calls, 1);
  });
  test('timeout is uncertain; late completion does not issue a retry',
      () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final repo = repository((_) {
      calls++;
      return pending.future;
    }, timeout: const Duration(milliseconds: 5));
    await expectLater(
        repo.create('Smoke design'),
        throwsA(isA<DesignFailure>().having((e) => e.message, 'message',
            allOf(contains('timed out'), contains('may have been created')))));
    pending.complete(http.Response(responseBody, 201));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
  });
  test('close owns the HTTP client once and prevents later I/O', () async {
    final client = TrackedClient((_) async => http.Response(responseBody, 201));
    final repo =
        DesignRepository(baseUrl: 'http://localhost:5100', client: client);
    repo.close();
    repo.close();
    expect(client.closeCalls, 1);
    await expectLater(
        repo.create('Smoke design'), throwsA(isA<DesignFailure>()));
    expect(client.requests, 0);
  });
  test('read-back validates identity and unsuccessful responses', () async {
    final repo = repository((_) async => http.Response(responseBody, 200));
    await expectLater(repo.getById('bad'), throwsA(isA<DesignFailure>()));
    await expectLater(repo.getById('abcdef12-1234-1234-1234-123456789abc'),
        throwsA(isA<DesignFailure>()));
    final missing = repository((_) async => http.Response('SECRET', 404));
    await expectLater(missing.getById(designId), throwsA(isA<DesignFailure>()));
  });
  test('invalid URL, embedded credentials and non-positive timeout rejected',
      () {
    for (final url in [
      'relative',
      'ftp://host',
      'http://user:pass@host',
      'http://host?q=1',
      'http://host/#f'
    ]) {
      expect(() => DesignRepository(baseUrl: url), throwsArgumentError);
    }
    expect(
        () => DesignRepository(
            baseUrl: 'http://host', requestTimeout: Duration.zero),
        throwsArgumentError);
  });
}
