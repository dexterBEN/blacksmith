import 'dart:convert';
import 'package:http/http.dart' as http;


class CloudServicesApi {
  CloudServicesApi({
    this.baseUrl = 'http://localhost:5256',
  });

  final String baseUrl;

  Future<String> ping() async {
    final uri = Uri.parse('$baseUrl/cloud_services/ping');
    final resp = await http.get(uri);

    if (resp.statusCode == 200) {
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      return map['message'] as String? ?? 'OK';
    }

    throw Exception(
      'Ping failed (${resp.statusCode}): ${resp.body}',
    );
  }

  Future<String> createBucket({
    required String projectId,
    required String bucketName,
  }) async {
    final uri = Uri.parse('$baseUrl/cloud_services/create-bucket')
        .replace(queryParameters: {
      'projectId': projectId,
      'bucketName': bucketName,
    });

    final resp = await http.post(uri);

    if (resp.statusCode == 200) {
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      return map['message'] as String? ?? 'Bucket created';
    }

    throw Exception(
      'CreateBucket failed (${resp.statusCode}): ${resp.body}',
    );
  }
}
