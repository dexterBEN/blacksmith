import 'package:test/test.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';
import 'package:blacksmith_front/prototypes/isometric_3d/resource_visuals_3d.dart';

void main() {
  test('four local GCP identities map to the four existing native cube scenes',
      () {
    expect(resourceVisuals3D.keys.toSet(), ResourceKind.values.toSet());
    expect(
        resourceVisuals3D
            .map((kind, visual) => MapEntry(kind, visual.scenePath)),
        {
          ResourceKind.cloudStorage:
              'res://assets/models/resource_cubes/cloud_storage.tscn',
          ResourceKind.computeEngine:
              'res://assets/models/resource_cubes/compute_engine.tscn',
          ResourceKind.cloudVpn:
              'res://assets/models/resource_cubes/cloud_vpn.tscn',
          ResourceKind.cloudLoadBalancing:
              'res://assets/models/resource_cubes/load_balancer.tscn',
        });
    expect(resourceVisuals3D.values.map((visual) => visual.buttonName).toSet(),
        {'CloudStorage', 'ComputeEngine', 'CloudVpn', 'CloudLoadBalancing'});
  });
}
