import '../services/cloud_services_api.dart';
export 'cloud_storage_failure.dart';

class CloudStorageRepository {
  CloudStorageRepository(this._api, {required String projectId})
      : _projectId = projectId;

  final CloudServicesApi _api;
  final String _projectId;

  Future<String> pingBackend() => _api.ping();

  Future<String> createBucket({
    required int row,
    required int col,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final bucketName = 'blacksmith-$row-$col-$ts'.toLowerCase();

    return _api.createBucket(
      projectId: _projectId,
      bucketName: bucketName,
    );
  }
}
