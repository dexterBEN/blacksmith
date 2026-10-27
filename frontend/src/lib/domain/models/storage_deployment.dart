import 'package:equatable/equatable.dart';

/// Durable backend evidence; a saved configuration is not evidence of deployment.
class StorageDeployment extends Equatable {
  const StorageDeployment(
      {required this.id,
      required this.resourceId,
      required this.designId,
      required this.resourceRevision,
      required this.projectId,
      required this.bucketName,
      required this.location,
      required this.status,
      required this.code,
      required this.ownershipVerified});
  final String id,
      resourceId,
      designId,
      projectId,
      bucketName,
      location,
      status,
      code;
  final int resourceRevision;
  final bool ownershipVerified;
  String describe(int? currentRevision) =>
      'Deployment: $status · $code · revision $resourceRevision'
      '${currentRevision == resourceRevision ? "" : " (older configuration)"}';
  @override
  List<Object?> get props => [
        id,
        resourceId,
        designId,
        resourceRevision,
        projectId,
        bucketName,
        location,
        status,
        code,
        ownershipVerified
      ];
}
