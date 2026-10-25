import 'package:equatable/equatable.dart';
import 'grid_position.dart';

/// Blacksmith metadata only. No bucket name, cloud configuration or deployment.
class PersistedResource extends Equatable {
  const PersistedResource(
      {required this.id,
      required this.designId,
      required this.position,
      this.name = displayName,
      this.type = storageType});
  static const storageType = 'gcp.storage.bucket';
  static const catalogCode = 'storage';
  static const displayName = 'Cloud Storage';
  final String id;
  final String designId;
  final GridPos position;
  final String name;
  final String type;
  int get x => position.col;
  int get y => position.row;
  static bool validId(String value) =>
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(value) &&
      value != '00000000-0000-0000-0000-000000000000';
  @override
  List<Object?> get props => [id, designId, position, name, type];
}
