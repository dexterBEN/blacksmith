import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/grid_position.dart';
import '../../domain/models/persisted_resource.dart';
import '../../domain/models/placed_resource.dart';
import '../../domain/models/resource_configuration.dart';
import 'cloud_storage_configuration_document.dart';

class ResourceFailure implements Exception {
  const ResourceFailure(this.message,
      {this.ambiguous = false, this.code, this.status});
  final String message;
  final bool ambiguous;
  final String? code;
  final int? status;
  @override
  String toString() => message;
}

/// Owns wire contracts. No Godot dependencies, provisioning or automatic retry.
class ResourceRepository {
  ResourceRepository(
      {required String baseUrl,
      http.Client? client,
      Duration requestTimeout = const Duration(seconds: 15)})
      : _base = _validateUrl(baseUrl),
        _client = client ?? http.Client(),
        _timeout = requestTimeout {
    if (_timeout <= Duration.zero) {
      throw ArgumentError('Invalid request timeout.');
    }
  }
  final String _base;
  final http.Client _client;
  final Duration _timeout;
  bool _closed = false;

  String configurationText(ResourceConfiguration? value,
          {bool legacy = false}) =>
      CloudStorageConfigurationDocument.format(value, legacy: legacy);
  ResourceConfiguration parseConfiguration(String text) {
    try {
      return CloudStorageConfigurationDocument.parse(text);
    } on FormatException catch (error) {
      throw ResourceFailure(error.message, code: 'invalid_configuration');
    }
  }

