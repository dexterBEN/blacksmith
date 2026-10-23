import '../../domain/models/resource_kind.dart';

/// Presentation metadata only; no backend classification or persistence mapping.
class ResourceVisual3D {
  const ResourceVisual3D(this.buttonName, this.scenePath);
  final String buttonName;
  final String scenePath;
}

const resourceVisuals3D = {
  ResourceKind.cloudStorage: ResourceVisual3D(
      'CloudStorage', 'res://assets/models/resource_cubes/cloud_storage.tscn'),
  ResourceKind.computeEngine: ResourceVisual3D('ComputeEngine',
      'res://assets/models/resource_cubes/compute_engine.tscn'),
  ResourceKind.cloudVpn: ResourceVisual3D(
      'CloudVpn', 'res://assets/models/resource_cubes/cloud_vpn.tscn'),
  ResourceKind.cloudLoadBalancing: ResourceVisual3D('CloudLoadBalancing',
      'res://assets/models/resource_cubes/load_balancer.tscn'),
};
