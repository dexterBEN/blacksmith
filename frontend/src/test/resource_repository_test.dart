import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/resource_repository.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';

const designId = '12345678-1234-1234-1234-123456789abc';
const resourceId = '22345678-1234-1234-1234-123456789abc';
const storageId = '10000000-0000-0000-0000-000000000002';
Map<String, Object?> record() => {
      'id': resourceId,
      'designId': designId,
      'x': 3,
      'y': 2,
      'type': 'gcp.storage.bucket',
      'name': 'Cloud Storage',
      'resourceTypeId': storageId,
      'revision': 1,
      'configurationState': 'absent',
      'configuration': null,
    };
http.Response catalog() => http.Response(
    jsonEncode([
      {'id': '10000000-0000-0000-0000-000000000001', 'code': 'virtual-machine'},
      {'id': storageId, 'code': 'storage'}
    ]),
    200);

void main() {
  test(
      'catalog mapping and create payload use real contracts and x=column/y=row',
      () async {
    final calls = <String>[];
    final client = MockClient((r) async {
      calls.add('${r.method} ${r.url.path}');
      if (r.url.path == '/resource-types') return catalog();
      expect(r.url.path, '/resources');
      expect(jsonDecode(r.body), {
        'designId': designId,
        'resourceTypeId': storageId,
        'name': 'Cloud Storage',
        'type': 'gcp.storage.bucket',
        'x': 3,
        'y': 2
      });
      return http.Response(jsonEncode(record()..remove('designId')), 201);
    });
    final repo =
        ResourceRepository(baseUrl: 'http://api.test/', client: client);
    addTearDown(repo.close);
    final saved = await repo.createCloudStorage(designId, const GridPos(2, 3));
    expect(saved.position, const GridPos(2, 3));
    expect(saved.x, 3);
    expect(saved.y, 2);
    expect(saved.designId, designId);
    expect(calls, ['GET /resource-types', 'POST /resources']);
  });
  test('scoped reads validate ownership and reverse-map grid coordinates',
      () async {
    final repo = ResourceRepository(
        baseUrl: 'http://api.test',
        client: MockClient((r) async {
          expect(r.method, 'GET');
          expect(r.url.path, '/designs/$designId/resources');
          expect(r.url.queryParameters, {'include': 'configuration'});
          return http.Response(jsonEncode([record()]), 200);
        }));
    addTearDown(repo.close);
    final loaded = (await repo.listForDesign(designId)).single;
    expect(loaded.position, const GridPos(2, 3));
    expect(loaded.id, resourceId);
  });
  test('empty Design is valid', () async {
    final repo = ResourceRepository(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => http.Response('[]', 200)));
    addTearDown(repo.close);
    expect(await repo.listForDesign(designId), isEmpty);
  });
  for (final entry in <String, Object>{
    'designId': resourceId,
    'x': 6,
    'y': -1,
    'type': 'storage',
    'id': 'invalid',
    'name': '',
    'x-double': 3.5
  }.entries) {
    test('reject invalid/unsupported loaded ${entry.key} without writes',
        () async {
      final data = record()
        ..[entry.key == 'x-double' ? 'x' : entry.key] = entry.value;
      final repo = ResourceRepository(
          baseUrl: 'http://api.test',
          client: MockClient((r) async {
            expect(r.method, 'GET');
            return http.Response(jsonEncode([data]), 200);
          }));
      addTearDown(repo.close);
      await expectLater(
          repo.listForDesign(designId), throwsA(isA<ResourceFailure>()));
    });
  }
  test('multiple records including duplicate positions are rejected', () async {
    final repo = ResourceRepository(
        baseUrl: 'http://api.test',
        client: MockClient(
            (_) async => http.Response(jsonEncode([record(), record()]), 200)));
    addTearDown(repo.close);
    await expectLater(
        repo.listForDesign(designId), throwsA(isA<ResourceFailure>()));
  });
  test('missing/ambiguous storage catalog never sends a write', () async {
    for (final body in [
      '[]',
      '[{"id":"$storageId","code":"storage"},{"id":"$storageId","code":"storage"}]'
    ]) {
      var posts = 0;
      final repo = ResourceRepository(
          baseUrl: 'http://api.test',
          client: MockClient((r) async {
            if (r.method == 'POST') posts++;
            return http.Response(body, 200);
          }));
      addTearDown(repo.close);
      await expectLater(repo.createCloudStorage(designId, const GridPos(2, 3)),
          throwsA(isA<ResourceFailure>()));
      expect(posts, 0);
    }
  });
  test('timeout and malformed 201 are ambiguous; neither is retried', () async {
    for (final malformed in [false, true]) {
      var posts = 0;
      final repo = ResourceRepository(
          baseUrl: 'http://api.test',
          requestTimeout: const Duration(milliseconds: 20),
          client: MockClient((r) async {
            if (r.method == 'GET') return catalog();
            posts++;
            if (!malformed) return Completer<http.Response>().future;
            return http.Response('sensitive invalid payload', 201);
          }));
      addTearDown(repo.close);
      await expectLater(
          repo.createCloudStorage(designId, const GridPos(2, 3)),
          throwsA(isA<ResourceFailure>()
              .having((e) => e.ambiguous, 'ambiguous', true)
              .having((e) => e.message, 'safe message',
                  isNot(contains('sensitive')))));
      expect(posts, 1);
    }
  });
  test(
      'definite 400 rejection is safe to recover and a GET timeout is not a write',
      () async {
    final repo = ResourceRepository(
        baseUrl: 'http://api.test',
        client: MockClient((r) async =>
            r.method == 'GET' ? catalog() : http.Response('secret', 400)));
    addTearDown(repo.close);
    await expectLater(
        repo.createCloudStorage(designId, const GridPos(2, 3)),
        throwsA(isA<ResourceFailure>()
            .having((e) => e.ambiguous, 'ambiguous', false)));
  });
  test(
      'invalid IDs/coordinates are rejected before I/O and unsafe URLs rejected',
      () async {
    var calls = 0;
    final repo = ResourceRepository(
        baseUrl: 'http://api.test',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }));
    addTearDown(repo.close);
    await expectLater(
        repo.listForDesign('bad'), throwsA(isA<ResourceFailure>()));
    await expectLater(repo.createCloudStorage(designId, const GridPos(6, 0)),
        throwsA(isA<ResourceFailure>()));
    expect(calls, 0);
    for (final url in [
      'file:///tmp',
      'http://user:password@api.test',
      'http://api.test?key=hidden'
    ]) {
      expect(() => ResourceRepository(baseUrl: url), throwsArgumentError);
    }
  });
}
