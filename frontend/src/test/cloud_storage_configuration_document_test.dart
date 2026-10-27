import 'dart:convert';
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/resource_repository.dart';
import 'package:blacksmith_front/data/repositories/cloud_storage_configuration_document.dart';

void main() {
  final repository = ResourceRepository(baseUrl: 'http://unused.test');
  tearDownAll(repository.close);
  String document(Map<String, dynamic> values) => jsonEncode({
        'schemaVersion': 1,
        'configuration': {
          'projectId': 'example-project-123',
          'bucketName': 'valid-bucket',
          'location': 'europe-west9',
          ...values
        }
      });
  test(
      'new template is v1, explicitly illustrative; legacy has no invented identifiers',
      () {
    final template =
        repository.parseConfiguration(repository.configurationText(null));
    expect(template.values['projectId'], 'example-project-123');
    final legacy = jsonDecode(repository.configurationText(null, legacy: true));
    expect(legacy['configuration']['projectId'], '');
    expect(legacy['configuration']['bucketName'], '');
    expect(() => repository.parseConfiguration(jsonEncode(legacy)),
        throwsA(isA<ResourceFailure>()));
  });
  test('v1 round-trip normalizes only backend-approved fixed defaults', () {
    final config = repository.parseConfiguration(document({}));
    expect(config.values['storageClass'], 'STANDARD');
    expect(config.values['uniformBucketLevelAccess'], true);
    expect(repository.parseConfiguration(repository.configurationText(config)),
        config);
    for (final location in CloudStorageConfigurationDocument.locations) {
      expect(
          repository
              .parseConfiguration(document({'location': location}))
              .values['location'],
          location);
    }
  });
  for (final values in <Map<String, dynamic>>[
    {'projectId': ''},
    {'projectId': 'Wrong Project'},
    {'projectId': 'google-project'},
    {'bucketName': 'bad.bucket'},
    {'bucketName': 'goog-secret'},
    {'bucketName': 123},
    {'location': 'US'},
    {'storageClass': 'NEARLINE'},
    {'uniformBucketLevelAccess': false},
    {'publicAccessPrevention': 'inherited'},
    {'private_key': 'never-echo-this'},
    {'labels': {}},
  ]) {
    test(
        'reject unsupported field/identifier combination ${values.keys.join(',')}: ${values.values.first.runtimeType}',
        () {
      expect(() => repository.parseConfiguration(document(values)),
          throwsA(isA<ResourceFailure>()));
    });
  }
  for (final invalid in [
    '{',
    '[]',
    '{"schemaVersion":1}',
    '{"schemaVersion":1.0,"configuration":{}}',
    r'{"schemaVersion":1,"configuration":{"projectId":"example-project-123","\u0070rojectId":"other-project","bucketName":"valid-bucket","location":"europe-west9"}}',
    '{"schemaVersion":1,"schemaVersion":1,"configuration":{}}',
    '{"type":"service_account","private_key":"never-echo-this"}',
    '${' ' * 16385}{}'
  ]) {
    test(
        'reject malformed/duplicate/credential/oversize input without reflecting it (${invalid.length})',
        () {
      try {
        repository.parseConfiguration(invalid);
        fail('Must reject input.');
      } on ResourceFailure catch (error) {
        expect(error.message, isNot(contains('never-echo-this')));
      }
    });
  }
}
