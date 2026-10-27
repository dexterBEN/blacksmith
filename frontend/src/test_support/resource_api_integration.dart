// Explicit fixture integration against an isolated test API. Never the dev DB.
// Run with BLACKSMITH_INTEGRATION_BASE set to that API's numeric local address.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../lib/data/repositories/design_repository.dart';
import '../lib/data/repositories/resource_repository.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/placed_resource.dart';
import '../lib/domain/models/resource_configuration.dart';
import '../lib/domain/models/resource_kind.dart';

class _OnlyTestApi extends http.BaseClient {
  _OnlyTestApi(this.base);
  final Uri base;
  final _real = http.Client();
  final events = <Map<String, Object>>[];
  bool loseNextPut = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _check(
        request.url.origin == base.origin &&
            RegExp(r'^/(designs|resources|resource-types)($|/)')
                .hasMatch(request.url.path) &&
            {'GET', 'POST', 'PUT'}.contains(request.method),
        'Only the isolated metadata API is permitted.');
    final response = await _real.send(request);
    events.add({
      'method': request.method,
      'path': request.url.path,
      'status': response.statusCode
    });
    if (loseNextPut && request.method == 'PUT') {
      loseNextPut = false;
      await response.stream.drain<void>();
      throw http.ClientException(
          'Injected response loss after the actual committed write.');
    }
    return response;
  }

  @override
  void close() => _real.close();
}

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

ResourceConfiguration _configuration(String bucket) =>
    ResourceConfiguration(schemaVersion: 1, values: {
      'projectId': 'example-project-123',
      'bucketName': bucket,
      'location': 'europe-west9'
    });
PlacedResource _new(String bucket) =>
    PlacedResource.local(ResourceKind.cloudStorage)
        .withConfiguration(_configuration(bucket));
Future<void> _failure(Future<Object?> operation,
    {int? status, bool ambiguous = false, String? code}) async {
  try {
    await operation;
  } on ResourceFailure catch (failure) {
    _check(
        failure.status == status &&
            failure.ambiguous == ambiguous &&
            (code == null || code == failure.code),
        'Unexpected failure classification.');
    return;
  }
  throw StateError('The operation unexpectedly succeeded.');
}

Future<void> main() async {
  final base = Uri.parse(Platform.environment['BLACKSMITH_INTEGRATION_BASE']!);
  final designClient = _OnlyTestApi(base), resourceClient = _OnlyTestApi(base);
  final designs =
      DesignRepository(baseUrl: base.toString(), client: designClient);
  final resources =
      ResourceRepository(baseUrl: base.toString(), client: resourceClient);
  try {
    final design = await designs.create(
        'Blacksmith Issue53 configured integration ${DateTime.now().microsecondsSinceEpoch}');
    final a = _new('blacksmith-fixture-a'), b = _new('blacksmith-fixture-b');
    final invalid = PlacedResource.local(ResourceKind.cloudStorage)
        .withConfiguration(ResourceConfiguration(schemaVersion: 1, values: {
      'projectId': 'example-project-123',
      'bucketName': 'rejected-fixture',
      'location': 'unsupported-region'
    }));
    await _failure(
        resources.writeConfigured(design.id, const GridPos(0, 2), invalid),
        status: 400,
        code: 'invalid_payload');
    await _failure(resources.getById(design.id, invalid.localKey),
        status: 404, code: 'resource_not_found');
    _check((await resources.listForDesign(design.id)).isEmpty,
        'Rejected configured create must leave no metadata/configuration row.');
    const pa = GridPos(2, 3), pb = GridPos(4, 1);
    resourceClient.loseNextPut = true;
    await _failure(resources.writeConfigured(design.id, pa, a),
        ambiguous: true, code: 'transport');
    final recovered = await resources.getById(design.id, a.localKey);
    _check(
        recovered.id == a.localKey &&
            recovered.configuration == a.configuration &&
            recovered.revision == 1,
        'Recover a lost configured response using the original UUID and canonical state.');
    await _failure(resources.writeConfigured(design.id, pa, a),
        status: 412, code: 'resource_exists');
    final second = await resources.writeConfigured(design.id, pb, b);
    final beforeSibling = await resources.getById(design.id, second.id);
    await _failure(
        resources.writeConfigured(
            design.id,
            pa,
            PlacedResource.fromPersisted(recovered)
                .withConfiguration(invalid.configuration!)),
        status: 400,
        code: 'invalid_payload');
    _check(await resources.getById(design.id, recovered.id) == recovered,
        'Rejected update must preserve metadata, configuration and revision.');
    final updatedIntent = PlacedResource.fromPersisted(recovered)
        .withConfiguration(_configuration('blacksmith-fixture-edited'));
    final edited =
        await resources.writeConfigured(design.id, pa, updatedIntent);
    _check(edited.id == recovered.id && edited.revision == 2,
        'Edit retains identity and advances revision.');
    _check(await resources.getById(design.id, second.id) == beforeSibling,
        'Editing A must preserve B.');
    await _failure(resources.writeConfigured(design.id, pa, updatedIntent),
        status: 412, code: 'revision_conflict');
    await _failure(
        resources.writeConfigured(design.id, pa, _new('occupied-fixture')),
        status: 409,
        code: 'tile_occupied');
    final noop = await resources.writeConfigured(
        design.id, pa, PlacedResource.fromPersisted(edited));
    _check(noop.revision == edited.revision,
        'A semantic no-op must retain revision.');
    final otherDesign =
        await designs.create('Blacksmith Issue53 isolated sibling');
    final unrelated = await resources.writeConfigured(
        otherDesign.id, pa, _new('unrelated-fixture'));
    final legacy =
        await resources.createCloudStorage(design.id, const GridPos(0, 0));
    final rows = await resources.listForDesign(design.id);
    _check(rows.length == 3 && rows.map((r) => r.id).toSet().length == 3,
        'Exactly three distinct fixture resources.');
    _check(rows.singleWhere((r) => r.id == legacy.id).configuration == null,
        'Legacy metadata must not acquire synthetic settings.');
    _check(
        rows.singleWhere((r) => r.id == a.localKey).configuration ==
            edited.configuration,
        'Canonical configuration must survive scoped read.');
    _check(await resources.getById(otherDesign.id, unrelated.id) == unrelated,
        'Other Design and its configuration are unaffected.');
    _check((await resources.listForDesign(otherDesign.id)).length == 1,
        'Design reads remain isolated.');
    final result = {
      'passed': true,
      'configured_resources': 2,
      'legacy_resources': 1,
      'same_uuid_recovery': true,
      'stale_revision': 412,
      'tile_conflict': 409,
      'cloud_calls': 0,
      'events': [...designClient.events, ...resourceClient.events]
    };
    final output = Platform.environment['BLACKSMITH_INTEGRATION_OUTPUT'];
    if (output != null) await File(output).writeAsString(jsonEncode(result));
    stdout.writeln(
        'BLACKSMITH_MULTI_RESOURCE_API_PASSED configured=2 legacy=1 cloud_calls=0');
  } finally {
    designs.close();
    resources.close();
  }
}
