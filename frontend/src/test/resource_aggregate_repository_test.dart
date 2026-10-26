import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/resource_repository.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/models/placed_resource.dart';
import 'package:blacksmith_front/domain/models/resource_configuration.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';

const owner = '12345678-1234-1234-1234-123456789abc';
const resource = '22345678-1234-1234-1234-123456789abc';
const other = '32345678-1234-1234-1234-123456789abc';
const catalog = '10000000-0000-0000-0000-000000000002';
ResourceConfiguration config([String bucket = 'blacksmith-example-assets']) =>
    ResourceConfiguration(schemaVersion: 1, values: {
      'projectId': 'example-project-123',
      'bucketName': bucket,
      'location': 'europe-west9'
    });
String tag(String id, int revision) =>
    '"resource-${id.replaceAll('-', '')}-r$revision"';
Map<String, Object?> aggregate(
        {String id = resource,
        int revision = 1,
        bool configured = true,
        String bucket = 'blacksmith-example-assets'}) =>
    {
      'id': id,
      'designId': owner,
      'resourceTypeId': catalog,
      'name': 'Cloud Storage',
      'type': 'gcp.storage.bucket',
      'x': 3,
      'y': 2,
      'revision': revision,
      'createdAtUtc': '2026-10-26T04:00:00Z',
      'configurationState': configured ? 'validated' : 'absent',
      'configuration': configured
          ? {
              'resourceId': id,
              'schemaVersion': 1,
              'configuration': config(bucket).values
            }
          : null
    };

