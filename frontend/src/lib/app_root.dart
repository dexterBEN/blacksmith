import 'dart:async';
import 'dart:ffi';
import 'package:godot_dart/godot_dart.dart';

import 'core/di/service_locator.dart' as di;
import 'core/runtime_shutdown.dart';
import 'domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'domain/bloc/isomap_grid/isomap_grid_state.dart';
import 'isomap_grid.dart';
import 'menu_overlay.dart';
import 'resource_visuals.dart';

part 'app_root.g.dart';

@GodotScript()
class AppRoot extends Node2D {
  @pragma('vm:entry-point')
  static ExtensionTypeInfo<AppRoot> get sTypeInfo => _$AppRootTypeInfo();
  @override
  ExtensionTypeInfo<AppRoot> get typeInfo => AppRoot.sTypeInfo;

  @pragma('vm:entry-point')
  AppRoot() : super();

  @pragma('vm:entry-point')
  AppRoot.withNonNullOwner(Pointer<Void> owner) : super.withNonNullOwner(owner);

  IsoMapGrid? _grid;
  MenuOverlay? _menu;
  IsomapGridBloc? _bloc;
  StreamSubscription<IsomapGridState>? _stateSubscription;
  bool _active = false;
  bool _ownsBloc = false;

  @override
  void vReady() {
    _active = true;
    final grid = getNodeT<IsoMapGrid>('IsoMapGrid')!;
    final menu = getNodeT<MenuOverlay>('MenuOverlay')!;
    _grid = grid;
    _menu = menu;

    try {
      if (!di.sl.isRegistered<IsomapGridBloc>()) di.setupServiceLocator();
      _bloc = di.sl<IsomapGridBloc>();
    } catch (_) {
      // Preserve the old local-only diagnostic behavior with the same logical
      // state machine. This instance has no repository or network client.
      _bloc = IsomapGridBloc.local();
      _ownsBloc = true;
      GD.pushWarning(Variant(
        '[AppRoot] Local diagnostic mode: using scene-owned editor state.',
      ));
    }

    final bloc = _bloc!;
    grid.onTileClicked = (position) {
      if (_active && !bloc.isClosed) bloc.add(TileClicked(position));
    };
    _stateSubscription = bloc.stream.listen((state) {
      if (_active) _renderState(state);
    });
    _renderState(bloc.state);
    installRuntimeShutdownHook(getTree()!.getRoot()!);
    GD.print(Variant('[AppRoot] Grid and palette ready.'));
  }

  void _renderState(IsomapGridState state) {
    _grid?.render(state);
    _menu?.setEnabled(state.selected != null);
  }

  @override
  void vExitTree() {
    _active = false;
    _grid?.onTileClicked = null;
    _grid = null;
    _menu = null;
    final subscription = _stateSubscription;
    _stateSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final bloc = _bloc;
    _bloc = null;
    if (_ownsBloc && bloc != null) unawaited(bloc.close());
  }

  @GodotExport()
  void onMenuItemChosen(String kind) {
    final resourceKind = resourceKindFromCode(kind);
    if (resourceKind == null) {
      GD.pushWarning(Variant('[AppRoot] Unknown resource kind: $kind'));
      return;
    }
    final bloc = _bloc;
    if (_active && bloc != null && !bloc.isClosed) {
      bloc.add(PlaceResource(resourceKind));
    }
  }
}
