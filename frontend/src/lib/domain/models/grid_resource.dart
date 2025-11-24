import 'grid_position.dart';

// domain/models/resource.dart
import 'package:equatable/equatable.dart';

class GridResource extends Equatable {
  final String id;          // interne (uuid ou "gcp:cloud_storage")
  final String texturePath; // chemin Godot, ex: 'res://src/assets/gcp_cloud_storage.jpeg';

  const GridResource({
    required this.id,
    required this.texturePath,
  });

  @override
  List<Object?> get props => [id, texturePath];
}


enum Provider { gcp, aws, azure, generic, none }

enum ResourceType {
  storageBucket,
  database,
  vm,
  loadBalancer,
  cache,
  // ...
}