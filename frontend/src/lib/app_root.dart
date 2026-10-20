import 'dart:async';
import 'dart:ffi';
import 'package:godot_dart/godot_dart.dart';

import 'core/di/service_locator.dart' as di;
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
  IsomapGridBloc? _bloc;
  StreamSubscription<IsomapGridState>? _stateSubscription;
  bool _active = false;
  bool _ownsBloc = false;
  int? _lastReportedAttempt;
  static bool _shutdownHookInstalled = false;

  @override
  void vReady() {
    _active = true;
    final grid = getNodeT<IsoMapGrid>('IsoMapGrid')!;
    final menu = getNodeT<MenuOverlay>('MenuOverlay')!;
    _grid = grid;

    try {
      if (!di.sl.isRegistered<IsomapGridBloc>()) di.setupServiceLocator();
      _bloc = di.sl<IsomapGridBloc>();
    } catch (_) {
      // Preserve the old local-only diagnostic behavior with the same logical
      // state machine. This instance has no repository or network client.
      _bloc = IsomapGridBloc.local();
      _ownsBloc = true;
      GD.pushWarning(Variant(
        '[AppRoot] Local diagnostic mode: cloud operations are disabled.',
      ));
    }

    final bloc = _bloc!;
    grid.onTileClicked = (position) {
      if (_active && !bloc.isClosed) bloc.add(TileClicked(position));
    };
    _lastReportedAttempt = bloc.state.lastResult?.attemptId;
    _stateSubscription = bloc.stream.listen((state) {
      if (_active) _renderState(state);
    });
    grid.render(bloc.state);
    menu.setEnabled(true);
    _installShutdownHook();
    GD.print(Variant('[AppRoot] Grid and palette ready.'));
  }

  void _renderState(IsomapGridState state) {
    _grid?.render(state);
    final result = state.lastResult;
    if (result == null || result.attemptId == _lastReportedAttempt) return;
    _lastReportedAttempt = result.attemptId;
    final position = result.position;
    final message = result.message;
    if (result.status == PlacementStatus.success) {
      GD.print(Variant('[AppRoot] Bucket creation at $position: $message'));
    } else {
      GD.pushWarning(Variant(
        '[AppRoot] Bucket creation at $position failed: $message',
      ));
    }
  }

  void _installShutdownHook() {
    final window = getTree()?.getRoot();
    if (_shutdownHookInstalled || window == null) return;
    // The root window outlives individual scenes. This callback captures no
    // scene instance; shared resources are disposed only on runtime exit.
    window.treeExiting.connect(window, () {
      unawaited(di.disposeServiceLocator());
    });
    _shutdownHookInstalled = true;
  }

  @override
  void vExitTree() {
    _active = false;
    _grid?.onTileClicked = null;
    _grid = null;
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
