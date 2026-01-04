import 'dart:convert';
import 'package:http/http.dart' as http;

class ResourcesApi {
  ResourcesApi({this.baseUrl = 'http://localhost:5256'});

  final String baseUrl;

  Future<String> createResource({
    required String name,
    required String type,
    required int x,
    required int y,
  }) async {
    final uri = Uri.parse('$baseUrl/resources');

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'type': type,
        'x': x,
        'y': y,
      }),
    );

    // backend send CreatedAtAction => 201
    if (resp.statusCode == 201 || resp.statusCode == 200) {
      final map = jsonDecode(resp.body) as Map<String, dynamic>;

      // ASP.NET send normally "id"
      final id = (map['id'] ?? map['Id'])?.toString();
      if (id == null || id.isEmpty) {
        throw Exception('CreateResource OK but missing id: ${resp.body}');
      }

      return id;
    }

    throw Exception('CreateResource failed (${resp.statusCode}): ${resp.body}');
  }
}