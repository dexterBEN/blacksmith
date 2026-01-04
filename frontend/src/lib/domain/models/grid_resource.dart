import 'package:equatable/equatable.dart';
import 'grid_position.dart';

enum Provider { gcp, aws, azure, generic, none }

enum ResourceType {
  storageBucket,
  database,
  vm,
  loadBalancer,
  cache,
}

class GridResource extends Equatable {
  /// set by backend (Guid)
  final String? id;

  final String name;

  final ResourceType type;

  /// Provider (optional)
  final Provider? provider;

  /// resource position
  final GridPos position;

  /// Texture UI Godot
  final String texturePath;

  const GridResource({
    this.id,
    required this.name,
    required this.type,
    required this.provider,
    required this.position,
    required this.texturePath,
  });

  GridResource copyWith({
    String? id,
    String? name,
    ResourceType? type,
    Provider? provider,
    GridPos? pos,
    String? texturePath,
  }) {
    return GridResource(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      provider: provider ?? this.provider,
      position: pos ?? this.position,
      texturePath: texturePath ?? this.texturePath,
    );
  }

  @override
  List<Object?> get props => [id, name, type, provider, position, texturePath];
}