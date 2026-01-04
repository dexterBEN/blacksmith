import '../services/resources_api.dart';

abstract class ResourcesRepository {
  /// Retourne l'id (Guid string) créé par le backend
  Future<String> createResource({
    required String name,
    required String type,
    required int x,
    required int y,
  });
}

class ResourcesRepositoryImpl implements ResourcesRepository {
  ResourcesRepositoryImpl(this._api);

  final ResourcesApi _api;

  @override
  Future<String> createResource({
    required String name,
    required String type,
    required int x,
    required int y,
  }) {
    return _api.createResource(name: name, type: type, x: x, y: y);
  }
}