import 'dart:async' as async;
import 'dart:ffi';
import 'dart:math' as math;
import 'package:godot_dart/godot_dart.dart';
import '../../core/di/service_locator.dart' as di;
import '../../core/runtime_shutdown.dart';
import '../../domain/bloc/design/design_cubit.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_event.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../../domain/models/grid_position.dart';
import '../../domain/models/resource_kind.dart';
import 'grid_layout.dart';
import 'resource_palette_3d.dart';
import 'resource_picker_draft.dart';
import 'resource_visuals_3d.dart';
import 'design_editor_3d.dart';
import 'workspace_3d.dart';

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
  DesignEditor3D? _designEditor;
  Workspace3D? _workspace;
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
    final window = getTree()!.getRoot()!;
    window.setMinSize(
        Vector2i.fromXY(Workspace3D.minimumWidth, Workspace3D.minimumHeight));
    installRuntimeShutdownHook(window);
    Workspace3D.attach(this);
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
    _palette = ResourcePalette3D(this, (kind, target) async {
      final bloc = _bloc;
      if (!_active ||
          (_designEditor?.isOpen ?? false) ||
          bloc == null ||
          bloc.isClosed ||
          bloc.state.selected != target) {
        throw const ResourcePickerFailure(
            'The selected tile is no longer available.');
      }
      if (kind == ResourceKind.cloudStorage) {
        if (!di.sl.isRegistered<DesignCubit>()) {
          throw const ResourcePickerFailure(
              'Create or open a Design to configure Cloud Storage.');
        }
        final cubit = di.sl<DesignCubit>();
        cubit.openResourceConfiguration();
        if (cubit.state.configurationDraft == null) {
          throw ResourcePickerFailure(
              cubit.state.error ?? cubit.state.persistenceMessage);
        }
      } else {
        final alreadyPlaced = bloc.state.tiles[target] == kind;
        final applied = alreadyPlaced
            ? null
            : bloc.stream
                .firstWhere((state) =>
                    state.selected != target || state.tiles[target] == kind)
                .timeout(const Duration(seconds: 10));
        bloc.add(PlaceResource(kind));
        if (applied != null) {
          final result = await applied;
          if (result.selected != target || result.tiles[target] != kind) {
            throw const ResourcePickerFailure(
                'Placement was not applied to the selected tile.');
          }
        }
      }
    }, onPlaced: () => _workspace?.dismissResources());
    // The camera is fixed: react to viewport changes instead of polling Godot
    // through Dart on every rendered frame. The connection is owned by this node.
    getViewport()!.sizeChanged.connect(this, _resizeWorkspace);
    Workspace3D.viewport(this).sizeChanged.connect(this, _fitCamera);
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
    _designEditor = DesignEditor3D(
        this, di.sl.isRegistered<DesignCubit>() ? di.sl<DesignCubit>() : null,
        (open) {
      _renderPalette(bloc.state, blocked: open);
    });
    _workspace = Workspace3D(this,
        onResourcesOpened: () => _palette?.open(),
        onResourcesClosed: () => _palette?.close(),
        configureStorage: () {
          if (_active &&
              !(_designEditor?.isOpen ?? false) &&
              di.sl.isRegistered<DesignCubit>()) {
            di.sl<DesignCubit>().openResourceConfiguration();
          }
        });
    _resizeWorkspace();
    _stateSubscription = bloc.stream.listen((state) {
      if (_active) _renderState(state);
    });
    _renderState(bloc.state);
    setProcessUnhandledInput(true);
    setProcessInput(true);
    GD.print(Variant('[Isometric3DGrid] 36 shared beveled tiles ready. '
        'bloc=${_ownsBloc ? "local" : "shared"} resources=${_resources.length}'));
  }

  @override
  void vInput(InputEvent? event) {
    if (_active && (_workspace?.isResourcesOpen ?? false)) {
      if (_workspace!.handleInput(event)) getViewport()!.setInputAsHandled();
      return;
    }
    if (_active && (_designEditor?.handleInput(event) ?? false)) {
      getViewport()!.setInputAsHandled();
      return;
    }
    if (_active &&
        !(_designEditor?.isOpen ?? false) &&
        (_workspace?.handleInput(event) ?? false)) {
      getViewport()!.setInputAsHandled();
    }
  }

  @override
  void vUnhandledInput(InputEvent? event) {
    final bloc = _bloc;
    if (!_active ||
        (_designEditor?.isOpen ?? false) ||
        bloc == null ||
        bloc.isClosed ||
        event is! InputEventMouseButton ||
        event.getButtonIndex() != MouseButton.left ||
        !event.isPressed()) {
      return;
    }
    final rect = Workspace3D.canvasRect(this);
    if (!rect.hasPoint(event.getPosition()) ||
        (_workspace?.blocksPointer(event.getPosition()) ?? false)) {
      return;
    }
    final viewportSize = Workspace3D.viewport(this).getVisibleRect().size;
    final local = event.getPosition() - rect.position;
    final point = Vector2(
        x: local.x * viewportSize.x / rect.size.x,
        y: local.y * viewportSize.y / rect.size.y);
    final camera = Workspace3D.camera(this);
    final worldOrigin = camera.projectRayOrigin(point);
    final worldDirection = camera.projectRayNormal(point);
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
    _renderPalette(state, blocked: _designEditor?.isOpen ?? false);
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

  void _renderPalette(IsomapGridState state, {required bool blocked}) {
    final cubit =
        di.sl.isRegistered<DesignCubit>() ? di.sl<DesignCubit>() : null;
    final canConfigure =
        cubit?.state.active != null && (cubit?.supportsPersistence ?? false);
    _palette?.render(state, blocked: blocked, canConfigure: canConfigure);
    _workspace?.render(state, blocked: blocked, canConfigure: canConfigure);
  }

  @override
  void vExitTree() {
    _active = false;
    _designEditor?.dispose();
    _designEditor = null;
    final subscription = _stateSubscription;
    _stateSubscription = null;
    if (subscription != null) async.unawaited(subscription.cancel());
    final bloc = _bloc;
    _bloc = null;
    if (_ownsBloc && bloc != null) async.unawaited(bloc.close());
    _tiles.clear();
    _palette?.close();
    _palette = null;
    _workspace = null;
    _resourceRoot = null;
    // Scene-owned controls/cubes are freed with the scene, not by the BLoC.
    _resources.clear();
    _resourceScenes.clear();
    _baseMaterial = null;
    _selectionMaterial = null;
  }

  void _resizeWorkspace() {
    final size = getViewport()!.getVisibleRect().size;
    _workspace?.resize();
    _designEditor?.resize(size);
    _fitCamera();
  }

  void _fitCamera() {
    final size = Workspace3D.viewport(this).getVisibleRect().size;
    if (size.x <= 24 || size.y <= 24) return;
    // Fixed 45° yaw and 35.264° elevation. Reserve the maximum cube height
    // even when empty: placement must never zoom/pan the board. The conservative
    // envelope includes the board underside and a cube on any perimeter tile.
    const bottom = -GridLayout3D.tileHeight / 2;
    const top = GridLayout3D.tileHeight / 2 + resourceScale;
    final projectedWidth = (layout.width + layout.depth) / math.sqrt(2);
    final projectedHeight = (layout.width + layout.depth) / math.sqrt(6) +
        (top - bottom) * math.sqrt(2 / 3);
    final unitsPerPixel = math.max(
            projectedWidth / (size.x - 24), projectedHeight / (size.y - 24)) *
        1.04;
    final projectedCenter = (top + bottom) / 2 * math.sqrt(2 / 3);
    final camera = Workspace3D.camera(this);
    // Fit the full-window render viewport; UI overlays reserve no camera space.
    // Selection input maps the main viewport point to this canvas before picking.
    camera
      ..setOrthogonal(unitsPerPixel * size.y, 0.1, 50)
      ..setVOffset(projectedCenter);
  }
}
