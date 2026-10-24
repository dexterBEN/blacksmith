import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/grid_position.dart';
import '../../domain/models/persisted_resource.dart';

class ResourceFailure implements Exception {
  const ResourceFailure(this.message, {this.ambiguous = false});
  final String message;
  final bool ambiguous;
  @override
  String toString() => message;
}

/// Existing metadata APIs only; one deliberate POST, no automatic write retry.
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
      throw const ResourceFailure('Invalid Design identifier.');
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
              ? 'Save outcome unknown. Use Check Save; no duplicate write will be sent.'
              : 'Unable to read backend data. Check the connection and try again.',
          ambiguous: write);
    }
  }

  dynamic _json(http.Response response, {bool write = false}) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw ResourceFailure('The backend returned invalid resource data.',
          ambiguous: write);
    }
  }

  Future<String> _storageCatalogId() async {
    final response =
        await _send(() => _client.get(Uri.parse('$_base/resource-types')));
    if (response.statusCode != 200) {
      throw const ResourceFailure('Unable to read the resource type catalog.');
    }
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

  PersistedResource _record(dynamic json, String designId, int rows, int cols,
      {bool scoped = true, bool write = false}) {
    if (json is Map<String, dynamic> &&
        json['id'] is String &&
        PersistedResource.validId(json['id'] as String) &&
        (!scoped ||
            json['designId'] is String &&
                (json['designId'] as String).toLowerCase() ==
                    designId.toLowerCase()) &&
        json['x'] is int &&
        json['y'] is int &&
        (json['x'] as int) >= 0 &&
        (json['x'] as int) < cols &&
        (json['y'] as int) >= 0 &&
        (json['y'] as int) < rows &&
        json['type'] == PersistedResource.storageType &&
        json['name'] is String &&
        (json['name'] as String).trim().isNotEmpty) {
      return PersistedResource(
          id: (json['id'] as String).toLowerCase(),
          designId: designId.toLowerCase(),
          position: GridPos(json['y'] as int, json['x'] as int),
          name: json['name'] as String,
          type: json['type'] as String);
    }
    throw ResourceFailure(
        'Unsupported, invalid or incorrectly owned resource. '
        'The local grid has not been replaced.',
        ambiguous: write);
  }

  Future<List<PersistedResource>> listForDesign(String designId,
      {int rows = 6, int cols = 6}) async {
    _id(designId);
    final response = await _send(
        () => _client.get(Uri.parse('$_base/designs/$designId/resources')));
    if (response.statusCode != 200) {
      throw ResourceFailure(
          'Unable to read Design resources (HTTP ${response.statusCode}).');
    }
    final data = _json(response);
    if (data is! List || data.length > 1) {
      throw const ResourceFailure('This workflow supports only an empty Design '
          'or one Cloud Storage resource. Existing data is unchanged.');
    }
    return data.map((json) => _record(json, designId, rows, cols)).toList();
  }

  Future<PersistedResource> createCloudStorage(
      String designId, GridPos position,
      {int rows = 6, int cols = 6}) async {
    _id(designId);
    if (position.row < 0 ||
        position.row >= rows ||
        position.col < 0 ||
        position.col >= cols) {
      throw const ResourceFailure('The placement is outside the grid.');
    }
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
    if (response.statusCode != 201) {
      throw ResourceFailure(
          'Resource save failed (HTTP ${response.statusCode}). '
          'Local placements are preserved.',
          ambiguous: !{400, 401, 403, 404}.contains(response.statusCode));
    }
    final record = _record(_json(response, write: true), designId, rows, cols,
        scoped: false, write: true);
    if (record.position != position ||
        record.name != PersistedResource.displayName) {
      throw const ResourceFailure(
          'The save response did not match the placement.',
          ambiguous: true);
    }
    return record;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
