import '../../domain/models/resource_kind.dart';

/// Presentation metadata only; no backend classification or persistence mapping.
class ResourceVisual3D {
  const ResourceVisual3D(this.buttonName, this.scenePath, this.label);
  final String buttonName;
  final String scenePath;
  final String label;
}

const resourceVisuals3D = {
  ResourceKind.cloudStorage: ResourceVisual3D('CloudStorage',
      'res://assets/models/resource_cubes/cloud_storage.tscn', 'Cloud Storage'),
  ResourceKind.computeEngine: ResourceVisual3D(
      'ComputeEngine',
      'res://assets/models/resource_cubes/compute_engine.tscn',
      'Compute Engine'),
  ResourceKind.cloudVpn: ResourceVisual3D('CloudVpn',
      'res://assets/models/resource_cubes/cloud_vpn.tscn', 'Cloud VPN'),
  ResourceKind.cloudLoadBalancing: ResourceVisual3D(
      'CloudLoadBalancing',
      'res://assets/models/resource_cubes/load_balancer.tscn',
      'Load Balancing'),
};