void main() {
  test(
      'scoped aggregate read restores multiple identities, configuration absence and revisions',
      () async {
    final repo = ResourceRepository(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.queryParameters, {'include': 'configuration'});
          return http.Response(
              jsonEncode([
                aggregate(),
                {...aggregate(id: other, configured: false), 'x': 1, 'y': 4}
              ]),
              200);
        }));
    addTearDown(repo.close);
    final rows = await repo.listForDesign(owner);
    expect(rows.map((r) => r.id), [resource, other]);
    expect(rows.first.configuration, config());
    expect(rows.last.configuration, isNull);
    expect(rows.last.configurationState, 'absent');
    expect(rows.last.position, const GridPos(4, 1));
    expect(rows.first.etag, tag(resource, 1));
  });

  test(
      'duplicate IDs and duplicate tiles fail instead of collapsing rows into a map',
      () async {
    for (final rows in [
      [
        aggregate(),
        {...aggregate(), 'x': 1}
      ],
      [aggregate(), aggregate(id: other)],
    ]) {
      final repo = ResourceRepository(
          baseUrl: 'http://api.test',
          client:
              MockClient((_) async => http.Response(jsonEncode(rows), 200)));
      addTearDown(repo.close);
      await expectLater(
          repo.listForDesign(owner),
          throwsA(isA<ResourceFailure>()
              .having((e) => e.code, 'code', 'duplicate_resources')));
    }
  });

  for (final invalid in <String, Map<String, Object?>>{
    'unknown schema': {
      ...aggregate(),
      'configuration': {
        'resourceId': resource,
        'schemaVersion': 2,
        'configuration': config().values
      }
    },
    'unsupported document': {
      ...aggregate(),
      'configurationState': 'unsupported',
      'configuration': null
    },
    'missing aggregate fields': {
      'id': resource,
      'designId': owner,
      'type': 'gcp.storage.bucket',
      'name': 'Cloud Storage',
      'x': 3,
      'y': 2
    },
    'wrong owner': {...aggregate(), 'designId': other},
    'wrong kind': {...aggregate(), 'type': 'gcp.compute.instance'},
    'outside grid': {...aggregate(), 'x': 6},
    'bad revision': {...aggregate(), 'revision': 0},
    'noninteger coordinate': {...aggregate(), 'y': 2.0},
    'missing configuration': {...aggregate(), 'configurationState': 'absent'},
  }.entries) {
    test(
        'complete Open rejects ${invalid.key} after a valid row without partial success',
        () async {
      final repo = ResourceRepository(
          baseUrl: 'http://api.test',
          client: MockClient((_) async => http.Response(
              jsonEncode([
                {...aggregate(id: other), 'x': 1},
                invalid.value
              ]),
              200)));
      addTearDown(repo.close);
      await expectLater(
          repo.listForDesign(owner), throwsA(isA<ResourceFailure>()));
    });
  }

  test(
      'single aggregate GET validates the owning ID and exact backend revision tag',
      () async {
    for (final etag in [tag(resource, 1), '"wrong"', null]) {
      final repo = ResourceRepository(
          baseUrl: 'http://api.test',
          client: MockClient((request) async {
            expect(request.url.path, '/resources/$resource');
            expect(request.url.queryParameters, {'include': 'configuration'});
            return http.Response(jsonEncode(aggregate()), 200,
                headers: {if (etag != null) 'etag': etag});
          }));
      addTearDown(repo.close);
      if (etag == tag(resource, 1)) {
        expect((await repo.getById(owner, resource)).etag, etag);
      } else {
        await expectLater(
            repo.getById(owner, resource), throwsA(isA<ResourceFailure>()));
      }
    }
  });

  test(
      'explicit configured create uses the captured UUID and existing nested v1 contract',
      () async {
    var calls = 0;
    final intent = PlacedResource(
        localKey: resource,
        kind: ResourceKind.cloudStorage,
        catalogId: catalog,
        configuration: config(),
        configurationState: 'validated');
    final repo = ResourceRepository(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'PUT');
          expect(request.url.path, '/designs/$owner/resources/$resource');
          expect(request.headers['If-None-Match'], '*');
          expect(request.headers['If-Match'], isNull);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.keys.toSet(),
              {'name', 'type', 'resourceTypeId', 'x', 'y', 'configuration'});
          expect(body['configuration'],
              {'schemaVersion': 1, 'configuration': config().values});
          expect(body['x'], 3);
          expect(body['y'], 2);
          return http.Response(jsonEncode(aggregate()), 201);
        }));
    addTearDown(repo.close);
    final row = await repo.writeConfigured(owner, const GridPos(2, 3), intent);
    expect(row.id, resource);
    expect(row.configuration, config());
    expect(calls, 1);
  });

  test(
      'configured edit retains identity and sends the original strong If-Match',
      () async {
    final methods = <String>[];
    final repo = ResourceRepository(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          methods.add(request.method);
          if (request.method == 'GET') {
            return http.Response(jsonEncode(aggregate(revision: 7)), 200,
                headers: {'etag': tag(resource, 7)});
          }
          expect(request.url.path, '/designs/$owner/resources/$resource');
          expect(request.headers['If-Match'], tag(resource, 7));
          expect(request.headers['If-None-Match'], isNull);
          return http.Response(
              jsonEncode(aggregate(revision: 8, bucket: 'bucket-edited')), 200);
        }));
    addTearDown(repo.close);
    final current = await repo.getById(owner, resource);
    final intent = PlacedResource.fromPersisted(current)
        .withConfiguration(config('bucket-edited'));
    final changed = await repo.writeConfigured(owner, current.position, intent);
    expect(changed.id, current.id);
    expect(changed.revision, 8);
    expect(methods, ['GET', 'PUT']);
  });

  for (final status in [400, 404, 409, 412, 428, 503]) {
    test(
        'HTTP $status is sanitized, classified and never automatically retried',
        () async {
      var calls = 0;
      final repo = ResourceRepository(
          baseUrl: 'http://api.test',
          client: MockClient((_) async {
            calls++;
            return http.Response(
                jsonEncode({
                  'code': status == 409
                      ? 'tile_occupied'
                      : status == 412
                          ? 'revision_conflict'
                          : 'precondition_required',
                  'error': 'RAW_SECRET_FIXTURE'
                }),
                status);
          }));
      addTearDown(repo.close);
      final intent = PlacedResource(
          localKey: resource,
          kind: ResourceKind.cloudStorage,
          catalogId: catalog,
          configuration: config());
      await expectLater(
          repo.writeConfigured(owner, const GridPos(2, 3), intent),
          throwsA(isA<ResourceFailure>()
              .having((e) => e.status, 'HTTP status', status)
              .having((e) => e.ambiguous, 'uncertainty', status == 503)
              .having((e) => e.message, 'sanitized',
                  isNot(contains('RAW_SECRET_FIXTURE')))));
      expect(calls, 1);
      expect(intent.localKey, resource);
    });
  }

  test(
      'configured timeout retains its original UUID and does not issue another PUT',
      () async {
    var calls = 0;
    final repo = ResourceRepository(
        baseUrl: 'http://api.test',
        requestTimeout: const Duration(milliseconds: 20),
        client: MockClient((_) {
          calls++;
          return Completer<http.Response>().future;
        }));
    addTearDown(repo.close);
    final intent = PlacedResource(
        localKey: resource,
        kind: ResourceKind.cloudStorage,
        catalogId: catalog,
        configuration: config());
    await expectLater(
        repo.writeConfigured(owner, const GridPos(2, 3), intent),
        throwsA(isA<ResourceFailure>()
            .having((e) => e.ambiguous, 'uncertain', true)));
    expect(calls, 1);
    expect(intent.localKey, resource);
  });
}