  static String _validateUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('Backend URL must be HTTP(S), without credentials.');
    }
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  void _id(String id) {
    if (!PersistedResource.validId(id)) {
      throw const ResourceFailure('Invalid Resource or Design identifier.');
    }
  }

  void _position(GridPos p, int rows, int cols) {
    if (p.row < 0 || p.row >= rows || p.col < 0 || p.col >= cols) {
      throw const ResourceFailure('The placement is outside the current grid.');
    }
  }

  Future<http.Response> _send(Future<http.Response> Function() send,
      {bool write = false}) async {
    if (_closed) throw const ResourceFailure('The backend client is closed.');
    try {
      return await send().timeout(_timeout);
    } on Exception {
      throw ResourceFailure(
          write
              ? 'Save outcome unknown. Check Save reads the backend before another write.'
              : 'Unable to read backend data. Check the connection and try again.',
          ambiguous: write,
          code: 'transport');
    }
  }

  dynamic _json(http.Response response, {bool write = false}) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw _invalid(write);
    }
  }

  ResourceFailure _invalid(bool write) => ResourceFailure(
      'Unsupported or invalid backend data. The local grid is preserved.',
      ambiguous: write,
      code: 'invalid_response');

  Never _error(http.Response response, {bool write = false}) {
    final status = response.statusCode;
    const codes = {
      'tile_occupied',
      'resource_exists',
      'revision_conflict',
      'resource_not_found',
      'design_not_found',
      'catalog_not_found',
      'invalid_payload',
      'precondition_required',
      'resource_design_mismatch'
    };
    String? code;
    try {
      final body = jsonDecode(response.body);
      if (body is Map &&
          body['code'] is String &&
          codes.contains(body['code'])) {
        code = body['code'] as String;
      }
    } on FormatException {/* Only fixed messages cross the boundary. */}
    final message = switch (status) {
      400 =>
        'The backend rejected the Resource data. Local changes are preserved.',
      409 =>
        'Resource or tile conflict. Open the Design to review backend changes.',
      412 =>
        'Resource identity or revision conflict. Read the original Resource before retrying.',
      428 =>
        'The backend requires a write precondition. No replacement write was sent.',
      404 => 'The Design, Resource or catalog entry is missing.',
      413 => 'The Resource request exceeds the 16 KiB limit.',
      _ => 'The backend operation failed.'
    };
    String? fieldError;
    if (status == 400) {
      // The backend emits fixed validator messages, not a field dictionary.
      // Accept only known literals; never echo arbitrary response/input text.
      const safeErrors = {
        'projectId is required and must be a non-empty string.',
        'bucketName is required and must be a non-empty string.',
        'location is required and must be a non-empty string.',
        'projectId must be a supported 6-30 character lowercase Google project ID.',
        'bucketName must use the supported 3-63 character lowercase letter/digit/hyphen format without reserved Google names.',
        'location must be europe-west9, us-central1 or northamerica-northeast1.',
        'storageClass must be STANDARD.',
        'uniformBucketLevelAccess must be true.',
        'publicAccessPrevention must be enforced.',
        'Only schemaVersion 1 is supported.',
        'Unsupported or duplicate fields are not allowed.'
      };
      try {
        final body = jsonDecode(response.body);
        if (body is Map && safeErrors.contains(body['error'])) {
          fieldError = body['error'] as String;
        }
      } on FormatException {/* Keep fixed fallback. */}
    }
    throw ResourceFailure('${fieldError ?? message} (HTTP $status)',
        status: status,
        code: code,
        ambiguous: write &&
            !{400, 401, 403, 404, 409, 412, 413, 415, 428}.contains(status));
  }

  String _tag(String id, int revision) =>
      '"resource-${id.replaceAll('-', '').toLowerCase()}-r$revision"';

  PersistedResource _record(dynamic value, String designId, int rows, int cols,
      {bool write = false}) {
    if (value is! Map<String, dynamic>) throw _invalid(write);
    final id = value['id'],
        owner = value['designId'],
        catalog = value['resourceTypeId'];
    final x = value['x'], y = value['y'], revision = value['revision'];
    if (id is! String ||
        !PersistedResource.validId(id) ||
        owner is! String ||
        owner.toLowerCase() != designId.toLowerCase() ||
        !value.containsKey('resourceTypeId') ||
        catalog != null &&
            (catalog is! String || !PersistedResource.validId(catalog)) ||
        value['name'] is! String ||
        (value['name'] as String).trim().isEmpty ||
        value['type'] != PersistedResource.storageType ||
        x is! int ||
        y is! int ||
        x < 0 ||
        x >= cols ||
        y < 0 ||
        y >= rows ||
        revision is! int ||
        revision < 1 ||
        !value.containsKey('configuration')) {
      throw _invalid(write);
    }
    final state = value['configurationState'];
    ResourceConfiguration? configuration;
    if (state == 'validated') {
      final envelope = value['configuration'];
      if (envelope is! Map<String, dynamic> ||
          envelope['resourceId'] is! String ||
          (envelope['resourceId'] as String).toLowerCase() !=
              id.toLowerCase() ||
          envelope['schemaVersion'] != 1 ||
          envelope['schemaVersion'] is! int ||
          envelope['configuration'] is! Map<String, dynamic>) {
        throw _invalid(write);
      }
      final fields = envelope['configuration'] as Map<String, dynamic>;
      const allowed = {
        'projectId',
        'bucketName',
        'location',
        'storageClass',
        'uniformBucketLevelAccess',
        'publicAccessPrevention'
      };
      if (fields.keys.toSet().difference(allowed).isNotEmpty ||
          fields.length != allowed.length ||
          ['projectId', 'bucketName', 'location'].any((key) =>
              fields[key] is! String ||
              (fields[key] as String).trim().isEmpty) ||
          fields['storageClass'] != 'STANDARD' ||
          fields['uniformBucketLevelAccess'] != true ||
          fields['publicAccessPrevention'] != 'enforced') {
        throw _invalid(write);
      }
      configuration = ResourceConfiguration(schemaVersion: 1, values: fields);
    } else if (state != 'absent' || value['configuration'] != null) {
      throw ResourceFailure(
          'This Design contains an unsupported configuration or resource. No partial load was applied.',
          ambiguous: write,
          code: 'unsupported_configuration');
    }
    return PersistedResource(
        id: id.toLowerCase(),
        designId: owner.toLowerCase(),
        position: GridPos(y, x),
        name: value['name'] as String,
        type: value['type'] as String,
        catalogId: (catalog as String?)?.toLowerCase(),
        revision: revision,
        etag: _tag(id, revision),
        configuration: configuration,
        configurationState: state as String);
  }

  Future<List<PersistedResource>> listForDesign(String designId,
      {int rows = 6, int cols = 6}) async {
    _id(designId);
    final response = await _send(() => _client.get(
        Uri.parse('$_base/designs/$designId/resources?include=configuration')));
    if (response.statusCode != 200) _error(response);
    final data = _json(response);
    if (data is! List) throw _invalid(false);
    final records =
        data.map((row) => _record(row, designId, rows, cols)).toList();
    if (records.map((r) => r.id).toSet().length != records.length ||
        records.map((r) => r.position).toSet().length != records.length) {
      throw const ResourceFailure(
          'Duplicate Resource identities or occupied tiles. The local grid is preserved.',
          code: 'duplicate_resources');
    }
    return List.unmodifiable(records);
  }

  Future<PersistedResource> getById(String designId, String id,
      {int rows = 6, int cols = 6}) async {
    _id(designId);
    _id(id);
    final response = await _send(() =>
        _client.get(Uri.parse('$_base/resources/$id?include=configuration')));
    if (response.statusCode != 200) _error(response);
    final record = _record(_json(response), designId, rows, cols);
    if (record.id != id.toLowerCase() ||
        response.headers['etag'] != record.etag) {
      throw _invalid(false);
    }
    return record;
  }

  Future<String> _storageCatalogId() async {
    final response =
        await _send(() => _client.get(Uri.parse('$_base/resource-types')));
    if (response.statusCode != 200) _error(response);
    final data = _json(response);
    if (data is List) {
      final matches = data
          .whereType<Map<String, dynamic>>()
          .where((row) => row['code'] == PersistedResource.catalogCode)
          .toList();
      if (matches.length == 1 &&
          matches.single['id'] is String &&
          PersistedResource.validId(matches.single['id'] as String)) {
        return matches.single['id'] as String;
      }
    }
    throw const ResourceFailure(
        'The backend storage catalog entry is missing or invalid.');
  }

  /// Transitional metadata-only POST. Its server ID must be read back before confirmation.
  Future<PersistedResource> createCloudStorage(
      String designId, GridPos position,
      {int rows = 6, int cols = 6}) async {
    _id(designId);
    _position(position, rows, cols);
    final catalog = await _storageCatalogId();
    final response = await _send(
        () => _client.post(Uri.parse('$_base/resources'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'designId': designId,
              'resourceTypeId': catalog,
              'name': PersistedResource.displayName,
              'type': PersistedResource.storageType,
              'x': position.col,
              'y': position.row
            })),
        write: true);
    if (response.statusCode != 201) _error(response, write: true);
    final value = _json(response, write: true);
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        !PersistedResource.validId(value['id'] as String) ||
        value['x'] != position.col ||
        value['y'] != position.row ||
        value['type'] != PersistedResource.storageType ||
        value['name'] != PersistedResource.displayName) {
      throw _invalid(true);
    }
    return PersistedResource(
        id: (value['id'] as String).toLowerCase(),
        designId: designId.toLowerCase(),
        position: position,
        catalogId: catalog.toLowerCase());
  }

  /// Configured intents/test fixtures; no configuration is invented for palettes.
  Future<PersistedResource> writeConfigured(
      String designId, GridPos position, PlacedResource intent,
      {int rows = 6, int cols = 6}) async {
    _id(designId);
    _position(position, rows, cols);
    final id = (intent.id ?? intent.localKey).toLowerCase();
    _id(id);
    final config = intent.configuration;
    if (config == null) {
      throw const ResourceFailure(
          'Complete explicit configuration is required.');
    }
    if (intent.id != null && intent.etag == null) {
      throw const ResourceFailure('Read the Resource revision before editing.',
          code: 'precondition_required');
    }
    final catalog = intent.catalogId ?? await _storageCatalogId();
    final response = await _send(
        () => _client.put(Uri.parse('$_base/designs/$designId/resources/$id'),
            headers: {
              'Content-Type': 'application/json',
              if (intent.id == null)
                'If-None-Match': '*'
              else
                'If-Match': intent.etag!
            },
            body: jsonEncode({
              'name': intent.name,
              'type': intent.type,
              'resourceTypeId': catalog,
              'x': position.col,
              'y': position.row,
              'configuration': {
                'schemaVersion': config.schemaVersion,
                'configuration': config.values
              }
            })),
        write: true);
    if (response.statusCode != (intent.id == null ? 201 : 200)) {
      _error(response, write: true);
    }
    final record = _record(_json(response, write: true), designId, rows, cols,
        write: true);
    if (record.id != id ||
        record.position != position ||
        record.name != intent.name ||
        record.catalogId != catalog.toLowerCase() ||
        record.configuration != config) {
      throw _invalid(true);
    }
    return record;
  }

  void close() {
    if (!_closed) {
      _closed = true;
      _client.close();
    }
  }
}
