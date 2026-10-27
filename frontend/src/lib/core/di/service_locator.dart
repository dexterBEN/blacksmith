import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import '../../domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../../domain/bloc/isomap_grid/isomap_grid_state.dart';
import '../../data/services/cloud_services_api.dart';
import '../../data/repositories/cloud_storage_repository.dart';
import '../../data/repositories/design_repository.dart';
import '../../data/repositories/resource_repository.dart';
import '../../domain/bloc/design/design_cubit.dart';

final sl = GetIt.instance;
const defaultBackendUrl = 'http://localhost:5100';
const defaultGcpProjectId = 'isometric-app-sample';

/// Register once per isolate. Configuration applies when instances are created;
/// calling setup again does not replace an existing runtime or its state.
void setupServiceLocator({
  int rows = IsomapGridState.defaultRows,
  int cols = IsomapGridState.defaultCols,
  String baseUrl = defaultBackendUrl,
  String projectId = defaultGcpProjectId,
  http.Client? httpClient,
  http.Client? designHttpClient,
  http.Client? resourceHttpClient,
  String? deploymentToken,
}) {
  if (!sl.isRegistered<CloudServicesApi>()) {
    sl.registerLazySingleton<CloudServicesApi>(
      () => CloudServicesApi(baseUrl: baseUrl, client: httpClient),
      dispose: (api) => api.close(),
    );
  }
  if (!sl.isRegistered<CloudStorageRepository>()) {
    sl.registerLazySingleton<CloudStorageRepository>(
      () =>
          CloudStorageRepository(sl<CloudServicesApi>(), projectId: projectId),
    );
  }
  if (!sl.isRegistered<IsomapGridBloc>()) {
    sl.registerLazySingleton<IsomapGridBloc>(
      () => IsomapGridBloc(
        rows: rows,
        cols: cols,
      ),
      dispose: (bloc) => bloc.close(),
    );
  }
  if (!sl.isRegistered<DesignRepository>()) {
    sl.registerLazySingleton<DesignRepository>(
      () => DesignRepository(baseUrl: baseUrl, client: designHttpClient),
      dispose: (repository) => repository.close(),
    );
  }
  if (!sl.isRegistered<ResourceRepository>()) {
    sl.registerLazySingleton<ResourceRepository>(
      () => ResourceRepository(
          baseUrl: baseUrl,
          client: resourceHttpClient,
          deploymentToken: deploymentToken),
      dispose: (repository) => repository.close(),
    );
  }
  if (!sl.isRegistered<DesignCubit>()) {
    sl.registerLazySingleton<DesignCubit>(
      () => DesignCubit(sl<DesignRepository>(), sl<IsomapGridBloc>(),
          resources: sl<ResourceRepository>()),
      dispose: (cubit) => cubit.close(),
    );
  }
}

Future<void> disposeServiceLocator() async {
  // Dispose created singletons in reverse order without instantiating unused
  // lazy registrations. Scene exit cancels only that scene's subscription.
  await sl.reset();
}
