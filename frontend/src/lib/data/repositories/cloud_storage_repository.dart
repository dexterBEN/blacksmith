import '../services/cloud_services_api.dart';


class CloudStorageRepository {
  CloudStorageRepository(this._api);

  final CloudServicesApi _api;

  Future<String> pingBackend() => _api.ping();

  Future<String> createBucket({
    required String bucketName,
    required int row,
    required int col,
  }) async {
    
    //final ts = DateTime.now().millisecondsSinceEpoch;
    //final bucketName = 'blacksmith-$row-$col-$ts'.toLowerCase();

    return _api.createBucket(
      projectId: 'isometric-app-sample',
      bucketName: bucketName,
    );
  }
}
