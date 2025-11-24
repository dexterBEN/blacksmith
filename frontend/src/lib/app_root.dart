import 'dart:ffi';
import 'package:godot_dart/godot_dart.dart';

// DI
import 'package:blacksmith_front/core/di/service_locator.dart' as di;

// Godot nodes


// BLoC
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_state.dart';

import 'isomap_grid.dart';
import 'menu_overlay.dart';

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
  AppRoot.withNonNullOwner(Pointer<Void> owner)
      : super.withNonNullOwner(owner);

  late final IsoMapGrid _grid;
  late final MenuOverlay _menu;

  IsomapGridBloc? _bloc;

  @override
  void vReady() {
    _grid = getNodeT<IsoMapGrid>('IsoMapGrid')!;
    _menu = getNodeT<MenuOverlay>('MenuOverlay')!;

    GD.print(Variant('[AppRoot] vReady OK (grid + menu trouvés)'));

    // 🔹 1) S’assurer que le DI est initialisé dans CET isolate
    if (!di.sl.isRegistered<IsomapGridBloc>()) {
      GD.print(
        Variant('[AppRoot] DI non initialisé dans cet isolate -> setupServiceLocator()'),
      );
      // pas besoin de `await`, le corps de setupServiceLocator est sync
      di.setupServiceLocator();
    }

    // 🔹 2) Récupérer le BLoC via GetIt
    if (di.sl.isRegistered<IsomapGridBloc>()) {
      _bloc = di.sl<IsomapGridBloc>();
      GD.print(Variant('[AppRoot] BLoC trouvé via DI'));

      // on écoute le stream pour redessiner la grille
      _bloc!.stream.listen((IsomapGridState state) {
        _grid.render(state);
      });

      // rendu initial
      _grid.render(_bloc!.state);
    } else {
      GD.pushWarning(
        Variant('[AppRoot] Toujours pas de BLoC après setup -> mode fallback'),
      );
    }

    _menu.setEnabled(true);
  }


  @GodotExport()
  void onMenuItemChosen(String kind) {
    GD.print(Variant('[AppRoot] onMenuItemChosen: $kind'));

    String? path;
    switch (kind) {
      case 'gcp:cloud_storage':
        path = 'res://src/assets/gcp_cloud_storage.png';
        break;
      case 'gcp:compute_engine':
        path = 'res://src/assets/gcp_compute_engine.png';
        break;
    }

    if (path == null) {
      GD.pushWarning(
        Variant('[AppRoot] unknown resource kind: $kind'),
      );
      return;
    }

    if (_bloc != null) {
      _bloc!.add(PlaceResource(path));
      return;
    }

    GD.pushWarning(Variant('[AppRoot] Pas de BLoC -> fallback direct map'));
    _grid.placeIconOnSelected(path);
  }
}

