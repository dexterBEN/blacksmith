import 'dart:ffi';
import 'dart:math' as math;
import 'package:godot_dart/godot_dart.dart';
import '../../domain/models/grid_position.dart';
import 'grid_layout.dart';

part 'isometric_3d_grid.g.dart';

@GodotScript()
class Isometric3DGrid extends Node3D {
  @pragma('vm:entry-point')
  static ExtensionTypeInfo<Isometric3DGrid> get sTypeInfo =>
      _$Isometric3DGridTypeInfo();
  @override
  ExtensionTypeInfo<Isometric3DGrid> get typeInfo => sTypeInfo;

  @pragma('vm:entry-point')
  Isometric3DGrid() : super();

  @pragma('vm:entry-point')
  Isometric3DGrid.withNonNullOwner(Pointer<Void> owner)
      : super.withNonNullOwner(owner);

  static const layout = GridLayout3D();

  @override
  void vReady() {
    final grid = getNodeT<Node3D>('GridRoot')!;
    final scene = ResourceLoader.singleton
        .load('res://scenes/isometric_3d/tile.tscn')! as PackedScene;
    for (var row = 0; row < layout.rows; row++) {
      for (var col = 0; col < layout.cols; col++) {
        final position = layout.worldPosition(GridPos(row, col));
        final tile = scene.instantiate()! as MeshInstance3D;
        tile
          ..setName('Tile_${row}_$col')
          ..setPosition(Vector3(x: position.x, y: position.y, z: position.z));
        grid.addChild(tile);
      }
    }
    // The camera is fixed: react to viewport changes instead of polling Godot
    // through Dart on every rendered frame. The connection is owned by this node.
    getViewport()!.sizeChanged.connect(this, _fitCamera);
    _fitCamera();
    GD.print(Variant('[Isometric3DGrid] 36 shared beveled tiles ready.'));
  }

  void _fitCamera() {
    final size = getViewport()!.getVisibleRect().size;
    if (size.x <= 0 || size.y <= 0) return;
    // Fixed 45° yaw and 35.264° elevation. Fit the complete tile AABB with a
    // 12% margin; the logical mapping remains independent of this projection.
    final projectedWidth = (layout.width + layout.depth) / math.sqrt(2);
    final projectedHeight = (layout.width + layout.depth) / math.sqrt(6) +
        GridLayout3D.tileHeight * math.sqrt(2 / 3);
    final camera = getNodeT<Camera3D>('Camera3D')!;
    camera.setOrthogonal(
      math.max(projectedHeight, projectedWidth * size.y / size.x) * 1.12,
      0.1,
      50,
    );
  }
}
