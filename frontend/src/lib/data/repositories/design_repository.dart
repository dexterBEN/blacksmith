import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/design.dart';

/// Only safe, locally authored messages cross the data/UI boundary.
class DesignFailure implements Exception {
  const DesignFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Owns its HTTP client. No Godot dependencies, cloud operations, or POST retry.
class DesignRepository {
  DesignRepository({
    required String baseUrl,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _baseUrl = _validateUrl(baseUrl),
        _timeout = requestTimeout,
        _client = client ?? http.Client() {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError('Request timeout must be positive.');
    }
  }

  final String _baseUrl;
  final Duration _timeout;
  final http.Client _client;
  bool _closed = false;
  static final _id = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static const _uncertain =
      'The Design may have been created. Check existing Designs through the API before submitting again.';

  static String _validateUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError(
          'Backend URL must be an absolute HTTP(S) URL without credentials.');
    }
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  Future<Design> create(String name) async {
    final invalid = Design.validateName(name);
    if (invalid != null) throw DesignFailure(invalid);
    final response = await _send(
        () => _client.post(Uri.parse('$_baseUrl/designs'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'name': name.trim()})),
        creating: true);
    if (response.statusCode != 201) {
      if (response.statusCode == 400) {
        throw const DesignFailure(
            'The backend rejected the Design name. Use 1–200 characters.');
      }
      throw DesignFailure(
          'Design creation failed (HTTP ${response.statusCode}). '
          '${response.statusCode >= 500 || response.statusCode >= 200 && response.statusCode < 400 ? _uncertain : 'Check the backend configuration and try again.'}');
    }
    final design = _decode(response, creating: true);
    if (design.name != name.trim()) {
      throw const DesignFailure(
          'The backend returned an unexpected Design. $_uncertain');
    }
    return design;
  }

  /// Read-back for integration verification; no Design browser is introduced.
  Future<Design> getById(String id) async {
    if (!_id.hasMatch(id)) {
      throw const DesignFailure('Invalid Design identifier.');
    }
    final response = await _send(
        () => _client.get(Uri.parse('$_baseUrl/designs/$id')),
        creating: false);
    if (response.statusCode != 200) {
      throw DesignFailure(
          'Unable to retrieve the Design (HTTP ${response.statusCode}).');
    }
    final design = _decode(response, creating: false);
    if (design.id.toLowerCase() != id.toLowerCase()) {
      throw const DesignFailure('The backend returned an unexpected Design.');
    }
    return design;
  }

  Future<http.Response> _send(Future<http.Response> Function() send,
      {required bool creating}) async {
    if (_closed) throw const DesignFailure('The backend client is closed.');
    try {
      return await send().timeout(_timeout);
    } on TimeoutException {
      throw DesignFailure(
          'The backend request timed out. ${creating ? _uncertain : 'Check the backend connection.'}');
    } on Exception {
      throw DesignFailure(
          'Unable to reach the backend. ${creating ? _uncertain : 'Check the backend connection.'}');
    }
  }

  Design _decode(http.Response response, {required bool creating}) {
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic> &&
          json['id'] is String &&
          _id.hasMatch(json['id'] as String) &&
          json['id'] != '00000000-0000-0000-0000-000000000000' &&
          json['name'] is String &&
          Design.validateName(json['name'] as String) == null) {
        return Design(id: json['id'] as String, name: json['name'] as String);
      }
    } on FormatException {/* Never expose the response body. */}
    throw DesignFailure(
        'The backend returned an invalid Design response. ${creating ? _uncertain : ''}'
            .trim());
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
