import 'package:get_it/get_it.dart';

import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';

/// Service locator
final sl = GetIt.instance;

//register all dependency once on setup
Future<void> setupServiceLocator({int rows = 6, int cols = 6}) async {
  // IsomapGridBloc
  if (!sl.isRegistered<IsomapGridBloc>()) {
    sl.registerLazySingleton<IsomapGridBloc>(
      () => IsomapGridBloc(rows: rows, cols: cols),
    );
  }

  // if (!sl.isRegistered<MenuBloc>()) {
  //   sl.registerLazySingleton<MenuBloc>(() => MenuBloc());
  // }
}


Future<void> disposeServiceLocator() async {
  if (sl.isRegistered<IsomapGridBloc>()) {
    await sl<IsomapGridBloc>().close();
  }
  // if (sl.isRegistered<MenuBloc>()) {
  //   await sl<MenuBloc>().close();
  // }
  await sl.reset();
}