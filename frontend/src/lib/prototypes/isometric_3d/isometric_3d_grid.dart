import 'dart:async' as async;
import 'dart:ffi';
import 'dart:math' as math;
import 'package:godot_dart/godot_dart.dart';
import '../../core/di/service_locator.dart' as di;
import '../../domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_event.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../../domain/models/grid_position.dart';
import '../../domain/models/resource_kind.dart';
import 'grid_layout.dart';
import 'resource_palette_3d.dart';
import 'resource_visuals_3d.dart';

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
  final _tiles = <GridPos, MeshInstance3D>{};
  IsomapGridBloc? _bloc;
  async.StreamSubscription<IsomapGridState>? _stateSubscription;
  ResourcePalette3D? _palette;
  Node3D? _resourceRoot;
  // Render caches derived exclusively from BLoC state, not placement state.
  final _resources = <GridPos, ({ResourceKind kind, Node3D node})>{};
  final _resourceScenes = <ResourceKind, PackedScene>{};
  static const resourceScale = 0.68;
  Material? _baseMaterial;
  Material? _selectionMaterial;
  bool _active = false;
  bool _ownsBloc = false;

  @override
  void vReady() {
    _active = true;
    final grid = getNodeT<Node3D>('GridRoot')!;
    final scene = ResourceLoader.singleton
        .load('res://scenes/isometric_3d/tile.tscn')! as PackedScene;
    _selectionMaterial = ResourceLoader.singleton
        .load('res://scenes/isometric_3d/selection_material.tres')! as Material;
    for (var row = 0; row < layout.rows; row++) {
      for (var col = 0; col < layout.cols; col++) {
        final position = layout.worldPosition(GridPos(row, col));
        final tile = scene.instantiate()! as MeshInstance3D;
        tile
          ..setName('Tile_${row}_$col')
          ..setPosition(Vector3(x: position.x, y: position.y, z: position.z));
        grid.addChild(tile);
        _baseMaterial ??= tile.getMaterialOverride();
        _tiles[GridPos(row, col)] = tile;
      }
    }
    _resourceRoot = getNodeT<Node3D>('ResourceRoot')!;
    _palette = ResourcePalette3D(this, (kind) {
      final bloc = _bloc;
      if (_active && bloc != null && !bloc.isClosed) {
        bloc.add(PlaceResource(kind));
      }
    });
    // The camera is fixed: react to viewport changes instead of polling Godot
    // through Dart on every rendered frame. The connection is owned by this node.
    getViewport()!.sizeChanged.connect(this, _fitCamera);
    _fitCamera();
    // The isolated launcher registers a shared local-only BLoC. When this
    // scene is run by the application, reuse its existing DI registration.
    // If DI is unavailable, own a local diagnostic BLoC, as AppRoot does.
    try {
      if (di.sl.isRegistered<IsomapGridBloc>()) {
        _bloc = di.sl<IsomapGridBloc>();
      }
    } catch (_) {
      GD.pushWarning(Variant('[Isometric3DGrid] Using local selection state.'));
    }
    if (_bloc == null) {
      _bloc = IsomapGridBloc.local();
      _ownsBloc = true;
    }
    final bloc = _bloc!;
    _stateSubscription = bloc.stream.listen((state) {
      if (_active) _renderState(state);
    });
    _renderState(bloc.state);
    setProcessUnhandledInput(true);
    GD.print(Variant('[Isometric3DGrid] 36 shared beveled tiles ready.'));
  }

  @override
  void vUnhandledInput(InputEvent? event) {
    final bloc = _bloc;
    if (!_active ||
        bloc == null ||
        bloc.isClosed ||
        event is! InputEventMouseButton ||
        event.getButtonIndex() != MouseButton.left ||
        !event.isPressed()) {
      return;
    }
    final camera = getNodeT<Camera3D>('Camera3D')!;
    final worldOrigin = camera.projectRayOrigin(event.getPosition());
    final worldDirection = camera.projectRayNormal(event.getPosition());
    // The ray and tile mapping use the same local axes, even if the scene
    // root is later translated or rotated. Camera/navigation is unchanged.
    final origin = toLocal(worldOrigin);
    final end = toLocal(worldOrigin + worldDirection);
    final position = layout.pickRay(
      origin: (x: origin.x, y: origin.y, z: origin.z),
      direction: (
        x: end.x - origin.x,
        y: end.y - origin.y,
        z: end.z - origin.z
      ),
    );
    if (position == null) return;
    bloc.add(TileClicked(position));
    getViewport()!.setInputAsHandled();
  }

  void _renderSelection(GridPos? selected) {
    // This map caches Godot nodes, not selection state. The BLoC remains the
    // only authority; one shared highlight resource is assigned to one tile.
    for (final entry in _tiles.entries) {
      entry.value.setMaterialOverride(
        entry.key == selected ? _selectionMaterial : _baseMaterial,
      );
    }
    GD.print(Variant('[Isometric3DGrid] Selected tile: ${selected ?? "none"}'));
  }

  void _renderState(IsomapGridState state) {
    _renderSelection(state.selected);
    _palette?.render(state);
    final root = _resourceRoot!;
    for (final position in _resources.keys.toList()) {
      if (state.tiles[position] != _resources[position]!.kind) {
        final previous = _resources.remove(position)!;
        root.removeChild(previous.node);
        previous.node.queueFree();
      }
    }
    for (final entry in state.tiles.entries) {
      if (_resources.containsKey(entry.key) || !_tiles.containsKey(entry.key)) {
        continue;
      }
      final packed = _resourceScenes.putIfAbsent(
          entry.value,
          () => ResourceLoader.singleton
              .load(resourceVisuals3D[entry.value]!.scenePath)! as PackedScene);
      final node = packed.instantiate()! as Node3D;
      final position = layout.worldPosition(entry.key);
      node
        ..setName('Resource_${entry.key.row}_${entry.key.col}')
        ..setPosition(Vector3(
            x: position.x, y: GridLayout3D.tileHeight / 2, z: position.z))
        ..setScale(
            Vector3(x: resourceScale, y: resourceScale, z: resourceScale));
      root.addChild(node);
      _resources[entry.key] = (kind: entry.value, node: node);
    }
  }

  @override
  void vExitTree() {
    _active = false;
    final subscription = _stateSubscription;
    _stateSubscription = null;
    if (subscription != null) async.unawaited(subscription.cancel());
    final bloc = _bloc;
    _bloc = null;
    if (_ownsBloc && bloc != null) async.unawaited(bloc.close());
    _tiles.clear();
    _palette = null;
    _resourceRoot = null;
    // Scene-owned controls/cubes are freed with the scene, not by the BLoC.
    _resources.clear();
    _resourceScenes.clear();
    _baseMaterial = null;
    _selectionMaterial = null;
  }

  void _fitCamera() {
    final size = getViewport()!.getVisibleRect().size;
    if (size.x <= 0 || size.y <= 0) return;
    _palette?.resize(size);
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
