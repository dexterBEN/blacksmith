import 'domain/models/resource_kind.dart';

class ResourceVisual {
  const ResourceVisual(this.code, this.path, this.tooltip);

  final String code;
  final String path;
  final String tooltip;
}

const resourceVisuals = {
  ResourceKind.cloudStorage: ResourceVisual(
    'gcp:cloud_storage',
    'res://src/assets/gcp_cloud_storage.png',
    'GCP · Cloud Storage',
  ),
  ResourceKind.computeEngine: ResourceVisual(
    'gcp:compute_engine',
    'res://src/assets/gcp_compute_engine.png',
    'GCP · Compute Engine',
  ),
};

ResourceKind? resourceKindFromCode(String code) {
  for (final entry in resourceVisuals.entries) {
    if (entry.value.code == code) return entry.key;
  }
  return null;
}
