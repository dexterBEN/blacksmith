import 'dart:convert';
import '../../domain/models/resource_configuration.dart';

/// Editor/wire syntax only. The backend remains the semantic authority.
class CloudStorageConfigurationDocument {
  static const maxBytes = 16384;
  static const locations = {
    'europe-west9',
    'us-central1',
    'northamerica-northeast1'
  };
  static const fields = {
    'projectId',
    'bucketName',
    'location',
    'storageClass',
    'uniformBucketLevelAccess',
    'publicAccessPrevention'
  };

  static String format(ResourceConfiguration? value, {bool legacy = false}) =>
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': value?.schemaVersion ?? 1,
        'configuration': value?.values ??
            {
              'projectId': legacy ? '' : 'example-project-123',
              'bucketName': legacy ? '' : 'replace-with-your-bucket-name',
              'location': legacy ? '' : 'europe-west9',
              'storageClass': 'STANDARD',
              'uniformBucketLevelAccess': true,
              'publicAccessPrevention': 'enforced'
            }
      });

  static ResourceConfiguration parse(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('Use at most 16 KiB of JSON text.');
    }
    dynamic document;
    try {
      document = jsonDecode(text);
    } on FormatException {
      // Never include the input text (which could contain pasted credentials).
      throw const FormatException(
          'Invalid JSON syntax. Check quotes, commas and braces.');
    }
    _checkDuplicateKeys(text);
    if (document is! Map<String, dynamic> ||
        document.keys
            .toSet()
            .difference({'schemaVersion', 'configuration'}).isNotEmpty ||
        document['schemaVersion'] is! int ||
        document['schemaVersion'] != 1 ||
        document['configuration'] is! Map<String, dynamic>) {
      throw const FormatException(
          'Use the v1 envelope: schemaVersion: 1 and a configuration object. Only supported fields are accepted.');
    }
    final values = document['configuration'] as Map<String, dynamic>;
    if (values.keys.toSet().difference(fields).isNotEmpty) {
      throw const FormatException(
          'Unsupported configuration fields. Credentials, tokens and passwords must not be included.');
    }
    for (final field in ['projectId', 'bucketName', 'location']) {
      if (values[field] is! String ||
          (values[field] as String).trim().isEmpty) {
        throw FormatException(
            '$field is required and must be a non-empty string.');
      }
    }
    final project = values['projectId'] as String;
    if (!RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(project) ||
        project.contains('google') ||
        project.contains('ssl')) {
      throw const FormatException(
          'projectId: use the supported 6–30 character lowercase project ID format.');
    }
    final bucket = values['bucketName'] as String;
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$').hasMatch(bucket) ||
        bucket.startsWith('goog') ||
        RegExp(r'g[o0]{2}gle').hasMatch(bucket)) {
      throw const FormatException(
          'bucketName: use 3–63 lowercase letters, digits or hyphens, without reserved Google names.');
    }
    if (!locations.contains(values['location'])) {
      throw const FormatException(
          'location: use europe-west9, us-central1 or northamerica-northeast1.');
    }
    for (final entry in const <String, Object>{
      'storageClass': 'STANDARD',
      'uniformBucketLevelAccess': true,
      'publicAccessPrevention': 'enforced'
    }.entries) {
      if (values.containsKey(entry.key) && values[entry.key] != entry.value) {
        throw FormatException('${entry.key} must be ${entry.value}.');
      }
    }
    return ResourceConfiguration(schemaVersion: 1, values: values);
  }

  // jsonDecode otherwise silently collapses duplicate keys. Syntax is already
  // checked above; scan complete string tokens, never regex-match inside values.
  static void _checkDuplicateKeys(String text) {
    final objects = <Set<String>>[];
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '{') {
        objects.add({});
      } else if (text[i] == '}') {
        objects.removeLast();
      } else if (text[i] == '"') {
        final start = i++;
        while (i < text.length) {
          if (text[i] == r'\') {
            i += 2;
            continue;
          }
          if (text[i] == '"') break;
          i++;
        }
        var next = i + 1;
        while (next < text.length && text[next].trim().isEmpty) {
          next++;
        }
        if (next < text.length && text[next] == ':' && objects.isNotEmpty) {
          final key = (jsonDecode(text.substring(start, i + 1)) as String)
              .toLowerCase();
          if (!objects.last.add(key)) {
            throw const FormatException(
                'Duplicate JSON fields are not allowed.');
          }
        }
      }
    }
  }
}
