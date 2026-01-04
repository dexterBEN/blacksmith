import 'package:get_it/get_it.dart';

import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';

import 'package:blacksmith_front/data/services/cloud_services_api.dart';
import 'package:blacksmith_front/data/services/resources_api.dart';

import 'package:blacksmith_front/data/repositories/cloud_storage_repository.dart';
import 'package:blacksmith_front/data/repositories/resources_repository.dart';

/// Service locator
final sl = GetIt.instance;

/// Register all dependencies once on setup
Future<void> setupServiceLocator({int rows = 6, int cols = 6}) async {
  // ============================
  // Services (HTTP APIs)
  // ============================

  if (!sl.isRegistered<CloudServicesApi>()) {
    sl.registerLazySingleton<CloudServicesApi>(
      () => CloudServicesApi(
        baseUrl: 'http://localhost:5256',
      ),
    );
  }

  if (!sl.isRegistered<ResourcesApi>()) {
    sl.registerLazySingleton<ResourcesApi>(
      () => ResourcesApi(
        baseUrl: 'http://localhost:5256',
      ),
    );
  }

  // ============================
  // Repositories
  // ============================

  if (!sl.isRegistered<CloudStorageRepository>()) {
    sl.registerLazySingleton<CloudStorageRepository>(
      () => CloudStorageRepository(
        sl<CloudServicesApi>(),
      ),
    );
  }

  if (!sl.isRegistered<ResourcesRepository>()) {
    sl.registerLazySingleton<ResourcesRepository>(
      () => ResourcesRepositoryImpl(
        sl<ResourcesApi>(),
      ),
    );
  }

  // ============================
  // BLoC
  // ============================

  if (!sl.isRegistered<IsomapGridBloc>()) {
    sl.registerLazySingleton<IsomapGridBloc>(
      () => IsomapGridBloc(
        rows: rows,
        cols: cols,
        cloudStorageRepository: sl<CloudStorageRepository>(),
        resourcesRepository: sl<ResourcesRepository>(),
      ),
    );
  }

  // if (!sl.isRegistered<MenuBloc>()) {
  //   sl.registerLazySingleton<MenuBloc>(() => MenuBloc());
  // }
}

/// Dispose everything properly
Future<void> disposeServiceLocator() async {
  if (sl.isRegistered<IsomapGridBloc>()) {
    await sl<IsomapGridBloc>().close();
  }

  // if (sl.isRegistered<MenuBloc>()) {
  //   await sl<MenuBloc>().close();
  // }

  await sl.reset();
}