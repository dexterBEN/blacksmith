import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../repositories/cloud_storage_failure.dart';

class CloudServicesApi {
  CloudServicesApi({
    required String baseUrl,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 30),
  })  : _baseUrl = _validateBaseUrl(baseUrl),
        _requestTimeout = _validateTimeout(requestTimeout),
        _client = client ?? http.Client();

  final String _baseUrl;
  final Duration _requestTimeout;
  final http.Client _client;
  bool _closed = false;

  static String _validateBaseUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('Backend URL must be an absolute HTTP(S) URL.');
    }
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  static Duration _validateTimeout(Duration value) {
    if (value <= Duration.zero) {
      throw ArgumentError('Request timeout must be positive.');
    }
    return value;
  }

  Future<String> ping() {
    final uri = Uri.parse('$_baseUrl/cloud_services/ping');
    return _request(() => _client.get(uri), fallback: 'OK');
  }

  Future<String> createBucket({
    required String projectId,
    required String bucketName,
  }) async {
    final uri = Uri.parse('$_baseUrl/cloud_services/create-bucket')
        .replace(queryParameters: {
      'projectId': projectId,
      'bucketName': bucketName,
    });

    return _request(
      () => _client.post(uri),
      fallback: 'Bucket created',
      createsBucket: true,
    );
  }

  Future<String> _request(
    Future<http.Response> Function() send, {
    required String fallback,
    bool createsBucket = false,
  }) async {
    if (_closed) {
      throw const CloudStorageFailure('The backend client is closed.');
    }
    final http.Response response;
    try {
      response = await send().timeout(_requestTimeout);
    } on TimeoutException {
      throw CloudStorageFailure(createsBucket
          ? 'The request timed out. Bucket creation may still complete on the server.'
          : 'The backend request timed out.');
    } on Exception {
      throw const CloudStorageFailure('Unable to reach the backend.');
    }
    if (response.statusCode != 200) {
      throw CloudStorageFailure(
        'Backend rejected the request (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const CloudStorageFailure('The backend returned invalid JSON.');
    }
    if (decoded is! Map<String, Object?>) {
      throw const CloudStorageFailure(
          'The backend returned an invalid response.');
    }
    final message = decoded['message'];
    if (message == null) return fallback;
    if (message is! String) {
      throw const CloudStorageFailure(
          'The backend returned an invalid message.');
    }
    return message;
  }

  /// This API instance owns its client, including an injected client.
  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
